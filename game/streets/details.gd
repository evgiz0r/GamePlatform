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
##              add: [{pts: [[x, z]...], k, w, name, name_en, o, l, sv}],   ends within 1 m of
##                                                    a baked node join it
##              set: [{k, name, near: [x, z], w, l, kerb, kerb_mid}]}   the baked roads of
##                                                    that kind and name passing within 3 m of
##                                                    `near` get that width, lanes, kerb paint
##                                                    (plain, red_white, blue_white,
##                                                    yellow_black: a whole way, junction to
##                                                    junction) or kerb_mid: the paint along
##                                                    its middle, the red-white corners and
##                                                    bus stops kept (streets.gd _kerb_marks);
##                                                    yard: false for no front gardens (a
##                                                    street of shops OSM calls residential)
##   crossings [[x, z], ...]                         zebras at the road nodes nearest these
##   white_bollards [{near: [x, z], r}]              the bollards by every zebra within r of
##                                                    near are white (the game picks a few)
##   no_parking [{near: [x, z], r}]                  no car parked at the kerb within r of
##                                                    near (a view the film had, kept open)
##   areas     [{k, p: [[x, z]...]}]                 as the city file's areas (plaza, park...)
##   buildings [{near: [x, z], arcade: [[x, z], [x, z]], depth, h}]   the building holding
##                                                    `near` gets an arcade along that line
##   surfaces  [{k, p: [[x, z]...], lift, lay: [x, z], ramps: [[[x, z], [x, z]]...]}]   paving
##                                                    laid over whatever is there, `lift` m up
##                                                    (0.14: level with the pavement), in a
##                                                    ground tone (slabs, pavers_dark...),
##                                                    slabs' joints along `lay`; each ramp
##                                                    rises from nothing at its first point
##                                                    to `lift` at its second (a raised
##                                                    crossing's slopes)
##   lines     [{kind, pts: [[x, z]...], h, base}]   stone_wall, wood_fence, loop_fence, hedge,
##                                                    shrubs (tall planting h high: leafy masses),
##                                                    shopfront (glazed bays h high on a
##                                                    block's face, facing `face`; signs: a
##                                                    name per bay, "" for none; panels: the
##                                                    bays with yellow panels in the window)
##   props     [{kind, at: [x, z], dir: [x, z]}]     bin, hoop_railing, bollard, twin_poles
##                                                    (dir: the line through them), barrier
##                                                    (dir: the way the boom goes, len),
##                                                    globe_lamp (h), manhole, motorbike and
##                                                    scooter (dir: the nose; box: a top box),
##                                                    kerb_paint (at: by the kerb of the road
##                                                    nearest; len, pat: red_white...),
##                                                    zebra (dir: along the road, w: how wide
##                                                    the crossing, len: kerb to kerb; laid on
##                                                    the paving there), ring30 (painted on the
##                                                    road, read along dir), zone30_sign (dir:
##                                                    the way it faces), parked_car (in the
##                                                    road by its kerb, nose along dir; body:
##                                                    sedan, hatch, suv, van), booth (a blue
##                                                    pay booth, its face along dir),
##                                                    sign_board (a yellow board on a pole),
##                                                    gatepost (concrete, face along dir; heart:
##                                                    a red graffiti heart on that face).
##                                                    Anything on a lifted surface stands on it.
##   trees     [[x, z], ...]                         more trees for the city's own builder
##   walks     {id: {name, points: [[t, x, z]...],   two points at one spot: it waits there
##              looks: [[from, to, degrees]...],     the head turned off the way it walks
##                                                    (+ right), to see the traffic coming
##              zebras: [[from, to, [x, z], [x, z]]...],  waiting at a crossing or on it:
##                                                    cars stop for it (kerb to kerb)
##              cars: [[t, [x, z], [dx, dz]]...],    a car sent down the street nearest the
##                                                    spot at second t, that way (traffic.gd)
##              people: [{at, to, t: [from, to], face, who, tall, stay}]}}   who the film
##                                                    shows: standing at `at` facing `face`, or
##                                                    walking `at` to `to` between those seconds
##                                                    (there only then, unless `stay`: then it
##                                                    stands where it got to)

var g: Node                    ## the streets game
var data := {}
const KERB_PAINT := ["plain", "red_white", "blue_white", "yellow_black"]   ## (the kerb shader's order)
const PAVE_OVER := 0.035               ## lifted paving stands this much over its height (see _paving)

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
	for st: Dictionary in ed.get("set", []):
		var near := _v2(st["near"])
		var hit := 0
		for r: Dictionary in city["roads"]:
			if String(r.get("k", "")) == String(st.get("k", "")) and String(r.get("name", "")) == String(st.get("name", "")) \
					and _passes(r, nodes, near, sc):
				for key: String in ["w", "l"]:
					if st.has(key):
						r[key] = st[key]
				if st.has("kerb"):
					r["kerb"] = KERB_PAINT.find(String(st["kerb"]))
				if st.has("kerb_mid"):
					r["kerb_mid"] = KERB_PAINT.find(String(st["kerb_mid"]))
				if st.has("yard"):
					r["yard"] = bool(st["yard"])
				hit += 1
		if hit == 0:
			Probe.note("details: no %s road '%s' at %s to set" % [st.get("k", ""), st.get("name", ""), near])
	for ad: Dictionary in ed.get("add", []):
		var ids: Array = []
		for p: Array in ad["pts"]:
			ids.append(_node_at(nodes, _v2(p), sc))
		var r := {"n": ids, "k": ad["k"], "w": float(ad.get("w", 6.0))}
		for key: String in ["name", "name_en", "o", "l", "sv"]:
			if ad.has(key):
				r[key] = ad[key]
		city["roads"].append(r)
	for np: Dictionary in data.get("no_parking", []):
		g._no_park.append([_v2(np["near"]), float(np.get("r", 8.0))])
	for wb: Dictionary in data.get("white_bollards", []):
		var c := _v2(wb["near"])
		var r := float(wb.get("r", 10.0))
		for i in range(nodes.size() / 2):
			if Vector2(nodes[i * 2], nodes[i * 2 + 1]).distance_to(c * sc) <= r * sc:
				g._white_bollards[i] = true
	var cross: Array = city.get("crossings", [])
	for p: Array in data.get("crossings", []):
		cross.append(_nearest_node(nodes, _v2(p), sc))
	city["crossings"] = cross
	for bd: Dictionary in data.get("buildings", []):
		if bd.has("arcade"):
			_arcade(city, bd, sc)
	var trees: Array = city.get("trees", [])
	for t: Array in data.get("trees", []):
		trees.append(roundi(float(t[0]) * sc))
		trees.append(roundi(float(t[1]) * sc))
	city["trees"] = trees
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

