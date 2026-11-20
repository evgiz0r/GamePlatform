extends SceneTree
## Traffic lights: how many junctions with lights (sites, see the game's _lights_setup) and
## walk lights; a close look at a junction's lights and walk lights; then 90 s of autodrive and
## traffic counting moments when two cars from crossing ways move inside one signalled junction
## together (a conflict the lights should prevent). Good: conflicts near zero. light_audit.gd
## checks every junction's groups, stop lines and walk lights.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.6).timeout
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
	print("junctions with lights %d (%d points), walk lights %d" % [g._sites.size(), g._lit.size(), int(g._dressing.get("walk_lights", 0))])
	# a close look: the signalled junction nearest the start
	var best := INF
	var jn := -1
	for j: int in g._lit:
		if g._nodes[j].distance_to(g._pos) < best:
			best = g._nodes[j].distance_to(g._pos)
			jn = j
	if OS.get_environment("OUT") != "" and not g._light_spots.is_empty():
		# close up, from where nothing (a tree, a pole) stands between: a car's light from its
		# stop line, then a walk light from across the street
		g.set_physics_process(false)
		process_frame.disconnect(g._frame)
		for which: Array in [[g._light_spots, 6.0, 1.4, "light_close"], [g._walk_spots, 4.0, 0.9, "walk_close"]]:
			var spots: Array = (which[0] as Array).duplicate()
			spots.sort_custom(func(a, b): return Vector2(a[0].x, a[0].z).distance_to(g._pos) < Vector2(b[0].x, b[0].z).distance_to(g._pos))
			for sp: Array in spots.slice(0, 40):
				var hd: Vector3 = sp[0]
				var fc: Vector2 = sp[1]
				var at := Vector2(hd.x, hd.z) + fc * float(which[1])
				var clear := true
				for k in range(1, 10):
					var q := Vector2(hd.x, hd.z).lerp(at, k / 10.0)
					for i: int in g._near(g._post_hash, q, 1.2, g.BLD_CELL):
						if (g._posts[i] as Vector2).distance_to(q) < 1.0 and (g._posts[i] as Vector2).distance_to(Vector2(hd.x, hd.z)) > 0.5:
							clear = false
				if not clear:
					continue
				g.look_from(Vector3(at.x, hd.y - float(which[2]), at.y), hd)
				await _snap(which[3])
				g._sig_phase = (g._sig_phase + g.SIGNAL_CYCLE.size() / 2) % g.SIGNAL_CYCLE.size()
				g._apply_signals()
				await _snap(String(which[3]) + "_other")
				break
		process_frame.connect(g._frame)
		g.set_physics_process(true)
		if OS.get_environment("SHOTS_ONLY") != "":
			quit(0)
			return
	if jn >= 0 and OS.get_environment("OUT") != "" and OS.get_environment("WIDE") != "":
		g.set_physics_process(false)
		var c: Vector2 = g._nodes[jn]
		var din: Vector2 = (g._sig_line[jn][0] as Array)[0]
		var eye := c - din * 26.0 + Vector2(-din.y, din.x) * 3.0
		g._pos = eye
		g._yaw = din.angle()
		g._snap_pose()
		process_frame.disconnect(g._frame)
		g.look_from(Vector3(eye.x, g._h(eye) + 2.0, eye.y), Vector3(c.x, g._h(c) + 2.5, c.y))
		await _snap("lights_a")
		g._sig_phase = (g._sig_phase + g.SIGNAL_CYCLE.size() / 2) % g.SIGNAL_CYCLE.size()
		g._apply_signals()
		await _snap("lights_b")
		process_frame.connect(g._frame)
		g.set_physics_process(true)
		g._land_on_road(g._nodes[jn] - din * 60.0, 40.0, din)
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	g._set_auto(true)
	var T = g._traffic
	var conflicts := 0
	var counted := {}
	for f in range(60 * 90):
		await physics_frame
		var movers: Array = []
		for c in T.cars:
			if c.alive and c.v > 2.0:
				movers.append([c.pos, Vector2(sin(c.yaw), cos(c.yaw))])
		if absf(g._v) > 2.0:
			movers.append([g._pos, g._fwd() * signf(g._v)])
		for j: int in g._lit:
			var cj: Vector2 = g._nodes[j]
			var inside: Array = movers.filter(func(m): return (m[0] as Vector2).distance_to(cj) < g._node_r[j] + 2.0)
			for a in range(inside.size()):
				for b in range(a + 1, inside.size()):
					if absf((inside[a][1] as Vector2).dot(inside[b][1])) < 0.5:
						var key := "%d:%d" % [j, f / 120]
						if not counted.has(key):
							counted[key] = true
							conflicts += 1
	print("90 s: moments two cars from crossing ways moved inside one signalled junction together: %d" % conflicts)
	quit(0)
