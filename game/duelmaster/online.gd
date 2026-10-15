extends Node
## The online half of duelmaster: the pool, challenges, and one match at a time, all over
## net.gd (Firebase Realtime Database, polled -- no SDK). See GAME.md, "Online".
##
## What lives in the database:
##   pool/<uid>            {name, best_of, seen}          -- you, while you wait in the pool
##   invites/<to>/<from>   {mid, name, best_of}           -- a challenge waiting for an answer
##   matches/<mid>         {host, guest, names, best_of, status,
##                          rounds/r<n> {kind, seed},     -- the host deals every duel
##                          res/r<n>/<role> {err, said},  -- each side's result
##                          done/r<n>/<role> true,        -- each side has seen the verdict
##                          ping/<role>, left/<role>}
##
## Nobody's phone clock is trusted. Pool heartbeats are stamped by the database itself and
## compared with our own; an opponent is "alive" while their match ping keeps CHANGING, as
## seen by this device's own clock. Two phones with different times still agree.
## Polling, not streaming: a duel only needs a handful of messages, and plain requests
## behave the same in a browser, on desktop and in a headless test.

signal pool_changed(players: Array)       ## [{uid, name, best_of}], everyone but you
signal invited(inv: Dictionary)           ## {from, name, best_of, mid}, or {} when it goes
signal declined(name: String)
signal match_started(info: Dictionary)    ## {host: bool, opp: name, best_of}
signal round_ready(n: int, kind: int, seed: int)
signal opp_result(n: int, err: float, said: String)
signal both_done(n: int)
signal opp_left
signal trouble(msg: String)

const Net := preload("res://game/duelmaster/net.gd")

const BEAT := 3.0                 ## heartbeat, seconds
const POLL_POOL := 1.2
const POLL_MATCH := 0.7
const STALE := 11.0               ## a pool heartbeat unchanged this long means they left
const GONE := 20.0                ## an opponent silent this long forfeits
const ASK_FOR := 30.0             ## a challenge nobody answers lapses

var net: Node
var my_name := ""
var best_of := 3
var state := "off"                ## off joining pool asking match
var players: Array = []
var invite := {}

var _seen := {}                   ## uid -> [last heartbeat, when it changed]: the fallback
var _invite_seen := {}            ## "<from>/<mid>" -> when we first saw it
var _ask_to := ""
var _ask_name := ""
var _ask_since := 0.0
var _mid := ""
var _role := ""
var _opp_role := ""
var _opp_ping: Variant = null
var _opp_ping_at := 0.0
var _rounds_told := 0
var _results_told := {}
var _done_told := {}
var _left_told := false
var _next := {}                   ## timer name -> when it is next due
var _busy := {}                   ## request kind -> in flight

func _ready() -> void:
	net = Net.new()
	add_child(net)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _due(what: String, every: float) -> bool:
	if _busy.get(what, false) or _now() < _next.get(what, 0.0):
		return false
	_next[what] = _now() + every
	return true

func _process(_d: float) -> void:
	match state:
		"pool", "asking":
			if _due("beat", BEAT):
				_beat()
			if _due("pool", POLL_POOL):
				_poll_pool()
			if state == "asking":
				if _due("ask", POLL_MATCH):
					_poll_ask()
				if _now() - _ask_since > ASK_FOR:
					cancel_challenge()
					declined.emit(_ask_name)
		"match":
			if _due("ping", BEAT):
				net.req("PATCH", "matches/%s/ping" % _mid, {_role: Net.now_stamp()})
			if _due("match", POLL_MATCH):
				_poll_match()

## ---- the pool ---------------------------------------------------------------

func join(name: String, n: int) -> bool:
	my_name = name
	best_of = n
	state = "joining"
	if net.uid == "" and not await net.sign_in():
		state = "off"
		trouble.emit("could not sign in")
		return false
	var r: Dictionary = await net.req("PUT", "pool/" + net.uid,
		{"name": my_name, "best_of": best_of, "seen": Net.now_stamp()})
	if not r.ok:
		state = "off"
		trouble.emit("could not reach the server")
		return false
	state = "pool"
	_next.clear()
	return true

func _beat() -> void:
	_busy["beat"] = true
	await net.req("PATCH", "pool/" + net.uid, {"seen": Net.now_stamp()})
	_busy["beat"] = false

