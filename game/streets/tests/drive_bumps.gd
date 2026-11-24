extends SceneTree
## What makes a drive bumpy: autodrive from STARTS places (default 6, spread over the town's
## streets), SECS each (default 40), counting every
##   jolt   -- what pitches, rolls and shakes the car: a wheel going onto a manhole cover or
##             drain grate (_cover_tick: a knock and a shake each), an axle onto or off a
##             median or island's kerb, a landing after a hop
##   knock  -- something knocked over or bent (a sign, a bollard, a bin: _knocked_n)
##   hit    -- the car stopped by a building, wall or post (_last_hit)
## each with the place, worst places first. A user (22 Nov, Tel Aviv): "the drive is pretty
## bumpy with many objects on the road, with the autodrive just driving straight".
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/drive_bumps.gd
## Good: no knocks or hits; jolts only from kerbs the car really drives over.
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
	while g._bg_build:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var want := int(OS.get_environment("STARTS")) if OS.get_environment("STARTS") != "" else 6
	var secs := int(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 40
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	# starts: points along kerbed public streets inside the town, spread by a coarse grid
	var cells := {}
	for r: Dictionary in g._roads:
		if not g._kerbed(r) or r.has("ys") or float(r["w"]) < 6.0:
			continue
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 2:
			continue
		# halfway along it by length, 15 m or more from either end (pts[size / 2] of a two-point
		# road is its end: a junction's middle, where any turn starts inside the corner)
		var total := 0.0
		for j in range(pts.size() - 1):
			total += pts[j].distance_to(pts[j + 1])
		if total < 30.0:
			continue
		var mid := Vector2.INF
		var md := Vector2.ZERO
		var run := 0.0
		for j in range(pts.size() - 1):
			var l := pts[j].distance_to(pts[j + 1])
			if run + l >= total * 0.5:
				mid = pts[j].lerp(pts[j + 1], (total * 0.5 - run) / maxf(l, 0.01))
				md = (pts[j + 1] - pts[j]).normalized()
				break
			run += l
		var rim: Rect2 = (g._bounds as Rect2).grow(-float(g.EDGE) - 40.0)
		if mid == Vector2.INF or not g._in_city(mid) or priv.near(avoid, mid) or not rim.has_point(mid):
			continue
		var k := Vector2i(floori(mid.x / 400.0), floori(mid.y / 400.0))
		if not cells.has(k):
			cells[k] = [mid, md]
	var starts: Array = cells.values()
	starts.sort_custom(func(a, b): return (a[0] as Vector2).x + (a[0] as Vector2).y * 0.37 < (b[0] as Vector2).x + (b[0] as Vector2).y * 0.37)
	var pick: Array = []
	for i in range(mini(want, starts.size())):
		pick.append(starts[i * starts.size() / mini(want, starts.size())])
	var by := {}      # cause -> count
	var places := {}  # "cause @ 20 m square" -> [count, point]
	var knocks := 0
	var hits := 0
	# over the kerb: the car's middle within 0.3 m of the asphalt's edge (its wheels over it,
	# half the car ~0.9 m) -- off: the middle 0.8 m past it. Seconds, and where (20 m squares)
	var kerb_s := 0.0
	var off_s := 0.0
	var kerb_at := {}
	var driven := 0.0
	var add := func(cause: String, p: Vector2) -> void:
		by[cause] = int(by.get(cause, 0)) + 1
		if priv.near(avoid, p):
			return
		var key := "%s @ %s" % [cause, Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))]
		if not places.has(key):
			places[key] = [0, p.round(), cause]
		places[key][0] += 1
	# each knock or hit with what led to it: the car's last 3 s, twice a second -- where, how
	# fast, why the plan went that speed, the road under it and how far past its edge
	var hist: Array = []
	var tell := func(si: int, what: String) -> void:
		print("  -- start %d, %s, at %s, %.1f m/s, heading %s:" % [si, what, str(g._pos.round()), g._v, str(g._fwd().snapped(Vector2(0.01, 0.01)))])
		for h: String in hist:
			print("       " + h)
	for si in range(pick.size()):
		var s: Array = pick[si]
		if OS.get_environment("ONLY") != "" and not Array(OS.get_environment("ONLY").split(",")).has(str(si)):
			continue
		hist.clear()
		g._set_auto(false)
		g._land_on_road(s[0], 15.0, s[1])
		g._ap_pts = PackedVector2Array()
		await create_timer(0.5).timeout
		g._set_auto(true)
		var odo0: float = g._odo
		var cov0: Array = (g._cover_on as Array).duplicate()
		var med0: Array = (g._median_on as Array).duplicate()
		var air0: bool = g._air
		var kn0: int = g._knocked_n
		var hit0: String = g._last_hit
		var cool0: float = g._crash_cool
		for f in range(60 * secs):
			await physics_frame
			var p: Vector2 = g._pos
			if f % 6 == 0 and absf(g._v) > 1.0:
				var kb: Dictionary = g._nearest_seg(p, 30.0, true, true, g._y)
				var e := 99.0 if kb.is_empty() else float(kb["edge"])
				if e > -0.3:
					kerb_s += 0.1
					if e > 0.8:
						off_s += 0.1
					if not priv.near(avoid, p):
						var kk := Vector2i(floori(p.x / 20.0), floori(p.y / 20.0))
						if not kerb_at.has(kk):
							kerb_at[kk] = [0.0, p.round(), "" if kb.is_empty() else String(g._roads[kb["road"]]["en"]), 0.0, si]
						kerb_at[kk][0] += 0.1
						kerb_at[kk][3] = maxf(kerb_at[kk][3], e)
			if f % 30 == 0:
				var on: Dictionary = g._nearest_seg(p, 30.0, true, true, g._y)
				var rd := "off any road" if on.is_empty() else "%s '%s' edge %.1f" % [g._roads[on["road"]]["k"], g._roads[on["road"]]["en"], float(on["edge"])]
				var ahead: Array = []
				for q in Array(g._ap_pts).slice(0, 4):
					ahead.append(Vector2i((q as Vector2).round()))
				hist.append("t %.1f  %s  %.1f m/s  steer %.2f  why %s  [%s]  plan %s" % [f / 60.0, str(p.round()), g._v, g._steer, g._ap_why, rd, str(ahead)])
				if hist.size() > 6:
					hist.pop_front()
			if int(g._knocked_n) > kn0:
				tell.call(si, "knocked " + String(g._last_hit))
				knocks += int(g._knocked_n) - kn0
				add.call("knocked " + String(g._last_hit), p)
				kn0 = g._knocked_n
			if float(g._crash_cool) > 0.0 and cool0 <= 0.0:
				tell.call(si, "hit " + String(g._last_hit))
				hits += 1
				add.call("hit " + String(g._last_hit).split(" ")[0], p)
			cool0 = g._crash_cool
			var cov: Array = g._cover_on
			for k in range(cov.size()):
				if cov[k] and not cov0[k] and absf(g._v) >= 1.0:
					add.call("jolt: a wheel onto a cover or grate", p)
			cov0 = (cov as Array).duplicate()
			var med: Array = g._median_on
			for k in range(med.size()):
				if med[k] != med0[k]:
					add.call("jolt: an axle onto or off a median or island", p)
			med0 = (med as Array).duplicate()
			if air0 and not g._air:
				add.call("jolt: landed after a hop", p)
			air0 = g._air
		driven += float(g._odo) - odo0
	print("DRIVE BUMPS: %d starts x %d s, %.1f km: %s; knocked over %d; hits %d" % [pick.size(), secs, driven / 1000.0, by, knocks, hits])
	print("OVER THE KERB: %.1f s (%.1f s a km), off the asphalt %.1f s" % [kerb_s, kerb_s / maxf(driven / 1000.0, 0.01), off_s])
	var kks := kerb_at.keys()
	kks.sort_custom(func(x, y): return kerb_at[x][0] > kerb_at[y][0])
	for kk in kks.slice(0, 8):
		print("  %4.1f s over the kerb at %s, %s, up to %.1f m past the edge (start %d)" % [kerb_at[kk][0], kerb_at[kk][1], kerb_at[kk][2], kerb_at[kk][3], kerb_at[kk][4]])
	for cause: String in by:
		print("  per km: %s %.1f" % [cause, float(by[cause]) / maxf(driven / 1000.0, 0.01)])
	var keys := places.keys()
	keys.sort_custom(func(a, b): return places[a][0] > places[b][0])
	for k in keys.slice(0, int(OS.get_environment("N")) if OS.get_environment("N") != "" else 20):
		print("  %3d  %s at %s" % [places[k][0], places[k][2], places[k][1]])
	quit(0)
