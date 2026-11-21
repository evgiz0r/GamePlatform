extends RefCounted
## Building sites at work, from a town's own map (the city file's "sites", baked by
## tools/osm_city.py from Tel Aviv's layer of open building files: 511 at work in level 7's
## box). Round each plot a hoarding of printed panels on posts; over a new building of any
## size, or a tall one, a tower crane -- the cranes over Tel Aviv's roofs are half of what
## its skyline looks like from a street. The hoarding is solid (walls the car and people
## bump); the crane's mast is a post.
##
## Set up once (which squares each site's edges and crane are in); built with each square.

const PANEL := 3.0            ## a hoarding panel's length
const HOARD_H := 2.4
const CRANE_AREA := 700.0     ## a new building's plot this big (m2) or more gets a crane, or any tall one's
const CRANE_RANGE := 1500.0   ## cranes are seen from far off: over the roofs from streets away

var g: Node
var _tile_items := {}         ## square -> [["edge", a, b, colour index, site] | ["crane", where, height, jib's angle, seed]]
var count := {}               ## for the tests: sites, panels, cranes

func _init(game: Node) -> void:
	g = game

func setup(data: Dictionary) -> void:
	var k := 1.0 / float(data.get("scale", 10))
	var si := 0
	for st: Dictionary in data.get("sites", []):
		var flat: Array = st["r"]
		var ring := PackedVector2Array()
		for i in range(0, flat.size() - 1, 2):
			ring.append(Vector2(flat[i], flat[i + 1]) * k)
		if ring.size() < 3:
			continue
		si += 1
		count["sites"] = int(count.get("sites", 0)) + 1
		var h := absi(hash(Vector2i(ring[0].round())))
		var col := h % 4
		for i in range(ring.size()):
			var a := ring[i]
			var b := ring[(i + 1) % ring.size()]
			var L := a.distance_to(b)
			if L < 0.3:
				continue
			var n := maxi(1, ceili(L / PANEL))
			for j in range(n):   # (panel by panel into the square each stands in)
				var pa := a.lerp(b, float(j) / n)
				var pb := a.lerp(b, float(j + 1) / n)
				_put((pa + pb) * 0.5, ["edge", pa, pb, col, si])
		var area := absf(_area(ring))
		if int(st.get("new", 0)) == 1 and (area >= CRANE_AREA or int(st.get("hi", 0)) == 1):
			var c := _mid(ring)
			if Geometry2D.is_point_in_polygon(c, ring):
				var tall := 34.0 + float(h % 9) * 2.0 + (22.0 if int(st.get("hi", 0)) == 1 else 0.0)
				_put(c, ["crane", c, tall, float((h / 9) % 360) * PI / 180.0, h])

func _put(p: Vector2, item: Array) -> void:
	var t: Vector2i = g._tile_of(p)
	if not _tile_items.has(t):
		_tile_items[t] = []
	(_tile_items[t] as Array).append(item)

