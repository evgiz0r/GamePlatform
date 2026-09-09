extends GameMode
## rumor -- one room full of people, and every one of them has a riddle for you.
## See game/rumor/GAME.md.
##
## Walk up to someone (or tap them) and they ask their question. Four answers, one is
## right. Right: points, and they are pleased with you. Wrong: they drop it and never
## bring it up again. Once everyone has asked, the round is over.
##
## Built for a thumb first: tap anywhere to walk there, hold and drag to steer, tap a
## person to walk up to them, tap the dialog to skip ahead. Keys work too but nothing
## needs them.

const SPEED := 150.0
const NPC_SPEED := 26.0
const TALK_RANGE := 34.0
const TYPE_SPEED := 55.0        ## characters per second in the dialog box
const SFX_SCALE := 0.35
const PEOPLE := 6

## The room. Walkers keep PAD away from the walls (sprites are taller than wide).
const ROOM := Rect2(20, 44, 600, 296)
const PAD := Vector2(16, 26)

const NAMES := ["Mira", "Theo", "Sam", "Zed", "Ava", "Kit", "Noor", "Eli", "June", "Ravi", "Lou", "Pia"]
const ACTORS := ["female", "adventurer", "soldier", "zombie"]

## Every question: the text and four answers. The FIRST answer is the right one; the
## order is shuffled when the question is handed out.
const QUESTIONS := [
	{"q": "What is the biggest country in the world?", "a": ["Russia", "Canada", "China", "Brazil"]},
	{"q": "Which country has the most people?", "a": ["India", "China", "USA", "Indonesia"]},
	{"q": "A hairy pet whose name starts with C?", "a": ["a cat", "a dog", "a canary", "a cactus"]},
	{"q": "What is the biggest ocean?", "a": ["Pacific", "Atlantic", "Indian", "Arctic"]},
	{"q": "Which planet is the hottest?", "a": ["Venus", "Mercury", "Mars", "Jupiter"]},
	{"q": "Which planet is the biggest?", "a": ["Jupiter", "Saturn", "Earth", "Neptune"]},
	{"q": "How many legs does a spider have?", "a": ["8", "6", "10", "4"]},
	{"q": "What is the fastest land animal?", "a": ["cheetah", "lion", "horse", "ostrich"]},
	{"q": "What is the tallest animal?", "a": ["giraffe", "elephant", "camel", "bear"]},
	{"q": "Which river flows through Egypt?", "a": ["the Nile", "the Amazon", "the Danube", "the Thames"]},
	{"q": "What gets wetter the more it dries?", "a": ["a towel", "a sponge", "the rain", "soap"]},
	{"q": "What has keys but can't open a single lock?", "a": ["a piano", "a map", "a door", "a jailer"]},
	{"q": "What has a face and two hands, but no arms?", "a": ["a clock", "a doll", "a statue", "a monkey"]},
	{"q": "What has to be broken before you can use it?", "a": ["an egg", "a window", "a promise", "a stick"]},
	{"q": "What goes up but never comes down?", "a": ["your age", "a ball", "a plane", "smoke"]},
	{"q": "What has one eye but cannot see?", "a": ["a needle", "a pirate", "a cyclops", "a spider"]},
	{"q": "How many continents are there?", "a": ["7", "5", "6", "9"]},
	{"q": "Which continent is the coldest?", "a": ["Antarctica", "Europe", "Asia", "North America"]},
	{"q": "What is the biggest hot desert?", "a": ["the Sahara", "the Gobi", "the Arabian", "the Kalahari"]},
	{"q": "How many days are in a leap year?", "a": ["366", "365", "364", "360"]},
	{"q": "What is the capital of France?", "a": ["Paris", "Rome", "Berlin", "Madrid"]},
	{"q": "What is the capital of Japan?", "a": ["Tokyo", "Kyoto", "Seoul", "Beijing"]},
	{"q": "Mix blue and yellow. What do you get?", "a": ["green", "purple", "orange", "brown"]},
	{"q": "What can travel the world while staying in a corner?", "a": ["a stamp", "a spider", "a clock", "a cat"]},
	{"q": "How many sides does a hexagon have?", "a": ["6", "5", "8", "7"]},
	{"q": "What is the biggest animal alive?", "a": ["the blue whale", "the elephant", "the giraffe", "the hippo"]},
	{"q": "What is the smallest country in the world?", "a": ["Vatican City", "Monaco", "Malta", "Luxembourg"]},
	{"q": "Which bird can't fly but swims like a fish?", "a": ["the penguin", "the eagle", "the parrot", "the owl"]},
	{"q": "I'm tall when I'm young and short when I'm old. What am I?", "a": ["a candle", "a tree", "a mountain", "a giraffe"]},
	{"q": "What has a neck but no head?", "a": ["a bottle", "a shirt", "a snake", "a swan"]},
	{"q": "What is full of holes but still holds water?", "a": ["a sponge", "a bucket", "a net", "a sock"]},
	{"q": "Which is the largest continent?", "a": ["Asia", "Africa", "Europe", "Australia"]},
]

