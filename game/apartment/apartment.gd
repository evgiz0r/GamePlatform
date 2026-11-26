extends GameMode3D
## apartment -- walk round a made-up Israeli flat, built in 3D from a floor plan.
##
## The plans are made by lab/apartments/plan.py (rooms on a 10 cm grid, doors, windows,
## furniture) and exported to plans/*.json with `--export`; this only builds and walks them.
## Everything is in metres: the plan's x is the world's X, its y (from the stairwell
## towards the balcony) is the world's +Z. The flat is centred on the origin.
##
## Two views: walking (eye height, first person) and the dollhouse (from above, ceilings
## off, you are a little figure). action_b swaps them. action_a starts the guided tour,
## which walks the flat room by room by itself (the bots press it, so a playtest is a real
## walk); a tap or click stops it.
##
## The furniture is boxes: each item in the plan is a few boxes in _item(), all merged into
## one mesh per colour so the whole flat is a dozen or so draws.

const LEVELS := [
	{"name": "flat 1: 4 rooms, 104 m2 + 8 m2 mirpeset", "plan": "plan_1"},
	{"name": "flat 2: 4 rooms, 98 m2 + 10 m2 mirpeset", "plan": "plan_2"},
	{"name": "flat 3: 4 rooms, 106 m2 + 10 m2 mirpeset", "plan": "plan_3"},
	{"name": "flat 4: 4 rooms, 106 m2 + 9 m2 mirpeset", "plan": "plan_4"},
	{"name": "flat 5: 4 rooms, 119 m2 + 14 m2 mirpeset", "plan": "plan_5"},
	{"name": "flat 6: 4 rooms, 127 m2 + 14 m2 mirpeset", "plan": "plan_6"},
	{"name": "flat 7: 4 rooms, 102 m2 + 13 m2 mirpeset", "plan": "plan_7"},
	{"name": "flat 8: 4 rooms, 103 m2 + 9 m2 mirpeset", "plan": "plan_8"},
]

const H := 2.7              ## floor to ceiling
const DOOR_H := 2.1
const SILL := 0.9
const WIN_TOP := 2.2
const EYE := 1.6
const R := 0.22             ## the walker's radius
const WALK := 1.6           ## m/s
const TURN := 2.2           ## rad/s on the keys
const SFX_SCALE := 0.28

## Interior colours. Realistic, not palette roles: like the city game this sits next to,
## a flat is meant to look like a flat.
const C_WALL := Color(0.93, 0.92, 0.89)
const C_MAMAD := Color(0.80, 0.79, 0.77)
const C_EXT := Color(0.90, 0.88, 0.84)
const C_CEIL := Color(0.97, 0.97, 0.96)
const C_FLOOR := {
	"salon": Color(0.82, 0.80, 0.76), "hall": Color(0.82, 0.80, 0.76),
	"entrance": Color(0.82, 0.80, 0.76), "kitchen": Color(0.78, 0.77, 0.74),
	"bedroom": Color(0.70, 0.56, 0.42), "parents": Color(0.70, 0.56, 0.42),
	"mamad": Color(0.76, 0.75, 0.72), "bath": Color(0.80, 0.85, 0.88),
	"ensuite": Color(0.80, 0.85, 0.88), "toilet": Color(0.80, 0.85, 0.88),
	"mirpeset": Color(0.72, 0.62, 0.52),
}
const C_WOOD := Color(0.62, 0.46, 0.32)
const C_WOOD_LT := Color(0.80, 0.68, 0.52)
const C_WHITE := Color(0.95, 0.95, 0.95)
const C_FABRIC := Color(0.55, 0.58, 0.62)
const C_SHEET := Color(0.92, 0.90, 0.86)
const C_DARK := Color(0.12, 0.12, 0.14)
const C_STEEL := Color(0.60, 0.62, 0.64)
const C_COUNTER := Color(0.30, 0.30, 0.32)
const C_LEAF := Color(0.30, 0.52, 0.28)
const C_GLASS := Color(0.65, 0.80, 0.90, 0.25)
const C_DOOR := Color(0.88, 0.86, 0.82)
const C_STEEL_DOOR := Color(0.45, 0.42, 0.40)

var plan: Dictionary = {}
var _off := Vector2.ZERO          ## plan point + _off = world X/Z (centres the flat)
var _batches := {}                ## Color -> [PackedVector3Array verts, PackedVector3Array normals]
var _solid: Array[Rect2] = []     ## what the walker cannot pass, world X/Z
var _org := Vector3.ZERO          ## _box subtracts this: builds an item round its own centre
var _mat_cache := {}              ## Color -> StandardMaterial3D, shared by every mesh
var items: Array = []             ## {node, rect (world X/Z), name, solid}: the furniture
var _door_ends := {}              ## "o|line|pos" of every door opening's two ends
var _ceiling: Node3D
var _labels: Node3D
var _figure: MeshInstance3D       ## the walker, seen in the dollhouse
var _pos := Vector2.ZERO          ## the walker, world X/Z
var _yaw := 0.0                   ## 0 looks along -Z
var _pitch := -0.08
var _doll := false
var _tour: Array = []             ## waypoints left on the guided tour
var _tour_best := INF            ## closest it has got to the current waypoint
var _tour_wait := 0.0             ## seconds without getting closer
var _drag_from := Vector2.INF
var _drag_yaw := 0.0
var _drag_now := Vector2.ZERO
var _room_label: Label
var _room_now := ""
var _sfx_was := 0.8
var _loaded := false

