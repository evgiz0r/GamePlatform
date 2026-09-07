extends GameMode
## rumor -- walk around a small school, talk to students, find out what the rumor is.
## See game/rumor/GAME.md.
##
## Three systems and not much else, on purpose:
##   world    -- four rooms off one hallway, walls done with rectangle checks, no physics
##   talking  -- walk into someone (or tap them) and a dialog panel opens at the bottom;
##               lines advance with action_a / tap, choices move with up/down + action_a
##               or a tap on the option
##   the chain -- the students are shuffled into an order every run; each one sends you
##               to the next and the next one asks a question only the previous one's
##               words can answer

const SPEED := 130.0
const TEACHER_SPEED := 70.0
const TALK_RANGE := 36.0
const BELL_SECONDS := 90.0
const TYPE_SPEED := 45.0        ## characters per second in the dialog box
const SFX_SCALE := 0.35

## ---- the map ---------------------------------------------------------------
## Hallway across the middle, two rooms above, two below. A door is a gap in the wall
## that faces the hallway, centred on the room.
const HALL := Rect2(20, 150, 600, 60)
const WALL := 4.0
## How far a walker's centre stays from a wall: half a sprite, and sprites are taller
## than they are wide.
const PAD := 14.0
const PAD_Y := 21.0
const DOOR_W := 46.0
const ROOMS := [
	{"name": "classroom", "rect": Rect2(20, 40, 280, 110)},
	{"name": "gym",       "rect": Rect2(340, 40, 280, 110)},
	{"name": "library",   "rect": Rect2(20, 210, 280, 120)},
	{"name": "cafeteria", "rect": Rect2(340, 210, 280, 120)},
]

## ---- the people ------------------------------------------------------------
## `fact` is what the previous student says about them, and what they may quiz you on.
const STUDENTS := [
	{"name": "Mira", "actor": "female",     "fact": "chess",       "pron": "she"},
	{"name": "Theo", "actor": "adventurer", "fact": "skateboards", "pron": "he"},
	{"name": "Sam",  "actor": "soldier",    "fact": "loud music",  "pron": "they"},
	{"name": "Zed",  "actor": "zombie",     "fact": "old movies",  "pron": "he"},
]
const RUMORS := [
	"the principal sleeps in the gym",
	"the cafeteria pudding is from 1998",
	"there is a cat living in the library ceiling",
	"the hall monitor is afraid of the bell",
]
const STRANGER_LINES := [
	"Do I know you? Ask around first.",
	"Not now. Somebody must have sent you.",
	"You're not on my list. Come back with a name.",
]

var _sfx_was := 0.8

var player: Blob
var _npcs: Array = []          ## dicts: {data, blob, room, order}
var _chain: Array = []         ## indices into _npcs, in the order you must visit them
var _progress := 0             ## how many in the chain have given you a clue
var _teacher: Blob
var _teacher_dir := 1.0
var _marker: Blob              ## the "!" over whoever you should talk to next
var _guide: Blob               ## breadcrumb at the next door on the way to them
var _bubble: Label             ## "..." over whoever is in range
var _invuln := 0.0
var _bell := BELL_SECONDS
var _bell_warned := false
var _route: Array = []         ## tap-to-walk waypoints
var _walk_t := 0.0
var _pclip := ""             ## the clip the player is showing, so play() is not spammed
var _rumor := ""

## Talking. `_dlg` is null when nothing is open.
var _dlg: Dictionary = {}
var _talk_lock: Object = null  ## the npc you just finished with; step away to re-trigger
var _layer: CanvasLayer
var _panel: Panel
var _portrait: Blob
var _name_lbl: Label
var _text_lbl: Label
var _opts_box: VBoxContainer
var _opt_btns: Array = []
var _sel := 0
var _type_t := 0.0
var _hud_bell: Label
var _hint: Label

func _ready() -> void:
	title = "rumor"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	set_lives(3)
	_rumor = RUMORS[randi() % RUMORS.size()]

	_build_world()
	_build_people()
	_build_dialog_ui()
	_pick_chain()

	Probe.event("start", {"chain": _chain_names()})
	Audio.play("voice_ready")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- world -----------------------------------------------------------------

