extends SceneTree
## What hangs on the blocks' walls, near the start (AT="x,z" elsewhere): how many AC units
## (on arms; up on a balcony's back wall), racks of washing and towels over parapets the
## squares round it got, then a look at the nearest of each from the street, a walker's eye
## a few metres off (shots wt_*.png in $OUT); and a person up close (one piece:
## streets.gd _one_piece), with the parts' colours where they belong.
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
	var at: Vector2 = g._pos
	var env := OS.get_environment("AT").split(",", false)
	if env.size() == 2:
		at = Vector2(float(env[0]), float(env[1]))
	print("ac units %s, washing racks %s, towels %s" % [g._dressing.get("ac_units", 0), g._dressing.get("washing_racks", 0),
		g._dressing.get("towels", 0)])
	# a person up close, before the camera is taken over (people move with the frame)
	var best: Node3D = null
	for w: Dictionary in g._walkers:
		var a: Node3D = w["actor"]
		if a.visible and (best == null or Vector2(a.position.x, a.position.z).distance_to(at) < Vector2(best.position.x, best.position.z).distance_to(at)):
			best = a
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	if best != null:
		var mis := best.find_children("*", "MeshInstance3D", true, false)
		var surf := 0
		for mi: MeshInstance3D in mis:
			surf += mi.mesh.get_surface_count()
		print("a person: %d meshes, %d surfaces (one piece: 1)" % [mis.size(), surf])
		var fw := best.global_transform.basis.z   # (the figures face +Z: Actor3D.face)
		var p := best.global_position
		g.look_from(p + fw * 2.4 + Vector3(0, 1.5, 0) + best.global_transform.basis.x * 0.6, p + Vector3(0, 1.0, 0))
		g._sky_follow()
		await _snap("wt_person")
	for kind: String in ["ac", "ac_balcony", "washing", "towels"]:
		var list: Array = (g.wall_things.get(kind, []) as Array).duplicate()
		if list.is_empty():
			print("%s: none" % kind)
			continue
		list.sort_custom(func(a, b): return Vector2(a.origin.x, a.origin.z).distance_to(at) < Vector2(b.origin.x, b.origin.z).distance_to(at))
		var t: Transform3D = list[0]
		var out := t.basis.z.normalized()   # (out of the wall)
		var side := out.cross(Vector3.UP).normalized()
		var foot := t.origin
		var ground: float = g._h(Vector2(foot.x, foot.z))
		var eye := foot + out * 6.0 + side * 2.0
		eye.y = maxf(ground + 1.7, foot.y - 4.0)
		print("%s: %d kept, nearest %d m, %.1f m up" % [kind, list.size(), int(Vector2(foot.x, foot.z).distance_to(at)), foot.y - ground])
		g.look_from(eye, foot + Vector3(0, -0.2, 0))
		g._sky_follow()
		await _snap("wt_" + kind)
	quit(0)
