extends SceneTree
## Things solid to the car standing in a road: a median's wall running out over a road
## it does not belong to (a bend, a junction, a slip road), any other wall (a fence, a garden
## wall, a barrier) or a post (a pole, a sign, a light, a bollard) on a road's lanes, a
## junction's middle or a rounded corner's asphalt. Prints each, with
## where, and shoots the worst from above (OUT). Good: none, but medians on their own road.
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the drivable road under p whose lanes p is on (inside its asphalt by `inset`), or -1
func _road_under(p: Vector2, inset: float, skip: int) -> int:
	for code: int in g._near(g._seg_hash, p, 12.0, g.SEG_CELL):
		var ri: int = code / 4096
		if ri == skip:
			continue
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var sj: int = code % 4096
		var cp := Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1])
		if p.distance_to(cp) < float(r["w"]) * 0.5 - inset:
			return ri
	# the asphalt round a junction's point (a disc as wide as its widest road), which no one
	# road's lanes cover: a railing or bollard at a corner stood there
	for code: int in g._near(g._seg_hash, p, 12.0, g.SEG_CELL):
		var r2: Dictionary = g._roads[code / 4096]
		if not r2["drive"] or r2["pv"]:
			continue
		var ids: PackedInt32Array = r2["ids"]
		for n: int in [ids[code % 4096], ids[code % 4096 + 1]]:
			if g._node_ways(n) >= 3 and p.distance_to(g._nodes[n]) < g._node_r[n] * 1.05 - inset:
				return code / 4096
	# and the asphalt a rounded corner adds out to its kerb (bollards by a zebra near a
	# junction stood there, in front of the corner's kerb): reported as the nearest road's
	for key: int in g._near(g._fill_hash, p, 1.0, g.BLD_CELL):
		var poly: PackedVector2Array = g._corner_fill[key]
		if not Geometry2D.is_point_in_polygon(p, poly):
			continue
		var edge := INF
		for k in range(1, poly.size() - 1):
			edge = minf(edge, Geometry2D.get_closest_point_to_segment(p, poly[k], poly[k + 1]).distance_to(p))
		if edge > inset:
			var hit: Dictionary = g._nearest_seg(p, 30.0, true)
			return int(hit["road"]) if not hit.is_empty() else -1
	return -1

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var found: Array = []   # [where, what, metres]
	# walls: a median belongs on its own road's middle; anything else on no road's lanes
	var n_walls: int = g._walls.size() / 2
	for i in range(n_walls):
		var a: Vector2 = g._walls[i * 2]
		var b: Vector2 = g._walls[i * 2 + 1]
		var half: float = g._wall_r[i]
		var mid := (a + b) * 0.5
		var own := -1
		for code: int in g._near(g._seg_hash, mid, 4.0, g.SEG_CELL):
			var r: Dictionary = g._roads[code / 4096]
			if not r.has("mid"):
				continue
			var pts: PackedVector2Array = r["pts"]
			var sj: int = code % 4096
			if Geometry2D.get_closest_point_to_segment(mid, pts[sj], pts[sj + 1]).distance_to(mid) < 0.6:
				own = code / 4096
		var bad := 0.0
		var steps := maxi(1, int(a.distance_to(b) / 0.5))
		var on := -1
		for k in range(steps + 1):
			var p := a.lerp(b, float(k) / steps)
			var ri := _road_under(p, half + 0.3, own)
			if ri >= 0:
				bad += a.distance_to(b) / steps
				on = ri
		if bad > 0.4:
			found.append([mid, ("median of '%s'" % g._roads[own]["name"]) if own >= 0 else "wall", bad, on])
	# posts on lanes
	for i in range(g._posts.size()):
		var p: Vector2 = g._posts[i]
		var ri := _road_under(p, float(g._post_r[i]) + 0.3, -1)
		if ri >= 0:
			found.append([p, "post r %.2f" % g._post_r[i], 0.0, ri])
	found.sort_custom(func(x, y): return x[2] > y[2])
	var medians := found.filter(func(f): return String(f[1]).begins_with("median"))
	var walls := found.filter(func(f): return f[1] == "wall")
	var posts := found.filter(func(f): return String(f[1]).begins_with("post"))
	var on_street := found.filter(func(f): return (g._roads[int(f[3])] as Dictionary)["k"] != "service")
	print("solid in a road: median pieces over another road %d, walls %d, posts %d (on a street, not a service lane: %d)" % [medians.size(), walls.size(), posts.size(), on_street.size()])
	for f: Array in found.slice(0, 40):
		print("  %s at %s: %.1f m over '%s' (%s)" % [f[1], (f[0] as Vector2).round(), f[2], g._roads[int(f[3])]["name"], g._roads[int(f[3])]["k"]])
	if OS.get_environment("OUT") == "" or found.is_empty():
		quit(0)
		return
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var shot := 0
	var done: Array = []
	for f: Array in found:
		var p: Vector2 = f[0]
		if done.any(func(q): return (q as Vector2).distance_to(p) < 40.0):
			continue
		done.append(p)
		var y: float = g._h(p)
		g.look_from(Vector3(p.x + 0.1, y + 38.0, p.y + 14.0), Vector3(p.x, y, p.y))
		await _snap("block_%d" % shot)
		shot += 1
		if shot >= int(OS.get_environment("SHOTS") if OS.get_environment("SHOTS") != "" else "6"):
			break
	quit(0)