const INTRO := [
	"Hey, you look smart. Quick one:",
	"Psst. Riddle for you.",
	"Wait, before you go...",
	"Bet you don't know this one.",
	"Okay okay, try this:",
	"Everyone gets this wrong. You?",
]
const RIGHT := ["Yes! That's it.", "Correct. Respect.", "Whoa. You actually knew that.", "Nailed it."]
const WRONG := ["Nope. Forget I asked.", "Wrong. I'm not talking about it again.", "Ehh, no. Never mind.", "Not even close. Moving on."]
const AFTER_RIGHT := ["You already got mine.", "Still impressed, honestly.", "Go ask someone else, genius."]
const AFTER_WRONG := ["...", "I said never mind.", "Not talking about it.", "Ask somebody else."]

var _sfx_was := 0.8

var player: Blob
var _pclip := ""                ## the clip the player is showing, so play() is not spammed
var _dest := Vector2.ZERO       ## where a tap told the player to go
var _has_dest := false
var _pointer_down := false
var _walk_t := 0.0

## dicts: {name, actor, blob, beacon, q, opts, correct, state: "open" | "right" | "wrong", to, wait}
var _people: Array = []
var _asked := 0
var _right := 0

## Talking. `_dlg` is empty when nothing is open.
var _dlg: Dictionary = {}
var _talk_lock: Object = null   ## the person you just finished with; step away to re-trigger
var _layer: CanvasLayer
var _panel: Panel
var _portrait: Blob
var _name_lbl: Label
var _text_lbl: Label
var _opts_box: GridContainer
var _opt_btns: Array = []
var _sel := 0
var _type_t := 0.0
var _more_lbl: Label            ## "tap to continue" while a line waits to be advanced
var _hud_lbl: Label
var _hint: Label

func _ready() -> void:
	title = "rumor"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	set_lives(0)   # nothing here costs a life; a wrong answer just closes a door
	_build_people()
	_build_ui()
	queue_redraw()
	Probe.event("start", {"people": _people.size()})
	Audio.play("voice_ready")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the room ----------------------------------------------------------------

func _inner() -> Rect2:
	return ROOM.grow_individual(-PAD.x, -PAD.y, -PAD.x, -PAD.y)

func _clamp(p: Vector2) -> Vector2:
	var r := _inner()
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))

func _draw() -> void:
	var floor_c := Palette.col("bg_alt")
	var wall_c := Palette.col("accent")
	draw_rect(ROOM, floor_c)
	# floorboards
	var y := ROOM.position.y + 24.0
	while y < ROOM.end.y - 6.0:
		draw_line(Vector2(ROOM.position.x + 6, y), Vector2(ROOM.end.x - 6, y),
			Color(wall_c.r, wall_c.g, wall_c.b, 0.05), 1.5)
		y += 24.0
	# a rug in the middle, so the room is not just a box
	var rug := Rect2(ROOM.position + ROOM.size * 0.5 - Vector2(120, 60), Vector2(240, 120))
	draw_rect(rug, Color(wall_c.r, wall_c.g, wall_c.b, 0.07))
	draw_rect(rug, Color(wall_c.r, wall_c.g, wall_c.b, 0.18), false, 2.0)
	draw_rect(ROOM, wall_c, false, 4.0)