func _build_world() -> void:
	# floors and walls are drawn in _draw(); the only nodes are the room labels
	for r in ROOMS:
		var rect: Rect2 = r["rect"]
		var l := UIKit.label(r["name"], 11, "accent")
		l.modulate.a = 0.55
		l.position = Vector2(rect.position.x + 8, rect.position.y + 6)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(l)
	queue_redraw()

func _door_x(i: int) -> float:
	var rect: Rect2 = ROOMS[i]["rect"]
	return rect.position.x + rect.size.x * 0.5

## The doorway, straddling the wall line far enough to bridge the padded room and the
## padded hallway.
func _door_rect(i: int) -> Rect2:
	var rect: Rect2 = ROOMS[i]["rect"]
	var top: bool = rect.end.y <= HALL.position.y + 1.0
	var wall_y: float = rect.end.y if top else rect.position.y
	return Rect2(_door_x(i) - DOOR_W * 0.5, wall_y - PAD_Y - 6.0, DOOR_W, (PAD_Y + 6.0) * 2.0)

## Where a walker stands just inside a room, lined up with its door.
func _inside_door(i: int) -> Vector2:
	var rect: Rect2 = ROOMS[i]["rect"]
	var top: bool = rect.end.y <= HALL.position.y + 1.0
	return Vector2(_door_x(i), rect.end.y - PAD_Y - 10.0 if top else rect.position.y + PAD_Y + 10.0)

func _hall_door(i: int) -> Vector2:
	return Vector2(_door_x(i), HALL.position.y + HALL.size.y * 0.5)

func _room_of(p: Vector2) -> int:
	for i in ROOMS.size():
		if _inner(ROOMS[i]["rect"]).has_point(p):
			return i
	return -1

func _inner(r: Rect2) -> Rect2:
	return r.grow_individual(-PAD, -PAD_Y, -PAD, -PAD_Y)

func _walkable(p: Vector2) -> bool:
	if _inner(HALL).has_point(p):
		return true
	for i in ROOMS.size():
		if _inner(ROOMS[i]["rect"]).has_point(p):
			return true
		if _door_rect(i).has_point(p):
			return true
	return false

func _draw() -> void:
	var floor_c := Palette.col("bg_alt")
	var wall_c := Palette.col("accent")
	var door_c := Palette.col("prize")
	# hallway
	draw_rect(HALL, floor_c)
	draw_rect(HALL, Color(wall_c.r, wall_c.g, wall_c.b, 0.35), false, WALL)
	# floor stripes down the hallway, the cheapest way to make it read as a corridor
	var x := HALL.position.x + 30.0
	while x < HALL.end.x - 10.0:
		draw_line(Vector2(x, HALL.position.y + 8), Vector2(x, HALL.end.y - 8),
			Color(wall_c.r, wall_c.g, wall_c.b, 0.06), 2.0)
		x += 40.0
	for i in ROOMS.size():
		var rect: Rect2 = ROOMS[i]["rect"]
		draw_rect(rect, floor_c.lightened(0.04))
		draw_rect(rect, wall_c, false, WALL)
		# door: paint over the wall, then a glowing sill so it reads from across the hall
		var d := _door_rect(i)
		var top: bool = rect.end.y <= HALL.position.y + 1.0
		var sill_y: float = rect.end.y if top else rect.position.y
		draw_rect(Rect2(d.position.x, sill_y - WALL, d.size.x, WALL * 2.0), floor_c)
		draw_line(Vector2(d.position.x, sill_y), Vector2(d.end.x, sill_y),
			Color(door_c.r, door_c.g, door_c.b, 0.25), 8.0)
		draw_line(Vector2(d.position.x, sill_y), Vector2(d.end.x, sill_y), door_c, 2.0)

## ---- people ----------------------------------------------------------------