## An arcade: the building holding `near` loses a strip `depth` deep along the line `arcade`
## (two points on its street face) to its ground floor. OpenStreetMap traces a block from
## above, so its outline runs out to the upper floors; under them the shops stand back and
## the pavement goes on between columns. Done as data, the game's own way: the strip becomes
## a building of its own raised `h` (the game puts a raised building on columns and lets you
## under it), the rest stands back from the street. Both outlines start at the same corner,
## and a building's colour, windows and guessed height all come from its first corner, so
## the two read as one block.
func _arcade(city: Dictionary, ed: Dictionary, sc: float) -> void:
	var near := _v2(ed["near"])
	var all: Array = city["buildings"]
	for bd: Dictionary in all:
		var ring := PackedVector2Array()
		var flat: Array = bd["p"]
		for i in range(0, flat.size(), 2):
			ring.append(Vector2(flat[i], flat[i + 1]) / sc)
		if not Geometry2D.is_point_in_polygon(near, ring):
			continue
		var a := _v2(ed["arcade"][0])
		var e := _v2(ed["arcade"][1])
		var d := (e - a).normalized()
		var inn := Vector2(-d.y, d.x)
		if inn.dot(near - a) < 0.0:
			inn = -inn
		var depth := float(ed.get("depth", 3.0))
		# the band from well outside the face to `depth` inside it, long enough for any block
		var band := PackedVector2Array([a - d * 500.0 - inn * 20.0, e + d * 500.0 - inn * 20.0,
			e + d * 500.0 + inn * depth, a - d * 500.0 + inn * depth])
		var strip := _biggest(Geometry2D.intersect_polygons(ring, band))
		var rest := _biggest(Geometry2D.clip_polygons(ring, band))
		if strip.size() < 3 or rest.size() < 3:
			Probe.note("details: no arcade cut from the building at %s" % near)
			return
		var q := a + inn * depth   # a corner the two share, on the cut
		var top := bd.duplicate()
		top.erase("addr")
		top.erase("name")
		top["b"] = float(ed.get("h", 3.4))
		top["p"] = _flat_from(strip, q, sc)
		bd["p"] = _flat_from(rest, q, sc)
		bd["shops"] = 1   # shops behind the columns: never itself open on columns
		var p0 := Vector2(top["p"][0], top["p"][1]) / sc
		if p0.distance_to(Vector2(bd["p"][0], bd["p"][1]) / sc) > 0.5:   # (both rounded to the same)
			Probe.note("details: the arcade's two parts start apart at %s" % near)
		bd["p"][0] = top["p"][0]
		bd["p"][1] = top["p"][1]
		all.append(top)
		return
	Probe.note("details: no building at %s for an arcade" % near)

