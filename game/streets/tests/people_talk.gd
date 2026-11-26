extends SceneTree
## Hands while talking (streets.gd "hands while talking"): two people standing face to face
## on the road ahead of the car, talking (Talk), the first shot close, from in front
## and to one side, every 0.33 s for 8 s (pt_00.png ... pt_23.png). Good: a forearm comes up from the
## elbow in front of the body now and then, the hand moves a little, the arm goes down;
## never bent backwards, through the body or over the head.
##   OUT=... game/streets/tests/run.sh people_talk 4
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
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
	for w: Dictionary in g._walkers:
		(w["actor"] as Node3D).position.y -= 500.0
	var p: Vector2 = g._pos
	var fw := Vector3(cos(g._yaw), 0, sin(g._yaw))
	var rt := fw.cross(Vector3.UP)
	var base := Vector3(p.x, g._h(p) + 0.02, p.y) + fw * 7.0
	var two := []
	for i in range(2):
		var a = load("res://shell/actor3d.gd").new()
		g.world.add_child(a)
		a.set_character(g.PEOPLE[i + 1], 1.7)
		g._humanize(a, 300 + i)
		g._talk._talker(a, 11 + i * 5)
		a.position = base + rt * (0.55 if i == 0 else -0.55)
		a.play("Idle")
		a.face(-rt if i == 0 else rt)
		two.append(a)
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	# the first from in front and to one side, close: every 0.33 s for 8 s
	var me: Node3D = two[0]
	var c: Vector3 = me.global_position + Vector3(0, 0.9, 0)
	var face: Vector3 = me.global_transform.basis.z   # (the figures face +Z)
	for k in range(24):
		g.look_from(c + face * 2.0 + face.cross(Vector3.UP) * 1.2 + Vector3(0, 0.1, 0), c)
		g._sky_follow()
		await create_timer(0.33).timeout
		await _snap("pt_%02d" % k)
	quit(0)
