extends SceneTree
## The green wave (wave.gd): autodrive comes up to a junction with lights, going straight on,
## with the wave switched on, the light starting at its worst for the car -- red, the cross
## street's green just begun -- and, as a check that the case would have stopped it, the same
## with the wave off. Per case: did the car stop or slow under 2 m/s before the line, the
## light its way as its nose crossed the line, seconds until it turned green, a red run (the
## game's own count), the cross street's lights in order (must go through amber to red, never
## straight from green), and whether the junction was back on the city's clock RELEASE_S
## seconds after the car went through.
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/green_wave.gd
## GW_N junctions (default 4). PASS: with the wave, none stopped, none in on red, every cross
## street's green ended through its amber, and every junction back in step; without it, at
## least one stopped (else the cases tell nothing).
var g: Node
const BACK := 250.0          ## the car starts this far before the stop line (at its pace by the time it is asked)
const RELEASE_S := 60.0

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
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var want := int(OS.get_environment("GW_N")) if OS.get_environment("GW_N") != "" else 4
	# lit points with a way in that runs back straight BACK m along one street, one per site,
	# and a road on past the junction the same way (somewhere to go straight on to)
	var picks: Array = []
	var sites := {}
	for n: int in g._sig_set:
		var s: int = g._site_of.get(n, -1)
		if sites.has(s) or not g._in_city(g._nodes[n]) or priv.near(avoid, g._nodes[n]):
			continue
		for way: Array in g._sig_line.get(n, []):
			if way[3]:
				continue
			var w0: Vector2 = way[0]
			var back: Vector2 = g._nodes[n] - w0 * (float(way[1]) + BACK)
			var hit: Dictionary = g._nearest_seg(back, 5.0, true, true)
			var mid: Dictionary = g._nearest_seg(g._nodes[n] - w0 * (float(way[1]) + BACK * 0.5), 5.0, true, true)
			var on: Dictionary = g._nearest_seg(g._nodes[n] + w0 * 60.0, 6.0, true, true)
			if hit.is_empty() or mid.is_empty() or on.is_empty():
				continue
			if int(hit["road"]) != int(mid["road"]) and String(g._roads[hit["road"]]["name"]) != String(g._roads[mid["road"]]["name"]):
				continue
			var crowded := false
			for p: Array in picks:
				if (g._nodes[p[0]] as Vector2).distance_to(g._nodes[n]) < 300.0:
					crowded = true
			if crowded:
				continue
			sites[s] = true
			picks.append([n, way, back, String(g._roads[mid["road"]].get("name", ""))])
			break
		if picks.size() >= want:
			break
	print("green_wave: %d junctions in %s" % [picks.size(), g._city_id])
	var bad := 0
	var runs := 0
	var control_stops := 0
	for p: Array in picks:
		for wave: bool in [false, true]:
			var res := await _case(p, wave)
			if res.is_empty():
				continue
			print("WAVE %s" % JSON.stringify(res))
			if wave:
				runs += 1
				if not res["ok"]:
					bad += 1
			elif res["stopped"]:
				control_stops += 1
	var ok := bad == 0 and runs > 0 and control_stops > 0
	print("WAVE: %s (%d of %d bad; without the wave %d stopped)" % ["PASS" if ok else "FAIL", bad, runs, control_stops])
	quit(0)

func _phase_of(grp: int, mine: String, theirs: String) -> int:
	for k in range(g.SIGNAL_CYCLE.size()):
		if String(g.SIGNAL_CYCLE[k][grp]) == mine and String(g.SIGNAL_CYCLE[k][3 - grp]) == theirs:
			return k
	return -1

func _case(p: Array, wave: bool) -> Dictionary:
	var n: int = p[0]
	var way: Array = p[1]
	var w0: Vector2 = way[0]
	var line: float = way[1]
	var node: Vector2 = g._nodes[n]
	var s: int = g._site_of.get(n, -1)
	for c in g._traffic.cars:
		c.alive = false
		c.retry = 1000.0
	g._set_auto(false)
	g._set_wave(false)
	for k: int in g._wave.ovr.keys():
		g._wave._drop(k)
	if not g._land_on_road(p[2], 6.0, w0):
		return {}
	await physics_frame
	g._set_dest(node + w0 * 260.0, "green wave test")
	g._set_auto(true)
	g._set_wave(wave)
	var grp: int = g._light_group(n, w0)
	# the worst start: red for the car, the cross street's green just begun
	g._sig_phase = _phase_of(grp, "r", "g")
	g._sig_t = 0.0
	g._apply_signals()
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var reds0: int = g._reds
	var cruising := false
	var slowest := INF
	var at_line := ""
	var green_at := -1.0
	var theirs: Array = []
	var passed_t := -1.0
	var shot_at := -1.0
	while t < 70.0:
		await physics_frame
		t += dt
		var nose: float = (node - (g._pos as Vector2)).dot(w0) - line - g.CAR_LEN * 0.5
		var ph: int = g._ph_at(n)
		var their := String(g.SIGNAL_CYCLE[ph][3 - grp])
		if theirs.is_empty() or theirs[-1] != their:
			theirs.append(their)
		if green_at < 0.0 and String(g.SIGNAL_CYCLE[ph][grp]) == "g":
			green_at = t
		if g._v > 8.0:
			cruising = true
		if cruising and nose > 0.0:
			slowest = minf(slowest, g._v)
		if wave and shot_at < 0.0 and nose <= 14.0 and OS.get_environment("OUT") != "":
			shot_at = t   # (its own lamps, over the shared ones: green for the car, red across)
			root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/wave_%d.png" % n)
		if at_line == "" and nose <= 0.0:
			at_line = String(g.SIGNAL_CYCLE[ph][grp])
		if nose < -(g._node_r[n] * 2.0 + 15.0):
			passed_t = t
			break
	var back_in_step := true
	if wave and passed_t >= 0.0:
		var t2 := 0.0
		while t2 < RELEASE_S and g._wave.ovr.has(s):
			await physics_frame
			t2 += dt
		back_in_step = not g._wave.ovr.has(s)
	if at_line == "":
		print("  (node %d: the car never reached its line, either way -- autodrive went elsewhere: no case)" % n)
		return {}
	var reds: int = g._reds - reds0
	var stopped := slowest < 2.0 or passed_t < 0.0
	# the cross street's green ends through its amber: after a "g" (or flashing) comes "gf" or "y", never "r"
	var amber_ok := true
	for i in range(theirs.size() - 1):
		if String(theirs[i]) in ["g", "gf"] and String(theirs[i + 1]) in ["r", "ry"]:
			amber_ok = false
	var ok: bool = not stopped and reds == 0 and amber_ok and back_in_step and at_line in ["g", "gf"]
	return {"node": n, "street": p[3], "wave": wave, "stopped": stopped,
		"slowest_kmh": snappedf(slowest * 3.6, 1) if slowest < INF else null, "light_at_line": at_line,
		"green_after_s": snappedf(green_at, 0.1), "cross_lights": theirs, "reds": reds,
		"back_in_step": back_in_step, "ok": ok if wave else null}
