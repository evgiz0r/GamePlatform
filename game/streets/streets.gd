extends GameMode3D
## streets -- free driving in a real city. Nothing here is made up: the roads, buildings,
## parks, trees and traffic lights come from OpenStreetMap, baked once into cities/*.json
## by tools/osm_city.py (GAME.md has the steps for adding another city). Chase cam behind
## the car. Closer to a driving sim than an arcade game: real sizes and speeds, weight,
## grip that runs out (push a corner too fast and the car runs wide), a reverse gear, and
## buildings you cannot drive through. The one game hook: every street of the city you
## drive down for the first time scores a point.
##
## Layout of this file: city data -> meshes -> the car -> camera -> autodrive -> exploring
## -> HUD (speedometer, street name, minimap, touch pedals).

const CITY := "givatayim"            ## which file in cities/ to drive
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md

## ---- the car, in real units (metres, seconds, kilograms, newtons) ----
const MASS := 1300.0
const WHEELBASE := 2.65
const CAR_LEN := 4.4
const CAR_WIDTH := 1.9
const CAR_HEIGHT := 1.55
const ENGINE_F := 5200.0             ## pull off the line, ~4 m/s^2
const POWER := 70000.0               ## then power-limited: ~150 km/h flat out
const REVERSE_F := 3000.0
const REVERSE_MAX := 6.0             ## ~22 km/h backwards
const BRAKE_F := 10500.0             ## ~8 m/s^2, a firm stop
const DRAG := 0.8                    ## 1/2 rho Cd A
const ROLL := 180.0                  ## rolling resistance
const ENGINE_BRAKE := 520.0          ## off the throttle
const MAX_STEER := 0.6               ## front wheel lock, radians (~34 degrees)
const STEER_V := 15.0                ## keyboard steering halves by this speed (m/s)
const STEER_RATE := 2.4              ## keyboard: lock to centre in ~0.4 s
const GRIP := 8.8                    ## tyres give up past ~0.9 g sideways: understeer
const CAR_R := 0.95                  ## the car is two circles of this radius...
const CAR_OFF := 1.25                ## ...this far ahead of and behind its centre
const BOUNCE := 0.15

## Drivable road kinds and the speed autodrive keeps on them (m/s): Israeli urban limits,
## 50 on through roads, 40 on residential streets. Kinds not listed are footpaths: drawn,
## not driven by autodrive, though nothing stops you mounting the pavement.
const DRIVE := {
	"motorway": 25.0, "trunk": 22.0, "primary": 13.9, "secondary": 13.9, "tertiary": 13.9,
	"unclassified": 11.1, "residential": 11.1, "living_street": 5.5, "service": 6.0,
	"road": 11.1, "motorway_link": 16.0, "trunk_link": 13.9, "primary_link": 11.1,
	"secondary_link": 11.1, "tertiary_link": 11.1, "busway": 11.1,
}
## streets that get a row of trees along each pavement (Givatayim's are lined with them,
## and OSM maps few of them one by one) -- an embellishment, see GAME.md
const TREE_ROADS := ["primary", "secondary", "tertiary", "residential", "living_street", "unclassified"]
const TREE_GAP := 11.0
const MAX_TREES := 9000
const SIGNAL_CYCLE := [              ## [seconds, phase of the E-W group, phase of N-S]
	[14.0, "g", "r"], [3.0, "y", "r"], [1.5, "r", "r"],
	[14.0, "r", "g"], [3.0, "r", "y"], [1.5, "r", "r"],
]

const SEG_CELL := 24.0               ## spatial hash cell for road segments (m)
const BLD_CELL := 24.0
const CHUNK := 320.0                 ## buildings are merged into meshes this big, for culling
const Y_AREA := 0.012
const Y_PATH := 0.022
const Y_ROAD := 0.035
const Y_MARK := 0.046
const NEW_STREET_M := 30.0           ## drive this far along a street for it to count
const MAP_R := 210.0                 ## the minimap shows this far around the car (m)

