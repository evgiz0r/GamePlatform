extends RefCounted
## A town's own kindergartens and public shelters (the city file's `places`, baked by
## tools/osm_city.py's places_apply from Givatayim's, Ramat Gan's and Ashdod's maps -- OSM
## had 7 kindergartens where Givatayim's map has 87, and no shelters at all).
##
## A kindergarten: its yard beside the point the map gives (that is its building, or its
## gate): a low green fence of bars, the soft rubber ground, a shade sail on four poles in
## one of four bright colours, and a slide -- the gan's yard is what the street sees of it.
## The street near it gets the school's SLOW (streets.gd's _schools).
## A public shelter: the concrete entrance -- a squat box, its steel door facing the
## nearest street, and the sign over it, "מקלט" in white on blue (Ashdod's and Givatayim's
## maps say which are under the ground: those are a low hut over the stairs down, the rest a
## small concrete building).
##
## Each one is put on the nearest clear ground to its point (not in a building, not on a
## road), up to SEEK m off, or left out. Solid: the fence and the shelter's walls.

const SEEK := 28.0            ## how far from its point a place looks for room (m)
const PAVE_CLEAR := 3.0       ## and this far back from any road's edge, footways too (the pavement)
const YARD := Vector2(7.0, 5.5)
const FENCE_H := 1.1
const SAIL_H := 3.2
const SHELTER := Vector3(3.0, 2.4, 2.6)      ## an above-ground shelter: across, high, deep
const HUT := Vector3(2.4, 2.1, 2.2)          ## the hut over an underground one's stairs

var g: Node
var _tile_items := {}         ## square -> [[kind, where, sub, seed], ...]
var count := {}               ## for tests: kindergartens, shelters, placed, left out
var spots: Array = []         ## for tests: [kind, where it was put] of each one built

func _init(game: Node) -> void:
	g = game

func setup(data: Dictionary) -> void:
	var k := 1.0 / float(data.get("scale", 10))
	var flat: Array = data.get("places", [])
	var kinds: Array = data.get("place_kinds", [])
	for i in range(0, flat.size() - 3, 4):
		var p := Vector2(flat[i], flat[i + 1]) * k
		var kind := String(kinds[int(flat[i + 2])]) if int(flat[i + 2]) < kinds.size() else ""
		if kind == "":
			continue
		count[kind] = int(count.get(kind, 0)) + 1
		var t: Vector2i = g._tile_of(p)
		if not _tile_items.has(t):
			_tile_items[t] = []
		(_tile_items[t] as Array).append([kind, p, int(flat[i + 3]), absi(hash(Vector2i(p.round())))])
		if kind == "kindergarten":
			g._schools.append(p)

## this square's
func build() -> void:
	var items: Array = _tile_items.get(g._tile, [])
	if items.is_empty():
		return
	var b = g.new_cbuf(400.0)
	for it: Array in items:
		var p: Vector2 = it[1]
		if String(it[0]) == "kindergarten":
			_yard(b, p, int(it[3]))
		else:
			_shelter(b, p, int(it[2]), int(it[3]))
	if not b.empty():
		g._add_mesh(b, g._vc_mat(), true, 320.0)

## the street nearest p: [the way along it (unit), the way from p toward it (unit)]
func _street_dir(p: Vector2) -> Array:
	var hit: Dictionary = g._nearest_seg(p, 60.0, true)
	if hit.is_empty():
		return [Vector2.RIGHT, Vector2.DOWN]
	var q: Vector2 = hit["q"]
	var to := (q - p).normalized() if q.distance_to(p) > 0.1 else Vector2.DOWN
	var along := Vector2(-to.y, to.x)
	return [along, to]

## the nearest spot to p, a box `size` (along, across) turned to `along`, standing clear of
## buildings, posts and roads; INF when none within SEEK
func _room(p: Vector2, size: Vector2, along: Vector2) -> Vector2:
	var across := Vector2(-along.y, along.x)
	var r := 0.0
	while r <= SEEK:
		var n := 1 if r == 0.0 else maxi(8, int(r * 1.2))
		for i in range(n):
			var a := TAU * float(i) / n
			var c := p + Vector2(cos(a), sin(a)) * r
			if _clear(c, size, along, across):
				return c
		r += 2.0
	return Vector2.INF

func _clear(c: Vector2, size: Vector2, along: Vector2, across: Vector2) -> bool:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	for u: float in [-1.0, 0.0, 1.0]:
		for v: float in [-1.0, 0.0, 1.0]:
			var q := c + along * hx * u + across * hy * v
			if not g._off_road(q, 0.6):
				return false
			# (off the pavement too: the first shelters stood on it, at the kerb)
			var on: Dictionary = g._nearest_seg(q, PAVE_CLEAR + 4.0, false)
			if not on.is_empty() and float(on["edge"]) < PAVE_CLEAR:
				return false
			if g._push_out(q, 0.5, true, false) != Vector2.ZERO:
				return false
			if _in_bld(q):
				return false
	return true

