extends SceneTree
## A car going round a delivery van, over the centre line, with autodrive coming the other way.
## A drive chart (route 6 at 3:10, 21 Nov 2026): a car pulled into autodrive's lane 12 m ahead
## and stopped dead there, held by the player; autodrive braked 8.8 m/s^2 from 48 km/h and
## touched it. Traffic checked the other lane only by distance (35 + 45 m) and never again
## once out: at 50 km/h the player is there in under 6 s, a pass from behind a van takes 7-8.
## Stages it on a straight two-way street of one lane each way (the longest such stretch away
## from junctions and from the places tests/pick_routes.py keeps away from; ROAD_AT="x,z" for
## another): a van standing in the lane for its delivery, a car 30 m behind it, the rest of
## traffic off; autodrive coming the other way from FROM metres past the van (a list,
## default 70,110,150,190 -- traffic is only kept within 240 m of the player) at the street's limit, set to drive on 120 m past them.
## Prints for each: whether the car went round before autodrive went by, how long it stood
## over the centre line held by the player ("head-on"), the least gap between them, and
## autodrive's hardest braking. PASS: never head-on, and the car does go round once the way is
## clear (no deadlock). PASS_OLD=1: the pass judged as before (by distance, once).
##   LEVEL=3 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/van_pass.gd
var g: Node
var verbose := false

## VERBOSE=1: after autodrive has gone by, every 2 s, what the car waits for -- and what its
## look at the other lane sees there (the same test the game makes)
func _tell(car, ci: int, van, t: float) -> void:
	var tr = g._traffic
	var rr: Dictionary = tr._roads[car.rd[mini(car.k + 1, car.rd.size() - 1)]]
	var gap: float = tr._path_gap(car, van.pos, 60.0, tr.LANE_W)
	var d: float = gap + van.len + car.len + 1.5
	var secs: float = tr._pass_secs(car, d)
	var seen := []
	for j in range(tr.cars.size() + 1):
		var q: Vector2 = g._pos if j == tr.cars.size() else tr.cars[j].pos
		if j < tr.cars.size() and (j == ci or not tr.cars[j].alive or tr._parked_double(tr.cars[j])):
			continue
		var pr: Vector2 = tr._proj(car, q, 8.0, 400.0)
		if pr.x != INF:
			seen.append("%s at %.0f m ahead, %.1f m left" % ["me" if j == tr.cars.size() else "car %d" % j, pr.x, pr.y])
	print("    t %.0f: car v %.1f why %s pass_i %d shift %.2f wait %.0f; van %.1f m ahead; near a junction %s; other lane clear %s (pass %.1f s, %.0f m); in its look: %s" % [
		t, car.v, car.why, car.pass_i, car.shift, car.wait, gap, str(tr._near_junction(car, gap + 12.0)),
		str(tr._oncoming_clear(car, ci, gap + 45.0, tr._pass_shift(rr), secs, d)), secs, d, ", ".join(seen)])

func _initialize() -> void:
	_run()

