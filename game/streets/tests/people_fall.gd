extends SceneTree
## Knocked down by the car (streets.gd _knock_down): the car driven at 6 m/s into two walkers
## and two people standing (a stop, a cafe table), the game's own driving and
## bumping doing the rest. Prints for each whether they fell, how long they were down and
## whether they were up and going again after; shots fa_<i>_<k> from the far side: k 0 the fall,
## 1 lying, 2 getting up, 3 up.
## Good: all four fall, each up again by DOWN_T (4.2 s) and walking or standing as before;
## nobody left lying, nobody sunk in the ground (a fall in place, on the pavement).
##   OUT=... game/streets/tests/run.sh people_fall 4
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
	await create_timer(2.0).timeout
	if not g._people_maker().on():
		print("old figures: nothing to test")
		quit(0)
		return
	var used := {}
	var fell := 0
	var up := 0
	for run in range(4):
		var lists: Array = [g._walkers] if run < 2 else [g._waiters, g._chatters]   # (not the shopkeepers: in their doorways, the shopfront stops the car first)
		var w: Dictionary = {}
		var best := INF
		for list: Array in lists:
			for c: Dictionary in list:
				var a: Node3D = c["actor"]
				var d := Vector2(a.position.x, a.position.z).distance_to(g._pos)
				if a.visible and not c.has("with") and not bool(c.get("sat", false)) and not used.has(a.get_instance_id()) \
						and d > 3.0 and d < best and float(c.get("startle", 0.0)) <= 0.0:
					best = d
					w = c
		if w.is_empty():
			print("%d: nobody left" % run)
			continue
		var a: Node3D = w["actor"]
		used[a.get_instance_id()] = true
		var pa := Vector2(a.position.x, a.position.z)
		var face: Vector2 = Vector2(cos(float(w.get("yaw", 0.0))), sin(float(w.get("yaw", 0.0)))) if run < 2 else (g._pos - pa).normalized()
		var from_dir: Vector2 = face.orthogonal() if run < 2 else face
		g._pos = pa + from_dir * 9.0
		g._prev_pos = g._pos
		g._snap_pose()
		var t := 0.0
		var t_fell := -1.0
		var touched := 0
		var closest := INF
		while t < 4.0 and t_fell < 0.0:
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			var q := Vector2(a.position.x, a.position.z)
			g._yaw = (q - g._pos).angle()
			g._v = 6.0
			if g._hit_who == a.get_instance_id():
				touched += 1
				g._hit_who = -1
			closest = minf(closest, g._body_gap(q, g._pos))
			if float(w.get("down", 0.0)) > 0.0:
				t_fell = t
		g._v = 0.0
		if t_fell < 0.0:
			print("%d: did not fall (the car's body came %.2f m off; touched them %d ticks; startle %.1f)" % [run, closest, touched, float(w.get("startle", 0.0))])
			continue
		fell += 1
		var side := Vector3(-from_dir.y, 0, from_dir.x)
		var k := 0
		var down_for := 0.0
		for wait: float in [0.15, 1.2, 1.6, 2.0]:
			await create_timer(wait).timeout
			down_for += wait
			var c: Vector3 = a.position + Vector3(0, 0.6, 0)
			g.look_from(c - Vector3(from_dir.x, 0, from_dir.y) * 3.4 + side * 1.2 + Vector3(0, 1.3, 0), c)   # (from the far side from the car)
			g._sky_follow()
			await _snap("fa_%d_%d" % [run, k])
			k += 1
		await create_timer(0.6).timeout
		var still_down := float(w.get("down", 0.0))
		var clip: String = a._clip
		print("%d (%s): fell at %.2f s; after %.1f s down %.2f, playing %s" % [run, "walker" if run < 2 else "standing", t_fell, down_for + 0.6, still_down, clip])
		if still_down <= 0.0 and clip != "Fall" and clip != "GetUp":
			up += 1
		g._pos += from_dir * 12.0   # (the car away, out of their path)
		g._prev_pos = g._pos
		await create_timer(0.5).timeout
	print("PASS %d/4 fell, %d/4 up and going again" % [fell, up])
	quit(0)
