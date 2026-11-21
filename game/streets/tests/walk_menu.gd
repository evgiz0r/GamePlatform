extends SceneTree
## The "Walks" level: the list shows (a shot, $OUT/walk_list.png) with every place in LEVELS
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
	root.get_node("Flow").start_game("streets", {"level": lv})
	await create_timer(2.0).timeout
	g = _game()
	if g == null or g._route_ui == null:
		print("WALK MENU: FAIL, no list")
		quit(1)
		return
	var buttons: Array = g._route_ui.find_children("*", "Button", true, false)
	print("the list: %d buttons (%s)" % [buttons.size(), "ok" if buttons.size() == walks else "FAIL: one per walk"])
	for b: Button in buttons:
		print("  ", b.text)
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
	print("WALK MENU: ok")
	quit()
