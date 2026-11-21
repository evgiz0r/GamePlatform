extends SceneTree
## Racer mode (racer.gd): the same drive by "go to", FROM -> TO (default the route set's
## route 2 in Givatayim, 1.2 km as the crow flies), once with autodrive keeping the rules and
## once with racer on, traffic as usual. Per drive: seconds to get there (or not, in
## TRIP_SECS), red lights run, cars passed (the bus/van pass and racer's), horns from the
## traffic, crashes, people hit or brushed (none allowed, racer or not), the fastest it went.
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/racer.gd
## PASS: racer got there, faster than autodrive, ran at least one red or passed at least one
## car, hit nobody; autodrive ran no red.
var g: Node

func _initialize() -> void:
	_run()

## a junction held at red: racer comes up to it from 150 m back on a straight way in and
## must go through without stopping, counted as a red run ({} if no such junction)
func _red_case() -> Dictionary:
	for n: int in g._sig_set:
		if not g._in_city(g._nodes[n]):
			continue
		for way: Array in g._sig_line.get(n, []):
			if way[3]:
				continue
			var w0: Vector2 = way[0]
			var back: Vector2 = g._nodes[n] - w0 * (float(way[1]) + 150.0)
			var hit: Dictionary = g._nearest_seg(back, 4.0, true, true)
			var mid: Dictionary = g._nearest_seg(g._nodes[n] - w0 * (float(way[1]) + 75.0), 4.0, true, true)
			var on: Dictionary = g._nearest_seg(g._nodes[n] + w0 * 60.0, 6.0, true, true)
			if hit.is_empty() or mid.is_empty() or on.is_empty() or int(hit["road"]) != int(mid["road"]):
				continue
			for c in g._traffic.cars:
				c.alive = false
				c.retry = 1000.0
			g._set_racer(false)
			g._set_auto(false)
			if not g._land_on_road(back, 6.0, w0):
				continue
			await physics_frame
			g._set_dest(g._nodes[n] + w0 * 250.0, "red test")
			g._set_racer(true)
			var grp: int = g._light_group(n, w0)
			var reds0: int = g._reds
			var slowest := INF
			var cruising := false
			var t := 0.0
			var passed := false
			while t < 60.0:
				for k in range(g.SIGNAL_CYCLE.size()):   # (held at red its way all along)
					if String(g.SIGNAL_CYCLE[k][grp]) == "r" and String(g.SIGNAL_CYCLE[k][3 - grp]) == "g":
						g._sig_phase = k
				g._sig_t = 0.0
				await physics_frame
				t += Engine.time_scale / Engine.physics_ticks_per_second
				if g._v > 8.0:
					cruising = true
				if cruising:
					slowest = minf(slowest, g._v)
				if ((g._pos as Vector2) - g._nodes[n]).dot(w0) > g._node_r[n] + 10.0:
					passed = true
					break
			g._set_racer(false)
			return {"node": n, "passed": passed, "reds": g._reds - reds0,
				"slowest_kmh": snappedf(slowest * 3.6, 1) if slowest < INF else 0.0, "hoots": g._racer.hoots}
	return {}

func _vec(key: String, d: Vector2) -> Vector2:
	var s := OS.get_environment(key)
	if s == "":
		return d
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

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
	var from := _vec("FROM", Vector2(187.0, 739.5))
	var to := _vec("TO", Vector2(-968.2, 370.8))
	var limit := float(OS.get_environment("TRIP_SECS")) if OS.get_environment("TRIP_SECS") != "" else 300.0
	var res := {}
	for racing: bool in [false, true]:
		g._set_racer(false)
		g._set_auto(false)
		g._land_on_road(from, 60.0, Vector2.ZERO)
		await physics_frame
		g._set_dest(to, "there")
		g._set_auto(true)
		if racing:
			g._set_racer(true)
		var c0: Dictionary = probe._counts.duplicate()
		var e0: int = probe._events.size()
		var reds0: int = g._reds
		var t := 0.0
		var top := 0.0
		var dt := Engine.time_scale / Engine.physics_ticks_per_second
		var arrived := false
		while t < limit:
			await physics_frame
			t += dt
			top = maxf(top, g._v)
			if not g._dest_on:
				arrived = true
				break
		var d := {}
		for k in ["pass_bus", "pass_van", "squeeze_van", "hoot", "crash", "racer_red", "person_hit", "hit_person"]:
			d[k] = int(probe._counts.get(k, 0)) - int(c0.get(k, 0))
		var people := 0
		var what: Array = []
		var right := 0
		for i in range(e0, probe._events.size()):
			var ev: Dictionary = probe._events[i]
			var data: Dictionary = ev["data"]
			if String(ev["kind"]) == "crash":
				what.append("%s at %d km/h" % [String(data.get("hit", "?")), int(data.get("kmh", 0))])
				if String(data.get("hit", "")) == "person":
					people += 1
			if String(ev["kind"]) in ["pass_bus", "pass_van"] and String(data.get("side", "")) == "right":
				right += 1
		var r := {"racer": racing, "arrived": arrived, "secs": snappedf(t, 0.1), "reds": g._reds - reds0,
			"passed": d["pass_bus"] + d["pass_van"], "hoots": d["hoot"], "crashes": d["crash"],
			"people_hit": people, "top_kmh": snappedf(top * 3.6, 1), "passed_right": right,
			"pavement": int(probe._counts.get("racer_pavement", 0)) - int(c0.get("racer_pavement", 0)), "hit": what}
		res[racing] = r
		print("RACER %s" % JSON.stringify(r))
	var a: Dictionary = res[false]
	var b: Dictionary = res[true]
	var red := await _red_case()
	print("RACER red %s" % JSON.stringify(red))
	var ok: bool = b["arrived"] and (not a["arrived"] or float(b["secs"]) < float(a["secs"])) \
			and int(b["people_hit"]) == 0 and int(a["reds"]) == 0 \
			and not red.is_empty() and bool(red["passed"]) and int(red["reds"]) > 0 and float(red["slowest_kmh"]) > 15.0
	print("RACER: %s" % ("PASS" if ok else "FAIL"))
	quit(0)