func _area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(ring.size()):
		var p := ring[i]
		var q := ring[(i + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5

func _mid(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	return c / ring.size()

## this square's: the hoardings' panels and posts, and the cranes
func build() -> void:
	var items: Array = _tile_items.get(g._tile, [])
	if items.is_empty():
		return
	var hoard = g.new_cbuf(400.0)
	var cranes = null
	# printed hoardings: white, the developer's blue, green mesh, a dark grey
	var cols: Array = [g._real_col("white"), g._real_col("blue").lerp(g._real_col("white"), 0.15),
		g._tone["fencegreen"], g._tone["tyre"].lerp(g._real_col("white"), 0.25)]
	var metal: Color = g._tone["metal"]
	for it: Array in items:
		if String(it[0]) == "edge":
			var a: Vector2 = it[1]
			var b: Vector2 = it[2]
			var m := (a + b) * 0.5
			# (not across a road -- the plot's outline and OSM's road a metre or two apart --
			# nor through a standing building's wall: the hoarding goes round the plot's open side)
			if g._push_out(m, 0.2, false, false) != Vector2.ZERO:
				continue
			# (the whole panel off the road, its ends too: checked at its middle alone, a
			# panel at an angle to the kerb stood up to 1 m into Stein's asphalt -- city_check)
			var on_road := false
			var steps := maxi(2, ceili(a.distance_to(b) / 0.5))
			for k in range(steps + 1):
				if not g._off_road(a.lerp(b, float(k) / steps), 0.3):
					on_road = true
					break
			if on_road:
				continue
			var L := a.distance_to(b)
			var t := (b - a) / L
			var bs := Basis(Vector3(t.x, 0, t.y), Vector3.UP, Vector3(-t.y, 0, t.x))
			var gy: float = g._h(m)
			var col: Color = cols[int(it[3])]
			g._furn._box(hoard, Vector3(m.x, gy + HOARD_H * 0.5, m.y), Vector3(L, HOARD_H, 0.05), col, bs)
			# a band along the top in the print's darker colour, and a post at the panel's end
			g._furn._box(hoard, Vector3(m.x, gy + HOARD_H - 0.18, m.y), Vector3(L, 0.36, 0.06), col.darkened(0.35), bs)
			g._furn._box(hoard, Vector3(b.x, gy + HOARD_H * 0.5 + 0.05, b.y), Vector3(0.07, HOARD_H + 0.1, 0.07), metal, bs)
			g.add_wall(a, b, 0.05)
			count["panels"] = int(count.get("panels", 0)) + 1
			continue
		if String(it[0]) == "crane":
			if cranes == null:
				cranes = g.new_cbuf(400.0)
			_crane(cranes, it[1], it[2], it[3], it[4])
			g._add_post(it[1], 1.1)
			count["cranes"] = int(count.get("cranes", 0)) + 1
	if not hoard.empty():
		g._add_mesh(hoard, g._vc_mat(), true, 400.0)
	if cranes != null:
		g._add_mesh(cranes, g._vc_mat(), true, CRANE_RANGE)

## a tower crane: a lattice mast, the cab and slewing ring on top, the jib out one way with
## its trolley and hook, the counter-jib the other with its concrete weights, the A-frame
## over them and its ties
func _crane(b, c: Vector2, tall: float, ang: float, seed: int) -> void:
	var gy: float = g._h(c)
	var yel: Color = g._real_col("yellow") if seed % 3 != 0 else g._real_col("white")
	var steel: Color = g._tone["metal"]
	var conc: Color = g._tone["metal"].lerp(g._real_col("white"), 0.4)
	var dir := Vector3(cos(ang), 0, sin(ang))
	var side := Vector3(-dir.z, 0, dir.x)
	var bs := Basis(dir, Vector3.UP, side)
	var base := Vector3(c.x, gy, c.y)
	var hw := 0.8   # the mast's half width
	# the footing, the mast's four chords and its rungs (a lattice read from the street)
	g._furn._box(b, base + Vector3(0, 0.4, 0), Vector3(4.0, 0.8, 4.0), conc, bs)
	for u: float in [-hw, hw]:
		for w: float in [-hw, hw]:
			g._furn._box(b, base + dir * u + side * w + Vector3(0, tall * 0.5, 0), Vector3(0.14, tall, 0.14), yel, bs)
	# a rung round the mast every bay and a diagonal across two of its faces (about a hundred
	# boxes a crane, with the jib: there are over a hundred cranes in Tel Aviv's box)
	var y := 3.5
	var bay := 0
	while y < tall:
		for face in range(4):
			var o := (dir if face < 2 else side) * (hw if face % 2 == 0 else -hw)
			g._furn._box(b, base + o + Vector3(0, y, 0), Vector3(0.08, 0.08, 1.6) if face < 2 else Vector3(1.6, 0.08, 0.08), yel, bs)
		var df := bay % 2   # (the diagonals on two faces, taking turns)
		var o2 := (dir if df == 0 else side) * hw
		g._furn._box(b, base + o2 + Vector3(0, y - 1.75, 0), Vector3(0.06, 3.9, 0.06), yel,
			bs * Basis(Vector3(0, 0, 1) if df == 0 else Vector3(1, 0, 0), 0.43 * (1.0 if bay % 4 < 2 else -1.0)))
		y += 3.5
		bay += 1
	var top := base + Vector3(0, tall, 0)
	g._furn._box(b, top + Vector3(0, 0.5, 0), Vector3(2.2, 1.0, 2.2), steel, bs)                    # slewing ring
	g._furn._box(b, top + dir * 1.4 + side * 1.2 + Vector3(0, 1.6, 0), Vector3(1.6, 1.8, 1.4), g._real_col("white"), bs)   # the cab
	var jib := 38.0 + float(seed % 13)
	var cj := 12.0
	# the jib: a triangular truss, two bottom chords and a top one, rungs every 2 m
	for w: float in [-0.6, 0.6]:
		g._furn._box(b, top + dir * (jib * 0.5) + side * w + Vector3(0, 1.1, 0), Vector3(jib, 0.12, 0.12), yel, bs)
	g._furn._box(b, top + dir * (jib * 0.5) + Vector3(0, 2.2, 0), Vector3(jib, 0.12, 0.12), yel, bs)
	var s := 3.0
	while s < jib:
		g._furn._box(b, top + dir * s + Vector3(0, 1.1, 0), Vector3(0.07, 0.07, 1.2), yel, bs)
		g._furn._box(b, top + dir * s + Vector3(0, 1.65, 0), Vector3(0.06, 1.1, 0.06), yel, bs)
		s += 3.0
	# the counter-jib and its weights
	g._furn._box(b, top - dir * (cj * 0.5) + Vector3(0, 1.2, 0), Vector3(cj, 0.35, 1.6), yel, bs)
	g._furn._box(b, top - dir * (cj - 1.6) + Vector3(0, 0.3, 0), Vector3(2.4, 2.0, 2.0), conc, bs)
	# the A-frame over the mast and the ties down to both ends
	g._furn._box(b, top + Vector3(0, 4.5, 0), Vector3(0.25, 7.0, 0.25), yel, bs)
	var peak := top + Vector3(0, 8.0, 0)
	for end: Vector3 in [top + dir * (jib * 0.62) + Vector3(0, 2.2, 0), top - dir * (cj - 0.5) + Vector3(0, 1.4, 0)]:
		var span := end - peak
		var mid := peak + span * 0.5
		var lb := Basis.looking_at(span.normalized(), Vector3.UP if absf(span.normalized().y) < 0.95 else Vector3.FORWARD)
		g._furn._box(b, mid, Vector3(0.05, 0.05, span.length()), steel, lb)
	# the trolley out along the jib, its cable and the hook block hanging
	var tro := 10.0 + float((seed / 13) % 24)
	var tp := top + dir * tro + Vector3(0, 0.9, 0)
	g._furn._box(b, tp, Vector3(1.2, 0.4, 1.2), steel, bs)
	var drop := 6.0 + float((seed / 7) % int(maxf(tall - 12.0, 7.0)))
	g._furn._box(b, tp - Vector3(0, drop * 0.5, 0), Vector3(0.04, drop, 0.04), steel, bs)
	g._furn._box(b, tp - Vector3(0, drop + 0.3, 0), Vector3(0.4, 0.6, 0.3), g._real_col("red"), bs)
