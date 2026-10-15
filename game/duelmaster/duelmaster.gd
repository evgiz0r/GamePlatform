extends GameMode
## duelmaster -- two players, best of N. See GAME.md.
## Duel after duel comes up at random. Both players play the SAME setup (the duel is
## rebuilt from one seed), the smaller error wins, close enough is a draw. First to more
## than half of N takes the set.
##
## Two ways to play:
##   same device -- BLUE and PINK take turns on one screen, passing it between turns.
##   online      -- a name, a pool of who is online, challenge + accept, then both play
##                  each duel at the same time on their own device (online.gd), synced
##                  every round: nobody starts the next duel until both saw the verdict.
##
## Each duel lives in duels/ and is "seed in, number out" -- that is the whole interface,
## and it is all online play sends between two phones.

const Online := preload("res://game/duelmaster/online.gd")
const DUELS := [
	preload("res://game/duelmaster/duels/marble.gd"),
	preload("res://game/duelmaster/duels/slice.gd"),
	preload("res://game/duelmaster/duels/clock.gd"),
	preload("res://game/duelmaster/duels/curling.gd"),
]
const ROLES := ["player", "hazard"]
const BEST_OF := [1, 3, 5, 7]
const COUNT_TIME := 0.9           ## "GO" beat before a turn, so the start tap is not an action
const RESULT_TIME := 1.4          ## the turn's result stays up this long
const VERDICT_TIME := 3.2
const CHAMPION_TIME := 3.6
const INTRO_TIME := 2.2           ## online: the duel's name and hint, before GO
const SAVE_PATH := "user://duelmaster.cfg"
const NAME_MAX := 12
## The shell default (0.8) is loud for a game that beeps every few seconds. Memory only,
## restored on exit. See CLAUDE.md, "things this kit learned the hard way".
const SFX_SCALE := 0.35

var best_of := 3
var _online := false
var _names := ["BLUE", "PINK"]    ## online: [you, them]
var _need := 2
var _wins := [0, 0]
var _duel_no := 0
var _bag: Array = []              ## shuffled duel indices still to come this cycle
var _kind := -1                   ## index into DUELS for the duel being played
var _seed := 0
var _first := 0                   ## same device: who opens this duel; alternates
var _turn := 0                    ## same device: 0 = first player's turn, 1 = second's
var _results := [0.0, 0.0]        ## by player, not by turn order
var _said := ["", ""]             ## the same results as words ("12 px off")
var _have := [false, false]       ## online: which results are in for this duel
var _duel: Node2D = null
var _info: Node2D = null          ## a bare instance of the duel, for its title, hint and tie
var _verdict := ""
var _verdict_role := "ink"
## same device: mode -> pick -> ready -> count -> turn -> result -> ready (other player)
##   -> count -> turn -> result -> verdict -> ready (next duel) ... -> champion -> win()
## online: mode -> login -> joining -> pool -> wait -> intro -> count -> turn -> result
##   -> (wait_opp) -> verdict -> wait -> intro ... -> champion -> win() / lose()
var _phase := "mode"
var _phase_left := 0.0
var _layer: CanvasLayer
var _pulse := 0.0
var _sfx_was := 0.8

var _net: Node = null             ## online.gd, while online
var _name_edit: LineEdit = null
var _pending_round := {}          ## a round the host dealt before we were ready for it
var _note := ""                   ## one line of news under the pool ("Dana said no")
var _note_left := 0.0

func _ready() -> void:
	title = "duelmaster"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()
	set_lives(0)                  ## no lives in a duel; hides the shell's stars
	# The bots only press buttons once they can see a player, and between turns there is
	# no actor on screen -- this marker stands in for "whoever is about to tap".
	var me := Node2D.new()
	add_child(me)
	me.position = center()
	Probe.track(me, "@")
	# Buttons live in a CanvasLayer above the shell's HUD, otherwise Flow's full-screen
	# Control takes the click and the button is decorative. (Same as checkers.)
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	Probe.event("boot")
	# "play again" comes back to where you were: the same N on one device, the pool online.
	# DUELMASTER_ONLINE=1 starts straight in online mode, for testing two copies at once.
	if config.get("online", false) or OS.get_environment("DUELMASTER_ONLINE") == "1":
		_show_login()
	elif config.has("best_of"):
		_begin_set(int(config["best_of"]))
	else:
		_show_mode()

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	if _info != null and is_instance_valid(_info):
		_info.free()
	if _net != null:
		_net.leave()