func _build_people() -> void:
	player = Blob.new()
	add_child(player)
	player.set_actor("player", 0.45)
	player.play("idle")
	player.position = Vector2(320, 180)
	Probe.track(player, "@")

	var order: Array = range(STUDENTS.size())
	order.shuffle()
	for i in STUDENTS.size():
		var data: Dictionary = STUDENTS[i]
		var room: int = order[i]
		var rect: Rect2 = ROOMS[room]["rect"]
		var b := Blob.new()
		add_child(b)
		b.set_actor(data["actor"], 0.45)
		b.play("idle")
		# stand off to one side so the walk from the door is never through them
		b.position = Vector2(rect.position.x + rect.size.x * (0.72 if room % 2 == 0 else 0.28),
			rect.position.y + rect.size.y * 0.55)
		b.flip_h = room % 2 == 0
		_npcs.append({"data": data, "blob": b, "room": room})

	_teacher = Blob.new()
	add_child(_teacher)
	_teacher.set_actor("soldier", 0.55)
	_teacher.play("walk", 8.0)
	_teacher.modulate = Palette.col("hazard").lightened(0.35)
	_teacher.position = Vector2(60, HALL.position.y + HALL.size.y * 0.5)
	Probe.track(_teacher, "x")

	_marker = Blob.new()
	_marker.role = "prize"
	_marker.shape = "diamond"
	_marker.radius = 5.0
	add_child(_marker)

	# The guide sits on the next waypoint of the route to the target, so it shows a
	# human which door to take and gives the bots (no pathfinding) a straight line to
	# follow. It is the thing tracked as "*", not the marker over the target's head.
	_guide = Blob.new()
	_guide.role = "prize"
	_guide.radius = 3.0
	add_child(_guide)
	Probe.track(_guide, "*")

	_bubble = UIKit.label("...", 14, "ink")
	_bubble.size = Vector2(40, 16)
	_bubble.visible = false
	add_child(_bubble)

func _pick_chain() -> void:
	_chain = range(_npcs.size())
	_chain.shuffle()
	_progress = 0
	_place_marker()

func _chain_names() -> Array:
	var out: Array = []
	for i in _chain:
		out.append(_npcs[i]["data"]["name"])
	return out

func _target() -> Dictionary:
	if _progress >= _chain.size():
		return {}
	return _npcs[_chain[_progress]]

func _place_marker() -> void:
	var t := _target()
	if t.is_empty():
		_marker.visible = false
		return
	_marker.visible = true
	_marker.position = (t["blob"] as Blob).position + Vector2(0, -42)

## ---- dialog ui -------------------------------------------------------------

func _build_dialog_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 20   # above the shell HUD (10) so the buttons actually get clicks
	add_child(_layer)

	_hud_bell = UIKit.label("", 12, "warn")
	_hud_bell.position = Vector2(120, 12)
	_hud_bell.size = Vector2(400, 16)
	_layer.add_child(_hud_bell)

	_hint = UIKit.label("walk into someone to talk  (arrows / tap)", 12, "ink")
	_hint.position = Vector2(120, 336)
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
	_text_lbl.size = Vector2(500, 40)
	_text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_panel.add_child(_text_lbl)

	_opts_box = VBoxContainer.new()
	_opts_box.position = Vector2(100, 74)
	_opts_box.size = Vector2(500, 70)
	_opts_box.add_theme_constant_override("separation", 3)
	_panel.add_child(_opts_box)

## Open a conversation. `steps` is a list; each step is either
##   {"say": "text"}                              -- a line, advance to continue
##   {"ask": "text", "opts": [...], "pick": Callable}  -- a choice
## `done` runs when the last step has been advanced past.
func _open(npc: Dictionary, steps: Array, done: Callable) -> void:
	_dlg = {"npc": npc, "steps": steps, "i": -1, "done": done}
	_route.clear()
	_pose("idle")
	var b: Blob = npc["blob"]
	b.play("talk")
	b.flip_h = player.position.x < b.position.x
	_portrait.set_actor(npc["data"]["actor"], 0.6)
	_portrait.play("talk")
	_name_lbl.text = npc["data"]["name"]
	_panel.visible = true
	_hint.visible = false
	Audio.play("open")
	Probe.event("talk", {"who": npc["data"]["name"]})
	_advance()

