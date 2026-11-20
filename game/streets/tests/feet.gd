extends SceneTree
## A walker's feet on the pavement, close up from the side; and one waiting at a crossing.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.4).timeout
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
	var best: Node3D = null
	var bd := INF
	for w: Dictionary in g._walkers:
		var a: Node3D = w["actor"]
		if a.visible:
			var d := Vector2(a.position.x, a.position.z).distance_to(g._pos)
			if d < bd:
				bd = d
				best = a
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	if best != null:
		var p := Vector2(best.position.x, best.position.z)
		var hit: Dictionary = g._nearest_seg(p, 8.0, true, true)
		var away := ((hit["q"] as Vector2) - p).normalized() if not hit.is_empty() else Vector2(1, 0)
		var eye := p + away * 3.2 + Vector2(-away.y, away.x) * 0.8
		print("walker feet %.2f over the ground, pavement top %.2f over it" % [best.position.y - g._h(p), g._pave_top()])
		g.look_from(Vector3(eye.x, g._h(eye) + 0.9, eye.y), best.position + Vector3(0, 0.5, 0))
		await _snap("feet_%d" % lvl)
	quit(0)
