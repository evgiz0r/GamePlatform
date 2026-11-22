extends RefCounted
## The city as built, measured for the bugs the user reported that a look at the built city
## can see -- each was a report, a fix and a test that staged it (named below: it has the
## details, the worst places and the shots). city_check.gd runs these on every city so a fix
## cannot come back unseen; the tests themselves were run once and then nothing ran them.
## Static helpers on the game node `g`, after the city is built. Each returns
## [count or measure, the first or worst place as text].
##
## Should read 0:
##   doubled            a thing that stands alone put up twice: two of one kind within reach of
##                      each other, facing the same way. One rule, every kind the city keeps a
##                      list of (doubled_all): stop / give-way signs (a slip road's sign also
##                      given to the street it merges into -- "a lot of places have double
##                      signs"; tests/signs_double.gd), people's lights (a divided road's zebra
##                      on each half, each putting poles at both outer kerbs -- "two red lights
##                      to the same direction for the people"; tests/walk_twins.gd), cars'
##                      lights, bus stops. A new kind of thing that stands alone joins the list.
##   junction_twins     a junction offering the same street twice within 40 degrees (an unnamed
##                      slip road offered beside the turn it shortcuts -- "it gave 4 options, 1
##                      of them is weird"; tests/junction_offers.gd)
##   islands_on_road    1 m samples of a raised traffic island on a road's asphalt or a junction's
##                      disc (the islands lay flat on the road at first -- "weird grass patches on
##                      the road"; tests/islands.gd)
##   medians_over_roads metres of a median's wall over a road it does not belong to (invisible
##                      walls where a median ran on over another road, 32 in Ashdod -- "the
##                      border is too low for my car"; tests/road_blocks.gd)
## A measure with a limit per city (city_check.gd's LIMITS), since the data never reads 0:
##   tilt               the share of road leaning more than 6% side to side ("that's a road in our
##                      test city", leaning; tests/road_tilt.gd; tools/level_roads.py levels it)
##   pavings_overlap    m2 of two different pavings laid over one spot at one height: the
##                      phone's depth buffer flickers between them ("a pavement ... is flickering
##                      a bit"; tests/pave_overlap.gd)

## [[kind, [count, the first pair]], ...] for every kind of thing that stands alone
static func doubled_all(g) -> Array:
	var signs: Array = []
	for a: Array in g.sign_at:
		signs.append([a[0], a[1], String(a[2])])
	var walk: Array = []
	for a: Array in g._walk_spots:
		walk.append([Vector2((a[0] as Vector3).x, (a[0] as Vector3).z), a[1], "a walk light"])
	var lights: Array = []
	for a: Array in g._light_spots:
		lights.append([Vector2((a[0] as Vector3).x, (a[0] as Vector3).z), a[1], "a light"])
	var stops: Array = []
	for ri: int in g._stops_by_road:
		for c: Vector2 in g._stops_by_road[ri]:
			stops.append([c, Vector2.ZERO, "a stop on '%s'" % (g._roads[ri] as Dictionary)["name"]])
	return [["signs doubled", doubled(signs, 3.0)], ["walk lights doubled", doubled(walk, 3.0)],
		["lights doubled", doubled(lights, 3.0)], ["bus stops doubled", doubled(stops, 5.0)]]

## two of `spots` ([where, the way it faces (ZERO: any), what]) within `reach` of each other
## and facing the same way: [count, the first pair]
static func doubled(spots: Array, reach: float) -> Array:
	var cells := {}
	var n := 0
	var first := ""
	for i in range(spots.size()):
		var a: Array = spots[i]
		var p: Vector2 = a[0]
		var cell := Vector2i((p / reach).floor())
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for j: int in cells.get(cell + Vector2i(dx, dz), []):
					var b: Array = spots[j]
					if p.distance_to(b[0]) > reach:
						continue
					if (a[1] as Vector2) != Vector2.ZERO and (a[1] as Vector2).dot(b[1]) < 0.7:
						continue
					n += 1
					if first == "":
						first = "%s at %s and %s at %s" % [b[2], (b[0] as Vector2).round(), a[2], p.round()]
		if not cells.has(cell):
			cells[cell] = []
		(cells[cell] as Array).append(i)
	return [n, first]

