extends SceneTree
## Crossing a divided road with no lights, from a side street: across its near carriageway
## and onto the far one (a left turn), or across both. With room for the car between the
## two (a median as deep as a car), autodrive should cross the near one when it is clear and
## wait in the middle for the far one, as drivers do -- not stand at the near kerb for a gap
## in both streams at once. One car is sent along each carriageway: the near one's past the
## side street just as autodrive gets there, the far one's a few seconds behind it. Each case
## twice: with waiting in the middle, and without (the junction taken as one, as before).
## Per case: where it waited and how long, how long to get across, the cars' braking for it,
## how close they came, hits, and whether its tail was clear of the near carriageway while
## it waited in the middle.
##   LEVEL=3 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/median_wait.gd
## MW_N crossings (default 4). Keeps away from the places tests/pick_routes.py keeps away from.
## PASS: with waiting in the middle, no hit, no car within 4 m, none braking over 3.5 m/s^2 for
## it, its tail clear of the near carriageway whenever it stood in the middle.
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

## [n1, n2, side road entry, A entry, B entry, link road, across entry or null, median]
func _pick(want: int) -> Array:
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var out: Array = []
	for n1 in range(g._nodes.size()):
		if g._sig_set.has(n1) or g._node_ways(n1) < 3 or not g._in_city(g._nodes[n1]) or priv.near(avoid, g._nodes[n1]):
			continue
		var a := Vector2i(-1, -1)
		var s := Vector2i(-1, -1)
		var link := -1
		var n2 := -1
		for e: Vector2i in g._node_roads[n1]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"] or r["pv"] or r.get("ring", false):
				continue
			var ids: PackedInt32Array = r["ids"]
			var last := ids.size() - 1
			if r.has("median"):
				if int(r["o"]) != 0 and float(r["median"]) >= 4.0:
					a = e
				continue
			# a short piece from here to another carriageway: the way across the middle
			var other := ids[last] if e.y == 0 else (ids[0] if e.y == last else -1)
			if other >= 0 and not g._sig_set.has(other) and g._nodes[other].distance_to(g._nodes[n1]) < 25.0:
				for e2: Vector2i in g._node_roads[other]:
					var r2: Dictionary = g._roads[e2.x]
					if r2.has("median") and int(r2["o"]) != 0 and e2.x != a.x and r2["drive"]:
						link = e.x
						n2 = other
			# the side street: ending here, coming in straight
			if (e.y == 0 or e.y == last):
				var into := 1 if e.y == last else -1
				if int(r["o"]) != 0 and int(r["o"]) != into:
					continue
				var back := _along(e.x, e.y, -into, 34.0)
				if not back.is_empty() and (back[0] as Vector2).distance_to(g._nodes[n1]) > 30.0:
					s = e
		if a.x < 0 or s.x < 0 or link < 0 or s.x == link:
			continue
		var b := Vector2i(-1, -1)
		var across: Variant = null
		for e2: Vector2i in g._node_roads[n2]:
			var r2: Dictionary = g._roads[e2.x]
			if not r2["drive"] or r2["pv"] or e2.x == link:
				continue
			if r2.has("median") and int(r2["o"]) != 0:
				b = e2
			elif across == null:
				var last2 := (r2["pts"] as PackedVector2Array).size() - 1
				var away := 1 if e2.y == 0 else (-1 if e2.y == last2 else 0)
				if away != 0 and (int(r2["o"]) == 0 or int(r2["o"]) == away) and not _along(e2.x, e2.y, away, 60.0).is_empty():
					across = [e2.x, e2.y, away]
		if b.x < 0:
			continue
		# the side street really across the carriageway, not along it
		var sp: PackedVector2Array = g._roads[s.x]["pts"]
		var sd := (sp[s.y] - sp[1 if s.y == 0 else s.y - 1]).normalized()
		var ap: PackedVector2Array = g._roads[a.x]["pts"]
		var ad := (ap[mini(a.y + 1, ap.size() - 1)] - ap[maxi(a.y - 1, 0)]).normalized()
		if absf(sd.dot(ad)) > 0.6:
			continue
		out.append([n1, n2, s, a, b, link, across, float(g._roads[a.x]["median"])])
	# the ones with room to wait in the middle first, then the rest; spread out
	var roomy := out.filter(func(p: Array) -> bool: return g._median_gap(p[0], p[1]) >= 0.0)
	print("median wait: %d crossings of a divided road from a side street with no lights in %s, %d with room to wait in the middle" % [out.size(), g._city_id, roomy.size()])
	# and every way across a divided road's middle in the town, from wherever (a left turn off
	# the main road through a gap in the median too): how many are deep enough to wait in
	var ways := 0
	var deep := 0
	for r: Dictionary in g._roads:
		var ids: PackedInt32Array = r["ids"]
		if not r["drive"] or r.has("median") or ids.size() < 2:
			continue
		var gp: float = g._median_gap(ids[0], ids[ids.size() - 1])
		var gq: float = g._median_gap(ids[ids.size() - 1], ids[0])
		if g._median_far.has(Vector2i(ids[0], ids[ids.size() - 1])) or g._median_far.has(Vector2i(ids[ids.size() - 1], ids[0])):
			ways += 1
			if maxf(gp, gq) >= 0.0:
				deep += 1
	print("median wait: %d ways across a median in all, %d deep enough to wait in" % [ways, deep])
	var picks: Array = []
	for p: Array in roomy + out.filter(func(q: Array) -> bool: return g._median_gap(q[0], q[1]) < 0.0):
		var crowded := false
		for o: Array in picks:
			if (g._nodes[o[0]] as Vector2).distance_to(g._nodes[p[0]]) < 200.0:
				crowded = true
		if not crowded:
			picks.append(p)
			if picks.size() >= want:
				break
	return picks

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3
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
	var picks := _pick(int(OS.get_environment("MW_N")) if OS.get_environment("MW_N") != "" else 4)
	print("median wait: %d picked" % picks.size())
	for p: Array in picks:
		var link_len := 0.0
		var lp: PackedVector2Array = g._roads[p[5]]["pts"]
		for i in range(lp.size() - 1):
			link_len += lp[i].distance_to(lp[i + 1])
		print("  %d-%d: points %.1f m apart (the way across %.1f m), radii %.1f / %.1f, carriageways %.1f / %.1f m wide, median %.1f m; room past a car %.1f m" % [
			p[0], p[1], (g._nodes[p[0]] as Vector2).distance_to(g._nodes[p[1]]), link_len, g._node_r[p[0]], g._node_r[p[1]],
			float(g._roads[(p[3] as Vector2i).x]["w"]), float(g._roads[(p[4] as Vector2i).x]["w"]), float(p[7]), g._median_gap(p[0], p[1])])
	if OS.get_environment("MW_GEOM") != "":
		quit(0)
		return
	var bad := 0
	var runs := 0
	var t_on := 0.0
	var t_off := 0.0
	for p: Array in picks:
		for go: String in ["onto the far side", "across both"]:
			if go == "across both" and p[6] == null:
				continue
			for wait_ok: bool in [false, true]:
				var res := await _case(p, go, wait_ok)
				if res.is_empty():
					continue
				print("MEDIAN WAIT %s" % JSON.stringify(res))
				if wait_ok:
					runs += 1
					if not res["ok"]:
						bad += 1
					t_on += float(res["across_in"])
				else:
					t_off += float(res["across_in"])
	g._ap_median_ok = true
	print("median wait: across in %.0f s all told waiting in the middle, %.0f s as one junction" % [t_on, t_off])
	print("MEDIAN WAIT: %s (%d of %d bad)" % ["PASS" if bad == 0 and runs > 0 else "FAIL", bad, runs])
	quit(0)

