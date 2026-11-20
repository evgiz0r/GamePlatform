extends SceneTree
## The street's cats and the flags on parked cars: how many of each the squares round the
## start got, then a close look at the nearest few, from a walker's eye height a couple of
## metres off (life_<kind>_<n>.png in $OUT). Near AT="x,z" when given, else the start.
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
	var at: Vector2 = g._pos
	var env := OS.get_environment("AT").split(",", false)
	if env.size() == 2:
		at = Vector2(float(env[0]), float(env[1]))
	for kind: String in ["cats_sit", "cats_loaf", "flags_on_cars"]:
		var list: Array = g._furn.where.get(kind, [])
		print("%s: %d" % [kind, list.size()])
		list.sort_custom(func(a, b): return Vector2(a.origin.x, a.origin.z).distance_to(at) < Vector2(b.origin.x, b.origin.z).distance_to(at))
		for i in range(mini(2, list.size())):
			var t: Transform3D = list[i]
			var fwd := t.basis.z if kind != "flags_on_cars" else t.basis.z
			var look := Vector2(fwd.x, fwd.z).normalized()
			var from := Vector2(t.origin.x, t.origin.z) + look * 2.2 + look.orthogonal() * 0.8
			var eye := Vector3(from.x, maxf(g._h(from) + 0.14, t.origin.y - 0.4) + 1.6, from.y)
			g.look_from(eye, t.origin + Vector3(0, 0.2 if kind != "flags_on_cars" else 0.3, 0))
			g._sky_follow()
			await _snap("life_%s_%d" % [kind, i])
	quit(0)