## ---- buttons ----------------------------------------------------------------

func _ui_clear() -> void:
	for c in _layer.get_children():
		c.queue_free()
	_name_edit = null

func _button(text: String, pos: Vector2, size: Vector2, cb: Callable, font := 15) -> Button:
	var b := UIKit.button(text, cb)
	b.custom_minimum_size = size
	b.size = size
	b.position = pos
	b.add_theme_font_size_override("font_size", font)
	_layer.add_child(b)
	return b

## ---- screens before a set -----------------------------------------------------

func _show_mode() -> void:
	_phase = "mode"
	_online = false
	_ui_clear()
	_button("same device", Vector2(130, 196), Vector2(180, 50), _show_picker, 17)
	_button("online", Vector2(330, 196), Vector2(180, 50), _show_login, 17)

func _show_picker() -> void:
	_phase = "pick"
	_ui_clear()
	for i in BEST_OF.size():
		var n: int = BEST_OF[i]
		_button("best of %d" % n, Vector2(56 + i * 136, 196), Vector2(124, 46), _begin_set.bind(n), 16)
	_button("back", Vector2(270, 290), Vector2(100, 30), _show_mode, 13)

func _begin_set(n: int) -> void:
	_ui_clear()
	_online = false
	_names = ["BLUE", "PINK"]
	best_of = n
	Flow.current_config = {"best_of": n}
	_reset_set()
	_first = randi() % 2
	Audio.play("voice_go")
	Probe.event("set_start", {"best_of": n, "online": false})
	_next_duel()

func _reset_set() -> void:
	_need = best_of / 2 + 1
	_wins = [0, 0]
	_duel_no = 0
	_bag.clear()
	_kind = -1

## ---- same device --------------------------------------------------------------

func _next_duel() -> void:
	_duel_no += 1
	_kind = _deal()
	_seed = randi()
	_first = 1 - _first if _duel_no > 1 else _first
	_turn = 0
	_set_info()
	Probe.event("duel_start", {"n": _duel_no, "duel": _info.title, "first": _names[_first]})
	_enter_ready()

## Next duel off a shuffled bag, never the same one twice running.
func _deal() -> int:
	if _bag.is_empty():
		for i in DUELS.size():
			_bag.append(i)
		_bag.shuffle()
		if _bag.size() > 1 and _bag[0] == _kind:
			_bag.append(_bag.pop_front())
	return _bag.pop_front()

func _set_info() -> void:
	_results = [0.0, 0.0]
	_said = ["", ""]
	_have = [false, false]
	if _info != null and is_instance_valid(_info):
		_info.free()
	_info = DUELS[_kind].new()    ## never built or added; it only answers title/hint/tie

func _player() -> int:
	if _online:
		return 0                  ## online you only ever play your own turn
	return _first if _turn == 0 else 1 - _first

func _enter_ready() -> void:
	_phase = "ready"
	Audio.play("open")

func _begin_turn() -> void:
	_phase = "count"
	# a slightly different beat every turn, so nobody can tap on a rhythm
	_phase_left = COUNT_TIME * randf_range(0.75, 1.4)
	_duel = DUELS[_kind].new()
	add_child(_duel)
	_duel.setup(_seed, ROLES[_player()])
	_duel.done.connect(_on_turn_done)
	Audio.play("select")

func _on_turn_done(err: float) -> void:
	var p := _player()
	_results[p] = err
	_said[p] = _duel.describe(err)
	_have[p] = true
	Probe.event("turn_done", {"who": _names[p], "err": snappedf(minf(err, 9999.0), 0.01)})
	if _online:
		_net.post_result(_duel_no, err, _said[p])
	_phase = "result"
	_phase_left = RESULT_TIME

func _after_result() -> void:
	if _duel != null and is_instance_valid(_duel):
		_duel.queue_free()
	_duel = null
	if _online:
		if _have[1]:
			_judge()
		else:
			_phase = "wait_opp"
		return
	if _turn == 0:
		_turn = 1
		_enter_ready()
		return
	_judge()

