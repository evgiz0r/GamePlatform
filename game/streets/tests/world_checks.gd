extends RefCounted
## The city as built, measured for the bugs the user reported that a look at the built city
## can see -- each was a report, a fix and a test that staged it (named below: it has the
## details, the worst places and the shots). city_check.gd runs these on every city so a fix
## cannot come back unseen; the tests themselves were run once and then nothing ran them.
## Static helpers on the game node `g`, after the city is built. Each returns
## [count or measure, the first or worst place as text].
##
## Should read 0:
##   signs_doubled      two stop / give-way poles facing the same way within 3 m (a slip
##                      road's sign also given to the street it merges into -- the user's
##                      "a lot of places have double signs"; tests/signs_double.gd)
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

static func signs_doubled(g) -> Array:
	var at: Array = g.sign_at
	var n := 0
	var first := ""
	for i in range(at.size()):
		for j in range(i + 1, at.size()):
			var a: Array = at[i]
			var b: Array = at[j]
			if (a[0] as Vector2).distance_to(b[0]) > 3.0 or (a[1] as Vector2).dot(b[1]) < 0.7:
				continue
			n += 1
			if first == "":
				first = "%s at %s and %s at %s" % [a[2], (a[0] as Vector2).round(), b[2], (b[0] as Vector2).round()]
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
					if (not hit.is_empty() and float(hit["edge"]) < -0.05) or g._in_junction(p, -0.05):
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
						places[pk] = [0.0, piece[0], {}]
					places[pk][0] = float(places[pk][0]) + absf(s) * 0.5
					var pair := "%.2f/%.2f" % [minf(tris[ta][2], tris[tb][2]), maxf(tris[ta][2], tris[tb][2])]
					places[pk][2][pair] = float(places[pk][2].get(pair, 0.0)) + absf(s) * 0.5
					if absf(s) * 0.5 > float(worst[0]):
						worst = [absf(s) * 0.5, piece[0]]
	last_places = places.values()
	last_places.sort_custom(func(x, y): return float(x[0]) > float(y[0]))
	return [area, "worst piece %.1f m2 at %s" % [worst[0], (worst[1] as Vector2).round()] if area > 0.0 else ""]

## pavings_overlap's overlap by 25 m square, most first: [m2, a point, {"code/code": m2}]
static var last_places: Array = []
