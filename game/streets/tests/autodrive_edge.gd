extends SceneTree
## Autodrive near the map's edge: put on streets that run off the map, ~120 m short of the
## barrier and heading for it, then left to drive (SECS each, default 30). Counted: how often
## it touched the barrier ("the edge of the map"), how often it turned round on the spot after
## the first seconds, the time it spent within 25 m of the barrier, and the nearest it came.
## Also (22 Nov, a user: "it has trouble getting back ... it just turns back into nowhere. the
## whole behaviour around the edges is meh"): seconds off any road (the car's middle more than
## 1 m past every road's asphalt), seconds stood still (under 0.5 m/s, after the first 3 s),
## and, for a run that came within 40 m of the barrier, whether it got back: 100 m or more
## off it at the end. ONLY=n runs only the n-th start (from 0), TRACE=1 prints each second
## of a run (where, how far off the barrier, speed, what autodrive is doing).
## Good: it never reaches the barrier -- it takes a way back into town at the junctions, or,
## on a street with none, turns round at the start rather than at the barrier -- never leaves
## the road, hardly stands, and gets back every time.
var g: Node
func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var rim: Rect2 = g._bounds.grow(-g.EDGE)
	var inner: Rect2 = rim.grow(-2.0)
	# the starts: where a public street crosses the barrier, 120 m back along it, facing out
	var starts: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"] or r["k"] == "service":
			continue
		var pts: PackedVector2Array = r["pts"]
		for k in range(1, pts.size()):
			var a_in: bool = inner.has_point(pts[k - 1])
			var b_in: bool = inner.has_point(pts[k])
			if a_in == b_in:
				continue
			var step := 1 if b_in else -1   # back along the road, inside (away from the outside point)
			var dir_out := 1 if not b_in else -1
			if r["o"] != 0 and r["o"] != dir_out:
				continue   # one-way into town: nobody drives out on it
			var j := k if b_in else k - 1
			var d := 0.0
			while j + step >= 0 and j + step < pts.size() and d < 120.0:
				d += pts[j].distance_to(pts[j + step])
				j += step
			if d < 60.0:
				continue
			var at := pts[j]
			var far := true
			for s: Array in starts:
				if (s[0] as Vector2).distance_to(at) < 300.0:
					far = false
			if far:
				starts.append([at, (pts[k] - pts[k - 1]).normalized() * float(-step), r["name"]])
	var want := int(OS.get_environment("STARTS")) if OS.get_environment("STARTS") != "" else 6
	var pick: Array = []
	for i in range(mini(want, starts.size())):
		pick.append(starts[i * starts.size() / mini(want, starts.size())])
	print("streets that run off the map: %d starts found, trying %d" % [starts.size(), pick.size()])
	var secs := int(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 30
	var touched := 0
	var turned := 0
	var near_s := 0.0
	var nearest := INF
	var off_all := 0.0
	var still_all := 0.0
	var back_n := 0
	var came_n := 0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var only := int(OS.get_environment("ONLY")) if OS.get_environment("ONLY") != "" else -1
	var trace := OS.get_environment("TRACE") != ""
	for si in range(pick.size()):
		var s: Array = pick[si]
		if only >= 0 and si != only:
			continue
		g._set_auto(false)
		g._land_on_road(s[0], 15.0, s[1])
		g._ap_pts = PackedVector2Array()
		g._light_odo = -1000.0
		await create_timer(0.5).timeout
		g._set_auto(true)
		var warned: float = g._edge_warned
		var was_turning := false
		var my_near := INF
		var my_touch := 0
		var my_turn := 0
		var my_off := 0.0
		var my_still := 0.0
		var gap_end := 0.0
		for f in range(60 * secs):
			await physics_frame
			var p: Vector2 = g._pos
			var gap := minf(minf(p.x - rim.position.x, rim.end.x - p.x), minf(p.y - rim.position.y, rim.end.y - p.y))
			my_near = minf(my_near, gap)
			if gap < 25.0:
				near_s += Engine.time_scale / Engine.physics_ticks_per_second
			if g._edge_warned != warned:
				warned = g._edge_warned
				my_touch += 1
			var on_road: Dictionary = g._nearest_seg(p, 20.0, true)
			if (on_road.is_empty() or float(on_road["edge"]) > 1.0) and not g._in_junction(p, 1.0):
				my_off += dt
			if f > 60 * 3 and absf(g._v) < 0.5:
				my_still += dt
			gap_end = gap
			if trace and f % 60 == 0:
				print("    t %2d s  %s  off the barrier %.0f m  %.1f m/s  turn %.1f back %.1f  plan to %s  %s" % [f / 60, p.round(), gap, g._v, g._ap_turn, g._ap_back,
					(g._ap_pts[g._ap_pts.size() - 1] as Vector2).round() if g._ap_pts.size() > 0 else "-", String(g.get("_ap_why")) if "_ap_why" in g else ""])
			var turning: bool = g._ap_turn > 0.0 or g._ap_back > 0.0
			if turning and not was_turning and f > 60 * 4:
				my_turn += 1
			was_turning = turning
		var came := my_near < 40.0
		var back := came and gap_end >= 100.0
		print("  from '%s' %s facing %s: nearest the barrier %.0f m, touched it %d, turned round %d, off the road %.1f s, stood %.1f s, %s (%.0f m off it at the end), %.0f m driven" % [s[2], (s[0] as Vector2).round(), (s[1] as Vector2).snapped(Vector2(0.01, 0.01)), my_near, my_touch, my_turn, my_off, my_still, "got back" if back else ("NOT BACK" if came else "never near"), gap_end, g._odo])
		touched += my_touch
		turned += my_turn
		off_all += my_off
		still_all += my_still
		back_n += 1 if back else 0
		came_n += 1 if came else 0
		nearest = minf(nearest, my_near)
	print("%d starts x %d s: touched the barrier %d, turned round on the spot %d, %.0f s within 25 m of it, nearest %.0f m; off the road %.1f s, stood %.0f s, got back %d of the %d that came within 40 m" % [pick.size(), secs, touched, turned, near_s, nearest, off_all, still_all, back_n, came_n])
	quit(0)
