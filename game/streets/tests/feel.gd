extends SceneTree
## How things feel: a crash into a building at 54 km/h (does the car bounce back, hop, spin?),
## jumping out at 50 km/h (how far you tumble, how far the empty car rolls on), driving into
## a fence (does it stop the car?). Good: rebound under 2 m/s, no hop, the car stops at the
## fence, the tumble a few metres and the car rolling on 30-70 m.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
func _place(p: Vector2, yaw: float, v: float) -> void:
	g._set_auto(false)
	g._pos = p
	g._yaw = yaw
	g._snap_pose()
	g._v = v
	g._v_lat = 0.0
	g._spin = 0.0
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
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	var start: Vector2 = g._pos
	print("walls registered: %d (fences, hedges, garden walls, shelters)" % g._wall_r.size())
	# 1. a crash: a building wall 14 m ahead with a clear run to it
	var hit_at := Vector2.INF
	var hit_dir := Vector2.ZERO
	for bi in range(g._blds.size()):
		if g._bld_solid[bi] == 0:
			continue
		var c: Vector2 = (g._bld_box[bi] as Rect2).get_center()
		if c.distance_to(start) > 400.0:
			continue
		for ang in range(0, 360, 30):
			var d := Vector2.from_angle(deg_to_rad(ang))
			var p := c + d * 30.0
			var free := true
			var k := 0.0
			var wall_k := -1.0
			while k < 30.0:
				var q := p - d * k
				if g._push_out(q, 1.2, true, false) != Vector2.ZERO:
					wall_k = k
					break
				k += 1.0
			if wall_k > 16.0 and wall_k < 26.0:
				hit_at = p
				hit_dir = -d
				break
		if hit_at != Vector2.INF:
			break
	if hit_at != Vector2.INF:
		_place(hit_at, hit_dir.angle(), 15.0)
		var min_v := 0.0
		var hopped := false
		var spin := 0.0
		for f in range(60 * 3):
			await physics_frame
			min_v = minf(min_v, g._v)
			hopped = hopped or g._air
			spin = maxf(spin, absf(g._spin))
		print("crash at 54 km/h: bounced back at %.1f m/s, hopped %s, spin %.2f rad/s, last hit %s" % [-min_v, hopped, spin, g._last_hit])
	# 2. out of a moving car
	var road: Dictionary = g._nearest_seg(start, 40.0, true, true)
	var pts: PackedVector2Array = g._roads[road["road"]]["pts"]
	var d := (pts[int(road["seg"]) + 1] - pts[road["seg"]]).normalized()
	_place(road["q"], d.angle(), 14.0)
	await physics_frame
	var car0: Vector2 = g._pos
	g._get_out()
	var me0: Vector2 = g._pos
	var shot := false
	for f in range(60 * 8):
		await physics_frame
		if not shot and f == 20 and OS.get_environment("OUT") != "":
			shot = true
			await _snap("jump_out")
	print("out at 50 km/h: tumbled %.1f m; the empty car rolled %.1f m and stands at %.1f m/s" % [g._pos.distance_to(me0), g._car_at.distance_to(car0), g._car_v])
	g._get_in()
	# 3. into a fence: one with a clear 12 m run-up square to it
	var wi := -1
	var nrm := Vector2.ZERO
	for i in range(g._wall_r.size()):
		var a0: Vector2 = g._walls[i * 2]
		var b0: Vector2 = g._walls[i * 2 + 1]
		var m0 := (a0 + b0) * 0.5
		if m0.distance_to(start) > 700.0 or g._wall_r[i] > 0.1 or a0.distance_to(b0) < 2.0:
			continue
		for sgn: float in [1.0, -1.0]:
			var n0 := (b0 - a0).orthogonal().normalized() * sgn
			var clear := true
			var k := 2.0
			while k <= 13.0:
				if g._push_out(m0 + n0 * k, 1.3, true, false) != Vector2.ZERO:
					clear = false
					break
				k += 1.0
			if clear:
				wi = i
				nrm = n0
				break
		if wi >= 0:
			break
	if wi >= 0:
		var a: Vector2 = g._walls[wi * 2]
		var b: Vector2 = g._walls[wi * 2 + 1]
		var m := (a + b) * 0.5
		g._assist = false   # (the lane-keeping assist steered it off the run-up, into a post)
		_place(m + nrm * 12.0, (-nrm).angle(), 10.0)
		var closest := INF
		for f in range(60 * 3):
			await physics_frame
			closest = minf(closest, Geometry2D.get_closest_point_to_segment(g._pos, a, b).distance_to(g._pos))
		print("into a fence at 36 km/h: the car's middle came within %.2f m of it (through it: under 0.1), last hit %s" % [closest, g._last_hit])
	else:
		print("no fence with a clear run-up found near the start")
	quit(0)
