extends SceneTree
## The map's edge: the car 40 m short of it facing it, then coasting into it.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)
func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var rim: Rect2 = g._bounds.grow(-g.EDGE)
	var start: Vector2 = g._pos
	# a road point 40-60 m short of the edge with a clear run out to it
	var best := INF
	var at := Vector2.ZERO
	var out := Vector2.ZERO
	for r: Dictionary in g._roads:
		if not r["drive"]:
			continue
		for p: Vector2 in r["pts"]:
			var sides := [[p.x - rim.position.x, Vector2(-1, 0)], [rim.end.x - p.x, Vector2(1, 0)],
				[p.y - rim.position.y, Vector2(0, -1)], [rim.end.y - p.y, Vector2(0, 1)]]
			sides.sort_custom(func(a, b): return a[0] < b[0])
			var d: float = sides[0][0]
			if d < 40.0 or d > 60.0 or p.distance_to(start) > best:
				continue
			var o: Vector2 = sides[0][1]
			var clear := true
			var k := 0.0
			while k < d - 3.0:
				if g._push_out(p + o * k, 1.6, true, false) != Vector2.ZERO:
					clear = false
					break
				k += 2.0
			if clear:
				best = p.distance_to(start)
				at = p
				out = o
	print("edge spot %.0f m from the start" % best)
	g._pos = at
	g._yaw = out.angle()
	g._v = 0.0
	g._snap_pose()
	await create_timer(2.5).timeout
	await _snap("edge_%d_near" % lvl)
	g._v = 14.0
	var t := 0.0
	var minv := 99.0
	while t < 4.0:
		await physics_frame
		t += 1.0 / 60.0
	var d_rim := minf(minf(g._pos.x - rim.position.x, rim.end.x - g._pos.x), minf(g._pos.y - rim.position.y, rim.end.y - g._pos.y))
	print("after coasting into it: centre %.1f m from the barrier, v %.1f, last hit %s" % [d_rim, g._v, g._last_hit])
	await _snap("edge_%d_hit" % lvl)
	g._set_night(true)
	await create_timer(1.0).timeout
	await _snap("edge_%d_night" % lvl)
	quit(0)
