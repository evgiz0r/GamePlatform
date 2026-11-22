extends SceneTree
## What gives under the car at speed (streets.gd _smash, 22 Nov 2026 -- the user: "things bit
## more breakable that dont completely stop us"): a kerb railing, a garden wall under knee
## height, a hedge go through; a tall fence (and so a building wall) does not. For each kind,
## up to N (3) of them in the town with a clear 10 m run-up square to them: the car put 8 m
## off, driven at it at KMH (30) for 2.5 s, and whether it came out the other side, and its
## speed after. PASS: every railing, low wall and hedge gone through, no tall fence.
## (at the default quality: kerb railings are put up only from medium up -- furniture `med`)
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/smash.gd
var g: Node

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

## nothing that does not give stands on the same line (a garden wall is laid by each plot that
## has it: a low one and its taller neighbour can share a line, and the tall one stops the car)
func _alone(i: int, m: Vector2) -> bool:
	for j: int in g._near(g._wall_hash, m, 1.5, g.BLD_CELL):
		if j != i and g._wall_give[j] == 0:
			var cp := Geometry2D.get_closest_point_to_segment(m, g._walls[j * 2], g._walls[j * 2 + 1])
			if cp.distance_to(m) < 1.5:
				return false
	return true

func _what(hit: String, m: Vector2, nn: Vector2) -> String:
	if not hit.begins_with("wall "):
		return ""
	var j := int(hit.substr(5))
	var a: Vector2 = g._walls[j * 2]
	var b: Vector2 = g._walls[j * 2 + 1]
	return " (r %.2f give %d soft %d, %.1f m long, at an angle of %.0f deg to this one, its middle %.1f m off)" % [g._wall_r[j], g._wall_give[j], g._wall_soft[j], a.distance_to(b),
		rad_to_deg(absf((b - a).normalized().dot(nn))) , ((a + b) * 0.5).distance_to(m)]

## the run-up from p back along -n is clear of everything solid but this wall
func _clear_run(p: Vector2, n: Vector2) -> bool:
	for k in range(2, 11):
		if g._push_out(p - n * float(k), 1.2, true, true) != Vector2.ZERO:
			return false
	for k in [2]:   # (and the other side, 2 m in: what stands behind a garden wall stops the car, not the wall)
		if g._push_out(p + n * float(k), 1.2, true, true) != Vector2.ZERO:
			return false
	return true

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(_env("LEVEL", "1"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	for c in g._traffic.cars:
		c.alive = false
		c.retry = 1000.0
	var per := int(_env("N", "3"))
	var census := {}
	for i in range(g._wall_r.size()):
		var key := "r %.2f give %d soft %d" % [g._wall_r[i], g._wall_give[i], g._wall_soft[i]]
		census[key] = int(census.get(key, 0)) + 1
	print("WALLS %s" % str(census))
	var v := float(_env("KMH", "30")) / 3.6
	# kinds: [name, test(i) -> bool, should go through]
	var kinds := [
		["kerb railing", func(i: int) -> bool: return g._wall_give[i] == 1 and g._wall_soft[i] == 0 and absf(g._wall_r[i] - 0.06) < 0.001, true],
		["low garden wall", func(i: int) -> bool: return g._wall_give[i] == 1 and g._wall_soft[i] == 0 and absf(g._wall_r[i] - 0.13) < 0.001, true],
		["hedge", func(i: int) -> bool: return g._wall_soft[i] == 1, true],
		["tall fence", func(i: int) -> bool: return g._wall_give[i] == 0 and absf(g._wall_r[i] - 0.06) < 0.001, false],
	]
	var bad := 0
	for kd: Array in kinds:
		var found := 0
		var through := 0
		var nwalls: int = g._wall_r.size()
		var step := maxi(1, nwalls / 4000)
		var i := 0
		while i < nwalls and found < per:
			var ok: bool = (kd[1] as Callable).call(i)
			if ok:
				var a: Vector2 = g._walls[i * 2]
				var b: Vector2 = g._walls[i * 2 + 1]
				if a.distance_to(b) > 1.0 and (not bool(kd[2]) or _alone(i, (a + b) * 0.5)):
					var m := (a + b) * 0.5
					var n := Vector2(-(b - a).y, (b - a).x).normalized()
					var sides := [n, -n]
					for nn: Vector2 in sides:
						if found >= per or not _clear_run(m, nn):
							continue
						found += 1
						# the car 8 m off, square to it, at speed
						g._auto = false
						g._pos = m - nn * 8.0
						g._yaw = atan2(nn.y, nn.x)
						g._y = float(g._h(g._pos))
						g._v = v
						g._v_lat = 0.0
						var t := 0.0
						var crossed := false
						while t < 2.5:
							# (held at speed, as a foot on the gas: what is solid still pushes it back, and
							# it stands there; let go after the run-up, it coasted to a stop at the line)
							if absf(float(g._v)) < v * 0.6 or t < 1.2:
								g._v = minf(v, float(g._v) + 0.4) if t > 1.2 else v
							await physics_frame
							t += 1.0 / 60.0
							if ((g._pos as Vector2) - m).dot(nn) > 2.5:
								crossed = true
								break
						print("  %s %d at (%.0f, %.0f): %s, %.0f km/h after%s" % [kd[0], i, m.x, m.y, "through" if crossed else "stopped", float(g._v) * 3.6,
							"" if crossed else " -- last touched %s, %.1f m short of it%s" % [g._last_hit, -((g._pos as Vector2) - m).dot(nn), _what(String(g._last_hit), m, nn)]])
						if crossed:
							through += 1
						break
			i += 1
		var want: bool = kd[2]
		print("SMASH %s: %d of %d through (want %s)" % [kd[0], through, found, "all" if want else "none"])
		if found == 0 or (want and through < found) or (not want and through > 0):
			bad += 1
	print("SMASH RESULT: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0)
