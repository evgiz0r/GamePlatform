extends SceneTree
## Buildings on the road: how many were cut back, how many still stand on a road's asphalt
## or kerb, and a look down Gazit (Givatayim) from the road.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)
func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	var t0 := Time.get_ticks_msec()
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	print("narrowed %s, cut back %s, left over a road %s" % [g._dressing.get("narrowed"), g._dressing.get("bld_clipped"), g._dressing.get("bld_over_road")])
	var on_road := 0
	var close := 0
	for bi in range(g._blds.size()):
		if g._bld_solid[bi] == 0:
			continue
		var ring: PackedVector2Array = g._blds[bi]
		var box: Rect2 = g._bld_box[bi]
		var worst := INF
		for code: int in g._near(g._seg_hash, box.get_center(), box.size.length() * 0.5 + 14.0, g.SEG_CELL):
			var r: Dictionary = g._roads[code / 4096]
			if not g._kerbed(r):
				continue
			var pts: PackedVector2Array = r["pts"]
			var sj: int = code % 4096
			for k in range(ring.size()):
				var cp := Geometry2D.get_closest_points_between_segments(pts[sj], pts[sj + 1], ring[k], ring[(k + 1) % ring.size()])
				worst = minf(worst, cp[0].distance_to(cp[1]) - float(r["w"]) * 0.5)
		if worst < 0.2:
			on_road += 1
			if on_road <= 6:
				print("  still on a road: building %d at %s, %.1f m into it, area %.0f" % [bi, str(Vector2i(box.get_center())), -worst, g._area(ring)])
		elif worst < 1.2:
			close += 1
	print("solid buildings on a road's asphalt or kerb: %d; with under a metre of pavement: %d" % [on_road, close])
	if lvl != 1 or OS.get_environment("OUT") == "":
		quit(0)
		return
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var shots := 0
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if String(r["en"]) != "Gazit" or not r["drive"] or shots >= 2:
			continue
		var pts: PackedVector2Array = r["pts"]
		var m := pts.size() / 2
		var d := (pts[mini(m + 1, pts.size() - 1)] - pts[m - 1 if m > 0 else 0]).normalized()
		var eye: Vector2 = pts[m] - d * 14.0 + Vector2(-d.y, d.x) * 1.0
		g._pos = eye
		g._names_tick(1.0)
		g.look_from(Vector3(eye.x, g._h(eye) + 2.2, eye.y), Vector3(pts[m].x + d.x * 10.0, g._h(pts[m]) + 1.5, pts[m].y + d.y * 10.0))
		await _snap("gazit_%d" % shots)
		shots += 1
	quit(0)
