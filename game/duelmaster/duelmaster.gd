extends GameMode
## duelmaster -- two players, one device, best of N. See GAME.md.
## Duel after duel comes up at random. BLUE and PINK each take a turn at the SAME setup
## (the duel is rebuilt from one seed), the smaller error wins, close enough is a draw.
## First to more than half of N takes the set.
##
## Each duel lives in duels/ and is "seed in, number out" -- that is the whole interface,
## and it is also everything online play will have to send between two phones.

const DUELS := [
	preload("res://game/duelmaster/duels/marble.gd"),
	preload("res://game/duelmaster/duels/slice.gd"),
	preload("res://game/duelmaster/duels/clock.gd"),
	preload("res://game/duelmaster/duels/curling.gd"),
]
const NAMES := ["BLUE", "PINK"]
const ROLES := ["player", "hazard"]
const BEST_OF := [1, 3, 5, 7]
const COUNT_TIME := 0.9           ## "GO" beat before a turn, so the start tap is not an action
const RESULT_TIME := 1.4          ## the turn's result stays up this long
const VERDICT_TIME := 3.2
const CHAMPION_TIME := 3.6
## The shell default (0.8) is loud for a game that beeps every few seconds. Memory only,
## restored on exit. See CLAUDE.md, "things this kit learned the hard way".
const SFX_SCALE := 0.35

var best_of := 3
var _need := 2
var _wins := [0, 0]
var _duel_no := 0
var _bag: Array = []              ## shuffled duel indices still to come this cycle
var _kind := 0                    ## index into DUELS for the duel being played
var _seed := 0
var _first := 0                   ## who opens this duel; alternates
var _turn := 0                    ## 0 = first player's turn, 1 = second's
var _results := [0.0, 0.0]        ## by player, not by turn order
var _said := ["", ""]             ## the same results as words ("12 px off")
var _duel: Node2D = null
var _info: Node2D = null          ## a throwaway built from the seed, for its title and hint
var _verdict := ""
var _verdict_role := "ink"
## pick -> ready -> count -> turn -> result -> ready (other player) -> ... -> verdict
## -> ready (next duel) ... -> champion -> win()
var _phase := "pick"
var _phase_left := 0.0
var _layer: CanvasLayer
var _pulse := 0.0
var _sfx_was := 0.8

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
	Probe.event("boot")
	# "play again" comes back with the same N, so it goes straight into the next set
	if config.has("best_of"):
		_begin_set(int(config["best_of"]))
	else:
		_show_picker()

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	if _info != null and is_instance_valid(_info):
		_info.free()

## ---- the set ----------------------------------------------------------------

func _show_picker() -> void:
	_phase = "pick"
	# Buttons live in a CanvasLayer above the shell's HUD, otherwise Flow's full-screen
	# Control takes the click and the button is decorative. (Same as checkers.)
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	for i in BEST_OF.size():
		var n: int = BEST_OF[i]
		var b := UIKit.button("best of %d" % n, _begin_set.bind(n))
		b.custom_minimum_size = Vector2(124, 46)
		b.size = Vector2(124, 46)
		b.position = Vector2(56 + i * 136, 196)
		b.add_theme_font_size_override("font_size", 16)
		_layer.add_child(b)

func _begin_set(n: int) -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
		_layer = null
	best_of = n
	_need = n / 2 + 1
	Flow.current_config["best_of"] = n
	_wins = [0, 0]
	_duel_no = 0
	_first = randi() % 2
	Audio.play("voice_go")
	Probe.event("set_start", {"best_of": n})
	_next_duel()

func _next_duel() -> void:
	_duel_no += 1
	if _bag.is_empty():
		for i in DUELS.size():
			_bag.append(i)
		_bag.shuffle()
		# never the same duel twice running across a reshuffle
		if _bag.size() > 1 and _bag[0] == _kind and _duel_no > 1:
			_bag.append(_bag.pop_front())
	_kind = _bag.pop_front()
	_seed = randi()
	_first = 1 - _first if _duel_no > 1 else _first
	_turn = 0
	_results = [0.0, 0.0]
	if _info != null and is_instance_valid(_info):
		_info.free()
	_info = DUELS[_kind].new()    ## never built or added; it only answers title/hint/tie
	Probe.event("duel_start", {"n": _duel_no, "duel": _info.title, "first": NAMES[_first]})
	_enter_ready()

