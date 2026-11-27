extends RefCounted
## The minimap: the streets round the car, gathered by squares of the map (moved out of streets.gd; `g` is the game).
## The minimap's lines round a point, in metres from it: outlines, paths, minor and major
## streets, the city limits, places. Gathered again only once the car is MAP_MOVE away,
## not every frame (that was a few thousand points a frame, in script).

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const MAP_MOVE := 60.0
var _map_lines := {}

## The minimap's lines, sorted once (while the city loads) into squares of the map, in the
## city's own coordinates: building outlines, paths, minor and major streets. Gathering the
## ones round the car is then joining the squares' arrays, not walking every outline and
## street in 360 m: that walk, every 60 m driven, was a stutter every few seconds.
const MAP_CELL := 120.0
var _map_cells := {}                 ## Vector2i -> {"blds", "paths", "minor", "major"}

func _map_build_cells() -> void:
	_map_cells = {}
	var cell_of := func(p: Vector2) -> Dictionary:
		var key := Vector2i(floori(p.x / MAP_CELL), floori(p.y / MAP_CELL))
		if not _map_cells.has(key):
			_map_cells[key] = {"blds": PackedVector2Array(), "paths": PackedVector2Array(),
				"minor": PackedVector2Array(), "major": PackedVector2Array()}
		return _map_cells[key]
	for poly: PackedVector2Array in g._blds:
		if poly.is_empty():
			continue
		var out: PackedVector2Array = cell_of.call(poly[0])["blds"]
		for j in range(poly.size()):
			out.append(poly[j])
			out.append(poly[(j + 1) % poly.size()])
	for r: Dictionary in g._roads:
		var pts: PackedVector2Array = r["pts"]
		var kind := "paths" if (not r["drive"] or r["pv"]) else ("major" if float(r["w"]) >= 9.0 else "minor")
		for j in range(pts.size() - 1):
			var out: PackedVector2Array = cell_of.call((pts[j] + pts[j + 1]) * 0.5)[kind]
			out.append(pts[j])
			out.append(pts[j + 1])

## the lines round `at` (in the city's coordinates: "at" in the result is where they were
## gathered, for knowing when to gather again)
func _map_gather(at: Vector2, r: float) -> Dictionary:
	if _map_cells.is_empty():
		_map_build_cells()
	var reach := r * 1.45 + MAP_MOVE * r / Streets.MAP_R   # the map's corners, wherever the car turns
	# (plain local arrays: appending through `dict[k] as PackedVector2Array` goes to a copy)
	var blds := PackedVector2Array()
	var paths := PackedVector2Array()
	var minor := PackedVector2Array()
	var major := PackedVector2Array()
	var c0 := Vector2i(floori((at.x - reach) / MAP_CELL), floori((at.y - reach) / MAP_CELL))
	var c1 := Vector2i(floori((at.x + reach) / MAP_CELL), floori((at.y + reach) / MAP_CELL))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell: Dictionary = _map_cells.get(Vector2i(cx, cz), {})
			if cell.is_empty():
				continue
			blds.append_array(cell["blds"])
			paths.append_array(cell["paths"])
			minor.append_array(cell["minor"])
			major.append_array(cell["major"])
	var limits: Array = []
	for ring: PackedVector2Array in g._boundary:
		var pts := ring.duplicate()
		pts.append(ring[0])
		limits.append(pts)
	var rails: PackedVector2Array = g._rails.map_lines(at, reach) if g._rails != null else PackedVector2Array()
	var places: Array = []
	for poi: Array in g._pois:
		var d: Vector2 = (poi[0] as Vector2) - at
		if absf(d.x) < reach and absf(d.y) < reach:
			places.append([poi[0], poi[1]])
	return {"at": at, "r": r, "blds": blds, "paths": paths, "minor": minor, "major": major, "rails": rails,
		"limits": limits, "places": places}

## the minimap: streets and building outlines round the car, heading up
func _draw_map() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_map_inner()
	g._prof["minimap"] = int(g._prof.get("minimap", 0)) + Time.get_ticks_usec() - t0

