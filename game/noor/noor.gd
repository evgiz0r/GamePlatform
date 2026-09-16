extends GameMode
## noor -- a two-player, turn-based strategy game on a square map. See GAME.md.
## Each side has cities; every land square belongs to whichever city is closest on foot,
## so taking a city takes its whole land with it. Cities make warriors, warriors walk two
## squares a turn and hit whatever they stand next to. Take every rival city to win.
##
## Tap a warrior, tap where it should go (or which enemy it should hit). "end turn" or
## Shift/K passes the turn; "auto" or Space has the advisor play your turn. The rival is
## the same advisor. A thirty-second clock ends a turn nobody finishes.

const COLS := 20
const ROWS := 9
const TILE := 30.0
const ORIGIN := Vector2(20, 42)

const UNIT_HP := 10
const UNIT_ATK := 6
const UNIT_RETALIATE := 3
const CITY_SHIELD := 2
const HEAL := 3
const MOVES := 2
const PROD_TURNS := 2
const TURN_SECONDS := 30.0
const AI_STEP := 0.16                       ## seconds between the advisor's moves, fewer with a big army
const STEP_TWEEN := 0.09                    ## how long one square of walking takes

## The shell default (0.8) is loud for a game that clanks every second or two. Scaled in
## memory only while noor is on screen -- the saved settings file is never touched.
const SFX_SCALE := 0.35
const MUSIC_SCALE := 0.45
const MUSIC_TRACK := "on_the_offensive"

const P1 := 0                               ## you
const P2 := 1                               ## the rival
const NEUTRAL := 2                          ## the middle cities and their guards
const ROLE_OF := ["player", "hazard", "ink"]
const UNIT_SPRITE := ["guard", "goblin", "skeleton"]
## What the playtest eye sees: "@" your cities, "E" the rival's, "N" neutral ones,
## "o" your warriors, "x" anything that can hurt you, "~" water.
const CITY_SYM := ["@", "E", "N"]
const UNIT_SYM := ["o", "x", "x"]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FAR := 9999

var _land: Array = []                       ## bool per square
var _bound: Array = []                      ## city index per square, -1 for water
var _cities: Array = []                     ## {pos, owner, prod, node}
var _units: Array = []                      ## {id, owner, pos, hp, mp, moved, done, node}
var _next_id := 1

var _side := P1
var _turn := 0
var _clock := TURN_SECONDS
var _turn_seconds := TURN_SECONDS
var _acting_ai := false                     ## the advisor is moving a side right now
var _ai_side := P2
var _step_t := 0.0
var _ai_step := AI_STEP
var _busy := false                          ## a walk tween is playing
var _busy_t := 0.0                          ## a hit animation is playing
var _t := 0.0

var _sel: Dictionary = {}                   ## the unit you picked up, or empty
var _reach: Dictionary = {}                 ## Vector2i -> cost
var _reach_from: Dictionary = {}            ## Vector2i -> the square before it
var _attackable: Dictionary = {}            ## enemy square -> square to hit from

var _over: Node2D                           ## health bars, drawn above the pieces
var _end_btn: Button
var _auto_btn: Button
var _sfx_was := 0.8
var _music_was := 0.7

