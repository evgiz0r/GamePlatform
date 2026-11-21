extends SceneTree
## A town's own kindergartens and public shelters (places.gd): with the whole city built,
## how many the map has, how many found room beside their point and how many were left out;
## then the view low over SHOTS of each kind (default 3), a shot each ($OUT/place_<kind>_<i>.png).
##   OUT=dir game/streets/tests/run.sh places 1      (STREETS_BUILD_ALL=1, run.sh's default)
## Good: most placed (the map's point is its building: the yard goes on the open ground
## beside it), none on a road or in a building (city_check counts those for everything
## solid); in the shots a fenced yard under a coloured sail, a concrete box with its sign.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	while not g._tiles_todo.is_empty() or g._tiled:
		await create_timer(0.5).timeout
	print("PLACES %s" % JSON.stringify(g._places.count))
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 3
	var out := OS.get_environment("OUT")
	var done := {}
	for sp: Array in g._places.spots:
		var kind := String(sp[0])
		if int(done.get(kind, 0)) >= shots or out == "":
			continue
		var p: Vector2 = sp[1]
		if not g._in_city(p):
			continue
		done[kind] = int(done.get(kind, 0)) + 1
		g._zoom_set(0.0)
		await create_timer(0.3).timeout
		g._land_on_road(p, 60.0, Vector2.ZERO)
		await create_timer(0.5).timeout
		g._zoom_set(0.3)
		g._zoom_off = p - g._pos
		await create_timer(2.5).timeout
		root.get_viewport().get_texture().get_image().save_png(out + "/place_%s_%d.png" % [kind, done[kind]])
		print("  shot %s %d at (%d, %d)" % [kind, done[kind], int(p.x), int(p.y)])
	print("PLACES: done")
	quit(0)