func _close() -> void:
	if _dlg.is_empty():
		return
	var b: Blob = _dlg["npc"]["blob"]
	b.play("idle")
	_talk_lock = b
	_dlg = {}
	_panel.visible = false
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
			btn.custom_minimum_size = Vector2(420, 20)
			btn.add_theme_font_size_override("font_size", 13)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_opts_box.add_child(btn)
			_opt_btns.append(btn)
		_show_sel()
		_opts_box.visible = false   # the choices appear once the question has been asked
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
		b.modulate = Color(1, 1, 1, 1) if k == _sel else Color(1, 1, 1, 0.55)
		b.text = ("> " if k == _sel else "   ") + str(b.get_meta("label"))

func _typing() -> bool:
	return _text_lbl.visible_characters >= 0 and _text_lbl.visible_characters < _text_lbl.text.length()

func _on_opt(k: int) -> void:
	if _dlg.is_empty():
		return
	var step: Dictionary = _dlg["steps"][_dlg["i"]]
	if not step.has("pick"):
		return
	Audio.play("select")
	var pick: Callable = step["pick"]
	pick.call(k)

func _dialog_input() -> void:
	if _typing():
		if PInput.just_pressed("action_a"):
			_text_lbl.visible_characters = -1
		return
	if _opt_btns.is_empty():
		if PInput.just_pressed("action_a"):
			_advance()
		return
	if PInput.just_pressed("move_up"):
		_sel = maxi(0, _sel - 1)
		_show_sel()
		Audio.play("click", 0.3, -8.0)
	elif PInput.just_pressed("move_down"):
		_sel = mini(_opt_btns.size() - 1, _sel + 1)
		_show_sel()
		Audio.play("click", 0.3, -8.0)
	elif PInput.just_pressed("action_a"):
		_on_opt(_sel)

## ---- what people say -------------------------------------------------------

func _talk_to(npc: Dictionary) -> void:
	var idx := _npcs.find(npc)
	var pos := _chain.find(idx)
	if pos < _progress:
		# already helped you: a nudge towards the next one
		var nxt := _target()
		var line := "You know everything I know."
		if not nxt.is_empty():
			line = "I already told you. Go find %s in the %s." % [nxt["data"]["name"], ROOMS[nxt["room"]]["name"]]
		_open(npc, [{"say": line}], func() -> void: pass)
	elif pos > _progress:
		_open(npc, [{"say": STRANGER_LINES[randi() % STRANGER_LINES.size()]}], func() -> void: pass)
	elif pos == 0:
		# the friend: free lead, and the tutorial for how a clue is worded
		_open(npc, [
			{"say": "Oh hey. You heard about the rumor too? Everyone's whispering."},
			{"say": "I only know who knows. " + _clue_line()},
		], _give_clue.bind(npc))
	else:
		var prev: Dictionary = _npcs[_chain[pos - 1]]
		var gate := _make_gate(npc, prev)
		_open(npc, gate, func() -> void: pass)

## "Ask <next> in the <room>. <pron> can't shut up about <fact>."
func _clue_line() -> String:
	var nxt: Dictionary = _npcs[_chain[_progress + 1]]
	var d: Dictionary = nxt["data"]
	var pron: String = str(d["pron"]).capitalize()
	return "Ask %s in the %s. %s can't shut up about %s. Say I sent you." % [
		d["name"], ROOMS[nxt["room"]]["name"], pron, d["fact"]]

## One question, three options, one right answer. Which question is a coin flip.
func _make_gate(npc: Dictionary, prev: Dictionary) -> Array:
	var d: Dictionary = npc["data"]
	var ask := ""
	var right := ""
	var pool: Array = []
	if randi() % 2 == 0:
		ask = "Hm. Who sent you?"
		right = prev["data"]["name"]
		for s in STUDENTS:
			pool.append(s["name"])
	else:
		ask = "Prove you actually know me. What am I into?"
		right = d["fact"]
		for s in STUDENTS:
			pool.append(s["fact"])
	pool.erase(right)
	pool.shuffle()
	var opts: Array = [right, pool[0], pool[1]]
	opts.shuffle()
	var correct := opts.find(right)
	return [
		{"say": "You're not from around here."},
		{"ask": ask, "opts": opts, "pick": _on_gate_pick.bind(npc, correct)},
	]