func _biggest(polys: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var ba := 0.0
	for p: PackedVector2Array in polys:
		if Geometry2D.is_polygon_clockwise(p) and polys.size() > 1:
			continue   # (a hole)
		var area := 0.0
		for i in range(p.size()):
			area += p[i].cross(p[(i + 1) % p.size()])
		if absf(area) > ba:
			ba = absf(area)
			best = p
	return best

## an outline as the city file keeps it (decimetres, flat), starting at its corner nearest q
func _flat_from(ring: PackedVector2Array, q: Vector2, sc: float) -> Array:
	var first := 0
	for i in range(ring.size()):
		if ring[i].distance_to(q) < ring[first].distance_to(q):
			first = i
	var flat: Array = []
	for k in range(ring.size()):
		var p := ring[(first + k) % ring.size()]
		flat.append(roundi(p.x * sc))
		flat.append(roundi(p.y * sc))
	return flat

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
	# batched like a square of the city, so a ground tone gets the ground's own shader
	g._batching = true
	var b = g.new_cbuf(400.0)
	var hedge = g.new_cbuf(400.0)
	var stone: Color = g._tone["stonewall"]
	var wood: Color = g._tone["woodfence"]
	var white: Color = g._tone["mark"]
	var dark: Color = g._tone["tyre"]
	var shrubs: Array = []
	var shrub_cols: Array = []
	var glass = g.new_cbuf(400.0)
	for sf: Dictionary in data.get("surfaces", []):
		_paving(sf)
	for ln: Dictionary in data.get("lines", []):
		var pts: Array = ln["pts"]
		var kind := String(ln["kind"])
		for j in range(pts.size() - 1):
			var a := _v2(pts[j])
			var e := _v2(pts[j + 1])
			match kind:
				"stone_wall":
					_wall(b, a, e, float(ln.get("h", 0.8)), 0.36, stone.lerp(g._greyed(stone, 1.0), 0.8).darkened(0.25), 0.0, true)
					_stones(b, a, e, float(ln.get("h", 0.8)), 0.4, g._greyed(stone, 0.85).darkened(0.12))
				"wood_fence":
					_slats(b, a, e, float(ln.get("base", 0.8)), float(ln.get("h", 1.1)), wood)
				"loop_fence":
					_pickets(b, a, e, float(ln.get("h", 0.9)), white)
				"hedge":
					g._furn._hedge_line(hedge, a, e)
					_solid(a, e, 0.45)
				"shrubs":
					_shrubs(shrubs, shrub_cols, a, e, float(ln.get("h", 2.6)))
				"shopfront":
					_shopfront(b, glass, a, e, float(ln.get("h", 3.2)), _v2(ln.get("face", [0, 0])),
						ln.get("signs", []), ln.get("panels", []))
	var bikes: Array = []
	var bike_cols: Array = []

	var scooters: Array = []
	var scooter_cols: Array = []
	var boxes: Array = []
	var cars := {}   ## kind -> [transforms, paints]
	# what bikes come in: white, black, silver, a dull blue; never the palette's neon
	var paint := [white, g._tone["tyre"].lightened(0.1), g._tone["rim"], g._natural(g._tone["signblue"], 0.45), white, g._tone["cartrim"]]
	var k := 0
	for pr: Dictionary in data.get("props", []):
		var at := _v2(pr["at"])
		var d := _v2(pr.get("dir", [1, 0])).normalized()
		var y: float = maxf(g._walk_y(at), g._h(at) + _lift_at(at))   # (on a pavement, or on paving of ours)
		k += 1
		match String(pr["kind"]):
			"bin":
				_bin(b, at, y, dark)
			"hoop_railing":
				_hoop(b, at, y, d, white)
			"bollard":
				_bollard(b, at, y, k)
			"twin_poles":
				_twin_poles(b, at, y, d)
			"barrier":
				_barrier(b, at, y, d, float(pr.get("len", 4.0)))
			"globe_lamp":
				_globe_lamp(b, at, y, float(pr.get("h", 2.7)))
			"gatepost":
				_gatepost(b, at, y, d, bool(pr.get("heart", false)))
			"booth":
				_booth(b, at, y, d)
			"sign_board":
				_sign_board(b, at, y, d)
			"parked_car":
				var kind := String(pr.get("body", ["sedan", "hatch", "suv"][k % 3]))
				if not cars.has(kind):
					cars[kind] = [[], []]
				var paints: Array = g._car_paints()
				var kc: Dictionary = (g.get_script() as GDScript).get_script_constant_map()
				var f := d.rotated(0.03 * (_rnd(k, 3) - 0.5))
				(cars[kind][0] as Array).append(Transform3D(Basis(Vector3.UP, atan2(f.x, f.y)), g._g3(at, float(kc["Y_ROAD"]))))
				(cars[kind][1] as Array).append(paints[(k * 5) % paints.size()])
				g._add_post(at + f * 1.25, 0.85)
				g._add_post(at - f * 1.25, 0.85)
			"zebra":
				_zebra(b, at, y, d, float(pr.get("w", 3.0)), float(pr.get("len", 8.0)))
			"ring30":
				_ring30(b, at, d)
			"zone30_sign":
				_zone30_sign(b, at, y, d)
			"kerb_paint":
				_kerb_paint(b, at, float(pr.get("len", 10.0)), KERB_PAINT.find(String(pr.get("pat", "red_white"))))
			"manhole":
				g._furn._tube(b, Vector3(at.x, y, at.y), Vector3(at.x, y + 0.012, at.y), 0.33, 0.33, g._tone["metal"].darkened(0.3), 14)
			"motorbike", "scooter":
				var xf := Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(at.x, y, at.y))
				var col: Color = paint[(k * 7) % paint.size()]
				if String(pr["kind"]) == "scooter":
					scooters.append(xf)
					scooter_cols.append(col)
				else:
					bikes.append(xf)
					bike_cols.append(col)
				if pr.get("box", false):
					boxes.append(xf)
				g._add_post(at, 0.45)
	g._add_mesh(b, g._vc_mat(), true, 260.0)
	g._add_mesh(hedge, g._surface("bush"), true, 260.0)
	g._add_mesh(glass, _window_glass(), false, 220.0)
	if not bikes.is_empty():
		g._chunked(_moto_kit(), bikes, 170.0, bike_cols, null, true)
	if not scooters.is_empty():
		g._chunked(g._furn._scooter_kit(), scooters, 170.0, scooter_cols, null, true)
	if not boxes.is_empty():
		g._chunked(_box_kit(), boxes, 170.0, [], null, true)
	for kind: String in cars:
		g._chunked(g._parked_mesh(kind), cars[kind][0], 140.0, cars[kind][1], null, true, true)
	if not shrubs.is_empty() and g._tree_meshes.has("crown"):
		g._chunked(g._tree_meshes["crown"], shrubs, 260.0, shrub_cols, null, false)
	await g._flush_batches()

## ---- paving -----------------------------------------------------------------------------------

## The highest lifted surface over p (0 off them all): what stands there stands on it
func _lift_at(p: Vector2) -> float:
	var best := 0.0
	for sf: Dictionary in data.get("surfaces", []):
		var lift := float(sf.get("lift", 0.0))
		if lift > best and Geometry2D.is_point_in_polygon(p, _ring(sf["p"])):
			best = lift
	return best + PAVE_OVER + (0.07 if g._hnx > 0 else 0.0) if best > 0.0 else 0.0

func _ring(pts: Array) -> PackedVector2Array:
	var r := PackedVector2Array()
	for q: Array in pts:
		r.append(_v2(q))
	return r