func _draw_map_inner() -> void:
	var sz := g._map.size
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	g._map.draw_rect(Rect2(Vector2.ZERO, sz), Color(bg, 0.72))
	# the view from above: the map follows it -- centred where you look, turned as the screen
	# is, wide enough to hold the ground on screen (outlined below); the usual map otherwise
	var zw := smoothstep(0.0, Streets.ZOOM_BLEND, g._zoom_v) if g._zoomed() else 0.0
	var mid := g._view_pos + g._zoom_off * zw
	var yaw := lerp_angle(g._view_yaw, g._zoom_yaw, zw)
	var r := Streets.MAP_R
	var foot := PackedVector2Array()
	if zw > 0.0:
		foot = _view_footprint()
		var far := 0.0
		for q: Vector2 in foot:
			far = maxf(far, q.distance_to(mid))
		r = lerpf(Streets.MAP_R, maxf(Streets.MAP_R, far * 1.2), zw)
	if _map_lines.is_empty() or (_map_lines["at"] as Vector2).distance_to(mid) > MAP_MOVE * r / Streets.MAP_R \
			or r > float(_map_lines["r"]) or r < float(_map_lines["r"]) * 0.5:
		_map_lines = _map_gather(mid, r * 1.3 if r > Streets.MAP_R else Streets.MAP_R)   # (growing: some to spare)
	var at := Vector2.ZERO   # the lines are in the city's own coordinates
	var s := sz.x * 0.5 / r
	# heading up round the middle of the map, the car in the middle
	var xf := Transform2D(-PI * 0.5 - yaw, Vector2(s, s), 0.0, sz * 0.5) * Transform2D(0.0, -mid)
	g._map.draw_set_transform_matrix(xf)
	if r < 450.0 and not (_map_lines["blds"] as PackedVector2Array).is_empty():   # (wider: a grey blur)
		# plain one-pixel lines: wide ones are rebuilt as strips every frame, and the outlines
		# are most of the map's lines
		g._map.draw_multiline(_map_lines["blds"], Color(ink, 0.3), -1.0)
	if not (_map_lines["paths"] as PackedVector2Array).is_empty():
		g._map.draw_multiline(_map_lines["paths"], Color(ink, 0.3), 1.0 / s)
	if not (_map_lines.get("rails", PackedVector2Array()) as PackedVector2Array).is_empty():   # a railway: light on dark
		g._map.draw_multiline(_map_lines["rails"], Color(bg, 0.9), 3.0 / s)
		g._map.draw_multiline(_map_lines["rails"], Color(ink, 0.6), 1.0 / s)
	if not (_map_lines["minor"] as PackedVector2Array).is_empty():
		g._map.draw_multiline(_map_lines["minor"], Color(ink, 0.75), 2.0 / s)
	if not (_map_lines["major"] as PackedVector2Array).is_empty():
		g._map.draw_multiline(_map_lines["major"], Palette.col("warn"), 3.0 / s)
	for pts: PackedVector2Array in _map_lines["limits"]:
		g._map.draw_polyline(pts, Color(Palette.col("accent"), 0.8), 1.5 / s)
	var rim := g._bounds.grow(-Streets.EDGE)
	var deep := rim.grow(-r * 1.5)   # (a map wider than the town: no inside at all)
	if deep.size.x <= 0.0 or deep.size.y <= 0.0 or not deep.has_point(mid):   # the map's edge, when it is in view
		g._map.draw_polyline(PackedVector2Array([rim.position - at, Vector2(rim.end.x, rim.position.y) - at, rim.end - at,
			Vector2(rim.position.x, rim.end.y) - at, rim.position - at]), Palette.col("hazard"), 3.0 / s)
	if g._auto and g._ap_pts.size() > 1:
		var route := PackedVector2Array()
		for p in g._ap_pts:
			route.append(p - at)
		# as a navigation app draws it: wider than any road, in the destination's own colour
		# (the line leads to the dot), on a dark edge that parts it from whatever road is under
		# it. (A thin line in the palette's mint, 1.5 px, was lost among the yellow main roads,
		# the white streets and the white dots of the traffic.)
		var col := Palette.col("accent")
		g._map.draw_polyline(route, Color(bg, 0.95), 7.0 / s)
		g._map.draw_polyline(route, col, 4.0 / s)
		for p: Vector2 in [route[0], route[route.size() - 1]]:   # (round ends, not cut-off ones)
			g._map.draw_circle(p, 3.5 / s, Color(bg, 0.95))
			g._map.draw_circle(p, 2.0 / s, col)
	for pl: Array in _map_lines["places"]:
		g._map.draw_circle(pl[0], 1.8 / s, Palette.col(pl[1]))
	if g._traffic != null:
		for c in g._traffic.cars:
			if c.alive:
				g._map.draw_circle(c.pos - at, 1.9 / s, Color(ink, 0.8))
	if g._walking:
		g._map.draw_rect(Rect2(g._car_at - at - Vector2(3, 3) / s, Vector2(6, 6) / s), Palette.col("warn"))
	if g._dest_on:
		g._map.draw_circle(g._dest - at, 6.0 / s, Palette.col("accent"))
		g._map.draw_arc(g._dest - at, 11.0 / s, 0.0, TAU, 24, Color(Palette.col("accent"), 0.6), 1.5 / s)
	if foot.size() == 4:   # what is on the screen
		g._map.draw_colored_polygon(foot, Color(Palette.col("player"), 0.13 * zw))
		var ring := foot.duplicate()
		ring.append(foot[0])
		g._map.draw_polyline(ring, Color(Palette.col("player"), 0.85 * zw), 1.5 / s)
	g._map.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# you: in the middle and heading up, or (the view dragged away) where you are, or an
	# arrow on the map's edge pointing there
	var me := xf * g._view_pos
	var fw := (xf.basis_xform(Vector2(cos(g._view_yaw), sin(g._view_yaw)))).normalized()
	var sd := Vector2(-fw.y, fw.x)
	var box := Rect2(Vector2.ZERO, sz).grow(-7.0)
	if not box.has_point(me):
		var c := sz * 0.5
		var d := me - c
		var k := minf(absf(box.size.x * 0.5 / d.x) if d.x != 0.0 else INF, absf(box.size.y * 0.5 / d.y) if d.y != 0.0 else INF)
		me = c + d * k
		fw = d.normalized()
		sd = Vector2(-fw.y, fw.x)
	g._map.draw_colored_polygon(PackedVector2Array([me + fw * 7.0, me - fw * 5.0 + sd * 5.0, me - fw * 5.0 - sd * 5.0]), Palette.col("player"))
	g._map.draw_rect(Rect2(Vector2.ZERO, sz), Color(ink, 0.5), false, 1.0)

## the ground on screen: where the four corners of the view meet it, in the city's metres
## (empty if a corner looks above the horizon)
func _view_footprint() -> PackedVector2Array:
	var y := g._h(g._view_pos + g._zoom_off)
	var out := PackedVector2Array()
	for sc: Vector2 in [g.play_area.position, Vector2(g.play_area.end.x, g.play_area.position.y), g.play_area.end,
			Vector2(g.play_area.position.x, g.play_area.end.y)]:
		var g_ := g.ground_point(sc, y)
		if g_ == Vector3.INF:
			return PackedVector2Array()
		out.append(Vector2(g_.x, g_.z))
	return out
