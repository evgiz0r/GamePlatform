extends SceneTree
## Traffic lights: how many junctions got their groups from their own main road where the old
## east-west / north-south rule put two different streets in the same group (both green at
## once); then 90 s of autodrive and traffic counting moments when two cars from crossing ways
## move inside one signalled junction together (a conflict the lights should prevent), and a
## close look at a junction's lights and walk lights. Good: conflicts near zero.
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
	var regrouped := 0
	for j: int in g._sig_ap:
		var ap: Array = g._sig_ap[j]
		for a: Array in ap:
			for b: Array in ap:
				var da: Vector2 = a[0]
				var db: Vector2 = b[0]
				var old_a := 1 if absf(da.x) >= absf(da.y) else 2
				var old_b := 1 if absf(db.x) >= absf(db.y) else 2
				if absf(da.dot(db)) < 0.7 and old_a == old_b and a[1] != b[1]:
					regrouped += 1
	print("signalled junctions %d, walk lights %d; crossing pairs of ways the old rule had green together: %d" % [g._sig_ap.size(), int(g._dressing.get("walk_lights", 0)), regrouped / 2])
	# a close look: the signalled junction nearest the start
	var best := INF
	var jn := -1
	for j: int in g._sig_ap:
		if g._nodes[j].distance_to(g._pos) < best:
			best = g._nodes[j].distance_to(g._pos)
			jn = j
	if jn >= 0 and OS.get_environment("OUT") != "":
		g.set_physics_process(false)
		var c: Vector2 = g._nodes[jn]
		var ap: Array = g._sig_ap[jn]
		var din: Vector2 = (ap[0] as Array)[0]
		var eye := c - din * 26.0 + Vector2(-din.y, din.x) * 3.0
		g._pos = eye
		g._yaw = din.angle()
		g._snap_pose()
		process_frame.disconnect(g._frame)
		g.look_from(Vector3(eye.x, g._h(eye) + 2.0, eye.y), Vector3(c.x, g._h(c) + 2.5, c.y))
		await _snap("lights_a")
		g._sig_phase = (g._sig_phase + 3) % g.SIGNAL_CYCLE.size()
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
		for j: int in g._sig_ap:
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
