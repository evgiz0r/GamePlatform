extends SceneTree
## How wide autodrive turns: up a side street to a cross street, then right and left onto it,
## the rest of the traffic and the people off. Per turn: the plan's own line and the car's,
## each as the tightest radius through the corner and where across the street it turned into
## each sits over the 4-25 m past the junction's middle (metres right of that street's middle
## line; its right-hand lane's middle is `lane`, the middle line 0: under 0.9 the car's left
## side is over it, into the oncoming lane); and how far the car strayed from its plan.
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/turn_width.gd
## TW_N junctions (default 5). Keeps away from the places tests/pick_routes.py keeps away from.
## Good: the car within ~0.5 m of its plan; the plan, and the car, in its lane after the turn
## (its left side not over the middle line of a two-way street).
var g: Node
var T

func _initialize() -> void:
	_run()

func _along(ri: int, k: int, dir: int, dist: float) -> Array:
	var left := dist
	var i := k
	for guard in range(40):
		var pts: PackedVector2Array = g._roads[ri]["pts"]
		while i + dir >= 0 and i + dir < pts.size():
			var seg := pts[i].distance_to(pts[i + dir])
			if seg >= left:
				var d := (pts[i + dir] - pts[i]).normalized()
				return [pts[i] + d * left, d]
			left -= seg
			i += dir
		var n: int = (g._roads[ri]["ids"] as PackedInt32Array)[i]
		var came := (pts[i] - pts[i - dir]).normalized()
		var best := -0.7
		var nxt := Vector3i(-1, 0, 0)
		for e: Vector2i in g._node_roads[n]:
			if e.x == ri or not g._roads[e.x]["drive"]:
				continue
			var q: PackedVector2Array = g._roads[e.x]["pts"]
			for dd: int in [1, -1]:
				if e.y + dd >= 0 and e.y + dd < q.size() and came.dot((q[e.y + dd] - q[e.y]).normalized()) > best:
					best = came.dot((q[e.y + dd] - q[e.y]).normalized())
					nxt = Vector3i(e.x, e.y, dd)
		if nxt.x < 0:
			return []
		ri = nxt.x
		i = nxt.y
		dir = nxt.z
	return []

## junctions with no lights where a two-way side street ends at a two-way cross street that
## runs on 40 m+ both ways, at about a right angle: [node, side entry, cross entry]
func _pick(want: int) -> Array:
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var out: Array = []
	for n in range(g._nodes.size()):
		if g._sig_set.has(n) or g._node_ways(n) < 3 or not g._in_city(g._nodes[n]) or priv.near(avoid, g._nodes[n]):
			continue
		var side := Vector2i(-1, -1)
		var cross := Vector2i(-1, -1)
		for e: Vector2i in g._node_roads[n]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"] or r["pv"] or r.get("ring", false) or int(r["o"]) != 0 or r["k"] == "service":
				continue
			var last := (r["pts"] as PackedVector2Array).size() - 1
			if (e.y == 0 or e.y == last) and side.x < 0:
				var into := 1 if e.y == last else -1
				var back := _along(e.x, e.y, -into, 34.0)
				if not back.is_empty() and (back[0] as Vector2).distance_to(g._nodes[n]) > 30.0:
					side = e
					continue
			if e.y > 0 and e.y < last and cross.x < 0:
				if not _along(e.x, e.y, 1, 40.0).is_empty() and not _along(e.x, e.y, -1, 40.0).is_empty():
					cross = e
		if side.x < 0 or cross.x < 0:
			continue
		var sp: PackedVector2Array = g._roads[side.x]["pts"]
		var sd := (sp[side.y] - sp[1 if side.y == 0 else side.y - 1]).normalized()
		var cp: PackedVector2Array = g._roads[cross.x]["pts"]
		var cd := (cp[cross.y + 1] - cp[cross.y - 1]).normalized()
		if absf(sd.dot(cd)) > 0.35:
			continue
		var crowded := false
		for o: Array in out:
			if (g._nodes[o[0]] as Vector2).distance_to(g._nodes[n]) < 250.0:
				crowded = true
		if crowded:
			continue
		out.append([n, side, cross])
		if out.size() >= want:
			break
	return out

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	T = g._traffic
	for cr: Dictionary in g._crossers:
		cr["state"] = "off"
		(cr["actor"] as Node3D).visible = false
	g._zebra_t = 1.0e9
	var picks := _pick(int(OS.get_environment("TW_N")) if OS.get_environment("TW_N") != "" else 5)
	print("turn width: %d junctions in %s" % [picks.size(), g._city_id])
	var over := 0
	var runs := 0
	var stray := 0.0   # (the car's worst straying from its plan, over all the turns)
	for p: Array in picks:
		for turn: String in ["right", "left"]:
			var res := await _case(p, turn)
			if res.is_empty():
				continue
			runs += 1
			if res["car_over_middle"] or res["plan_over_middle"]:
				over += 1
			stray = maxf(stray, float(res["car_off_plan"]))
			print("TURN WIDTH %s" % JSON.stringify(res))
	print("TURN WIDTH: %d of %d turns with the car's left side over the middle line after the turn" % [over, runs])
	# The bug ("its radius of turning is like double of what it should be, it hits the opposing
	# or the next lane a lot"): 4 of 8 of Givatayim's turns came out with the car's middle on
	# the middle line, 1.5-2.2 m off a plan whose corner sat on it. The fix read 0 of 8 over
	# the line (0 of 10 in Ashdod, 0 of 2 in the test town) and the car 0.5-0.8 m off its plan:
	# none over, and the straying under the bug's least, 1.5 m.
	var ok := runs > 0 and over == 0 and stray < 1.5
	print("REGRESS turn_width: %s -- turns with the car or its plan over the middle line after the turn %d of %d, the car at most %.1f m off its plan (good 0, and under 1.5 m; the bug: 4 of 8, 1.5-2.2 m)" % [
		"PASS" if ok else "FAIL", over, runs, stray])
	quit(0)

