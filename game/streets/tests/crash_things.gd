extends SceneTree
## What breaks: the car driven at 30 km/h into the nearest bin and the nearest bollard
## (are they knocked over / bent, is the car let through?), then at 50 km/h into a building
## (sparks, glass on the road, a dent in the car), and after 35 s away from them, are they
## back? Prints what happened; shots crash_<what>.png in $OUT (a chase view at the moment).
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
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

## drive straight at the thing at `at` from 9 m back along `d`, at v m/s, for `secs`
func _run_at(name: String, at: Vector2, d: Vector2, v: float, secs: float) -> Dictionary:
	_place(at - d * 9.0, d.angle(), v)
	var before: int = g._knocked.size()
	var min_v := v
	for f in range(int(secs * 60.0)):
		g._v = maxf(g._v, 0.0)
		if f < 30:
			g._v = v   # (held at speed until it gets there)
		await physics_frame
		min_v = minf(min_v, g._v)
		if f == int(0.9 * v / 9.0 * 60.0):
			await _snap("crash_" + name)
	return {"knocked": g._knocked.size() - before, "min_v": min_v, "end_v": g._v}

func _nearest(kind: String, from: Vector2) -> Transform3D:
	var best := Transform3D()
	var bd := INF
	for t: Transform3D in g._furn.where.get(kind, []):
		var d := Vector2(t.origin.x, t.origin.z).distance_to(from)
		if d < bd:
			bd = d
			best = t
	return best

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var start: Vector2 = g._pos
	g._assist = false   # (it brakes for what is ahead: here the point is to hit it)
	print("knockable things: %d" % g._knockable.size())
	for kind: String in ["tumble", "bend"]:
		# the nearest of its kind with a clear run of 8 m at it (nothing else solid on the way)
		var pick := -1
		var pd := Vector2.ZERO
		var best := INF
		for pid: int in g._knockable:
			var k: Array = g._knockable[pid]
			if k[4] != kind:
				continue
			var p: Vector2 = g._posts[pid]
			if p.distance_to(start) >= best:
				continue
			for ang in range(0, 360, 20):
				var d := Vector2.from_angle(deg_to_rad(ang))
				var clear := true
				var s := 8.0
				while s > 2.0:
					if g._push_out(p - d * s, 0.95, true, false) != Vector2.ZERO:
						clear = false
						break
					s -= 0.5
				if clear:
					pick = pid
					pd = d
					best = p.distance_to(start)
					break
		if pick < 0:
			print(kind, ": none with a clear run")
			continue
		var p: Vector2 = g._posts[pick]
		var r := await _run_at(kind, p, pd, 8.5, 1.6)
		print("%s at %s: knocked %d, slowest %.1f m/s, after %.1f m/s (8.5 in)" % [kind, p, r["knocked"], r["min_v"], r["end_v"]])
	# a building, from 14 m at 14 m/s (as feel.gd finds one)
	var found := false
	for bi in range(g._blds.size()):
		if found or g._bld_solid[bi] == 0:
			continue
		var c: Vector2 = (g._bld_box[bi] as Rect2).get_center()
		if c.distance_to(start) > 300.0:
			continue
		for ang in range(0, 360, 30):
			var d := Vector2.from_angle(deg_to_rad(ang))
			var p := c + d * 30.0
			var k := 0.0
			var wall_k := -1.0
			while k < 30.0:
				if g._push_out(p - d * k, 1.2, true, false) != Vector2.ZERO:
					wall_k = k
					break
				k += 1.0
			if wall_k > 12.0 and wall_k < 20.0:
				_place(p, (-d).angle(), 14.0)
				for f in range(60 * 2):
					await physics_frame
					if f == 50:
						await _snap("crash_wall")
				print("into a building at 50 km/h: dents %s, glass patches %d" % [str(g._dents), g._glass.size()])
				found = true
				break
	# a bollard bent as the car would (straight _knock, the car going along the kerb at 8 m/s)
	var bend_at := Vector3.ZERO
	for pid: int in g._knockable:
		if (g._knockable[pid] as Array)[4] == "bend" and (g._posts[pid] as Vector2).distance_to(start) < 400.0:
			var tt: Transform3D = (g._knockable[pid] as Array)[2]
			bend_at = tt.origin
			g._v = 8.0
			g._knock(pid)
			print("bent a bollard at %s" % (g._posts[pid] as Vector2))
			break
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	if bend_at != Vector3.ZERO:
		g.look_from(bend_at + Vector3(1.8, 1.4, 1.8), bend_at + Vector3(0, 0.4, 0))
		g._sky_follow()
		await create_timer(0.5).timeout
		await _snap("crash_bent")
	if not g._glass.is_empty():   # the glass from the driver's height
		var gp: Vector3 = (g._glass[0][0] as Node3D).get_aabb().get_center() if false else g._contact
		g.look_from(gp + Vector3(2.5, 1.6, 2.5), gp - Vector3(0, 0.4, 0))
		g._sky_follow()
		await create_timer(0.5).timeout
		await _snap("crash_glass")
	# the car's dent, from outside
	var cp: Vector3 = g._car.global_position
	var body: Node3D = g._sedan_node.get_child(0)
	var f3: Vector3 = body.global_transform.basis.z.normalized()   # (the dents' frame: z forward)
	var s3 := f3.cross(Vector3.UP).normalized()
	g.look_from(cp + f3 * 3.6 + s3 * 1.6 + Vector3(0, 1.5, 0), cp + f3 * 1.6 + Vector3(0, 0.5, 0))
	g._sky_follow()
	await create_timer(0.5).timeout
	await _snap("crash_dent")
	print("knocked down now: %d" % g._knocked.size())
	quit(0)