func _player() -> int:
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
	_results[_player()] = err
	_said[_player()] = _duel.describe(err)
	Probe.event("turn_done", {"who": NAMES[_player()], "err": snappedf(minf(err, 9999.0), 0.01)})
	_phase = "result"
	_phase_left = RESULT_TIME

func _after_result() -> void:
	if _duel != null and is_instance_valid(_duel):
		_duel.queue_free()
	_duel = null
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
		_verdict = "%s WINS THE DUEL" % NAMES[w]
		_verdict_role = ROLES[w]
		Juice.hit(6.0)
		Audio.play("voice_correct")
		Probe.event("duel_won", {"who": NAMES[w], "score": "%d-%d" % [_wins[0], _wins[1]]})
	_phase = "verdict"
	_phase_left = VERDICT_TIME
	if _duel_no % 3 == 1:
		Probe.capture("duel %d" % _duel_no)

func _after_verdict() -> void:
	for i in 2:
		if _wins[i] >= _need:
			_phase = "champion"
			_phase_left = CHAMPION_TIME
			_verdict = "%s IS THE DUELMASTER" % NAMES[i]
			_verdict_role = ROLES[i]
			Juice.hit(10.0)
			Audio.play("voice_congratulations")
			Probe.event("set_won", {"who": NAMES[i], "score": "%d-%d" % [_wins[0], _wins[1]]})
			return
	_next_duel()

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

func _process(delta: float) -> void:
	if finished:
		return
	_pulse += delta
	queue_redraw()
	if _phase == "pick":
		if PInput.just_pressed("action_a"):
			_begin_set(3)
		return
	if PInput.just_pressed("action_a"):
		_on_press()
	if PInput.just_released("action_a"):
		_on_release()

	match _phase:
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
				win()

## ---- the screen ---------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")
	if _phase == "pick":
		_text(f, 320, 110, "DUELMASTER", 34, Palette.col("accent"))
		_text(f, 320, 146, "two players, one screen. take turns, closest wins.", 13, ink)
		_text(f, 320, 176, "how many duels?", 14, Palette.col("warn"))
		return

	_scoreboard(f)
	match _phase:
		"ready":
			var p := _player()
			var col := Palette.col(ROLES[p])
			_text(f, 320, 104, "DUEL %d  ·  %s" % [_duel_no, _info.title], 15, Palette.col("accent"))
			_text(f, 320, 156, "%s, YOUR TURN" % NAMES[p], 30, col)
			_text(f, 320, 190, _info.hint, 14, ink)
			if _turn == 1:
				var o := 1 - p
				_text(f, 320, 226, "%s: %s  -- beat that" % [NAMES[o], _said[o]],
					14, Palette.col(ROLES[o]))
			else:
				_text(f, 320, 226, "same setup for both of you", 12, Palette.col("bg_alt").lightened(0.4))
			var a := 0.55 + 0.45 * sin(_pulse * 4.0)
			_text(f, 320, 290, "tap when ready", 16, Color(col.r, col.g, col.b, a))
		"count":
			_text(f, 320, 70, "%s  ·  GO" % NAMES[_player()], 14, Palette.col(ROLES[_player()]))
		"turn":
			_text(f, 320, 70, "%s  ·  %s" % [NAMES[_player()], _info.hint], 12, Palette.col(ROLES[_player()]))
		"result":
			_text(f, 320, 74, _said[_player()], 22, Palette.col(ROLES[_player()]))
		"verdict":
			for i in 2:
				var x := 190.0 if i == 0 else 450.0
				var c := Palette.col(ROLES[i])
				_text(f, x, 150, NAMES[i], 20, c)
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

func _scoreboard(f: Font) -> void:
	var y := 30.0
	_text(f, 230, y, "%s %d" % [NAMES[0], _wins[0]], 18, Palette.col(ROLES[0]))
	_text(f, 410, y, "%d %s" % [_wins[1], NAMES[1]], 18, Palette.col(ROLES[1]))
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
