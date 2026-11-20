extends SceneTree
## Frame time per quality level (software rendering here: only the ratios mean anything).
var g: Node
func _initialize() -> void:
	_run()
func _avg(label: String, n := 12) -> void:
	await process_frame
	await process_frame
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		await process_frame
	var v: SubViewport = g.view
	print("%-28s %6.1f ms   tris %8d (+%8d shadow) draws %d" % [label, (Time.get_ticks_usec() - t0) / 1000.0 / n,
		v.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		v.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		v.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)])
func _run() -> void:
	await create_timer(0.5).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_auto(true)
	await create_timer(3.0).timeout
	g.set_physics_process(false)
	for q in [3, 2, 1, 0]:
		g._set_quality(q)
		await _avg("quality %d" % q)
	g.sun.shadow_enabled = false
	g._set_quality(3)
	g.sun.shadow_enabled = false
	await _avg("quality 3, no shadows")
	quit(0)
