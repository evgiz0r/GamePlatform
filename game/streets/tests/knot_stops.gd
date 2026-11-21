extends SceneTree
## Cars standing inside a junction with lights. Where a divided road meets another, OSM draws
## one junction as two to four signalled points 10-30 m apart; the game makes them one junction
## (one set of lights, a car in on its green goes through all of it). A user: "cars sometimes
## stop in intersections as if there are 2 turns... instead of a normal 2x2, there are some
## stops in the middle that cause chaos" (Ashdod, a divided road's T with lights, behind a car
## standing in the middle).
## Watches KS_N junctions of two signalled points or more (default 4, the ones with the most
## points first, away from the places tests/pick_routes.py keeps away from; KNOT_AT="x,z" one
## junction instead), SECS each (default 90), the player parked out of the way, traffic as it
## comes. Every car that stands 1.5 s or more inside it (within a point's disc and a metre) is
## printed once per stand: what holds it (its `why`), the car in front if that is it (and whether
## that one is inside too), its light by the way it came, which point, and how long.
##   LEVEL=3 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/knot_stops.gd
## Counts stands by what began them: a car held by a car is a queue; the rest are the causes.
## DRIVE=1: autodrive drives through it too, from 100 m back on each way in to 120 m past,
## straight on; its own stands inside are printed with `_ap_why`, and traffic held by it ("player").
## (The people on the crossings come out only near the player: parked away, nobody crosses.)
## ZEBRA_OLD=1: a car waits for anyone on a crossing till the far kerb, as before 21 Nov.
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
	if OS.get_environment("ZEBRA_OLD") != "":
		g._zebra_past = false   # (as before: anyone on the crossing holds a car till the far kerb)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	var want := int(OS.get_environment("KS_N")) if OS.get_environment("KS_N") != "" else 4
	# the junctions: lit points by site
	var by_site := {}
	for n: int in g._sig_set:
		var s: int = g._site_of.get(n, n)
		if not by_site.has(s):
			by_site[s] = []
		(by_site[s] as Array).append(n)
	var picks: Array = []
	if OS.get_environment("KNOT_AT") != "":
		var xz := OS.get_environment("KNOT_AT").split(",")
		var at := Vector2(float(xz[0]), float(xz[1]))
		var best := -1
		for s: int in by_site:
			var d: float = (g._nodes[by_site[s][0]] as Vector2).distance_to(at)
			if best < 0 or d < (g._nodes[by_site[best][0]] as Vector2).distance_to(at):
				best = s
		picks.append(by_site[best])
	else:
		var priv = load("res://game/streets/tests/private_spots.gd")
		var avoid: Array = priv.spots(g)
		var sites: Array = []
		for s: int in by_site:
			var ns: Array = by_site[s]
			if ns.size() >= 2 and g._in_city(g._nodes[ns[0]]) and not priv.near(avoid, g._nodes[ns[0]]):
				sites.append(ns)
		sites.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
		for ns: Array in sites:
			var crowded := false
			for p: Array in picks:
				if (g._nodes[p[0]] as Vector2).distance_to(g._nodes[ns[0]]) < 250.0:
					crowded = true
			if not crowded:
				picks.append(ns)
			if picks.size() >= want:
				break
	var all_q := 0
	var all_c := 0
	var causes := {}
	for ns: Array in picks:
		var res: Array = []
		if OS.get_environment("DRIVE") != "":
			res = await _drive_through(ns)
		else:
			res = await _watch(ns, secs)
		all_q += int(res[0])
		all_c += int(res[1])
		for k: String in res[2]:
			causes[k] = int(causes.get(k, 0)) + int(res[2][k])
	print("KNOT STOPS: %d junctions, %d stands inside not behind a car (%s), %d queued behind one inside" % [picks.size(), all_c, str(causes), all_q])
	quit(0)

