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

## a tap on a list's button, to the game's own _input
func _tap(b: Button) -> void:
	var at := b.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	# (to the game's own _input, where a real tap arrives already in its 640x360 layout: pushed
	# into the window it was read as window pixels and landed on another button)
	g._input(ev)

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
	# the routes' rows only: not the page tabs ("the ten", "yours") or "back" (counted with them,
	# the test said FAIL and tapped route 8, Tel Aviv, for the 10th)
	var buttons: Array = g._route_ui.find_children("*", "Button", true, false).filter(
		func(x): return not (x.text in ["back", "the ten"] or x.text.begins_with("yours") or x.has_meta("setting")))
	print("the list: %d buttons" % buttons.size())
	# the list's settings (_list_settings): "racer" and "night" tapped, so the drive should start
	# racing at night (SETTINGS="" leaves them as they are: normal, by day)
	var want: Array = Array((OS.get_environment("SETTINGS") if OS.has_environment("SETTINGS") else "racer,night").split(",", false))
	for word: String in want:
		for sb: Button in g._route_ui.find_children("*", "Button", true, false):
			if sb.has_meta("setting") and sb.text == word:
				_tap(sb)
				await process_frame
				break
	buttons = g._route_ui.find_children("*", "Button", true, false).filter(   # (the list was built anew)
		func(x): return not (x.text in ["back", "the ten"] or x.text.begins_with("yours") or x.has_meta("setting")))
	var route_list_ok := _layout_ok("route_list")
	await _snap("route_list")
	var pick := int(OS.get_environment("ROUTE_PICK")) if OS.get_environment("ROUTE_PICK") != "" else 10
	_tap(buttons[pick - 1])
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
	var t := 0.0
	while g._tod_busy and t < 20.0:   # (night comes through evening)
		await create_timer(0.25).timeout
		t += 0.25
	var style_ok: bool = g._racing() == ("racer" in want) and g._night == ("night" in want) and g._ap_style_now() == ("racer" if "racer" in want else "rules")
	print("settings %s: racing %s, night %s, the chip says %s (%s)" % [want, g._racing(), g._night, g._ap_style_now(), "ok" if style_ok else "FAIL"])
	await _snap("route_started")
	var ok: bool = buttons.size() == 10 and g._auto and g._dest_on and (g._pos as Vector2).distance_to(from) < 80.0 and style_ok and route_list_ok
	print("ROUTE MENU: %s" % ("PASS" if ok else "FAIL"))
	quit(0)
