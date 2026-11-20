extends SceneTree
## People crossing a divided road's zebra: placed along the whole span, looked at from above.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.6).timeout
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
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var start: Vector2 = g._pos
	var picks: Array = []
	for ni: int in g._crossing_nodes:
		var z: Array = g._zebra_geom(ni)
		if z.is_empty() or not (g._roads[int(z[4])] as Dictionary).has("median"):
			continue
		var span: Array = g._zebra_span(z)
		if span.is_empty():
			continue
		picks.append([g._nodes[ni].distance_to(start), z, span])
	picks.sort_custom(func(a, b): return a[0] < b[0])
	print("dual-road zebras with a span: ", picks.size())
	var shots := 0
	for pk in picks:
		if shots >= 2:
			break
		var z: Array = pk[1]
		var span: Array = pk[2]
		var a: Vector2 = span[0]
		var b: Vector2 = span[1]
		print("span %.1f m (half %.1f, median %.1f)" % [a.distance_to(b), float(z[2]), float((g._roads[int(z[4])] as Dictionary)["median"])])
		for i in range(g._crossers.size()):
			var cr: Dictionary = g._crossers[i]
			var act: Node3D = cr["actor"]
			var t := float(i) / float(g._crossers.size() - 1)
			var p: Vector2 = a.lerp(b, t)
			act.position = Vector3(p.x, g._h(p), p.y)
			act.visible = true
		var mid := (a + b) * 0.5
		var way: Vector2 = z[3]
		var eye: Vector2 = mid + way * 16.0 + (b - a).normalized() * 4.0
		g._pos = eye
		g.look_from(Vector3(eye.x, g._h(eye) + 7.0, eye.y), Vector3(mid.x, g._h(mid), mid.y))
		await _snap("dualzebra_%d_%d" % [lvl, shots])
		shots += 1
	quit(0)