func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-8, -7, 16, 14)

func _ready() -> void:
	title = "apartment"
	super()

func start(config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	var n := clampi(int(config.get("level", 1)), 1, LEVELS.size())
	var f := FileAccess.open("res://game/apartment/plans/%s.json" % LEVELS[n - 1]["plan"], FileAccess.READ)
	plan = JSON.parse_string(f.get_as_text())
	var size := Vector2(plan["size"][0], plan["size"][1])
	_off = -size / 2.0
	world_area = Rect2(-size.x / 2 - 1, -size.y / 2 - 1, size.x + 2, size.y + 2)
	env.ambient_light_energy = 0.75
	env.ambient_light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 0.55
	sun.rotation_degrees = Vector3(-55, -30, 0)
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color = Color(0.35, 0.55, 0.85)
	sky.sky_horizon_color = Color(0.75, 0.84, 0.92)
	sky.ground_horizon_color = Color(0.75, 0.84, 0.92)
	sky.ground_bottom_color = Color(0.55, 0.55, 0.52)
	cam.fov = 70.0
	cam.near = 0.05
	_build()
	_build_ui()
	_build_deco_ui()
	var s: Array = plan["start"]
	_pos = _w(s[0], s[1])
	_yaw = 0.0
	if _yaw == 0.0:
		_yaw = PI   # face into the flat (+Z), away from the front door
	Probe.event("start")
	_loaded = true

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

func _w(x: float, y: float) -> Vector2:
	return Vector2(x, y) + _off

## ---- building -----------------------------------------------------------------

func _build() -> void:
	for r in plan["rooms"]:
		var rc: Array = r["rect"]
		var a := _w(rc[0], rc[1])
		var b := _w(rc[2], rc[3])
		var y := 0.004 if r["kind"] == "ensuite" else 0.0   # painted over the parents' room
		_box(Vector3(a.x, y - 0.05, a.y), Vector3(b.x, y, b.y), C_FLOOR.get(r["kind"], C_WALL))
	# where door openings end, so a wall run does not reach into one (see _wall)
	for wr in plan["walls"]:
		if wr[4] == "door":
			_door_ends["%s|%.2f|%.2f" % [wr[0], wr[1], wr[2]]] = true
			_door_ends["%s|%.2f|%.2f" % [wr[0], wr[1], wr[3]]] = true
	for wr in plan["walls"]:
		_wall(wr)
	for d in plan["doors"]:
		_door(d)
	world.add_child(_commit("Flat"))
	# every piece of furniture its own object, so it can be picked up and moved
	for it in plan["items"]:
		_make_item(it)
	# ceilings, a mesh of their own so the dollhouse can hide them
	for r in plan["rooms"]:
		if r["kind"] == "mirpeset":
			continue
		var rc: Array = r["rect"]
		var a := _w(rc[0], rc[1])
		var b := _w(rc[2], rc[3])
		_box(Vector3(a.x, H, a.y), Vector3(b.x, H + 0.1, b.y), C_CEIL)
	_ceiling = _commit("Ceiling")
	world.add_child(_ceiling)
	# a slab under it all and round it, so the dollhouse does not float in the sky
	var size := Vector2(plan["size"][0], plan["size"][1])
	_box(Vector3(-size.x / 2 - 3, -0.4, -size.y / 2 - 3), Vector3(size.x / 2 + 3, -0.06, size.y / 2 + 3),
		Color(0.55, 0.55, 0.56))
	world.add_child(_commit("Slab"))
	# room names, seen from above
	_labels = Node3D.new()
	world.add_child(_labels)
	for r in plan["rooms"]:
		if r["kind"] == "hall":
			continue
		var l := Label3D.new()
		var p := _w(r["label"][0], r["label"][1])
		l.text = "%s\n%.1f m²" % [r["name"], r["area"]]
		l.position = Vector3(p.x, 1.3, p.y)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 48
		l.pixel_size = 0.006
		l.outline_size = 12
		l.modulate = Color(0.1, 0.1, 0.12)
		l.outline_modulate = Color(1, 1, 1, 0.9)
		l.no_depth_test = true
		_labels.add_child(l)
	_labels.visible = false
	# the walker as the dollhouse sees it
	_figure = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 1.7
	_figure.mesh = cap
	_figure.material_override = mat("player", 0.6)
	_figure.visible = false
	world.add_child(_figure)
	track3d(_figure, "@")

## One wall run from the plan: [o, line, a, b, kind, thickness]. Solid walls go floor to
## ceiling, a window keeps a sill and a lintel with glass between, a door keeps a lintel.
func _wall(wr: Array) -> void:
	var o: String = wr[0]
	var line: float = wr[1]
	var a: float = wr[2]
	var b: float = wr[3]
	var kind: String = wr[4]
	var t: float = wr[5] / 2.0
	var col := C_WALL
	if kind == "mamad":
		col = C_MAMAD
	elif kind == "ext":
		col = C_EXT
	# solid runs reach half their thickness past each end to close the corners, except
	# into a door opening (a mamad's 15 cm on each side left a door 50 cm wide)
	var solid := kind in ["ext", "wall", "mamad"]
	var ea := t if solid and not _door_ends.has("%s|%.2f|%.2f" % [o, line, a]) else 0.0
	var eb := t if solid and not _door_ends.has("%s|%.2f|%.2f" % [o, line, b]) else 0.0
	var box := func(y0: float, y1: float, c: Color, tt: float = t) -> void:
		var p0: Vector2
		var p1: Vector2
		if o == "v":
			p0 = _w(line - tt, a - ea)
			p1 = _w(line + tt, b + eb)
		else:
			p0 = _w(a - ea, line - tt)
			p1 = _w(b + eb, line + tt)
		_box(Vector3(p0.x, y0, p0.y), Vector3(p1.x, y1, p1.y), c)
	var rect := Rect2()
	if o == "v":
		rect = Rect2(_w(line - t, a - ea), Vector2(2 * t, b - a + ea + eb))
	else:
		rect = Rect2(_w(a - ea, line - t), Vector2(b - a + ea + eb, 2 * t))
	match kind:
		"ext", "wall", "mamad":
			box.call(0.0, H, col)
			_solid.append(rect)
		"window":
			box.call(0.0, SILL, C_EXT)
			box.call(WIN_TOP, H, C_EXT)
			box.call(SILL, WIN_TOP, C_GLASS, 0.01)
			_solid.append(rect)
		"door":
			box.call(DOOR_H, H, C_WALL)
		"rail":
			box.call(0.0, 1.05, Color(0.85, 0.84, 0.80))
			_solid.append(rect)

## Door leaves, standing open at a right angle into the room they swing into; the balcony
## slider as two glass panes, one pushed behind the other.
func _door(d: Dictionary) -> void:
	var o: String = d["o"]
	var line: float = d["line"]
	var a: float = d["a"]
	var b: float = d["b"]
	if d["style"] == "slider":
		var m := (a + b) / 2.0
		for k in [[a, m + 0.1, -0.04], [m - 0.1 + (b - m) * 0.6, b + (b - m) * 0.6 - 0.2, 0.04]]:
			var p0: Vector2
			var p1: Vector2
			if o == "h":
				p0 = _w(k[0], line + k[2] - 0.015)
				p1 = _w(minf(k[1], b), line + k[2] + 0.015)
			else:
				p0 = _w(line + k[2] - 0.015, k[0])
				p1 = _w(line + k[2] + 0.015, minf(k[1], b))
			_box(Vector3(p0.x, 0.0, p0.y), Vector3(p1.x, DOOR_H, p1.y), C_GLASS)
		return
	var w := b - a
	var side: float = d["side"]
	var hinge: float = d["hinge"]
	var steel: bool = d["style"] == "front" or d["into"] == "mamad"
	var th := 0.07 if steel else 0.04
	var col := C_STEEL_DOOR if steel else C_DOOR
	var q0: Vector2
	var q1: Vector2
	if o == "h":
		# leaf runs from the hinge into the room along y
		q0 = _w(hinge - th / 2, line)
		q1 = _w(hinge + th / 2, line + side * (w - 0.02))
	else:
		q0 = _w(line, hinge - th / 2)
		q1 = _w(line + side * (w - 0.02), hinge + th / 2)
	var lo := Vector2(minf(q0.x, q1.x), minf(q0.y, q1.y))
	var hi := Vector2(maxf(q0.x, q1.x), maxf(q0.y, q1.y))
	_box(Vector3(lo.x, 0.01, lo.y), Vector3(hi.x, DOOR_H - 0.02, hi.y), col)

## ---- furniture -----------------------------------------------------------------

## One item: its rect in plan metres and the way it faces (S = towards +y/+Z). Built in a
## local frame where u runs along its back wall and v out from it, then mapped.
func _item(it: Dictionary) -> void:
	var rc: Array = it["rect"]
	var a := _w(rc[0], rc[1])
	var b := _w(rc[2], rc[3])
	var face: String = it["face"]
	var name: String = it["name"]
	# local frame: length L along the wall, depth D out of it
	var L := (b.x - a.x) if face in ["S", "N"] else (b.y - a.y)
	var D := (b.y - a.y) if face in ["S", "N"] else (b.x - a.x)
	var part := func(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, c: Color) -> void:
		var p := _local(a, b, face, u0, v0)
		var q := _local(a, b, face, u1, v1)
		_box(Vector3(minf(p.x, q.x), y0, minf(p.y, q.y)), Vector3(maxf(p.x, q.x), y1, maxf(p.y, q.y)), c)
	match name:
		"bed_double", "bed_single":
			part.call(0, L, 0, D, 0.0, 0.3, C_WOOD)
			part.call(0.02, L - 0.02, 0.02, D - 0.02, 0.3, 0.5, C_SHEET)
			part.call(0, L, 0, 0.06, 0.0, 1.0, C_WOOD)                     # headboard
			var n := 2 if name == "bed_double" else 1
			for i in n:
				var u0 := L * i / n + 0.08
				part.call(u0, u0 + L / n - 0.16, 0.1, 0.45, 0.5, 0.62, C_WHITE)
			part.call(0.02, L - 0.02, D * 0.45, D - 0.02, 0.5, 0.56, C_FABRIC)  # duvet
		"sofa", "sofa_bed":
			var c := C_FABRIC if name == "sofa" else Color(0.45, 0.50, 0.42)
			part.call(0, L, 0, D, 0.0, 0.42, c)
			part.call(0, L, 0, 0.22, 0.42, 0.85, c)
			part.call(0, 0.16, 0, D, 0.42, 0.62, c)
			part.call(L - 0.16, L, 0, D, 0.42, 0.62, c)
		"wardrobe":
			part.call(0, L, 0, D, 0.0, 2.2, C_WOOD_LT)
			for k in range(1, int(L / 0.5)):
				part.call(k * 0.5 - 0.005, k * 0.5 + 0.005, D, D + 0.01, 0.05, 2.15, C_WOOD)
		"shelves":
			for k in 5:
				part.call(0, L, 0, D, k * 0.42, k * 0.42 + 0.03, C_WOOD_LT)
			part.call(0, 0.03, 0, D, 0.0, 1.8, C_WOOD_LT)
			part.call(L - 0.03, L, 0, D, 0.0, 1.8, C_WOOD_LT)
		"shoe_cabinet":
			part.call(0, L, 0, D, 0.0, 1.0, C_WOOD_LT)
		"desk":
			part.call(0, L, 0, D, 0.72, 0.76, C_WOOD_LT)
			part.call(0, 0.04, 0, D, 0.0, 0.72, C_WOOD_LT)
			part.call(L - 0.04, L, 0, D, 0.0, 0.72, C_WOOD_LT)
			part.call(L * 0.3, L * 0.7, 0.05, 0.1, 0.76, 1.1, C_DARK)        # a screen
		"nightstand":
			part.call(0, L, 0, D, 0.0, 0.5, C_WOOD)
		"counter":
			part.call(0, L, 0, D, 0.0, 0.88, C_WHITE)
			part.call(0, L, 0, D + 0.02, 0.88, 0.92, C_COUNTER)
			part.call(0, L, 0, 0.35, 1.5, 2.2, C_WHITE)                      # upper cabinets
			if L >= 1.4:
				part.call(L * 0.28 - 0.25, L * 0.28 + 0.25, 0.1, D - 0.1, 0.9, 0.925, C_STEEL)   # sink
				part.call(L * 0.7 - 0.3, L * 0.7 + 0.3, 0.05, D - 0.05, 0.92, 0.93, C_DARK)      # hob
		"fridge":
			part.call(0, L, 0, D, 0.0, 1.85, Color(0.85, 0.86, 0.87))
		"dining_table":
			part.call(0, L, 0, D, 0.72, 0.76, C_WOOD)
			for u in [0.05, L - 0.1]:
				for v in [0.05, D - 0.1]:
					part.call(u, u + 0.05, v, v + 0.05, 0.0, 0.72, C_WOOD)
		"coffee_table":
			part.call(0, L, 0, D, 0.0, 0.4, C_WOOD)
		"table_round":
			part.call(0.05, L - 0.05, 0.05, D - 0.05, 0.68, 0.72, Color(0.85, 0.85, 0.83))
			part.call(L / 2 - 0.03, L / 2 + 0.03, D / 2 - 0.03, D / 2 + 0.03, 0.0, 0.68, C_STEEL)
		"chair":
			part.call(0.03, L - 0.03, 0.03, D - 0.03, 0.43, 0.47, C_WOOD)
			part.call(0.03, L - 0.03, 0.0, 0.04, 0.0, 0.9, C_WOOD)
			part.call(0.03, 0.07, D - 0.07, D - 0.03, 0.0, 0.43, C_WOOD)
			part.call(L - 0.07, L - 0.03, D - 0.07, D - 0.03, 0.0, 0.43, C_WOOD)
		"tv_unit":
			part.call(0, L, 0, D, 0.0, 0.45, C_WOOD)
			part.call(L * 0.15, L * 0.85, 0.08, 0.13, 0.6, 1.25, C_DARK)
			part.call(L * 0.48, L * 0.52, 0.08, 0.2, 0.45, 0.6, C_DARK)
		"bathtub":
			part.call(0, L, 0, D, 0.0, 0.55, C_WHITE)
			part.call(0.08, L - 0.08, 0.08, D - 0.08, 0.3, 0.56, Color(0.75, 0.85, 0.92))
		"shower":
			part.call(0, L, 0, D, 0.0, 0.05, C_WHITE)
			part.call(0, L, D - 0.01, D, 0.05, 2.0, C_GLASS)
			part.call(L * 0.4, L * 0.6, 0.0, 0.05, 1.9, 2.0, C_STEEL)
		"toilet":
			part.call(L * 0.15, L * 0.85, 0.0, 0.2, 0.0, 0.8, C_WHITE)       # tank
			part.call(L * 0.1, L * 0.9, 0.2, D, 0.0, 0.42, C_WHITE)          # bowl
		"sink", "sink_small":
			part.call(0, L, 0, D, 0.0, 0.82, C_WOOD_LT if name == "sink" else C_WHITE)
			part.call(0, L, 0, D, 0.82, 0.86, C_WHITE)
			part.call(0, L, 0, 0.03, 1.0, 1.7, Color(0.80, 0.86, 0.90))      # mirror
		"washer":
			part.call(0, L, 0, D, 0.0, 0.85, C_WHITE)
			part.call(L * 0.25, L * 0.75, D, D + 0.01, 0.25, 0.7, C_DARK)
		"plant":
			part.call(0.1, L - 0.1, 0.1, D - 0.1, 0.0, 0.35, Color(0.62, 0.36, 0.24))
			part.call(0.0, L, 0.0, D, 0.35, 0.9, C_LEAF)
		"lounger":
			part.call(0, L, 0, D, 0.25, 0.35, C_WHITE)
			part.call(0, L, 0, D * 0.3, 0.35, 0.7, C_WHITE)
		_:
			part.call(0, L, 0, D, 0.0, 0.8, C_WOOD_LT)

## Item-local (u along its back wall from its left end, v out from the wall) to world X/Z.
func _local(a: Vector2, b: Vector2, face: String, u: float, v: float) -> Vector2:
	match face:
		"S":   # back at min y, faces +y; u runs +x
			return Vector2(a.x + u, a.y + v)
		"N":   # back at max y; u runs -x
			return Vector2(b.x - u, b.y - v)
		"E":   # back at min x, faces +x; u runs -y
			return Vector2(a.x + v, b.y - u)
		_:     # "W": back at max x; u runs +y
			return Vector2(b.x - v, a.y + u)

## ---- mesh batching ---------------------------------------------------------------

func _box(lo: Vector3, hi: Vector3, c: Color) -> void:
	lo -= _org
	hi -= _org
	if not _batches.has(c):
		_batches[c] = [PackedVector3Array(), PackedVector3Array()]
	var vs: PackedVector3Array = _batches[c][0]
	var ns: PackedVector3Array = _batches[c][1]
	var p := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	# faces: -z, +z, -x, +x, -y, +y (each wound clockwise seen from outside, Godot's front)
	var faces := [[0, 3, 2, 1, Vector3.FORWARD], [4, 5, 6, 7, Vector3.BACK], [0, 4, 7, 3, Vector3.LEFT],
		[1, 2, 6, 5, Vector3.RIGHT], [0, 1, 5, 4, Vector3.DOWN], [3, 7, 6, 2, Vector3.UP]]
	for f in faces:
		for k in [0, 1, 2, 0, 2, 3]:
			vs.append(p[f[k]])
			ns.append(f[4])
	_batches[c][0] = vs
	_batches[c][1] = ns

func _commit(node_name: String) -> MeshInstance3D:
	var am := ArrayMesh.new()
	for c in _batches:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _batches[c][0]
		arr[Mesh.ARRAY_NORMAL] = _batches[c][1]
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m: StandardMaterial3D = _mat_cache.get(c)
		if m == null:
			m = StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.85
			if c.a < 1.0:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.roughness = 0.1
			_mat_cache[c] = m
		am.surface_set_material(am.get_surface_count() - 1, m)
	_batches.clear()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = am
	return mi

## ---- walking ---------------------------------------------------------------------

func _build_ui() -> void:
	_room_label = Label.new()
	_room_label.position = Vector2(0, 8)
	_room_label.size = Vector2(640, 20)
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.add_theme_font_size_override("font_size", 14)
	_room_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_room_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_room_label.add_theme_constant_override("outline_size", 4)
	add_child(_room_label)
	var help := Label.new()
	help.text = "move: arrows / drag    view: shift (K)    tour: space (tap to stop)"
	help.position = Vector2(0, 340)
	help.size = Vector2(640, 16)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 9)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	help.add_theme_constant_override("outline_size", 3)
	add_child(help)

