extends SceneTree
## Autodrive's pace through roundabouts. A user: "driver pauses before roundabout exits,
## shouldn't. In general he is very defensive in its driving, somewhat slow" (Givatayim, a small
## roundabout on a main road, 13 km/h on the ring).
## For RB_N roundabouts (default 6; away from the places tests/pick_routes.py keeps away from)
## it drives in from one arm and out of the one most nearly straight across, from 70 m back to
## 80 m out, no traffic (TRAFFIC=1 for traffic). Per ring: its radius, the speed coming to the
## ring, the slowest on the ring and why, the slowest from the ring's edge to 25 m out (the exit)
## and why, any standing (where and why), and the time from 30 m before the ring to 30 m after.
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/rb_pace.gd
## VERBOSE=1 prints the speed and why every quarter second near the ring. WANDER=1: no
## destination -- autodrive picks its own way (it plans a ring only to its next exit, then
## the next piece), out of whichever arm it takes.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	if OS.get_environment("TRAFFIC") != "1":
		for c in g._traffic.cars:
			c.alive = false
			c.retry = 1.0e9
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	# the rings: ring roads joined by shared points
	var ring_of := {}   # node -> ring id
	var rings: Array = []   # [nodes dict]
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r.get("ring", false):
			continue
		var ids: PackedInt32Array = r["ids"]
		var hit := -1
		for n in ids:
			if ring_of.has(n):
				hit = ring_of[n]
		if hit < 0:
			hit = rings.size()
			rings.append({})
		for n in ids:
			(rings[hit] as Dictionary)[n] = true
			ring_of[n] = hit
	var want := int(OS.get_environment("RB_N")) if OS.get_environment("RB_N") != "" else 6
	var done := 0
	var rows: Array = []
	for ring: Dictionary in rings:
		if done >= want:
			break
		var mid := Vector2.ZERO
		for n: int in ring:
			mid += g._nodes[n]
		mid /= ring.size()
		var rad := 0.0
		for n: int in ring:
			rad = maxf(rad, (g._nodes[n] as Vector2).distance_to(mid))
		if rad < 4.0 or rad > 30.0 or not g._in_city(mid) or priv.near(avoid, mid):
			continue
		# its arms: drivable roads off the ring at its points, [point, way out (unit), can come in]
		var arms: Array = []
		for n: int in ring:
			for e: Vector2i in g._node_roads[n]:
				var r: Dictionary = g._roads[e.x]
				if not r["drive"] or r.get("ring", false) or r["pv"] or r["k"] == "service":
					continue
				var pts: PackedVector2Array = r["pts"]
				var dd := 1 if e.y == 0 else -1
				if e.y != 0 and e.y != pts.size() - 1:
					continue
				var out := (pts[e.y + dd] - pts[e.y]).normalized()
				var can_in: bool = int(r["o"]) == 0 or int(r["o"]) == -dd
				var can_out: bool = int(r["o"]) == 0 or int(r["o"]) == dd
				arms.append([n, out, can_in, can_out, String(r["en"])])
		var best: Array = []
		var best_dot := 0.0
		for a: Array in arms:
			if not a[2]:
				continue
			for b: Array in arms:
				if not b[3] or b[0] == a[0]:
					continue
				var dot: float = -(a[1] as Vector2).dot(b[1])   # (in along -a, out along b: straight across is 1)
				if dot > best_dot:
					best_dot = dot
					best = [a, b]
		if best.is_empty() or best_dot < 0.3:
			continue
		var row: Dictionary = await _through(mid, rad, best[0], best[1])
		if row.is_empty():
			continue
		done += 1
		rows.append(row)
		print("RB %s" % JSON.stringify(row))
	var pauses := 0
	var off := 0
	var ring_kmh: Array = []
	var exit_kmh: Array = []
	for r: Dictionary in rows:
		if not r.has("ring_min_kmh"):
			continue
		if float(r["exit_min_kmh"]) < 5.0 or float(r["ring_min_kmh"]) < 5.0:
			pauses += 1
		if float(r["off_asphalt_m"]) > 0.8:
			off += 1
		ring_kmh.append(r["ring_min_kmh"])
		exit_kmh.append(r["exit_min_kmh"])
	ring_kmh.sort()
	exit_kmh.sort()
	print("RB PACE: %d roundabouts, %d with a pause on the ring or at the exit (under 5 km/h), %d off the asphalt (0.8 m+); slowest on the ring %s km/h, at the exit %s" % [
		rows.size(), pauses, off, str(ring_kmh), str(exit_kmh)])
	quit(0)

