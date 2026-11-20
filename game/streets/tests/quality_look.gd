extends SceneTree
## The road's surface texture at quality 3 and quality 0, at the start and 600 m away.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 1})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var start: Vector2 = g._pos
	print("start at ", Vector2i(start))
	await _snap("tex_start_q3")
	g._set_quality(0)
	await _snap("tex_start_q0")
	# somewhere 600 m off along a street
	var far := Vector2.ZERO
	var fy := 0.0
	for r: Dictionary in g._roads:
		if r["drive"] and r["k"] == "residential":
			var pts: PackedVector2Array = r["pts"]
			if pts.size() >= 2 and absf(pts[0].distance_to(start) - 600.0) < 40.0:
				far = pts[0]
				fy = (pts[1] - pts[0]).angle()
				break
	g._pos = far
	g._yaw = fy
	g._snap_pose()
	print("far at ", Vector2i(far))
	await _snap("tex_far_q0")
	g._set_quality(3)
	await _snap("tex_far_q3")
	quit(0)