func _judge() -> void:
	var a: float = _results[0]
	var b: float = _results[1]
	var both_miss: bool = a >= _info.MISS and b >= _info.MISS
	if both_miss or absf(a - b) <= _info.tie:
		_verdict = "DRAW"
		_verdict_role = "ink"
		Audio.play("impact_metal")
		Probe.event("duel_draw")
	else:
		var w := 0 if a < b else 1
		_wins[w] += 1
		add_score(1)
		_verdict = "%s WINS THE DUEL" % _names[w].to_upper()
		_verdict_role = ROLES[w]
		Juice.hit(6.0)
		Audio.play("voice_correct")
		Probe.event("duel_won", {"who": _names[w], "score": "%d-%d" % [_wins[0], _wins[1]]})
	_phase = "verdict"
	_phase_left = VERDICT_TIME
	if _duel_no % 3 == 1:
		Probe.capture("duel %d" % _duel_no)

func _after_verdict() -> void:
	if _online:
		_net.post_done(_duel_no)
	for i in 2:
		if _wins[i] >= _need:
			_crown(i, "%s IS THE DUELMASTER" % _names[i].to_upper())
			return
	if _online:
		_phase = "wait"
		_take_pending_round()
	else:
		_next_duel()

func _crown(i: int, msg: String) -> void:
	_phase = "champion"
	_phase_left = CHAMPION_TIME
	_verdict = msg
	_verdict_role = ROLES[i]
	Juice.hit(10.0)
	Audio.play("voice_congratulations" if i == 0 or not _online else "voice_game_over")
	Probe.event("set_won", {"who": _names[i], "score": "%d-%d" % [_wins[0], _wins[1]]})
	if _online:
		_net.end_match()

## ---- online: login and the pool -----------------------------------------------

func _load_profile() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return {"name": "", "best_of": 3}
	return {"name": str(cf.get_value("online", "name", "")),
		"best_of": int(cf.get_value("online", "best_of", 3))}

func _save_profile(name: String, n: int) -> void:
	var cf := ConfigFile.new()
	cf.set_value("online", "name", name)
	cf.set_value("online", "best_of", n)
	cf.save(SAVE_PATH)

func _show_login() -> void:
	_phase = "login"
	_online = true
	Flow.current_config = {"online": true}
	_ui_clear()
	var prof := _load_profile()
	best_of = int(prof.best_of)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "your name"
	_name_edit.text = prof.name
	_name_edit.max_length = NAME_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.position = Vector2(220, 128)
	_name_edit.size = Vector2(200, 36)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.text_submitted.connect(func(_t): _join())
	_layer.add_child(_name_edit)
	for i in BEST_OF.size():
		var n: int = BEST_OF[i]
		var b := _button("best of %d" % n, Vector2(80 + i * 124, 206), Vector2(112, 34),
			_pick_n.bind(n), 14)
		b.toggle_mode = true
		b.button_pressed = n == best_of
		# the chosen N has to read as chosen: filled, in your colour
		var on := StyleBoxFlat.new()
		on.bg_color = Palette.col(ROLES[0]).darkened(0.55)
		on.border_color = Palette.col(ROLES[0])
		on.set_border_width_all(3)
		on.set_corner_radius_all(4)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.set_meta("n", n)
	_button("enter", Vector2(250, 262), Vector2(140, 38), _join, 17)
	_button("back", Vector2(270, 314), Vector2(100, 28), _back_to_mode, 13)

func _pick_n(n: int) -> void:
	best_of = n
	for c in _layer.get_children():
		if c is Button and c.has_meta("n"):
			c.button_pressed = c.get_meta("n") == n

func _back_to_mode() -> void:
	if _net != null:
		_net.leave()
		_net.queue_free()
		_net = null
	_show_mode()

func _join() -> void:
	if _phase != "login":
		return
	var name := _name_edit.text.strip_edges() if _name_edit != null else ""
	if name == "":
		name = "guest-" + Online.Net.random_id(2)
	name = name.substr(0, NAME_MAX)
	_save_profile(name, best_of)
	_names = [name, "?"]
	_phase = "joining"
	_ui_clear()
	if _net == null:
		_net = Online.new()
		add_child(_net)
		_net.pool_changed.connect(func(_p): _show_pool())
		_net.invited.connect(func(_i): _show_pool())
		_net.declined.connect(_on_declined)
		_net.trouble.connect(_on_trouble)
		_net.match_started.connect(_on_match_started)
		_net.round_ready.connect(_on_round_ready)
		_net.opp_result.connect(_on_opp_result)
		_net.both_done.connect(_on_both_done)
		_net.opp_left.connect(_on_opp_left)
	if await _net.join(name, best_of):
		Probe.event("joined_pool", {"name": name})
		_show_pool()
	else:
		_show_login()

