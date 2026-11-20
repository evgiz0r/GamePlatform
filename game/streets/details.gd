extends RefCounted
## What a walk filmed along a real street showed that OpenStreetMap does not: a short street
## the map draws as a footpath, the zebra it leaves unmarked, the walls and fences down a
## passage, the bin in it and the railings at its end. Hand-placed, per city, in
## cities/details/<city>.json -- metres on the city file's own ground (+x east, +z south) --
## and applied as the city loads: the road edits before the roads are read, the rest once
## the street is built. A city with no such file is left as baked.
##
## The file can also hold walks: a route as [seconds, x, z] points, timed to the film it was
## taken from, that a place in LEVELS can replay in first person (see "A filmed walk" in
## streets.gd).
##
## Format (every key optional):
##   roads     {drop: [{k, name, near: [x, z]}],   the baked roads of that kind and name
##                                                    that pass within 3 m of `near`
##              add: [{pts: [[x, z]...], k, w, name, name_en, o, l, sv}]}   ends within 1 m of
##                                                    a baked node join it
##   crossings [[x, z], ...]                         zebras at the road nodes nearest these
##   areas     [{k, p: [[x, z]...]}]                 as the city file's areas (plaza, park...)
##   lines     [{kind, pts: [[x, z]...], h, base}]   stone_wall, wood_fence, loop_fence, hedge
##   props     [{kind, at: [x, z], dir: [x, z]}]     bin, hoop_railing
##   walks     {id: {name, points: [[t, x, z]...]}}

var g: Node                    ## the streets game
var data := {}

func _init(game: Node, d: Dictionary) -> void:
	g = game
	data = d

## the file for a city, or {} when it has none
static func load_for(dir: String, city: String) -> Dictionary:
	var path := dir + "details/" + city + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

## ---- before the roads are read: edits to the parsed city file ------------------------------

func edit_city(city: Dictionary) -> void:
	var sc := float(city.get("scale", 10))
	var nodes: Array = city["nodes"]
	var ed: Dictionary = data.get("roads", {})
	for dr: Dictionary in ed.get("drop", []):
		var near := _v2(dr["near"])
		var kept: Array = []
		for r: Dictionary in city["roads"]:
			if String(r.get("k", "")) == String(dr.get("k", "")) and String(r.get("name", "")) == String(dr.get("name", "")) \
					and _passes(r, nodes, near, sc):
				continue
			kept.append(r)
		city["roads"] = kept
	for ad: Dictionary in ed.get("add", []):
		var ids: Array = []
		for p: Array in ad["pts"]:
			ids.append(_node_at(nodes, _v2(p), sc))
		var r := {"n": ids, "k": ad["k"], "w": float(ad.get("w", 6.0))}
		for key: String in ["name", "name_en", "o", "l", "sv"]:
			if ad.has(key):
				r[key] = ad[key]
		city["roads"].append(r)
	var cross: Array = city.get("crossings", [])
	for p: Array in data.get("crossings", []):
		cross.append(_nearest_node(nodes, _v2(p), sc))
	city["crossings"] = cross
	var areas: Array = city.get("areas", [])
	for a: Dictionary in data.get("areas", []):
		var flat: Array = []
		for p: Array in a["p"]:
			flat.append(roundi(float(p[0]) * sc))
			flat.append(roundi(float(p[1]) * sc))
		areas.append({"k": a["k"], "p": flat})
	city["areas"] = areas

func _v2(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))

func _passes(r: Dictionary, nodes: Array, near: Vector2, sc: float) -> bool:
	var ids: Array = r["n"]
	for j in range(ids.size() - 1):
		var a := Vector2(nodes[int(ids[j]) * 2], nodes[int(ids[j]) * 2 + 1]) / sc
		var b := Vector2(nodes[int(ids[j + 1]) * 2], nodes[int(ids[j + 1]) * 2 + 1]) / sc
		if Geometry2D.get_closest_point_to_segment(near, a, b).distance_to(near) < 3.0:
			return true
	return false

func _nearest_node(nodes: Array, p: Vector2, sc: float) -> int:
	var best := -1
	var bd := INF
	for i in range(nodes.size() / 2):
		var d := Vector2(nodes[i * 2], nodes[i * 2 + 1]).distance_squared_to(p * sc)
		if d < bd:
			bd = d
			best = i
	return best

## the baked node within 1 m of p, or a new one
func _node_at(nodes: Array, p: Vector2, sc: float) -> int:
	var i := _nearest_node(nodes, p, sc)
	if i >= 0 and Vector2(nodes[i * 2], nodes[i * 2 + 1]).distance_to(p * sc) <= sc:
		return i
	nodes.append(roundi(p.x * sc))
	nodes.append(roundi(p.y * sc))
	return nodes.size() / 2 - 1

## ---- once the street is built: what stands on it -------------------------------------------