## A surface in one of the ground's tones, `lift` above the ground, cut in metre squares so
## it follows the ground's rise and fall, with a skirt down to the ground all round. Drawn
## here rather than as a city area: an area lies under the pavement, this lies level with
## it. The tone goes in the vertex colour the way the city's batches put it there (its
## index in red), with the way slabs are laid in the spare green.
func _paving(sf: Dictionary) -> void:
	var ring := _ring(sf["p"])
	var tone := String(sf.get("k", "slabs"))
	var how: Array = g._merge_as(g._surface(tone))
	if how.is_empty():
		return
	var lay := _v2(sf.get("lay", [1, 0]))
	var col: Color = how[0]
	col.g = fposmod(atan2(lay.y, lay.x), PI) / PI
	# 3.5 cm over its nominal height: the city's pavement runs straight from one end of a
	# street's piece to the other, so where the ground dips between them it stands above the
	# ground's own line, and a few millimetres' margin left it drawn over this paving
	var lift := float(sf.get("lift", 0.14)) + PAVE_OVER
	var ramps: Array = sf.get("ramps", [])
	var buf = g.new_buf()
	var box := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		box = box.expand(p)
	var x := floorf(box.position.x)
	while x < box.end.x:
		var z := floorf(box.position.y)
		while z < box.end.y:
			var sq := PackedVector2Array([Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(ring, sq):
				var idx := Geometry2D.triangulate_polygon(piece)
				for i in range(0, idx.size(), 3):
					var v0: Vector2 = piece[idx[i]]
					var v1: Vector2 = piece[idx[i + 1]]
					var v2: Vector2 = piece[idx[i + 2]]
					buf.tri(_up(v0, _ramped(v0, lift, ramps)), _up(v1, _ramped(v1, lift, ramps)),
						_up(v2, _ramped(v2, lift, ramps)), Vector3.UP, col)
			z += 1.0
		x += 1.0
	for i in range(ring.size()):
		var a := ring[i]
		var e := ring[(i + 1) % ring.size()]
		var out := (e - a).orthogonal().normalized()
		if Geometry2D.is_point_in_polygon((a + e) * 0.5 + out * 0.05, ring):
			out = -out
		var n := Vector3(out.x, 0, out.y)
		var la := _ramped(a, lift, ramps)
		var le := _ramped(e, lift, ramps)
		buf.tri(_up(a, la), _up(e, le), _up(e, -0.1), n, col)
		buf.tri(_up(a, la), _up(e, -0.1), _up(a, -0.1), n, col)
	g._retint_tone_mat()   # (a tone new to the city joins its table)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = buf.v
	arr[Mesh.ARRAY_NORMAL] = buf.n
	arr[Mesh.ARRAY_COLOR] = buf.c
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, g._tone_mat())
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.visibility_range_end = 400.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.world.add_child(mi)

## the paving's height at p: `lift`, less where a ramp is still climbing to it
func _ramped(p: Vector2, lift: float, ramps: Array) -> float:
	var f := 1.0
	for r: Array in ramps:
		var a := _v2(r[0])
		var e := _v2(r[1])
		var L := a.distance_to(e)
		f = minf(f, clampf((p - a).dot((e - a) / L) / L, 0.0, 1.0))
	return lift * f

## (the game's own lift: on a hilly map everything paved stands 7 cm higher, its pavements too)
func _up(p: Vector2, lift: float) -> Vector3:
	return g._g3(p, lift)

## ---- things standing ------------------------------------------------------------------------

## A stretch of kerb painted in stripes, `len` long, centred by `at`, on the kerb of the
## road nearest it on at's side: laid over the city's kerb a shade bigger, in the kerb
## shader's own colours, for paint that stops short of a whole street (a road's kerb paint
## is one pattern from junction to junction: "set" in roads gives a whole way's)
func _kerb_paint(b, at: Vector2, L: float, pat: int) -> void:
	var hit: Dictionary = g._nearest_seg(at, 15.0, true, true)
	if hit.is_empty() or pat <= 0:
		return
	var r: Dictionary = g._roads[int(hit["road"])]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var d := (pts[sj + 1] - pts[sj]).normalized()
	var q: Vector2 = pts[sj] + d * (at - pts[sj]).dot(d)
	var n := (at - q).normalized()
	var mat: ShaderMaterial = g._kerb_mat
	if mat == null:
		return   # (no kerbs built yet)
	var kc: Dictionary = (g.get_script() as GDScript).get_script_constant_map()
	var kw: float = kc["KERB_W"]
	var kh: float = kc["KERB_H"]
	var white: Color = mat.get_shader_parameter("white")
	var paint: Color = mat.get_shader_parameter(["", "red", "blue", "yellow"][pat])
	if pat == 3:
		white = mat.get_shader_parameter("black")
	var lift: float = 0.07 if g._hnx > 0 else 0.0
	var steps := maxi(2, int(round(L)))
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	for i in range(steps):
		var c: Vector2 = q + n * (float(r["w"]) * 0.5 + kw * 0.5) + d * (-L * 0.5 + (float(i) + 0.5) * L / steps)
		var gy: float = g._h(c) + lift
		g._furn._box(b, Vector3(c.x, gy + kh * 0.5 + 0.004, c.y), Vector3(L / steps + 0.002, kh + 0.016, kw + 0.02),
			paint if i % 2 == 0 else white, bs)

## A zebra laid on raised paving (a raised crossing: the stripes are on the table, not the
## asphalt): stripes half a metre wide with half-metre gaps, `w` long along the road (`d`),
## across it kerb to kerb (`len`), a little worn
func _zebra(b, at: Vector2, y: float, d: Vector2, w: float, L: float) -> void:
	var o := Vector2(-d.y, d.x)
	var paint: Color = g._tone["mark"].lerp(g._tone["kerb"], 0.15)
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	var x := -L * 0.5 + 0.25
	while x < L * 0.5 - 0.2:
		var c := at + o * (x + 0.25)
		g._furn._box(b, Vector3(c.x, y + 0.004, c.y), Vector3(w, 0.008, 0.5), paint, bs)
		x += 1.0

## A segment of paint or of a sign's lettering from A to B, `wide` across, `thick` through:
## a flat box whose length runs A to B and whose thickness runs along `nrm`
func _stroke(b, A: Vector3, B: Vector3, nrm: Vector3, wide: float, thick: float, col: Color) -> void:
	var xa := (B - A).normalized()
	var za := xa.cross(nrm).normalized()
	g._furn._box(b, (A + B) * 0.5, Vector3(A.distance_to(B) + wide * 0.5, thick, wide), col, Basis(xa, nrm, za))

## the digits 3 and 0 as seven-segment strokes, `h` high, `right` and `up` the two ways
## across the surface they are on (up: the way they read)
func _thirty(b, c: Vector3, right: Vector3, up: Vector3, h: float, nrm: Vector3, wide: float, col: Color) -> void:
	var w := h * 0.5
	for k in range(2):
		var o := c + right * ((float(k) - 0.5) * w * 1.5)
		var P := func(x: float, yy: float) -> Vector3: return o + right * ((x - 0.5) * w) + up * ((yy - 0.5) * h)
		var segs: Array = [[Vector2(0, 1), Vector2(1, 1)], [Vector2(1, 1), Vector2(1, 0.5)], [Vector2(1, 0.5), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(1, 0)]]
		if k == 0:
			segs.append([Vector2(0.2, 0.5), Vector2(1, 0.5)])   # 3: the middle bar
		else:
			segs.append_array([[Vector2(0, 1), Vector2(0, 0.5)], [Vector2(0, 0.5), Vector2(0, 0)]])   # 0: the left side
		for sg: Array in segs:
			_stroke(b, P.call(sg[0].x, sg[0].y), P.call(sg[1].x, sg[1].y), nrm, wide, 0.006, col)

## a ring of strokes, radius r, on the surface with normal `nrm`
func _round(b, c: Vector3, right: Vector3, up: Vector3, r: float, nrm: Vector3, wide: float, col: Color) -> void:
	var n := 28
	for i in range(n):
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		_stroke(b, c + (right * cos(a0) + up * sin(a0)) * r, c + (right * cos(a1) + up * sin(a1)) * r, nrm, wide, 0.006, col)

## "30" in a red ring painted on the road, read by a driver going along `d` (a 30 zone's
## entrance), a little faded
func _ring30(b, at: Vector2, d: Vector2) -> void:
	var kc: Dictionary = (g.get_script() as GDScript).get_script_constant_map()
	var c: Vector3 = g._g3(at, float(kc["Y_MARK"]) + 0.004)
	var up := Vector3(d.x, 0, d.y)
	var right := Vector3(-d.y, 0, d.x) * -1.0   # (the driver's right, looking along d)
	var red: Color = (g._kerb_mat.get_shader_parameter("red") if g._kerb_mat != null else g._tone["signred"])
	_round(b, c, right, up, 1.25, Vector3.UP, 0.18, red.lerp(g._tone["asphalt"], 0.25))
	_thirty(b, c, right, up, 1.2, Vector3.UP, 0.16, g._tone["mark"].lerp(g._tone["asphalt"], 0.2))

## The sign at a 30 zone's entrance: a white board on a post, a red-ringed 30 on it (the
## word for zone above it left out), facing `d`
func _zone30_sign(b, at: Vector2, y: float, d: Vector2) -> void:
	var p := Vector3(at.x, y, at.y)
	var grey: Color = g._tone["pole"]
	g._furn._tube(b, p, p + Vector3.UP * 2.6, 0.035, 0.035, grey, 6)
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x) + PI * 0.5)
	var face := p + Vector3.UP * 2.15 + Vector3(d.x, 0, d.y) * 0.05
	g._furn._box(b, face, Vector3(0.6, 0.85, 0.03), g._tone["mark"], bs)
	var nrm := Vector3(d.x, 0, d.y)
	var right := Vector3(-d.y, 0, d.x)
	var c := face + nrm * 0.02 - Vector3.UP * 0.1
	var red: Color = (g._kerb_mat.get_shader_parameter("red") if g._kerb_mat != null else g._tone["signred"])
	_round(b, c, right, Vector3.UP, 0.22, nrm, 0.05, red)
	_thirty(b, c, right, Vector3.UP, 0.17, nrm, 0.03, g._tone["tyre"])
	g._add_post(at, 0.1)

