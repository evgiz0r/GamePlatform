extends SceneTree
## The islands between a slip road (`*_link`) and the roads it joins (_find_link_islands):
## OSM rarely maps them, so each road laid its own kerb and paving into the triangle and the
## strips stood loose and askew in the junction ("messy", Tel Aviv). Prints how many were
## found, the kerb pieces and corners left out for them, and anything of the island on
## asphalt (should be 0), then shoots N of them (default 6) from above (isl_<i>_top.png) and
## from a driver's height on the slip road (isl_<i>.png). AT=x,z shoots only those within
## 60 m of that point -- before the fix there is no island list, so AT also shoots that spot
## as it stands (at_top.png, at.png from 25 m south).
##   N=6 AT=844,457 tests/run.sh link_islands 7
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	var n_shots := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6
	var at := Vector2.INF
	if OS.get_environment("AT") != "":
		var xz := OS.get_environment("AT").split(",")
		at = Vector2(float(xz[0]), float(xz[1]))
	var isl: Array = g.get("_link_islands") if g.get("_link_islands") != null else []
	var tallies: Dictionary = g._dressing
	print("link islands: %d pieces; kerb pieces left out %s, corners left out %s" % [isl.size(),
		tallies.get("kerb_on_a_link_island", "?"), tallies.get("corners_on_a_link_island", "?")])
	# any of an island over a drivable road's asphalt (its corners and middle, 0.3 m in)
	var on_road := 0
	var area := 0.0
	for p: PackedVector2Array in isl:
		area += absf(g._area_signed(p))
		var c := Vector2.ZERO
		for q in p:
			c += q
		c /= p.size()
		for q in p:
			var t := q.lerp(c, 0.3 / maxf(q.distance_to(c), 0.3))
			if g._asphalt_other(t, -1):
				on_road += 1
				print("  on the road: %s" % t.round())
				break
	print("islands' area %.0f m2, pieces with a point on asphalt: %d" % [area, on_road])
	if at != Vector2.INF:   # what lays a kerb near AT, and whether it faces into a slip road's triangle
		for ring: PackedVector2Array in g._link_rings:
			if (g._bld_box_of(ring) as Rect2).get_center().distance_to(at) < 60.0:
				print("  triangle %s" % [Array(ring).map(func(q): return q.round())])
		for ri in range(g._roads.size()):
			var r: Dictionary = g._roads[ri]
			if not g._kerbed(r):
				continue
			var hw := float(r["w"]) * 0.5
			for run: PackedVector2Array in g._street_runs(r, g.KERB_CUT, true):
				var near := false
				for q in run:
					near = near or q.distance_to(at) < 40.0
				if not near:
					continue
				for sgn: float in [-1.0, 1.0]:
					var inner_side := r.has("median") and sgn == -float(r["o"])
					var inner: PackedVector2Array = g._offset_line(run, hw * sgn)
					var hits := 0
					for i in range(run.size() - 1):
						var na: Vector2 = (inner[i] - run[i]).normalized()
						if g._in_link_island((inner[i] + inner[i + 1]) * 0.5 + na * 1.5):
							hits += 1
					print("  road %d '%s' %s median %s side %d%s: %d of %d pieces in a triangle%s, run %s..%s" % [ri, r["name"], r["k"],
						r.get("median", "-"), sgn, " (median side)" if inner_side else "", hits, run.size() - 1,
						", faces a median" if not inner_side and g._faces_median(run, hw, sgn, ri) else "", run[0].round(), run[run.size() - 1].round()])
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var pick: Array = []
	for p: PackedVector2Array in isl:
		var c: Vector2 = (g._bld_box_of(p) as Rect2).get_center()
		if at == Vector2.INF or c.distance_to(at) < 60.0:
			pick.append(c)
	seed(5)
	pick.shuffle()
	pick = pick.slice(0, n_shots)
	if at != Vector2.INF:
		var y0: float = g._h(at)
		g.look_from(Vector3(at.x, y0 + 40.0, at.y + 40.0 * 0.35), Vector3(at.x, y0, at.y))
		await _snap("at_top")
		g.look_from(Vector3(at.x, y0 + 2.1, at.y + 25.0), Vector3(at.x, y0 + 0.3, at.y))
		await _snap("at")
	for i in range(pick.size()):
		var c: Vector2 = pick[i]
		var y: float = g._h(c)
		print("island %d at %s" % [i, c.round()])
		g.look_from(Vector3(c.x, y + 30.0, c.y + 30.0 * 0.35), Vector3(c.x, y, c.y))
		await _snap("isl_%d_top" % i)
		g.look_from(Vector3(c.x + 14.0, y + 2.1, c.y + 18.0), Vector3(c.x, y + 0.2, c.y))
		await _snap("isl_%d" % i)
	quit(0)