func build() -> void:
	var b = g.new_cbuf(400.0)
	var hedge = g.new_cbuf(400.0)
	var stone: Color = g._tone["stonewall"]
	var wood: Color = g._tone["woodfence"]
	var white: Color = g._tone["mark"]
	var dark: Color = g._tone["tyre"]
	for ln: Dictionary in data.get("lines", []):
		var pts: Array = ln["pts"]
		var kind := String(ln["kind"])
		for j in range(pts.size() - 1):
			var a := _v2(pts[j])
			var e := _v2(pts[j + 1])
			match kind:
				"stone_wall":
					_wall(b, a, e, float(ln.get("h", 0.8)), 0.4, stone, 0.0, true)
				"wood_fence":
					_slats(b, a, e, float(ln.get("base", 0.8)), float(ln.get("h", 1.1)), wood)
				"loop_fence":
					_pickets(b, a, e, float(ln.get("h", 0.9)), white)
				"hedge":
					g._furn._hedge_line(hedge, a, e)
					_solid(a, e, 0.45)
	for pr: Dictionary in data.get("props", []):
		var at := _v2(pr["at"])
		var d := _v2(pr.get("dir", [1, 0])).normalized()
		match String(pr["kind"]):
			"bin":
				_bin(b, at, dark)
			"hoop_railing":
				_hoop(b, at, d, white)
	g._add_mesh(b, g._vc_mat(), true, 260.0)
	g._add_mesh(hedge, g._surface("bush"), true, 260.0)

## posts along a line so the walker and the car cannot go through it
func _solid(a: Vector2, e: Vector2, r: float) -> void:
	var L := a.distance_to(e)
	var n := maxi(1, int(L / (r * 1.6)))
	for i in range(n + 1):
		g._add_post(a.lerp(e, float(i) / n), r)

## a box standing on the ground from a to e, `t` thick, from `y0` up to `y0 + h`
func _wall(b, a: Vector2, e: Vector2, h: float, t: float, col: Color, y0 := 0.0, solid := false) -> void:
	var L := a.distance_to(e)
	if L < 0.05:
		return
	var d := (e - a) / L
	var mid := (a + e) * 0.5
	var gy := minf(g._h(a), g._h(e))
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	g._furn._box(b, Vector3(mid.x, gy + y0 + h * 0.5 - 0.15, mid.y), Vector3(L, h + 0.3, t), col, bs)
	if solid:
		_solid(a, e, t * 0.6 + 0.05)

## a fence of horizontal wooden boards with gaps between, on posts, from `base` up `h`
func _slats(b, a: Vector2, e: Vector2, base: float, h: float, col: Color) -> void:
	var L := a.distance_to(e)
	var d := (e - a) / L
	var gy := minf(g._h(a), g._h(e))
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	var mid := (a + e) * 0.5
	var y := base
	var k := 0
	while y + 0.12 <= base + h + 0.01:
		var c := col.darkened(0.08 * float(k % 3))
		g._furn._box(b, Vector3(mid.x, gy + y + 0.06, mid.y), Vector3(L, 0.12, 0.03), c, bs)
		y += 0.145
		k += 1
	var s := 0.0
	while s <= L:
		var p := a + d * s
		g._furn._box(b, Vector3(p.x, gy + base + h * 0.5, p.y), Vector3(0.08, h, 0.08), col.darkened(0.2), bs)
		s += 1.8
	_solid(a, e, 0.2)

## a low white fence of round-topped pickets between two rails
func _pickets(b, a: Vector2, e: Vector2, h: float, col: Color) -> void:
	var L := a.distance_to(e)
	var d := (e - a) / L
	var gy := minf(g._h(a), g._h(e))
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	var mid := (a + e) * 0.5
	for ry: float in [0.15, h - 0.12]:
		g._furn._box(b, Vector3(mid.x, gy + ry, mid.y), Vector3(L, 0.04, 0.04), col, bs)
	var s := 0.06
	while s < L:
		var p := a + d * s
		g._furn._box(b, Vector3(p.x, gy + h * 0.5, p.y), Vector3(0.025, h, 0.025), col, bs)
		# the loop over the top: two short bars leaning in, like the bent tube of the real one
		g._furn._box(b, Vector3(p.x + d.x * 0.045, gy + h + 0.035, p.y + d.y * 0.045), Vector3(0.09, 0.025, 0.025), col, bs)
		s += 0.11
	_solid(a, e, 0.2)

## a litter bin: a black slotted cylinder on a short post
func _bin(b, at: Vector2, col: Color) -> void:
	var gy: float = g._h(at)
	g._furn._tube(b, Vector3(at.x, gy, at.y), Vector3(at.x, gy + 1.0, at.y), 0.26, 0.26, col, 10)
	g._furn._box(b, Vector3(at.x, gy + 1.0, at.y), Vector3(0.5, 0.04, 0.5), col.darkened(0.2))
	g._add_post(at, 0.3)

## a white tubular railing: a straight top rail on two posts with a hoop curving under it,
## `d` the way it runs
func _hoop(b, at: Vector2, d: Vector2, col: Color) -> void:
	var gy: float = g._h(at)
	var half := 0.9
	var A := Vector3(at.x - d.x * half, gy, at.y - d.y * half)
	var E := Vector3(at.x + d.x * half, gy, at.y + d.y * half)
	for p: Vector3 in [A, E]:
		g._furn._tube(b, p, p + Vector3.UP * 1.0, 0.03, 0.03, col, 6)
	g._furn._tube(b, A + Vector3.UP * 1.0, E + Vector3.UP * 1.0, 0.03, 0.03, col, 6)
	var steps := 8
	var prev := A + Vector3.UP * 0.95
	for i in range(1, steps + 1):
		var f := float(i) / steps
		var q := A.lerp(E, f) + Vector3.UP * (0.95 - 0.55 * sin(f * PI))
		g._furn._tube(b, prev, q, 0.025, 0.025, col, 5)
		prev = q
	g._add_post(at, 0.25)