func _case(p: Array, go: String, wait_ok: bool) -> Dictionary:
	var n1: int = p[0]
	var n2: int = p[1]
	var s: Vector2i = p[2]
	var a: Vector2i = p[3]
	var b: Vector2i = p[4]
	var sr: Dictionary = g._roads[s.x]
	var into := 1 if s.y == (sr["pts"] as PackedVector2Array).size() - 1 else -1
	var start: Array = _along(s.x, s.y, -into, 34.0)
	var h: Vector2 = ((g._nodes[n1] as Vector2) - (start[0] as Vector2)).normalized()
	var ob := int(g._roads[b.x]["o"])
	var dest: Array = _along(b.x, b.y, ob, 100.0) if go == "onto the far side" else _along(p[6][0], p[6][1], p[6][2], 60.0)
	if dest.is_empty():
		return {}
	for c in T.cars:
		c.alive = false
		c.retry = 1000.0
	g._ap_median_ok = wait_ok
	g._set_auto(false)
	if not g._land_on_road(start[0], 10.0, h):
		return {}
	await physics_frame
	g._set_dest(dest[0], "median test")
	g._set_auto(true)
	var oa := int(g._roads[a.x]["o"])
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var sent_a = null
	var sent_b = null
	var b_at := -1.0
	var r1: float = g._node_r[n1]
	var r2: float = g._node_r[n2]
	var link_d: Vector2 = ((g._nodes[n2] as Vector2) - (g._nodes[n1] as Vector2)).normalized()
	var stood_kerb := 0.0
	var stood_mid := 0.0
	var tail_in := false
	var across_at := -1.0
	var brake := 0.0
	var vs := {}
	var closest := INF
	var hits := 0
	var last_hit: String = g._last_hit
	var last_v := 0.0
	while t < 45.0:
		await physics_frame
		t += dt
		var my_d: float = (g._pos as Vector2).distance_to(g._nodes[n1])
		# the near carriageway's car: there when autodrive is
		if sent_a == null and my_d < 30.0:
			var eta := (my_d - r1) / maxf(absf(g._v), 4.5)
			var far := clampf(float(g._roads[a.x]["speed"]) * 0.85 * eta + r1, 25.0, 80.0)
			var at: Array = _along(a.x, a.y, -oa, far)
			if at.is_empty() or not T.send(at[0], -(at[1] as Vector2)):
				return {}
			for c in T.cars:
				if c.alive:
					sent_a = c
			b_at = t + 2.5
		# the far one's, a few seconds behind it
		if sent_b == null and b_at > 0.0 and t >= b_at:
			var at2: Array = _along(b.x, b.y, -ob, 70.0)
			if not at2.is_empty() and T.send(at2[0], -(at2[1] as Vector2)):
				for c in T.cars:
					if c.alive and c != sent_a:
						sent_b = c
		# where it stands: short of the near carriageway, or in the middle
		var rel: Vector2 = (g._pos as Vector2) - g._nodes[n1]
		var along: float = rel.dot(link_d)
		var span: float = g._nodes[n1].distance_to(g._nodes[n2])
		if absf(g._v) < 0.3 and across_at < 0.0:
			if along < -r1:
				stood_kerb += dt
			elif along > r1 and along < span - r2:
				stood_mid += dt
				var tail: float = ((g._pos as Vector2) - g._fwd() * g.CAR_LEN * 0.5 - g._nodes[n1]).dot(link_d)
				if tail < r1:
					tail_in = true
		if across_at < 0.0 and (g._pos as Vector2).distance_to(g._nodes[n2]) > r2 + 6.0 and along > span:
			across_at = t
		if g._last_hit != last_hit and g._last_hit != "" and g._crash_cool > 0.35 and absf(last_v) > 1.0 and String(g._last_hit).begins_with("car"):
			hits += 1
		last_hit = g._last_hit
		last_v = g._v
		for c in [sent_a, sent_b]:
			if c == null:
				continue
			closest = minf(closest, c.pos.distance_to(g._pos))
			var arr: Array = vs.get(c, [])
			arr.append(float(c.v))
			if arr.size() > 30:
				arr.pop_front()
				if String(c.why) == "player" or (String(c.why) == "junction" and g._ap_giving.is_empty() and my_d < 30.0):
					brake = maxf(brake, (float(arr[0]) - float(c.v)) / (29.0 * dt))
			vs[c] = arr
		if across_at > 0.0 and t > across_at + 2.0:
			break
	if across_at < 0.0:
		across_at = 99.0
	var ok := hits == 0 and closest >= 4.0 and brake <= 3.5 and not tail_in
	return {"node": n1, "street": String(g._roads[a.x].get("name", "")), "median_m": snappedf(p[7], 0.1), "going": go,
		"waits_in_middle": wait_ok, "across_in": snappedf(across_at, 0.1), "stood_at_kerb": snappedf(stood_kerb, 0.1),
		"stood_in_middle": snappedf(stood_mid, 0.1), "tail_in_near_side": tail_in, "car_brake": snappedf(brake, 0.1),
		"closest": snappedf(closest, 0.1), "hits": hits, "ok": ok}
