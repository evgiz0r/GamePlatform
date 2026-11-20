extends SceneTree
## One signalled junction watched for SECS seconds (KNOT_AT="x,z", LEVEL): the player's car
## parked out of the way, traffic coming and going. Every car that drives into one of the
## junction's signalled points on red (by the way it came in, once per junction, as the exam
## counts it) is printed with what it saw in the 4 s before: its distance to the point, its
## speed, what held it, the speed its light check allowed, and the light as it read it then.
## Lists the junction's points, its main road and groups first. Made for a junction in Ashdod
## where the exam kept counting traffic through on red.
var g: Node
var T

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	T = g._traffic
	var xz := (OS.get_environment("KNOT_AT") if OS.get_environment("KNOT_AT") != "" else "-1820,2354").split(",")
	var at := Vector2(float(xz[0]), float(xz[1]))
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 120.0
	# the junction's points
	var pts: Array = []
	for n: int in g._near(g._sig_hash, at, 60.0, g.SEG_CELL):
		if g._nodes[n].distance_to(at) < 60.0:
			pts.append(n)
	print("signalled points within 60 m of %s: %d" % [Vector2i(at), pts.size()])
	for n: int in pts:
		var owner: int = g._sig_owner.get(n, n)
		var names: Array = []
		for e: Vector2i in g._node_roads[n]:
			names.append("%s (%s)" % [(g._roads[e.x] as Dictionary)["en"], (g._roads[e.x] as Dictionary)["k"]])
		print("  point %d at %s, r %.1f, junction %d, roads %s" % [n, Vector2i(g._nodes[n]), g._node_r[n], owner, str(names)])
	# park out of the way: on a road 90-140 m off
	for ang in range(0, 360, 30):
		var q := at + Vector2.from_angle(deg_to_rad(ang)) * 110.0
		if g._land_on_road(q, 30.0, Vector2.ZERO) and g._pos.distance_to(at) > 80.0:
			break
	g._set_auto(false)
	var hist := {}       # car -> Array of [t, pos, v, why, light speed, light read]
	var inside := {}
	var came := {}
	var t := 0.0
	var dt := 1.0 / 60.0
	var reds := 0
	var entries := 0
	while t < secs:
		await physics_frame
		t += dt
		g._v = 0.0
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive or c.pos.distance_to(at) > 120.0:
				hist.erase(i)
				came.erase(i)
				continue
			var h: Array = hist.get(i, [])
			var lv: float = T._light_ahead(c)
			h.append([t, c.pos, c.v, c.why, lv])
			while h.size() > 0 and t - float(h[0][0]) > 4.0:
				h.pop_front()
			hist[i] = h
			var in_any := false
			for n: int in pts:
				if g._nodes[n].distance_to(c.pos) >= g._node_r[n] + 1.0:
					continue
				in_any = true
				var key := "%d:%d" % [i, g._sig_owner.get(n, n)]
				if not inside.has(key) and c.v > 2.0:
					entries += 1
					var cd: Vector2 = came.get(i, Vector2(sin(c.yaw), cos(c.yaw)))
					if g._light_at(n, cd) == "r":
						reds += 1
						if reds <= 12:
							print("RED: car %d (%s) into point %d at %.1f m/s, came %s, group %d, phase %d, last light at %.1f (s %.1f)" % [
								i, c.kind, n, c.v, cd, g._light_group(n, cd), g._sig_phase, c.last_light, c.s])
							for k in range(0, h.size(), 15):
								var e: Array = h[k]
								print("    t-%.1f  %.1f m from it, v %.1f, held by %s, light allows %s" % [
									t - float(e[0]), (e[1] as Vector2).distance_to(g._nodes[n]), e[2], e[3],
									"any" if float(e[4]) == INF else "%.1f" % float(e[4])])
				inside[key] = t
			if not in_any:
				came[i] = Vector2(sin(c.yaw), cos(c.yaw))
	print("KNOT: %d cars went in, %d of them on red, in %.0f s" % [entries, reds, secs])
	quit(0)
