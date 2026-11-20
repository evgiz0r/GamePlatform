extends RefCounted
## The beaches: the sand (areas of kind "sand" that lie by the sea) with what is on it --
## umbrellas, each with two white plastic chairs facing the water, in a band behind the wet
## sand; a lifeguard's tower on stilts every LIFEGUARD_EVERY metres along the shore; and the
## chairs as seats for the bathers (streets.gd's _bathers, placed like the bench sitters).
## Any town with a coast: the sea is a water area held at its level ("y") whose outline runs
## along the map's edge (the baker's sea polygons close along the box).
##
## Set up once from the city's areas (where everything goes, square by square); built with
## each square (build()), where the spot is checked against the roads and what stands there.

const STEP := 6.5             ## the umbrellas' grid
const BAND := Vector2(16.0, 52.0)   ## umbrellas this far from the water's edge (the wet sand is kept clear)
const FILL := 0.55            ## the share of the grid's places with an umbrella
const LIFEGUARD_AT := 14.0    ## a tower this far up the sand from the water
const LIFEGUARD_EVERY := 230.0

var g: Node
var _tile_items := {}         ## square -> [["umb", where, to the sea, seed] | ["tower", where, to the sea]]
var count := {}               ## for the tests: beaches, umbrellas, towers (and the chairs)

func _init(game: Node) -> void:
	g = game

func setup(data: Dictionary) -> void:
	var seas: Array = []
	for a: Dictionary in data.get("areas", []):
		if String(a["k"]) == "water" and a.has("y") and a.has("_ring") and _on_edge(a["_ring"]):
			seas.append(a["_ring"])
	if seas.is_empty():
		return
	var towers: Array = []
	for a: Dictionary in data.get("areas", []):
		if String(a["k"]) != "sand" or not a.has("_ring"):
			continue
		var ring: PackedVector2Array = a["_ring"]
		if ring.size() < 3:
			continue
		var box := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			box = box.expand(p)
		# the sea's shore near this sand, as segments
		var shore: Array = []
		var near := box.grow(BAND.y + 20.0)
		for sea: PackedVector2Array in seas:
			for i in range(sea.size()):
				var p0 := sea[i]
				var p1 := sea[(i + 1) % sea.size()]
				if near.intersects(Rect2(p0, Vector2.ZERO).expand(p1)) and not _along_edge(p0, p1):
					shore.append([p0, p1])
		if shore.is_empty():
			continue   # sand inland (a playground's pit, a dune): no beach
		count["beaches"] = int(count.get("beaches", 0)) + 1
		var x := box.position.x + STEP * 0.5
		while x < box.end.x:
			var z := box.position.y + STEP * 0.5
			while z < box.end.y:
				var j := Vector2(x, z)
				var h := _hash(j)
				var p := j + Vector2(float(h % 100) - 50.0, float((h / 100) % 100) - 50.0) * 0.012
				z += STEP
				if not Geometry2D.is_point_in_polygon(p, ring):
					continue
				var to := _to_sea(p, shore)
				var d := to.length()
				if d < 0.5:
					continue
				var dir := to / d
				if d >= BAND.x and d <= BAND.y and float((h / 10000) % 100) < FILL * 100.0:
					_put(p, ["umb", p, dir, h])
				elif absf(d - LIFEGUARD_AT) < STEP * 0.5 and towers.all(func(q): return (q as Vector2).distance_to(p) > LIFEGUARD_EVERY):
					towers.append(p)
					_put(p, ["tower", p, dir, h])
			x += STEP

## an outline that runs along the map's edge for a stretch (the sea's, closed along the box)
func _on_edge(ring: PackedVector2Array) -> bool:
	for i in range(ring.size()):
		if _along_edge(ring[i], ring[(i + 1) % ring.size()]) and ring[i].distance_to(ring[(i + 1) % ring.size()]) > 50.0:
			return true
	return false

func _along_edge(a: Vector2, b: Vector2) -> bool:
	var r: Rect2 = g._bounds
	for e: float in [r.position.x, r.end.x]:
		if absf(a.x - e) < 1.0 and absf(b.x - e) < 1.0:
			return true
	for e: float in [r.position.y, r.end.y]:
		if absf(a.y - e) < 1.0 and absf(b.y - e) < 1.0:
			return true
	return false

func _to_sea(p: Vector2, shore: Array) -> Vector2:
	var best := Vector2(1e9, 1e9)
	for s: Array in shore:
		var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
		if (q - p).length_squared() < best.length_squared():
			best = q - p
	return best

func _hash(p: Vector2) -> int:
	return absi(hash(Vector2i(p.round())))

func _put(p: Vector2, item: Array) -> void:
	var t: Vector2i = g._tile_of(p)
	if not _tile_items.has(t):
		_tile_items[t] = []
	(_tile_items[t] as Array).append(item)