func _radius(path: PackedVector2Array) -> float:
	# the tightest circle through three points 3 m apart along the line
	var pts := PackedVector2Array()
	for i in range(path.size()):
		if pts.is_empty() or path[i].distance_to(pts[pts.size() - 1]) >= 3.0:
			pts.append(path[i])
	var best := INF
	for i in range(1, pts.size() - 1):
		var a := pts[i - 1]
		var b := pts[i]
		var c := pts[i + 1]
		var area2 := absf((b - a).cross(c - a))
		if area2 < 0.01:
			continue
		best = minf(best, a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * area2))
	return best

func _case(p: Array, turn: String) -> Dictionary:
	var n: int = p[0]
	var node: Vector2 = g._nodes[n]
	var side: Vector2i = p[1]
	var cross: Vector2i = p[2]
	var sr: Dictionary = g._roads[side.x]
	var into := 1 if side.y == (sr["pts"] as PackedVector2Array).size() - 1 else -1
	var start: Array = _along(side.x, side.y, -into, 34.0)
	var h: Vector2 = (node - (start[0] as Vector2)).normalized()
	var right := Vector2(-h.y, h.x)
	var ka: Array = _along(cross.x, cross.y, 1, 12.0)
	var dir_r := 1 if ((ka[0] as Vector2) - node).dot(right) > 0.0 else -1
	var go_dir := dir_r if turn == "right" else -dir_r
	var dest: Array = _along(cross.x, cross.y, go_dir, 70.0)
	var a20: Array = _along(cross.x, cross.y, go_dir, 20.0)
	if dest.is_empty() or a20.is_empty():
		return {}
	var out_d: Vector2 = ((a20[0] as Vector2) - node).normalized()
	var out_r := Vector2(-out_d.y, out_d.x)
	var cr_road: Dictionary = g._roads[cross.x]
	var lane: float = g._lane_off(cr_road)
	for c in T.cars:
		c.alive = false
		c.retry = 1000.0
	g._set_auto(false)
	if not g._land_on_road(start[0], 10.0, h):
		return {}
	await physics_frame
	g._set_dest(dest[0], "turn test")
	g._set_auto(true)
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var car := PackedVector2Array()
	var plan_seen := PackedVector2Array()
	var stray := 0.0
	var plan_v := INF
	var plan_pts := 0
	var v_in := INF
	var car_lat := [INF, -INF]
	var plan_lat := [INF, -INF]
	while t < 25.0:
		await physics_frame
		t += dt
		var pos: Vector2 = g._pos
		var d_node := pos.distance_to(node)
		if d_node < 30.0:
			car.append(pos)
			v_in = minf(v_in, absf(g._v)) if d_node < 12.0 else v_in
			# its plan, as it stands now near the junction (kept the first time it is within 15 m)
			if plan_seen.is_empty() and d_node < 15.0:
				# (a metre apart: the plan has few points on a straight)
				var raw: PackedVector2Array = g._ap_pts
				for i in range(raw.size() - 1):
					var L := raw[i].distance_to(raw[i + 1])
					for k in range(maxi(1, ceili(L))):
						plan_seen.append(raw[i].lerp(raw[i + 1], float(k) / maxi(1, ceili(L))))
				# the plan's corner speeds near the junction
				for i in range(mini(raw.size(), (g._ap_v as PackedFloat32Array).size())):
					if raw[i].distance_to(node) < 15.0 and g._ap_v[i] > 0.0:
						plan_v = minf(plan_v, g._ap_v[i])
				if OS.get_environment("TW_TRACE") == str(n):
					# what keeps the lane spot by the junction from being clear (see _clear_lane)
					for back: float in [0.0, 1.0, 2.5]:
						for off: float in [2.5, 1.5, 0.6, 0.0]:
							var q: Vector2 = node - h * back + right * off
							var said := []
							for k: float in [0.0, 1.4, -1.4]:
								g._last_hit = ""
								var pu: Vector2 = g._push_out(q + h * k, 1.2 if k == 0.0 else 1.15, true, false, g._y)
								if pu != Vector2.ZERO:
									said.append("%+.1f: %s (%.2f m)" % [k, g._last_hit, pu.length()])
							print("  lane spot %.1f m short, %.1f m right: %s" % [back, off, "clear" if said.is_empty() else ", ".join(said)])
					for e: Vector2i in g._node_roads[n]:
						var rr: Dictionary = g._roads[e.x]
						var rp: PackedVector2Array = rr["pts"]
						var nb: Array = []
						for dd: int in [-1, 1]:
							if e.y + dd >= 0 and e.y + dd < rp.size():
								nb.append("%.1f m" % rp[e.y].distance_to(rp[e.y + dd]))
						print("  road %d '%s' at its point %d of %d, next points %s, w %.1f, o %d" % [e.x, rr.get("name", ""), e.y, rp.size(), ", ".join(nb), float(rr["w"]), int(rr["o"])])
					for i in range(raw.size()):
						if raw[i].distance_to(node) < 60.0:
							print("  plan point %d: in %.1f right %.1f, %.1f m/s" % [i, (raw[i] - node).dot(h), (raw[i] - node).dot(right), g._ap_v[i] if i < g._ap_v.size() else -1.0])
				plan_pts = 0
				for q: Vector2 in raw:
					if q.distance_to(node) < 15.0:
						plan_pts += 1
			var pp: PackedVector2Array = g._ap_pts
			if pp.size() > 1:
				var bd := INF
				for i in range(mini(pp.size() - 1, 12)):
					bd = minf(bd, Geometry2D.get_closest_point_to_segment(pos, pp[i], pp[i + 1]).distance_to(pos))
				stray = maxf(stray, bd)
		if OS.get_environment("TW_TRACE") == str(n) and d_node < 22.0 and int(t * 60.0) % 6 == 0:
			var fw: Vector2 = g._fwd()
			var nose: Vector2 = pos + fw * (g.CAR_OFF + 0.5 + absf(g._v) * 0.3)
			var shove: Vector2 = g._push_out(nose, 1.15, true, false, g._y)
			print("  %s t %.1f  in %.1f right %.1f (of the way in)  out %.1f right %.1f (of the way out)  %.1f m/s  steer %.2f  yaw rate %.2f  shove %.2f (%s)" % [turn, t,
				(pos - node).dot(h), (pos - node).dot(right), (pos - node).dot(out_d), (pos - node).dot(out_r), g._v, g._steer, g._yaw_rate, shove.dot(Vector2(-fw.y, fw.x)), g._ap_why])
		var along: float = (pos - node).dot(out_d)
		if along > 4.0 and along < 25.0 and absf((pos - node).dot(out_r)) < 12.0:
			var lat: float = (pos - node).dot(out_r)
			car_lat[0] = minf(car_lat[0], lat)
			car_lat[1] = maxf(car_lat[1], lat)
		if along > 30.0:
			break
	for q: Vector2 in plan_seen:
		var along: float = (q - node).dot(out_d)
		if along > 4.0 and along < 25.0 and absf((q - node).dot(out_r)) < 12.0:
			var lat: float = (q - node).dot(out_r)
			plan_lat[0] = minf(plan_lat[0], lat)
			plan_lat[1] = maxf(plan_lat[1], lat)
	var plan_near := PackedVector2Array()
	for q: Vector2 in plan_seen:
		if q.distance_to(node) < 25.0:
			plan_near.append(q)
	return {"node": n, "turn": turn, "into": String(cr_road.get("name", "")), "street_w": snappedf(float(cr_road["w"]), 0.1), "lane": snappedf(lane, 0.1),
		"plan_r": snappedf(_radius(plan_near), 0.1), "car_r": snappedf(_radius(car), 0.1), "kmh_in_it": snappedf(v_in * 3.6, 1),
		"plan_right_of_middle": [snappedf(plan_lat[0], 0.1), snappedf(plan_lat[1], 0.1)], "car_right_of_middle": [snappedf(car_lat[0], 0.1), snappedf(car_lat[1], 0.1)],
		"car_off_plan": snappedf(stray, 0.1), "plan_kmh": snappedf(plan_v * 3.6, 1), "plan_points_within_15m": plan_pts, "plan_over_middle": plan_lat[0] < 0.9, "car_over_middle": car_lat[0] < 0.9}