## for a car held by a zebra: the crossing with someone on it on its way, as traffic's
## _zebra_ahead finds it: "where, how far on, how far from the junction's points, its people"
func _zebra_of(c, ns: Array) -> String:
	for z: Array in g._zebras_on:
		var zm: Vector2 = z[0]
		if zm.distance_to(c.pos) > 70.0:
			continue
		for j in range(c.k, c.pts.size() - 1):
			var base: float = c.cum[j] - c.s
			if base > 70.0:
				break
			var cp := Geometry2D.get_closest_point_to_segment(zm, c.pts[j], c.pts[j + 1])
			if cp.distance_to(zm) < float(z[1]):
				if g._zebra_clear(z, cp):
					break
				var nearest := INF
				for n: int in ns:
					nearest = minf(nearest, (g._nodes[n] as Vector2).distance_to(zm) - g._node_r[n])
				var who := "a filmed walk's" if z.size() < 5 else "someone %.1f m off its middle" % ((z[3] as Vector2).distance_to(zm))
				return "zebra %.1f m on at %s, %.1f m outside the nearest point's disc, %s" % [base + c.pts[j].distance_to(cp), zm.round(), nearest, who]
	return "no zebra found"

func _inside(ns: Array, p: Vector2) -> int:
	for n: int in ns:
		if (g._nodes[n] as Vector2).distance_to(p) < g._node_r[n] + 1.0:
			return n
	return -1

## watches one junction: [stands queued behind a car inside, other stands, {why: count}]
func _watch(ns: Array, secs: float) -> Array:
	var mid := Vector2.ZERO
	for n: int in ns:
		mid += g._nodes[n]
	mid /= ns.size()
	var names := {}
	for n: int in ns:
		for e: Vector2i in g._node_roads[n]:
			if (g._roads[e.x] as Dictionary)["drive"]:
				names[String((g._roads[e.x] as Dictionary)["en"])] = true
	var span := 0.0
	for a: int in ns:
		for b: int in ns:
			span = maxf(span, (g._nodes[a] as Vector2).distance_to(g._nodes[b]))
	print("junction of %d lit points at %s, %.0f m across: %s" % [ns.size(), mid.round(), span, ", ".join(names.keys())])
	for ang in range(0, 360, 30):
		var q := mid + Vector2.from_angle(deg_to_rad(ang)) * 130.0
		if g._land_on_road(q, 30.0, Vector2.ZERO) and g._pos.distance_to(mid) > 100.0:
			break
	g._set_auto(false)
	var t := 0.0
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var stood := {}     # car -> seconds standing inside
	var told := {}      # car -> told about this stand
	var came := {}      # car -> its heading before it came in
	var queued := 0
	var other := 0
	var why_n := {}
	while t < secs:
		await physics_frame
		t += dt
		g._v = 0.0
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive or c.pos.distance_to(mid) > span + 40.0:
				stood.erase(i)
				told.erase(i)
				continue
			var n := _inside(ns, c.pos)
			if n < 0:
				came[i] = Vector2(sin(c.yaw), cos(c.yaw))
				stood.erase(i)
				told.erase(i)
				continue
			if c.v > 0.3:
				stood.erase(i)
				told.erase(i)
				continue
			stood[i] = float(stood.get(i, 0.0)) + dt
			if float(stood[i]) < 1.5 or told.has(i):
				continue
			told[i] = true
			var cd: Vector2 = came.get(i, Vector2(sin(c.yaw), cos(c.yaw)))
			var lead := ""
			var behind_inside := false
			if c.blocker >= 0 and c.blocker < T.cars.size():
				var o = T.cars[c.blocker]
				behind_inside = _inside(ns, o.pos) >= 0
				lead = ", behind car %d (%s, its why '%s', %s, %.1f m)" % [c.blocker, o.kind, o.why, "inside too" if behind_inside else "outside", o.pos.distance_to(c.pos)]
			elif c.blocker == -1:
				lead = ", behind the player"
			var turn := "straight"
			var ahead := Vector2(sin(c.yaw), cos(c.yaw))
			if c.k + 4 < c.pts.size():
				ahead = ((c.pts[mini(c.k + 6, c.pts.size() - 1)] as Vector2) - c.pos).normalized()
			var cross := cd.cross(ahead)
			if cd.dot(ahead) < 0.8:
				turn = "turning left" if cross < 0.0 else "turning right"   # (left of (0,1) is (1,0) here)
			if c.why == "car" and behind_inside:
				queued += 1
			else:
				other += 1
				why_n[String(c.why)] = int(why_n.get(String(c.why), 0)) + 1
			print("  t %.0f: car %d (%s) standing inside at point %d (%.1f m from it), why '%s'%s, %s, its light %s, phase %d%s" % [
				t, i, c.kind, n, (g._nodes[n] as Vector2).distance_to(c.pos), c.why, lead, turn, g._light_at(n, cd), g._sig_phase,
				(": " + _zebra_of(c, ns)) if c.why == "zebra" else (", kerb %s hold %.1f dwell %.1f" % [c.kerb, c.hold_t, c.dwell] if c.why == "limit" else "")])
	print("  -> %d stands inside not behind a car (%s), %d behind one inside" % [other, str(why_n), queued])
	return [queued, other, why_n]