func _input(e: InputEvent) -> void:
	if Flow.pointer_over_hud() or not _loaded:
		return
	# a phone sends both touch and emulated mouse events: take the mouse ones only
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		return
	if e is InputEventMouseButton:
		if e.button_index != MOUSE_BUTTON_LEFT or _over_own_ui(e.position):
			return
		if e.pressed:
			_tour.clear()
			if _deco_press(e.position):
				return
			_drag_from = e.position
			_drag_now = e.position
			_drag_yaw = _yaw
		else:
			_drag_from = Vector2.INF
			_deco_release()
	elif e is InputEventMouseMotion:
		if not _hold.is_empty():
			_deco_drag(e.position)
		elif _drag_from.is_finite():
			_drag_now = e.position

func _process(delta: float) -> void:
	if not _loaded:
		return
	if PInput.just_pressed("action_b"):
		_doll = not _doll
		_select(-1)
		Probe.event("view_" + ("doll" if _doll else "walk"))
	_deco_hint.visible = _doll and _sel < 0
	if _deco_keys():
		_view()
		return
	if PInput.just_pressed("action_a") and _tour.is_empty():
		_start_tour()
	var d := PInput.dir()
	var fwd := -d.y
	var turn := -d.x
	if _drag_from.is_finite():
		# a drag works like a stick held where you put your thumb down: sideways turns,
		# up walks forward, down walks back
		var dd := (_drag_now - _drag_from) / Vector2(get_viewport_rect().size) * Vector2(640, 360)
		turn = -clampf(dd.x / 60.0, -1.0, 1.0)
		fwd = clampf(-dd.y / 50.0, -1.0, 1.0)
	# the tour drives until it is done or you touch the screen (a tap or a click stops it);
	# the move keys do not stop it, so a bot that presses action_a really walks the flat
	if not _tour.is_empty():
		var tw := _tour_step(delta)
		fwd = tw.x
		turn = tw.y
	_yaw += turn * TURN * delta
	var look := Vector2(-sin(_yaw), -cos(_yaw))
	_move(look * fwd * WALK * delta)
	_view()
	_where()