## a square concrete gatepost a little taller than a man, its face along `d`; `heart`: a red
## heart sprayed on that face, a hand across
func _gatepost(b, at: Vector2, y: float, d: Vector2, heart: bool) -> void:
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x) + PI * 0.5)
	var conc: Color = g._tone["concrete"]
	g._furn._box(b, Vector3(at.x, y + 0.85, at.y), Vector3(0.42, 1.7, 0.42), conc, bs)
	g._furn._box(b, Vector3(at.x, y + 1.73, at.y), Vector3(0.48, 0.06, 0.48), conc.darkened(0.1), bs)
	if heart:
		var nrm := Vector3(d.x, 0, d.y)
		var right := Vector3(-d.y, 0, d.x)
		var c := Vector3(at.x, y + 1.05, at.y) + nrm * 0.215
		var red: Color = (g._kerb_mat.get_shader_parameter("red") if g._kerb_mat != null else g._tone["signred"])
		var prev := Vector3.ZERO
		for i in range(29):
			var t := TAU * float(i) / 28.0
			var hx := 16.0 * pow(sin(t), 3)
			var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
			var q := c + right * hx * 0.0065 + Vector3.UP * hy * 0.0065
			if i > 0:
				_stroke(b, prev, q, nrm, 0.022, 0.004, red)
			prev = q
	g._add_post(at, 0.3)

