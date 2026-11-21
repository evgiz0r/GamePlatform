extends RefCounted
## The city seen from above before it is built: "when i zoom the beginning the rest of the
## city is still being built. maybe i can still see something (roads?!, dunno), and click in
## the area of the city, before it rendered". Only the squares round the car are built at the
## start; the rest go up one by one while you drive. Each square still to be built gets a
## cheap stand-in at once, from the city file already loaded: its roads as flat strips, its
## buildings' outlines flat on the ground, its parks, woods, pitches and water -- one mesh a
## square, one draw. It is shown only while the view is up over the city (from the street
## the unbuilt squares are far off in the haze), and dropped the moment its square is built.
## A long press up there already finds the street (it reads the road data, not the meshes):
## this is something to see and aim at.

const ROAD_Y := 0.4           ## heights over the ground: the areas, the roads, the buildings
const AREA_Y := 0.2
const BLD_Y := 0.6
const STEP := 12.0            ## a road strip follows the ground every this many metres

var g: Node
var root: Node3D
var _by_tile := {}            ## square -> its MeshInstance3D
var _mat: StandardMaterial3D
var made := 0                 ## for tests: stand-ins made, dropped, and the ms it took
var dropped := 0
var ms := 0

func _init(game: Node) -> void:
	g = game

## a stand-in for every square still to build (a few milliseconds a frame: g._over / _pause)
func build_all() -> void:
	var t0 := Time.get_ticks_msec()
	root = Node3D.new()
	root.name = "standins"
	root.visible = false
	g.world.add_child(root)
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cols := {
		"road": Palette.col("ink").darkened(0.45),
		"bld": Palette.col("ink").darkened(0.15),
		"park": Palette.col("friend").darkened(0.5),
		"grass": Palette.col("friend").darkened(0.55),
		"wood": Palette.col("friend").darkened(0.65),
		"pitch": Palette.col("friend").darkened(0.4),
		"water": Palette.col("player").darkened(0.35),
		"parking": Palette.col("bg_alt").lightened(0.12),
		"plaza": Palette.col("bg_alt").lightened(0.2),
	}
	for t: Vector2i in (g._tiles_todo as Array).duplicate():
		if g._tiles_done.has(t):
			continue
		if g._over():
			await g._pause()
		if g._tiles_done.has(t) or not is_instance_valid(root):
			continue   # (built meanwhile)
		var mi := _square(t, cols)
		if mi != null:
			root.add_child(mi)
			_by_tile[t] = mi
			made += 1
	ms = Time.get_ticks_msec() - t0
	print("[streets] stand-ins for %d squares still to build, %d ms" % [made, ms])
	Probe.event("standins", {"squares": made, "ms": ms})

## square t is built: its stand-in goes
func drop(t: Vector2i) -> void:
	if _by_tile.has(t):
		var mi: Node = _by_tile[t]
		if is_instance_valid(mi):
			mi.queue_free()
		_by_tile.erase(t)
		dropped += 1

func show(on: bool) -> void:
	if root != null and is_instance_valid(root) and root.visible != on:
		root.visible = on and not _by_tile.is_empty()

func _square(t: Vector2i, cols: Dictionary) -> MeshInstance3D:
	var rect: Rect2 = g._tile_rect(t)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	var clip := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	# parks, woods, water...: cut to the square (a park across two squares is half in each)
	for kind: String in g._tile_rings:
		if not cols.has(kind):
			continue
		var all: Array = g._area_rings.get(kind, [])
		for i: int in (g._tile_rings[kind] as Dictionary).get(t, []):
			for part: PackedVector2Array in Geometry2D.intersect_polygons(all[i], clip):
				n += _flat(st, part, cols[kind], AREA_Y, false)
	# roads: each piece of its line cut to the square, a strip as wide as the road
	for ri: int in g._tile_roads.get(t, []):
		var r: Dictionary = g._roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var hw := float(r["w"]) * 0.5
		for j in range(pts.size() - 1):
			var seg := _clip_seg(pts[j], pts[j + 1], rect)
			if seg.is_empty():
				continue
			n += _strip(st, seg[0], seg[1], hw, cols["road"])
	# buildings: the outline, flat, at the highest ground under it
	for bi: int in g._tile_blds.get(t, []):
		n += _flat(st, g._blds[bi], cols["bld"], BLD_Y, true)
	if n == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## a filled outline lying on the ground (`level`: all of it at its highest point, a roof
## seen from above; else each corner on the ground under it)
func _flat(st: SurfaceTool, ring: PackedVector2Array, col: Color, dy: float, level: bool) -> int:
	if ring.size() < 3:
		return 0
	var tri := Geometry2D.triangulate_polygon(ring)
	if tri.is_empty():
		return 0
	var ys := PackedFloat32Array()
	var top := -INF
	for p: Vector2 in ring:
		var y: float = g._h(p)
		ys.append(y)
		top = maxf(top, y)
	st.set_color(col)
	for k in tri:
		var p: Vector2 = ring[k]
		st.add_vertex(Vector3(p.x, (top if level else ys[k]) + dy, p.y))
	return 1

## a flat strip from a to b, hw either side, following the ground every STEP metres
func _strip(st: SurfaceTool, a: Vector2, b: Vector2, hw: float, col: Color) -> int:
	var L := a.distance_to(b)
	if L < 0.05:
		return 0
	var dir := (b - a) / L
	var side := Vector2(-dir.y, dir.x) * hw
	var steps := maxi(1, ceili(L / STEP))
	st.set_color(col)
	var p0 := a
	var y0: float = g._h(a) + ROAD_Y
	for i in range(1, steps + 1):
		var p1 := a.lerp(b, float(i) / steps)
		var y1: float = g._h(p1) + ROAD_Y
		var q := [Vector3(p0.x + side.x, y0, p0.y + side.y), Vector3(p0.x - side.x, y0, p0.y - side.y),
			Vector3(p1.x + side.x, y1, p1.y + side.y), Vector3(p1.x - side.x, y1, p1.y - side.y)]
		for v: Vector3 in [q[0], q[1], q[2], q[2], q[1], q[3]]:
			st.add_vertex(v)
		p0 = p1
		y0 = y1
	return 1

## the part of segment a-b inside rect ([] if none): Liang-Barsky
func _clip_seg(a: Vector2, b: Vector2, rect: Rect2) -> Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for e: Array in [[-d.x, a.x - rect.position.x], [d.x, rect.end.x - a.x], [-d.y, a.y - rect.position.y], [d.y, rect.end.y - a.y]]:
		var pp: float = e[0]
		var qq: float = e[1]
		if absf(pp) < 1e-9:
			if qq < 0.0:
				return []
			continue
		var r := qq / pp
		if pp < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return []
	return [a + d * t0, a + d * t1]