func _poll_pool() -> void:
	_busy["pool"] = true
	var r: Dictionary = await net.req("GET", "pool")
	var inv: Dictionary = await net.req("GET", "invites/" + net.uid)
	_busy["pool"] = false
	if state != "pool" and state != "asking":
		return
	var now := _now()
	var alive: Array = []
	var all: Dictionary = r.data if r.data is Dictionary else {}
	# Our own heartbeat was stamped by the same database clock as everyone else's, so
	# comparing against it needs no trust in anybody's phone clock.
	var mine: Variant = all[net.uid].get("seen") if all.get(net.uid) is Dictionary else null
	for uid in all:
		var p: Variant = all[uid]
		if uid == net.uid or not (p is Dictionary):
			continue
		var beat: Variant = p.get("seen")
		var fresh := false
		if (mine is float or mine is int) and (beat is float or beat is int):
			fresh = float(mine) - float(beat) < STALE * 1000.0
		else:
			# no stamps to compare: fall back to "has it changed lately", by our own clock
			var was: Array = _seen.get(uid, [null, now])
			if was[0] != beat:
				was = [beat, now]
			_seen[uid] = was
			fresh = now - float(was[1]) < STALE
		if fresh:
			alive.append({"uid": uid, "name": str(p.get("name", "?")),
				"best_of": int(p.get("best_of", 3))})
	alive.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	if JSON.stringify(alive) != JSON.stringify(players):
		players = alive
		pool_changed.emit(players)
	_take_invites(inv.data if inv.data is Dictionary else {}, alive)

func _take_invites(all: Dictionary, alive: Array) -> void:
	var now := _now()
	var live_uids := alive.map(func(p): return p.uid)
	var best := {}
	for from in all:
		var i: Variant = all[from]
		if not (i is Dictionary) or not live_uids.has(from):
			continue
		var tag := "%s/%s" % [from, i.get("mid", "")]
		if not _invite_seen.has(tag):
			_invite_seen[tag] = now
		if now - float(_invite_seen[tag]) > ASK_FOR:
			continue
		best = {"from": from, "name": str(i.get("name", "?")),
			"best_of": int(i.get("best_of", 3)), "mid": str(i.get("mid", ""))}
	# Both tapped each other at once: the smaller id's challenge stands, the other side
	# drops its own and takes it -- they both wanted this match anyway.
	if not best.is_empty() and state == "asking" and best.from == _ask_to:
		if net.uid < best.from:
			return
		await cancel_challenge()
		accept(best)
		return
	if JSON.stringify(best) != JSON.stringify(invite):
		invite = best
		invited.emit(invite)

## ---- challenges ---------------------------------------------------------------

func challenge(p: Dictionary) -> void:
	if state != "pool":
		return
	state = "asking"
	_ask_to = p.uid
	_ask_name = p.name
	_ask_since = _now()
	_mid = "%s-%s" % [net.uid, Net.random_id(3)]
	# kept locally: a crossed challenge can cancel this one while these requests are out
	var to: String = p.uid
	var mid := _mid
	await net.req("PUT", "matches/" + mid, {
		"host": net.uid, "guest": to, "best_of": best_of, "status": "pending",
		"names": {"host": my_name, "guest": p.name}})
	await net.req("PUT", "invites/%s/%s" % [to, net.uid],
		{"mid": mid, "name": my_name, "best_of": best_of})
	if state != "asking" or _mid != mid:
		# cancelled before the invite landed: take it back so it does not linger
		await net.req("DELETE", "invites/%s/%s" % [to, net.uid])

func cancel_challenge() -> void:
	if state != "asking":
		return
	state = "pool"
	var mid := _mid
	var to := _ask_to
	_ask_to = ""
	await net.req("PATCH", "matches/" + mid, {"status": "cancelled"})
	await net.req("DELETE", "invites/%s/%s" % [to, net.uid])

func _poll_ask() -> void:
	_busy["ask"] = true
	var r: Dictionary = await net.req("GET", "matches/%s/status" % _mid)
	_busy["ask"] = false
	if state != "asking":
		return
	match r.data:
		"on":
			_start_match(true, _ask_name)
		"declined":
			state = "pool"
			_ask_to = ""
			declined.emit(_ask_name)

func accept(inv: Dictionary) -> void:
	if state == "asking":
		await cancel_challenge()
	var r: Dictionary = await net.req("GET", "matches/%s/status" % inv.mid)
	await net.req("DELETE", "invites/%s/%s" % [net.uid, inv.from])
	if r.data != "pending":
		invite = {}
		invited.emit(invite)
		trouble.emit("that challenge is gone")
		return
	await net.req("PATCH", "matches/" + inv.mid, {"status": "on"})
	_mid = inv.mid
	best_of = inv.best_of             ## the challenger's N
	_start_match(false, inv.name)