## a parking pay booth: a blue cabinet a little taller than a man, a dark panel and a slot on
## its face (`d` the way it faces), a grey cap
func _booth(b, at: Vector2, y: float, d: Vector2) -> void:
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x) + PI * 0.5)
	var blue: Color = g._natural(g._tone["signblue"], 0.7)
	g._furn._box(b, Vector3(at.x, y + 0.95, at.y), Vector3(0.75, 1.9, 0.55), blue, bs)
	g._furn._box(b, Vector3(at.x, y + 1.93, at.y), Vector3(0.82, 0.08, 0.62), g._tone["concrete"], bs)
	var f := at + d * 0.28
	g._furn._box(b, Vector3(f.x, y + 1.4, f.y), Vector3(0.42, 0.3, 0.02), g._tone["tyre"], bs)
	g._furn._box(b, Vector3(f.x, y + 1.05, f.y), Vector3(0.3, 0.05, 0.02), g._tone["mark"], bs)
	g._add_post(at, 0.42)

## a yellow information board (parking times) on a grey pole, facing `d`
func _sign_board(b, at: Vector2, y: float, d: Vector2) -> void:
	var p := Vector3(at.x, y, at.y)
	g._furn._tube(b, p, p + Vector3.UP * 2.5, 0.03, 0.03, g._tone["pole"], 6)
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x) + PI * 0.5)
	var face := p + Vector3.UP * 2.2 + Vector3(d.x, 0, d.y) * 0.04
	g._furn._box(b, face, Vector3(0.45, 0.55, 0.02), g._tone["markyellow"], bs)
	g._add_post(at, 0.08)

## a black steel bollard with a yellow band near the top; now and then one worn grey
func _bollard(b, at: Vector2, y: float, k: int) -> void:
	var body: Color = g._tone["tyre"] if k % 5 != 2 else g._tone["concrete"].darkened(0.25)
	var band: Color = g._tone["markyellow"]
	var p := Vector3(at.x, y, at.y)
	g._furn._tube(b, p, p + Vector3.UP * 0.6, 0.075, 0.075, body, 8)
	g._furn._tube(b, p + Vector3.UP * 0.6, p + Vector3.UP * 0.7, 0.077, 0.077, band, 8)
	g._furn._tube(b, p + Vector3.UP * 0.7, p + Vector3.UP * 0.8, 0.075, 0.075, body, 8)
	g._furn._tube(b, p + Vector3.UP * 0.8, p + Vector3.UP * 0.84, 0.075, 0.04, body, 8)
	g._add_post(at, 0.12)

## A pole transformer on two galvanised poles, braced across near the top, standing on a
## concrete plinth with a couple of rocks against it: the poles `d` apart, 0.8 m
func _twin_poles(b, at: Vector2, y: float, d: Vector2) -> void:
	var steel: Color = g._tone["pole"].lerp(g._tone["concrete"], 0.4)
	var conc: Color = g._tone["concrete"]
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	g._furn._box(b, Vector3(at.x, y + 0.15, at.y), Vector3(1.5, 0.3, 0.75), conc, bs)
	var o := Vector3(-d.y, 0, d.x)
	for r: Vector2 in [Vector2(0.25, 0.55), Vector2(-0.35, 0.6)]:
		var q := Vector3(at.x, y, at.y) + Vector3(d.x, 0, d.y) * r.x + o * r.y
		g._furn._box(b, q + Vector3.UP * 0.15, Vector3(0.45, 0.35, 0.4), conc.darkened(0.2), Basis(Vector3.UP, r.x * 3.0))
	var feet: Array = []
	for sg: float in [-0.4, 0.4]:
		var f := Vector3(at.x + d.x * sg, y + 0.3, at.y + d.y * sg)
		feet.append(f)
		g._furn._box(b, f + Vector3.UP * 5.0, Vector3(0.2, 10.0, 0.2), steel, bs)
	var A: Vector3 = feet[0]
	var E: Vector3 = feet[1]
	for h0: float in [6.2, 7.6]:   # the bracing: crossed straps between the poles
		g._furn._tube(b, A + Vector3.UP * h0, E + Vector3.UP * (h0 + 1.4), 0.03, 0.03, steel, 4)
		g._furn._tube(b, E + Vector3.UP * h0, A + Vector3.UP * (h0 + 1.4), 0.03, 0.03, steel, 4)
	var mid := (A + E) * 0.5
	g._furn._box(b, mid + Vector3.UP * 4.2, Vector3(1.2, 0.1, 0.9), steel.darkened(0.2), bs)   # the platform
	g._furn._box(b, mid + Vector3.UP * 4.85, Vector3(0.8, 1.2, 0.65), g._tone["trafo"], bs)     # the tank
	for sg: float in [-1.0, 1.0]:   # its cooling fins
		g._furn._box(b, mid + Vector3.UP * 4.8 + o * 0.36 * sg, Vector3(0.65, 0.9, 0.06), g._tone["trafo"].darkened(0.15), bs)
	for x: float in [-0.25, 0.0, 0.25]:   # bushings on its lid
		g._furn._tube(b, mid + Vector3.UP * 5.45 + Vector3(d.x, 0, d.y) * x, mid + Vector3.UP * 5.75 + Vector3(d.x, 0, d.y) * x, 0.04, 0.03, g._tone["insulator"], 5)
	g._furn._box(b, mid + Vector3.UP * 9.7, Vector3(2.4, 0.12, 0.12), steel, bs)   # the cross-arm
	for x: float in [-1.0, 0.0, 1.0]:
		g._furn._box(b, mid + Vector3.UP * 9.84 + Vector3(d.x, 0, d.y) * x, Vector3(0.07, 0.18, 0.07), g._tone["insulator"], bs)
	g._add_post(at, 0.75)

