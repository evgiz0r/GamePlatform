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
	print("PLACES %s; models stamped %s" % [JSON.stringify(g._places.count), JSON.stringify(g._models.stamped)])
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 3
	var out := OS.get_environment("OUT")
	var done := {}
	var spots: Array = g._places.spots.duplicate()
	for lm: Array in g._landmarks:   # (and the parks' playgrounds: the made models there too)
		if String(lm[1]) == "playground":
			spots.append(["park_playground", lm[0]])
	for sp: Array in spots:
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
		# and from eye height, 9 m off on the open side: under a yard's sail
		var cam := Camera3D.new()
		g.world.add_child(cam)
		var best := Vector2.ZERO
		for k in range(16):
			var d := Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0))
			if not g._places._in_bld(p + d * 9.0) and not g._places._in_bld(p + d * 4.5):
				best = d
				break
		var eye := p + best * 9.0
		cam.position = Vector3(eye.x, g._h(eye) + 1.7, eye.y)
		cam.look_at(Vector3(p.x, g._h(p) + 1.0, p.y), Vector3.UP)
		cam.fov = 60.0
		cam.make_current()
		await create_timer(1.0).timeout
		root.get_viewport().get_texture().get_image().save_png(out + "/place_%s_%d_eye.png" % [kind, done[kind]])
		cam.queue_free()
	print("PLACES: done")
	quit(0)
