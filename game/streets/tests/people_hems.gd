extends SceneTree
## The hems (people.gd's limbs in _join): four people in a row, 7 m ahead of the car, facing it
## -- a man in shorts, a woman in a skirt, someone in short sleeves, someone in long ones (seeds
## searched for each). Shots hem_<i>_legs (knees, from the front and a little above) and
## hem_<i>_arm (an arm, from beside) in $OUT.
## Good: every hem a straight line across the limb -- the shorts and skirt a hand above the
## knee, a short sleeve halfway down the upper arm, a long one at the wrist -- no zigzag.
##   OUT=... game/streets/tests/run.sh people_hems 4
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.3).timeout
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
	if not g._people_maker().on():
		print("old figures: nothing to test")
		quit(0)
		return
	for list: Array in [g._walkers, g._chatters, g._waiters, g._keepers, g._sitters]:
		for w: Dictionary in list:
			(w["actor"] as Node3D).position.y -= 500.0
	var p: Vector2 = g._pos
	var y: float = g._h(p) + 0.02
	var fw := Vector3(cos(g._yaw), 0, sin(g._yaw))
	var rt := fw.cross(Vector3.UP)
	var base := Vector3(p.x, y, p.y) + fw * 7.0
	var want := [
		func(c): return c["shorts"] and not c["female"],
		func(c): return c["shorts"] and c["female"] and not c["dress"],
		func(c): return not c["long_sleeves"] and not c["shorts"],
		func(c): return c["long_sleeves"],
	]
	var names := ["shorts", "skirt", "short sleeves", "long sleeves"]
	var made := []
	for i in range(want.size()):
		var a = null
		for seed in range(6000, 6400):
			var t = load("res://shell/actor3d.gd").new()
			g.world.add_child(t)
			g._set_character(t, g.PEOPLE[(seed + i) % g.PEOPLE.size()], 1.72)
			g._humanize(t, seed)
			if t.has_meta("clothes") and want[i].call(t.get_meta("clothes")):
				a = t
				print("%d %s: seed %d %s" % [i, names[i], seed, t.get_meta("clothes")])
				break
			t.queue_free()
		if a == null:
			print("%d %s: none in 400 seeds" % [i, names[i]])
			continue
		g._people_lod(a)
		a.position = base + rt * (float(i) * 1.3 - 2.0)
		a.play("Idle", true)
		a.face(-fw)
		made.append(a)
	await create_timer(0.6).timeout
	process_frame.disconnect(g._frame)
	g.set_physics_process(false)
	for i in range(made.size()):
		var a: Node3D = made[i]
		var k: Vector3 = a.global_position + Vector3(0, 0.5, 0)
		g.look_from(k - fw * 1.3 + Vector3(0, 0.25, 0), k)
		g._sky_follow()
		await _snap("hem_%d_legs" % i)
		var e: Vector3 = a.global_position + Vector3(0, 1.15, 0) + rt * 0.25
		g.look_from(e + rt * 1.1 - fw * 0.3, e)
		g._sky_follow()
		await _snap("hem_%d_arm" % i)
	print("PASS shots of %d" % made.size())
	quit(0)
