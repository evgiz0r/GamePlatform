extends SceneTree
## Traffic's corners over the kerb, and which corner: the exam's "traffic body off the
## asphalt" (a moving car's corner 0.35 m+ past every road's edge, out of junction discs, 3
## samples running) on traffic alone -- no autodrive, the player parked far off -- for SECS
## (240) of the town at SPEED (4) times, every vehicle kind, and for each time it fires: the
## kind, which corner (front or rear, the inside or the outside of the bend it is on), how far
## past, how sharp the bend (its radius from the lane 6 m either side), at a stop or not.
## The 22 Nov 2026 exams read 2-11 a town, nearly all buses on bends and at stops.
## AT="x,z;x,z" parks the player at each spot in turn for SECS (traffic lives around the
## player: with none, only round where the town starts). PASS: none.
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/bus_bends.gd
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
	var T = g._traffic
	Engine.time_scale = float(_env("SPEED", "4"))
	var secs := float(_env("SECS", "240"))
	# AT="x,z;x,z": the player parked at each in turn (traffic lives around the player), SECS each
	var spots: Array = []
	for sp in _env("AT", "").split(";", false):
		var xz := sp.split(",")
		spots.append(Vector2(float(xz[0]), float(xz[1])))
	var per := secs
	if not spots.is_empty():
		secs = per * spots.size()
	var t := 0.0
	var tick := 0
	var next_spot := 0
	var run := {}     # car -> samples running
	var fired := 0
	var by := {}      # "kind corner side" -> count
	while t < secs:
		if next_spot < spots.size() and t >= per * next_spot:
			g._land_on_road(spots[next_spot], 30.0, Vector2.RIGHT)
			print("  AT (%.0f, %.0f)" % [spots[next_spot].x, spots[next_spot].y])
			next_spot += 1
		await physics_frame
		t += Engine.time_scale / Engine.physics_ticks_per_second
		tick += 1
		if tick % 6 != 0:
			continue
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive or c.v < 2.0 or c.kerb or c.hold_t > 0.0 or c.rev_t > 0.0:
				run.erase(i)
				continue
			var box: Array = Bodies.car_box(c)
			var cs: PackedVector2Array = Bodies.corners(box)
			var worst := -INF
			var wk := -1
			for k in range(4):
				var on: Dictionary = g._nearest_seg(cs[k], 14.0, true, true, float(c.y))
				var e := INF if on.is_empty() else float(on["edge"])
				if e > 0.35 and not g._in_junction(cs[k], 0.2) and not g._in_corner_fill(cs[k], 0.2) and e > worst:
					worst = e
					wk = k
			if wk < 0:
				run.erase(i)
				continue
			run[i] = int(run.get(i, 0)) + 1
			if run[i] != 3:
				continue
			fired += 1
			# the bend: the lane 6 m back, here, 6 m on
			var a: Vector2 = T._at(c, c.s - 6.0)
			var m: Vector2 = T._at(c, c.s)
			var b: Vector2 = T._at(c, c.s + 6.0)
			var turn := (m - a).normalized().cross((b - m).normalized())
			var ang := absf(asin(clampf(turn, -1.0, 1.0)))
			var rad := 6.0 / maxf(ang, 0.001)
			# corners 0, 3 on the +side (s = (-f.y, f.x): +cross of the heading); a turn > 0
			# bends toward it
			var plus := wk == 0 or wk == 3
			var side := "straight" if ang < 0.02 else ("inside" if (turn > 0.0) == plus else "outside")
			var end := "front" if wk <= 1 else "rear"
			var key := "%s %s %s" % [c.kind, end, side]
			by[key] = int(by.get(key, 0)) + 1
			print("  OFF %s at (%.0f, %.0f): %s corner, the %s of the bend (radius %.0f m), %.2f m past the edge, %.0f km/h, %s, shift %.2f%s" % [
				c.kind, cs[wk].x, cs[wk].y, end, side, rad, worst, c.v * 3.6, c.why, c.shift, ", dwell" if c.dwell > 0.0 else ""])
	print("BUS BENDS: %d off the asphalt in %.0f s; %s" % [fired, secs, str(by)])
	print("BUS BENDS RESULT: %s" % ("PASS" if fired == 0 else "FAIL"))
	quit(0)