## autodrive through the junction from each way in, straight on, traffic about: [traffic stands
## behind a car inside, other stands (traffic's and autodrive's), {why: count}]
func _drive_through(ns: Array) -> Array:
	var mid := Vector2.ZERO
	for n: int in ns:
		mid += g._nodes[n]
	mid /= ns.size()
	var ways: Array = []
	for n: int in ns:
		for way: Array in g._sig_line.get(n, []):
			if not way[3]:
				ways.append([n, way])
	print("junction of %d lit points at %s: %d ways in" % [ns.size(), mid.round(), ways.size()])
	var queued := 0
	var other := 0
	var why_n := {}
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	for w: Array in ways:
		var n0: int = w[0]
		var dir: Vector2 = w[1][0]
		g._set_auto(false)
		if not g._land_on_road(g._nodes[n0] - dir * (float(w[1][1]) + 100.0), 8.0, dir):
			continue
		g._v = 0.0
		await physics_frame
		var dest: Vector2 = g._nodes[n0] + dir * 120.0
		g._set_dest(dest, "knot test")
		g._set_auto(true)
		var t := 0.0
		var stood := {}
		var told := {}
		var me_st := 0.0
		var me_told := false
		var through := false
		while t < 70.0:
			await physics_frame
			t += dt
			# autodrive inside
			if _inside(ns, g._pos) >= 0:
				through = true
				if absf(g._v) < 0.3:
					me_st += dt
					if me_st >= 1.5 and not me_told:
						me_told = true
						var k := "autodrive: " + String(g._ap_why)
						if g._ap_why == "car" and g._ap_lead >= 0.0:
							k = "autodrive: car"
						why_n[k] = int(why_n.get(k, 0)) + 1
						other += 1
						print("  from %s: AUTODRIVE standing inside, %.1f m from point %d, why '%s', lead %.1f, gives way at %d points, light ahead %s" % [
							dir.snappedf(0.01), (g._nodes[_inside(ns, g._pos)] as Vector2).distance_to(g._pos), _inside(ns, g._pos), g._ap_why, g._ap_lead, g._ap_giving.size(), g._light_at(n0, dir)])
				else:
					me_st = 0.0
					me_told = false
			# traffic inside
			for i in range(T.cars.size()):
				var c = T.cars[i]
				if not c.alive or c.v > 0.3 or _inside(ns, c.pos) < 0:
					stood.erase(i)
					told.erase(i)
					continue
				stood[i] = float(stood.get(i, 0.0)) + dt
				if float(stood[i]) < 1.5 or told.has(i):
					continue
				told[i] = true
				var behind_inside := false
				if c.blocker >= 0 and c.blocker < T.cars.size():
					behind_inside = _inside(ns, T.cars[c.blocker].pos) >= 0
				if c.why == "car" and behind_inside:
					queued += 1
				else:
					other += 1
					var k := String(c.why) + (" (me)" if c.blocker == -1 else "")
					why_n[k] = int(why_n.get(k, 0)) + 1
					print("  from %s: car %d (%s) standing inside, why '%s', blocker %d, me %.0f m off (my why '%s', %.1f m/s)%s" % [
						dir.snappedf(0.01), i, c.kind, c.why, c.blocker, c.pos.distance_to(g._pos), g._ap_why, g._v,
						(": " + _zebra_of(c, ns)) if c.why == "zebra" else (", kerb %s hold %.1f dwell %.1f" % [c.kerb, c.hold_t, c.dwell] if c.why == "limit" else "")])
			if through and _inside(ns, g._pos) < 0 and g._pos.distance_to(mid) > 40.0:
				break
		print("  from %s: through in %.0f s" % [dir.snappedf(0.01), t] if through else "  from %s: never got in (%.0f s, why '%s')" % [dir.snappedf(0.01), t, g._ap_why])
	print("  -> %d stands inside not behind a car (%s), %d behind one inside" % [other, str(why_n), queued])
	return [queued, other, why_n]
