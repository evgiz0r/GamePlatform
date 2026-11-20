extends SceneTree
## The streets at eye level, the way a phone sees them on a walk: a person's height above
## the pavement of the streets nearest a point, looking along each street both ways and once
## across it, and once down at the pavement in front. For comparing the city with photos of
## the real one. The point: AT="x,z" (metres in the city's frame; the start when not given).
## Last, the nearest block on columns, from the street. Prints each spot; screenshots
## eye_NN_*.png and eye_columns.png in $OUT.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout   # (draw ranges and the shadow map settle after a move)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var at: Vector2 = g._pos
	var env := OS.get_environment("AT").split(",", false)
	if env.size() == 2:
		at = Vector2(float(env[0]), float(env[1]))
	# freeze the game: its own camera would move ours back
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	# the drivable roads nearest the point, one spot on each
	var seen := {}
	var spots: Array = []   # [pavement point, along the street, out from the road]
	for r_try in [20.0, 40.0, 70.0, 110.0, 160.0]:
		for code: int in g._near(g._seg_hash, at, r_try, g.SEG_CELL):
			var ri := code / 4096
			if seen.has(ri) or spots.size() >= 6:
				continue
			var r: Dictionary = g._roads[ri]
			if not r["drive"] or r["k"] == "service":
				continue
			seen[ri] = true
			var pts: PackedVector2Array = r["pts"]
			var j := code % 4096
			var q := Geometry2D.get_closest_point_to_segment(at, pts[j], pts[j + 1])
			var d := (pts[j + 1] - pts[j]).normalized()
			var side := Vector2(-d.y, d.x)
			if side.dot(at - q) < 0.0:
				side = -side
			spots.append([q + side * (float(r["w"]) * 0.5 + 1.4), d, side, String(r["name"])])
	print("point ", at, ": ", spots.size(), " spots")
	var k := 0
	for s: Array in spots:
		var p: Vector2 = s[0]
		var d: Vector2 = s[1]
		var side: Vector2 = s[2]
		var eye := Vector3(p.x, g._h(p) + 0.14 + 1.55, p.y)   # on the pavement (kerb height), eyes at 1.55 m
		print("spot %d at %s on %s" % [k, p, s[3]])
		for view: Array in [["along", d, 0.0], ["back", -d, 0.0], ["across", -side, 0.0], ["down", d, -0.9]]:
			var dir: Vector2 = view[1]
			var tgt := eye + Vector3(dir.x, float(view[2]), dir.y) * 10.0
			g.look_from(eye, tgt)
			g._sky_follow()
			await _snap("eye_%02d_%s" % [k, view[0]])
		k += 1
	# the nearest block on columns, from the street: its lobby under the floors
	var best := -1
	var bd := INF
	for bi in range(g._bld_kind.size()):
		if g._bld_kind[bi] == 1:
			var c: Vector2 = (g._bld_box[bi] as Rect2).get_center()
			if c.distance_to(at) < bd:
				bd = c.distance_to(at)
				best = bi
	if best >= 0:
		var box: Rect2 = g._bld_box[best]
		var c := box.get_center()
		var hit: Dictionary = g._nearest_seg(c, 60.0, true)
		var dir: Vector2 = ((hit["q"] as Vector2) - c).normalized() if not hit.is_empty() else Vector2(1, 0)
		var e2 := c + dir * (box.size.length() * 0.5 + 5.0)
		var eye := Vector3(e2.x, g._h(e2) + 1.6, e2.y)
		g.look_from(eye, Vector3(c.x, g._h(c) + 1.4, c.y))
		g._sky_follow()
		print("block on columns %d m from the point" % int(bd))
		await _snap("eye_columns")
	quit(0)
