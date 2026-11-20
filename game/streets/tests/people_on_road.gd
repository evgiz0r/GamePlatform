extends SceneTree
## People on the asphalt: over a minute of autodrive, every half second, every visible
## walker / waiting or leaving crosser that stands on a drivable road's surface.
var g: Node
func _initialize() -> void:
	_run()
func _on_asphalt(p: Vector2) -> Array:
	var best: Array = []
	for code: int in g._near(g._seg_hash, p, 20.0, g.SEG_CELL):
		var ri: int = code / 4096
		var r: Dictionary = g._roads[ri]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var sj: int = code % 4096
		var cp := Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1])
		var depth: float = float(r["w"]) * 0.5 - p.distance_to(cp)
		if depth > 0.3 and (best.is_empty() or depth > best[1]):
			best = [ri, depth]
	return best
func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
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
	if OS.get_environment("FULL") == "":
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	g._set_auto(true)
	var looks := 0
	var walk_n := 0
	var walk_bad := 0
	var cr_n := 0
	var cr_bad := 0
	var why := {}
	var shot_at: Array = []
	for f in range(120):
		await create_timer(0.5).timeout
		for w: Dictionary in g._walkers:
			var a: Node3D = w["actor"]
			if not a.visible:
				continue
			walk_n += 1
			var p := Vector2(a.position.x, a.position.z)
			var hit := _on_asphalt(p)
			if hit.is_empty():
				continue
			walk_bad += 1
			var r: Dictionary = g._roads[hit[0]]
			var key := "walker on %s%s" % [r["k"], " (dual half)" if r.has("median") else ""]
			why[key] = why.get(key, 0) + 1
			if shot_at.size() < 3 and p.distance_to(g._pos) < 40.0:
				shot_at.append(p)
		for cr: Dictionary in g._crossers:
			var a: Node3D = cr["actor"]
			if not a.visible or cr["state"] in ["cross", "back", "off"]:
				continue
			cr_n += 1
			var p := Vector2(a.position.x, a.position.z)
			var hit := _on_asphalt(p)
			if hit.is_empty():
				continue
			cr_bad += 1
			var r: Dictionary = g._roads[hit[0]]
			var own: Array = g._zebra_geom(int(cr["ni"]))
			var key := "crosser %s on %s%s, zebra hw %.1f" % [cr["state"], r["k"], " (dual half)" if r.has("median") else "", float(own[2]) if not own.is_empty() else -1.0]
			why[key] = why.get(key, 0) + 1
			if shot_at.size() < 3 and p.distance_to(g._pos) < 40.0:
				shot_at.append(p)
		if shot_at.size() > looks and OS.get_environment("OUT") != "":
			var p: Vector2 = shot_at[looks]
			var eye: Vector2 = g._pos - g._fwd() * 6.0
			g.look_from(Vector3(eye.x, g._h(eye) + 4.0, eye.y), Vector3(p.x, g._h(p) + 0.8, p.y))
			await _snap("ppl_%d_%d" % [lvl, looks])
			looks += 1
	print("walkers seen %d, on asphalt %d (%.1f%%)" % [walk_n, walk_bad, 100.0 * walk_bad / maxf(walk_n, 1)])
	print("crossers waiting/leaving %d, on asphalt %d" % [cr_n, cr_bad])
	for k in why:
		print("  ", why[k], "  ", k)
	quit(0)