## ---- people ------------------------------------------------------------------

func _build_people() -> void:
	player = Blob.new()
	add_child(player)
	player.set_actor("player", 0.45)
	player.play("idle")
	player.position = _clamp(ROOM.position + ROOM.size * 0.5)
	Probe.track(player, "@")

	var names: Array = NAMES.duplicate()
	names.shuffle()
	var qs: Array = QUESTIONS.duplicate()
	qs.shuffle()
	var friend := Palette.col("friend")
	var accent := Palette.col("accent")
	var prize := Palette.col("prize")
	# repeats of the four actors are told apart by a faint tint
	var tints: Array = [Color.WHITE, friend.lerp(Color.WHITE, 0.55), accent.lerp(Color.WHITE, 0.55),
		prize.lerp(Color.WHITE, 0.55), Color.WHITE, friend.lerp(Color.WHITE, 0.55)]

	for i in PEOPLE:
		var q: Dictionary = qs[i]
		var opts: Array = (q["a"] as Array).duplicate()
		var right: String = opts[0]
		opts.shuffle()
		var b := Blob.new()
		add_child(b)
		b.set_actor(ACTORS[i % ACTORS.size()], 0.45)
		b.play("idle")
		b.modulate = tints[i % tints.size()]
		b.position = _spawn_spot()
		b.flip_h = b.position.x > player.position.x
		# the bots find people through this "*" beacon; it is freed once that person is done
		var beacon := Node2D.new()
		b.add_child(beacon)
		Probe.track(beacon, "*")
		_people.append({
			"name": names[i], "actor": ACTORS[i % ACTORS.size()], "blob": b, "beacon": beacon,
			"q": q["q"], "opts": opts, "correct": opts.find(right), "state": "open",
			"to": b.position, "wait": randf_range(0.5, 3.0),
		})

## A spot away from the player and from everyone already placed.
func _spawn_spot() -> Vector2:
	var r := _inner().grow(-10.0)
	var best := Vector2.ZERO
	var best_gap := -1.0
	for _try in 24:
		var p := Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
		var gap := p.distance_to(player.position)
		for n in _people:
			gap = minf(gap, p.distance_to((n["blob"] as Blob).position))
		if gap > best_gap:
			best_gap = gap
			best = p
		if gap > 90.0:
			break
	return best

func _wander(delta: float) -> void:
	for n in _people:
		var b: Blob = n["blob"]
		if not _dlg.is_empty() and _dlg["npc"] == n:
			continue   # stands still while talking to you
		if n["wait"] > 0.0:
			n["wait"] -= delta
			if n["wait"] <= 0.0:
				var r := _inner().grow(-10.0)
				n["to"] = Vector2(randf_range(r.position.x, r.end.x), randf_range(r.position.y, r.end.y))
				b.play("walk", 6.0)
			continue
		var to: Vector2 = n["to"]
		var d := to - b.position
		if d.length() < 3.0:
			n["wait"] = randf_range(1.5, 5.0)
			b.play("idle")
			continue
		var step := d.normalized() * NPC_SPEED * delta
		# nobody walks through the player, or close enough to start a talk you did not ask
		# for; they stop short and wait instead
		if (b.position + step).distance_to(player.position) < TALK_RANGE + 12.0:
			n["wait"] = 1.0
			b.play("idle")
			continue
		b.position += step
		b.flip_h = step.x < 0.0