func _on_gate_pick(k: int, npc: Dictionary, correct: int) -> void:
	var last: bool = _progress == _chain.size() - 1
	if k == correct:
		Audio.play("voice_correct")
		Juice.pop(npc["blob"])
		var steps: Array = []
		if last:
			steps = [
				{"say": "Fine. You didn't hear it from me..."},
				{"say": "The rumor is: " + _rumor + "."},
			]
			_dlg = {"npc": npc, "steps": steps, "i": -1, "done": _found_rumor}
		else:
			steps = [{"say": "Okay, you're alright. " + _clue_line()}]
			_dlg = {"npc": npc, "steps": steps, "i": -1, "done": _give_clue.bind(npc)}
		_advance()
	else:
		Audio.play("voice_wrong")
		Juice.flash(npc["blob"], Palette.col("hazard"))
		Probe.event("wrong_answer", {"who": npc["data"]["name"]})
		_dlg = {"npc": npc, "steps": [{"say": "Nice try. Get lost."}], "i": -1,
			"done": func() -> void: lose_life()}
		_advance()

func _give_clue(npc: Dictionary) -> void:
	_progress += 1
	add_score(100)
	Juice.text(self, (npc["blob"] as Blob).position + Vector2(-10, -50), "+100", Palette.col("prize"))
	Audio.play("coin")
	Probe.event("clue", {"from": npc["data"]["name"], "progress": _progress})
	_place_marker()

func _found_rumor() -> void:
	_progress += 1
	_place_marker()
	var bonus := int(_bell) * 5
	add_score(200 + bonus)
	Probe.event("rumor_found", {"bonus": bonus})
	Audio.play("voice_you_win")
	Juice.hit(4.0)
	player.play("cheer", 6.0)
	win()

## ---- the loop --------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return

	# the bell keeps ringing whether you are talking or not
	_bell -= delta
	_hud_bell.text = "bell in %d:%02d" % [int(_bell) / 60, int(_bell) % 60]
	if _bell <= 15.0 and not _bell_warned:
		_bell_warned = true
		Audio.play("impact_bell")
		Audio.play("voice_hurry_up")
		Juice.text(self, Vector2(280, 100), "hurry!", Palette.col("warn"))
	if _bell <= 0.0:
		Probe.event("bell")
		Audio.play("voice_time_over")
		lose()
		return

	_move_teacher(delta)

	if not _dlg.is_empty():
		if _typing():
			_type_t += delta * TYPE_SPEED
			_text_lbl.visible_characters = int(_type_t)
		elif not _opts_box.visible and not _opt_btns.is_empty():
			_opts_box.visible = true
		_dialog_input()
		return

	_move_player(delta)
	_check_teacher()
	_check_talk()
	_marker.position.y = _target_marker_y() + sin(Time.get_ticks_msec() / 160.0) * 3.0
	_place_guide()

func _place_guide() -> void:
	var t := _target()
	if t.is_empty():
		_guide.visible = false
		return
	var b: Blob = t["blob"]
	var goal := b.position + Vector2(26.0 if player.position.x > b.position.x else -26.0, 4.0)
	var next := goal
	for wp in _route_to(goal):
		if player.position.distance_to(wp) > 6.0:
			next = wp
			break
	_guide.position = next
	# on the last leg the marker over their head already says where to go
	_guide.visible = next != goal
	_guide.radius = 3.0 + sin(Time.get_ticks_msec() / 120.0) * 1.0

func _target_marker_y() -> float:
	var t := _target()
	if t.is_empty():
		return _marker.position.y
	return (t["blob"] as Blob).position.y - 42.0

func _move_player(delta: float) -> void:
	var d := PInput.dir()
	if d != Vector2.ZERO:
		_route.clear()   # keys/pad override a tap route
	elif not _route.is_empty():
		var goal: Vector2 = _route[0]
		if player.position.distance_to(goal) < 3.0:
			_route.pop_front()
		else:
			d = (goal - player.position).normalized()
	if d == Vector2.ZERO:
		_pose("idle")
		return
	_pose("walk", 10.0)
	if absf(d.x) > 0.1:
		player.flip_h = d.x < 0.0
	# walls: try each axis on its own so sliding along a wall works
	var step := d * SPEED * delta
	var nx := player.position + Vector2(step.x, 0)
	if _walkable(nx):
		player.position = nx
	var ny := player.position + Vector2(0, step.y)
	if _walkable(ny):
		player.position = ny
	elif not _route.is_empty():
		_route.clear()   # a tap route that hits a wall is a bad route; stop rather than jitter
	_walk_t += delta
	if _walk_t > 0.28:
		_walk_t = 0.0
		Audio.play("step_wood", 0.15, -10.0)

