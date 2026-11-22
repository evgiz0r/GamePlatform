extends SceneTree
## Watched, not driven (streets.gd _watching): a test drive (`ROUTE`, default 10, the test town's)
## and a walk (`WALK_LEVEL`, default the test town's) take no control -- keys (the seat view,
## the walk button, autodrive off), the pedals, and taps on the HUD's buttons and the screen
## change nothing; the drive goes on with autodrive, the walk on its own clock.
var g: Node

func _initialize() -> void:
	_run()

func _game() -> Node:
	for n in root.find_children("*", "Node2D", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
			return n
	return null

func _load(cfg: Dictionary) -> void:
	root.get_node("Flow").start_game("streets", cfg)
	g = null
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		g = _game()
	await create_timer(2.0).timeout

func _poke() -> void:
	# the keyboard's switches and the pedals, then taps all over the screen
	for k: int in [KEY_C, KEY_F, KEY_V, KEY_M, KEY_SPACE, KEY_H]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = true
		Input.parse_input_event(e)
		await process_frame
		e = e.duplicate()
		e.pressed = false
		Input.parse_input_event(e)
	Input.action_press("action_b")
	Input.action_press("move_down")
	Input.action_press("move_left")
	for i in range(30):
		await physics_frame
	Input.action_release("action_b")
	Input.action_release("move_down")
	Input.action_release("move_left")
	for y in range(20, 360, 40):
		for x in range(20, 640, 60):
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = true
			m.position = Vector2(x, y)
			m.global_position = m.position
			g._input(m)
			m = m.duplicate()
			m.pressed = false
			g._input(m)
	await create_timer(1.0).timeout

func _run() -> void:
	await create_timer(0.3).timeout
	var probe = load("res://game/streets/streets.gd")
	var rlv := 0
	var wlv := int(OS.get_environment("WALK_LEVEL")) if OS.get_environment("WALK_LEVEL") != "" else 0
	for i in range(probe.LEVELS.size()):
		var lv: Dictionary = probe.LEVELS[i]
		if lv.get("routes", false):
			rlv = i + 1
		if wlv == 0 and String(lv.get("walk", "")) == "dimyon_market":
			wlv = i + 1
	var ok := true
	# a test drive
	var route := int(OS.get_environment("ROUTE")) if OS.get_environment("ROUTE") != "" else 10
	await _load({"level": 4, "route": route})
	var seat0: bool = g._cockpit
	var p0: Vector2 = g._pos
	await _poke()
	await create_timer(3.0).timeout
	var moved: float = (g._pos as Vector2).distance_to(p0)
	var drive_ok: bool = g._watching() and g._auto and g._cockpit == seat0 and not g._walking and g._dest_on and moved > 5.0
	print("test drive %d: watching %s, autodrive %s, seat view %s (was %s), on foot %s, going somewhere %s, %.0f m on: %s"
		% [route, g._watching(), g._auto, g._cockpit, seat0, g._walking, g._dest_on, moved, "ok" if drive_ok else "FAIL"])
	ok = ok and drive_ok
	# a walk
	await _load({"level": wlv})
	var t0: float = g._film_t
	var w0: float = Time.get_ticks_msec() / 1000.0
	await _poke()
	var rate: float = (g._film_t - t0) / (Time.get_ticks_msec() / 1000.0 - w0)
	var walk_ok: bool = g._watching() and not g._film.is_empty() and rate > 0.8 and rate < 1.3 and not g._auto
	print("walk (level %d): watching %s, its clock %.2f s a second, speed %sx: %s" % [wlv, g._watching(), rate, g._walk_speed,
		"ok" if walk_ok else "FAIL"])
	ok = ok and walk_ok
	print("WATCH ONLY: %s" % ("ok" if ok else "FAIL"))
	quit()
