extends SceneTree
## A divided road's zebra (people cross it kerb to kerb, both halves at once): autodrive comes
## up one half while someone crosses -- from the near kerb, then from the far one. How long
## it stands for them, against how long they are on its half. It should wait while they are on
## its half (or about to step onto it), not for the whole crossing: on Givatayim's divided
## roads that is 18-22 m, some 15 s on foot, and a car stood through most of its green for
## someone on the other half, then through a whole red (41 s on the route set's first drive).
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/zebra_halves.gd
## ZH_N crossings (default 3). The other people at crossings are kept off for the test.
## PASS: from the far kerb it did not stop at all, or for no longer than they were on its half
## (and the 2.5 s before they stepped onto it); from the near kerb it went before they reached
## the far kerb.
var g: Node

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
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var want := int(OS.get_environment("ZH_N")) if OS.get_environment("ZH_N") != "" else 3
	# divided roads' crossings, a car's run-up on the one-way half before each
	var picks: Array = []
	for ni: int in g._crossing_nodes:
		var z: Array = g._zebra_geom(ni)
		if z.is_empty():
			continue
		var r: Dictionary = g._roads[int(z[4])]
		if not r.has("median") or int(r["o"]) == 0 or r["pv"]:
			continue
		var sp: Array = g._zebra_span(z)
		if sp.size() < 2 or (sp[0] as Vector2).distance_to(sp[1]) < 14.0:
			continue
		var d: Vector2 = (z[3] as Vector2) * float(r["o"])   # the way the cars go
		var start: Vector2 = (z[0] as Vector2) - d * 45.0
		var hit: Dictionary = g._nearest_seg(start, 4.0, true, true)
		if hit.is_empty() or int(hit["road"]) != int(z[4]) and String(g._roads[int(hit["road"])].get("name", "")) != String(r.get("name", "")):
			continue   # (not the same street 45 m back: a bend, a junction)
		var crowded := false
		for p: Array in picks:
			if (g._nodes[p[0]] as Vector2).distance_to(g._nodes[ni]) < 150.0:
				crowded = true
		if crowded:
			continue
		picks.append([ni, start, d, sp])
		if picks.size() >= want:
			break
	print("zebra halves: %d crossings in %s" % [picks.size(), g._city_id])
	g._zebra_t = 1.0e9   # (no one else sent to a crossing)
	var bad := 0
	for p: Array in picks:
		for from_far: bool in [false, true]:
			var res := await _case(p, from_far)
			if res.is_empty():
				continue
			if not res["ok"]:
				bad += 1
			print("ZEBRA HALVES %s" % JSON.stringify(res))
	print("ZEBRA HALVES: %s (%d bad)" % ["PASS" if bad == 0 and not picks.is_empty() else "FAIL", bad])
	quit(0)

func _case(p: Array, from_far: bool) -> Dictionary:
	var ni: int = p[0]
	var mid: Vector2 = g._nodes[ni]
	var sp: Array = p[3]
	var near_end: Vector2 = sp[0] if (sp[0] as Vector2).distance_to(mid) < (sp[1] as Vector2).distance_to(mid) else sp[1]
	var far_end: Vector2 = sp[1] if near_end == sp[0] else sp[0]
	for cr: Dictionary in g._crossers:
		cr["state"] = "off"
		(cr["actor"] as Node3D).visible = false
	for c in g._traffic.cars:
		if c.alive and c.pos.distance_to(mid) < 120.0:
			c.alive = false   # (the street to ourselves)
	g._set_auto(false)
	if not g._land_on_road(p[1], 6.0, p[2]):
		return {}
	await physics_frame
	g._set_auto(true)
	var cr: Dictionary = g._crossers[0]
	cr["ni"] = ni
	cr["a"] = far_end if from_far else near_end
	cr["b"] = near_end if from_far else far_end
	cr["s"] = 0.0
	cr["state"] = "wait"
	cr["t"] = 1.0e9
	cr["sig"] = -1
	cr["speed"] = 1.3
	(cr["actor"] as Node3D).visible = true
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var went := false
	var stood := 0.0
	var on_mine := 0.0      # seconds the person was on the car's half while the car was short of it
	var passed := -1.0
	var gone := -1.0
	var hw: float = float(g._roads[g._zebra_geom(ni)[4]]["w"]) * 0.5
	while t < 40.0:
		await physics_frame
		t += dt
		var my_d: float = (g._pos as Vector2).distance_to(mid)
		if not went and my_d < 30.0:
			went = true
			cr["state"] = "cross"
			cr["actor"].play("Walk", true, 1.0)
		var ahead: bool = ((mid - g._pos) as Vector2).dot(g._fwd()) > 0.0
		if went and ahead:
			if absf(g._v) < 0.3 and g._ap_why == "zebra":
				stood += dt
			if cr["state"] == "cross":
				var at: Vector2 = (cr["a"] as Vector2).lerp(cr["b"], float(cr["s"]))
				if absf((at - mid).dot(((cr["b"] as Vector2) - (cr["a"] as Vector2)).normalized())) < hw + 1.0:
					on_mine += dt
		if passed < 0.0 and not ahead and my_d > 3.0:
			passed = t
		if gone < 0.0 and went and cr["state"] != "cross":
			gone = t
		if passed > 0.0 and t > passed + 1.0:
			break
	# from the far kerb: it waits no longer than they were on its half; from the near: it is
	# by before they reach the far kerb
	# (+4 s: it also waits while they are about to step onto its half, 2.5 s out, and the
	# metre past its edge as they step off)
	var ok := passed > 0.0 and (stood <= on_mine + 4.0 if from_far else (gone < 0.0 or passed < gone))
	return {"node": ni, "street": String(g._roads[g._zebra_geom(ni)[4]].get("name", "")), "from": "far kerb" if from_far else "near kerb",
		"span": snappedf((sp[0] as Vector2).distance_to(sp[1]), 0.1), "stood": snappedf(stood, 0.1), "on_its_half": snappedf(on_mine, 0.1),
		"car_by_at": snappedf(passed, 0.1), "crossing_done_at": snappedf(gone, 0.1), "ok": ok}