## The walker moves, then is pushed out of anything solid (a few passes for corners).
func _move(step: Vector2) -> void:
	_pos += step
	for _i in 3:
		for r: Rect2 in _blocks():
			if not r.grow(R).has_point(_pos):
				continue
			var c := Vector2(clampf(_pos.x, r.position.x, r.end.x), clampf(_pos.y, r.position.y, r.end.y))
			var away := _pos - c
			if away.length() > 0.0001:
				if away.length() < R:
					_pos = c + away.normalized() * R
			else:
				# inside the rect: out through the nearest side
				var dl := _pos.x - r.position.x
				var dr := r.end.x - _pos.x
				var du := _pos.y - r.position.y
				var dn := r.end.y - _pos.y
				var m := minf(minf(dl, dr), minf(du, dn))
				if m == dl:
					_pos.x = r.position.x - R
				elif m == dr:
					_pos.x = r.end.x + R
				elif m == du:
					_pos.y = r.position.y - R
				else:
					_pos.y = r.end.y + R

func _view() -> void:
	_ceiling.visible = not _doll
	_labels.visible = _doll
	_figure.visible = _doll
	_figure.position = Vector3(_pos.x, 0.85, _pos.y)
	if _doll:
		var size := Vector2(plan["size"][0], plan["size"][1])
		# close and steep, so a piece is big enough to put a finger on
		var dist := maxf(size.x, size.y) * 0.95
		look_from(Vector3(_pos.x * 0.3, dist, _pos.y * 0.3 + dist * 0.38), Vector3(_pos.x * 0.3, 0, _pos.y * 0.3))
	else:
		var eye := Vector3(_pos.x, EYE, _pos.y)
		var dirv := Vector3(-sin(_yaw) * cos(_pitch), sin(_pitch), -cos(_yaw) * cos(_pitch))
		look_from(eye, eye + dirv)

