extends SceneTree
## A route of your own, made the way a player makes one: the Test routes list, its "yours"
## page, a city (the test town: quick to load), then "from" and "to" in the address picker
## (two addresses picked by the script, as a tap on one would) -- and the route is saved
## (user://my_routes.json), the car set down at its "from" and autodrive on to its "to"; back
## on the list it shows on the "yours" page. Shots in $OUT: the page, the picker asking from
## and to, the drive starting, the page with the route on it. The file is put back as it was.
##   STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/my_route.gd
var g: Node
var saved_before := ""

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

func _tap(text_starts: String) -> bool:
	for b: Button in g._route_ui.find_children("*", "Button", true, false):
		if b.text.begins_with(text_starts) and not b.is_queued_for_deletion():
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = b.get_global_rect().get_center()
			ev.global_position = ev.position
			g._input(ev)   # (the game's own _input: see route_menu.gd)
			return true
	return false

func _fail(why: String) -> void:
	print("MY ROUTE: FAIL, " + why)
	_restore()
	quit(1)

func _restore() -> void:
	if saved_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://my_routes.json"))
	else:
		FileAccess.open("user://my_routes.json", FileAccess.WRITE).store_string(saved_before)

func _run() -> void:
	if FileAccess.file_exists("user://my_routes.json"):
		saved_before = FileAccess.get_file_as_string("user://my_routes.json")
	await create_timer(0.3).timeout
	var probe = load("res://game/streets/streets.gd")
	var lv := 0
	for i in range(probe.LEVELS.size()):
		if (probe.LEVELS[i] as Dictionary).get("routes", false):
			lv = i + 1
	root.get_node("Flow").start_game("streets", {"level": lv})
	await create_timer(2.0).timeout
	g = _game()
	if g == null or g._route_ui == null:
		return _fail("no list")
	var had: int = g._my_routes().size()
	if not _tap("yours"):
		return _fail("no 'yours' tab")
	await create_timer(0.3).timeout
	await _snap("my_routes_page")
	if not _tap("test town"):
		return _fail("no city button on the 'yours' page")
	# the city loads, the picker opens asking "from"
	var waited := 0.0
	g = null
	while waited < 600.0:
		await create_timer(0.5).timeout
		waited += 0.5
		var n := _game()
		if n != null and n._loaded and n._picker != null:
			g = n
			break
	if g == null:
		return _fail("the city did not load, or no picker")
	print("picker: \"%s\"" % g._pick_title.text)
	await _snap("my_route_from")
	# two addresses on different streets, a few hundred metres apart
	var picks: Array = []
	for st: String in g._addr:
		for a: Array in g._addr[st]:
			if picks.is_empty() or (st != picks[0][0] and (a[1] as Vector2).distance_to(picks[0][2]) > 300.0):
				picks.append([st, String(a[0]), a[1]])
				break
		if picks.size() == 2:
			break
	if picks.size() < 2:
		return _fail("no two addresses")
	g._go_to("%s %s" % [picks[0][0], picks[0][1]], picks[0][2])
	await create_timer(0.3).timeout
	var asked_to: String = g._pick_title.text if g._picker != null else "(no picker)"
	print("then: \"%s\"" % asked_to)
	await _snap("my_route_to")
	g._go_to("%s %s" % [picks[1][0], picks[1][1]], picks[1][2])
	var set_down: float = (g._pos as Vector2).distance_to(picks[0][2])   # (where it was put, before it drives off)
	var street: Dictionary = g._nearest_seg(picks[0][2], 150.0, true, true)
	var street_d: float = (street["q"] as Vector2).distance_to(picks[0][2]) if not street.is_empty() else 0.0
	print("set down %.0f m from the 'from' address (its nearest street %.0f m off)" % [set_down, street_d])
	await create_timer(3.0).timeout
	var mine: Array = g._my_routes()
	var r: Dictionary = mine[0] if not mine.is_empty() else {}
	print("saved: %d routes (had %d); newest %s" % [mine.size(), had, JSON.stringify(r)])
	print("driving: autodrive %s, to %s, 3 s later %.0f m from its start" % ["on" if g._auto else "off",
		g._dest_name if g._dest_on else "(nowhere)", (g._pos as Vector2).distance_to(picks[0][2])])
	await _snap("my_route_driving")
	var ok: bool = mine.size() == mini(had + 1, g.MY_ROUTES_MAX) and r.get("mine", false) and r.get("city", "") == "dimyon" and g._auto and g._dest_on \
		and asked_to.contains("to where") and set_down < street_d + 25.0
	# the list again, on the "yours" page
	root.get_node("Flow").start_game("streets", {"level": lv, "page": "mine"})
	await create_timer(2.0).timeout
	g = _game()
	var rows := 0
	for b: Button in g._route_ui.find_children("*", "Button", true, false):
		if b.text.contains(" from "):
			rows += 1
	print("the 'yours' page: %d routes listed" % rows)
	await _snap("my_routes_after")
	ok = ok and rows == mine.size()
	_restore()
	print("MY ROUTE: %s" % ("PASS" if ok else "FAIL"))
	quit(0)
