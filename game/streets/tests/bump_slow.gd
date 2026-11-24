extends SceneTree
## Speed bumps slow the cars (g.bump_v; OSM's bumps, tables and cushions, built by
## furniture.gd into g.bumps, 24 Nov 2026 -- drawn, and every car drove over them at the
## limit). Picks up to N (4) bumps across a street of two ways or a one-way's own way, each
## with 70 m of the same road before it; for each, autodrive is sent along the road over it
## from 60 m back, then a traffic car is; prints each one's speed as its middle crosses the
## bump (good: at most the kind's BUMP_KMH + 4) and its top speed in the 50 m before.
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/bump_slow.gd
var g: Node
var T

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	T = g._traffic
	var want := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 4
	print("bumps built: %d" % g.bumps.size())
	# bumps with a straight run of road before them (the start 60 m back on the same road)
	var picks: Array = []
	for b: Array in g.bumps:
		if picks.size() >= want:
			break
		var at: Vector2 = b[0]
		var d: Vector2 = b[1]
		var hit: Dictionary = g._nearest_seg(at, 3.0, true, true)
		if hit.is_empty():
			continue
		var r: Dictionary = g._roads[hit["road"]]
		if int(r["o"]) != 0:
			var pts: PackedVector2Array = r["pts"]
			var sj: int = hit["seg"]
			var way: Vector2 = (pts[sj + 1] - pts[sj]).normalized() * float(r["o"])
			d = way
		var from: Vector2 = at - d * 60.0
		var h2: Dictionary = g._nearest_seg(from, 4.0, true, true)
		if h2.is_empty() or int(h2["road"]) != int(hit["road"]):
			continue
		var far: bool = false
		for p2: Array in picks:
			if (p2[0] as Vector2).distance_to(at) < 150.0:
				far = true
		if far:
			continue
		picks.append([at, d, String(b[3]), from])
	var bad := 0
	var runs := 0
	for p: Array in picks:
		var at: Vector2 = p[0]
		var d: Vector2 = p[1]
		var cap: float = float(g.BUMP_KMH.get(p[2], 15.0))
		for who: String in ["autodrive", "traffic"]:
			for c in T.cars:
				c.alive = false
			var top := 0.0
			var over := -1.0
			var t := 0.0
			var car = null
			if who == "autodrive":
				g._set_auto(false)
				if not g._land_on_road(p[3], 6.0, d):
					continue
				await physics_frame
				g._set_dest(at + d * 60.0, "bump test")
				g._set_auto(true)
			else:
				g._set_auto(false)
				g._land_on_road(at + Vector2(-d.y, d.x) * 40.0 + d * 120.0, 60.0, Vector2.ZERO)   # (out of its way)
				await physics_frame
				T.send(p[3], d)
				for c in T.cars:
					if c.alive and (c.pos as Vector2).distance_to(p[3]) < 10.0:
						car = c
				if car == null:
					continue
			var last_along := -INF
			while t < 25.0:
				await physics_frame
				t += 1.0 / Engine.physics_ticks_per_second
				var pos: Vector2 = g._pos if who == "autodrive" else car.pos
				var v: float = absf(g._v) if who == "autodrive" else car.v
				var along: float = (pos - at).dot(d)
				if along > -50.0 and along < -6.0:
					top = maxf(top, v)
				if last_along < 0.0 and along >= 0.0 and absf((pos - at).dot(Vector2(-d.y, d.x))) < 6.0:
					over = v
					break
				last_along = along
				if who == "traffic" and not car.alive:
					break
			runs += 1
			var ok: bool = over >= 0.0 and over * 3.6 <= cap + 4.0
			if not ok:
				bad += 1
			print("BUMP %s (%.0f, %.0f), a %s (%.0f km/h): %s over it at %s, %.0f km/h top in the 50 m before" % [
				"ok" if ok else "FAST", at.x, at.y, p[2], cap, who, "%.0f km/h" % (over * 3.6) if over >= 0.0 else "never", top * 3.6])
	print("REGRESS bump_slow: %s -- autodrive and traffic over %d speed bumps: %d too fast or not over (good 0; before: every car at the limit)" % [
		"PASS" if bad == 0 and runs > 0 else "FAIL", picks.size(), bad])
	quit(0)