func _ready() -> void:
	title = "noor"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_music_was = float(SaveData.data.get("volume_music", 0.7))
	SaveData.data["volume_music"] = _music_was * MUSIC_SCALE

	# Bots cannot read a clock, so a playtest may shorten it: an idle player then loses
	# inside a minute instead of inside ten.
	var forced := OS.get_environment("NOOR_TURN_SECONDS")
	if forced.is_valid_float() and float(forced) > 0.0:
		_turn_seconds = float(forced)

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	_over = Node2D.new()
	_over.z_index = 1
	_over.draw.connect(_draw_over)
	add_child(_over)

	_build_map()
	for ci in _cities.size():
		_make_city_node(ci)
		_spawn_unit(_cities[ci]["owner"], _cities[ci]["pos"])
	_bind_land()
	for y in ROWS:
		for x in COLS:
			if not _land[_idx(Vector2i(x, y))]:
				var w := Node2D.new()
				add_child(w)
				w.position = _centre(Vector2i(x, y))
				Probe.track(w, "~")

	# Text and buttons live in a CanvasLayer above the shell's HUD (10), otherwise Flow's
	# full-screen Control takes the click first and the button is decorative.
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_auto_btn = UIKit.button("auto", _auto_turn)
	_auto_btn.custom_minimum_size = Vector2(84, 28)
	_auto_btn.size = Vector2(84, 28)
	_auto_btn.position = Vector2(402, 322)
	_auto_btn.add_theme_font_size_override("font_size", 13)
	layer.add_child(_auto_btn)
	_end_btn = UIKit.button("end turn", _end_turn)
	_end_btn.custom_minimum_size = Vector2(122, 28)
	_end_btn.size = Vector2(122, 28)
	_end_btn.position = Vector2(498, 322)
	_end_btn.add_theme_font_size_override("font_size", 13)
	layer.add_child(_end_btn)

	set_lives(_count_cities(P1))
	_begin_turn(P1)
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	SaveData.data["volume_music"] = _music_was
	Audio.stop_music()

## ---- the map ----------------------------------------------------------------
## Mirrored left-right so both sides get the same start. Your three cities on the left,
## the rival's are their reflections, and a neutral pair sits in the middle.

func _build_map() -> void:
	for attempt in 30:
		_land.clear()
		_land.resize(COLS * ROWS)
		_land.fill(true)
		_cities.clear()
		var mine: Array = [
			Vector2i(2, 4 + randi_range(-1, 1)),
			Vector2i(randi_range(4, 6), randi_range(0, 1)),
			Vector2i(randi_range(4, 6), randi_range(7, 8)),
		]
		for p in mine:
			_cities.append({"pos": p, "owner": P1, "prod": PROD_TURNS, "node": null})
		for p in mine:
			_cities.append({"pos": _mirror(p), "owner": P2, "prod": PROD_TURNS, "node": null})
		var mid := Vector2i(randi_range(8, 9), randi_range(1, 7))
		_cities.append({"pos": mid, "owner": NEUTRAL, "prod": PROD_TURNS, "node": null})
		_cities.append({"pos": _mirror(mid), "owner": NEUTRAL, "prod": PROD_TURNS, "node": null})

		# a few lakes, grown from a seed, kept a square away from any city
		for k in 3:
			var seed_c := Vector2i(randi_range(1, 8), randi_range(0, ROWS - 1))
			if _near_city(seed_c):
				continue
			var lake: Array = [seed_c]
			var want := randi_range(2, 4)
			var tries := 0
			while lake.size() < want and tries < 20:
				tries += 1
				var from: Vector2i = lake[randi() % lake.size()]
				var n: Vector2i = from + DIRS[randi() % 4]
				if _inside(n) and n.x <= 9 and not lake.has(n) and not _near_city(n):
					lake.append(n)
			for c in lake:
				_land[_idx(c)] = false
				_land[_idx(_mirror(c))] = false
		if _flood_count(_cities[0]["pos"]) == _land.count(true):
			return
	# thirty tries and still cut in two: play on dry land instead
	_land.fill(true)

func _mirror(c: Vector2i) -> Vector2i:
	return Vector2i(COLS - 1 - c.x, c.y)

func _near_city(c: Vector2i) -> bool:
	for city in _cities:
		var d: Vector2i = (city["pos"] as Vector2i) - c
		if absi(d.x) <= 1 and absi(d.y) <= 1:
			return true
	return false

