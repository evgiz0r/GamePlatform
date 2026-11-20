extends SceneTree
## The car driven straight across a median (the test town's, else the first found) at a few
## speeds: it gets over (a median is a kerb, not a wall), each axle's jolt slows it a little
## and the faster the harder, and it rides the kerb's height while on it. Shots from behind.
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
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
	await create_timer(1.0).timeout
	if g._medians.is_empty():
		print("no medians")
		quit(0)
		return
	# a long straight stretch of median, away from junctions
	var best := -1
	for i in range(g._median_r.size()):
		if (g._medians[i * 2] as Vector2).distance_to(g._medians[i * 2 + 1]) > 8.0:
			best = i
			break
	var a: Vector2 = g._medians[best * 2]
	var b: Vector2 = g._medians[best * 2 + 1]
	var mid := (a + b) * 0.5
	var across := Vector2(-(b - a).y, (b - a).x).normalized()
	for kmh: float in [10.0, 30.0, 50.0]:
		g._set_auto(false)
		g._pos = mid - across * 7.0
		g._yaw = across.angle()
		g._v = kmh / 3.6
		g._snap_pose()
		var v0: float = g._v
		var top := 0.0
		var crossed := false
		var shot := false
		for f in range(60 * 3):
			await physics_frame
			top = maxf(top, g._median_lift)
			if (g._pos - mid).dot(across) > 2.5:
				crossed = true
			if not shot and kmh == 30.0 and g._median_on[0]:
				shot = true
				g.look_from(Vector3(g._pos.x - across.x * 6.0 + 2.0, g._y + 2.5, g._pos.y - across.y * 6.0), Vector3(g._pos.x, g._y + 0.5, g._pos.y))
		print("%d km/h: got over %s, rode %.2f m up, %.1f km/h after" % [int(kmh), crossed, top, g._v * 3.6])
	quit(0)