static func junction_twins(g) -> Array:
	var n := 0
	var first := ""
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"] or r.get("ring", false):
			continue
		var pts: PackedVector2Array = r["pts"]
		for end: Array in [[pts.size() - 1, 1], [0, -1]]:
			var ei: int = end[0]
			var dir: int = end[1]
			if int(r["o"]) != 0 and int(r["o"]) != dir:
				continue
			var found: Array = g._ap_ways(ri, ei, dir)
			var main: Array = (found[0] as Array).filter(func(x): return not x["service"])
			if main.size() < 2:
				continue
			var prev := pts[ei - dir] if (ei - dir >= 0 and ei - dir < pts.size()) else pts[ei]
			var came := (pts[ei] - prev).normalized()
			var exits: Array = g._cluster_exits(main, came, 0, {})
			for a in range(exits.size()):
				for b in range(a + 1, exits.size()):
					if String(exits[a]["name"]) != "" and exits[a]["name"] == exits[b]["name"] \
							and absf(angle_difference(exits[a]["turn"], exits[b]["turn"])) < 0.7:
						n += 1
						if first == "":
							first = "'%s' twice at %s" % [exits[a]["name"], Vector2i(pts[ei])]
	return [n, first]

## a hit (_nearest_seg) on a deck more than a metre off the ground at both ends of its piece:
## a lawn under a bridge's span is not on its road (streets.gd _island_cut keeps it)
static func high_deck(g, hit: Dictionary) -> bool:
	var r: Dictionary = g._roads[int(hit["road"])]
	if not r.has("ys"):
		return false
	var sj := int(hit["seg"])
	return minf(absf(r["ys"][sj] - r["gs"][sj]), absf(r["ys"][sj + 1] - r["gs"][sj + 1])) > 1.0

static func islands_on_road(g) -> Array:
	var n := 0
	var first := ""
	for piece: PackedVector2Array in g._islands:
		var box: Rect2 = g._bld_box_of(piece)
		var x := box.position.x + 0.5
		while x < box.end.x:
			var z := box.position.y + 0.5
			while z < box.end.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, piece):
					var hit: Dictionary = g._nearest_seg(p, 14.0, true)
					if (not hit.is_empty() and float(hit["edge"]) < -0.05 and not high_deck(g, hit)) or g._in_junction(p, -0.05):
						n += 1
						if first == "":
							first = "at %s" % p.round()
				z += 1.0
			x += 1.0
	return [n, first]

## a median's wall belongs on its own road's middle; metres of one over any other road's
## lanes, a junction's disc or a corner's asphalt (other walls on roads are city_check's own)
static func medians_over_roads(g) -> Array:
	var metres := 0.0
	var first := ""
	for i in range(g._walls.size() / 2):
		var a: Vector2 = g._walls[i * 2]
		var b: Vector2 = g._walls[i * 2 + 1]
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
		if own < 0:
			continue   # not a median
		var half: float = g._wall_r[i]
		var steps := maxi(1, int(a.distance_to(b) / 0.5))
		var bad := 0.0
		for k in range(steps + 1):
			if _road_under(g, a.lerp(b, float(k) / steps), half + 0.3, own) >= 0:
				bad += a.distance_to(b) / steps
		if bad > 0.4:
			metres += bad
			if first == "":
				first = "median of '%s' at %s, %.1f m" % [g._roads[own]["name"], mid.round(), bad]
	return [metres, first]