func _flood_count(from: Vector2i) -> int:
	var seen := {}
	seen[from] = true
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in DIRS:
			var n: Vector2i = c + d
			if _is_land(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size()

## Every land square goes to the city closest on foot. Re-run whenever that could have
## changed -- it never does after the start, since cities do not move, but ownership is
## read through the city so a capture needs no rebinding at all.
func _bind_land() -> void:
	_bound.clear()
	_bound.resize(COLS * ROWS)
	_bound.fill(-1)
	var queue: Array = []
	for ci in _cities.size():
		var p: Vector2i = _cities[ci]["pos"]
		_bound[_idx(p)] = ci
		queue.append(p)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var ci: int = _bound[_idx(c)]
		for d in DIRS:
			var n: Vector2i = c + d
			if _is_land(n) and _bound[_idx(n)] < 0:
				_bound[_idx(n)] = ci
				queue.append(n)

## ---- grid helpers -------------------------------------------------------------

func _idx(c: Vector2i) -> int:
	return c.y * COLS + c.x

func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS

func _is_land(c: Vector2i) -> bool:
	return _inside(c) and _land[_idx(c)]

func _tile_owner(c: Vector2i) -> int:
	if not _is_land(c):
		return -1
	var b: int = _bound[_idx(c)]
	return -1 if b < 0 else _cities[b]["owner"]

func _city_at(c: Vector2i) -> int:
	for ci in _cities.size():
		if _cities[ci]["pos"] == c:
			return ci
	return -1

func _unit_at(c: Vector2i) -> Dictionary:
	for u in _units:
		if u["pos"] == c:
			return u
	return {}

func _centre(c: Vector2i) -> Vector2:
	return ORIGIN + (Vector2(c) + Vector2(0.5, 0.5)) * TILE

func _rect(c: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(c) * TILE, Vector2(TILE, TILE))

func _cell_of(p: Vector2) -> Vector2i:
	var rel := (p - ORIGIN) / TILE
	return Vector2i(int(floorf(rel.x)), int(floorf(rel.y)))

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _count_cities(owner: int) -> int:
	var n := 0
	for c in _cities:
		if c["owner"] == owner:
			n += 1
	return n

func _count_tiles(owner: int) -> int:
	var n := 0
	for i in _bound.size():
		var b: int = _bound[i]
		if b >= 0 and _cities[b]["owner"] == owner:
			n += 1
	return n

## ---- cities and units --------------------------------------------------------

## The banner on a city is remade whenever the city changes hands: Probe tracks a node
## under one symbol for life, so a new owner means a new node with a new symbol.
func _make_city_node(ci: int) -> void:
	var c: Dictionary = _cities[ci]
	if c["node"] != null and is_instance_valid(c["node"]):
		c["node"].queue_free()
	var b := Blob.new()
	b.role = ROLE_OF[c["owner"]]
	b.set_sprite("banner", 1.1)
	b.glow = c["owner"] != NEUTRAL
	add_child(b)
	b.position = _centre(c["pos"]) + Vector2(8, -8)
	c["node"] = b
	Probe.track(b, CITY_SYM[c["owner"]])
	Juice.pop(b, 1.5)

func _spawn_unit(owner: int, c: Vector2i) -> Dictionary:
	var b := Blob.new()
	b.role = ROLE_OF[owner]
	b.set_sprite(UNIT_SPRITE[owner], 1.4)
	b.glow = owner != NEUTRAL
	b.flip_h = owner == P2
	add_child(b)
	b.position = _centre(c)
	var u := {"id": _next_id, "owner": owner, "pos": c, "hp": UNIT_HP, "mp": 0,
		"moved": false, "done": false, "node": b}
	_next_id += 1
	_units.append(u)
	Probe.track(b, UNIT_SYM[owner])
	Juice.pop(b, 1.4)
	return u

func _remove_unit(u: Dictionary) -> void:
	var b: Blob = u["node"]
	if is_instance_valid(b):
		var tw := b.create_tween()
		tw.tween_property(b, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(b.queue_free)
	if not _sel.is_empty() and _sel["id"] == u["id"]:
		_deselect()
	for i in _units.size():
		if _units[i]["id"] == u["id"]:
			_units.remove_at(i)
			return

## ---- turns ----------------------------------------------------------------------

func _begin_turn(side: int) -> void:
	if finished:
		return
	_side = side
	_deselect()
	if side == P1:
		_turn += 1
		Probe.event("turn", {"turn": _turn, "tiles": "%d:%d" % [_count_tiles(P1), _count_tiles(P2)],
			"units": "%d:%d" % [_count_units(P1), _count_units(P2)]})
		if _turn % 5 == 0:
			Probe.capture("turn %d" % _turn)
	# rest heals, but only at home
	for u in _units:
		if u["owner"] == side and not u["moved"] and u["hp"] < UNIT_HP and _tile_owner(u["pos"]) == u["owner"]:
			u["hp"] = mini(UNIT_HP, u["hp"] + HEAL)
			Juice.text(self, u["node"].position + Vector2(-6, -14), "+%d" % HEAL, Palette.col("friend"))
		if u["owner"] == side:
			u["mp"] = MOVES
			u["moved"] = false
			u["done"] = false
	# cities make a warrior every few turns, into an empty city only
	for c in _cities:
		if c["owner"] != side:
			continue
		c["prod"] -= 1
		if c["prod"] <= 0:
			if _unit_at(c["pos"]).is_empty():
				var u := _spawn_unit(side, c["pos"])
				u["mp"] = MOVES
				c["prod"] = PROD_TURNS
				Probe.event("unit_made", {"side": side})
				if side == P1:
					Audio.play("pickup", 0.05, -4.0)
			else:
				c["prod"] = 0
	if side == P1:
		_clock = _turn_seconds
		Audio.play("select", 0.05, -6.0)
	else:
		_start_ai(P2)

func _end_turn() -> void:
	if finished or _acting_ai or _is_busy() or _side != P1:
		return
	Probe.event("end_turn", {"turn": _turn})
	Audio.play("click", 0.05, -6.0)
	_begin_turn(P2)

func _auto_turn() -> void:
	if finished or _acting_ai or _is_busy() or _side != P1:
		return
	Probe.event("auto_turn", {"turn": _turn})
	_start_ai(P1)

func _start_ai(side: int) -> void:
	_deselect()
	_acting_ai = true
	_ai_side = side
	_step_t = 0.3
	_ai_step = clampf(2.4 / maxf(1.0, float(_count_units(side))), 0.07, AI_STEP)
	for u in _units:
		u["done"] = false

func _finish_ai() -> void:
	_acting_ai = false
	if finished:
		return
	if _ai_side == P1:
		Probe.event("end_turn", {"turn": _turn, "auto": true})
	_begin_turn(P2 if _ai_side == P1 else P1)

func _alive(u: Dictionary) -> bool:
	for v in _units:
		if v["id"] == u["id"]:
			return true
	return false

func _is_busy() -> bool:
	return _busy or _busy_t > 0.0

func _count_units(owner: int) -> int:
	var n := 0
	for u in _units:
		if u["owner"] == owner:
			n += 1
	return n

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	_over.queue_redraw()
	_t += delta
	# Audio.music() no-ops while the track is still playing, so calling it every frame
	# only ever restarts it once the clip ends -- the cheap way to loop a real track.
	Audio.music(MUSIC_TRACK)
	if _busy_t > 0.0:
		_busy_t -= delta

	if _acting_ai:
		if _is_busy():
			return
		_step_t -= delta
		if _step_t > 0.0:
			return
		var u := _next_ai_unit()
		if u.is_empty():
			_finish_ai()
			return
		_ai_act(u)
		_step_t = _ai_step
		return

	if _side != P1 or _is_busy():
		return
	if PInput.just_pressed("action_a"):
		_auto_turn()
	elif PInput.just_pressed("action_b"):
		_end_turn()
	else:
		_clock -= delta
		if _clock <= 0.0:
			Probe.event("turn_timeout", {"turn": _turn})
			Audio.play("thud", 0.05, -6.0)
			_begin_turn(P2)

## ---- the advisor (rival brain and "auto" button alike) ------------------------------
## One action per call so the moves are watchable: hit whatever is adjacent, hold a
## threatened home city, otherwise walk one square toward the nearest city that is not
## ours.

## Front to back: the warrior nearest a target moves first, so the ones behind it find
## the square ahead already empty instead of giving up on a jam.
func _next_ai_unit() -> Dictionary:
	var field := _dist_field(_ai_side)
	var best: Dictionary = {}
	var best_d := FAR + 1
	for u in _units:
		if u["owner"] == _ai_side and u["mp"] > 0 and not u["done"]:
			var d: int = field[_idx(u["pos"])]
			if d < best_d:
				best_d = d
				best = u
	return best

func _ai_act(u: Dictionary) -> void:
	var s: int = u["owner"]
	var pos: Vector2i = u["pos"]

	var target: Dictionary = {}
	for d in DIRS:
		var e := _unit_at(pos + d)
		if not e.is_empty() and e["owner"] != s:
			if target.is_empty() or e["hp"] < target["hp"]:
				target = e
	if not target.is_empty():
		# do not trade a last sliver of health for a hit that does not finish the job
		if u["hp"] > UNIT_RETALIATE or _damage_to(target) >= target["hp"]:
			_attack(u, target)
			return

	# too hurt to trade blows: get back onto our own land and rest there
	if u["hp"] <= UNIT_RETALIATE:
		if _tile_owner(pos) == s:
			u["mp"] = 0
			u["done"] = true
			return
		if not _step_down(u, _home_field(s)):
			u["done"] = true
		return

	var ci := _city_at(pos)
	if ci >= 0 and _cities[ci]["owner"] == s and _threat_near(pos, s, 3):
		u["mp"] = 0
		u["done"] = true
		return

	if not _step_down(u, _dist_field(s)):
		u["done"] = true

## One square toward wherever `field` gets smaller. When the way down is blocked, a
## sideways step onto an equal square keeps the column flowing round the jam. False if
## every way is blocked.
func _step_down(u: Dictionary, field: PackedInt32Array) -> bool:
	var pos: Vector2i = u["pos"]
	var here: int = field[_idx(pos)]
	var best := Vector2i(-1, -1)
	var best_d := here + 1
	var sideways: Array = []
	for d in DIRS:
		var n: Vector2i = pos + d
		if not _is_land(n) or not _unit_at(n).is_empty():
			continue
		var nd: int = field[_idx(n)]
		if nd < best_d:
			best_d = nd
			best = n
		elif nd == here:
			sideways.append(n)
	if best.x < 0 and not sideways.is_empty() and u["mp"] > 1:
		best = sideways[randi() % sideways.size()]
	if best.x < 0:
		return false
	_step_to(u, best)
	return true

## Squares to the nearest city not owned by `s`, walking over land, ignoring units.
func _dist_field(s: int) -> PackedInt32Array:
	var sources: Array = []
	for c in _cities:
		if c["owner"] != s:
			sources.append(c["pos"])
	return _bfs_field(sources)

## Squares to the nearest land owned by `s`.
func _home_field(s: int) -> PackedInt32Array:
	var sources: Array = []
	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			if _tile_owner(c) == s:
				sources.append(c)
	return _bfs_field(sources)

func _bfs_field(sources: Array) -> PackedInt32Array:
	var field := PackedInt32Array()
	field.resize(COLS * ROWS)
	field.fill(FAR)
	var queue: Array = []
	for p in sources:
		field[_idx(p)] = 0
		queue.append(p)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var dist: int = field[_idx(c)]
		for d in DIRS:
			var n: Vector2i = c + d
			if _is_land(n) and field[_idx(n)] == FAR:
				field[_idx(n)] = dist + 1
				queue.append(n)
	return field

func _threat_near(pos: Vector2i, s: int, radius: int) -> bool:
	for u in _units:
		if u["owner"] != s and u["owner"] != NEUTRAL and _manhattan(u["pos"], pos) <= radius:
			return true
	return false

## ---- moving and fighting ------------------------------------------------------------

## One square, animated. Walking into a city that is not ours takes it and ends the move.
func _step_to(u: Dictionary, dest: Vector2i) -> void:
	var from: Vector2i = u["pos"]
	u["pos"] = dest
	u["mp"] -= 1
	u["moved"] = true
	var b: Blob = u["node"]
	if dest.x != from.x:
		b.flip_h = dest.x < from.x
	var tw := b.create_tween()
	tw.tween_property(b, "position", _centre(dest), STEP_TWEEN)
	Audio.play("step", 0.12, -8.0)
	Probe.event("unit_moved", {"side": u["owner"]})
	var ci := _city_at(dest)
	if ci >= 0 and _cities[ci]["owner"] != u["owner"]:
		u["mp"] = 0
		_capture(ci, u["owner"])

func _damage_to(d: Dictionary) -> int:
	var dmg := UNIT_ATK
	var ci := _city_at(d["pos"])
	if ci >= 0 and _cities[ci]["owner"] == d["owner"]:
		dmg -= CITY_SHIELD
	return dmg

func _attack(a: Dictionary, d: Dictionary) -> void:
	var dmg := _damage_to(d)
	a["mp"] = 0
	a["moved"] = true
	a["done"] = true
	var an: Blob = a["node"]
	var dn: Blob = d["node"]
	var home := _centre(a["pos"])
	var tw := an.create_tween()
	tw.tween_property(an, "position", home.lerp(dn.position, 0.45), 0.07)
	tw.tween_property(an, "position", home, 0.09)
	_busy_t = 0.18
	d["hp"] -= dmg
	Juice.flash(dn, Palette.col("hazard") if d["owner"] == P1 else Color.WHITE)
	Juice.text(self, dn.position + Vector2(-8, -16), "-%d" % dmg, Palette.col("warn"))
	Juice.shake(3.0)
	Audio.play("impact_punch", 0.1, -2.0)
	Probe.event("attack", {"by": a["owner"], "dmg": dmg})
	if d["hp"] <= 0:
		_kill(d, a["owner"])
		return
	a["hp"] -= UNIT_RETALIATE
	Juice.text(self, an.position + Vector2(-8, -16), "-%d" % UNIT_RETALIATE, Palette.col("ink"))
	if a["hp"] <= 0:
		_kill(a, d["owner"])

func _kill(u: Dictionary, by: int) -> void:
	Probe.event("unit_killed", {"side": u["owner"], "by": by})
	Audio.play("explode", 0.1, -6.0)
	Juice.hit(5.0)
	if by == P1 and u["owner"] != P1:
		add_score(10)
		Juice.text(self, u["node"].position + Vector2(-10, -28), "+10", Palette.col("prize"))
	_remove_unit(u)

func _capture(ci: int, new_owner: int) -> void:
	var c: Dictionary = _cities[ci]
	var old: int = c["owner"]
	c["owner"] = new_owner
	c["prod"] = PROD_TURNS
	_make_city_node(ci)
	var at := _centre(c["pos"])
	if new_owner == P1:
		add_score(100 if old == P2 else 50)
		Juice.hit(8.0)
		Audio.play("voice_objective_achieved")
		Juice.text(self, at + Vector2(-34, -30), "city taken!", Palette.col("warn"))
	elif old == P1:
		Juice.hit(8.0)
		Audio.play("hurt")
		Juice.text(self, at + Vector2(-30, -30), "city lost", Palette.col("hazard"))
	else:
		Juice.shake(4.0)
		Audio.play("impact_bell", 0.05, -6.0)
	set_lives(_count_cities(P1))
	Probe.event("city_captured", {"by": new_owner, "from": old, "turn": _turn})
	_check_end()

func _check_end() -> void:
	if finished:
		return
	if _count_cities(P1) == 0:
		Probe.event("defeat", {"turn": _turn})
		Audio.play("voice_you_lose")
		lose()
	elif _count_cities(P2) == 0:
		Probe.event("victory", {"turn": _turn})
		add_score(500)
		Audio.play("voice_you_win")
		win()

## ---- your orders ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if finished or _side != P1 or _acting_ai or _is_busy():
		return
	if Flow.pointer_over_hud():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	# _input runs before the GUI, so without this a tap on a button also lands on the map
	if _end_btn.get_global_rect().has_point(mb.position) or _auto_btn.get_global_rect().has_point(mb.position):
		return
	var c := _cell_of(get_global_mouse_position())
	if not _inside(c):
		_deselect()
		return
	_tap(c)

func _tap(c: Vector2i) -> void:
	if not _sel.is_empty():
		if _reach.has(c):
			_order_move(_sel, c, Callable())
			return
		if _attackable.has(c):
			var target := _unit_at(c)
			var from: Vector2i = _attackable[c]
			var me := _sel
			if from == me["pos"]:
				_attack(me, target)
				_deselect()
			else:
				_order_move(me, from, func(): _attack(me, target))
			return
	var u := _unit_at(c)
	if not u.is_empty() and u["owner"] == P1 and u["mp"] > 0:
		_select(u)
		return
	_deselect()

func _select(u: Dictionary) -> void:
	_sel = u
	_compute_reach(u)
	Juice.pop(u["node"], 1.25)
	Audio.play("select", 0.06, -4.0)

func _deselect() -> void:
	_sel = {}
	_reach.clear()
	_reach_from.clear()
	_attackable.clear()

## Where this warrior can walk this turn, and which enemies it can reach a swing at.
## Nothing walks through anyone; a city that is not ours is a dead end (walking in
## takes it and stops you there).
func _compute_reach(u: Dictionary) -> void:
	_reach.clear()
	_reach_from.clear()
	_attackable.clear()
	var start: Vector2i = u["pos"]
	var mp: int = u["mp"]
	var cost := {}
	cost[start] = 0
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var here: int = cost[c]
		if here + 1 <= mp:
			var enters_foreign_city := false
			var ci := _city_at(c)
			if c != start and ci >= 0 and _cities[ci]["owner"] != u["owner"]:
				enters_foreign_city = true
			if not enters_foreign_city:
				for d in DIRS:
					var n: Vector2i = c + d
					if _is_land(n) and not cost.has(n) and _unit_at(n).is_empty():
						cost[n] = here + 1
						_reach[n] = here + 1
						_reach_from[n] = c
						queue.append(n)
	for c in cost:
		if cost[c] + 1 > mp:
			continue
		for d in DIRS:
			var e := _unit_at(c + d)
			if not e.is_empty() and e["owner"] != u["owner"]:
				var n: Vector2i = c + d
				if not _attackable.has(n) or cost[_attackable[n]] > cost[c]:
					_attackable[n] = c

## Walk a picked-up warrior along its path one square at a time, then maybe do
## something on arrival. Input is off until the walk is over.
func _order_move(u: Dictionary, dest: Vector2i, then: Callable) -> void:
	var path: Array = []
	var c := dest
	var start: Vector2i = u["pos"]
	while c != start:
		path.push_front(c)
		c = _reach_from[c]
	_deselect()
	if path.is_empty():
		if then.is_valid():
			then.call()
		return
	_busy = true
	_walk(u, path, 0, then)

func _walk(u: Dictionary, path: Array, i: int, then: Callable) -> void:
	if finished or i >= path.size() or u["mp"] <= 0:
		_busy = false
		if not finished and then.is_valid() and u["hp"] > 0:
			then.call()
		elif not finished and u["mp"] > 0 and _alive(u):
			_select(u)
		return
	_step_to(u, path[i])
	var tw := create_tween()
	tw.tween_interval(STEP_TWEEN)
	tw.tween_callback(_walk.bind(u, path, i + 1, then))

## ---- the screen --------------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")
	var warn := Palette.col("warn")
	var hazard := Palette.col("hazard")

	for y in ROWS:
		for x in COLS:
			var c := Vector2i(x, y)
			var r := _rect(c)
			if not _land[_idx(c)]:
				draw_rect(r, Palette.col("bg_alt"))
				var w := Color(ink, 0.14)
				draw_line(r.position + Vector2(5, 11), r.position + Vector2(13, 11), w, 1.0)
				draw_line(r.position + Vector2(15, 20), r.position + Vector2(24, 20), w, 1.0)
				continue
			var o := _tile_owner(c)
			var col := ink if o < 0 or o == NEUTRAL else Palette.col(ROLE_OF[o])
			draw_rect(r.grow(-1.0), Color(col, 0.05 if o == NEUTRAL or o < 0 else 0.17))
			draw_rect(r, Color(ink, 0.05), false, 1.0)
			# a bright line wherever the land changes hands
			for d in DIRS:
				var n: Vector2i = c + d
				var no := _tile_owner(n) if _is_land(n) else -2
				if no != o:
					var e := _edge(r, d)
					draw_line(e[0], e[1], Color(col, 0.85 if o < NEUTRAL else 0.3), 2.0)

	for ci in _cities.size():
		var c: Dictionary = _cities[ci]
		var r := _rect(c["pos"])
		var col: Color = Palette.col(ROLE_OF[c["owner"]])
		var pulse := 0.3 + 0.08 * sin(_t * 3.0 + ci)
		draw_rect(r.grow(-2.0), Color(col, pulse))
		draw_rect(r.grow(-2.0), col, false, 2.0)
		if c["owner"] != NEUTRAL:
			var lit: int = PROD_TURNS - c["prod"]
			for i in PROD_TURNS:
				var p := r.position + Vector2(5 + i * 6, TILE - 5)
				draw_circle(p, 2.0, Color(col, 0.95 if i < lit else 0.3))

	if not _sel.is_empty():
		for c in _reach:
			draw_rect(_rect(c).grow(-3.0), Color(warn, 0.22))
			draw_rect(_rect(c).grow(-3.0), Color(warn, 0.5), false, 1.0)
		for c in _attackable:
			draw_rect(_rect(c).grow(-2.0), Color(hazard, 0.6 + 0.35 * sin(_t * 9.0)), false, 2.0)
		draw_rect(_rect(_sel["pos"]).grow(-1.0), warn, false, 2.0)

	# the clock, then who is doing what
	var bar := Rect2(ORIGIN.x, ORIGIN.y + ROWS * TILE + 4, COLS * TILE, 4)
	draw_rect(bar, Palette.col("bg_alt"))
	if _side == P1 and not _acting_ai:
		var frac := clampf(_clock / _turn_seconds, 0.0, 1.0)
		var role := "friend" if frac > 0.5 else ("warn" if frac > 0.2 else "hazard")
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Palette.col(role))
	var msg := ""
	if _acting_ai:
		msg = "turn %d   your advisor is moving..." % _turn if _ai_side == P1 else "turn %d   the rival is moving..." % _turn
	else:
		msg = "turn %d   your move" % _turn
	draw_string(f, Vector2(ORIGIN.x, 342), msg, HORIZONTAL_ALIGNMENT_LEFT, 260, 13, Palette.col("accent"))
	draw_string(f, Vector2(280, 342), "land %d : %d" % [_count_tiles(P1), _count_tiles(P2)],
		HORIZONTAL_ALIGNMENT_LEFT, 120, 13, ink)

## Health bars and the "still has moves" pip sit above the sprites, not under them.
func _draw_over() -> void:
	for u in _units:
		var b: Blob = u["node"]
		if not is_instance_valid(b):
			continue
		var col: Color = Palette.col(ROLE_OF[u["owner"]])
		var p: Vector2 = b.position
		_over.draw_rect(Rect2(p + Vector2(-9, 11), Vector2(18, 3)), Color(0, 0, 0, 0.6))
		_over.draw_rect(Rect2(p + Vector2(-9, 11), Vector2(18.0 * float(u["hp"]) / float(UNIT_HP), 3)), col)
		if _side == P1 and not _acting_ai and u["owner"] == P1 and u["mp"] > 0:
			_over.draw_circle(p + Vector2(-11, -11), 2.5, Color(Palette.col("prize"), 0.6 + 0.4 * sin(_t * 6.0)))

func _edge(r: Rect2, d: Vector2i) -> Array:
	if d.x > 0:
		return [r.position + Vector2(r.size.x - 1, 0), r.position + Vector2(r.size.x - 1, r.size.y)]
	if d.x < 0:
		return [r.position + Vector2(1, 0), r.position + Vector2(1, r.size.y)]
	if d.y > 0:
		return [r.position + Vector2(0, r.size.y - 1), r.position + Vector2(r.size.x, r.size.y - 1)]
	return [r.position + Vector2(0, 1), r.position + Vector2(r.size.x, 1)]
