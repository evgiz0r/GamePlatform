extends SceneTree
## Junction corners that one look at their middle let in whole across a road: how many, and
## a look at the nearest few now.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)
func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var fixed: Array = []
	for e: Array in g._corner_cut_at:
		if e[1]:
			fixed.append(e[0])
	print("corners in pieces %d, of them the old look let in whole: %d" % [g._corner_cut_at.size(), fixed.size()])
	if OS.get_environment("OUT") == "":
		quit(0)
		return
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var start: Vector2 = g._pos
	fixed.sort_custom(func(a, b): return a.distance_to(start) < b.distance_to(start))
	for i in range(mini(3, fixed.size())):
		var p: Vector2 = fixed[i]
		var hit: Dictionary = g._nearest_seg(p, 30.0, true, true)
		var away := Vector2(1, 0)
		if not hit.is_empty():
			var pts: PackedVector2Array = g._roads[hit["road"]]["pts"]
			away = (pts[int(hit["seg"]) + 1] - pts[hit["seg"]]).normalized()
		var eye := p + away * 22.0 + Vector2(-away.y, away.x) * 3.0
		g._pos = eye
		g.look_from(Vector3(eye.x, g._h(eye) + 6.0, eye.y), Vector3(p.x, g._h(p), p.y))
		await _snap("corner_%d_%d" % [lvl, i])
	quit(0)