## the drivable road under p whose lanes, junction disc or corner asphalt p is on (inside by
## `inset`), other than `skip`; -1 if none (as tests/road_blocks.gd)
static func _road_under(g, p: Vector2, inset: float, skip: int) -> int:
	for code: int in g._near(g._seg_hash, p, 12.0, g.SEG_CELL):
		var ri: int = code / 4096
		if ri == skip:
			continue
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var sj: int = code % 4096
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1])) < float(r["w"]) * 0.5 - inset:
			return ri
	# the asphalt round a junction's point (a disc as wide as its widest road), which no one
	# road's lanes cover
	for code: int in g._near(g._seg_hash, p, 12.0, g.SEG_CELL):
		var r2: Dictionary = g._roads[code / 4096]
		if not r2["drive"] or r2["pv"]:
			continue
		var ids: PackedInt32Array = r2["ids"]
		for n: int in [ids[code % 4096], ids[code % 4096 + 1]]:
			if g._node_ways(n) >= 3 and p.distance_to(g._nodes[n]) < g._node_r[n] * 1.05 - inset:
				return code / 4096
	# and the asphalt a rounded corner adds out to its kerb
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

static func tilt(g) -> Array:
	var total := 0.0
	var over6 := 0.0
	var over10 := 0.0
	var worst := [0.0, ""]
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.5:
				continue
			var d := (b - a) / L
			var side := Vector2(-d.y, d.x)
			var s := 0.0
			while s < L:
				var c := a + d * s
				var y0: float = g._h(c)
				var yl: float = g._decks.surf(c + side * hw, y0 + 1.0) if r.has("ys") else g._h(c + side * hw)
				var yr: float = g._decks.surf(c - side * hw, y0 + 1.0) if r.has("ys") else g._h(c - side * hw)
				var slope := absf(yl - yr) / (2.0 * hw)
				total += 3.0
				if slope > 0.06:
					over6 += 3.0
				if slope > 0.10:
					over10 += 3.0
				if slope > float(worst[0]):
					worst = [slope, "%.0f%% at %s on '%s'" % [slope * 100.0, c.round(), r["name"]]]
				s += 3.0
	return [100.0 * over6 / maxf(total, 1.0), "%.1f%% of it over 10%%; worst %s" % [100.0 * over10 / maxf(total, 1.0), worst[1]]]

## m2 of two different pavings laid at one height over one spot (the kerbs' mesh's faces up;
## as tests/pave_overlap.gd). Needs the meshes' arrays: -1 when they read back empty.
static func pavings_overlap(g) -> Array:
	const CELL := 3.0
	var tris: Array = []
	var meshes := 0
	for mi: MeshInstance3D in g.world.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh as ArrayMesh
		if m == null:
			continue
		for s in range(m.get_surface_count()):
			if m.surface_get_material(s) != g._kerb_mat:
				continue
			meshes += 1
			var arr := m.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := idx.size() if not idx.is_empty() else v.size()
			var xf := mi.global_transform
			for i in range(0, n, 3):
				var i0 := idx[i] if not idx.is_empty() else i
				var i1 := idx[i + 1] if not idx.is_empty() else i + 1
				var i2 := idx[i + 2] if not idx.is_empty() else i + 2
				if nrm[i0].y < 0.9 or col[i0].b <= 0.5:
					continue   # a kerb's face, or a kerb's top: pavement only
				var a := xf * v[i0]
				var b := xf * v[i1]
				var c := xf * v[i2]
				var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
				if absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) < 0.002:
					continue
				tris.append([tri, (a.y + b.y + c.y) / 3.0, col[i0].r])
	if tris.is_empty():
		return [-1.0, "no pavement read back (%d kerb meshes)" % meshes]
	var cells := {}
	for t in range(tris.size()):
		var tri: PackedVector2Array = tris[t][0]
		var box := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
		for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
				var k := Vector2i(cx, cz)
				if not cells.has(k):
					cells[k] = []
				cells[k].append(t)
	var area := 0.0
	var worst := [0.0, Vector2.ZERO]
	var places := {}   # 25 m square -> [m2, a point, {code pair: m2}]  (pavings_where.gd)
	for k: Vector2i in cells:
		var list: Array = cells[k]
		for x in range(list.size()):
			for y in range(x + 1, list.size()):
				var ta: int = list[x]
				var tb: int = list[y]
				if absf(float(tris[ta][1]) - float(tris[tb][1])) > 0.04 or absf(float(tris[ta][2]) - float(tris[tb][2])) <= 0.01:
					continue   # (one paving laid on itself at a bend flickers between the same pattern: unseen)
				var A: PackedVector2Array = tris[ta][0]
				var B: PackedVector2Array = tris[tb][0]
				var boxa := Rect2(A[0], Vector2.ZERO).expand(A[1]).expand(A[2])
				var boxb := Rect2(B[0], Vector2.ZERO).expand(B[1]).expand(B[2])
				if not boxa.intersects(boxb):
					continue
				var both := boxa.intersection(boxb)
				if Vector2i(floori(both.position.x / CELL), floori(both.position.y / CELL)) != k:
					continue   # (counted once, in the cell where the overlap starts)
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(A, B):
					var s := 0.0
					for i in range(piece.size()):
						s += piece[i].cross(piece[(i + 1) % piece.size()])
					area += absf(s) * 0.5
					var pk := Vector2i(floori(piece[0].x / 25.0), floori(piece[0].y / 25.0))
					if not places.has(pk):
						places[pk] = [0.0, piece[0], {}, [A, B]]   # (and the first two triangles that overlap there)
					places[pk][0] = float(places[pk][0]) + absf(s) * 0.5
					var pair := "%.2f/%.2f" % [minf(tris[ta][2], tris[tb][2]), maxf(tris[ta][2], tris[tb][2])]
					places[pk][2][pair] = float(places[pk][2].get(pair, 0.0)) + absf(s) * 0.5
					if absf(s) * 0.5 > float(worst[0]):
						worst = [absf(s) * 0.5, piece[0]]
	last_places = places.values()
	last_places.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	return [area, "worst piece %.1f m2 at %s" % [worst[0], (worst[1] as Vector2).round()] if area > 0.0 else ""]

