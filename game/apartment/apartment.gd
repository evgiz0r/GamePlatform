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
	_build_outside()
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
			# a low parapet, glass above it and a metal handrail on top
			box.call(0.0, 0.25, C_EXT)
			box.call(0.25, 1.02, C_GLASS, 0.01)
			box.call(1.02, 1.07, C_STEEL, 0.03)
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
	var was := _pos
	_move(look * fwd * WALK * delta)
	_bob += _pos.distance_to(was) * 7.0     # a step every ~0.9 m
	if not _riding:
		_y = _height(_pos, _y)
	if _cab and _in_lift(_pos):
		_cab.position.y = _y
	_head(delta)
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
	_above.visible = not _doll
	_labels.visible = _doll
	_figure.visible = _doll
	_figure.position = Vector3(_pos.x, _y + 0.85, _pos.y)
	if _doll:
		var size := Vector2(plan["size"][0], plan["size"][1])
		# close and steep, so a piece is big enough to put a finger on
		var dist := maxf(size.x, size.y) * 0.95
		var tz := _pos.y * 0.3 + size.y * 0.1   # a little towards the balcony, which hangs off the front
		look_from(Vector3(_pos.x * 0.3, dist, tz + dist * 0.38), Vector3(_pos.x * 0.3, 0, tz))
	else:
		var eye := Vector3(_pos.x, _y + EYE + 0.022 * sin(_bob), _pos.y)
		var hy := _yaw + _head_yaw
		var hp := _pitch + _head_pitch
		var dirv := Vector3(-sin(hy) * cos(hp), sin(hp), -cos(hy) * cos(hp))
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
	var r := _room_at(_pos) if _y > -1.0 else {}
	var n: String = r.get("name", "")
	if _in_core(_pos):
		n = "lift" if _in_lift(_pos) else "stairwell"
		r = {"kind": n}
	elif _y < -1.0:
		n = "under the building" if absf(_pos.x) < _hx and absf(_pos.y) < _hz else "street"
		r = {"kind": n.replace(" ", "_")}
	if n != _room_now:
		_room_now = n
		_room_label.text = n
		if n != "":
			Probe.event("enter_" + str(r["kind"]))

## ---- the guided tour ------------------------------------------------------------

## Every room once, to its middle, in order along the flat, then back to where it began.
## The way between is found on a 20 cm grid of where the walker fits (AStarGrid2D), so the
## tour goes through doors and round the furniture by itself.
func _start_tour(from_street := false) -> void:
	_tour.clear()
	_make_grid()
	var here := _pos
	if from_street:
		# from the pavement, under the building, through the lobby door, into the lift,
		# up to the flat's floor, across the landing and in at the front door
		var dx := _core.get_center().x
		var lift_c := _lift.get_center()
		_tour.append(Vector2(dx, _hz + 1.5))
		_tour.append(Vector2(dx, -_hz + 1.0))
		_tour.append({"look_at_point": Vector3(dx, _g0 + 1.4, -_hz), "say": "the lobby door", "t_max": 2.0})
		_tour.append(Vector2(dx, -_hz - 0.7))
		_tour.append(Vector2(lift_c.x, -_hz - 0.8))
		_tour.append(lift_c)
		_tour.append({"turn_to": PI})                     # face the lift doors (+Z)
		_tour.append({"ride": 0.0})
		_tour.append(Vector2(lift_c.x, -_hz - 0.7))
		_tour.append(Vector2(dx, -_hz - 0.7))
		_tour.append({"look_at_point": Vector3(dx, 1.2, -_hz), "say": "the front door", "t_max": 2.0})
		here = _w(plan["start"][0], plan["start"][1])
		_tour.append(here)
	var rooms := []
	for r in plan["rooms"]:
		if r["kind"] in ["hall", "entrance"]:
			continue
		rooms.append(r)
	rooms.sort_custom(func(p, q): return p["label"][0] < q["label"][0])
	# in each room, walk up to its most interesting pieces (one or two) and look at them;
	# a room with nothing worth a look gets a look round from its middle instead
	var from := here
	for r in rooms:
		var picks := []
		for i in items.size():
			if items[i]["room"] == r["kind"] and _room_at(items[i]["rect"].get_center()).get("rect", []) == r["rect"] \
					and INTEREST.get(items[i]["name"], 0) >= 2:
				picks.append(i)
		picks.sort_custom(func(p, q): return INTEREST.get(items[p]["name"], 0) > INTEREST.get(items[q]["name"], 0))
		picks = picks.slice(0, 2)
		if r["kind"] == "mirpeset":
			# out on the balcony: to the rail, and look out over the street
			var rc: Array = r["rect"]
			var at := _w((rc[0] + rc[2]) / 2.0, rc[3] - 0.55)
			var leg0 := _path(from, at)
			_tour.append_array(leg0)
			if not leg0.is_empty():
				from = leg0[-1]
			_tour.append({"view": true})
			continue
		if picks.is_empty():
			var leg := _path(from, _w(r["label"][0], r["label"][1]))
			_tour.append_array(leg)
			if not leg.is_empty():
				from = leg[-1]
			_tour.append({"look": true})
			continue
		for i in picks:
			var leg := _path(from, _stand_by(i))
			_tour.append_array(leg)
			if not leg.is_empty():
				from = leg[-1]
			_tour.append({"look_at": i})
	_tour.append_array(_path(from, here))
	Probe.event("tour")

