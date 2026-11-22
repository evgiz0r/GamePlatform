extends SceneTree
## The "Cities" level: its list (city_list.png), one button per city, and "back" goes to the
## start screen (start_screen.png). Then the "Walks" level: the list shows (a shot, $OUT/walk_list.png) with every place in LEVELS
## that has a "walk", the filmed ones first; a tap on one (WALK_PICK, default the last: the
## test town's, quick to load) starts its city with that walk replaying (walk_started.png, a
## few seconds in). Prints the buttons, the level the tap started, and where the walker is
## against the walk's first point.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _game() -> Node:
	for n in root.find_children("*", "Node2D", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
			return n
	return null

## every button on the list inside the 640x360 screen and none on another (a settings row once
## ran "night" off the right edge); prints and returns whether so
func _layout_ok(what: String) -> bool:
	var bs: Array = g._route_ui.find_children("*", "Button", true, false)
	var bad: Array = []
	for i in range(bs.size()):
		var a := Rect2((bs[i] as Button).position, (bs[i] as Button).size)
		if not Rect2(0, 0, 640, 360).encloses(a):
			bad.append("%s off the screen" % bs[i].text)
		for j in range(i + 1, bs.size()):
			if a.intersects(Rect2((bs[j] as Button).position, (bs[j] as Button).size)):
				bad.append("%s on %s" % [bs[i].text, bs[j].text])
	print("%s layout: %d buttons, %s" % [what, bs.size(), "ok" if bad.is_empty() else "FAIL " + str(bad)])
	return bad.is_empty()

func _run() -> void:
	await create_timer(0.3).timeout
	var lv := 0
	var walks := 0
	var probe = load("res://game/streets/streets.gd")
	for i in range(probe.LEVELS.size()):
		if (probe.LEVELS[i] as Dictionary).get("walks", false):
			lv = i + 1
		if (probe.LEVELS[i] as Dictionary).has("walk"):
			walks += 1
	print("the Walks level is level %d; %d walks in LEVELS" % [lv, walks])
	# the Cities list first: one button per city, and "back" to the start screen
	var clv := 0
	var cities := 0
	for i in range(probe.LEVELS.size()):
		var l: Dictionary = probe.LEVELS[i]
		if l.get("cities", false):
			clv = i + 1
		# (the list's own rule, _walk_list_open: not a walk, a scenario, a place that is its own
		# test drive or a list -- counting the scenarios, this said FAIL from the day they came)
		elif l.has("city") and not l.has("walk") and not l.has("scenario") and not l.has("test_drive") and not probe._is_list(l):
			cities += 1
	root.get_node("Flow").start_game("streets", {"level": clv})
	await create_timer(2.0).timeout
	g = _game()
	if g == null or g._route_ui == null:
		print("CITY MENU: FAIL, no list")
		quit(1)
		return
	var all: Array = g._route_ui.find_children("*", "Button", true, false)
	var cb: Array = all.filter(func(x): return x.text != "back" and not x.has_meta("setting"))
	print("the Cities list (level %d): %d buttons for %d cities (%s): %s" % [clv, cb.size(), cities,
		"ok" if cb.size() == cities else "FAIL", ", ".join(cb.map(func(x): return x.text))])
	_layout_ok("city_list")
	await _snap("city_list")
	var back: Array = all.filter(func(x): return x.text == "back")
	if back.size() != 1:
		print("CITY MENU: FAIL, %d back buttons" % back.size())
		quit(1)
		return
	var bev := InputEventMouseButton.new()
	bev.button_index = MOUSE_BUTTON_LEFT
	bev.pressed = true
	bev.position = (back[0] as Button).get_global_rect().get_center()
	bev.global_position = bev.position
	g._input(bev)
	await create_timer(1.0).timeout
	print("back: %s" % ("the start screen (no game running)" if _game() == null else "FAIL, still in the game"))
	await _snap("start_screen")
	root.get_node("Flow").start_game("streets", {"level": lv})
	await create_timer(2.0).timeout
	g = _game()
	if g == null or g._route_ui == null:
		print("WALK MENU: FAIL, no list")
		quit(1)
		return
	var buttons: Array = g._route_ui.find_children("*", "Button", true, false).filter(func(x): return x.text != "back" and not x.has_meta("setting"))
	print("the list: %d buttons (%s)" % [buttons.size(), "ok" if buttons.size() == walks else "FAIL: one per walk"])
	for b: Button in buttons:
		print("  ", b.text)
	_layout_ok("walk_list")
	await _snap("walk_list")
	var pick := int(OS.get_environment("WALK_PICK")) if OS.get_environment("WALK_PICK") != "" else buttons.size()
	var b: Button = buttons[pick - 1]
	var at := b.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	g._input(ev)   # (the game's own _input, as route_menu.gd: a real tap arrives in its 640x360 layout)
	var waited := 0.0
	g = null
	while waited < 600.0:
		await create_timer(0.5).timeout
		waited += 0.5
		var n := _game()
		if n != null and n._loaded:
			g = n
			break
	if g == null:
		print("WALK MENU: FAIL, the walk's city never loaded")
		quit(1)
		return
	print("started level %d (%s), its walk %s" % [int(root.get_node("Flow").current_config.get("level", 0)), g._place.get("name", "?"), g._place.get("walk", "none")])
	if g._film.is_empty():
		print("WALK MENU: FAIL, no walk replaying")
		quit(1)
		return
	await create_timer(4.0).timeout
	var p0 := Vector2(g._film[0].x, g._film[0].y)
	print("walk of %.0f s, %d points; %.1f s in, the walker %.1f m from its first point" % [g._film[g._film.size() - 1].z,
		g._film.size(), g._film_t, g._pos.distance_to(p0)])
	await _snap("walk_started")
	# the speed button (bottom right): pressed once, the walk's clock goes twice as fast against
	# real time; the progress bar's fill and time along the foot
	var r0: float = g._film_t
	var w0 := Time.get_ticks_msec()
	await create_timer(2.0, true, false, true).timeout
	var rate1: float = (g._film_t - r0) / ((Time.get_ticks_msec() - w0) / 1000.0)
	var sev := InputEventMouseButton.new()
	sev.button_index = MOUSE_BUTTON_LEFT
	sev.pressed = true
	sev.position = (g._walk_btn as Button).get_global_rect().get_center()
	sev.global_position = sev.position
	g._input(sev)
	await create_timer(0.5, true, false, true).timeout
	r0 = g._film_t
	w0 = Time.get_ticks_msec()
	await create_timer(2.0, true, false, true).timeout
	var rate2: float = (g._film_t - r0) / ((Time.get_ticks_msec() - w0) / 1000.0)
	print("speed button: %s; the walk's clock %.2f then %.2f s a second (%s); the bar %s, at %.0f px" % [g._walk_btn.text, rate1, rate2,
		"ok" if rate2 > rate1 * 1.6 else "FAIL: not faster", g._walk_time.text, g._walk_fill.size.x])
	print("the game's own transform %s (the bar's layer assumes none)" % g.get_global_transform())
	await _snap("walk_faster")
	print("WALK MENU: ok")
	quit()