func decline(inv: Dictionary) -> void:
	invite = {}
	invited.emit(invite)
	await net.req("PATCH", "matches/" + inv.mid, {"status": "declined"})
	await net.req("DELETE", "invites/%s/%s" % [net.uid, inv.from])

## ---- the match ------------------------------------------------------------------

func _start_match(host: bool, opp: String) -> void:
	state = "match"
	_role = "host" if host else "guest"
	_opp_role = "guest" if host else "host"
	_opp_ping = null
	_opp_ping_at = _now()
	_rounds_told = 0
	_results_told.clear()
	_done_told.clear()
	_left_told = false
	invite = {}
	_next.clear()
	net.req("DELETE", "pool/" + net.uid)      ## out of the pool while busy
	match_started.emit({"host": host, "opp": opp, "best_of": best_of})

func is_host() -> bool:
	return _role == "host"

## Host only: deal duel n.
func open_round(n: int, kind: int, seed: int) -> void:
	_put_hard("matches/%s/rounds/r%d" % [_mid, n], {"kind": kind, "seed": seed})

func post_result(n: int, err: float, said: String) -> void:
	_put_hard("matches/%s/res/r%d/%s" % [_mid, n, _role], {"err": err, "said": said})

func post_done(n: int) -> void:
	_put_hard("matches/%s/done/r%d/%s" % [_mid, n, _role], true)

## The writes the match cannot go on without get a few tries.
func _put_hard(path: String, body: Variant) -> void:
	for i in 4:
		var r: Dictionary = await net.req("PUT", path, body)
		if r.ok or state != "match":
			return
		await get_tree().create_timer(0.5 * (i + 1)).timeout

func _poll_match() -> void:
	_busy["match"] = true
	var r: Dictionary = await net.req("GET", "matches/" + _mid)
	_busy["match"] = false
	if state != "match":
		return
	var now := _now()
	if not r.ok or not (r.data is Dictionary):
		if now - _opp_ping_at > GONE:
			_lost_them()
		return
	var m: Dictionary = r.data
	var ping: Variant = m.get("ping", {}).get(_opp_role) if m.get("ping") is Dictionary else null
	if ping != _opp_ping:
		_opp_ping = ping
		_opp_ping_at = now
	if (m.get("left") is Dictionary and m.left.has(_opp_role)) or now - _opp_ping_at > GONE:
		_lost_them()
		return
	var rounds: Dictionary = m.get("rounds") if m.get("rounds") is Dictionary else {}
	while rounds.has("r%d" % (_rounds_told + 1)):
		_rounds_told += 1
		var rd: Dictionary = rounds["r%d" % _rounds_told]
		round_ready.emit(_rounds_told, int(rd.kind), int(rd.seed))
	var res: Dictionary = m.get("res") if m.get("res") is Dictionary else {}
	for key in res:
		var n := int(str(key).substr(1))
		var mine: Variant = res[key]
		if mine is Dictionary and mine.has(_opp_role) and not _results_told.has(n):
			_results_told[n] = true
			var o: Dictionary = mine[_opp_role]
			opp_result.emit(n, float(o.err), str(o.said))
	var done: Dictionary = m.get("done") if m.get("done") is Dictionary else {}
	for key in done:
		var n := int(str(key).substr(1))
		var d: Variant = done[key]
		if d is Dictionary and d.has("host") and d.has("guest") and not _done_told.has(n):
			_done_told[n] = true
			both_done.emit(n)

func _lost_them() -> void:
	if _left_told:
		return
	_left_told = true
	opp_left.emit()

## The set is over: stop talking about it.
func end_match() -> void:
	if state == "match":
		state = "off"

## Leaving for good (back, menu, or closing the game). Best effort: the requests are sent
## from a node parked on the root so they outlive this game's scene.
func leave() -> void:
	var was := state
	state = "off"
	if net.uid == "":
		return
	var bye: Array = [["DELETE", "pool/" + net.uid, null]]
	if was == "asking":
		bye.append(["PATCH", "matches/" + _mid, {"status": "cancelled"}])
		bye.append(["DELETE", "invites/%s/%s" % [_ask_to, net.uid], null])
	elif was == "match":
		bye.append(["PATCH", "matches/%s/left" % _mid, {_role: true}])
	net.courier(bye)
