extends SceneTree
## A head-on meeting in a narrow street: autodrive up David Kalai, a traffic car sent down it
## toward us. Does either get past within 30 s? (Also with the car stood in the middle.)
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
func _stage(ri: int, mid: bool) -> void:
	var T = g._traffic
	var r: Dictionary = g._roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var d := (pts[1] - pts[0]).normalized()
	g._set_auto(false)
	g._pos = pts[0] + d * 10.0 + Vector2(-d.y, d.x) * (0.0 if mid else float(g._lane_off(r)))
	g._yaw = d.angle()
	g._v = 0.0
	g._snap_pose()
	# every other car well away, one sent down at us
	for c in T.cars:
		if c.alive and c.pos.distance_to(g._pos) < 80.0:
			c.alive = false
			T._hide_or_show(T.cars.find(c))
	var c = T.cars[0]
	var at := pts[0] + d * 34.0
	var lane: float = T._lane(r)
	c.lane_i = 0
	c.shift = 0.0
	c.shift_to = 0.0
	c.split = false
	c.served = {}
	c.squeeze = 0.0
	c.wait = 0.0
	c.pts = PackedVector2Array([at + Vector2(d.y, -d.x) * lane])
	c.cum = PackedFloat32Array([0.0])
	c.node = PackedInt32Array([-1])
	c.rd = PackedInt32Array([ri])
	c.vmax = PackedFloat32Array([float(r["speed"]) * c.pace])
	c.k = 0
	c.s = 0.0
	c.last_light = -1000.0
	T._leg(c, ri, 0, -1)
	while c.cum[c.cum.size() - 1] < 140.0:
		if not T._next(c):
			break
	c.v = 6.0
	c.hit = 0.0
	c.ignore = 0.0
	c.alive = true
	T._place(c)
	c.prev_pos = c.pos
	c.prev_yaw = c.yaw
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 1})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var ri := -1
	for i in range(g._roads.size()):
		if String(g._roads[i]["en"]) == "David Kalai" and g._roads[i]["drive"]:
			ri = i
	var pts: PackedVector2Array = g._roads[ri]["pts"]
	print("David Kalai: %.0f m long, w %.1f" % [pts[0].distance_to(pts[pts.size() - 1]), float(g._roads[ri]["w"])])
	for mid: bool in [false, true]:
		await _stage(ri, mid)
		await physics_frame
		var T = g._traffic
		var c = T.cars[0]
		var start: Vector2 = g._pos
		g._set_auto(true)
		var t := 0.0
		var still := 0.0
		var longest := 0.0
		var closest := INF
		var squeezed := false
		var gone := false
		var shot := false
		while t < 30.0:
			await physics_frame
			t += 1.0 / 60.0
			if c.alive:
				closest = minf(closest, c.pos.distance_to(g._pos))
				if c.squeeze > 0.0:
					squeezed = true
			else:
				gone = true
			if absf(g._v) < 0.4:
				still += 1.0 / 60.0
				longest = maxf(longest, still)
			else:
				still = 0.0
			if not shot and t > 6.0 and OS.get_environment("OUT") != "":
				shot = true
				await _snap("standoff_%s" % ("mid" if mid else "lane"))
		print("%s: drove %.0f m in 30 s, longest standstill %.1f s, closest %.1f m, it edged past: %s, sent away: %s" % [
			"from the middle" if mid else "in its lane", g._pos.distance_to(start), longest, closest, squeezed, gone])
	quit(0)
