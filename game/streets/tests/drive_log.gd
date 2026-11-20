extends SceneTree
## The drive recorder: 60 s of autodrive, then the map page (a screenshot) and "save log"
## (its path printed: draw it with tests/drive_log_map.py).
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
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
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	g._set_auto(true)
	for f in range(60 * int(OS.get_environment("SECS") if OS.get_environment("SECS") != "" else "60")):
		await physics_frame
	print("samples %d, events %d" % [g._log.samples.size(), g._log.events.size()])
	g._toggle_perf()
	g._toggle_perf()   # (the second page: the drive map)
	if OS.get_environment("OUT") != "":
		await _snap("drive_map")
	print("saved ", g._log.save(g))
	quit(0)
