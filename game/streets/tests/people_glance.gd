extends SceneTree
## People glancing at you (people.gd Glance) and the collar's line (people.gd COLLAR_Y): three
## people side by side facing along the road, you put 4 m to their right; they turn their heads
## to you and back after a couple of seconds. Prints each one's head turn over time; shots
## gl_<i>_turned (a second in), gl_<i>_back (four seconds in) of each face, and gl_<i>_collar,
## the neck and shoulders up close, in $OUT.
## Good: the turn rises to ~0.8-1.1 (radians, about the up) within a second, is back to 0 by
## four; the faces in _turned look to their right; the collar is a clean line, no zigzag.
##   OUT=... game/streets/tests/run.sh people_glance 4
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _glance(a: Node3D) -> Object:
	for m in a.model.find_children("*", "SkeletonModifier3D", true, false):
		if m.get_script() != null and m.has_method("_process_modification_with_delta") and "curious" in m:
			return m
	return null

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if not g._people_maker().on():
		print("old figures: nothing to test")
		quit(0)
		return
	for w: Dictionary in g._walkers:
		(w["actor"] as Node3D).position.y -= 500.0
	var p: Vector2 = g._pos
	var y: float = g._h(p) + 0.02
	var fw := Vector3(cos(g._yaw), 0, sin(g._yaw))
	var rt := fw.cross(Vector3.UP)
	var base := Vector3(p.x, y, p.y) + fw * 7.0
	var made := []
	for i in range(3):
		var a = load("res://shell/actor3d.gd").new()
		g.world.add_child(a)
		a.set_character(g.PEOPLE[i % g.PEOPLE.size()], 1.72)
		g._humanize(a, 5000 + i * 11)
		g._people_lod(a)
		a.position = base + rt * (float(i) * 1.2 - 1.2)
		a.play("Idle", true)
		a.face(-fw)   # facing the camera's way back
		var gl = _glance(a)
		if gl != null:
			gl.curious = true
		made.append(a)
	await create_timer(0.5).timeout
	process_frame.disconnect(g._frame)
	g.set_physics_process(false)
	var me: Vector3 = base + rt * 4.0 + Vector3(0, 1.55, 0) - fw * 1.5   # to their right (they face -fw: their right is +rt... measured, not assumed)
	g._ppl.me_at(me)
	var t := 0.0
	var shot := {1.0: "turned", 4.0: "back"}
	while t < 4.05:
		await process_frame
		t += g.get_process_delta_time()
		var line := "t %.2f:" % t
		for a in made:
			line += " %.2f" % _glance(a).turn
		if fmod(t, 0.5) < g.get_process_delta_time():
			print(line)
		for k: float in shot.keys():
			if t >= k:
				for i in range(made.size()):
					var c: Vector3 = (made[i] as Node3D).global_position + Vector3(0, 1.6, 0)
					g.look_from(c - fw * 1.1 + Vector3(0, 0.05, 0), c)
					g._sky_follow()
					await _snap("gl_%d_%s" % [i, shot[k]])
				shot.erase(k)
				g._ppl.me_at(me)
	g._ppl.me_at(Vector3(1e9, 0, 0))
	for i in range(made.size()):
		var c: Vector3 = (made[i] as Node3D).global_position + Vector3(0, 1.4, 0)
		g.look_from(c - fw * 0.7 + rt * 0.2 + Vector3(0, 0.1, 0), c)
		g._sky_follow()
		await _snap("gl_%d_collar" % i)
	quit(0)