## a car park's barrier: a box on a post, the boom red and white out along `d`, resting on
## a little fork at its far end
func _barrier(b, at: Vector2, y: float, d: Vector2, L: float) -> void:
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	var grey: Color = g._tone["concrete"]
	g._furn._box(b, Vector3(at.x, y + 0.5, at.y), Vector3(0.32, 1.0, 0.32), grey, bs)
	var red: Color = g._tone["signred"]
	var white: Color = g._tone["mark"]
	var n := 8
	for i in range(n):
		var c := at + d * (0.2 + (L - 0.2) * (float(i) + 0.5) / n)
		g._furn._box(b, Vector3(c.x, y + 0.92, c.y), Vector3((L - 0.2) / n, 0.08, 0.05), red if i % 2 == 0 else white, bs)
	var f := at + d * L
	g._furn._box(b, Vector3(f.x, y + 0.42, f.y), Vector3(0.06, 0.84, 0.06), grey, bs)
	g._add_post(at, 0.25)

## a garden lamp: a thin dark pole and a white globe on top
func _globe_lamp(b, at: Vector2, y: float, h: float) -> void:
	var p := Vector3(at.x, y, at.y)
	g._furn._tube(b, p, p + Vector3.UP * h, 0.045, 0.035, g._tone["tyre"], 6)
	g._furn._tube(b, p + Vector3.UP * (h - 0.02), p + Vector3.UP * (h + 0.16), 0.13, 0.19, g._tone["lamp"], 8)
	g._furn._tube(b, p + Vector3.UP * (h + 0.16), p + Vector3.UP * (h + 0.34), 0.19, 0.08, g._tone["lamp"], 8)
	g._add_post(at, 0.1)

## a motorbike, nose along local +Z (white where it takes its paint): spoked wheels a good
## deal bigger than a scooter's, the engine low between them, a tank, a seat, an exhaust
func _moto_kit() -> ArrayMesh:
	var b = g.new_buf()
	var body := Color.WHITE
	var dark: Color = g._tone["tyre"]
	var metal: Color = g._tone["rim"]
	for z: float in [-0.7, 0.7]:
		g._furn._tube(b, Vector3(-0.07, 0.3, z), Vector3(0.07, 0.3, z), 0.3, 0.3, dark, 12)
		g._furn._tube(b, Vector3(-0.08, 0.3, z), Vector3(0.08, 0.3, z), 0.12, 0.12, metal, 8)
	g._furn._box(b, Vector3(0, 0.48, 0.0), Vector3(0.3, 0.34, 0.5), metal)                        # the engine
	g._furn._box(b, Vector3(0, 0.85, 0.22), Vector3(0.34, 0.24, 0.5), body)                       # the tank
	g._furn._box(b, Vector3(0, 0.84, -0.32), Vector3(0.27, 0.09, 0.55), dark, Basis(Vector3.RIGHT, 0.08))   # the seat
	g._furn._box(b, Vector3(0, 0.82, -0.72), Vector3(0.2, 0.12, 0.35), body, Basis(Vector3.RIGHT, -0.25))   # the tail
	g._furn._tube(b, Vector3(0, 0.3, 0.7), Vector3(0, 1.0, 0.48), 0.035, 0.035, metal, 5)         # the forks
	g._furn._tube(b, Vector3(-0.38, 1.04, 0.46), Vector3(0.38, 1.04, 0.46), 0.02, 0.02, dark, 4)   # the bars
	g._furn._box(b, Vector3(0, 0.96, 0.62), Vector3(0.2, 0.18, 0.12), dark)                       # the lamp
	g._furn._tube(b, Vector3(0.14, 0.36, -0.15), Vector3(0.17, 0.5, -0.82), 0.05, 0.045, metal, 6) # the exhaust
	g._furn._box(b, Vector3(0, 0.65, -0.95), Vector3(0.24, 0.16, 0.05), g._tone["markyellow"])   # the plate (yellow)
	return g._furn._mesh(b)

## a black top box over a bike's tail
func _box_kit() -> ArrayMesh:
	var b = g.new_buf()
	g._furn._box(b, Vector3(0, 1.12, -0.72), Vector3(0.44, 0.34, 0.4), g._tone["tyre"])
	return g._furn._mesh(b)

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

## A rough stone wall's face, both sides: rows of stones a hand or two high and of uneven
## length, each a shade of its own and standing a little proud or back, over the mortar
## (the plain wall `_wall` lays behind them, `t` a little less thick)
func _stones(b, a: Vector2, e: Vector2, h: float, t: float, col: Color) -> void:
	var L := a.distance_to(e)
	if L < 0.2:
		return
	var d := (e - a) / L
	var o := Vector2(-d.y, d.x)
	var gy := minf(g._h(a), g._h(e))
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	var y := -0.05
	var row := 0
	while y < h - 0.05:
		var rh := 0.19 + 0.09 * _rnd(row, 0)
		rh = minf(rh, h - y)
		var s := -0.25 * _rnd(row, 1)
		var k := 0
		while s < L:
			var sl := 0.28 + 0.34 * _rnd(row, k + 2)
			var s0 := maxf(s, 0.0)
			var s1 := minf(s + sl, L)
			if s1 - s0 > 0.06:
				var mid := a + d * ((s0 + s1) * 0.5)
				var shade := 0.82 + 0.3 * _rnd(row * 31 + k, 7)
				var c := Color(col.r * shade, col.g * shade * (0.98 + 0.04 * _rnd(k, row)), col.b * shade)
				var proud := 0.015 * _rnd(k + 5, row + 3)
				for side: float in [-1.0, 1.0]:
					var q := mid + o * side * (t * 0.5 - 0.02 + proud)
					g._furn._box(b, Vector3(q.x, gy + y + rh * 0.5, q.y), Vector3(s1 - s0 - 0.025, rh - 0.025, 0.06), c, bs)
			s += sl
			k += 1
		y += rh
		row += 1