## ---- dialog ui -----------------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20   # above the shell HUD (10) so the buttons actually get taps
	add_child(_layer)

	_hud_lbl = UIKit.label("", 12, "accent")
	_hud_lbl.position = Vector2(120, 12)
	_hud_lbl.size = Vector2(400, 16)
	_layer.add_child(_hud_lbl)
	_update_hud()

	_hint = UIKit.label("walk up to someone, or tap them", 12, "ink")
	_hint.position = Vector2(120, 342)
	_hint.size = Vector2(400, 16)
	_hint.modulate.a = 0.7
	_layer.add_child(_hint)

	_panel = UIKit.panel(Vector2(616, 150))
	_panel.position = Vector2(12, 204)
	_panel.size = Vector2(616, 150)
	_panel.visible = false
	_layer.add_child(_panel)

	_portrait = Blob.new()
	_portrait.position = Vector2(52, 92)
	_panel.add_child(_portrait)

	_name_lbl = UIKit.label("", 15, "accent")
	_name_lbl.position = Vector2(100, 10)
	_name_lbl.size = Vector2(300, 18)
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_panel.add_child(_name_lbl)

	_text_lbl = UIKit.label("", 14, "ink")
	_text_lbl.position = Vector2(100, 32)
	_text_lbl.size = Vector2(500, 44)
	_text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_panel.add_child(_text_lbl)

	# four answers in two columns, each tall enough for a thumb
	_opts_box = GridContainer.new()
	_opts_box.columns = 2
	_opts_box.position = Vector2(100, 80)
	_opts_box.size = Vector2(504, 62)
	_opts_box.add_theme_constant_override("h_separation", 8)
	_opts_box.add_theme_constant_override("v_separation", 6)
	_panel.add_child(_opts_box)

	_more_lbl = UIKit.label("tap to continue", 11, "accent")
	_more_lbl.position = Vector2(470, 126)
	_more_lbl.size = Vector2(134, 16)
	_more_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_more_lbl.visible = false
	_panel.add_child(_more_lbl)

func _update_hud() -> void:
	_hud_lbl.text = "%d of %d asked   %d right" % [_asked, _people.size(), _right]

## Open a conversation. `steps` is a list; each step is either
##   {"say": "text"}                                   -- a line, advance to continue
##   {"ask": "text", "opts": [...], "pick": Callable}  -- a choice
## `done` runs when the last step has been advanced past.
func _open(npc: Dictionary, steps: Array, done: Callable) -> void:
	_dlg = {"npc": npc, "steps": steps, "i": -1, "done": done}
	_has_dest = false
	_pose("idle")
	var b: Blob = npc["blob"]
	b.play("talk")
	b.flip_h = player.position.x < b.position.x
	player.flip_h = b.position.x < player.position.x
	_portrait.set_actor(npc["actor"], 0.6)
	_portrait.modulate = b.modulate
	_portrait.play("talk")
	_name_lbl.text = npc["name"]
	_panel.visible = true
	_hint.visible = false
	Audio.play("open")
	Probe.event("talk", {"who": npc["name"]})
	_advance()

func _close() -> void:
	if _dlg.is_empty():
		return
	var b: Blob = _dlg["npc"]["blob"]
	b.play("idle")
	_talk_lock = b
	_dlg = {}
	_panel.visible = false
	_more_lbl.visible = false
	_clear_opts()

func _advance() -> void:
	_dlg["i"] += 1
	var i: int = _dlg["i"]
	var steps: Array = _dlg["steps"]
	if i >= steps.size():
		var done: Callable = _dlg["done"]
		_close()
		done.call()
		return
	var step: Dictionary = steps[i]
	_clear_opts()
	_more_lbl.visible = false
	_type_t = 0.0
	if step.has("say"):
		_text_lbl.text = step["say"]
	else:
		_text_lbl.text = step["ask"]
		var opts: Array = step["opts"]
		_sel = 0
		for k in opts.size():
			var btn := UIKit.button(opts[k], _on_opt.bind(k))
			btn.set_meta("label", opts[k])
			btn.custom_minimum_size = Vector2(248, 28)
			btn.add_theme_font_size_override("font_size", 13)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_opts_box.add_child(btn)
			_opt_btns.append(btn)
		_show_sel()
		_opts_box.visible = false   # the answers appear once the question has been asked
	_text_lbl.visible_characters = 0
	Audio.play("click", 0.2, -6.0)