## How much a piece is worth stopping for, and how high its middle is (where the eye goes).
const INTEREST := {"tv_unit": 5, "bed_double": 5, "sofa": 4, "dining_table": 4, "counter": 4,
	"bed_single": 4, "bathtub": 4, "wardrobe": 3, "desk": 3, "shower": 3, "fridge": 3,
	"sofa_bed": 3, "table_round": 3, "sink": 2, "lounger": 2, "plant": 2, "shelves": 2,
	"washer": 2, "toilet": 1, "coffee_table": 1, "shoe_cabinet": 1, "nightstand": 1}
const MID_H := {"bed_double": 0.5, "bed_single": 0.5, "sofa": 0.6, "sofa_bed": 0.6, "tv_unit": 0.95,
	"wardrobe": 1.2, "desk": 0.9, "counter": 1.0, "fridge": 1.1, "dining_table": 0.75,
	"bathtub": 0.5, "shower": 1.1, "toilet": 0.5, "sink": 1.0, "sink_small": 0.9, "washer": 0.6,
	"shelves": 1.0, "plant": 0.6, "table_round": 0.7, "lounger": 0.4, "coffee_table": 0.4,
	"shoe_cabinet": 0.7, "nightstand": 0.5, "chair": 0.5}

## Which way a piece faces now (decorating may have turned it), world X/Z.
func _front(i: int) -> Vector2:
	var it: Dictionary = items[i]
	var base: Vector2 = {"S": Vector2(0, 1), "N": Vector2(0, -1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}[_face_of(i)]
	var a: float = it["node"].rotation.y
	return Vector2(base.x * cos(a) + base.y * sin(a), -base.x * sin(a) + base.y * cos(a))

func _face_of(i: int) -> String:
	return items[i]["face"]

## Where a person would stand to look at a piece: a metre or so in front of it.
func _stand_by(i: int) -> Vector2:
	var r: Rect2 = items[i]["rect"]
	var f := _front(i)
	var half := absf(f.x) * r.size.x / 2.0 + absf(f.y) * r.size.y / 2.0
	# far enough back to see the whole of it: a wardrobe from 1 m filled the view
	var wide := absf(f.y) * r.size.x + absf(f.x) * r.size.y
	var p := r.get_center() + f * (half + clampf(0.9 + wide * 0.45, 1.1, 2.0))
	# not out of its room: step back towards it until inside
	for k in 8:
		if _room_at(p).get("kind", "") != "":
			break
		p -= f * 0.15
	return p

var _bob := 0.0
var _head_yaw := 0.0        ## the head, turned from where the body walks
var _head_pitch := 0.0
var _glance := -1           ## the piece the walker's eye is on while it walks past
var _glance_t := 0.0
var _glanced := {}          ## piece -> when it was last looked at (seconds of tour)
var _tour_clock := 0.0

## The head: forward while walking, turning to a piece it passes for a moment, and on a
## piece it stopped at. Damped, so it moves like a head rather than a camera.
func _head(delta: float) -> void:
	_tour_clock += delta
	var want_y := 0.0
	var want_p := 0.0
	var touring := not _tour.is_empty()
	if touring and _tour[0] is Dictionary and _tour[0].has("view"):
		var t: float = _tour[0].get("t", 0.0)
		want_p = -0.45 + 0.35 * smoothstep(1.5, 4.0, t)       # down at the street, then up
		want_y = 0.7 * sin(maxf(t - 3.0, 0.0) * 0.9)           # along it one way and the other
	elif touring and _tour[0] is Dictionary and _tour[0].has("look_at"):
		var i: int = _tour[0]["look_at"]
		var aim := _aim(i)
		want_y = wrapf(aim.x - _yaw, -PI, PI)
		want_p = aim.y
		# eyes wander a little across it
		want_y += 0.18 * sin(_tour_clock * 0.9)
	elif touring and not (_tour[0] is Dictionary):
		_glance_t -= delta
		if _glance >= 0 and _glance_t <= 0.0:
			_glanced[_glance] = _tour_clock
			_glance = -1
		if _glance < 0:
			_glance = _pick_glance()
			_glance_t = 1.6
		if _glance >= 0:
			var aim := _aim(_glance)
			var off := wrapf(aim.x - _yaw, -PI, PI)
			if absf(off) < 1.5:
				want_y = off
				want_p = aim.y
			else:
				_glanced[_glance] = _tour_clock
				_glance = -1
	if touring and _tour[0] is Dictionary and _tour[0].has("look_at_point"):
		var lp: Vector3 = _tour[0]["look_at_point"]
		want_p = atan2(lp.y - (_y + EYE), maxf(Vector2(lp.x, lp.z).distance_to(_pos), 0.3))
		_caption(-1)
		_look_label.text = "looking at " + str(_tour[0]["say"])
		_said = -3
	elif touring and _tour[0] is Dictionary and _tour[0].has("ride"):
		_caption(-1)
		_look_label.text = "going up in the lift"
		_said = -3
	elif touring and _tour[0] is Dictionary and _tour[0].has("view"):
		_caption(-1)
		if _look_label:
			_look_label.text = "looking at the street"
			_said = -3
	else:
		_caption(_tour[0]["look_at"] if touring and _tour[0] is Dictionary and _tour[0].has("look_at") \
			else (_glance if touring else -1))
	var k := 1.0 - exp(-delta * 3.0)
	_head_yaw = lerpf(_head_yaw, want_y, k)
	_head_pitch = lerpf(_head_pitch, want_p, k)

## What the eyes are on, in words, low in the middle of the view.
const SAY := {"tv_unit": "the TV", "bed_double": "the double bed", "bed_single": "a bed",
	"sofa": "the sofa", "sofa_bed": "the sofa bed", "dining_table": "the dining table",
	"counter": "the kitchen counter", "bathtub": "the bathtub", "wardrobe": "the wardrobe",
	"desk": "the desk", "shower": "the shower", "fridge": "the fridge",
	"table_round": "the balcony table", "sink": "the sink", "lounger": "a sun lounger",
	"plant": "a plant", "shelves": "the shelves", "washer": "the washing machine",
	"toilet": "the toilet", "coffee_table": "the coffee table", "shoe_cabinet": "the shoe cabinet",
	"nightstand": "the nightstand"}
var _look_label: Label
var _said := -2

func _caption(i: int) -> void:
	if _look_label == null:
		_look_label = Label.new()
		_look_label.position = Vector2(0, 300)
		_look_label.size = Vector2(640, 24)
		_look_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_look_label.add_theme_font_size_override("font_size", 16)
		_look_label.add_theme_color_override("font_color", Color(1, 1, 1))
		_look_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_look_label.add_theme_constant_override("outline_size", 5)
		add_child(_look_label)
	if i == _said:
		return
	_said = i
	_look_label.text = ("looking at " + SAY.get(items[i]["name"], items[i]["name"])) if i >= 0 else ""

## Yaw and pitch from the eye to a piece's middle.
func _aim(i: int) -> Vector2:
	var c: Vector2 = items[i]["rect"].get_center()
	var to := c - _pos
	var h: float = MID_H.get(items[i]["name"], 0.7)
	return Vector2(atan2(-to.x, -to.y), atan2(h - EYE, maxf(to.length(), 0.3)))

## Something worth a glance: near, ahead or to the side, in sight, not just looked at.
func _pick_glance() -> int:
	var best := -1
	if _y < -1.0:
		return best
	var score := 0.0
	for i in items.size():
		var w: float = INTEREST.get(items[i]["name"], 0)
		if w < 2 or _tour_clock - float(_glanced.get(i, -100.0)) < 8.0:
			continue
		var c: Vector2 = items[i]["rect"].get_center()
		var d := c.distance_to(_pos)
		if d > 4.0 or d < 0.6:
			continue
		var off := absf(wrapf(_aim(i).x - _yaw, -PI, PI))
		if off > 1.2:
			continue
		if not _in_sight(c):
			continue
		var sc := w / (1.0 + d) * (1.3 - off)
		if sc > score:
			score = sc
			best = i
	return best

func _in_sight(c: Vector2) -> bool:
	var n := int(_pos.distance_to(c) / 0.1)
	for k in range(1, n):
		var p := _pos.lerp(c, float(k) / n)
		for r: Rect2 in _solid:
			if r.has_point(p):
				return false
	return true

## The way out of a point with the most room in front of it (to look at a room from).
func _open_dir(p: Vector2) -> float:
	var best := 0.0
	var by := _yaw
	for k in 24:
		var y := k * TAU / 24
		var d := Vector2(-sin(y), -cos(y))
		var free := 0.0
		while free < 8.0:
			var hit := false
			for r: Rect2 in _solid:
				if r.has_point(p + d * free):
					hit = true
					break
			if hit:
				break
			free += 0.15
		if free > best:
			best = free
			by = y
	return by

var _look: Array = []   ## yaw marks left in a look round a room
var _look_hold := 0.0

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
			for r: Rect2 in _flat_blocks():
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
	if _tour[0] is Dictionary and _tour[0].has("ride"):
		# in the lift: the floor (and the walker) rises to the flat's level
		_riding = true
		var target: float = _tour[0]["ride"]
		_y = move_toward(_y, target, 1.3 * delta)
		if is_equal_approx(_y, target):
			_riding = false
			_tour.pop_front()
		return Vector2.ZERO
	if _tour[0] is Dictionary and _tour[0].has("turn_to"):
		var dt := wrapf(float(_tour[0]["turn_to"]) - _yaw, -PI, PI)
		if absf(dt) < 0.05:
			_tour.pop_front()
			return Vector2.ZERO
		return Vector2(0.0, clampf(dt * 1.5, -0.6, 0.6))
	if _tour[0] is Dictionary and _tour[0].has("look_at_point"):
		var lp: Vector3 = _tour[0]["look_at_point"]
		var to3 := Vector2(lp.x, lp.z) - _pos
		var dl := wrapf(atan2(-to3.x, -to3.y) - _yaw, -PI, PI)
		_tour[0]["t"] = float(_tour[0].get("t", 0.0)) + delta
		if _tour[0]["t"] > float(_tour[0].get("t_max", 2.0)):
			_tour.pop_front()
			return Vector2.ZERO
		return Vector2(0.0, clampf(dl * 1.2, -0.5, 0.5))
	if _tour[0] is Dictionary and _tour[0].has("view"):
		# at the balcony rail: face the street, look down at it, then across and along it
		_tour[0]["t"] = float(_tour[0].get("t", 0.0)) + delta
		if _tour[0]["t"] > 7.0:
			_tour.pop_front()
			return Vector2.ZERO
		var diff_v := wrapf(PI - _yaw, -PI, PI)   # +Z, the street side
		return Vector2(0.0, clampf(diff_v * 1.2, -0.5, 0.5))
	if _tour[0] is Dictionary and _tour[0].has("look_at"):
		# stopped at a piece: turn the body to it, then stand and look for a while
		var aim := _aim(_tour[0]["look_at"])
		var diff_b := wrapf(aim.x - _yaw, -PI, PI)
		_tour[0]["t"] = float(_tour[0].get("t", 0.0)) + delta
		if _tour[0]["t"] > 3.2:
			_glanced[_tour[0]["look_at"]] = _tour_clock
			_tour.pop_front()
			return Vector2.ZERO
		return Vector2(0.0, clampf(diff_b * 1.2, -0.5, 0.5))
	if _tour[0] is Dictionary:
		# looking round: turn to the most open view, then slowly left, right, and back
		if _look.is_empty() and _look_hold <= 0.0:
			var c := _open_dir(_pos)
			_look = [c, c + 1.3, c - 1.3, c]
			_look_hold = 0.01
		if _look.is_empty():
			_tour.pop_front()
			_look_hold = 0.0
			return Vector2.ZERO
		var diff_l := wrapf(float(_look[0]) - _yaw, -PI, PI)
		if absf(diff_l) < 0.03:
			_look_hold += delta
			if _look_hold > 0.6:
				_look.pop_front()
				_look_hold = 0.01
			return Vector2.ZERO
		return Vector2(0.0, clampf(diff_l * 1.5, -0.45, 0.45))
	# walking: aim at a point a little further down the path, so the view leads into the
	# next room instead of staring at the wall beside the corner
	if _tour.size() > 2 and _tour[1] is Vector2 and _tour[2] is Vector2 \
			and (_tour[0] as Vector2).distance_to(_pos) < 0.6:
		_tour.pop_front()
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
	var turn := clampf(diff * 1.6, -0.8, 0.8)
	var fwd := clampf(1.0 - absf(diff) * 1.2, 0.0, 0.85)
	return Vector2(fwd, turn)

## ---- filming (tools/record_video.sh) -----------------------------------------------

var _filming := false
var _film_t := 0.0

func film_ready() -> bool:
	if _loaded and not _filming:
		_filming = true
		_doll = false   # eye level from the first frame to the last (Evgeni: "not from the top")
		# from the street: under the building, the lobby, the lift, then the flat
		_pos = Vector2(_core.get_center().x + 2.0, _hz + 6.0)
		_y = _g0
		_yaw = 0.0
		_cab.position.y = _g0     # the lift waits on the entrance floor
		_start_tour(true)
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
	var node: Node3D
	if USE_MODELS and _furnish_model(it, a, b, c):
		node = _model_root
		_model_root = null
	else:
		_item(it)
		node = _commit(it["name"])
	node.position = _org
	_org = Vector3.ZERO
	world.add_child(node)
	items.append({"node": node, "rect": Rect2(a, b - a), "name": it["name"],
		"solid": it["name"] not in LOW, "room": it["room"], "face": it["face"], "home": c})

## ---- outside: the building below the flat and a street in front -------------------
##
## The flat is on the third floor. Below it its own building goes down to the ground; in
## front, past the balcony, a pavement with trees, a street with parked cars, and a row of
## blocks across the road; more blocks to the sides and behind. All boxes merged by colour
## (a few draws) plus a handful of Kenney trees and cars.

const FLOOR_UP := 3                ## which floor the flat is on
const STOREY := 3.0
const C_PLASTER := [Color(0.92, 0.89, 0.82), Color(0.86, 0.84, 0.80), Color(0.90, 0.86, 0.76),
	Color(0.80, 0.80, 0.78), Color(0.93, 0.91, 0.87)]
const C_ROAD := Color(0.28, 0.28, 0.30)
const C_PAVE := Color(0.70, 0.68, 0.64)
const C_WIN := Color(0.25, 0.32, 0.40)
var _above: Node3D
var _y := 0.0                     ## the floor under the walker (0 = the flat's floor)
var _riding := false
var _g0 := -9.0                   ## the street's level
var _hx := 5.0
var _hz := 5.0
var _core := Rect2()              ## the stairwell, world X/Z
var _lift := Rect2()              ## the lift car's floor
var _cab: Node3D
var _core_solid: Array = []       ## its walls, on every level
var _ground_solid: Array = []     ## the entrance floor: columns, the lobby wall (door gap)
var _mid_solid: Array = []        ## floors between: the stairwell's front wall, closed

## ---- the stairwell: landings, two flights a floor, the lift --------------------------
##
## Behind the flat, centred on its front door: 4 m wide, 5 m deep. A landing by the doors
## (1.3 m), then two flights side by side (2.5 m) to a half landing at the back (1.2 m);
## the lift beside the flights, its doors on the landing. On the entrance floor the front
## wall has the lobby's glass door; on the flat's floor it is the flat's own wall.

const CORE_W := 4.0
const CORE_D := 5.0

func _build_core(g0: float) -> void:
	var size := Vector2(plan["size"][0], plan["size"][1])
	var fd: Dictionary = {}
	for d in plan["doors"]:
		if d["style"] == "front":
			fd = d
	var dx := _w((float(fd["a"]) + float(fd["b"])) / 2.0, 0).x
	var z1 := -_hz
	var z0 := z1 - CORE_D
	var x0 := dx - CORE_W / 2.0
	var x1 := dx + CORE_W / 2.0
	_core = Rect2(x0, z0, CORE_W, CORE_D)
	var top := H + 0.1
	var wc := Color(0.88, 0.87, 0.84)
	var t := 0.2
	# outer walls: the two sides and the back, street to roof
	for r in [Rect2(x0 - t, z0 - t, t, CORE_D + t), Rect2(x1, z0 - t, t, CORE_D + t), Rect2(x0 - t, z0 - t, CORE_W + 2 * t, t)]:
		_box(Vector3(r.position.x, g0, r.position.y), Vector3(r.end.x, top, r.end.y), wc)
		_core_solid.append(r)
	_box(Vector3(x0 - t, top, z0 - t), Vector3(x1 + t, top + 0.2, z1), wc)     # its roof
	# the front wall below the flat: the lobby door on the entrance floor, closed above
	var door_w := 1.4
	_box(Vector3(x0, g0, z1 - 0.1), Vector3(dx - door_w / 2, g0 + STOREY, z1 + 0.1), wc)
	_box(Vector3(dx + door_w / 2, g0, z1 - 0.1), Vector3(x1, g0 + STOREY, z1 + 0.1), wc)
	_box(Vector3(dx - door_w / 2, g0 + 2.3, z1 - 0.1), Vector3(dx + door_w / 2, g0 + STOREY, z1 + 0.1), wc)
	_box(Vector3(dx - door_w / 2, g0, z1 - 0.03), Vector3(dx - 0.05, g0 + 2.3, z1 + 0.03), C_GLASS)
	_ground_solid.append(Rect2(x0, z1 - 0.1, dx - door_w / 2 - x0, 0.2))
	_ground_solid.append(Rect2(dx + door_w / 2, z1 - 0.1, x1 - dx - door_w / 2, 0.2))
	_box(Vector3(x0, g0 + STOREY, z1 - 0.1), Vector3(x1, -0.06, z1 + 0.1), wc)
	_mid_solid.append(Rect2(x0, z1 - 0.1, CORE_W, 0.2))
	for k in [1, 2]:    # the neighbours' front doors on the floors between
		_box(Vector3(dx - 0.45, g0 + k * STOREY, z1 - 0.12), Vector3(dx + 0.45, g0 + k * STOREY + 2.05, z1 - 0.1), C_STEEL_DOOR)
	# floors: a landing at each level, the half landings, and the flights
	var fa := Rect2(x0, z1 - 3.8, 1.15, 2.5)            # flight A: up from the landing, away
	var fb := Rect2(x0 + 1.25, z1 - 3.8, 1.15, 2.5)     # flight B: up from the half landing, back
	_stairs = {"a": fa, "b": fb, "z_front": z1 - 1.3, "run": 2.5, "x0": x0, "x1": x1, "z0": z0, "z1": z1}
	for k in FLOOR_UP + 1:
		var y := g0 + k * STOREY
		_box(Vector3(x0, y - 0.2, z1 - 1.3), Vector3(x1, y, z1), Color(0.75, 0.73, 0.70))
		if k < FLOOR_UP:
			_box(Vector3(x0, y + 1.3, z0), Vector3(x0 + 2.4, y + 1.5, z1 - 3.8), Color(0.75, 0.73, 0.70))
			for j in 9:
				var za := z1 - 1.3 - j * 2.5 / 9.0
				_box(Vector3(fa.position.x, y, za - 2.5 / 9.0), Vector3(fa.end.x, y + (j + 1) * 1.5 / 9.0, za), Color(0.80, 0.78, 0.74))
				var zb := z1 - 3.8 + j * 2.5 / 9.0
				_box(Vector3(fb.position.x, y + 1.5, zb), Vector3(fb.end.x, y + 1.5 + (j + 1) * 1.5 / 9.0, zb + 2.5 / 9.0), Color(0.80, 0.78, 0.74))
	# the wall between the flights, and a handrail on the flights' open side
	_box(Vector3(x0 + 1.15, g0, z1 - 3.8), Vector3(x0 + 1.25, top, z1 - 1.3), wc)
	_core_solid.append(Rect2(x0 + 1.15, z1 - 3.8, 0.1, 2.5))
	# the lift: a shaft beside the flights, open to the landing, and its car
	_lift = Rect2(x0 + 2.55, z1 - 3.0, x1 - x0 - 2.6, 1.65)
	for r in [Rect2(x0 + 2.4, z1 - 3.1, 0.12, 1.8), Rect2(x0 + 2.4, z1 - 3.25, x1 - x0 - 2.4, 0.15)]:
		_box(Vector3(r.position.x, g0, r.position.y), Vector3(r.end.x, top, r.end.y), Color(0.70, 0.70, 0.72))
		_core_solid.append(r)
	_core_solid.append(Rect2(x0 + 2.4, z0, x1 - x0 - 2.4, z1 - 3.25 - z0))   # dead space behind it
	world.add_child(_commit("Core"))
	_box(Vector3(_lift.position.x, -0.05, _lift.position.y), Vector3(_lift.end.x, 0.0, _lift.end.y), Color(0.55, 0.55, 0.58))
	_box(Vector3(_lift.position.x, 0.0, _lift.position.y), Vector3(_lift.end.x, 2.2, _lift.position.y + 0.05), C_STEEL)
	_box(Vector3(_lift.position.x, 2.2, _lift.position.y), Vector3(_lift.end.x, 2.25, _lift.end.y), Color(0.9, 0.9, 0.85))
	_cab = _commit("LiftCar")
	world.add_child(_cab)

var _stairs := {}

func _in_core(p: Vector2) -> bool:
	return _core.has_point(p)

func _in_lift(p: Vector2) -> bool:
	return _lift.grow(0.05).has_point(p)

## The floor's height under a point, given the height the walker is at now: the stairs
## overlap themselves floor over floor, so the nearest of the levels they could be on wins.
func _height(p: Vector2, cur: float) -> float:
	if _in_core(p) and not _stairs.is_empty():
		if _in_lift(p):
			return cur
		var cands: Array = []
		var fa: Rect2 = _stairs["a"]
		var fb: Rect2 = _stairs["b"]
		var zf: float = _stairs["z_front"]
		for k in FLOOR_UP + 1:
			var base := _g0 + k * STOREY
			if p.y >= zf:
				cands.append(base)
			elif k < FLOOR_UP:
				var tt := clampf((zf - p.y) / 2.5, 0.0, 1.0)
				if fa.has_point(p):
					cands.append(base + 1.5 * tt)
				elif fb.has_point(p):
					cands.append(base + 1.5 + 1.5 * (1.0 - tt))
				else:
					cands.append(base + 1.5)
		var best := cur
		var dbest := INF
		for c in cands:
			if absf(c - cur) < dbest:
				dbest = absf(c - cur)
				best = c
		return best
	if absf(p.x) < _hx and absf(p.y) < _hz and cur > -1.5:
		return 0.0
	return _g0

func _build_outside() -> void:
	var size := Vector2(plan["size"][0], plan["size"][1])
	var g0 := -FLOOR_UP * STOREY      # the street's level
	var hx := size.x / 2.0
	var hz := size.y / 2.0
	_g0 = g0
	_hx = hx
	_hz = hz
	var rng := RandomNumberGenerator.new()
	rng.seed = int(plan.get("seed", 1)) * 977
	# the ground, the pavements and the street in front
	_box(Vector3(-80, g0 - 0.3, -80), Vector3(80, g0, 80), Color(0.52, 0.50, 0.46))
	var street_a := hz + 4.0
	_box(Vector3(-80, g0, hz - 1.0), Vector3(80, g0 + 0.12, street_a), C_PAVE)
	_box(Vector3(-80, g0 - 0.05, street_a), Vector3(80, g0 + 0.02, street_a + 9.0), C_ROAD)
	for k in range(-40, 40):
		_box(Vector3(k * 2.0, g0 + 0.02, street_a + 4.45), Vector3(k * 2.0 + 1.0, g0 + 0.03, street_a + 4.55), Color(0.9, 0.9, 0.85))
	_box(Vector3(-80, g0, street_a + 9.0), Vector3(80, g0 + 0.12, street_a + 12.0), C_PAVE)
	# our own building: from the street up to under the flat, and two storeys over it
	# its entrance floor is open, on columns (as most Givatayim blocks are); the two floors
	# over it are other people's flats
	_block(Vector3(-hx, g0 + STOREY, -hz), Vector3(hx, -0.06, hz), C_PLASTER[0], true)
	_box(Vector3(-hx, g0 + STOREY - 0.35, -hz), Vector3(hx, g0 + STOREY, hz), C_PLASTER[0].darkened(0.1))
	var door_x := 0.0
	for d in plan["doors"]:
		if d["style"] == "front":
			door_x = _w((float(d["a"]) + float(d["b"])) / 2.0, 0).x
	for cxk in [-hx + 0.2, -hx / 3.0, hx / 3.0, hx - 0.2]:
		if absf(cxk - door_x) < 1.2:
			continue     # keep the way from the street to the lobby door clear
		for czk in [-hz + 0.2, 0.0, hz - 0.2]:
			_box(Vector3(cxk - 0.2, g0, czk - 0.2), Vector3(cxk + 0.2, g0 + STOREY - 0.35, czk + 0.2), C_PLASTER[3])
			_ground_solid.append(Rect2(cxk - 0.2, czk - 0.2, 0.4, 0.4))
	_build_core(g0)
	# neighbours beside ours, across the street and behind
	for side in [-1, 1]:
		var x0 := hx + 4.0
		var x := x0
		while x < 70.0:
			var w := rng.randf_range(12.0, 20.0)
			var h := STOREY * rng.randi_range(4, 8)
			var xa: float = side * x
			var xb: float = side * (x + w)
			_block(Vector3(minf(xa, xb), g0, -hz - 2), Vector3(maxf(xa, xb), g0 + h, hz), C_PLASTER[rng.randi() % 5], false)
			x += w + rng.randf_range(3.0, 6.0)
	var x2 := -70.0
	while x2 < 70.0:
		var w2 := rng.randf_range(12.0, 22.0)
		var h2 := STOREY * rng.randi_range(4, 9)
		_block(Vector3(x2, g0, street_a + 14.0), Vector3(x2 + w2, g0 + h2, street_a + 14.0 + rng.randf_range(12.0, 16.0)),
			C_PLASTER[rng.randi() % 5], false)
		x2 += w2 + rng.randf_range(3.0, 7.0)
	var x3 := -70.0
	while x3 < 70.0:
		var w3 := rng.randf_range(14.0, 22.0)
		var h3 := STOREY * rng.randi_range(5, 9)
		if absf(x3 + w3 / 2) > hx + 6:
			_block(Vector3(x3, g0, -hz - 22.0), Vector3(x3 + w3, g0 + h3, -hz - 8.0), C_PLASTER[rng.randi() % 5], false)
		x3 += w3 + rng.randf_range(3.0, 6.0)
	world.add_child(_commit("Outside"))
	# the two storeys over the flat: their own mesh, hidden in the dollhouse with the ceilings
	_block(Vector3(-hx, H + 0.1, -hz), Vector3(hx, H + 0.1 + 2 * STOREY, hz), C_PLASTER[0], true)
	_above = _commit("Above")
	world.add_child(_above)
	# trees along both pavements, cars parked at the kerb
	var tx := -60.0
	while tx < 60.0:
		for zz in [street_a - 1.2, street_a + 10.4]:
			var t := model("tree-large", rng.randf_range(5.0, 7.5), "friend")
			t.position = Vector3(tx + rng.randf_range(-1.0, 1.0), g0 + 0.12, zz)
			t.rotation.y = rng.randf() * TAU
			world.add_child(t)
		tx += rng.randf_range(7.0, 10.0)
	var cx := -50.0
	var cars := ["sedan", "taxi", "suv", "van", "sedan", "sedan"]
	while cx < 50.0:
		if rng.randf() < 0.7:
			var car := model(cars[rng.randi() % cars.size()], 4.3, "warn")
			car.position = Vector3(cx, g0, street_a + (1.2 if rng.randf() < 0.5 else 7.8))
			car.rotation.y = PI / 2 if car.position.z < street_a + 4 else -PI / 2
			world.add_child(car)
		cx += rng.randf_range(5.0, 7.0)

## A block of flats as a box with rows of windows and balcony slabs on its faces. `own`
## leaves the window rows off the top of our building (the flat's own windows are real).
func _block(lo: Vector3, hi: Vector3, col: Color, own: bool) -> void:
	_box(lo, hi, col)
	var floors := int((hi.y - lo.y) / STOREY)
	for f in floors:
		var y := lo.y + f * STOREY
		if f == 0 and not own:
			# the entrance floor on columns: a dark band
			_box(Vector3(lo.x + 0.4, y, lo.z + 0.4), Vector3(hi.x - 0.4, y + STOREY - 0.3, hi.z - 0.4), Color(0.35, 0.35, 0.36))
			continue
		# windows on the long faces (z), every 3.5 m, and a balcony slab now and then
		var nx := int((hi.x - lo.x) / 3.5)
		for k in nx:
			var x := lo.x + (k + 0.5) * (hi.x - lo.x) / nx
			for zf in [lo.z - 0.02, hi.z + 0.02]:
				_box(Vector3(x - 0.8, y + 0.9, zf - 0.02), Vector3(x + 0.8, y + 2.2, zf + 0.02), C_WIN)
			if k % 3 == 1:
				_box(Vector3(x - 1.8, y - 0.05, hi.z), Vector3(x + 1.8, y + 0.15, hi.z + 1.4), col.darkened(0.08))
				_box(Vector3(x - 1.8, y + 0.15, hi.z + 1.35), Vector3(x + 1.8, y + 1.05, hi.z + 1.4), Color(0.75, 0.82, 0.86, 0.5))
		var nz := int((hi.z - lo.z) / 3.5)
		for k in nz:
			var z := lo.z + (k + 0.5) * (hi.z - lo.z) / nz
			for xf in [lo.x - 0.02, hi.x + 0.02]:
				_box(Vector3(xf - 0.02, y + 0.9, z - 0.8), Vector3(xf + 0.02, y + 2.2, z + 0.8), C_WIN)
	# a roof edge
	_box(Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y + 0.6, lo.z + 0.25), col.darkened(0.1))
	_box(Vector3(lo.x, hi.y, hi.z - 0.25), Vector3(hi.x, hi.y + 0.6, hi.z), col.darkened(0.1))

