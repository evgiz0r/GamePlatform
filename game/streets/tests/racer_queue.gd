extends SceneTree
## Racer behind cars standing at a red (the user, 22 Nov 2026: "we were 2 cars standing in a
## red light on a 3 lane street, in racer mode"). Racer should go round a standing car -- left
## or right where there are two lanes or more its way -- and on through the red; behind a queue
## that does not move, up onto the pavement. Stages it: a lit junction whose way in has 2+
## lanes its way and a straight 150 m, held at red; CARS (default 1) traffic cars standing in
## the kerb lane at the line, the rest of traffic off; racer from 150 m back, going straight on.
## Prints every second (VERBOSE=1) what holds it, and at the end whether it got through, how
## long it stood, and the passes. PASS: through the junction within 40 s, standing under 3 s,
## its body never 0.1 m into a car's (squeezing by brushes, it does not drive into them).
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/racer_queue.gd
## LANE=n puts the cars in lane n (0 = kerb); SKIP=n takes the n-th such junction; TURN=right
## or left sends racer off that way at the junction (its plan turns there); ALL_LANES=1 puts
## CARS in every lane, side by side; TWO_WAY=1 takes only two-way streets (one lane its way
## or more: racer goes past the queue in the other way's lanes).
const Bodies := preload("res://game/streets/tests/bodies.gd")
var g: Node

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(_env("LEVEL", "1"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	var tr = g._traffic
	var ncars := int(_env("CARS", "1"))
	var lane := int(_env("LANE", "0"))
	var skip := int(_env("SKIP", "0"))
	var verbose := OS.get_environment("VERBOSE") != ""
	var all_lanes := OS.get_environment("ALL_LANES") != ""
	var two_way := OS.get_environment("TWO_WAY") != ""
	for n: int in g._sig_set:
		if not g._in_city(g._nodes[n]):
			continue
		for way: Array in g._sig_line.get(n, []):
			if way[3]:
				continue
			var w0: Vector2 = way[0]
			var line_at: Vector2 = g._nodes[n] - w0 * float(way[1])
			var back: Vector2 = line_at - w0 * 150.0
			var hit: Dictionary = g._nearest_seg(back, 4.0, true, true)
			var mid: Dictionary = g._nearest_seg(line_at - w0 * 75.0, 4.0, true, true)
			var near: Dictionary = g._nearest_seg(line_at - w0 * 8.0, 4.0, true, true)
			var on: Dictionary = g._nearest_seg(g._nodes[n] + w0 * 60.0, 6.0, true, true)
			if hit.is_empty() or mid.is_empty() or near.is_empty() or on.is_empty() or int(hit["road"]) != int(mid["road"]):
				continue
			var r: Dictionary = g._roads[int(near["road"])]
			var nl: int = g._lanes_each_way(r)
			# TWO_WAY=1: a two-way street (one lane its way will do: past the queue on the other side)
			if two_way and int(r["o"]) != 0:
				continue
			if nl < (1 if two_way else 2) or lane >= nl:
				continue
			if skip > 0:
				skip -= 1
				continue
			for c in tr.cars:
				c.alive = false
				c.retry = 1000.0
			g._set_racer(false)
			g._set_auto(false)
			if not g._land_on_road(back, 6.0, w0):
				continue
			await physics_frame
			var grp: int = g._light_group(n, w0)
			var hold := func() -> void:
				for k in range(g.SIGNAL_CYCLE.size()):   # (held at red its way all along)
					if String(g.SIGNAL_CYCLE[k][grp]) == "r" and String(g.SIGNAL_CYCLE[k][3 - grp]) == "g":
						g._sig_phase = k
				g._sig_t = 0.0
			hold.call()
			# the cars at the line, one behind the other, in lane `lane`
			var put := 0
			for c in tr.cars:
				if put >= (ncars * nl if all_lanes else ncars):
					break
				if c.kind == "bus" or c.kind == "moto":
					continue
				# ALL_LANES=1: CARS deep in every lane, side by side (a real red: every lane queued)
				var row := put / nl if all_lanes else put
				var ln := put % nl if all_lanes else lane
				var at := line_at - w0 * (3.5 + 6.5 * row)
				# (on the way in's own road: by the nearest middle alone, 3.5 m short of the line,
				# a car was put on the crossing street, standing 58 degrees across racer's way)
				var ri: int = int(near["road"])
				var p: PackedVector2Array = (g._roads[ri] as Dictionary)["pts"]
				var sh := {"road": ri, "seg": 0, "q": p[0]}
				var bd := INF
				for j in range(p.size() - 1):
					var cq := Geometry2D.get_closest_point_to_segment(at, p[j], p[j + 1])
					if cq.distance_to(at) < bd:
						bd = cq.distance_to(at)
						sh = {"road": ri, "seg": j, "q": cq}
				if bd > 3.0:
					continue
				var sj: int = sh["seg"]
				var dir := 1 if (p[sj + 1] - p[sj]).dot(w0) >= 0.0 else -1
				if not tr._start_on(c, int(sh["road"]), sj, sh["q"], dir):
					continue
				c.alive = true
				c.lane_i = ln
				c.shift = tr._lane_shift(g._roads[int(sh["road"])], ln)
				c.shift_to = c.shift
				c.rear = Vector2.INF   # (its back put afresh in the lane: set after, the nose jumped a lane over and the back stayed, the car 58 degrees across)
				tr._place(c)
				c.lane_t = 999.0
				c.v = 0.0
				c.retry = 1000.0
				put += 1
			# TURN=right / left: to a point off to that side of the junction (the plan turns there)
			var dest: Vector2 = g._nodes[n] + w0 * 250.0
			if _env("TURN", "") != "":
				var sd := Vector2(-w0.y, w0.x) * (1.0 if _env("TURN", "") == "right" else -1.0)
				dest = g._nodes[n] + sd * 200.0 + w0 * 20.0
			g._set_dest(dest, "racer queue")
			g._set_racer(true)
			print("JUNCTION %d at (%.0f, %.0f): way in on %s (%s, %.1f m wide, %d lanes its way, o%d); %d car(s) at the line in lane %d" % [
				n, g._nodes[n].x, g._nodes[n].y, String(r.get("en", r["name"])), r["k"], float(r["w"]), nl, int(r["o"]), put, lane])
			var probe = root.get_node("Probe")
			var c0: Dictionary = (probe._counts as Dictionary).duplicate()
			var p0: int = g._racer.passes
			var m0: int = g._racer.mounts
			var t := 0.0
			var stood := 0.0
			var passed := false
			var inside := false
			var touch := 0.0   # deepest racer's body went into a car's
			var last_s := -1
			while t < 40.0:
				hold.call()
				for c in tr.cars:   # (the cars at the line stay put: a red, held)
					if c.alive and c.pos.distance_to(line_at) < 20.0:
						c.v = 0.0
				await physics_frame
				var pbx: Array = Bodies.player_box(g)
				for c in tr.cars:
					if c.alive and c.pos.distance_to(g._pos) < 8.0:
						touch = maxf(touch, Bodies.box_depth(pbx, Bodies.car_box(c)))
				t += Engine.time_scale / Engine.physics_ticks_per_second
				if absf(float(g._v)) < 0.3 and t > 3.0:
					stood += Engine.time_scale / Engine.physics_ticks_per_second
				if verbose and int(t) != last_s:
					last_s = int(t)
					print("  t %2d: %.0f m to the line, %.1f m/s, held by %s, lead %.1f m (car %d), wait %.1f, turn ahead %d; queue: %s" % [
						last_s, (line_at - (g._pos as Vector2)).dot(w0), g._v, g._ap_why, g._ap_lead, g._ap_lead_i, g._ap_wait, g._ap_turn_ahead(), g._race_q_why])
					if g._ap_lead_i >= 0:
						var lc = tr.cars[g._ap_lead_i]
						var lb := INF
						for j in range(g._ap_pts.size() - 1):
							lb = minf(lb, Geometry2D.get_closest_point_to_segment(lc.pos, g._ap_pts[j], g._ap_pts[j + 1]).distance_to(lc.pos))
						print("       the car in front %.2f m off the plan (%d points, the first %.1f m off)" % [lb, g._ap_pts.size(), (g._ap_pts[0] as Vector2).distance_to(g._pos)])
						var cd := Vector2(sin(lc.yaw), cos(lc.yaw))
						var pts := []
						for off: float in [-lc.len * 0.5 + 0.3, -lc.len * 0.33, 0.0, lc.len * 0.33, lc.len * 0.5 - 0.3]:
							var bq: Vector2 = lc.pos + cd * off
							var bb := INF
							for j in range(g._ap_pts.size() - 1):
								bb = minf(bb, Geometry2D.get_closest_point_to_segment(bq, g._ap_pts[j], g._ap_pts[j + 1]).distance_to(bq))
							pts.append("%.2f" % bb)
						var l3: Array = tr.lead_on(g._ap_pts, g._pos, 60.0, false, g._y)
						print("       its body points off the plan %s; lead_on %.1f car %d; its heading against the plan's %.0f deg" % [", ".join(pts), float(l3[0]), int(l3[3]), rad_to_deg(acos(clampf(cd.dot(((g._ap_pts[1] as Vector2) - (g._ap_pts[0] as Vector2)).normalized()), -1.0, 1.0)))])
					var asides := []
					for c in tr.cars:
						if c.alive and absf(float(c.aside)) > 0.01:
							asides.append("%.2f" % float(c.aside))
					if not asides.is_empty():
						print("       edged aside: %s" % ", ".join(asides))
				# through: in the junction, then out of it any way (a turn too)
				var dn: float = (g._pos as Vector2).distance_to(g._nodes[n])
				if dn < float(g._node_r[n]) + 3.0:
					inside = true
				if inside and dn > float(g._node_r[n]) + 10.0:
					passed = true
					break
			var ev := []
			for k in ["pass_bus", "racer_pass", "racer_queue", "racer_pavement", "crash"]:
				var d := int(probe._counts.get(k, 0)) - int(c0.get(k, 0))
				if d > 0:
					ev.append("%s %d" % [k, d])
			if int(g._racer.passes) > p0:
				ev.append("racer passes %d" % (int(g._racer.passes) - p0))
			if int(g._racer.mounts) > m0:
				ev.append("onto the pavement %d" % (int(g._racer.mounts) - m0))
			print("RACER QUEUE: through %s in %.1f s, stood %.1f s, into a car %.2f m; %s" % [str(passed), t, stood, touch, ", ".join(ev) if not ev.is_empty() else "no passes"])
			print("RACER QUEUE RESULT: %s" % ("PASS" if passed and stood < 3.0 and touch < 0.1 else "FAIL"))
			quit(0)
			return
	print("RACER QUEUE: no lit junction with a way in of 2+ lanes and 150 m straight")
	quit(1)
