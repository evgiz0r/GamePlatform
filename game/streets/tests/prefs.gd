extends SceneTree
## The player's choices kept between launches (_prefs_load / _prefs_save): a saved file's
## settings come back on the next start -- the lists' time of day and autodrive style, the
## buttons folded, the steering assist -- and a change is written straight back. Uses its own
## file (STREETS_PREFS_PATH), never the player's. Needs no screen:
##   STREETS_PREFS=1 STREETS_PREFS_PATH=user://streets_prefs_test.json \
##     $GODOT --headless --path . -s res://game/streets/tests/prefs.gd
var fails := 0

func _ok(what: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	var path := OS.get_environment("STREETS_PREFS_PATH")
	if path == "" or OS.get_environment("STREETS_PREFS") != "1":
		print("prefs: set STREETS_PREFS=1 and STREETS_PREFS_PATH (never the player's own file)")
		quit(2)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"time": "night", "routes_style": "racer", "cities_style": "rules",
		"folded": true, "assist": false}))
	f = null
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 4})
	var g: Node = null
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	_ok("the lists' settings read (%s, %s, %s)" % [g._list_time, g._routes_style, g._cities_style],
		g._list_time == "night" and g._routes_style == "racer" and g._cities_style == "rules")
	_ok("folded and assist off, as saved", g._hud_folded and not g._assist)
	g._hud_tap(g.SHOW_BTN.get_center())
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	_ok("show unfolds and is written back (%s)" % [d], d is Dictionary and d["folded"] == false and d["time"] == "night")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("prefs: %d failed" % fails)
	quit(1 if fails > 0 else 0)