## pavings_overlap's overlap by 25 m square, most first: [m2, a point, {"code/code": m2}, [the
## first two triangles that overlap there]]
static var last_places: Array = []

## The lights as built, as tests/light_audit.gd counts them before its drive (it calls this):
## every signalled junction against what a driver and a walker would expect. Returns the counts
## and the audit's summary lines; `verbose` prints each place. city_check.gd guards them per city.
static func light_counts(g, verbose := false) -> Dictionary:
	var lines: Array = []
	# ---- groups at each lit junction
	var conflicts := 0
	var conflict_j := {}
	var single := 0
	for j: int in g._lit:
		var arms := light_arms(g, j)
		var seen := {}
		var groups := {}
		for a: Array in arms:
			groups[g._light_group(j, a[0])] = true
		if groups.size() < 2:
			single += 1
		# (a way from inside the junction -- the road between two of its points -- has no light
		# and no line: its cars are in the junction already, and it is no way in to conflict)
		var inside: Array = []
		for way: Array in g._sig_line.get(j, []):
			if bool(way[3]):
				inside.append([way[0], int(way[2])])
		var from_inside := func(a: Array) -> bool:
			return inside.any(func(w): return int(w[1]) == int(a[1]) and (w[0] as Vector2).dot(a[0]) > 0.99)
		for x in range(arms.size()):
			for y in range(x + 1, arms.size()):
				var A: Array = arms[x]
				var B: Array = arms[y]
				if not A[3] or not B[3] or from_inside.call(A) or from_inside.call(B):
					continue
				var da: Vector2 = A[0]
				var db: Vector2 = B[0]
				if absf(da.dot(db)) < 0.6 and g._light_group(j, da) == g._light_group(j, db):
					conflicts += 1
					conflict_j[j] = true
					if verbose:
						print("  same group, crossing: node %d at %s  '%s' %s / '%s' %s  angle %d" % [j, g._nodes[j].round(), A[2], da.snapped(Vector2(0.01, 0.01)), B[2], db.snapped(Vector2(0.01, 0.01)), int(rad_to_deg(da.angle_to(db)))])
	lines.append("lit junctions %d; crossing ways in sharing a group: %d (at %d junctions); junctions with one group only: %d" % [g._lit.size(), conflicts, conflict_j.size(), single])
	# ---- stop points that are not a junction's (a light mapped a few metres out)
	var short := 0
	for n: int in g._sig_set:
		if g._node_ways(n) < 3:
			var near_j := false
			for o: int in g._sig_set:
				if o != n and g._node_ways(o) >= 3 and g._nodes[o].distance_to(g._nodes[n]) < 40.0:
					near_j = true
			if near_j:
				short += 1
				if verbose:
					print("  stop point %d %s is not a junction, and a lit junction is within 40 m" % [n, g._nodes[n].round()])
	var multi := 0
	var most := 0
	for st: Dictionary in g._sites:
		if (st["nodes"] as Array).size() > 1:
			multi += 1
		most = maxi(most, (st["nodes"] as Array).size())
	if verbose:
		for st: Dictionary in g._sites:
			var ns: Array = st["nodes"]
			if ns.size() >= 4:
				var names := {}
				var span := 0.0
				for n: int in ns:
					span = maxf(span, g._nodes[n].distance_to(st["c"]))
					for e: Vector2i in g._node_roads[n]:
						names[String((g._roads[e.x] as Dictionary)["name"])] = true
				print("  site of %d points at %s, %.0f m across: %s" % [ns.size(), (st["c"] as Vector2).round(), span * 2.0, ", ".join(names.keys())])
	lines.append("sites %d (of several points: %d, the most %d); stop points short of a junction (where no pole stands): %d" % [g._sites.size(), multi, most, short])
	# ---- knots: a junction's points within 35 m of each other along a road
	var unlit_twins := 0
	var split_groups := 0
	for j: int in g._lit:
		for e: Vector2i in g._node_roads[j]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"]:
				continue
			var ids: PackedInt32Array = r["ids"]
			var pts: PackedVector2Array = r["pts"]
			for step: int in [-1, 1]:
				var k := e.y
				var d := 0.0
				while k + step >= 0 and k + step < ids.size():
					d += pts[k].distance_to(pts[k + step])
					k += step
					if d > 35.0:
						break
					var o: int = ids[k]
					if g._node_ways(o) < 3:
						continue
					if not g._lit.has(o) and not g._sig_set.has(o) and g._other_half(j, o, e.x):
						unlit_twins += 1
						if verbose:
							print("  lit %d %s and the unlit other half of its road %d %.0f m along '%s'" % [j, g._nodes[j].round(), o, d, r["name"]])
					elif g._lit.has(o) and o > j:
						# travelling j -> o along this road: same light both?
						var dir := (pts[k] - pts[k - step]).normalized()
						var gj: int = g._light_group(j, (pts[e.y] - pts[e.y - step]).normalized() if e.y - step >= 0 and e.y - step < pts.size() else dir)
						var go: int = g._light_group(o, dir)
						if gj != go:
							split_groups += 1
							if verbose:
								print("  knot %d -> %d along '%s' (%.0f m): group %d then %d" % [j, o, r["name"], d, gj, go])
					break
	lines.append("knots: lit junction with the other half of its divided road unlit: %d; a road through two lit points of one knot in different groups: %d" % [unlit_twins, split_groups])
	# ---- ways in with no pole: built poles face -dir from their spot
	var no_pole := 0
	var on_zebra := 0
	for j: int in g._lit:
		for a: Array in g._sig_line.get(j, []):
			if a[3]:
				continue   # from inside the site: no light on purpose
			var din: Vector2 = a[0]
			# where a stopped car's front is, against the zebras on that way in
			var front: Vector2 = g._nodes[j] - din * (float(a[1]) + 1.0)
			for ni: int in g._crossing_nodes:
				var zp: Vector2 = g._nodes[ni]
				if zp.distance_to(front) < 12.0:
					var along := (front - zp).dot(din)
					if absf((front - zp).dot(Vector2(-din.y, din.x))) < 3.0 and along > -1.5 and along < 1.5 + g.CAR_LEN:
						on_zebra += 1
						if verbose:
							print("  node %d %s: a car stopped at the line has its front on the zebra %d" % [j, g._nodes[j].round(), ni])
			var found := false
			for sp: Array in g._light_spots:
				var hd: Vector3 = sp[0]
				var p := Vector2(hd.x, hd.z)
				if p.distance_to(g._nodes[j]) < 30.0 and (sp[1] as Vector2).dot(-din) > 0.95:
					found = true
					break
			if not found:
				no_pole += 1
				if verbose:
					var r: Dictionary = g._roads[int(a[2])]
					print("  node %d %s: no light for the way in %s along '%s' (%s, w %.1f, one-way %d)" % [j, g._nodes[j].round(), din.snapped(Vector2(0.01, 0.01)), r["name"], r["k"], r["w"], r["o"]])
	lines.append("ways in to a lit junction with no light facing them: %d; stop lines that leave a waiting car's front on a zebra: %d" % [no_pole, on_zebra])
	# ---- walk lights: the road under the zebra, both ways, against the walk light's group
	var walk_bad := 0
	var walk_n := 0
	for ni: int in g._crossing_nodes:
		var z: Array = g._zebra_geom(ni)
		if z.is_empty():
			continue
		var j: int = g._zebra_light(ni)
		if j < 0:
			continue
		walk_n += 1
		var gw: int = g._light_group(j, z[3])
		var gb: int = g._light_group(j, -(z[3] as Vector2))
		if gw != gb:
			walk_bad += 1
			if verbose:
				print("  zebra %d %s: its road is group %d one way and %d the other" % [ni, (z[0] as Vector2).round(), gw, gb])
	lines.append("zebras with walk lights: %d; of them on a road with green one way while the green man shows: %d" % [walk_n, walk_bad])
	return {"conflicts": conflicts, "single": single, "short": short, "unlit_twins": unlit_twins,
		"split_groups": split_groups, "no_pole": no_pole, "on_zebra": on_zebra, "walk_n": walk_n,
		"walk_bad": walk_bad, "lines": lines}