func _in_bld(q: Vector2) -> bool:
	for bi: int in g._near(g._bld_hash, q, 2.0, g.BLD_CELL):
		if (g._bld_box[bi] as Rect2).has_point(q) and Geometry2D.is_point_in_polygon(q, g._blds[bi]):
			return true
	return false

## a kindergarten's yard
func _yard(b, p: Vector2, seed: int) -> void:
	var sd: Array = _street_dir(p)
	var along: Vector2 = sd[0]
	var c := _room(p, YARD + Vector2(1.0, 1.0), along)
	if c == Vector2.INF:
		count["left_out"] = int(count.get("left_out", 0)) + 1
		return
	count["yards"] = int(count.get("yards", 0)) + 1
	spots.append(["kindergarten", c])
	var across := Vector2(-along.y, along.x)
	var gy: float = g._h(c)
	var bs := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(across.x, 0, across.y))
	var green: Color = g._tone["fencegreen"]
	var metal: Color = g._tone["metal"]
	var sails: Array = [g._real_col("red"), g._real_col("blue"), g._real_col("yellow"), g._real_col("green")]
	var sail: Color = sails[seed % sails.size()].lerp(g._real_col("white"), 0.12)
	var hx := YARD.x * 0.5
	var hy := YARD.y * 0.5
	# the soft ground: rubber tiles, a darker green or a brick red
	var mat: Color = g._tone["grass"].darkened(0.25) if seed % 2 == 0 else g._real_col("red").darkened(0.35)
	g._furn._box(b, Vector3(c.x, gy + 0.03, c.y), Vector3(YARD.x, 0.06, YARD.y), mat, bs)
	# the fence: a rail along the top and bottom, bars every 12 cm read as a band, a post at
	# each corner and every 2 m; a gate's gap in the side toward the street
	var to_street: Vector2 = sd[1]
	var corners := [c - along * hx - across * hy, c + along * hx - across * hy, c + along * hx + across * hy, c - along * hx + across * hy]
	for i in range(4):
		var a: Vector2 = corners[i]
		var e: Vector2 = corners[(i + 1) % 4]
		var mid := (a + e) * 0.5
		var L := a.distance_to(e)
		var t := (e - a) / L
		var sb := Basis(Vector3(t.x, 0, t.y), Vector3.UP, Vector3(-t.y, 0, t.x))
		var gate := (mid - c).normalized().dot(to_street) > 0.7
		var pieces: Array = [[a, e]] if not gate else [[a, mid - t * 0.6], [mid + t * 0.6, e]]
		for pc: Array in pieces:
			var pa: Vector2 = pc[0]
			var pb: Vector2 = pc[1]
			var pm := (pa + pb) * 0.5
			var pl := pa.distance_to(pb)
			var y0: float = g._h(pm)
			g._furn._box(b, Vector3(pm.x, y0 + FENCE_H - 0.03, pm.y), Vector3(pl, 0.05, 0.05), green, sb)
			g._furn._box(b, Vector3(pm.x, y0 + 0.12, pm.y), Vector3(pl, 0.05, 0.05), green, sb)
			g._furn._box(b, Vector3(pm.x, y0 + FENCE_H * 0.5 + 0.05, pm.y), Vector3(pl, FENCE_H - 0.2, 0.025), green.darkened(0.15), sb)
			var n := maxi(1, int(pl / 2.0))
			for k in range(n + 1):
				var q := pa.lerp(pb, float(k) / n)
				g._furn._box(b, Vector3(q.x, g._h(q) + FENCE_H * 0.5, q.y), Vector3(0.06, FENCE_H, 0.06), green, sb)
			g.add_wall(pa, pb, 0.05)
	# the shade sail on four poles, its corners at two heights (tilted, as they hang)
	var inset := 0.4
	var poles := [c - along * (hx - inset) - across * (hy - inset), c + along * (hx - inset) - across * (hy - inset),
		c + along * (hx - inset) + across * (hy - inset), c - along * (hx - inset) + across * (hy - inset)]
	var tops: Array = []
	for i in range(4):
		var q: Vector2 = poles[i]
		var h := SAIL_H + (0.5 if i % 2 == 0 else -0.2)
		g._furn._box(b, Vector3(q.x, gy + h * 0.5, q.y), Vector3(0.09, h, 0.09), metal, bs)
		tops.append(Vector3(q.x, gy + h, q.y))
	var up := Vector3.UP
	b.tri(tops[0], tops[1], tops[2], up, sail)
	b.tri(tops[0], tops[2], tops[3], up, sail)
	b.tri(tops[0], tops[2], tops[1], -up, sail.darkened(0.3))
	b.tri(tops[0], tops[3], tops[2], -up, sail.darkened(0.3))
	# a slide (made with Blender: tools/blender/recipes/slide.py), its tower at one end of the
	# yard and the chute down along it; a spring rider in the other corner
	var cols := {"paint": sails[(seed / 4 + 1) % sails.size()], "paint2": sails[(seed / 4 + 2) % sails.size()],
		"paint3": sails[(seed / 4 + 3) % sails.size()]}
	var sc := c - along * (hx - 1.0) - across * (hy * 0.35)
	_stamp(b, "slide", Transform3D(bs, Vector3(sc.x, gy + 0.06, sc.y)), cols)
	g._add_post(sc, 0.6)
	var rc := c + along * (hx - 1.0) + across * (hy * 0.45)
	var rider_cols := {"paint": cols["paint3"], "paint2": cols["paint"], "paint3": cols["paint2"]}
	_stamp(b, "spring_rider", Transform3D(bs.rotated(Vector3.UP, PI * 0.75), Vector3(rc.x, gy + 0.06, rc.y)), rider_cols)
	g._add_post(rc, 0.35)