func _room_at(p: Vector2) -> Dictionary:
	var best := {}
	for r in plan["rooms"]:
		var rc: Array = r["rect"]
		var rr := Rect2(_w(rc[0], rc[1]), Vector2(rc[2] - rc[0], rc[3] - rc[1]))
		if rr.has_point(p):
			best = r   # later rooms win, as in the plan's grid (the shower room)
	return best

func _where() -> void:
	var r := _room_at(_pos)
	var n: String = r.get("name", "")
	if n != _room_now:
		_room_now = n
		_room_label.text = n
		if n != "":
			Probe.event("enter_" + str(r["kind"]))

## ---- the guided tour ------------------------------------------------------------

## Every room once, to its middle, in order along the flat, then back to where it began.
## The way between is found on a 20 cm grid of where the walker fits (AStarGrid2D), so the
## tour goes through doors and round the furniture by itself.
func _start_tour() -> void:
	_tour.clear()
	_make_grid()
	var here := _pos
	var rooms := []
	for r in plan["rooms"]:
		if r["kind"] in ["hall", "entrance"]:
			continue
		rooms.append(r)
	rooms.sort_custom(func(p, q): return p["label"][0] < q["label"][0])
	var from := _pos
	var stops: Array = []
	for r in rooms:
		stops.append(_w(r["label"][0], r["label"][1]))
	stops.append(here)
	for stop in stops:
		var leg := _path(from, stop)
		_tour.append_array(leg)
		if not leg.is_empty():
			from = leg[-1]
	Probe.event("tour")