## a lit junction's arms: [way in, road, name, one-way lets it in]
static func light_arms(g, j: int) -> Array:
	var out: Array = []   # [way in, road, name, one-way ok]
	var c: Vector2 = g._nodes[j]
	for e: Vector2i in g._node_roads[j]:
		var r: Dictionary = g._roads[e.x]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		for d2: int in [-1, 1]:
			var from := e.y + d2
			if from < 0 or from >= pts.size():
				continue
			var ok: bool = r["o"] == 0 or r["o"] == -d2
			out.append([(c - pts[from]).normalized(), e.x, String(r["name"]), ok])
	return out

## Cars parked by the streets (g._parked_at, _parked_face) where nobody parks, each judged on
## the car's body: between two roads (asphalt within 2.6 m either side: a divided road's
## median -- "a lot of parked cars in the middle of somewhat main roads"; tests/parked_median.gd),
## in a bus stop (its middle within the law's 12 m either side along the stop's own kerb --
## "a lot of parked cars inside bus stations"), on a zebra (its body over the stripes), in a
## junction (an end inside the junction's disc). [[row, [count, the first]], ...]
static func parked_wrong(g) -> Array:
	var res := {"parked on a median": [0, ""], "parked in a bus stop": [0, ""], "parked on a zebra": [0, ""],
		"parked in a junction": [0, ""]}
	var cell := 20.0
	var stops := {}      ## cell -> [[spot, its kerb's way]]
	for ri: int in g._stops_by_road:
		var pts: PackedVector2Array = g._roads[ri]["pts"]
		for c: Vector2 in g._stops_by_road[ri]:
			var best := INF
			var dir := Vector2.ZERO
			for j in range(pts.size() - 1):
				var q := Geometry2D.get_closest_point_to_segment(c, pts[j], pts[j + 1])
				if q.distance_squared_to(c) < best:
					best = q.distance_squared_to(c)
					dir = (pts[j + 1] - pts[j]).normalized()
			_cell_add(stops, c, cell, [c, dir])
	var zebras := {}     ## cell -> [[middle, along the road, half the road's width]]
	for ni: int in g._crossing_nodes:
		var z: Array = g._zebra_geom(ni)
		if not z.is_empty():
			_cell_add(zebras, z[0], cell, [z[0], z[3], float(z[2])])
	var joins := {}      ## cell -> [[junction point, its disc's radius]]
	for n in range(g._nodes.size()):
		if g._node_ways(n) >= 3:
			_cell_add(joins, g._nodes[n], cell, [g._nodes[n], float(g._node_r[n])])
	var half: float = g.CAR_LEN * 0.5
	for i in range(g._parked_at.size()):
		var p: Vector2 = g._parked_at[i]
		var f: Vector2 = g._parked_face[i]
		var lx := Vector2(-f.y, f.x)
		var at := "at %s" % p.round()
		if not g._off_road(p + lx * 2.6, 0.0) and not g._off_road(p - lx * 2.6, 0.0):
			_count(res["parked on a median"], at)
		for st: Array in _cell_near(stops, p, cell):
			var c: Vector2 = st[0]
			var d: Vector2 = st[1]
			if absf((p - c).dot(d)) < g.BUS_CLEAR and absf((p - c).dot(Vector2(-d.y, d.x))) < 4.0:
				_count(res["parked in a bus stop"], at)
				break
		for z: Array in _cell_near(zebras, p, cell):
			var mid: Vector2 = z[0]
			var along: Vector2 = z[1]
			# the stripes: about 2 m either side of the crossing's line, kerb to kerb (+ the
			# parking strip by it); the car's body: its half length along the road, a metre across
			if absf((p - mid).dot(along)) < 2.0 + half * absf(f.dot(along)) + 0.9 * absf(lx.dot(along)) \
					and absf((p - mid).dot(Vector2(-along.y, along.x))) < float(z[2]) + 2.5:
				_count(res["parked on a zebra"], at)
				break
		for jn: Array in _cell_near(joins, p, cell):
			if (p + f * half).distance_to(jn[0]) < float(jn[1]) or (p - f * half).distance_to(jn[0]) < float(jn[1]):
				_count(res["parked in a junction"], at)
				break
	var out: Array = []
	for k: String in res:
		out.append([k, res[k]])
	return out

