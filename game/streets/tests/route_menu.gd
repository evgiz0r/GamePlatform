extends SceneTree
## The "Test routes" level: the list shows (a shot, $OUT/route_list.png), a tap on a route
## (ROUTE_PICK, default 10: the test town's, quick to load) starts its city with the car at
## its "from" and autodrive going to its "to" (a shot of that, route_started.png). Prints
## what it found: the buttons, where the car is against the route's start, autodrive on.
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
	var probe = load("res://game/streets/streets.gd")
	for i in range(probe.LEVELS.size()):
		if (probe.LEVELS[i] as Dictionary).get("routes", false):
			lv = i + 1
	print("the Test routes level is level %d" % lv)
	root.get_node("Flow").start_game("streets", {"level": lv})
	await create_timer(2.0).timeout
	g = _game()
	if g == null or g._route_ui == null:
		print("ROUTE MENU: FAIL, no list")
		quit(1)
		return
	var buttons: Array = g._route_ui.find_children("*", "Button", true, false)
	print("the list: %d buttons" % buttons.size())
	await _snap("route_list")
	var pick := int(OS.get_environment("ROUTE_PICK")) if OS.get_environment("ROUTE_PICK") != "" else 10
	var b: Button = buttons[pick - 1]
	var at := b.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	root.push_input(ev)
	# the route's city loads
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
		print("ROUTE MENU: FAIL, the route's city did not load")
		quit(1)
		return
	await create_timer(3.0).timeout
	var r: Dictionary = g._route
	var from := Vector2(float(r["from_at"][0]), float(r["from_at"][1]))
	print("route %d in %s: the car %.0f m from its start, autodrive %s, going to %s" % [
		int(r["id"]), g._city_id, (g._pos as Vector2).distance_to(from), "on" if g._auto else "off", g._dest_name if g._dest_on else "(nowhere)"])
	await _snap("route_started")
	var ok: bool = buttons.size() == 10 and g._auto and g._dest_on and (g._pos as Vector2).distance_to(from) < 80.0
	print("ROUTE MENU: %s" % ("PASS" if ok else "FAIL"))
	quit(0)