func _pose(clip: String, fps: float = 8.0) -> void:
	if _pclip == clip:
		return
	_pclip = clip
	player.play(clip, fps)

func _move_teacher(delta: float) -> void:
	_teacher.position.x += _teacher_dir * TEACHER_SPEED * delta
	if _teacher.position.x > HALL.end.x - 30.0:
		_teacher_dir = -1.0
	elif _teacher.position.x < HALL.position.x + 30.0:
		_teacher_dir = 1.0
	_teacher.flip_h = _teacher_dir < 0.0

func _check_teacher() -> void:
	if _invuln > 0.0:
		_invuln -= get_process_delta_time()
		player.modulate.a = 0.55 if int(_invuln * 12.0) % 2 == 0 else 1.0
		return
	player.modulate.a = 1.0
	if player.position.distance_to(_teacher.position) > 28.0:
		return
	_invuln = 1.6
	Probe.event("caught")
	Juice.text(self, Vector2(clampf(player.position.x - 36.0, 8.0, 540.0), player.position.y - 50.0),
		"NO RUNNING!", Palette.col("hazard"))
	Juice.flash(player, Palette.col("hazard"))
	_pose("hurt")
	# shoved along the hall in the direction the monitor is walking
	var to := player.position + Vector2(_teacher_dir * 44.0, 0)
	if _walkable(to):
		player.position = to
	_route.clear()
	lose_life()

func _nearest_npc() -> Dictionary:
	var best: Dictionary = {}
	var best_d := TALK_RANGE
	for n in _npcs:
		var d: float = player.position.distance_to((n["blob"] as Blob).position)
		if d < best_d:
			best_d = d
			best = n
	return best

func _check_talk() -> void:
	var n := _nearest_npc()
	if n.is_empty():
		_talk_lock = null
		_bubble.visible = false
		return
	var b: Blob = n["blob"]
	_bubble.visible = true
	_bubble.position = b.position + Vector2(-20, -60)
	# walking up to someone starts the talk; after it ends you step away or press to retry
	if _talk_lock != b or PInput.just_pressed("action_a"):
		_talk_lock = null
		_bubble.visible = false
		_talk_to(n)

## ---- touch / mouse ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	if finished or not _dlg.is_empty() or Flow.pointer_over_hud():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := get_global_mouse_position()
	# tap on a person: walk up to them (the talk starts on arrival)
	for n in _npcs:
		var b: Blob = n["blob"]
		if p.distance_to(b.position) < 30.0:
			p = b.position + Vector2(24.0 if player.position.x > b.position.x else -24.0, 6.0)
			break
	if not _walkable(p):
		return
	_route = _route_to(p)
	Audio.play("click", 0.2, -8.0)

## Every room opens onto the hallway, so a route is at most: out of my room, along the
## hall, into the target's room, to the point. No pathfinding needed. A waypoint the
## walker is already lined up with is left out, otherwise whoever follows the route
## (the tap-to-walk code, the bots) dithers at it.
func _route_to(p: Vector2) -> Array:
	var out: Array = []
	var here := player.position
	var mine := _room_of(here)
	var theirs := _room_of(p)
	if mine == theirs:
		out.append(p)
		return out
	if mine < 0 and not _inner(HALL).has_point(here):
		# standing in a doorway: step straight into the hall before anything else
		for i in ROOMS.size():
			if _door_rect(i).has_point(here):
				if i == theirs:
					out.append(_inside_door(i))
					out.append(p)
					return out
				out.append(_hall_door(i))
				break
	if mine >= 0:
		if absf(here.x - _door_x(mine)) > 10.0:
			out.append(_inside_door(mine))
		out.append(_hall_door(mine))
	if theirs >= 0:
		var aligned: bool = mine < 0 and absf(here.x - _door_x(theirs)) < 10.0
		if not aligned:
			out.append(_hall_door(theirs))
		out.append(_inside_door(theirs))
	out.append(p)
	return out
