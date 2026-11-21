extends SceneTree
## Traffic past a car parked by hand (details.gd, from a film) that stands wholly in the road,
## as filmed -- on Ha-Meri in Givatayim, noted as 1 m into the lane with traffic driving
## through it (the game parks its own a third in the road, where the lanes miss them).
## 21 Nov 2026: least gap 1.03-1.11 m in 4 passes, the lane clear of it (not reproduced). Puts the player 60 m
## off, then PASSES cars one at a time on the road beside the parked car, 30 m before it, in
## the direction that has it on their kerb side, and runs each until 15 m past it. Prints the
## least gap between the moving car's side and the parked car's (both as boxes, 0.1 m steps)
## and how far out it rode; PASS when no gap is under 0.
##   PARKED=605.86,-577.34 LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/hand_parked.gd
var g: Node
func _initialize() -> void:
	_run()

## the least distance between two boxes (centre, unit along, half length, half width)
func _box_gap(c1: Vector2, u1: Vector2, h1: Vector2, c2: Vector2, u2: Vector2, h2: Vector2) -> float:
	var best := INF
	for pair in [[c1, u1, h1, c2, u2, h2], [c2, u2, h2, c1, u1, h1]]:
		var ca: Vector2 = pair[0]
		var ua: Vector2 = pair[1]
		var ha: Vector2 = pair[2]
		var cb: Vector2 = pair[3]
		var ub: Vector2 = pair[4]
		var hb: Vector2 = pair[5]
		var va := Vector2(-ua.y, ua.x)
		# corners of a, in b's frame
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var p: Vector2 = ca + ua * ha.x * sx + va * ha.y * sy - cb
				var lx := absf(p.dot(ub)) - hb.x
				var ly := absf(p.dot(Vector2(-ub.y, ub.x))) - hb.y
				var d := Vector2(maxf(lx, 0.0), maxf(ly, 0.0)).length() if (lx > 0.0 or ly > 0.0) else maxf(lx, ly)
				best = minf(best, d)
	return best

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	var want := Vector2(605.86, -577.34)
	if OS.get_environment("PARKED") != "":
		var xz := OS.get_environment("PARKED").split(",")
		want = Vector2(float(xz[0]), float(xz[1]))
	var bi := -1
	for i in range(g._car_box_c.size()):
		if (g._car_box_c[i] as Vector2).distance_to(want) < 1.0:
			bi = i
	if bi < 0:
		print("no parked car at %s" % want)
		quit(1)
		return
	var pc: Vector2 = g._car_box_c[bi]
	var pu: Vector2 = g._car_box_u[bi]
	var hit: Dictionary = g._nearest_seg(pc, 8.0, true, true)
	var ri: int = hit["road"]
	var r: Dictionary = g._roads[ri]
	print("parked car at %s on '%s' (%s, %.1f m wide), %.2f m from its middle" % [pc.round(), r["name"], r["k"], float(r["w"]),
		(hit["q"] as Vector2).distance_to(pc)])
	var tr = g._traffic
	var passes := int(OS.get_environment("PASSES")) if OS.get_environment("PASSES") != "" else 4
	var worst := INF
	var driven := 0
	for pass_i in range(passes):
		# the player 60 m off, standing, so the traffic is kept near
		g._pos = pc + Vector2(60.0, 0.0)
		g._v = 0.0
		for c in tr.cars:
			c.alive = false
		var c = tr.cars[0]
		var pts: PackedVector2Array = r["pts"]
		var sj: int = hit["seg"]
		var d := (pts[sj + 1] - pts[sj]).normalized()
		# the way that has the parked car on its right (the kerb side)
		var side := (pc - (hit["q"] as Vector2)).dot(Vector2(-d.y, d.x))
		var dir := 1 if side < 0.0 else -1
		if int(r["o"]) != 0 and dir != int(r["o"]):
			print("one-way the other way: nothing to drive")
			break
		var start: Vector2 = (hit["q"] as Vector2) - d * dir * 30.0
		var sh: Dictionary = g._nearest_seg(start, 6.0, true, true)
		c.alive = tr._start_on(c, int(sh["road"]), int(sh["seg"]), sh["q"], dir)
		if not c.alive:
			print("could not start a car there")
			continue
		driven += 1
		var least := INF
		var out := 0.0
		var t := 0.0
		while t < 20.0:
			await physics_frame
			t += 1.0 / 60.0
			g._pos = pc + Vector2(60.0, 0.0)
			for o in tr.cars:   # (the rest kept off: one car past it at a time)
				if o != c:
					o.alive = false
			if not c.alive:
				break
			var cu := Vector2(sin(c.yaw), cos(c.yaw))
			var hw: Vector2 = tr.CORNERS.get(c.kind, Vector2(0.9, 2.3))
			least = minf(least, _box_gap(c.pos, cu, Vector2(hw.y, hw.x), pc, pu, Vector2(g.CAR_BOX.x, g.CAR_BOX.y)))
			out = maxf(out, c.shift)
			if (c.pos - pc).dot(d * dir) > 15.0:
				break
		worst = minf(worst, least)
		print("pass %d (%s): least gap %.2f m, rode out %.2f m" % [pass_i, c.kind, least, out])
	print("HAND_PARKED: %s (least gap %.2f m over %d passes)" % ["PASS" if driven > 0 and worst >= 0.0 else "FAIL", worst, driven])
	quit(0)