const CELL := 0.2
var _grid: AStarGrid2D

func _make_grid() -> void:
	if _grid:
		return
	var size := Vector2(plan["size"][0], plan["size"][1])
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, int(ceil(size.x / CELL)), int(ceil(size.y / CELL)))
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = _off + Vector2(CELL, CELL) / 2.0
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for x in _grid.region.size.x:
		for y in _grid.region.size.y:
			var c := _grid.offset + Vector2(x, y) * CELL
			for r: Rect2 in _blocks():
				if r.grow(R + 0.02).has_point(c):
					_grid.set_point_solid(Vector2i(x, y))
					break

func _cell(p: Vector2) -> Vector2i:
	var c := Vector2i(((p - _grid.offset) / CELL).round())
	c = c.clamp(Vector2i.ZERO, _grid.region.size - Vector2i.ONE)
	if not _grid.is_point_solid(c):
		return c
	# the nearest free cell (a label point can sit right by a bed)
	for k in range(1, 8):
		for dx in range(-k, k + 1):
			for dy in range(-k, k + 1):
				var q := c + Vector2i(dx, dy)
				if _grid.region.has_point(q) and not _grid.is_point_solid(q):
					return q
	return c

func _path(a: Vector2, b: Vector2) -> Array:
	var pts := _grid.get_point_path(_cell(a), _cell(b), true)
	var out := []
	# every other point is plenty to steer by
	for i in pts.size():
		if i % 2 == 1 or i == pts.size() - 1:
			out.append(pts[i])
	return out