## the least distance between two boxes (centre, unit along, half length and half width)
func _box_gap(c1: Vector2, u1: Vector2, h1: Vector2, c2: Vector2, u2: Vector2, h2: Vector2) -> float:
	var best := INF
	for pair in [[c1, u1, h1, c2, u2, h2], [c2, u2, h2, c1, u1, h1]]:
		var ua: Vector2 = pair[1]
		var ub: Vector2 = pair[4]
		var ha: Vector2 = pair[2]
		var hb: Vector2 = pair[5]
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var p: Vector2 = (pair[0] as Vector2) + ua * ha.x * sx + Vector2(-ua.y, ua.x) * ha.y * sy - (pair[3] as Vector2)
				var lx := absf(p.dot(ub)) - hb.x
				var ly := absf(p.dot(Vector2(-ub.y, ub.x))) - hb.y
				best = minf(best, Vector2(maxf(lx, 0.0), maxf(ly, 0.0)).length() if (lx > 0.0 or ly > 0.0) else maxf(lx, ly))
	return best

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
	var tr = g._traffic
	if OS.get_environment("PASS_OLD") != "":
		tr.pass_by_time = false   # (as before 21 Nov: the other lane judged by distance, once)
	var avoid: Array = load("res://game/streets/tests/private_spots.gd").spots(g)
	var priv = load("res://game/streets/tests/private_spots.gd")
	# the street: a straight run of a two-way road of one lane each way that vans stop in
	var pick: Array = []   # [road, segment, from, to (unit along), length]
	var want_at := Vector2.INF
	if OS.get_environment("ROAD_AT") != "":
		var xz := OS.get_environment("ROAD_AT").split(",")
		want_at = Vector2(float(xz[0]), float(xz[1]))
	var best_len := 0.0
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if int(r["o"]) != 0 or not r["drive"] or not tr.DBL_ROADS.has(String(r["k"])) or tr._lanes_dir(r) > 1:
			continue
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var a: Vector2 = pts[j]
			var b: Vector2 = pts[j + 1]
			var L := a.distance_to(b)
			if want_at != Vector2.INF:
				if Geometry2D.get_closest_point_to_segment(want_at, a, b).distance_to(want_at) < 10.0 and L > best_len:
					best_len = L
					pick = [ri, j, a, b, L]
				continue
			if L < 200.0 or L <= best_len or priv.near(avoid, a.lerp(b, 0.5)):
				continue
			best_len = L
			pick = [ri, j, a, b, L]
	if pick.is_empty():
		print("no straight street long enough")
		quit(1)
		return
	var a0: Vector2 = pick[2]
	var b0: Vector2 = pick[3]
	var u := (b0 - a0).normalized()
	var r0: Dictionary = g._roads[pick[0]]
	print("street '%s' (%s, %.1f m wide), a straight %.0f m" % [String(r0.get("en", r0["name"])), r0["k"], float(r0["w"]), float(pick[4])])
	var van_at := a0.lerp(b0, 0.45)
	var froms: Array = []
	for s in (OS.get_environment("FROM") if OS.get_environment("FROM") != "" else "70,110,150,190").split(","):
		froms.append(float(s))
	var vi := -1
	var ci := -1
	for i in range(tr.cars.size()):
		if vi < 0 and tr.cars[i].kind == "van":
			vi = i
		elif ci < 0 and tr.cars[i].kind in ["sedan", "suv", "mini"]:
			ci = i
	if vi < 0 or ci < 0:
		print("no van or car in the traffic")
		quit(1)
		return
	var bad := 0
	var stuck := 0
	verbose = OS.get_environment("VERBOSE") != ""
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	for from: float in froms:
		var dirn := 1 if (b0 - a0).dot(u) > 0.0 else -1
		for c in tr.cars:
			c.alive = false
		var van = tr.cars[vi]
		var car = tr.cars[ci]
		var sv: Dictionary = g._nearest_seg(van_at, 6.0, true, true)
		van.alive = tr._start_on(van, int(sv["road"]), int(sv["seg"]), sv["q"], dirn)
		var sc: Dictionary = g._nearest_seg(van_at - u * 30.0, 6.0, true, true)
		car.alive = tr._start_on(car, int(sc["road"]), int(sc["seg"]), sc["q"], dirn)
		if not van.alive or not car.alive:
			print("  from %.0f m: could not put the van or the car down" % from)
			continue
		van.v = 0.0
		van.dbl_s = van.s + 0.5
		van.dbl = 60.0
		car.v = 6.0
		# autodrive coming the other way at the street's limit
		g._set_auto(false)
		if not g._land_on_road(van_at + u * from, 6.0, -u):
			print("  from %.0f m: no road for the player" % from)
			continue
		g._set_dest(van_at - u * 120.0, "van pass test")
		g._set_auto(true)
		var lim: float = g._ap_lim[1] if g._ap_lim.size() > 1 else 13.9
		g._v = lim
		var t := 0.0
		var head_on := 0.0
		var least := INF
		var hardest := 0.0
		var v_prev: float = g._v
		var went_before := false
		var went_after := false
		var met := false
		var acc_t := 0.0
		var out_max := 0.0
		var face := 0.0
		while t < 40.0:
			await physics_frame
			t += dt
			for o in tr.cars:   # (only the two)
				if o != van and o != car:
					o.alive = false
			van.dbl = maxf(van.dbl, 5.0)   # (stands all the while)
			if not car.alive:
				break
			var over: bool = car.shift > 1.0
			var ahead: float = (g._pos - car.pos).dot(Vector2(sin(car.yaw), cos(car.yaw)))
			if not met and ahead < 0.0:
				met = true   # (autodrive has gone by it)
			if over and not met:
				went_before = true
			if over and met:
				went_after = true
			if over and car.v < 0.3 and String(car.why) == "player" and not met:
				head_on += dt
			var hw: Vector2 = tr.CORNERS.get(car.kind, Vector2(0.9, 2.3))
			least = minf(least, _box_gap(car.pos, Vector2(sin(car.yaw), cos(car.yaw)), Vector2(hw.y, hw.x), g._pos, g._fwd(), Vector2(g.CAR_LEN * 0.5, 0.9)))
			if not met:
				out_max = maxf(out_max, car.shift)
			if not met and car.v < 0.3 and absf(float(g._v)) < 0.3 and car.pos.distance_to(g._pos) < 15.0:
				face += dt
			acc_t += dt
			if acc_t >= 0.1:
				hardest = maxf(hardest, (v_prev - g._v) / acc_t)
				v_prev = g._v
				acc_t = 0.0
			if met and (car.pos - van.pos).dot(u * dirn) > van.len:
				break   # (round the van, the way clear)
			if verbose and met and int(t * 10.0) % 20 == 0 and int((t - dt) * 10.0) % 20 != 0:
				_tell(car, ci, van, t)
		var past: bool = (car.pos - van.pos).dot(u * dirn) > van.len
		if head_on > 0.3 or face > 3.0:
			bad += 1
		if not past:
			stuck += 1
		print("  autodrive from %.0f m at %.0f km/h: the car %s (out %.1f m before autodrive went by), head-on %.1f s, both standing face to face %.1f s, least gap %.2f m, autodrive's hardest braking %.1f m/s^2, round the van %s (%.0f s)" % [
			from, lim * 3.6, "went round before autodrive went by" if went_before else ("waited, then went round" if went_after else "did not go round"),
			out_max, head_on, face, least, hardest, "yes" if past else "NO", t])
	print("VAN PASS: %d of %d head-on or face to face, %d never got round -- %s" % [bad, froms.size(), stuck, "PASS" if bad == 0 and stuck == 0 else "FAIL"])
	quit()