func _on_trouble(msg: String) -> void:
	_say(msg)
	Audio.play("hurt")

func _on_declined(who: String) -> void:
	_say("%s said no" % who)
	_show_pool()

func _say(msg: String) -> void:
	_note = msg
	_note_left = 4.0

func _show_pool() -> void:
	if _net == null or (_net.state != "pool" and _net.state != "asking"):
		return
	_phase = "pool"
	_ui_clear()
	var inv: Dictionary = _net.invite
	if not inv.is_empty():
		_button("accept", Vector2(196, 238), Vector2(116, 38), _accept, 16)
		_button("no thanks", Vector2(328, 238), Vector2(116, 38), _decline, 15)
		return
	if _net.state == "asking":
		_button("cancel", Vector2(270, 238), Vector2(100, 34), func(): _net.cancel_challenge(); _show_pool(), 14)
		return
	var shown: Array = _net.players.slice(0, 10)
	for i in shown.size():
		var p: Dictionary = shown[i]
		# one column up to five people, two columns past that
		var x := 200.0
		var row := i
		if shown.size() > 5:
			x = 70.0 + (i % 2) * 260.0
			row = i / 2
		var b := _button("%s  ·  best of %d" % [p.name, p.best_of], Vector2(x, 112 + row * 42),
			Vector2(240, 34), _challenge.bind(p), 14)
		b.add_theme_color_override("font_color", Palette.col("hazard"))
	_button("back", Vector2(270, 326), Vector2(100, 26), _back_to_mode, 12)

func _challenge(p: Dictionary) -> void:
	Audio.play("select")
	Probe.event("challenge", {"to": p.name})
	await _net.challenge(p)
	_show_pool()

func _accept() -> void:
	if _net.invite.is_empty():
		return
	Probe.event("accept", {"from": _net.invite.name})
	_net.accept(_net.invite)

func _decline() -> void:
	if not _net.invite.is_empty():
		_net.decline(_net.invite)

## ---- online: the match ----------------------------------------------------------

func _on_match_started(info: Dictionary) -> void:
	_ui_clear()
	_names = [_names[0], str(info.opp)]
	best_of = int(info.best_of)
	_reset_set()
	_pending_round = {}
	Audio.play("voice_go")
	Probe.event("set_start", {"best_of": best_of, "online": true, "vs": info.opp,
		"host": info.host})
	_phase = "wait"
	if info.host:
		_host_deal(1)

func _host_deal(n: int) -> void:
	_kind = _deal()
	_net.open_round(n, _kind, randi())

func _on_round_ready(n: int, kind: int, seed: int) -> void:
	_pending_round = {"n": n, "kind": kind, "seed": seed}
	if _phase == "wait":
		_take_pending_round()

func _take_pending_round() -> void:
	if _pending_round.is_empty() or int(_pending_round.n) != _duel_no + 1:
		return
	_duel_no = int(_pending_round.n)
	_kind = int(_pending_round.kind)
	_seed = int(_pending_round.seed)
	_pending_round = {}
	_set_info()
	Probe.event("duel_start", {"n": _duel_no, "duel": _info.title})
	_phase = "intro"
	_phase_left = INTRO_TIME
	Audio.play("open")

func _on_opp_result(n: int, err: float, said: String) -> void:
	if n != _duel_no:
		return
	_results[1] = err
	_said[1] = said
	_have[1] = true
	if _phase == "wait_opp":
		_judge()

## Host only: both have seen duel n's verdict, so deal duel n+1 (unless the set is over).
func _on_both_done(n: int) -> void:
	if not _net.is_host() or n != _duel_no or _phase == "champion":
		return
	if _wins[0] >= _need or _wins[1] >= _need:
		return
	_host_deal(n + 1)

func _on_opp_left() -> void:
	if _phase == "champion" or finished or not _online:
		return
	if _duel != null and is_instance_valid(_duel):
		_duel.queue_free()
	_duel = null
	_wins[0] = maxi(_wins[0], _need)
	_crown(0, "%s LEFT -- YOU WIN" % _names[1].to_upper())