## Steer at the next waypoint: (forward, turn). Turns on the spot when facing away.
func _tour_step(delta: float) -> Vector2:
	var tgt: Vector2 = _tour[0]
	var to := tgt - _pos
	# a point it cannot reach (furniture in the way, or the point inside it): give up on
	# it after a while of getting no closer and go on to the next
	if to.length() < _tour_best - 0.05:
		_tour_best = to.length()
		_tour_wait = 0.0
	else:
		_tour_wait += delta
	if to.length() < 0.2 or _tour_wait > 2.5:
		_tour.pop_front()
		_tour_best = INF
		_tour_wait = 0.0
		return Vector2.ZERO
	var want := atan2(-to.x, -to.y)
	var diff := wrapf(want - _yaw, -PI, PI)
	var turn := clampf(diff * 2.0, -1.0, 1.0)
	var fwd := clampf(1.0 - absf(diff) * 1.2, 0.0, 1.0)
	return Vector2(fwd, turn)

## ---- filming (tools/record_video.sh) -----------------------------------------------

var _filming := false
var _film_t := 0.0

func film_ready() -> bool:
	if _loaded and not _filming:
		_filming = true
		_doll = true
		get_tree().create_timer(4.0).timeout.connect(func(): _doll = false)
		_start_tour()
	return _loaded

func film_mode(on: bool) -> void:
	for c in get_children():
		if c is Label and c != _room_label:
			c.visible = not on

func film_done() -> bool:
	return _filming and _tour.is_empty()

## ---- decorating ------------------------------------------------------------------
##
## In the dollhouse every piece of furniture can be moved: tap it (it lights up), drag it
## by the same amount your finger moves (never snapped to the finger), rotate it with the
## "rotate" button or space. The arrow keys nudge it 10 cm a press. A piece cannot end up
## in a wall, out of the flat or on another piece: let go there and it goes back. Tap the
## floor to put it down. In the walking view nothing is picked up.

const SNAP := 0.05
const LOW := ["chair", "plant"]   ## things the walker brushes past and pieces may overlap

var _sel := -1                    ## index into items, -1 when nothing is picked up
var _sel_mark: MeshInstance3D     ## the glow under the picked-up piece
var _hold := {}                   ## the drag of a piece: ground and centre where it began
var _rotate_btn: Button
var _deco_hint: Label

func _make_item(it: Dictionary) -> void:
	var rc: Array = it["rect"]
	var a := _w(rc[0], rc[1])
	var b := _w(rc[2], rc[3])
	var c := (a + b) / 2.0
	_org = Vector3(c.x, 0, c.y)
	_item(it)
	var node := _commit(it["name"])
	node.position = _org
	_org = Vector3.ZERO
	world.add_child(node)
	items.append({"node": node, "rect": Rect2(a, b - a), "name": it["name"],
		"solid": it["name"] not in LOW, "room": it["room"]})

## Walls, windows and rails, then the furniture that is in the way.
func _blocks() -> Array:
	var out: Array = _solid.duplicate()
	for i in items.size():
		if items[i]["solid"]:
			out.append(items[i]["rect"])
	return out

func _item_at(p: Vector2) -> int:
	# the smallest piece under the point (a chair over a rug, a lamp on a table)
	var best := -1
	var area := INF
	for i in items.size():
		var r: Rect2 = items[i]["rect"]
		if r.grow(0.05).has_point(p) and r.get_area() < area:
			best = i
			area = r.get_area()
	return best

## Where a piece may stand: inside the flat, clear of the walls, not on another piece
## (low things like chairs may tuck under a table).
func _fits(i: int, r: Rect2) -> bool:
	var inner := r.grow(-0.02)
	for p in [inner.position, inner.end, Vector2(inner.position.x, inner.end.y),
			Vector2(inner.end.x, inner.position.y), inner.get_center()]:
		if _room_at(p).is_empty():
			return false
	for w in _solid:
		if w.intersects(inner):
			return false
	if items[i]["solid"]:
		for j in items.size():
			if j != i and items[j]["solid"] and items[j]["rect"].intersects(inner):
				return false
	return true

func _select(i: int) -> void:
	_sel = i
	_hold = {}
	if _sel_mark == null:
		_sel_mark = MeshInstance3D.new()
		_sel_mark.mesh = BoxMesh.new()
		world.add_child(_sel_mark)
	_sel_mark.visible = i >= 0
	_rotate_btn.visible = i >= 0
	if i >= 0:
		Probe.event("pick_" + str(items[i]["name"]))
	_mark()