func _clear_opts() -> void:
	for b in _opt_btns:
		if is_instance_valid(b):
			b.queue_free()
	_opt_btns.clear()

func _show_sel() -> void:
	for k in _opt_btns.size():
		var b: Button = _opt_btns[k]
		b.modulate = Color(1, 1, 1, 1) if k == _sel else Color(1, 1, 1, 0.6)
		b.text = ("> " if k == _sel else "   ") + str(b.get_meta("label"))

func _typing() -> bool:
	return _text_lbl.visible_characters >= 0 and _text_lbl.visible_characters < _text_lbl.text.length()

func _waiting() -> bool:
	return not _dlg.is_empty() and not _typing() and _opt_btns.is_empty()

func _on_opt(k: int) -> void:
	if _dlg.is_empty():
		return
	var step: Dictionary = _dlg["steps"][_dlg["i"]]
	if not step.has("pick"):
		return
	Audio.play("select")
	var pick: Callable = step["pick"]
	pick.call(k)

## A tap anywhere on the screen while talking: finish the line, or go to the next one.
## Answers are buttons and handle their own taps.
func _tap_dialog() -> void:
	if _typing():
		_text_lbl.visible_characters = -1
	elif _opt_btns.is_empty():
		_advance()

func _dialog_keys() -> void:
	if _typing():
		if PInput.just_pressed("action_a"):
			_text_lbl.visible_characters = -1
		return
	if _opt_btns.is_empty():
		if PInput.just_pressed("action_a"):
			_advance()
		return
	var n := _opt_btns.size()
	var moved := false
	if PInput.just_pressed("move_up"):
		_sel = maxi(0, _sel - 2)
		moved = true
	elif PInput.just_pressed("move_down"):
		_sel = mini(n - 1, _sel + 2)
		moved = true
	elif PInput.just_pressed("move_left"):
		_sel = maxi(0, _sel - 1)
		moved = true
	elif PInput.just_pressed("move_right"):
		_sel = mini(n - 1, _sel + 1)
		moved = true
	if moved:
		_show_sel()
		Audio.play("click", 0.3, -8.0)
	elif PInput.just_pressed("action_a"):
		_on_opt(_sel)

## ---- what people say ---------------------------------------------------------

func _talk_to(npc: Dictionary) -> void:
	match npc["state"]:
		"right":
			_open(npc, [{"say": AFTER_RIGHT[randi() % AFTER_RIGHT.size()]}], func() -> void: pass)
		"wrong":
			_open(npc, [{"say": AFTER_WRONG[randi() % AFTER_WRONG.size()]}], func() -> void: pass)
		_:
			_open(npc, [
				{"say": INTRO[randi() % INTRO.size()]},
				{"ask": npc["q"], "opts": npc["opts"], "pick": _on_answer.bind(npc)},
			], func() -> void: pass)

func _on_answer(k: int, npc: Dictionary) -> void:
	var b: Blob = npc["blob"]
	_asked += 1
	if k == npc["correct"]:
		npc["state"] = "right"
		_right += 1
		add_score(100)
		Audio.play("voice_correct")
		Juice.pop(b)
		Juice.text(self, b.position + Vector2(-10, -50), "+100", Palette.col("prize"))
		b.modulate = Palette.col("prize").lerp(Color.WHITE, 0.35)
		Probe.event("right", {"who": npc["name"]})
		_dlg = {"npc": npc, "steps": [{"say": RIGHT[randi() % RIGHT.size()]}], "i": -1, "done": _after_answer}
	else:
		npc["state"] = "wrong"
		Audio.play("voice_wrong")
		Juice.flash(b, Palette.col("hazard"))
		b.modulate.a = 0.55
		Probe.event("wrong", {"who": npc["name"]})
		_dlg = {"npc": npc, "steps": [{"say": WRONG[randi() % WRONG.size()]}], "i": -1, "done": _after_answer}
	var beacon: Node2D = npc["beacon"]
	if is_instance_valid(beacon):
		beacon.queue_free()
	_update_hud()
	_advance()

