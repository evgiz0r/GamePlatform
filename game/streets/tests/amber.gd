extends SceneTree
## The end of a green, from autodrive's seat: it comes up to a light at the town's pace, and
## when its nose is D metres from the stop line the light goes to the end of its green --
## the flashing green (Israel's: 3 s, then 3 s of amber) or straight to amber (North
## America's, and Israel's to test the amber alone). Each D, going straight on and turning
## left. Per case: on through or stopped, a red run (the game's own count), the hardest
## braking (over half a second), and where it stopped. The rest of the traffic and the people at crossings off.
##   LEVEL=3 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/amber.gd
## AM_N junctions (default 3). Keeps away from the places tests/pick_routes.py keeps away from.
## PASS: no red run, no braking over 5 m/s^2, none stopped more than 2 m over its line, and
## none left standing more than 4 m short of it (where it stands 6 s on: rolled up to it).
## (Before: "too late to stop at 3 m/s^2" went on at 50 km/h into a left turn, slowed for the
## corner, and the amber ran out short of the line -- the route set's one red.)
## (And: the stop braked at 1.5 m/s^2 at least, wherever the line was -- a green ending 80 m off
## stopped the car 23 m on, and it stood there, 57 m short, all through the red. A user, twice.)
var g: Node
const DS := [10.0, 20.0, 30.0, 40.0, 55.0, 80.0]

func _initialize() -> void:
	_run()

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
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var want := int(OS.get_environment("AM_N")) if OS.get_environment("AM_N") != "" else 3
	# lit points with a way in that runs back straight 110 m along one street, one per site
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
			var back: Vector2 = g._nodes[n] - w0 * (float(way[1]) + 110.0)
			var hit: Dictionary = g._nearest_seg(back, 5.0, true, true)
			var mid: Dictionary = g._nearest_seg(g._nodes[n] - w0 * (float(way[1]) + 50.0), 5.0, true, true)
			if hit.is_empty() or mid.is_empty() or int(hit["road"]) != int(mid["road"]) and String(g._roads[hit["road"]]["name"]) != String(g._roads[mid["road"]]["name"]):
				continue
			var crowded := false
			for p: Array in picks:
				if (g._nodes[p[0]] as Vector2).distance_to(g._nodes[n]) < 200.0:
					crowded = true
			if crowded:
				continue
			sites[s] = true
			picks.append([n, way, back, String(g._roads[mid["road"]].get("name", ""))])
			break
		if picks.size() >= want:
			break
	print("amber: %d lights in %s, cycle %s" % [picks.size(), g._city_id, "with a flashing green" if _phase_of(1, "gf") >= 0 else "without"])
	for cr: Dictionary in g._crossers:
		cr["state"] = "off"
		(cr["actor"] as Node3D).visible = false
	g._zebra_t = 1.0e9
	var bad := 0
	var runs := 0
	var starts: Array = ["gf", "y"] if _phase_of(1, "gf") >= 0 else ["y"]
	for p: Array in picks:
		for go: String in ["straight", "left"]:
			for st: String in starts:
				for d: float in DS:
					if OS.get_environment("AM_D") != "" and d != float(OS.get_environment("AM_D")):
						continue   # (one distance only)
					var res := await _case(p, go, st, d)
					if res.is_empty():
						continue
					runs += 1
					if not res["ok"]:
						bad += 1
					print("AMBER %s" % JSON.stringify(res))
	print("AMBER: %s (%d of %d bad)" % ["PASS" if bad == 0 and runs > 0 else "FAIL", bad, runs])
	quit(0)

## the first phase where group grp shows `st`, or -1
func _phase_of(grp: int, st: String) -> int:
	for k in range(g.SIGNAL_CYCLE.size()):
		if String(g.SIGNAL_CYCLE[k][grp]) == st:
			return k
	return -1

func _case(p: Array, go: String, st: String, d: float) -> Dictionary:
	var n: int = p[0]
	var way: Array = p[1]
	var w0: Vector2 = way[0]
	var line: float = way[1]
	var node: Vector2 = g._nodes[n]
	for c in g._traffic.cars:
		c.alive = false
		c.retry = 1000.0
	g._set_auto(false)
	if not g._land_on_road(p[2], 6.0, w0):
		return {}
	await physics_frame
	var left := Vector2(w0.y, -w0.x)
	g._set_dest(node + (w0 * 120.0 if go == "straight" else left * 100.0 + w0 * 8.0), "amber test")
	g._set_auto(true)
	var grp: int = g._light_group(n, w0)
	var green := _phase_of(grp, "g")
	var end_at := _phase_of(grp, st)
	g._sig_phase = green
	g._sig_t = 0.0
	g._apply_signals()
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var reds0: int = g._reds
	var switched := -1.0
	var v_then := 0.0
	var brake := 0.0
	var vs: Array = []   # (the speed the last half second: braking read over that -- one tick
	                     # read 15 m/s^2 where the last creep is zeroed as the car stands)
	var stood := 0.0
	var stop_at := INF   # (where it stands at the end: its nose short of the line)
	var first_stop := INF   # (where it first came to a stand)
	var passed := false
	while t < 40.0:
		await physics_frame
		t += dt
		var nose: float = (node - (g._pos as Vector2)).dot(w0) - line - g.CAR_LEN * 0.5   # (to the line)
		if switched < 0.0:
			g._sig_t = 0.0   # (green, held, until then)
			if nose <= d:
				if nose < d - 6.0:
					return {}   # (it came in some other way: no case)
				g._sig_phase = end_at
				g._sig_t = 0.0
				g._apply_signals()
				switched = t
				v_then = g._v
		else:
			if t - switched > 1.5 and g._sig_t == 0.0 and g._sig_phase == end_at:
				print("  (the lights are not ticking: no case)")
				return {}
			vs.append(float(g._v))
			if vs.size() > 30:
				vs.pop_front()
				brake = maxf(brake, (float(vs[0]) - float(g._v)) / (29.0 * dt))
			if OS.get_environment("VERBOSE") != "" and int(t * 60.0) % 15 == 0:
				print("  t %.2f phase %d (%.1f s in) light %s, red in %.1f, nose %.1f m at %.1f m/s, allowed %.1f (%s)" % [t - switched, g._sig_phase, g._sig_t,
					g._light_at(n, w0), g._light_red_in(n, w0) if g.has_method("_light_red_in") else -1.0, nose, g._v, g._ap_light_v(), g._ap_why])
			if absf(g._v) < 0.2:
				stood += dt
				stop_at = nose
				if first_stop == INF:
					first_stop = nose
				if stood > 6.0:
					break   # (6 s standing: where it waits)
			else:
				stood = 0.0
			if nose < -(g._node_r[n] * 2.0 + 10.0):
				passed = true
				break
	if switched < 0.0:
		return {}
	var reds: int = g._reds - reds0
	var ok: bool = reds == 0 and brake <= 5.0 and (stop_at == INF or (stop_at > -2.0 and stop_at < 4.0))
	return {"node": n, "street": p[3], "going": go,
		"from": st, "at_m": d, "kmh": snappedf(v_then * 3.6, 1), "did": "stopped" if first_stop < INF else ("on through" if passed else "neither"),
		"stopped_m_short": snappedf(stop_at, 0.1) if stop_at < INF else null, "first_stood_m_short": snappedf(first_stop, 0.1) if first_stop < INF else null, "hardest_brake": snappedf(brake, 0.1), "reds": reds, "ok": ok}