## The glow under the picked-up piece: the accent colour where it fits, the hazard
## colour where it would not.
func _mark() -> void:
	if _sel < 0:
		return
	var r: Rect2 = items[_sel]["rect"]
	var ok := _fits(_sel, r)
	_sel_mark.position = Vector3(r.get_center().x, 0.02, r.get_center().y)
	(_sel_mark.mesh as BoxMesh).size = Vector3(r.size.x + 0.12, 0.03, r.size.y + 0.12)
	_sel_mark.material_override = mat("accent" if ok else "hazard", 0.9)

func _place(i: int, center: Vector2, rot: float) -> void:
	var it: Dictionary = items[i]
	var node: Node3D = it["node"]
	var r: Rect2 = it["rect"]
	var size := r.size
	var turns := int(round((rot - node.rotation.y) / (PI / 2))) % 2
	if turns != 0:
		size = Vector2(size.y, size.x)
	node.rotation.y = rot
	node.position = Vector3(center.x, 0, center.y)
	it["rect"] = Rect2(center - size / 2.0, size)
	_grid = null   # the tour's map of where it can walk is stale now
	_mark()

## Try a move; keep it only if the piece fits there. Returns whether it moved.
func _try(i: int, center: Vector2, rot: float) -> bool:
	var node: Node3D = items[i]["node"]
	var old_c := Vector2(node.position.x, node.position.z)
	var old_r := node.rotation.y
	_place(i, center, rot)
	if _fits(i, items[i]["rect"]):
		return true
	_place(i, old_c, old_r)
	return false

func _rotate_sel() -> void:
	if _sel < 0:
		return
	var node: Node3D = items[_sel]["node"]
	var c := Vector2(node.position.x, node.position.z)
	if not _try(_sel, c, wrapf(node.rotation.y + PI / 2, -PI, PI)):
		Probe.event("rotate_blocked")
	else:
		Probe.event("rotate")

func _snap2(v: Vector2) -> Vector2:
	return (v / SNAP).round() * SNAP

## A tap in the dollhouse: on a piece picks it up (and starts dragging it), on the floor
## puts it down. Returns true when the tap was the decorator's.
func _deco_press(screen: Vector2) -> bool:
	if not _doll:
		return false
	var g := ground_point(screen)
	if not g.is_finite():
		return false
	var p := Vector2(g.x, g.z)
	var i := _item_at(p)
	if i < 0:
		if _sel >= 0:
			_select(-1)
			return true
		return false
	if i != _sel:
		_select(i)
	var node: Node3D = items[i]["node"]
	_hold = {"from": p, "center": Vector2(node.position.x, node.position.z), "rot": node.rotation.y}
	return true

func _deco_drag(screen: Vector2) -> void:
	var g := ground_point(screen)
	if not g.is_finite() or _hold.is_empty():
		return
	var c: Vector2 = _hold["center"] + (Vector2(g.x, g.z) - _hold["from"])
	_place(_sel, _snap2(c), items[_sel]["node"].rotation.y)

func _deco_release() -> void:
	if _hold.is_empty() or _sel < 0:
		return
	if not _fits(_sel, items[_sel]["rect"]):
		_place(_sel, _hold["center"], _hold["rot"])   # back where it was
		Probe.event("move_blocked")
	else:
		Probe.event("move")
	_hold = {}

## Keys while a piece is picked up: arrows nudge it, space turns it, shift puts it down.
func _deco_keys() -> bool:
	if _sel < 0 or not _doll:
		return false
	var node: Node3D = items[_sel]["node"]
	var c := Vector2(node.position.x, node.position.z)
	for k in [["move_left", Vector2(-0.1, 0)], ["move_right", Vector2(0.1, 0)],
			["move_up", Vector2(0, -0.1)], ["move_down", Vector2(0, 0.1)]]:
		if PInput.just_pressed(k[0]):
			_try(_sel, c + k[1], node.rotation.y)
	if PInput.just_pressed("action_a"):
		_rotate_sel()
	return true

func _build_deco_ui() -> void:
	_rotate_btn = Button.new()
	_rotate_btn.text = "rotate"
	_rotate_btn.position = Vector2(560, 300)
	_rotate_btn.size = Vector2(68, 30)
	_rotate_btn.visible = false
	_rotate_btn.pressed.connect(_rotate_sel)
	add_child(_rotate_btn)
	_deco_hint = Label.new()
	_deco_hint.text = "tap a piece of furniture to move it"
	_deco_hint.position = Vector2(0, 26)
	_deco_hint.size = Vector2(640, 16)
	_deco_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_deco_hint.add_theme_font_size_override("font_size", 10)
	_deco_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_deco_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_deco_hint.add_theme_constant_override("outline_size", 3)
	_deco_hint.visible = false
	add_child(_deco_hint)

func _over_own_ui(screen: Vector2) -> bool:
	return _rotate_btn != null and _rotate_btn.visible and Rect2(_rotate_btn.position, _rotate_btn.size).grow(4).has_point(screen)