func _through(mid: Vector2, rad: float, a: Array, b: Array) -> Dictionary:
	var entry: Vector2 = g._nodes[a[0]]
	var din: Vector2 = -(a[1] as Vector2)
	g._set_auto(false)
	if not g._land_on_road(entry - din * 70.0, 10.0, din):
		return {}
	g._v = 0.0
	await physics_frame
	var dest: Vector2 = (g._nodes[b[0]] as Vector2) + (b[1] as Vector2) * 80.0
	var wander := OS.get_environment("WANDER") != ""
	if wander:
		g._clear_dest()
	else:
		g._set_dest(dest, "roundabout test")
	g._set_auto(true)
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var at_ring := -1.0
	var ring_min := INF
	var ring_why := ""
	var exit_min := INF
	var exit_why := ""
	var t_in := -1.0
	var t_out := -1.0
	var phase := 0   # 0 coming, 1 on the ring, 2 out of it
	var stood := 0.0
	var stands: Array = []
	var tick := 0
	var dumped := false
	var off_max := 0.0   # (the car's middle off the asphalt, at most: a bend cut onto the island or the pavement)
	while t < 60.0:
		await physics_frame
		t += dt
		tick += 1
		var d: float = (g._pos as Vector2).distance_to(mid)
		if OS.get_environment("PLAN") != "" and not dumped and d < rad + 25.0:
			dumped = true   # (the plan through the ring: each point's distance from the middle, its speed, the bend there)
			var out: Array = []
			for k in range(1, g._ap_pts.size() - 1):
				var pk: Vector2 = g._ap_pts[k]
				if pk.distance_to(mid) < rad + 20.0:
					var a2: Vector2 = g._ap_walk(k, -5.0)
					var c2: Vector2 = g._ap_walk(k, 5.0)
					var cr := absf((pk - a2).cross(c2 - a2))
					var rr := INF if cr < 0.001 else a2.distance_to(pk) * pk.distance_to(c2) * c2.distance_to(a2) / (2.0 * cr)
					out.append("%.0f m out %.1f km/h r %.1f (%.1f to next)" % [pk.distance_to(mid), g._ap_v[k] * 3.6, rr, pk.distance_to(g._ap_pts[k + 1])])
			print("  plan: " + " | ".join(out))
		var v: float = absf(g._v)
		if t_in < 0.0 and d < rad + 30.0:
			t_in = t
		if d < rad + 30.0:
			var on: Dictionary = g._nearest_seg(g._pos, 30.0, true, true)
			off_max = maxf(off_max, float(on["edge"]) if not on.is_empty() else 99.0)
		if phase == 0 and d < rad + 2.0:
			phase = 1
			at_ring = v
		elif phase == 1 and d > rad + 3.0 and (wander or ((g._pos - mid).dot(b[1]) > 0.0 and (g._pos as Vector2).distance_to(g._nodes[b[0]]) < 12.0)):
			phase = 2
		if phase == 1 and v < ring_min:
			ring_min = v
			ring_why = g._ap_why
		if phase == 2 and d < rad + 25.0 and v < exit_min:
			exit_min = v
			exit_why = g._ap_why
		if d < rad + 30.0 and OS.get_environment("VERBOSE") != "" and tick % 15 == 0:
			print("  t %.2f phase %d, %.1f m from the middle, %.1f km/h, why '%s'" % [t, phase, d, v * 3.6, g._ap_why])
		if d < rad + 30.0 and v < 0.3:
			stood += dt
		else:
			if stood > 0.5:
				stands.append("%.1f s at %.0f m from the middle (phase %d, '%s')" % [stood, d, phase, g._ap_why])
			stood = 0.0
		if phase == 2 and d > rad + 30.0:
			t_out = t
			break
	if phase < 2:
		return {"ring_r": snappedf(rad, 0.1), "failed": "phase %d, %.0f m from the middle, why '%s'" % [phase, (g._pos as Vector2).distance_to(mid), g._ap_why], "from": a[4], "to": b[4]}
	return {"at": mid.round(), "ring_r": snappedf(rad, 0.1), "from": a[4], "to": b[4], "to_ring_kmh": snappedf(at_ring * 3.6, 1),
		"ring_min_kmh": snappedf(ring_min * 3.6, 1), "ring_why": ring_why, "exit_min_kmh": snappedf(exit_min * 3.6, 1), "exit_why": exit_why,
		"stands": stands, "secs_60m": snappedf(t_out - t_in, 0.1), "off_asphalt_m": snappedf(off_max, 0.1)}
