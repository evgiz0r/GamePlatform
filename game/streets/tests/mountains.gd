extends SceneTree
## The test town's mountains, as you see them: from the middle of town at street height
## looking out four ways, from the hill's viewpoint, and from halfway up the mountain road.
## For the look -- run it before and after a change and put the shots side by side.
##   tests/run.sh mountains 4        (FULL=1 RES=1280x720 for the real thing)
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "4")})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.5).timeout
	var mid: Vector2 = g._bounds.get_center()
	# from the car, as you see it: on a street in town facing each way out, the chase camera
	for d: Array in [[Vector2(1, 0), "east"], [Vector2(-1, 0), "west"], [Vector2(0, 1), "south"], [Vector2(0, -1), "north"]]:
		var dir: Vector2 = d[0]
		g._land_on_road(mid + dir * 120.0, 60.0, dir)
		await create_timer(2.5).timeout
		await _snap("from_town_" + String(d[1]))
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	# the highest point of the ground in town, looking out over the rest
	var best := -INF
	var top := mid
	for k in range(200):
		var p: Vector2 = mid + Vector2(randf_range(-500, 500), randf_range(-500, 500))
		if g._in_city(p) and g._h(p) > best:
			best = g._h(p)
			top = p
	var out: Vector2 = (top - mid).normalized() if top != mid else Vector2.RIGHT
	g.look_from(Vector3(top.x, best + 6.0, top.y), Vector3(top.x + out.x * 500.0, best + 40.0, top.y + out.y * 500.0))
	await _snap("from_the_hill")
	# up on a mountainside, looking along it
	var side: Vector2 = mid + Vector2(1, 0.3).normalized() * (g._bounds.size.x * 0.5 - 120.0)
	var sy: float = g._h(side)
	g.look_from(Vector3(side.x, sy + 30.0, side.y), Vector3(side.x - 60.0, sy, side.y + 300.0))
	await _snap("along_the_mountain")
	# the wind turbines on the crest, from 250 m off toward the town
	if not g._hubs.is_empty():
		var hub: Vector3 = g._hubs[g._hubs.size() / 2][0]
		var f3: Vector3 = g._hubs[g._hubs.size() / 2][1]
		var eye := hub + f3 * 250.0 + Vector3(0, -20.0, 0)
		g.look_from(eye, hub - Vector3(0, 15.0, 0))
		await _snap("turbines")
		print("turbines: %d" % g._hubs.size())
	quit(0)
