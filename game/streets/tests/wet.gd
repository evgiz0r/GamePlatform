extends SceneTree
## After rain (the "wet" button): the same views dry and wet -- down the start street from a
## car, a straight street looking towards the sun and away from it, and at a walker's eye
## height down at the pavement -- by day and in the evening (low sun: the glare). Shots
## wet_<view>_<time>_<dry|wet>.png in $OUT.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	var p: Vector2 = g._pos
	var f: Vector2 = g._fwd()
	var side := Vector2(-f.y, f.x)
	var walk := p + side * 7.0
	var views := {
		"street": [Vector3(p.x - f.x * 6, g._h(p) + 3.2, p.y - f.y * 6), Vector3(p.x + f.x * 80, g._h(p + f * 80), p.y + f.y * 80)],
		"back": [Vector3(p.x + f.x * 6, g._h(p) + 1.6, p.y + f.y * 6), Vector3(p.x - f.x * 80, g._h(p - f * 80), p.y - f.y * 80)],
		"pavement": [Vector3(walk.x, g._h(walk) + 1.7, walk.y), Vector3(walk.x + f.x * 6, g._h(walk), walk.y + f.y * 6)],
	}
	for time: String in ["day", "evening"]:
		if time == "evening":
			await g._set_evening(true)
		for state: String in ["dry", "wet"]:
			g._wet_k = 1.0 if state == "wet" else 0.0
			g._far_update()
			for v: String in views:
				g.look_from(views[v][0], views[v][1])
				g._sky_follow()
				await _snap("wet_%s_%s_%s" % [v, time, state])
	quit(0)