## Tall planting along a line, `h` high: the trees' leaf-card crowns sat on the ground a
## metre or so apart, each a little different in size and place, broad leaves and small
## ones mixed (the crown's atlas cell is the instance colour's alpha), solid to walk into
func _shrubs(xf: Array, cols: Array, a: Vector2, e: Vector2, h: float) -> void:
	var L := a.distance_to(e)
	var d := (e - a) / maxf(L, 0.01)
	var o := Vector2(-d.y, d.x)
	var n := maxi(1, int(L / 1.05))
	for i in range(n + 1):
		var r1 := _rnd(i, int(a.x * 10.0))
		var r2 := _rnd(i + 17, int(a.y * 10.0))
		var p := a + d * (L * float(i) / n + (r1 - 0.5) * 0.5) + o * (r2 - 0.5) * 0.5
		var hh := h * (0.85 + 0.3 * r2)
		var w := 0.8 + 0.3 * r1
		var gy: float = g._h(p)
		xf.append(Transform3D(Basis(Vector3.UP, r1 * TAU).scaled(Vector3(w, hh * 0.5, w)), Vector3(p.x, gy + hh * 0.48, p.y)))
		cols.append(Color(0.8, 0.92, 0.78, 0.125) if r2 < 0.6 else Color(0.7, 0.88, 0.66, 0.375))
	_solid(a, e, 0.45)

## Shop fronts along a block's face from a to e, `h` high (keep it under an arcade's ceiling:
## that is counted from the lowest ground under the arcade, so on a slope it is lower than
## its nominal height), facing `face`: bays of about three
## metres of lit glass in light aluminium frames, a dark kick plate under them and a sign band
## over them, each shop's band its own colour (the second dark brown: the confectionery's)
func _shopfront(b, glass, a: Vector2, e: Vector2, h: float, face: Vector2, signs: Array, panels: Array) -> void:
	var L := a.distance_to(e)
	var d := (e - a) / L
	var out := face.normalized()
	var gy: float = maxf(g._walk_y((a + e) * 0.5 + out * 0.6), g._h((a + e) * 0.5) + _lift_at((a + e) * 0.5 + out * 0.6))
	var bs := Basis(Vector3.UP, atan2(-d.y, d.x))
	var frame: Color = g._tone["concrete"].lightened(0.3)
	var kick: Color = g._tone["tyre"].lightened(0.12)
	var bands: Array = [g._tone["mark"], g._tone["woodfence"].darkened(0.35), g._natural(g._tone["signblue"], 0.55), g._tone["tyre"]]
	var n := maxi(1, int(round(L / 3.3)))
	for i in range(n):
		var s0 := L * float(i) / n
		var s1 := L * float(i + 1) / n
		var w := s1 - s0
		var mid := a + d * ((s0 + s1) * 0.5) + out * 0.03
		# from the top down: the sign band (its top 55 cm), a transom, the glass to the kick plate
		var top := h - 0.55
		g._furn._box(glass, Vector3(mid.x, gy + (0.35 + top - 0.05) * 0.5, mid.y), Vector3(w - 0.1, top - 0.4, 0.03), Color.WHITE, bs)
		g._furn._box(b, Vector3(mid.x, gy + 0.175, mid.y), Vector3(w, 0.35, 0.07), kick, bs)
		g._furn._box(b, Vector3(mid.x, gy + top - 0.02, mid.y), Vector3(w, 0.1, 0.09), frame, bs)
		var band := mid + out * 0.03
		g._furn._box(b, Vector3(band.x, gy + (top + 0.03 + h) * 0.5, band.y), Vector3(w - 0.04, h - top - 0.03, 0.1), bands[i % bands.size()], bs)
		for x: float in [s0, (s0 + s1) * 0.5, s1]:
			var q := a + d * x + out * 0.05
			g._furn._box(b, Vector3(q.x, gy + top * 0.5, q.y), Vector3(0.12 if x != (s0 + s1) * 0.5 else 0.06, top, 0.08), frame, bs)
		if panels.has(i):   # yellow boards behind the lower glass, either side of the middle
			for f: float in [0.27, 0.73]:
				var q := a + d * (s0 + w * f) + out * 0.045
				g._furn._box(b, Vector3(q.x, gy + 0.85, q.y), Vector3(w * 0.36, 0.9, 0.01), g._tone["markyellow"], bs)
		if i < signs.size() and String(signs[i]) != "":
			var lb := Label3D.new()
			lb.text = String(signs[i])
			lb.font = g._font
			lb.font_size = 64
			lb.pixel_size = 0.0055
			lb.modulate = g._tone["mark"].lerp(g._tone["markyellow"], 0.15)
			lb.outline_size = 0
			var at := band + out * 0.06
			lb.position = Vector3(at.x, gy + (h - 0.55 + h) * 0.5, at.y)
			lb.rotation.y = atan2(out.x, out.y)
			lb.visibility_range_end = 120.0
			g.world.add_child(lb)

## A shop window by day: dark glass that reflects, the shop's light showing faintly through
## (the game's lit shop glass, made for a street at night, glowed as a flat cream wall in
## the arcade's shade)
func _window_glass() -> StandardMaterial3D:
	var m := g._shop_glass().duplicate() as StandardMaterial3D
	m.albedo_color = g._tone["carglass"]
	m.emission_energy_multiplier = 0.2
	m.roughness = 0.08
	m.metallic = 0.5
	return m

## a steady pseudo-random number in [0, 1) for a stone's size and shade, so a wall comes
## out the same every time
func _rnd(i: int, j: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(j) * 78.233) * 43758.5453, 1.0)

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
func _bin(b, at: Vector2, gy: float, col: Color) -> void:
	g._furn._tube(b, Vector3(at.x, gy, at.y), Vector3(at.x, gy + 1.0, at.y), 0.26, 0.26, col, 10)
	g._furn._box(b, Vector3(at.x, gy + 1.0, at.y), Vector3(0.5, 0.04, 0.5), col.darkened(0.2))
	g._add_post(at, 0.3)

## a white tubular railing: a straight top rail on two posts with a hoop curving under it,
## `d` the way it runs
func _hoop(b, at: Vector2, gy: float, d: Vector2, col: Color) -> void:
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
