extends SceneTree
## Racer's moves round a car standing in its way (racer.gd, streets.gd _ap_pass_bus /
## _ap_mount_by), staged: a car put on the road 60 m ahead in racer's lane and held there
## (traffic's "stunned" time), the rest of the traffic gone, on CASES of each kind:
##   pass     a one-way street of two lanes or more: it goes round in the next lane
##   pavement a one-way street of one lane: no lane to go round in -- up onto the pavement
##            where it is clear, else it waits
## Per case: what it did (passed, pavement, stood), on past the car within 40 s, crashes,
## people hit.
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --path . -s res://game/streets/tests/racer_moves.gd
## PASS: every pass case went round (on past it), none crashed, nobody hit; the pavement
## cases each went up onto it and past, or stood (where it was not clear).
var g: Node
const AHEAD := 60.0

func _initialize() -> void:
	_run()

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
	var probe = root.get_node("Probe")
	probe.enabled = true
	var want := int(OS.get_environment("CASES")) if OS.get_environment("CASES") != "" else 3
	var bad := 0
	for kind: String in ["pass", "pavement"]:
		var spots := _spots(kind, want)
		print("RACER_MOVES %s: %d streets" % [kind, spots.size()])
		for sp: Array in spots:
			var res := await _case(sp, kind, probe)
			if res.is_empty():
				continue
			print("RACER_MOVES %s" % JSON.stringify(res))
			if int(res["crashes"]) > 0 or int(res["people_hit"]) > 0:
				bad += 1
			elif kind == "pass" and not (bool(res["past"]) and int(res["passed"]) > 0):
				bad += 1
			elif kind == "pavement" and bool(res["past"]) and int(res["pavement"]) == 0 and int(res["passed"]) == 0:
				bad += 1   # (on past it with neither: through the car?)
	print("RACER_MOVES: %s (%d bad)" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(0)

## straight stretches of one-way streets, 150 m or more, with n lanes (pass: 2+, pavement: 1)
func _spots(kind: String, want: int) -> Array:
	var out: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or int(r["o"]) == 0 or r["pv"] or r.has("ys") or g.HIGHWAYS.has(r["k"]) or r["k"] == "service":
			continue
		var n: int = g._lanes_each_way(r)
		if (kind == "pass" and n < 2) or (kind == "pavement" and n != 1):
			continue
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var a := pts[j] if int(r["o"]) == 1 else pts[j + 1]
			var b := pts[j + 1] if int(r["o"]) == 1 else pts[j]
			if a.distance_to(b) < 150.0 or not g._in_city(a) or not g._in_city(b):
				continue
			var crowded := false
			for o: Array in out:
				if (o[0] as Vector2).distance_to(a) < 400.0:
					crowded = true
			if not crowded:
				out.append([a, (b - a).normalized(), String(r["name"])])
			break
		if out.size() >= want:
			break
	return out

func _case(sp: Array, kind: String, probe) -> Dictionary:
	var a: Vector2 = sp[0]
	var dir: Vector2 = sp[1]
	for c in g._traffic.cars:
		c.alive = false
		c.retry = 1000.0
	g._set_racer(false)
	g._set_auto(false)
	if not g._land_on_road(a + dir * 5.0, 6.0, dir):
		return {}
	await physics_frame
	# the car in the way: put down 60 m on, in the lane autodrive keeps, and held there
	if not g._traffic.send(a + dir * (5.0 + AHEAD), dir, {"lane": "kerb"}):
		return {}
	var held = null
	for c in g._traffic.cars:
		if c.alive:
			held = c
	held.hit = 1000.0
	held.v = 0.0
	for c in g._traffic.cars:
		if c != held:
			c.alive = false
	g._ap_passed = -1
	g._set_dest(a + dir * 145.0, "racer moves")
	g._set_racer(true)
	var c0: Dictionary = probe._counts.duplicate()
	var e0: int = probe._events.size()
	var passes0: int = g._racer.passes
	var mounts0: int = g._racer.mounts
	var t := 0.0
	var past := false
	while t < 40.0:
		await physics_frame
		t += Engine.time_scale / Engine.physics_ticks_per_second
		held.hit = 1000.0
		held.v = 0.0
		if OS.get_environment("VERBOSE") != "" and int(t * 60.0) % 120 == 0:
			print("   t %.0f v %.1f why %s lead %.1f wait %.1f turn_ahead %d passed_i %d held_i %d to_held %.1f plan_off %.2f" % [t, g._v, g._ap_why,
				g._ap_lead, g._ap_wait, g._ap_turn_ahead(), g._ap_passed, g._traffic.cars.find(held), ((held.pos as Vector2) - (g._pos as Vector2)).dot(dir), _plan_off(held.pos)])
		if ((g._pos as Vector2) - (held.pos as Vector2)).dot(dir) > 8.0:
			past = true
			break
	var people := 0
	var crashes := 0
	for i in range(e0, probe._events.size()):
		var ev: Dictionary = probe._events[i]
		if String(ev["kind"]) == "crash":
			crashes += 1
			if String((ev["data"] as Dictionary).get("hit", "")) == "person":
				people += 1
	g._set_racer(false)
	return {"kind": kind, "street": sp[2], "past": past, "secs": snappedf(t, 0.1),
		"passed": g._racer.passes - passes0, "pavement": g._racer.mounts - mounts0,
		"crashes": crashes, "people_hit": people}

## how far autodrive's plan runs from p (its nearest point)
func _plan_off(p: Vector2) -> float:
	var best := INF
	var pts: PackedVector2Array = g._ap_pts
	var along := 0.0
	for j in range(pts.size() - 1):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p))
		along += pts[j].distance_to(pts[j + 1])
		if along > 120.0:
			break   # (the stretch ahead: a plan round the block comes back along the same street)
	return best