## a public shelter's way in
func _shelter(b, p: Vector2, sub: int, seed: int) -> void:
	var sd: Array = _street_dir(p)
	var along: Vector2 = sd[0]
	var to_street: Vector2 = sd[1]
	var size: Vector3 = HUT if sub == 2 else SHELTER
	var c := _room(p, Vector2(size.x + 0.6, size.z + 1.6), along)
	if c == Vector2.INF:
		count["left_out"] = int(count.get("left_out", 0)) + 1
		return
	count["shelters_put"] = int(count.get("shelters_put", 0)) + 1
	spots.append(["shelter", c])
	var gy: float = g._h(c)
	var across := to_street   # (its door faces the street)
	var bs := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(across.x, 0, across.y))
	var conc: Color = g._tone["concrete"] if g._tone.has("concrete") else g._tone["wall"]
	g._furn._box(b, Vector3(c.x, gy + size.y * 0.5, c.y), size, conc, bs)
	# the roof's slab a little over the walls, and the door, steel, grey-green
	g._furn._box(b, Vector3(c.x, gy + size.y + 0.08, c.y), Vector3(size.x + 0.3, 0.16, size.z + 0.3), conc.darkened(0.12), bs)
	var face := c + across * (size.z * 0.5 + 0.02)
	g._furn._box(b, Vector3(face.x, gy + 1.0, face.y), Vector3(1.0, 2.0, 0.06), g._tone["fencegreen"].darkened(0.35), bs)
	# under the ground: the stairs' parapet out in front, a step down to the door
	if sub == 2:
		var st := c + across * (size.z * 0.5 + 0.8)
		for sgn: float in [-1.0, 1.0]:
			var w := st + along * 0.75 * sgn
			g._furn._box(b, Vector3(w.x, gy + 0.45, w.y), Vector3(0.15, 0.9, 1.6), conc, bs)
	# collision: its four walls
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var cs := [c - along * hx - across * hz, c + along * hx - across * hz, c + along * hx + across * hz, c - along * hx + across * hz]
	for i in range(4):
		g.add_wall(cs[i], cs[(i + 1) % 4], 0.1)
	# the sign over the door: white letters on blue
	var plate := face + across * 0.03
	g._furn._box(b, Vector3(plate.x, gy + 2.2 if sub != 2 else gy + 1.9, plate.y), Vector3(1.1, 0.34, 0.03), g._tone["signblue"], bs)
	var lb := Label3D.new()
	lb.text = "מקלט"
	lb.font = g._font
	lb.font_size = 64
	lb.pixel_size = 0.0045
	lb.outline_size = 0
	lb.modulate = g._tone["mark"]
	lb.shaded = true
	lb.double_sided = false
	# (a Label3D reads from its +Z: that out toward the street, its +X up x +Z)
	var out3 := Vector3(across.x, 0.0, across.y)
	lb.transform = Transform3D(Basis(Vector3.UP.cross(out3), Vector3.UP, out3),
		Vector3(plate.x, (gy + 2.2 if sub != 2 else gy + 1.9), plate.y) + out3 * 0.025)
	lb.visibility_range_end = 60.0
	g.world.add_child(lb)

func _role_col(role: String, cols: Dictionary) -> Color:
	if cols.has(role):
		return cols[role]
	match role:
		"metal":
			return g._tone["metal"]
		"wood":
			return g._tone["woodfence"]
		"rubber", "dark":
			return g._real_col("black")
		"white":
			return g._real_col("white")
		"concrete":
			return g._tone["concrete"] if g._tone.has("concrete") else g._tone["wall"]
		"plastic":
			return g._real_col("green")
	return g._real_col("white")

## a model made with Blender (models.gd) into the yard's batch: "paint" roles from `cols`
func _stamp(b, name: String, at: Transform3D, cols: Dictionary) -> void:
	g._models.stamp(b, name, at, func(role: String) -> Color: return _role_col(role, cols))
	count["models"] = int(count.get("models", 0)) + 1