## ---- input ----------------------------------------------------------------
## Mouse and finger are the main way in; space (action_a) does the same thing so the
## keyboard and the playtest bots can play too.

func _input(event: InputEvent) -> void:
	if finished or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if Flow.pointer_over_hud():
			return
		_on_press()
	else:
		_on_release()

func _on_press() -> void:
	match _phase:
		"ready":
			_begin_turn()
		"turn":
			_duel.press()
		"verdict":
			if VERDICT_TIME - _phase_left > 0.8:     ## not the same tap that ended the turn
				_after_verdict()

func _on_release() -> void:
	if _phase == "turn" and _duel != null:
		_duel.release()

## The action button on the screens that are otherwise buttons only: it takes the obvious
## choice, so a keyboard (and a bot) can get through them.
func _action_shortcut() -> void:
	match _phase:
		"mode":
			_show_picker()
		"pick":
			_begin_set(3)
		"login":
			if _name_edit == null or not _name_edit.has_focus():
				_join()
		"pool":
			if not _net.invite.is_empty():
				_accept()
			elif _net.state == "pool" and not _net.players.is_empty():
				_challenge(_net.players[0])

func _process(delta: float) -> void:
	if finished:
		return
	_pulse += delta
	_note_left = maxf(0.0, _note_left - delta)
	queue_redraw()
	if PInput.just_pressed("action_a"):
		if _phase in ["mode", "pick", "login", "pool"]:
			_action_shortcut()
		else:
			_on_press()
	if PInput.just_released("action_a"):
		_on_release()

	match _phase:
		"intro":
			_phase_left -= delta
			if _phase_left <= 0.0:
				_begin_turn()
		"count":
			_phase_left -= delta
			if _phase_left <= 0.0:
				_phase = "turn"
		"turn":
			_duel.advance(delta)
		"result":
			_duel.advance(delta)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_after_result()
		"verdict":
			_phase_left -= delta
			if _phase_left <= 0.0:
				_after_verdict()
		"champion":
			_phase_left -= delta
			if _phase_left <= 0.0:
				if _wins[0] >= _need or not _online:
					win()
				else:
					lose()

## ---- the screen ---------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")
	var dim := Palette.col("bg_alt").lightened(0.4)
	match _phase:
		"mode":
			_text(f, 320, 110, "DUELMASTER", 34, Palette.col("accent"))
			_text(f, 320, 146, "best of N, one duel at a time. closest wins.", 13, ink)
			_text(f, 320, 176, "how are you playing?", 14, Palette.col("warn"))
			return
		"pick":
			_text(f, 320, 110, "SAME DEVICE", 28, Palette.col("accent"))
			_text(f, 320, 146, "take turns, pass the phone between them.", 13, ink)
			_text(f, 320, 176, "how many duels?", 14, Palette.col("warn"))
			return
		"login":
			_text(f, 320, 84, "ONLINE", 28, Palette.col("accent"))
			_text(f, 320, 114, "your name", 12, dim)
			_text(f, 320, 196, "if somebody challenges you, you play this many:", 12, ink)
			_note_line(f)
			return
		"joining":
			_text(f, 320, 180, "connecting" + ".".repeat(int(_pulse * 3.0) % 4), 18, ink)
			return
		"pool":
			_draw_pool(f)
			return
	_scoreboard(f)
	match _phase:
		"ready":
			var p := _player()
			var col := Palette.col(ROLES[p])
			_text(f, 320, 104, "DUEL %d  ·  %s" % [_duel_no, _info.title], 15, Palette.col("accent"))
			_text(f, 320, 156, "%s, YOUR TURN" % _names[p], 30, col)
			_text(f, 320, 190, _info.hint, 14, ink)
			if _turn == 1:
				var o := 1 - p
				_text(f, 320, 226, "%s: %s  -- beat that" % [_names[o], _said[o]],
					14, Palette.col(ROLES[o]))
			else:
				_text(f, 320, 226, "same setup for both of you", 12, dim)
			var a := 0.55 + 0.45 * sin(_pulse * 4.0)
			_text(f, 320, 290, "tap when ready", 16, Color(col.r, col.g, col.b, a))
		"wait":
			_text(f, 320, 170, "waiting for %s" % _names[1] + ".".repeat(int(_pulse * 3.0) % 4),
				16, ink)
		"intro":
			_text(f, 320, 104, "DUEL %d" % _duel_no, 15, Palette.col("accent"))
			_text(f, 320, 156, _info.title, 30, Palette.col(ROLES[0]))
			_text(f, 320, 190, _info.hint, 14, ink)
			_text(f, 320, 226, "%s is playing this one right now too" % _names[1], 12, dim)
			var k := ceili(_phase_left)
			_text(f, 320, 290, str(k), 24, Palette.col("warn"))
		"count":
			_text(f, 320, 70, "%s  ·  GO" % _names[_player()], 14, Palette.col(ROLES[_player()]))
		"turn":
			_text(f, 320, 70, "%s  ·  %s" % [_names[_player()], _info.hint], 12, Palette.col(ROLES[_player()]))
		"result":
			_text(f, 320, 74, _said[_player()], 22, Palette.col(ROLES[_player()]))
		"wait_opp":
			_text(f, 320, 150, "you: %s" % _said[0], 18, Palette.col(ROLES[0]))
			_text(f, 320, 196, "waiting for %s" % _names[1] + ".".repeat(int(_pulse * 3.0) % 4),
				16, ink)
		"verdict":
			for i in 2:
				var x := 190.0 if i == 0 else 450.0
				var c := Palette.col(ROLES[i])
				_text(f, x, 150, _names[i], 20, c)
				_text(f, x, 182, _said[i], 18, c)
			_text(f, 320, 110, _info.title, 14, Palette.col("accent"))
			_text(f, 320, 250, _verdict, 26, Palette.col(_verdict_role))
			if VERDICT_TIME - _phase_left > 0.8:
				_text(f, 320, 300, "tap to go on", 12, ink)
		"champion":
			var c := Palette.col(_verdict_role)
			var s := 1.0 + 0.06 * sin(_pulse * 6.0)
			_text(f, 320, 160, _verdict, int(30 * s), c)
			_text(f, 320, 206, "%d - %d" % [_wins[0], _wins[1]], 24, ink)

