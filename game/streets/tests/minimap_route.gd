extends SceneTree
## The minimap with a route on it: a destination DIST metres off (default 700) given to
## autodrive, then shots of the screen and of the minimap alone, enlarged (map_*.png), at
## a few moments along the way -- for judging how the route reads against the roads.
##   tests/run.sh minimap_route 1
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("OUT") + "/" + name + ".png")
	# the minimap, cut out and doubled (the viewport is the game's 640x360 scaled to the window)
	var k := float(img.get_width()) / 640.0
	var r: Rect2 = g._map.get_global_rect()
	var cut := img.get_region(Rect2i(int(r.position.x * k), int(r.position.y * k), int(r.size.x * k), int(r.size.y * k)))
	cut.resize(cut.get_width() * 2, cut.get_height() * 2, Image.INTERPOLATE_NEAREST)
	cut.save_png(OS.get_environment("OUT") + "/map_" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var dist := float(OS.get_environment("DIST")) if OS.get_environment("DIST") != "" else 700.0
	# a street about DIST metres away
	var best := Vector2.ZERO
	var name := ""
	for r: Dictionary in g._roads:
		if not r["drive"] or String(r["name"]) == "":
			continue
		var q: Vector2 = (r["pts"] as PackedVector2Array)[0]
		if absf(q.distance_to(g._pos) - dist) < absf(best.distance_to(g._pos) - dist) or best == Vector2.ZERO:
			best = q
			name = r["name"]
	g._set_dest(best, name)
	print("destination '%s', %.0f m off; autodrive %s, route points %d" % [name, best.distance_to(g._pos), g._auto, g._ap_pts.size()])
	for i in range(3):
		await create_timer(4.0).timeout
		await _snap("route_%d" % i)
	quit(0)