static func _count(row: Array, at: String) -> void:
	row[0] = int(row[0]) + 1
	if String(row[1]) == "":
		row[1] = at

static func _cell_add(cells: Dictionary, p: Vector2, size: float, item: Array) -> void:
	var k := Vector2i((p / size).floor())
	if not cells.has(k):
		cells[k] = []
	(cells[k] as Array).append(item)

## the items in p's cell and the eight round it
static func _cell_near(cells: Dictionary, p: Vector2, size: float) -> Array:
	var out: Array = []
	var k := Vector2i((p / size).floor())
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			out.append_array(cells.get(k + Vector2i(dx, dz), []))
	return out

## Any solid thing put up twice, of whatever kind: two posts (every tree, pole, bollard, bin,
## lamp, bench... registers one, g._add_post) the same size with their middles within 0.3 m.
## The doubled rows above know which way each kind faces; this knows no kinds, so it catches
## only the same spot -- but for every kind, with no list of its own needed. A parked car's
## posts (`parked_r`) are left out: five overlap along each car. [count, the first]
static func posts_twice(g, parked_r: float) -> Array:
	var n := 0
	var first := ""
	for i in range(g._posts.size()):
		var r: float = g._post_r[i]
		if is_equal_approx(r, parked_r):
			continue
		var p: Vector2 = g._posts[i]
		for j: int in g._near(g._post_hash, p, 0.3, g.BLD_CELL):
			if j <= i or not is_equal_approx(float(g._post_r[j]), r):
				continue
			if (g._posts[j] as Vector2).distance_to(p) < 0.3:
				n += 1
				if first == "":
					first = "two posts %.2f m across at %s" % [r * 2.0, p.snapped(Vector2(0.1, 0.1))]
				break
	return [n, first]
