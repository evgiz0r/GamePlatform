extends SceneTree
## One drive of the route set (routes.json beside the game, picked by pick_routes.py): ROUTE=n. The car
## set down at its "from" address, "go to" its "to", autodrive there (TRIP_SECS, default 600).
## Prints one line "ROUTE RESULT {...}" (arrived, seconds, metres, hits, standstills of 5 s+
## and what held them, red lights run, rescues, seconds off the asphalt) for
## route_report.py, and saves the drive logs (user://drive_logs/route-<n>-*.json, every two
## minutes and at the end) to draw it. Run headless and fast (run_routes.sh does):
##   ROUTE=3 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/route_set.gd
var g: Node

func _initialize() -> void:
	_run()

func _save_log(n: int, tag: String) -> String:
	var f: String = g._log.save(g)
	var named := f.get_base_dir() + "/route-%d-%s.json" % [n, tag]
	DirAccess.rename_absolute(f, named)
	return named

## TRACE=path (see the loop): a row every tenth of a second for drawing the drive
## (tests/drive_trace.py makes the data for a chart of it). LEADLOG=1: a line for each car
## that turns up close in front, or holds itself for the player in front of it.
func _run() -> void:
	var n := int(OS.get_environment("ROUTE")) if OS.get_environment("ROUTE") != "" else 1
	var f := FileAccess.open("res://game/streets/routes.json", FileAccess.READ)
	var all: Dictionary = JSON.parse_string(f.get_as_text())
	var route: Dictionary = {}
	for r: Dictionary in all["routes"]:
		if int(r["id"]) == n:
			route = r
	if route.is_empty():
		print("no route %d" % n)
		quit(1)
		return
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(route["level"])})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var from := Vector2(float(route["from_at"][0]), float(route["from_at"][1]))
	var to := Vector2(float(route["to_at"][0]), float(route["to_at"][1]))
	g._land_on_road(from, 60.0, Vector2.ZERO)
	await physics_frame
	g._set_dest(to, String(route["to"]))
	g._set_auto(true)
	var planned := true
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var odo0: float = g._odo
	var still := 0.0
	var held := ""
	var stills: Array = []
	var hits: Array = []
	var last_hit: String = g._last_hit
	var hit_log := 0.0
	var last_v := 0.0
	var reds0: int = g._reds
	var events0: int = g._log.events.size()
	var off := 0.0
	var arrived := false
	var next_log := 120.0
	var limit := float(OS.get_environment("TRIP_SECS")) if OS.get_environment("TRIP_SECS") != "" else 600.0
	# TRACE=path: a row every tenth of a second -- [t, x, z, km/h, limit km/h, why, street,
	# acceleration (m/s^2), the light it reads (its colour for my way, metres to its stop; "" -1),
	# the car it follows (metres, km/h, what holds that car; -1 0 ""), the car it gives way to
	# (metres, km/h; -1 0)] -- and the plan at the start; written as JSON at the end
	var trace := OS.get_environment("TRACE")
	var rows: Array = []
	var plan0: Array = []
	for q: Vector2 in g._ap_pts:
		plan0.append([snappedf(q.x, 0.1), snappedf(q.y, 0.1)])
	var tick := 0
	var v_prev: float = g._v
	var knocked0: int = g._knocked_n
	var leadlog := OS.get_environment("LEADLOG") != ""
	var lead_was := -1
	var told := {}
	while t < limit:
		await physics_frame
		dt = Engine.time_scale / Engine.physics_ticks_per_second
		t += dt
		tick += 1
		if trace != "" and tick % 6 == 0:
			var lim: float = g._ap_lim[mini(1, g._ap_lim.size() - 1)] if g._ap_lim.size() > 0 else 0.0
			var li: Array = g._ap_light_dbg
			var lead := [-1.0, 0.0, ""]
			if g._ap_lead >= 0.0 and g._ap_lead_i >= 0 and g._ap_lead_i < g._traffic.cars.size():
				var lc = g._traffic.cars[g._ap_lead_i]
				lead = [snappedf(g._ap_lead, 0.1), snappedf(lc.v * 3.6, 0.1), String(lc.why)]
			var give := [-1.0, 0.0]
			if g._ap_give_car >= 0 and g._ap_give_car < g._traffic.cars.size():
				var gc = g._traffic.cars[g._ap_give_car]
				give = [snappedf(gc.pos.distance_to(g._pos), 0.1), snappedf(gc.v * 3.6, 0.1)]
			rows.append([snappedf(t, 0.1), snappedf(g._pos.x, 0.1), snappedf(g._pos.y, 0.1), snappedf(g._v * 3.6, 0.1),
				snappedf(lim * 3.6, 1), String(g._ap_why), String(g._on_name), snappedf((g._v - v_prev) / (6.0 * dt), 0.01),
				String(li[1]) if li.size() > 2 else "", snappedf(float(li[2]), 0.1) if li.size() > 2 else -1.0,
				lead[0], lead[1], lead[2], give[0], give[1]])
			v_prev = g._v
		if leadlog:
			# LEADLOG=1: a car that turns up close in front (under 15 m, not followed the tick
			# before), or holds itself for the player while in front of it: how it stands
			var li2: int = g._ap_lead_i if g._ap_lead >= 0.0 else -1
			if li2 >= 0 and li2 < g._traffic.cars.size():
				var lc2 = g._traffic.cars[li2]
				var key := "%d" % li2
				if (li2 != lead_was and g._ap_lead < 15.0) or (String(lc2.why) == "player" and not told.has(key)):
					told[key] = true
					var cf := Vector2(sin(lc2.yaw), cos(lc2.yaw))
					var rel: Vector2 = g._pos - lc2.pos
					var rn: Dictionary = g._traffic._roads[lc2.rd[mini(lc2.k, lc2.rd.size() - 1)]] if lc2.rd.size() > 0 else {}
					print("LEAD t %.1f at %.1f m: car %d %s v %.1f why %s pos (%.1f,%.1f) heading off mine %.0f deg; me from it: %.1f ahead %.1f left; its road %s k %d/%d shift %.2f->%.2f realign %s; gap to me on its path %.1f" % [
						t, g._ap_lead, li2, lc2.kind, lc2.v * 3.6, lc2.why, lc2.pos.x, lc2.pos.y,
						rad_to_deg(absf(angle_difference(atan2(cf.y, cf.x), g._yaw))), rel.dot(cf), rel.dot(Vector2(-cf.y, cf.x)),
						String(rn.get("name", "?")), lc2.k, lc2.pts.size(), lc2.shift, lc2.shift_to, str(lc2.realign),
						g._traffic._path_gap(lc2, g._pos, 60.0, g._traffic.PLAYER_W)])
			lead_was = li2
			# and standing 5 s giving way to a car that stands too: what holds that one
			var gi: int = g._ap_give_car
			if absf(g._v) < 0.3 and gi >= 0 and gi < g._traffic.cars.size() and still >= 5.0 and not told.has("g%d" % gi):
				var gc2 = g._traffic.cars[gi]
				if gc2.v < 0.3:
					told["g%d" % gi] = true
					print("GIVE t %.1f standing %.1f s giving way to car %d %s, standing too %.1f m off: why %s, held by %d, its wait %.1f s; wants %.1f, react %.1f/%.1f, hit %.1f, jwait %.1f, holding %s, still %.1f, at (%.1f,%.1f)" % [
						t, still, gi, gc2.kind, gc2.pos.distance_to(g._pos), gc2.why, gc2.blocker, gc2.wait, gc2.want, gc2.react_t, gc2.react, gc2.hit, gc2.jwait, str(gc2.holding), gc2.still, gc2.pos.x, gc2.pos.y])
		if not g._dest_on:
			# arrived -- or gave up at once: "can't find a way there from here" clears the
			# destination too (a route read as arrived in 0 s with 1.3 km to go)
			arrived = g._pos.distance_to(to) < 40.0
			planned = arrived or t > 2.0
			break
		if absf(g._v) < 0.3:
			if still == 0.0:
				held = g._log._why(g)
			still += dt
		else:
			if still >= 5.0:
				stills.append([snappedf(still, 0.1), held, [int(g._pos.x), int(g._pos.y)], g._on_name])
			still = 0.0
		var h: String = g._last_hit
		if h != last_hit and h != "" and g._crash_cool > 0.35 and absf(last_v) > 1.0:
			hits.append([h, int(absf(last_v) * 3.6), [int(g._pos.x), int(g._pos.y)], g._on_name])
			hit_log = t + 1.0   # (a log of its own a second after: the two minutes up to it, people and all)
		last_hit = h
		# (knocking a sign or a bin over is no crash -- no `_crash_cool` -- and went uncounted: a
		# one-way sign at the split of a divided road took 19 km/h off autodrive in a tenth of a second)
		if g._knocked_n != knocked0:
			knocked0 = g._knocked_n
			hits.append([String(g._knocked_what), int(absf(last_v) * 3.6), [int(g._pos.x), int(g._pos.y)], g._on_name])
		if hit_log > 0.0 and t >= hit_log:
			hit_log = 0.0
			_save_log(n, "hit%03d" % int(t))
		last_v = g._v
		var on: Dictionary = g._nearest_seg(g._pos, 30.0, true, false)
		if on.is_empty() or float(on["edge"]) > 1.0:
			off += dt
		if t >= next_log:
			next_log += 120.0
			_save_log(n, "%03d" % int(t))
		if not g._auto:
			break
	var rescues: Array = []
	for ev: Array in g._log.events.slice(events0):
		if String(ev[1]) in ["rescue", "unstuck"]:
			rescues.append([String(ev[1]), int(ev[0])])
	var longest := 0.0
	for s: Array in stills:
		longest = maxf(longest, float(s[0]))
	var res := {"id": n, "city": route["city"], "from": route["from"], "to": route["to"],
		"arrived": arrived, "no_way": not planned, "secs": int(t), "metres": int(g._odo - odo0),
		"left_m": int(g._pos.distance_to(to)), "hits": hits, "stills": stills,
		"longest_wait": snappedf(longest, 0.1), "reds": g._reds - reds0, "rescues": rescues,
		"off_road_s": snappedf(off, 0.1)}
	_save_log(n, "end")
	if trace != "":
		var tf := FileAccess.open(trace, FileAccess.WRITE)
		tf.store_string(JSON.stringify({"route": res, "level": route["level"], "plan": plan0, "dest": [to.x, to.y],
			"columns": ["t", "x", "z", "kmh", "limit_kmh", "why", "street", "accel", "light", "light_m", "lead_m", "lead_kmh", "lead_why", "give_m", "give_kmh"],
			"rows": rows}))
		tf.close()
		print("trace: %d rows to %s" % [rows.size(), trace])
	print("ROUTE RESULT " + JSON.stringify(res))
	quit(0)