func _after_answer() -> void:
	if _asked < _people.size():
		return
	Probe.event("round_over", {"right": _right, "of": _people.size()})
	if _right == _people.size():
		add_score(200)
		Audio.play("voice_congratulations")
	else:
		Audio.play("voice_mission_completed")
	player.play("cheer", 6.0)
	Juice.hit(3.0)
	win()

## ---- the loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_wander(delta)
	if not _dlg.is_empty():
		if _typing():
			_type_t += delta * TYPE_SPEED
			_text_lbl.visible_characters = int(_type_t)
		elif not _opts_box.visible and not _opt_btns.is_empty():
			_opts_box.visible = true
		_more_lbl.visible = _waiting() and int(Time.get_ticks_msec() / 500.0) % 2 == 0
		_dialog_keys()
		return
	_move_player(delta)
	_check_talk()

func _move_player(delta: float) -> void:
	var d := PInput.dir()
	if d != Vector2.ZERO:
		_has_dest = false   # keys/pad override a tap
	elif _has_dest:
		if player.position.distance_to(_dest) < 3.0:
			_has_dest = false
		else:
			d = (_dest - player.position).normalized()
	if d == Vector2.ZERO:
		_pose("idle")
		return
	_pose("walk", 10.0)
	if absf(d.x) > 0.1:
		player.flip_h = d.x < 0.0
	var next := _clamp(player.position + d * SPEED * delta)
	if next == player.position:
		_has_dest = false
	player.position = next
	_walk_t += delta
	if _walk_t > 0.28:
		_walk_t = 0.0
		Audio.play("step_wood", 0.15, -10.0)

func _pose(clip: String, fps: float = 8.0) -> void:
	if _pclip == clip:
		return
	_pclip = clip
	player.play(clip, fps)

func _nearest() -> Dictionary:
	var best: Dictionary = {}
	var best_d := TALK_RANGE
	for n in _people:
		var d: float = player.position.distance_to((n["blob"] as Blob).position)
		if d < best_d:
			best_d = d
			best = n
	return best

func _check_talk() -> void:
	var n := _nearest()
	if n.is_empty():
		_talk_lock = null
		return
	# walking up to someone starts the talk; afterwards step away, or press, to talk again
	if _talk_lock != n["blob"] or PInput.just_pressed("action_a"):
		_talk_lock = null
		_has_dest = false
		_talk_to(n)

## ---- touch / mouse -----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if finished or Flow.pointer_over_hud():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if not mb.pressed:
			_pointer_down = false
			return
		if not _dlg.is_empty():
			_tap_dialog()
			return
		_pointer_down = true
		_go_to(get_global_mouse_position(), true)
	elif event is InputEventMouseMotion and _pointer_down and _dlg.is_empty():
		# holding the finger down steers: the destination follows it
		_go_to(get_global_mouse_position(), false)

## Walk towards a point. A tap on a person goes to their side instead, and a tap on
## someone already in reach talks to them straight away.
func _go_to(p: Vector2, tap: bool) -> void:
	if tap:
		for n in _people:
			var b: Blob = n["blob"]
			if p.distance_to(b.position) < 30.0:
				if player.position.distance_to(b.position) < TALK_RANGE:
					_talk_lock = null
					_talk_to(n)
					return
				p = b.position + Vector2(24.0 if player.position.x > b.position.x else -24.0, 4.0)
				break
		Audio.play("click", 0.2, -8.0)
	_dest = _clamp(p)
	_has_dest = true