## this square's: the umbrellas and chairs as instances, the towers as boxes; the chairs'
## seats into g._beach_spots for the bathers; posts where the car or a walker bumps
func build() -> void:
	var items: Array = _tile_items.get(g._tile, [])
	if items.is_empty():
		return
	var poles: Array = []
	var shades: Array = []
	var shade_cols: Array = []
	var seats: Array = []
	var backs: Array = []
	var legs: Array = []
	var white: Color = g._tone["mark"]
	# (a beach's umbrellas in paint's colours: the palette's, softened, came out all but white)
	var hues := ["blue", "orange", "red", "green", "yellow", "blue", "white"]
	var towers = null
	for it: Array in items:
		var p: Vector2 = it[1]
		var dir: Vector2 = it[2]
		# (not on a path or a road across the sand, nor into a kiosk or what stands there)
		if not g._off_road(p, 2.0) or g._push_out(p, 1.6, true) != Vector2.ZERO:
			continue
		var gy: float = g._h(p)
		if String(it[0]) == "tower":
			if towers == null:
				towers = g.new_cbuf(400.0)
			_tower(towers, p, gy, dir)
			g._add_post(p, 1.5)
			count["towers"] = int(count.get("towers", 0)) + 1
			continue
		var h: int = it[3]
		var lean := Vector3(float(h % 7) - 3.0, 0, float((h / 7) % 7) - 3.0)
		var tilt := Basis(lean.normalized() if lean.length() > 0.5 else Vector3.RIGHT, 0.06)
		poles.append(Transform3D(tilt, Vector3(p.x, gy + 1.2, p.y)))
		shades.append(Transform3D(tilt, Vector3(p.x, gy, p.y) + tilt * Vector3(0, 2.35, 0)))
		var hue: String = hues[posmod(h >> 3, hues.size())]
		shade_cols.append(g._real_col(hue))
		g._add_post(p, 0.12)
		count["umbrellas"] = int(count.get("umbrellas", 0)) + 1
		var side := Vector2(-dir.y, dir.x)
		for sgn: float in [-1.0, 1.0]:
			if (h >> (10 + int(sgn + 1.0))) % 5 == 0:
				continue   # (now and then one chair, or none)
			var face := dir.rotated((float((h >> (12 + int(sgn + 1.0))) % 9) - 4.0) * 0.06)
			var ch := p + side * 0.75 * sgn - dir * 0.3
			var yaw := atan2(face.x, face.y)
			var b := Basis(Vector3.UP, yaw)
			seats.append(Transform3D(b, Vector3(ch.x, gy + 0.45, ch.y)))
			var bk := ch - face * 0.2
			backs.append(Transform3D(b, Vector3(bk.x, gy + 0.68, bk.y)))
			legs.append(Transform3D(b, Vector3(ch.x, gy + 0.21, ch.y)))
			g._beach_spots.append([ch, face])
			count["chairs"] = int(count.get("chairs", 0)) + 1
	if towers != null:
		g._add_mesh(towers, g._vc_mat(), true, 500.0)
	if poles.is_empty():
		return
	var range_end: float = g.SIGN_RANGE * 2.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.025
	pole.height = 2.4
	pole.radial_segments = 4
	g._chunked(pole, poles, range_end, [], g._surface("furniture"))
	var shade := CylinderMesh.new()
	shade.top_radius = 0.04
	shade.bottom_radius = 1.35
	shade.height = 0.45
	shade.radial_segments = 10
	g._chunked(shade, shades, range_end * 1.5, shade_cols, g._vc_mat())
	if seats.is_empty():
		return
	var whites: Array = []
	whites.resize(seats.size())
	whites.fill(white)
	var seat := BoxMesh.new()
	seat.size = Vector3(0.44, 0.05, 0.42)
	var back := BoxMesh.new()
	back.size = Vector3(0.44, 0.44, 0.04)
	var leg := BoxMesh.new()   # (the four legs as one splayed block, read as legs from a car)
	leg.size = Vector3(0.4, 0.42, 0.36)
	g._chunked(seat, seats, range_end, whites, g._vc_mat())
	g._chunked(back, backs, range_end, whites, g._vc_mat())
	var shadowed: Array = whites.map(func(c): return (c as Color).darkened(0.18))
	g._chunked(leg, legs, range_end * 0.6, shadowed, g._vc_mat())

## a lifeguard's tower: a hut on four legs, a roof over it, a band round it, a ramp down to
## the sand behind and a flag, its window toward the sea
func _tower(b, p: Vector2, gy: float, dir: Vector2) -> void:
	var z3 := Vector3(dir.x, 0.0, dir.y)   # toward the sea
	var x3 := Vector3(dir.y, 0.0, -dir.x)
	var bs := Basis(x3, Vector3.UP, z3)
	var base := Vector3(p.x, gy, p.y)
	var P := func(u: float, v: float, w: float) -> Vector3: return base + x3 * u + Vector3.UP * v + z3 * w
	var white: Color = g._tone["mark"]
	var blue: Color = g._tone["signblue"]
	var frame: Color = g._tone["metal"]
	var red: Color = g._tone["signred"]
	for u: float in [-1.0, 1.0]:
		for w: float in [-0.8, 0.8]:
			g._furn._box(b, P.call(u, 1.3, w), Vector3(0.14, 2.6, 0.14), frame, bs)
	g._furn._box(b, P.call(0.0, 2.65, 0.0), Vector3(2.6, 0.12, 2.0), frame, bs)        # the floor
	g._furn._box(b, P.call(0.0, 3.75, -0.25), Vector3(2.4, 2.1, 1.5), white, bs)       # the hut
	g._furn._box(b, P.call(0.0, 3.4, -0.25), Vector3(2.44, 0.35, 1.54), blue, bs)      # its band
	g._furn._box(b, P.call(0.0, 4.25, 0.51), Vector3(2.0, 0.8, 0.03), g._tone["tyre"], bs)   # the window
	g._furn._box(b, P.call(0.0, 4.92, -0.1), Vector3(2.9, 0.14, 2.3), blue, bs)        # the roof
	g._furn._box(b, P.call(0.0, 2.95, 0.95), Vector3(2.6, 0.5, 0.05), white, bs)       # the balcony's front
	g._furn._box(b, P.call(0.0, 1.35, -2.4), Vector3(0.9, 0.08, 3.1), frame, bs * Basis(Vector3.RIGHT, -0.72))   # the ramp
	g._furn._box(b, P.call(1.15, 5.9, -0.9), Vector3(0.05, 2.0, 0.05), frame, bs)      # the flag's pole
	g._furn._box(b, P.call(1.15, 6.6, -1.3), Vector3(0.02, 0.5, 0.75), red, bs)        # the flag