func _draw_pool(f: Font) -> void:
	var ink := Palette.col("ink")
	_text(f, 320, 40, "%s  ·  best of %d" % [_names[0], best_of], 16, Palette.col(ROLES[0]))
	var inv: Dictionary = _net.invite
	if not inv.is_empty():
		_text(f, 320, 150, "%s CHALLENGES YOU" % inv.name.to_upper(), 26, Palette.col(ROLES[1]))
		_text(f, 320, 190, "best of %d -- their rules" % inv.best_of, 15, ink)
	elif _net.state == "asking":
		_text(f, 320, 150, "challenging %s" % _net._ask_name, 22, Palette.col(ROLES[1]))
		_text(f, 320, 190, "waiting for an answer" + ".".repeat(int(_pulse * 3.0) % 4), 14, ink)
	elif _net.players.is_empty():
		_text(f, 320, 150, "nobody else is here yet", 18, ink)
		_text(f, 320, 180, "keep this open -- names show up as people join", 12,
			Palette.col("bg_alt").lightened(0.4))
	else:
		_text(f, 320, 86, "tap someone to challenge them", 13, Palette.col("warn"))
	_note_line(f)

func _note_line(f: Font) -> void:
	if _note_left > 0.0:
		var c := Palette.col("warn")
		_text(f, 320, 306, _note, 13, Color(c.r, c.g, c.b, minf(1.0, _note_left)))

func _scoreboard(f: Font) -> void:
	var y := 30.0
	_text(f, 210, y, "%s %d" % [_names[0], _wins[0]], 18, Palette.col(ROLES[0]))
	_text(f, 430, y, "%d %s" % [_wins[1], _names[1]], 18, Palette.col(ROLES[1]))
	_text(f, 320, y, "best of %d" % best_of, 11, Palette.col("ink"))
	# one pip per win needed, filled as they come
	for i in 2:
		for k in _need:
			var x := (200.0 - k * 14.0) if i == 0 else (440.0 + k * 14.0)
			var c := Palette.col(ROLES[i])
			if k < _wins[i]:
				draw_circle(Vector2(x, y + 10), 4.0, c)
			else:
				draw_arc(Vector2(x, y + 10), 4.0, 0, TAU, 16, Color(c.r, c.g, c.b, 0.5), 1.0)

func _text(f: Font, cx: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(cx - 300, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 600, size, col)
