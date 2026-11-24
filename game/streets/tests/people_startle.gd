extends SceneTree
## People startled by the car (streets.gd's walkers, "a car about to hit them"): the car is
## sent at 8 m/s straight at a walker in view, three times, and then past three others 2.2 m to
## their side (a car going by, not at them). Prints for each whether they started (the
## Startled clip), when, and how close the car's body came; shots st_<i>_at_<k>.png, four
## frames of each start (0.1 to 0.7 s), from beside, in $OUT.
## Then the car at three people standing still (stops, shop doors, cafe tables): st_still_<i>.
## Good: every one driven at starts back, with the car 3-6 m off; none of those driven past
## starts; the standing ones start too and step about 0.4 m.
##   OUT=... game/streets/tests/run.sh people_startle 4
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
	var used := {}
	var at_ok := 0
	var by_bad := 0
	for run in range(6):
		var past := run >= 3
		# a walker in view, walking, not used yet
		var w: Dictionary = {}
		var best := INF
		for c: Dictionary in g._walkers:
			var a: Node3D = c["actor"]
			var d := Vector2(a.position.x, a.position.z).distance_to(g._pos)
			if a.visible and not c.has("with") and not used.has(a.get_instance_id()) and d > 4.0 and d < best and float(c.get("startle", 0.0)) <= 0.0:
				best = d
				w = c
		if w.is_empty():
			print("no walker left")
			break
		var a: Node3D = w["actor"]
		used[a.get_instance_id()] = true
		var pa := Vector2(a.position.x, a.position.z)
		var heading := Vector2(cos(float(w.get("yaw", 0.0))), sin(float(w.get("yaw", 0.0))))
		var aim := pa + heading * float(w.get("anim_v", w["speed"])) * 1.6   # (where they will be: at their pace now, 0 if stopped at a kerb)
		var from_dir := heading.orthogonal()   # (from their side, as from the road)
		var start := aim + from_dir * 13.0
		var d := (aim - start).normalized()
		if past:
			start += d.orthogonal() * (2.2 + 0.9)   # (its middle: its side 2.2 m off them)
		g._pos = start
		g._yaw = d.angle()
		g._v = 8.0
		g._snap_pose()
		var t := 0.0
		var started := -1.0
		var gap_then := 0.0
		var closest := INF
		while t < 2.6:
			await process_frame
			var dt: float = g.get_process_delta_time()
			t += dt
			g._pos += d * 8.0 * dt
			g._yaw = d.angle()
			g._v = 8.0
			g._snap_pose()
			var p := Vector2(a.position.x, a.position.z)
			closest = minf(closest, g._body_gap(p, g._pos))
			if started < 0.0 and float(w.get("startle", 0.0)) > 0.0:
				started = t
				gap_then = g._body_gap(p, g._pos)
				# a few frames of the start, from beside them (the car held where it is meanwhile)
				var c: Vector3 = a.position + Vector3(0, 1.0, 0)
				var side := Vector3(d.y, 0, -d.x)
				for k in range(4):
					await create_timer(0.08 if k == 0 else 0.2).timeout
					c = a.position + Vector3(0, 1.0, 0)
					g.look_from(c + side * 2.6 + Vector3(0, 0.3, 0), c)
					g._sky_follow()
					await _snap("st_%d_at_%d" % [run, k])
		var said := "started at %.2f s, the car's body %.1f m off" % [started, gap_then] if started >= 0.0 else "did not start"
		print("%s %d: %s; closest %.2f m" % ["past" if past else "at", run, said, closest])
		if not past and started >= 0.0:
			at_ok += 1
		if past and started >= 0.0 and closest > 1.2:
			by_bad += 1   # (passing them, it is fair to start only if it came within a metre or so)
		g._v = 0.0
		await create_timer(0.5).timeout
	# people standing still (at a stop, a shop door, a cafe table): the car at three of them,
	# from the way they face
	var still_ok := 0
	var still_n := 0
	for run in range(3):
		var c: Dictionary = {}
		var best := INF
		for list: Array in [g._waiters, g._keepers, g._chatters]:
			for o: Dictionary in list:
				var a: Node3D = o["actor"]
				var d := Vector2(a.position.x, a.position.z).distance_to(g._pos)
				if a.visible and not bool(o.get("sat", false)) and not used.has(a.get_instance_id()) and d < best:
					best = d
					c = o
		if c.is_empty():
			print("no one standing left")
			break
		var a: Node3D = c["actor"]
		used[a.get_instance_id()] = true
		var pa := Vector2(a.position.x, a.position.z)
		var face := Vector2(-a.global_transform.basis.z.x, -a.global_transform.basis.z.z)
		if face.length() < 0.1:
			face = Vector2(1, 0)
		face = face.normalized()
		if (g._pos - pa).dot(face) < 0.0 and (g._pos - pa).length() > 1.0:
			face = (g._pos - pa).normalized()   # (whichever way the model faces: from our side)
		var start := pa + face * 13.0
		var d := (pa - start).normalized()
		g._pos = start
		g._yaw = d.angle()
		g._v = 8.0
		g._snap_pose()
		var t := 0.0
		var started := -1.0
		var gap_then := 0.0
		var moved := 0.0
		while t < 2.6:
			await process_frame
			var dt: float = g.get_process_delta_time()
			t += dt
			if started < 0.0:
				g._pos += d * 8.0 * dt
			g._yaw = d.angle()
			g._v = 8.0 if started < 0.0 else 0.0
			g._snap_pose()
			var p := Vector2(a.position.x, a.position.z)
			moved = maxf(moved, p.distance_to(pa))
			if started < 0.0 and float(c.get("startle", 0.0)) > 0.0:
				started = t
				gap_then = g._body_gap(p, g._pos)
				var cc: Vector3 = a.position + Vector3(0, 1.0, 0)
				var side := Vector3(d.y, 0, -d.x)
				for k in range(3):
					await create_timer(0.08 if k == 0 else 0.25).timeout
					cc = a.position + Vector3(0, 1.0, 0)
					g.look_from(cc + side * 2.6 + Vector3(0, 0.3, 0), cc)
					g._sky_follow()
					await _snap("st_still_%d_at_%d" % [run, k])
		still_n += 1
		var said := "started at %.2f s, the car's body %.1f m off, stepped %.2f m" % [started, gap_then, moved] if started >= 0.0 else "did not start"
		print("still %d: %s" % [run, said])
		if started >= 0.0:
			still_ok += 1
		g._v = 0.0
		await create_timer(0.5).timeout
	print("PASS %d/3 driven at started, %d/3 driven past started, %d/%d standing started" % [at_ok, by_bad, still_ok, still_n])
	quit(0)