## ---- real furniture (Kenney's Furniture Kit, CC0, assets/models/furniture) ----------
##
## Each plan item is one or more models fitted into its rect: stretched to the rect along
## the wall (u) and out of it (v), to a real height, and turned so the model's +Z (the side
## Kenney's pieces face) looks out of the wall. Long runs (a wardrobe, the kitchen) are a
## row of units. A missing model falls back to the boxes in _item().

const USE_MODELS := true
const FURN_DIR := "res://assets/models/furniture/"
## item -> [[model, u0, u1 (fractions of L, or a unit width in m when "tile"), v0, v1
##   (fractions of D), y0, height], ...]
const FURN := {
	"bed_double": [["bedDouble", 0, 1, 0, 1, 0.0, 0.55]],
	"bed_single": [["bedSingle", 0, 1, 0, 1, 0.0, 0.55]],
	"nightstand": [["cabinetBedDrawer", 0, 1, 0, 1, 0.0, 0.5]],
	"sofa": [["loungeSofa", 0, 1, 0, 1, 0.0, 0.85]],
	"sofa_bed": [["loungeSofa", 0, 1, 0, 1, 0.0, 0.85]],
	"wardrobe": [["tile:bookcaseClosedDoors:0.6", 0, 1, 0, 1, 0.0, 2.2]],
	"shelves": [["bookcaseOpen", 0, 1, 0, 1, 0.0, 1.8]],
	"shoe_cabinet": [["bookcaseClosedWide", 0, 1, 0, 1, 0.0, 1.0]],
	"desk": [["desk", 0, 1, 0, 1, 0.0, 0.76], ["computerScreen", 0.3, 0.7, 0.05, 0.3, 0.76, 0.45]],
	"fridge": [["kitchenFridgeLarge", 0, 1, 0, 1, 0.0, 1.85]],
	"dining_table": [["table", 0, 1, 0, 1, 0.0, 0.76]],
	"chair": [["chair", 0, 1, 0, 1, 0.0, 0.92]],
	"coffee_table": [["tableCoffee", 0, 1, 0, 1, 0.0, 0.42]],
	"tv_unit": [["cabinetTelevision", 0, 1, 0, 1, 0.0, 0.5], ["televisionModern", 0.1, 0.9, 0.1, 0.6, 0.5, 0.7]],
	"bathtub": [["bathtub", 0, 1, 0, 1, 0.0, 0.58]],
	"shower": [["shower", 0, 1, 0, 1, 0.0, 2.05]],
	"toilet": [["toilet", 0, 1, 0, 1, 0.0, 0.8]],
	"sink": [["bathroomSink", 0, 1, 0, 1, 0.0, 0.9], ["bathroomMirror", 0.15, 0.85, 0, 0.25, 1.15, 0.7]],
	"sink_small": [["bathroomSink", 0, 1, 0, 1, 0.0, 0.85]],
	"washer": [["washer", 0, 1, 0, 1, 0.0, 0.85]],
	"plant": [["pottedPlant", 0, 1, 0, 1, 0.0, 1.0]],
	"table_round": [["tableRound", 0, 1, 0, 1, 0.0, 0.74]],
	"lounger": [["loungeChairRelax", 0, 1, 0, 1, 0.0, 0.85]],
	"counter": [["kitchen", 0, 1, 0, 1, 0.0, 0.9]],
}
var _scenes := {}
var _boxes_of := {}           ## model -> its AABB at scale 1
var _model_root: Node3D