## Facades: a wall colour, a window grid per storey, a darker ground floor. UV is (metres
## along this wall, metres above the ground); UV2 is (wall length, roof height). COLOR.r is
## the building's brightness and COLOR.g how far it leans to the second wall tone.
const WALL_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 wall_a : source_color;
uniform vec4 wall_b : source_color;
uniform vec4 glass : source_color;
void fragment() {
	vec3 base = mix(wall_a.rgb, wall_b.rgb, COLOR.g) * COLOR.r;
	float along = UV.x;
	float up = UV.y;
	float len = UV2.x;
	float top = UV2.y;
	float n = floor(len / 3.3);
	float win = 0.0;
	float shade = 1.0;
	if (n >= 1.0 && up < top - 0.9) {
		float fx = fract(along / (len / n));
		if (up > 3.0) {
			float fy = fract((up - 3.0) / 3.0);
			win = step(0.2, fx) * step(fx, 0.8) * step(0.3, fy) * step(fy, 0.85);
			shade = 1.0 - 0.16 * step(fy, 0.07);
		} else {
			win = step(0.1, fx) * step(fx, 0.9) * step(up, 2.5) * 0.8;
		}
	}
	ALBEDO = mix(base * shade, glass.rgb, win);
	ROUGHNESS = mix(0.92, 0.25, win);
	SPECULAR = mix(0.2, 0.6, win);
}
"""

## Triangle soup for one merged mesh surface. Godot treats CLOCKWISE triangles as front
## faces, so tri() takes the normal the face should have and fixes the winding itself.
class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color,
			ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO, u2 := Vector2.ZERO) -> void:
		if (b - a).cross(d - a).dot(nrm) > 0.0:
			var t := b
			b = d
			d = t
			var tu := ub
			ub = ud
			ud = tu
		v.append(a)
		v.append(b)
		v.append(d)
		for i in 3:
			n.append(nrm)
			c.append(col)
			uv2.append(u2)
		uv.append(ua)
		uv.append(ub)
		uv.append(ud)

	## a flat quad on the ground (y up), corners in order around it
	func flat(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, y: float, col := Color.WHITE) -> void:
		var a := Vector3(p0.x, y, p0.y)
		var b := Vector3(p1.x, y, p1.y)
		var d := Vector3(p2.x, y, p2.y)
		var e := Vector3(p3.x, y, p3.y)
		tri(a, b, d, Vector3.UP, col)
		tri(a, d, e, Vector3.UP, col)

	func empty() -> bool:
		return v.is_empty()

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		return a

## ---- city data ----
var _city_name := ""
var _bounds := Rect2()
var _nodes := PackedVector2Array()
var _node_roads: Array = []          ## per node: Array of Vector2i(road, index along it)
var _node_r := PackedFloat32Array()  ## per node: half-width of the widest road through it
var _roads: Array = []               ## {pts, ids, w, k, o, name, en, drive, speed}
var _seg_hash := {}                  ## Vector2i cell -> Array of road * 4096 + segment
var _blds: Array = []                ## PackedVector2Array outlines, counter-clockwise
var _bld_box: Array = []             ## Rect2 per building
var _bld_solid := PackedByteArray()  ## 0 for a building raised on stilts you can drive under
var _bld_hash := {}
var _posts := PackedVector2Array()   ## round things you can hit: trees, signal poles
var _post_r := PackedFloat32Array()
var _post_hash := {}
var _boundary: Array = []            ## PackedVector2Array rings of the city limits
var _streets := {}                   ## name -> true, the named streets inside the limits
var _visited := {}
var _signals: Array = []             ## per traffic-light group: {role -> MultiMesh}
var _sig_mats: Array = []            ## [group][0 red, 1 yellow, 2 green] materials
var _sig_phase := 0
var _sig_t := 0.0

## ---- look ----
var _tone := {}
var _smat := {}                      ## tone name -> StandardMaterial3D
var _wall_mat: ShaderMaterial
var _font: Font

## ---- the car ----
var _car: Node3D
var _body: Node3D
var _wheels: Array = []              ## [node, rest rotation.y] for the two front wheels
var _pos := Vector2.ZERO
var _yaw := 0.0                      ## heading: forward is (cos, sin) on the x/z ground
var _v := 0.0                        ## forward speed, m/s (negative = backwards)
var _v_lat := 0.0
var _yaw_rate := 0.0
var _steer := 0.0                    ## front wheel angle, radians
var _steer_in := 0.0                 ## keyboard steering after the ramp, -1..1
var _gear := 1                       ## 1 drive, -1 reverse
var _rev_hold := 0.0
var _a_long := 0.0
var _roll := 0.0
var _pitch := 0.0
var _crash_cool := 0.0
var _odo := 0.0

## ---- camera ----
var _cam_yaw := 0.0
var _cam_dist := 6.5

## ---- autodrive (the bots' way in, and the seed of AI traffic later) ----
var _auto := false
var _ap_pts := PackedVector2Array()  ## the lane ahead
var _ap_v := PackedFloat32Array()    ## speed allowed at each of those points (corners)
var _ap_lim := PackedFloat32Array()  ## the limit on the road leading to each point
var _ap_end := Vector3i(-1, 0, 0)    ## the last leg planned: road, last index, direction
var _ap_stuck := 0.0
var _ap_back := 0.0

## ---- exploring ----
var _on_name := ""
var _on_m := 0.0
var _scan_t := 0.0
var _inside := true
var _inside_t := 0.0

## ---- HUD ----
var _hud: Node2D
var _map: Control
var _street_lbl: Label
var _street_en_lbl: Label
var _speed_lbl: Label
var _gear_lbl: Label
var _count_lbl: Label
var _banner: Label
var _banner_tw: Tween
var _osm_lbl: Label
var _loaded := false
var _touch_seen := false
var _touch_steer_id := -1
var _touch_steer_x0 := 0.0
var _touch_steer := 0.0
var _touch_pedal := {}               ## touch index -> "gas" / "brake"
var _sfx_was := 0.8
const AUTO_BTN := Rect2(270, 334, 100, 20)
const GAS_BTN := Rect2(560, 236, 72, 100)
const BRAKE_BTN := Rect2(480, 276, 72, 60)

func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-1500, -1300, 3000, 2600)   ## replaced by the city's real bounds

func _ready() -> void:
	title = "streets"
	super()
	Bus.palette_changed.connect(_retint_city)

func start(_config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	set_lives(0)
	_make_font()
	_tones()
	var t0 := Time.get_ticks_msec()
	if not _load_city(CITY):
		_build_hud()
		_show_banner("no city file -- see GAME.md", 30.0)
		return
	var t1 := Time.get_ticks_msec()
	world_area = _bounds
	_build_world()
	_build_car()
	_place_start()
	_build_hud()
	_retint_city()
	_loaded = true
	track3d(_car, "@")
	Probe.event("city", {"name": _city_name, "roads": _roads.size(), "buildings": _blds.size(),
		"trees": _posts.size(), "streets": _streets.size(),
		"parse_ms": t1 - t0, "build_ms": Time.get_ticks_msec() - t1})
	_show_banner(_city_name, 3.0)

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- loading the city ---------------------------------------------------------------

func _load_city(id: String) -> bool:
	var path: String = get_script().resource_path.get_base_dir() + "/cities/" + id + ".json"
	if not FileAccess.file_exists(path):
		Probe.note("no city file at %s -- bake one with tools/osm_city.py (GAME.md)" % path)
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		Probe.note("city file %s did not parse" % path)
		return false
	var k := 1.0 / float(data.get("scale", 10))
	_city_name = String(data.get("name", id))
	var b: Array = data["bounds"]
	_bounds = Rect2(b[0], b[1], float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))

	var nd: Array = data["nodes"]
	_nodes.resize(nd.size() / 2)
	for i in range(_nodes.size()):
		_nodes[i] = Vector2(nd[i * 2], nd[i * 2 + 1]) * k
	_node_roads.resize(_nodes.size())
	_node_r.resize(_nodes.size())
	for i in range(_nodes.size()):
		_node_roads[i] = []

	for rd: Dictionary in data["roads"]:
		var kind := String(rd.get("k", ""))
		if rd.has("tu"):
			continue   # tunnels are underground; there is no underground yet
		var ids := PackedInt32Array()
		var pts := PackedVector2Array()
		for n in rd["n"]:
			ids.append(int(n))
			pts.append(_nodes[int(n)])
		var r := {"pts": pts, "ids": ids, "w": float(rd.get("w", 6.0)), "k": kind,
			"o": int(rd.get("o", 0)), "l": int(rd.get("l", 0)), "name": String(rd.get("name", "")),
			"en": String(rd.get("name_en", "")), "drive": DRIVE.has(kind),
			"speed": float(DRIVE.get(kind, 5.0))}
		var ri := _roads.size()
		_roads.append(r)
		var hw: float = r["w"] * 0.5
		for j in range(ids.size()):
			(_node_roads[ids[j]] as Array).append(Vector2i(ri, j))
			if r["drive"]:
				_node_r[ids[j]] = maxf(_node_r[ids[j]], hw)
		for j in range(pts.size() - 1):
			_hash_add(_seg_hash, Rect2(pts[j], Vector2.ZERO).expand(pts[j + 1]).grow(hw), SEG_CELL, ri * 4096 + j)

	for ring: Array in data.get("boundary", []):
		var poly := PackedVector2Array()
		for i in range(0, ring.size(), 2):
			poly.append(Vector2(ring[i], ring[i + 1]) * k)
		_boundary.append(poly)
	for r: Dictionary in _roads:
		if r["drive"] and r["name"] != "" and r["k"] != "service":
			for p: Vector2 in r["pts"]:
				if _in_city(p):
					_streets[r["name"]] = true
					break

	for bd: Dictionary in data["buildings"]:
		var flat: Array = bd["p"]
		var ring := PackedVector2Array()
		for i in range(0, flat.size(), 2):
			ring.append(Vector2(flat[i], flat[i + 1]) * k)
		var h := float(bd["h"])
		if bd.has("g"):
			# a guess: vary it a storey either way so a street is not one flat wall
			h += float(posmod(_hash_i(ring[0]), 3) - 1) * 3.0
		var base := float(bd.get("b", 0.0))
		var box := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			box = box.expand(p)
		var bi := _blds.size()
		_blds.append(ring)
		_bld_box.append(box)
		_bld_solid.append(1 if base < 2.4 else 0)
		_hash_add(_bld_hash, box, BLD_CELL, bi)
		bd["_h"] = h
		bd["_ring"] = ring
		bd["_base"] = base
	_city_data = data
	return true

var _city_data: Dictionary = {}      ## the parsed file, kept only until the meshes exist

## ---- building the world ---------------------------------------------------------------

func _build_world() -> void:
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.rotation_degrees = Vector3(-50, -28, 0)
	cam.near = 0.1
	cam.far = 2200.0
	var k := 1.0 / float(_city_data.get("scale", 10))

	# the ground, well past the edges so the horizon is not a cliff
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = _bounds.size + Vector2(4000, 4000)
	pm.material = _surface("ground")
	ground.mesh = pm
	ground.position = Vector3(_bounds.get_center().x, 0.0, _bounds.get_center().y)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)

	# parks, grass, water, car parks
	var areas := {}
	for a: Dictionary in _city_data.get("areas", []):
		var kind := String(a["k"])
		var tone := "grass" if kind in ["park", "grass"] else kind
		if not areas.has(tone):
			areas[tone] = Buf.new()
		var flat: Array = a["p"]
		var ring := PackedVector2Array()
		for i in range(0, flat.size(), 2):
			ring.append(Vector2(flat[i], flat[i + 1]) * k)
		var y := Y_AREA + (0.002 if tone in ["parking", "plaza"] else 0.0)
		_fill(areas[tone], ring, y)
	for tone: String in areas:
		_add_mesh(areas[tone], _surface(tone), false)

	# roads: asphalt ribbons, with a round patch where roads meet so corners are filled
	var asphalt := Buf.new()
	var paths := Buf.new()
	var marks := Buf.new()
	for r: Dictionary in _roads:
		if r["drive"]:
			_ribbon(asphalt, r["pts"], r["w"] * 0.5, Y_ROAD)
		else:
			_ribbon(paths, r["pts"], r["w"] * 0.5, Y_PATH)
	for i in range(_nodes.size()):
		if _node_r[i] > 0.0 and (_node_roads[i] as Array).size() >= 2:
			_disc(asphalt, _nodes[i], _node_r[i] * 1.05, Y_ROAD)
	for r: Dictionary in _roads:
		_markings(marks, r)
	for ni in _city_data.get("crossings", []):
		_zebra(marks, int(ni))
	_add_mesh(paths, _surface("path"), false)
	_add_mesh(asphalt, _surface("asphalt"), false)
	_add_mesh(marks, _surface("mark"), false)

	_build_buildings()
	_build_trees()
	_build_signals()
	_city_data = {}

func _surface(tone: String) -> StandardMaterial3D:
	if _smat.has(tone):
		return _smat[tone]
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	m.metallic_specular = 0.25
	m.albedo_color = _tone.get(tone, Palette.col("warn"))
	_smat[tone] = m
	return m

func _add_mesh(buf: Buf, m: Material, shadows: bool) -> MeshInstance3D:
	if buf.empty():
		return null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, buf.arrays())
	am.surface_set_material(0, m)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi

## a polygon on the ground
func _fill(buf: Buf, ring: PackedVector2Array, y: float) -> void:
	var idx := Geometry2D.triangulate_polygon(ring)
	for i in range(0, idx.size(), 3):
		var a := ring[idx[i]]
		var b := ring[idx[i + 1]]
		var d := ring[idx[i + 2]]
		buf.tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(d.x, y, d.y), Vector3.UP, Color.WHITE)

## a strip of half-width hw along a polyline, mitred at the bends
func _ribbon(buf: Buf, pts: PackedVector2Array, hw: float, y: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(n):
		var d_in := (pts[i] - pts[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var d_out := (pts[i + 1] - pts[i]).normalized() if i < n - 1 else Vector2.ZERO
		var d := d_in + d_out
		if d.length_squared() < 0.0001:
			d = d_out if d_out != Vector2.ZERO else d_in
		d = d.normalized()
		var side := Vector2(-d.y, d.x)
		var m := 1.0
		if i > 0 and i < n - 1:
			m = 1.0 / maxf(side.dot(Vector2(-d_out.y, d_out.x)), 0.5)
		left.append(pts[i] - side * hw * m)
		right.append(pts[i] + side * hw * m)
	for i in range(n - 1):
		buf.flat(left[i], left[i + 1], right[i + 1], right[i], y)

func _disc(buf: Buf, c: Vector2, r: float, y: float) -> void:
	var seg := 14
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		buf.tri(Vector3(c.x, y, c.y), Vector3(c.x + cos(a0) * r, y, c.y + sin(a0) * r),
			Vector3(c.x + cos(a1) * r, y, c.y + sin(a1) * r), Vector3.UP, Color.WHITE)

## dashed white lines: down the middle of a two-way street, between lanes of a one-way
func _markings(buf: Buf, r: Dictionary) -> void:
	if not r["drive"] or r["k"] == "service":
		return
	var w: float = r["w"]
	var pts: PackedVector2Array = r["pts"]
	var offs: Array = []
	if r["o"] == 0:
		if w >= 6.5:
			offs = [0.0]
	else:
		var lanes: int = r["l"]
		for i in range(1, lanes):
			offs.append(-w * 0.5 + w * i / lanes)
	if offs.is_empty():
		return
	# no paint across junctions
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var clear: Array = []
	var ids: PackedInt32Array = r["ids"]
	for i in range(ids.size()):
		if (_node_roads[ids[i]] as Array).size() >= 2:
			clear.append(Vector2(cum[i], _node_r[ids[i]] + 2.5))
	var total := cum[cum.size() - 1]
	var s := 1.5
	while s + 3.0 < total:
		var ok := true
		for c: Vector2 in clear:
			if absf(s + 1.5 - c.x) < c.y + 1.5:
				ok = false
				break
		if ok:
			var a := _along(pts, cum, s)
			var b := _along(pts, cum, s + 3.0)
			var d := (b - a).normalized()
			var side := Vector2(-d.y, d.x)
			for o: float in offs:
				var oa := a + side * o
				var ob := b + side * o
				buf.flat(oa - side * 0.07, ob - side * 0.07, ob + side * 0.07, oa + side * 0.07, Y_MARK)
		s += 8.0

func _along(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in range(1, pts.size()):
		if cum[i] >= s:
			var seg := cum[i] - cum[i - 1]
			return pts[i - 1].lerp(pts[i], (s - cum[i - 1]) / maxf(seg, 0.001))
	return pts[pts.size() - 1]

## a zebra crossing over every road through a crossing node
func _zebra(buf: Buf, ni: int) -> void:
	if ni < 0 or ni >= _nodes.size():
		return
	var c := _nodes[ni]
	for e: Vector2i in _node_roads[ni]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var a := pts[maxi(e.y - 1, 0)]
		var b := pts[mini(e.y + 1, pts.size() - 1)]
		var d := (b - a).normalized()
		var side := Vector2(-d.y, d.x)
		var hw: float = r["w"] * 0.5 - 0.4
		var o := -hw
		while o < hw:
			var p := c + side * (o + 0.25)
			buf.flat(p - d * 1.5 - side * 0.25, p + d * 1.5 - side * 0.25,
				p + d * 1.5 + side * 0.25, p - d * 1.5 + side * 0.25, Y_MARK + 0.002)
			o += 1.0
		return   # one road is enough; the others through this node are its continuation

## every building: walls with a window grid (one shader), flat roofs, merged per chunk
func _build_buildings() -> void:
	_wall_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WALL_SHADER
	_wall_mat.shader = sh
	var roof := _surface("roof")
	roof.vertex_color_use_as_albedo = true
	var chunks := {}
	for bd: Dictionary in _city_data["buildings"]:
		var ring: PackedVector2Array = bd["_ring"]
		var h: float = bd["_h"]
		var base: float = bd["_base"]
		var key := _cell(_bld_box_of(ring).get_center(), CHUNK)
		if not chunks.has(key):
			chunks[key] = [Buf.new(), Buf.new()]
		var walls: Buf = chunks[key][0]
		var roofs: Buf = chunks[key][1]
		var hsh := _hash_i(ring[0])
		var bright := 0.86 + 0.16 * float(posmod(hsh, 7)) / 6.0
		var tint := 0.45 if posmod(hsh >> 3, 5) == 0 else 0.0
		var col := Color(bright, tint, 0.0)
		var n := ring.size()
		var area := 0.0
		for i in range(n):
			area += ring[i].x * ring[(i + 1) % n].y - ring[(i + 1) % n].x * ring[i].y
		var sgn := 1.0 if area > 0.0 else -1.0
		for i in range(n):
			var a := ring[i]
			var b := ring[(i + 1) % n]
			var e := b - a
			var len := e.length()
			if len < 0.05:
				continue
			var out := Vector2(e.y, -e.x).normalized() * sgn
			var nrm := Vector3(out.x, 0.0, out.y)
			var a0 := Vector3(a.x, base, a.y)
			var b0 := Vector3(b.x, base, b.y)
			var a1 := Vector3(a.x, h, a.y)
			var b1 := Vector3(b.x, h, b.y)
			var u2 := Vector2(len, h)
			walls.tri(a0, b0, b1, nrm, col, Vector2(0, base), Vector2(len, base), Vector2(len, h), u2)
			walls.tri(a0, b1, a1, nrm, col, Vector2(0, base), Vector2(len, h), Vector2(0, h), u2)
		var idx := Geometry2D.triangulate_polygon(ring)
		var rc := Color(bright * 0.95, bright * 0.95, bright * 0.95)
		for i in range(0, idx.size(), 3):
			var p0 := ring[idx[i]]
			var p1 := ring[idx[i + 1]]
			var p2 := ring[idx[i + 2]]
			roofs.tri(Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p2.x, h, p2.y), Vector3.UP, rc)
	for key: Vector2i in chunks:
		var walls: Buf = chunks[key][0]
		var roofs: Buf = chunks[key][1]
		var am := ArrayMesh.new()
		if not walls.empty():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, walls.arrays())
			am.surface_set_material(am.get_surface_count() - 1, _wall_mat)
		if not roofs.empty():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, roofs.arrays())
			am.surface_set_material(am.get_surface_count() - 1, roof)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		world.add_child(mi)

func _bld_box_of(ring: PackedVector2Array) -> Rect2:
	var box := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		box = box.expand(p)
	return box

## trees: the ones OSM knows, plus a row along each pavement of a residential street
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_city_name)
	var spots: Array = []   ## [x, z, scale]
	var k := 1.0 / float(_city_data.get("scale", 10))
	var tr: Array = _city_data.get("trees", [])
	for i in range(0, tr.size(), 2):
		var p := Vector2(tr[i], tr[i + 1]) * k
		if _tree_ok(p, 2.0):
			_add_post(p, 0.3)
			spots.append(Vector3(p.x, p.y, rng.randf_range(0.85, 1.3)))
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		if not TREE_ROADS.has(r["k"]) or spots.size() >= MAX_TREES:
			continue
		var pts: PackedVector2Array = r["pts"]
		var off: float = r["w"] * 0.5 + 1.3
		var s := rng.randf() * TREE_GAP
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			var d := (b - a) / maxf(L, 0.001)
			var side := Vector2(-d.y, d.x)
			while s < L:
				for sgn: float in [-1.0, 1.0]:
					if rng.randf() < 0.22:
						continue
					var p := a + d * s + side * off * sgn
					if _tree_ok(p, 5.0):
						_add_post(p, 0.3)
						spots.append(Vector3(p.x, p.y, rng.randf_range(0.8, 1.25)))
				s += TREE_GAP + rng.randf_range(-2.5, 2.5)
			s -= L
	if spots.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.11
	trunk.bottom_radius = 0.16
	trunk.height = 2.6
	trunk.radial_segments = 6
	trunk.rings = 1
	trunk.material = _surface("trunk")
	var crown := SphereMesh.new()
	crown.radius = 1.0
	crown.height = 2.0
	crown.radial_segments = 9
	crown.rings = 5
	var leaf := _surface("leaf")
	leaf.vertex_color_use_as_albedo = true
	crown.material = leaf
	var mt := MultiMesh.new()
	mt.transform_format = MultiMesh.TRANSFORM_3D
	mt.mesh = trunk
	mt.instance_count = spots.size()
	var mc := MultiMesh.new()
	mc.transform_format = MultiMesh.TRANSFORM_3D
	mc.use_colors = true
	mc.mesh = crown
	mc.instance_count = spots.size()
	for i in range(spots.size()):
		var sp: Vector3 = spots[i]
		var sc := sp.z
		var rot := Basis(Vector3.UP, rng.randf() * TAU)
		mt.set_instance_transform(i, Transform3D(rot.scaled(Vector3.ONE * sc), Vector3(sp.x, 1.3 * sc, sp.y)))
		var cb := rot.scaled(Vector3(2.3, 1.9, 2.3) * sc)
		mc.set_instance_transform(i, Transform3D(cb, Vector3(sp.x, 3.9 * sc, sp.y)))
		var g := rng.randf_range(0.8, 1.1)
		mc.set_instance_color(i, Color(g, g, g))
	for mm: MultiMesh in [mt, mc]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		world.add_child(mmi)

func _tree_ok(p: Vector2, spacing: float) -> bool:
	if not _bounds.has_point(p):
		return false
	var hit := _nearest_seg(p, 12.0, true)
	if not hit.is_empty() and hit["edge"] < 0.7:
		return false
	if _push_out(p, 1.1, false) != Vector2.ZERO:
		return false
	for i: int in _near(_post_hash, p, spacing, BLD_CELL):
		if _posts[i].distance_to(p) < spacing:
			return false
	return true

func _add_post(p: Vector2, r: float) -> void:
	var i := _posts.size()
	_posts.append(p)
	_post_r.append(r)
	_hash_add(_post_hash, Rect2(p, Vector2.ZERO).grow(r), BLD_CELL, i)

## a traffic light on the right of every way into a signalled junction, in two groups by
## direction so crossing streets take turns
func _build_signals() -> void:
	var poles: Array = []
	var heads: Array = []
	var bulbs: Array = [[[], [], []], [[], [], []]]
	for ni in _city_data.get("signals", []):
		var node := int(ni)
		if node < 0 or node >= _nodes.size():
			continue
		var c := _nodes[node]
		var rn := _node_r[node]
		for e: Vector2i in _node_roads[node]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [-1, 1]:
				var from := e.y + d2
				if from < 0 or from >= pts.size():
					continue
				# arriving from `from` means travelling in direction -d2 along the road
				if r["o"] != 0 and r["o"] != -d2:
					continue
				var dir := (c - pts[from]).normalized()
				var right := Vector2(-dir.y, dir.x)
				var p := c - dir * (rn + 1.5) + right * (float(r["w"]) * 0.5 + 0.8)
				if _push_out(p, 0.3, false) != Vector2.ZERO:
					continue
				var g := 0 if absf(dir.x) >= absf(dir.y) else 1
				var face := Basis(Vector3.UP, atan2(-dir.x, -dir.y))   # +Z of the head toward the traffic
				poles.append(Transform3D(Basis(), Vector3(p.x, 1.7, p.y)))
				heads.append(Transform3D(face, Vector3(p.x, 3.3, p.y)))
				var front := Vector3(-dir.x, 0.0, -dir.y) * 0.17
				for ci in range(3):
					bulbs[g][ci].append(Vector3(p.x, 3.3 + 0.3 - 0.3 * ci, p.y) + front)
				_add_post(p, 0.15)
	if poles.is_empty():
		return
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 3.4
	pole_mesh.radial_segments = 6
	pole_mesh.material = _surface("pole")
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.34, 1.0, 0.3)
	head_mesh.material = _surface("pole")
	_multi(pole_mesh, poles)
	_multi(head_mesh, heads)
	var bulb := SphereMesh.new()
	bulb.radius = 0.11
	bulb.height = 0.22
	bulb.radial_segments = 8
	bulb.rings = 4
	_sig_mats = []
	for g in range(2):
		var mats: Array = []
		for ci in range(3):
			var m := StandardMaterial3D.new()
			m.roughness = 0.4
			mats.append(m)
			var ts: Array = []
			for p: Vector3 in bulbs[g][ci]:
				ts.append(Transform3D(Basis(), p))
			if not ts.is_empty():
				var mi := _multi(bulb, ts)
				mi.material_override = m
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sig_mats.append(mats)
	_apply_signals()

func _multi(mesh: Mesh, xforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	world.add_child(mi)
	return mi

func _signals_tick(dt: float) -> void:
	if _sig_mats.is_empty():
		return
	_sig_t += dt
	var step: Array = SIGNAL_CYCLE[_sig_phase]
	if _sig_t >= float(step[0]):
		_sig_t = 0.0
		_sig_phase = (_sig_phase + 1) % SIGNAL_CYCLE.size()
		_apply_signals()

func _apply_signals() -> void:
	var step: Array = SIGNAL_CYCLE[_sig_phase]
	var roles := ["hazard", "warn", "friend"]
	var keys := ["r", "y", "g"]
	for g in range(_sig_mats.size()):
		for ci in range(3):
			var m: StandardMaterial3D = _sig_mats[g][ci]
			var on: bool = step[1 + g] == keys[ci]
			var col := Palette.col(roles[ci])
			m.albedo_color = col if on else col.lerp(Palette.col("bg"), 0.8)
			m.emission_enabled = on
			m.emission = col
			m.emission_energy_multiplier = 2.2

## ---- look: every colour is a palette role, mixed for daylight ---------------------------

func _tones() -> void:
	var bg := Palette.col("bg")
	var alt := Palette.col("bg_alt")
	var ink := Palette.col("ink")
	var pl := Palette.col("player")
	var fr := Palette.col("friend")
	var wn := Palette.col("warn")
	var ac := Palette.col("accent")
	var pz := Palette.col("prize")
	_tone = {
		"ground": alt.lerp(ink, 0.42),
		"path": alt.lerp(ink, 0.62),
		"asphalt": alt.lerp(ink, 0.2),
		"parking": alt.lerp(ink, 0.32),
		"plaza": alt.lerp(ink, 0.58).lerp(wn, 0.08),
		"grass": fr.lerp(bg, 0.48),
		"pitch": fr.lerp(bg, 0.36),
		"wood": fr.lerp(bg, 0.6),
		"water": pl.lerp(bg, 0.42),
		"mark": ink,
		"wall": ink.lerp(wn, 0.1),
		"wall2": ink.lerp(ac, 0.28),
		"glass": alt.lerp(pl, 0.3),
		"roof": ink.lerp(alt, 0.42),
		"leaf": fr.lerp(bg, 0.52),
		"trunk": alt.lerp(wn, 0.3),
		"pole": alt.lerp(ink, 0.3),
		"sky": pl.lerp(pz, 0.35).lerp(bg, 0.32),
		"haze": ink.lerp(pl, 0.3),
	}

func _retint_city() -> void:
	_tones()
	for t: String in _smat:
		(_smat[t] as StandardMaterial3D).albedo_color = _tone[t]
	if _wall_mat != null:
		_wall_mat.set_shader_parameter("wall_a", _tone["wall"])
		_wall_mat.set_shader_parameter("wall_b", _tone["wall2"])
		_wall_mat.set_shader_parameter("glass", _tone["glass"])
	if env != null:
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = _tone["sky"]
		sky.sky_horizon_color = _tone["haze"]
		sky.ground_horizon_color = _tone["haze"]
		sky.ground_bottom_color = _tone["ground"]
		sky.sky_curve = 0.12
		env.background_color = _tone["haze"]
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = _tone["haze"]
		env.ambient_light_energy = 0.55
		env.fog_enabled = true
		env.fog_light_color = _tone["haze"]
		env.fog_density = 0.0014
		env.fog_sky_affect = 0.0
	if sun != null:
		sun.light_color = Palette.col("ink").lerp(Palette.col("warn"), 0.12)
		sun.light_energy = 1.05
	_apply_signals_safe()
	_retint_hud()

func _apply_signals_safe() -> void:
	if not _sig_mats.is_empty():
		_apply_signals()

## ---- the car ------------------------------------------------------------------------------

func _build_car() -> void:
	_car = Node3D.new()
	_car.name = "car"
	world.add_child(_car)
	_body = Node3D.new()
	_car.add_child(_body)
	var m := model("sedan", CAR_LEN, "player")
	# the kit's car is a stubby toy; stretch it to a real car's proportions
	var aabb: AABB = m.get_meta("aabb")
	m.scale = Vector3(CAR_WIDTH / maxf(aabb.size.x, 0.01), CAR_HEIGHT / maxf(aabb.size.y, 0.01), 1.0)
	_body.add_child(m)
	for nm: String in ["wheel-front-left", "wheel-front-right"]:
		var w := m.find_child(nm, true, false) as Node3D
		if w != null:
			_wheels.append([w, w.rotation.y])

func _fwd() -> Vector2:
	return Vector2(cos(_yaw), sin(_yaw))

## start on a through road near the middle of town, in the right-hand lane
func _place_start() -> void:
	var mid := _bounds.get_center()
	if not _boundary.is_empty():
		var box := Rect2((_boundary[0] as PackedVector2Array)[0], Vector2.ZERO)
		for ring: PackedVector2Array in _boundary:
			for p in ring:
				box = box.expand(p)
		mid = box.get_center()
	var best := INF
	var at := mid
	var dir := Vector2.RIGHT
	for r: Dictionary in _roads:
		if not r["drive"] or not (r["k"] in ["primary", "secondary", "tertiary"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var L := pts[j].distance_to(pts[j + 1])
			if L < 25.0:
				continue
			var c := (pts[j] + pts[j + 1]) * 0.5
			var d := c.distance_to(mid)
			if d < best:
				best = d
				dir = (pts[j + 1] - pts[j]).normalized()
				if r["o"] == -1:
					dir = -dir
				var lane := 0.0 if r["o"] != 0 else minf(float(r["w"]) * 0.25, 1.8)
				at = c + Vector2(-dir.y, dir.x) * lane
	_pos = at
	_yaw = dir.angle()
	_cam_yaw = _yaw
	_place_car(0.016)
	_camera(1.0)

func _physics_process(dt: float) -> void:
	if not _loaded or finished:
		return
	_signals_tick(dt)
	_crash_cool = maxf(0.0, _crash_cool - dt)
	if PInput.just_pressed("action_a") and not _auto:
		_set_auto(true)
	elif PInput.just_pressed("action_b") and _auto:
		_set_auto(false)
	var ctl: Array = _autodrive(dt) if _auto else _manual(dt)
	_drive(dt, ctl[0], ctl[1], ctl[2])
	_explore(dt)
	_camera(dt)
	_tick_hud()

## keys and touch -> [throttle, brake, wheel angle]. Down brakes, and once stopped, holding
## it selects reverse; then down drives backwards and up brakes, like a real automatic.
func _manual(dt: float) -> Array:
	var steer_t := PInput.axis("move_left", "move_right")
	var up := 1.0 if PInput.pressed("move_up") else 0.0
	var down := 1.0 if PInput.pressed("move_down") else 0.0
	for id in _touch_pedal:
		if _touch_pedal[id] == "gas":
			up = 1.0
		else:
			down = 1.0
	if _touch_steer_id >= 0:
		_steer_in = _touch_steer
	else:
		var rate := STEER_RATE if absf(steer_t) > 0.0 and signf(steer_t) == signf(_steer_in) else STEER_RATE * 1.8
		_steer_in = move_toward(_steer_in, steer_t, rate * dt)
	var lock := MAX_STEER / (1.0 + pow(absf(_v) / STEER_V, 2.0))
	var throttle := 0.0
	var brake := 0.0
	if _gear > 0:
		throttle = up
		brake = down
		if down > 0.0 and up == 0.0 and _v < 0.4:
			_rev_hold += dt
			if _rev_hold > 0.3:
				_gear = -1
				Probe.event("reverse")
		else:
			_rev_hold = 0.0
	else:
		throttle = down
		brake = up
		if up > 0.0 and down == 0.0 and _v > -0.4:
			_gear = 1
	return [throttle, brake, _steer_in * lock]

func _drive(dt: float, throttle: float, brake: float, steer: float) -> void:
	_steer = steer
	var v := _v
	var f := 0.0
	if _gear > 0:
		f = throttle * minf(ENGINE_F, POWER / maxf(absf(v), 0.1))
	elif v > -REVERSE_MAX:
		f = -throttle * REVERSE_F
	var resist := DRAG * v * absf(v) + ROLL * signf(v)
	if throttle <= 0.01:
		resist += ENGINE_BRAKE * signf(v)
	var nv := v + (f - resist) / MASS * dt
	if v != 0.0 and signf(nv) != signf(v) and throttle <= 0.01:
		nv = 0.0   # resistance stops you; it never pushes you backwards
	nv = move_toward(nv, 0.0, brake * BRAKE_F / MASS * dt)
	_a_long = (nv - v) / dt
	_v = nv
	_odo += absf(_v) * dt
	# bicycle model turning about the rear axle, capped by what the tyres can hold
	var want := _v * tan(_steer) / WHEELBASE
	var cap := GRIP / maxf(absf(_v), 1.0)
	want = clampf(want, -cap, cap)
	_yaw_rate = lerpf(_yaw_rate, want, 1.0 - exp(-dt * 10.0))
	_yaw = wrapf(_yaw + _yaw_rate * dt, -PI, PI)
	_v_lat *= exp(-dt * 5.0)
	var fwd := _fwd()
	var right := Vector2(-fwd.y, fwd.x)
	_pos += (fwd * _v + right * (_v_lat + _yaw_rate * WHEELBASE * 0.5)) * dt
	_collide()
	var edge := _bounds.grow(-8.0)
	if not edge.has_point(_pos):
		_pos = _pos.clamp(edge.position, edge.end)
		_v *= 0.5
	_place_car(dt)

func _place_car(dt: float) -> void:
	_car.position = Vector3(_pos.x, 0.0, _pos.y)
	_car.rotation.y = PI * 0.5 - _yaw
	var k := 1.0 - exp(-dt * 6.0)
	_roll = lerpf(_roll, clampf(-_v * _yaw_rate * 0.006, -0.07, 0.07), k)
	_pitch = lerpf(_pitch, clampf(-_a_long * 0.005, -0.05, 0.05), k)
	_body.rotation = Vector3(_pitch, 0.0, _roll)
	for w: Array in _wheels:
		(w[0] as Node3D).rotation.y = float(w[1]) - _steer

## ---- collisions: the car's two circles against building outlines and posts -------------

func _collide() -> void:
	var fwd := _fwd()
	var total := Vector2.ZERO
	for off: float in [CAR_OFF, -CAR_OFF]:
		var p := _push_out(_pos + fwd * off, CAR_R, true)
		if p != Vector2.ZERO:
			total += p
			_pos += p
	if total == Vector2.ZERO:
		return
	var n := total.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var vel := fwd * _v + right * _v_lat
	var vn := vel.dot(n)
	if vn < 0.0:
		vel -= n * vn * (1.0 + BOUNCE)
		vel *= 0.94
		_crash(-vn)
	_v = vel.dot(fwd)
	_v_lat = clampf(vel.dot(right), -4.0, 4.0)

func _crash(speed: float) -> void:
	if speed < 1.2 or _crash_cool > 0.0:
		return
	_crash_cool = 0.4
	if speed > 9.0:
		hit3d(minf(8.0, speed * 0.35))
		Audio.play("impact_metal")
	elif speed > 4.0:
		shake3d(speed * 0.4)
		Audio.play("impact_punch")
	else:
		shake3d(1.0)
		Audio.play("impact_soft", 0.1, -6.0)
	Probe.event("crash", {"kmh": int(speed * 3.6)})

## how far to move a circle so it overlaps nothing solid
func _push_out(c: Vector2, r: float, posts: bool) -> Vector2:
	var push := Vector2.ZERO
	for i: int in _near(_bld_hash, c, r, BLD_CELL):
		if _bld_solid[i] == 0:
			continue
		var box: Rect2 = _bld_box[i]
		if not box.grow(r).has_point(c + push):
			continue
		push += _poly_push(_blds[i], c + push, r)
	if posts:
		for i: int in _near(_post_hash, c, r, BLD_CELL):
			var d := (c + push) - _posts[i]
			var need := r + _post_r[i]
			if d.length() < need:
				push += d.normalized() * (need - d.length()) if d.length() > 0.001 else Vector2(need, 0)
	return push

func _poly_push(poly: PackedVector2Array, c: Vector2, r: float) -> Vector2:
	var best := INF
	var q := c
	var n := poly.size()
	for i in range(n):
		var p := Geometry2D.get_closest_point_to_segment(c, poly[i], poly[(i + 1) % n])
		var d := c.distance_squared_to(p)
		if d < best:
			best = d
			q = p
	best = sqrt(best)
	if Geometry2D.is_point_in_polygon(c, poly):
		var out := q - c
		return out + out.normalized() * r if best > 0.001 else Vector2(r, 0)
	if best < r:
		return (c - q) / maxf(best, 0.001) * (r - best)
	return Vector2.ZERO

## ---- spatial hashes -------------------------------------------------------------------------

func _cell(p: Vector2, size: float) -> Vector2i:
	return Vector2i(floori(p.x / size), floori(p.y / size))

func _hash_add(h: Dictionary, box: Rect2, size: float, item: int) -> void:
	var a := _cell(box.position, size)
	var b := _cell(box.end, size)
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			var key := Vector2i(cx, cz)
			if h.has(key):
				(h[key] as Array).append(item)
			else:
				h[key] = [item]

## every item whose cells touch the square of radius r round p, once each
func _near(h: Dictionary, p: Vector2, r: float, size: float) -> Array:
	var a := _cell(p - Vector2(r, r), size)
	var b := _cell(p + Vector2(r, r), size)
	if a == b:
		return h.get(a, [])
	var seen := {}
	for cx in range(a.x, b.x + 1):
		for cz in range(a.y, b.y + 1):
			for i: int in h.get(Vector2i(cx, cz), []):
				seen[i] = true
	return seen.keys()

## the closest road segment to p within max_d: {road, seg, q (closest point), edge (metres
## past the asphalt's edge, negative when on it)}; {} when there is none
func _nearest_seg(p: Vector2, max_d: float, drivable: bool) -> Dictionary:
	var best := {}
	var bd := INF
	for code: int in _near(_seg_hash, p, max_d, SEG_CELL):
		var ri := code / 4096
		var sj := code % 4096
		var r: Dictionary = _roads[ri]
		if drivable and not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var q := Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1])
		var edge := p.distance_to(q) - float(r["w"]) * 0.5
		if edge < bd:
			bd = edge
			best = {"road": ri, "seg": sj, "q": q, "edge": edge}
	return best

func _hash_i(v: Vector2) -> int:
	return absi((int(v.x * 7.0) * 73856093) ^ (int(v.y * 7.0) * 19349663))

func _in_city(p: Vector2) -> bool:
	if _boundary.is_empty():
		return true
	for ring: PackedVector2Array in _boundary:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false

## ---- camera: a chase cam that swings wide on turns and never sits inside a building -----

func _camera(dt: float) -> void:
	_cam_yaw = lerp_angle(_cam_yaw, _yaw, 1.0 - exp(-dt * 3.0))
	var back := Vector2(cos(_cam_yaw), sin(_cam_yaw))
	var spd := clampf(absf(_v) / 30.0, 0.0, 1.0)
	var want := lerpf(6.3, 7.8, spd)
	var clear := _clear_behind(_pos, -back, want)
	_cam_dist = clear if clear < _cam_dist else lerpf(_cam_dist, clear, 1.0 - exp(-dt * 1.5))
	var d := _cam_dist
	var eye := Vector3(_pos.x - back.x * d, 2.0 + d * 0.14, _pos.y - back.y * d)
	var at := Vector3(_pos.x + back.x * 4.0, 1.0, _pos.y + back.y * 4.0)
	look_from(eye, at)
	cam.fov = lerpf(64.0, 74.0, spd)

func _clear_behind(from: Vector2, dir: Vector2, want: float) -> float:
	var s := 1.0
	while s <= want + 0.6:
		var p := from + dir * s
		for i: int in _near(_bld_hash, p, 0.1, BLD_CELL):
			var box: Rect2 = _bld_box[i]
			if box.has_point(p) and Geometry2D.is_point_in_polygon(p, _blds[i]):
				return maxf(2.2, s - 0.8)
		s += 0.5
	return want

## ---- autodrive: follow the road graph in the right-hand lane, preferring new streets ----

func _set_auto(on: bool) -> void:
	_auto = on
	_ap_pts = PackedVector2Array()
	_ap_v = PackedFloat32Array()
	_ap_lim = PackedFloat32Array()
	_ap_stuck = 0.0
	_ap_back = 0.0
	if on:
		_gear = 1
	Probe.event("autodrive", {"on": on})
	_show_banner("autodrive" if on else "you drive", 1.2)

func _autodrive(dt: float) -> Array:
	if _ap_back > 0.0:     # stuck against something: back off, then plan again
		_ap_back -= dt
		_gear = -1
		if _ap_back <= 0.0:
			_gear = 1
			_ap_pts = PackedVector2Array()
		return [0.7, 0.0, -signf(_steer) * MAX_STEER * 0.6]
	if _ap_pts.size() < 2 or _pos.distance_to(_ap_pts[0]) > 30.0:
		_ap_plan()
		if _ap_pts.size() < 2:
			return [0.0, 1.0, 0.0]
	# forget what is behind
	while _ap_pts.size() > 2:
		var a := _ap_pts[0]
		var seg := _ap_pts[1] - a
		if (_pos - a).dot(seg) / maxf(seg.length_squared(), 0.001) > 1.0:
			_ap_pts.remove_at(0)
			_ap_v.remove_at(0)
			_ap_lim.remove_at(0)
		else:
			break
	while _ap_len() < 160.0:
		if not _ap_next():
			break
	# pure pursuit on a point ahead of the rear axle
	var fwd := _fwd()
	var rear := _pos - fwd * WHEELBASE * 0.5
	var look := clampf(4.0 + absf(_v) * 0.6, 6.0, 18.0)
	var tgt := _ap_point_ahead(look)
	var to := tgt - rear
	var alpha := fwd.angle_to(to)
	var steer := clampf(atan(2.0 * WHEELBASE * sin(alpha) / maxf(to.length(), 1.0)), -MAX_STEER, MAX_STEER)
	# keep the limit, and slow for the corners ahead: at most the speed from which each
	# one can still be braked down to in time
	var vt: float = _ap_lim[1]
	var dist := 0.0
	var p := _pos
	for i in range(1, _ap_pts.size()):
		dist += p.distance_to(_ap_pts[i])
		p = _ap_pts[i]
		if dist > 90.0:
			break
		vt = minf(vt, sqrt(_ap_v[i] * _ap_v[i] + 2.0 * 2.6 * dist))
	var err := vt - _v
	var throttle := clampf(err * 0.35, 0.0, 1.0)
	var brake := clampf(-err * 0.25, 0.0, 1.0) if err < -0.3 else 0.0
	if throttle > 0.3 and absf(_v) < 0.4:
		_ap_stuck += dt
		if _ap_stuck > 2.0:
			_ap_stuck = 0.0
			_ap_back = 1.4
			Probe.event("autodrive_stuck")
	else:
		_ap_stuck = 0.0
	return [throttle, brake, steer]

func _ap_len() -> float:
	var L := 0.0
	for i in range(1, _ap_pts.size()):
		L += _ap_pts[i - 1].distance_to(_ap_pts[i])
	return L

func _ap_point_ahead(look: float) -> Vector2:
	var p := Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[0], _ap_pts[1])
	var left := look
	for i in range(1, _ap_pts.size()):
		var nxt := _ap_pts[i]
		var L := p.distance_to(nxt)
		if L >= left:
			return p + (nxt - p) * (left / maxf(L, 0.001))
		left -= L
		p = nxt
	return p

func _ap_plan() -> void:
	_ap_pts = PackedVector2Array()
	_ap_v = PackedFloat32Array()
	_ap_lim = PackedFloat32Array()
	var hit := _nearest_seg(_pos, 60.0, true)
	if hit.is_empty():
		return
	var ri: int = hit["road"]
	var sj: int = hit["seg"]
	var r: Dictionary = _roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var dir := 1 if (pts[sj + 1] - pts[sj]).dot(_fwd()) >= 0.0 else -1
	if r["o"] != 0:
		dir = r["o"]
	_ap_pts.append(hit["q"])
	_ap_v.append(float(r["speed"]))
	_ap_lim.append(float(r["speed"]))
	_ap_leg(ri, sj + 1 if dir > 0 else sj, dir)

## append a road from index `from` to its end in direction `dir`, offset into the lane
func _ap_leg(ri: int, from: int, dir: int) -> void:
	var r: Dictionary = _roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var lane := 0.0
	if r["o"] == 0 and float(r["w"]) >= 5.0:
		lane = minf(float(r["w"]) * 0.25, 1.9)
	var last := pts.size() - 1 if dir > 0 else 0
	var i := from
	var start := _ap_pts.size()
	while true:
		var prv := pts[i - dir] if (i - dir >= 0 and i - dir < pts.size()) else pts[i]
		var nxt := pts[i + dir] if (i + dir >= 0 and i + dir < pts.size()) else pts[i]
		var d := (nxt - prv).normalized()
		if d == Vector2.ZERO:
			d = _fwd()
		_ap_pts.append(pts[i] + Vector2(-d.y, d.x) * lane)
		_ap_v.append(float(r["speed"]))
		_ap_lim.append(float(r["speed"]))
		if i == last:
			break
		i += dir
	_ap_end = Vector3i(ri, last, dir)
	# corners: the sharper the bend, the slower
	for k in range(maxi(1, start - 1), _ap_pts.size() - 1):
		var a := (_ap_pts[k] - _ap_pts[k - 1]).normalized()
		var b := (_ap_pts[k + 1] - _ap_pts[k]).normalized()
		var turn := absf(a.angle_to(b))
		if turn > 0.15:
			_ap_v[k] = minf(_ap_v[k], lerpf(_ap_v[k], 3.5, clampf((turn - 0.15) / 1.3, 0.0, 1.0)))

## at the end of the planned road pick the next one: ahead rather than a turn, a street
## not driven yet rather than an old one, never against a one-way, U-turn only at a dead end
func _ap_next() -> bool:
	if _ap_end.x < 0:
		return false
	var r: Dictionary = _roads[_ap_end.x]
	var pts: PackedVector2Array = r["pts"]
	var ei := _ap_end.y
	var dir := _ap_end.z
	var node: int = (r["ids"] as PackedInt32Array)[ei]
	var prev := ei - dir
	if prev < 0 or prev >= pts.size():
		prev = ei
	var came := (pts[ei] - pts[prev]).normalized()
	var best := Vector3i(-1, 0, 0)
	var back := Vector3i(-1, 0, 0)
	var best_score := -INF
	for e: Vector2i in _node_roads[node]:
		var r2: Dictionary = _roads[e.x]
		if not r2["drive"]:
			continue
		var p2: PackedVector2Array = r2["pts"]
		for d2: int in [1, -1]:
			var nxt := e.y + d2
			if nxt < 0 or nxt >= p2.size():
				continue
			if r2["o"] != 0 and r2["o"] != d2:
				continue
			var go := (p2[nxt] - p2[e.y]).normalized()
			if e.x == _ap_end.x and nxt == prev:
				back = Vector3i(e.x, nxt, d2)
				continue
			var c := came.dot(go)
			if c < -0.7:
				continue
			var score := c * 1.2 + randf()
			if r2["name"] != "" and not _visited.has(r2["name"]):
				score += 1.4
			if r2["k"] == "service":
				score -= 1.5
			if score > best_score:
				best_score = score
				best = Vector3i(e.x, nxt, d2)
	if best.x < 0:
		best = back
	if best.x < 0:
		return false
	_ap_leg(best.x, best.y, best.z)
	return true

## ---- exploring: a point for every street of the city you drive down -----------------------

func _explore(dt: float) -> void:
	_on_m += absf(_v) * dt
	_scan_t -= dt
	if _scan_t > 0.0:
		return
	_scan_t = 0.15
	var hit := _nearest_seg(_pos, 14.0, true)
	var nm := ""
	var en := ""
	if not hit.is_empty() and float(hit["edge"]) < 1.5:
		var r: Dictionary = _roads[hit["road"]]
		nm = r["name"]
		en = r["en"]
	if nm != _on_name:
		_on_name = nm
		_on_m = 0.0
		_street_lbl.text = nm
		_street_en_lbl.text = en if en != nm else ""
	if nm != "" and _on_m >= NEW_STREET_M and _streets.has(nm) and not _visited.has(nm):
		_visited[nm] = true
		add_score(1)
		Audio.play("coin", 0.05, -4.0)
		Probe.event("new_street", {"n": _visited.size()})
		_show_banner("+ " + nm, 1.6)
		_count_lbl.text = "streets %d / %d" % [_visited.size(), _streets.size()]
	_inside_t -= 0.15
	if _inside_t <= 0.0 and not _boundary.is_empty():
		_inside_t = 0.6
		var now := _in_city(_pos)
		if now != _inside:
			_inside = now
			_show_banner(("welcome to " if now else "leaving ") + _city_name, 2.2)
			Probe.event("city_limits", {"inside": now})

## ---- HUD ---------------------------------------------------------------------------------

func _make_font() -> void:
	var base: Font = ThemeDB.fallback_font
	var he: Font = load(get_script().resource_path.get_base_dir() + "/fonts/NotoSansHebrew-SemiBold.woff2")
	if he == null:
		_font = base
		return
	var f := FontVariation.new()
	f.base_font = base
	var fb: Array[Font] = [he]
	f.fallbacks = fb
	_font = f

func _label(size: int, role: String) -> Label:
	var l := UIKit.label("", size, role)
	l.add_theme_font_override("font", _font)
	l.add_theme_color_override("font_outline_color", Palette.col("bg"))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("role", role)
	_hud.add_child(l)
	return l

func _build_hud() -> void:
	_hud = Node2D.new()
	_hud.z_index = 50
	add_child(_hud)
	_hud.draw.connect(_draw_hud)
	_street_lbl = _label(17, "ink")
	_street_lbl.position = Vector2(170, 2)
	_street_lbl.size = Vector2(300, 26)
	_street_en_lbl = _label(10, "ink")
	_street_en_lbl.position = Vector2(170, 26)
	_street_en_lbl.size = Vector2(300, 14)
	_count_lbl = _label(11, "ink")
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_count_lbl.position = Vector2(10, 32)
	_count_lbl.text = "streets 0 / %d" % _streets.size()
	_speed_lbl = _label(30, "ink")
	_speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_lbl.position = Vector2(500, 300)
	_speed_lbl.size = Vector2(100, 40)
	_gear_lbl = _label(16, "warn")
	_gear_lbl.position = Vector2(604, 312)
	_gear_lbl.size = Vector2(24, 22)
	var unit := _label(9, "ink")
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unit.position = Vector2(500, 336)
	unit.size = Vector2(100, 14)
	unit.text = "km/h"
	_banner = _label(20, "warn")
	_banner.position = Vector2(120, 70)
	_banner.size = Vector2(400, 30)
	_banner.modulate.a = 0.0
	_osm_lbl = _label(8, "ink")
	_osm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_osm_lbl.position = Vector2(8, 347)
	_osm_lbl.text = "map data © OpenStreetMap contributors"
	_osm_lbl.modulate.a = 0.7
	_map = Control.new()
	_map.position = Vector2(8, 224)
	_map.size = Vector2(118, 118)
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	_hud.add_child(_map)

func _retint_hud() -> void:
	if _hud == null:
		return
	for c in _hud.get_children():
		if c is Label and c.has_meta("role"):
			(c as Label).add_theme_color_override("font_color", Palette.col(c.get_meta("role")))
			(c as Label).add_theme_color_override("font_outline_color", Palette.col("bg"))

func _show_banner(msg: String, secs: float) -> void:
	if _banner == null:
		return
	_banner.text = msg
	if _banner_tw != null:
		_banner_tw.kill()
	_banner.modulate.a = 1.0
	_banner_tw = create_tween()
	_banner_tw.tween_interval(secs)
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.5)

func _tick_hud() -> void:
	_speed_lbl.text = str(int(round(absf(_v) * 3.6)))
	_gear_lbl.text = "D" if _gear > 0 else "R"
	_hud.queue_redraw()
	_map.queue_redraw()

func _draw_hud() -> void:
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	var on := Palette.col("friend") if _auto else ink
	_hud.draw_rect(AUTO_BTN, Color(bg, 0.65))
	_hud.draw_rect(AUTO_BTN, Color(on, 0.9), false, 1.5)
	var txt := "AUTODRIVE ON" if _auto else "autodrive"
	_hud.draw_string(_font, AUTO_BTN.position + Vector2(0, 15), txt, HORIZONTAL_ALIGNMENT_CENTER, AUTO_BTN.size.x, 11, on)
	if _touch_seen:
		var pl := Palette.col("player")
		var hz := Palette.col("hazard")
		_hud.draw_rect(GAS_BTN, Color(pl, 0.18 if not _touch_pedal.values().has("gas") else 0.45))
		_hud.draw_rect(BRAKE_BTN, Color(hz, 0.18 if not _touch_pedal.values().has("brake") else 0.45))
		_hud.draw_string(_font, GAS_BTN.position + Vector2(0, 54), "gas", HORIZONTAL_ALIGNMENT_CENTER, GAS_BTN.size.x, 12, Color(ink, 0.8))
		_hud.draw_string(_font, BRAKE_BTN.position + Vector2(0, 34), "brake", HORIZONTAL_ALIGNMENT_CENTER, BRAKE_BTN.size.x, 12, Color(ink, 0.8))
		if _touch_steer_id >= 0:
			var c := Vector2(_touch_steer_x0, 300)
			_hud.draw_line(c - Vector2(70, 0), c + Vector2(70, 0), Color(ink, 0.3), 2.0)
			_hud.draw_circle(c + Vector2(_touch_steer * 70.0, 0), 12.0, Color(pl, 0.5))

## the minimap: streets and building outlines round the car, heading up
func _draw_map() -> void:
	var sz := _map.size
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(bg, 0.72))
	var s := sz.x * 0.5 / MAP_R
	_map.draw_set_transform(sz * 0.5, -PI * 0.5 - _yaw, Vector2(s, s))
	var blds := PackedVector2Array()
	for i: int in _near(_bld_hash, _pos, MAP_R, BLD_CELL):
		var poly: PackedVector2Array = _blds[i]
		for j in range(poly.size()):
			blds.append(poly[j] - _pos)
			blds.append(poly[(j + 1) % poly.size()] - _pos)
	if not blds.is_empty():
		_map.draw_multiline(blds, Color(ink, 0.22), 1.0 / s)
	var major := PackedVector2Array()
	var minor := PackedVector2Array()
	for code: int in _near(_seg_hash, _pos, MAP_R, SEG_CELL):
		var r: Dictionary = _roads[code / 4096]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var j := code % 4096
		if float(r["w"]) >= 9.0:
			major.append(pts[j] - _pos)
			major.append(pts[j + 1] - _pos)
		else:
			minor.append(pts[j] - _pos)
			minor.append(pts[j + 1] - _pos)
	if not minor.is_empty():
		_map.draw_multiline(minor, Color(ink, 0.75), 2.0 / s)
	if not major.is_empty():
		_map.draw_multiline(major, Palette.col("warn"), 3.0 / s)
	for ring: PackedVector2Array in _boundary:
		var pts := PackedVector2Array()
		for p in ring:
			pts.append(p - _pos)
		pts.append(ring[0] - _pos)
		_map.draw_polyline(pts, Color(Palette.col("accent"), 0.8), 1.5 / s)
	if _auto and _ap_pts.size() > 1:
		var route := PackedVector2Array()
		for p in _ap_pts:
			route.append(p - _pos)
		_map.draw_polyline(route, Color(Palette.col("friend"), 0.8), 1.5 / s)
	_map.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c := sz * 0.5
	_map.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 5), c + Vector2(-5, 5)]), Palette.col("player"))
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(ink, 0.5), false, 1.0)

## ---- touch: drag anywhere on the left to steer, pedals on the right, tap autodrive ----------

func _input(event: InputEvent) -> void:
	if not _loaded:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not Flow.pointer_over_hud() \
				and AUTO_BTN.grow(4).has_point(mb.position):
			_set_auto(not _auto)
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_touch_seen = true
		if t.pressed:
			if AUTO_BTN.grow(4).has_point(t.position):
				return   # the emulated mouse click handles the button
			if GAS_BTN.grow(8).has_point(t.position):
				_touch_pedal[t.index] = "gas"
			elif BRAKE_BTN.grow(8).has_point(t.position):
				_touch_pedal[t.index] = "brake"
			elif t.position.x < 320.0 and t.position.y > 50.0 and _touch_steer_id < 0:
				_touch_steer_id = t.index
				_touch_steer_x0 = t.position.x
				_touch_steer = 0.0
		else:
			_touch_pedal.erase(t.index)
			if t.index == _touch_steer_id:
				_touch_steer_id = -1
				_touch_steer = 0.0
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == _touch_steer_id:
			_touch_steer = clampf((dr.position.x - _touch_steer_x0) / 70.0, -1.0, 1.0)