func _scene(n: String) -> PackedScene:
	if not _scenes.has(n):
		var path := FURN_DIR + n + ".glb"
		_scenes[n] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[n]

func _furnish_model(it: Dictionary, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var parts: Array = FURN.get(it["name"], [])
	if parts.is_empty():
		return false
	var face: String = it["face"]
	var L := (b.x - a.x) if face in ["S", "N"] else (b.y - a.y)
	var D := (b.y - a.y) if face in ["S", "N"] else (b.x - a.x)
	var f: Vector2 = {"S": Vector2(0, 1), "N": Vector2(0, -1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}[face]
	var rot := atan2(f.x, f.y)
	_model_root = Node3D.new()
	_model_root.name = it["name"]
	var put := func(model: String, u0: float, u1: float, v0: float, v1: float, y0: float, h: float) -> bool:
		var ps := _scene(model)
		if ps == null:
			return false
		var inst: Node3D = ps.instantiate()
		if not _boxes_of.has(model):
			_boxes_of[model] = GameMode3D.aabb_of(inst)
		var bb: AABB = _boxes_of[model]
		var sc := Vector3((u1 - u0) / maxf(bb.size.x, 0.01), h / maxf(bb.size.y, 0.01), (v1 - v0) / maxf(bb.size.z, 0.01))
		var pivot := Node3D.new()
		var mid := _local(a, b, face, (u0 + u1) / 2.0, (v0 + v1) / 2.0) - c
		pivot.position = Vector3(mid.x, y0, mid.y)
		pivot.rotation.y = rot
		inst.scale = sc
		inst.position = -Vector3(bb.get_center().x * sc.x, bb.position.y * sc.y, bb.get_center().z * sc.z)
		pivot.add_child(inst)
		_model_root.add_child(pivot)
		return true
	var ok := true
	for p in parts:
		var model: String = p[0]
		if model == "kitchen":
			ok = _kitchen_run(put, L, D, it) and ok
		elif model.begins_with("tile:"):
			var bits := model.split(":")
			var n := maxi(1, int(round(L / float(bits[2]))))
			for k in n:
				ok = put.call(bits[1], L * k / n, L * (k + 1) / n, p[3] * D, p[4] * D, p[5], p[6]) and ok
		else:
			ok = put.call(model, p[1] * L, p[2] * L, p[3] * D, p[4] * D, p[5], p[6]) and ok
	if not ok:
		_model_root.free()
		_model_root = null
	return ok

## A kitchen run: base units ~60 cm wide, the sink a third of the way along and the hob
## two thirds (like the plan's drawing), wall cupboards over it.
func _kitchen_run(put: Callable, L: float, D: float, it: Dictionary) -> bool:
	var n := maxi(1, int(round(L / 0.6)))
	var sink_k := int(n * 0.28)
	var hob_k := mini(n - 1, int(n * 0.7))
	var ok := true
	for k in n:
		var m := "kitchenCabinetDrawer" if k % 2 == 0 else "kitchenCabinet"
		if L >= 1.4 and k == sink_k:
			m = "kitchenSink"
		elif L >= 1.4 and k == hob_k:
			m = "kitchenStove"
		ok = put.call(m, L * k / n, L * (k + 1) / n, 0.0, D, 0.0, 0.92) and ok
		ok = put.call("kitchenCabinetUpper", L * k / n, L * (k + 1) / n, 0.0, minf(D, 0.35), 1.5, 0.7) and ok
	return ok

## Walls, windows and rails, then the furniture that is in the way.
func _blocks() -> Array:
	if _y < -1.0:
		# down the stairwell or at the street: the flat's walls are not on this level
		var out2: Array = _core_solid.duplicate()
		out2.append_array(_ground_solid if _y < _g0 + 1.5 else _mid_solid)
		return out2
	return _flat_blocks()

## The flat's walls and solid furniture (and the stairwell's walls, on the flat's level).
func _flat_blocks() -> Array:
	var out: Array = _solid.duplicate()
	out.append_array(_core_solid)
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
