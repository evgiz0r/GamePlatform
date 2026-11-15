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

## The places you can drive: the game's start screen offers one per entry. `city` is the
## file in cities/ (bake it with the "bake a real city" workflow, see GAME.md); `start` is
## the corner to begin at, by street names as OSM spells them: [street, cross street] puts
## the car on the first just past the second. Without one it starts on a main road
## mid-town.
const LEVELS := [
	{"name": "Givatayim", "city": "givatayim", "start": ["המרי", "שיינקין"]},
	{"name": "Bedford, Nova Scotia", "city": "bedford"},
]
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
const MAX_TREES := 16000
const SIGNAL_CYCLE := [              ## [seconds, phase of the E-W group, phase of N-S]
	[14.0, "g", "r"], [3.0, "y", "r"], [1.5, "r", "r"],
	[14.0, "r", "g"], [3.0, "r", "y"], [1.5, "r", "r"],
]

const SEG_CELL := 24.0               ## spatial hash cell for road segments (m)
const BLD_CELL := 24.0
const CHUNK := 400.0                 ## buildings and trees are merged per square this big, for culling
const VIEW_RANGE := 1100.0           ## building chunks further than this are not drawn
const TREE_RANGE := 700.0
const Y_AREA := 0.012
const Y_PATH := 0.022
const Y_ROAD := 0.035
const Y_MARK := 0.046
const NEW_STREET_M := 30.0           ## drive this far along a street for it to count
const MAP_R := 210.0                 ## the minimap shows this far around the car (m)
const AP_LAT := 3.0                  ## autodrive keeps the sideways pull in turns under this (m/s^2)

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
var _city_id := ""
var _place: Dictionary = {}          ## the LEVELS entry being driven
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
var _last_hit := ""                  ## what the car last bumped: "building 12" / "post 40", for the report

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

## ---- going somewhere: an address, a route on the road graph, a beacon over it ----
var _astar: AStar2D                  ## the drivable road graph (one-ways are one-way)
var _edge_of := {}                   ## Vector2i(from node, to node) -> Vector3i(road, index, dir)
var _addr := {}                      ## street (as the address spells it) -> Array of [number, Vector2]
var _dest_on := false
var _dest := Vector2.ZERO            ## the address itself
var _dest_stop := Vector2.ZERO       ## the kerb in front of it, where the drive ends
var _dest_name := ""
var _dest_t := 0.0
var _beacon: MeshInstance3D
var _picker: Control
var _pick_body: Control              ## where the page of buttons goes
var _pick_letters: Control
var _pick_page_lbl: Label
var _pick_prev: Button
var _pick_next: Button
var _pick_mode := "streets"          ## or "numbers"
var _pick_letter := ""               ## "" = every street
var _pick_page := 0
var _pick_street := ""
var _streets_list: Array = []        ## {name, en, label, count}, sorted, built once per city
var _dest_lbl: Label

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
var _stick_id := -1                  ## the touch that owns the stick; -1 when no thumb is down
var _stick := Vector2.ZERO           ## its deflection, inside the unit circle
var _sfx_was := 0.8
const AUTO_BTN := Rect2(226, 334, 100, 20)
const GOTO_BTN := Rect2(334, 334, 84, 20)
const STICK_C := Vector2(556, 268)   ## the touch stick sits still, here, on the right
const STICK_R := 52.0                ## thumb travel (design px) for full lock / full gas
const STICK_GRAB := 84.0             ## a thumb this close to its centre takes hold of it
const STICK_DEAD := 0.12

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
	_touch_seen = DisplayServer.is_touchscreen_available()   # phones get the stick hint at once
	_make_font()
	_tones()
	var t0 := Time.get_ticks_msec()
	_place = LEVELS[clampi(int(_config.get("level", 1)), 1, LEVELS.size()) - 1]
	if not _load_city(String(_place["city"])):
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
	var dir: String = get_script().resource_path.get_base_dir() + "/cities/"
	var path := dir + id + ".json"
	if not FileAccess.file_exists(path):
		# not baked yet: drive whichever city is there rather than nothing
		var any := ""
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				any = dir + f
				break
		if any == "":
			Probe.note("no city file at %s -- bake one with tools/osm_city.py (GAME.md)" % path)
			return false
		Probe.note("no %s yet, driving %s instead" % [path, any.get_file()])
		path = any
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		Probe.note("city file %s did not parse" % path)
		return false
	var k := 1.0 / float(data.get("scale", 10))
	_city_id = path.get_file().get_basename()
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
			"en": String(rd.get("name_en", "")), "drive": DRIVE.has(kind), "pv": rd.has("pv"),
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
		if bd.has("addr"):
			_add_address(String(bd["addr"]), box.get_center())
	for a: Array in data.get("addrs", []):   # address points that are not on a building
		_add_address("%s %s" % [a[2], a[3]], Vector2(a[0], a[1]) * k)
	_build_graph()
	_city_data = data
	return true

## "Sheinkin 47" -> filed under "Sheinkin" as number "47"
func _add_address(full: String, at: Vector2) -> void:
	var cut := full.rfind(" ")
	if cut <= 0:
		return
	var street := full.substr(0, cut)
	var num := full.substr(cut + 1)
	if not _addr.has(street):
		_addr[street] = []
	for a: Array in _addr[street]:
		if a[0] == num:
			return   # a building and an address point for the same door
	(_addr[street] as Array).append([num, at])

## the drivable roads as a directed graph for routing (Godot's AStar2D, distance-weighted)
func _build_graph() -> void:
	_astar = AStar2D.new()
	for ri in range(_roads.size()):
		var r: Dictionary = _roads[ri]
		if not r["drive"] or r["pv"]:
			continue
		var ids: PackedInt32Array = r["ids"]
		for j in range(ids.size() - 1):
			var a := ids[j]
			var b := ids[j + 1]
			if a == b:
				continue
			for id: int in [a, b]:
				if not _astar.has_point(id):
					_astar.add_point(id, _nodes[id])
			if r["o"] != -1:
				_astar.connect_points(a, b, false)
				_edge_of[Vector2i(a, b)] = Vector3i(ri, j, 1)
			if r["o"] != 1:
				_astar.connect_points(b, a, false)
				_edge_of[Vector2i(b, a)] = Vector3i(ri, j + 1, -1)

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
		var tone := "grass" if kind in ["park", "grass"] else ("ground" if kind == "land" else kind)
		if not areas.has(tone):
			areas[tone] = Buf.new()
		var flat: Array = a["p"]
		var ring := PackedVector2Array()
		for i in range(0, flat.size(), 2):
			ring.append(Vector2(flat[i], flat[i + 1]) * k)
		# islands sit on the sea, parks and car parks on whatever is under them
		var y := Y_AREA + (0.002 if tone in ["parking", "plaza"] else (0.001 if kind == "land" else 0.0))
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
		mi.visibility_range_end = VIEW_RANGE   # past this the haze has it anyway
		mi.visibility_range_end_margin = 80.0
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
	# one pair of multimeshes per chunk, so trees far off are not drawn at all
	var groups := {}
	for sp: Vector3 in spots:
		var key := _cell(Vector2(sp.x, sp.y), CHUNK)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(sp)
	for key: Vector2i in groups:
		var list: Array = groups[key]
		var mt := MultiMesh.new()
		mt.transform_format = MultiMesh.TRANSFORM_3D
		mt.mesh = trunk
		mt.instance_count = list.size()
		var mc := MultiMesh.new()
		mc.transform_format = MultiMesh.TRANSFORM_3D
		mc.use_colors = true
		mc.mesh = crown
		mc.instance_count = list.size()
		for i in range(list.size()):
			var sp: Vector3 = list[i]
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
			mmi.visibility_range_end = TREE_RANGE
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
				var on := _nearest_seg(p, 12.0, true)
				if not on.is_empty() and float(on["edge"]) < 0.4:
					continue   # OSM puts the light's node a few metres out; never plant it in a lane
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
		"beacon": Color(ac, 0.35),
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
		env.fog_density = 0.0018
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

## start at the place's `start` corner, else on a through road near the middle of town; always in
## the right-hand lane, facing the way traffic goes
func _place_start() -> void:
	var spot: Array = _place.get("start", []) if _place.get("city") == _city_id else []
	if spot.size() == 2 and _start_on(spot[0], spot[1]):
		_cam_yaw = _yaw
		_place_car(0.016)
		_camera(1.0)
		return
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

## put the car on `street` a few metres past where it meets `cross`; false if they never meet
func _start_on(street: String, cross: String) -> bool:
	for i in range(_nodes.size()):
		var on_street: Array = []
		var on_cross := false
		for e: Vector2i in _node_roads[i]:
			var r: Dictionary = _roads[e.x]
			if not r["drive"]:
				continue
			if r["name"] == street:
				on_street.append(e)
			elif r["name"] == cross:
				on_cross = true
		if not on_cross:
			continue
		for e: Vector2i in on_street:
			var r: Dictionary = _roads[e.x]
			var pts: PackedVector2Array = r["pts"]
			for d2: int in [1, -1]:
				var nxt := e.y + d2
				if nxt < 0 or nxt >= pts.size() or (r["o"] != 0 and r["o"] != d2):
					continue
				var dir := (pts[nxt] - pts[e.y]).normalized()
				var lane := 0.0 if r["o"] != 0 else minf(float(r["w"]) * 0.25, 1.8)
				var into := minf(_node_r[i] + 6.0, pts[e.y].distance_to(pts[nxt]) * 0.6)
				_pos = pts[e.y] + dir * into + Vector2(-dir.y, dir.x) * lane
				_yaw = dir.angle()
				return true
	Probe.note("start corner: %s never meets %s in %s" % [street, cross, _city_id])
	return false

func _physics_process(dt: float) -> void:
	if not _loaded or finished or _picker != null:
		return   # the address picker is open: the world waits
	_signals_tick(dt)
	_crash_cool = maxf(0.0, _crash_cool - dt)
	if PInput.just_pressed("action_a") and not _auto:
		_set_auto(true)
	elif PInput.just_pressed("action_b") and _auto:
		_set_auto(false)
	var ctl: Array = _autodrive(dt) if _auto else _manual(dt)
	_drive(dt, ctl[0], ctl[1], ctl[2])
	_check_arrival(dt)
	_explore(dt)
	_camera(dt)
	_tick_hud()

## keys and touch -> [throttle, brake, wheel angle]. Down brakes, and once stopped, holding
## it selects reverse; then down drives backwards and up brakes, like a real automatic.
func _manual(dt: float) -> Array:
	var steer_t := PInput.axis("move_left", "move_right")
	var up := 1.0 if PInput.pressed("move_up") else 0.0
	var down := 1.0 if PInput.pressed("move_down") else 0.0
	if _stick_id >= 0:
		# the touch stick is analog: a little off centre is a little gas or a little lock,
		# and steering is eased near the middle so small corrections stay small
		var k := _stick
		up = maxf(up, _dead(-k.y))
		down = maxf(down, _dead(k.y))
		var sx := _dead(absf(k.x))
		_steer_in = signf(k.x) * pow(sx, 1.4)
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

## 0 inside the dead zone, then 0..1 to the rim
func _dead(v: float) -> float:
	return clampf((v - STICK_DEAD) / (1.0 - STICK_DEAD), 0.0, 1.0)

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
	Probe.event("crash", {"kmh": int(speed * 3.6), "hit": _last_hit, "at": Vector2i(_pos),
		"street": _on_name, "auto": _auto})

## how far to move a circle so it overlaps nothing solid
func _push_out(c: Vector2, r: float, posts: bool) -> Vector2:
	var push := Vector2.ZERO
	for i: int in _near(_bld_hash, c, r, BLD_CELL):
		if _bld_solid[i] == 0:
			continue
		var box: Rect2 = _bld_box[i]
		if not box.grow(r).has_point(c + push):
			continue
		var p := _poly_push(_blds[i], c + push, r)
		if p != Vector2.ZERO:
			push += p
			_last_hit = "building %d" % i
	if posts:
		for i: int in _near(_post_hash, c, r, BLD_CELL):
			var d := (c + push) - _posts[i]
			var need := r + _post_r[i]
			if d.length() < need:
				push += d.normalized() * (need - d.length()) if d.length() > 0.001 else Vector2(need, 0)
				_last_hit = "post %d" % i
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
func _nearest_seg(p: Vector2, max_d: float, drivable: bool, public := false) -> Dictionary:
	var best := {}
	var bd := INF
	for code: int in _near(_seg_hash, p, max_d, SEG_CELL):
		var ri := code / 4096
		var sj := code % 4096
		var r: Dictionary = _roads[ri]
		if drivable and not r["drive"]:
			continue
		if public and r["pv"]:
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
	if _ap_pts.size() < 2 or _ap_off_route() > 25.0:
		_ap_plan()
		if _ap_pts.size() < 2:
			return [0.0, 1.0, 0.0]
	# forget what is behind: we are on whichever of the next stretches is closest. Looking
	# at only the current one lost track after a sharp corner and sent the car back round
	# to a point it had already passed.
	var at := _ap_nearest_seg()
	for _k in range(at):
		_ap_pts.remove_at(0)
		_ap_v.remove_at(0)
		_ap_lim.remove_at(0)
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

## the point `dist` metres along the planned lane from point k (negative = back)
func _ap_walk(k: int, dist: float) -> Vector2:
	var step := 1 if dist > 0.0 else -1
	var left := absf(dist)
	var p := _ap_pts[k]
	var j := k + step
	while j >= 0 and j < _ap_pts.size():
		var L := p.distance_to(_ap_pts[j])
		if L >= left:
			return p + (_ap_pts[j] - p) * (left / maxf(L, 0.0001))
		left -= L
		p = _ap_pts[j]
		j += step
	return p

## index of the planned stretch the car is on: the closest of the next three, or of any
## further one that starts within 60 m of the car (not "within 40 m of the point behind":
## a long first stretch then hid the next one, and the car never saw its stop coming)
func _ap_nearest_seg() -> int:
	var best_i := 0
	var best_d := INF
	for i in range(_ap_pts.size() - 1):
		if i >= 3 and _ap_pts[i].distance_to(_pos) > 60.0:
			break
		var d := Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[i], _ap_pts[i + 1]).distance_to(_pos)
		if d < best_d - 0.05:
			best_d = d
			best_i = i
	return best_i

func _ap_off_route() -> float:
	if _ap_pts.size() < 2:
		return INF
	var i := _ap_nearest_seg()
	return Geometry2D.get_closest_point_to_segment(_pos, _ap_pts[i], _ap_pts[i + 1]).distance_to(_pos)

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
	if _dest_on:
		if not _route_to(_dest):
			_show_banner("can't find a way there from here", 2.0)
			_clear_dest()
		return
	var hit := _nearest_seg(_pos, 60.0, true, true)
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
	# corners: the radius through the points 5 m either side of each one, and the speed
	# that keeps the sideways pull comfortable round it. A sharp junction corner and the
	# gentle-looking many-sided ring of a roundabout both come out as the tight turns
	# they are. (Points near the old end are redone now that there is road beyond them.)
	_ap_curves(start - 10)

func _ap_curves(from_k: int) -> void:
	for k in range(maxi(1, from_k), _ap_pts.size() - 1):
		var a := _ap_walk(k, -5.0)
		var b := _ap_pts[k]
		var c := _ap_walk(k, 5.0)
		var cross := absf((b - a).cross(c - a))
		var radius := INF if cross < 0.001 else a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * cross)
		_ap_v[k] = minf(_ap_lim[k], maxf(sqrt(AP_LAT * radius), 2.5))

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
		if not r2["drive"] or r2["pv"]:
			continue   # autodrive stays out of private driveways and car parks
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

## ---- going to an address ------------------------------------------------------------------

## plan the shortest legal way from the car to the kerb nearest `goal` into the autodrive lane
func _route_to(goal: Vector2) -> bool:
	var s := _nearest_seg(_pos, 40.0, true, true)
	var g := _nearest_seg(goal, 150.0, true, true)
	if s.is_empty() or g.is_empty():
		return false
	var r: Dictionary = _roads[s["road"]]
	var ids: PackedInt32Array = r["ids"]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = s["seg"]
	var ahead := (pts[sj + 1] - pts[sj]).dot(_fwd()) >= 0.0
	var dir: int = r["o"] if r["o"] != 0 else (1 if ahead else -1)
	var first := ids[sj + 1] if dir > 0 else ids[sj]
	# arrive at either end of the goal's segment, whichever is legal and shorter
	var gr: Dictionary = _roads[g["road"]]
	var gids: PackedInt32Array = gr["ids"]
	var gj: int = g["seg"]
	var best := PackedInt64Array()
	var best_len := INF
	var best_dir := 0
	for end: Array in [[gids[gj], 1], [gids[gj + 1], -1]]:
		if gr["o"] != 0 and gr["o"] != end[1]:
			continue   # would mean driving the last bit against a one-way
		if not _astar.has_point(first) or not _astar.has_point(end[0]):
			continue
		var path := _astar.get_id_path(first, end[0])
		if path.is_empty():
			continue
		var other := gids[gj + 1] if end[1] == 1 else gids[gj]
		if path.size() >= 2 and path[path.size() - 2] == other:
			continue   # it drives past the address to the far end, then U-turns back: no
		var L := 0.0
		for i in range(1, path.size()):
			L += _nodes[path[i - 1]].distance_to(_nodes[path[i]])
		if L < best_len:
			best_len = L
			best = path
			best_dir = end[1]
	if best.is_empty():
		return false
	_ap_pts = PackedVector2Array([s["q"]])
	_ap_lim = PackedFloat32Array([float(r["speed"])])
	for i in range(best.size()):
		var n := int(best[i])
		var prv := _ap_pts[_ap_pts.size() - 1]
		var nxt: Vector2 = _nodes[best[i + 1]] if i + 1 < best.size() else g["q"]
		var e: Vector3i = _edge_of.get(Vector2i(int(best[i - 1]), n), Vector3i(s["road"], 0, 1)) if i > 0 else Vector3i(s["road"], 0, dir)
		var road: Dictionary = _roads[e.x]
		var d := (nxt - prv).normalized()
		var lane := minf(float(road["w"]) * 0.25, 1.9) if road["o"] == 0 and float(road["w"]) >= 5.0 else 0.0
		_ap_pts.append(_nodes[n] + Vector2(-d.y, d.x) * lane)
		_ap_lim.append(float(road["speed"]))
	# the last stretch along the goal's segment, to the kerb in front of the address
	var last_dir := (gr["pts"] as PackedVector2Array)[gj + 1] - (gr["pts"] as PackedVector2Array)[gj]
	last_dir = last_dir.normalized() * float(best_dir)
	var glane := minf(float(gr["w"]) * 0.25, 1.9) if gr["o"] == 0 else 0.0
	_dest_stop = (g["q"] as Vector2) + Vector2(-last_dir.y, last_dir.x) * glane
	_ap_pts.append(_dest_stop)
	_ap_lim.append(float(gr["speed"]))
	_ap_v = _ap_lim.duplicate()
	_ap_curves(1)
	_ap_v[_ap_v.size() - 1] = 0.0   # and stop there
	_ap_end = Vector3i(-1, 0, 0)    # nothing after the destination
	Probe.event("route", {"to": _dest_name, "m": int(best_len), "points": _ap_pts.size()})
	return true

func _set_dest(at: Vector2, label: String) -> void:
	_dest_on = true
	_dest = at
	_dest_stop = at
	_dest_name = label
	_dest_t = 0.0
	if _beacon == null:
		_beacon = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.4
		cm.bottom_radius = 1.4
		cm.height = 70.0
		cm.radial_segments = 16
		cm.cap_top = false
		var m := _surface("beacon")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		cm.material = m
		_beacon.mesh = cm
		_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(_beacon)
	_beacon.position = Vector3(at.x, 35.0, at.y)
	_beacon.visible = true
	Probe.event("destination", {"to": label})
	_set_auto(true)
	_show_banner("→ " + label, 2.0)

func _clear_dest() -> void:
	_dest_on = false
	if _beacon != null:
		_beacon.visible = false

func _check_arrival(dt: float) -> void:
	if not _dest_on:
		return
	_dest_t += dt
	var near_stop := _pos.distance_to(_dest_stop)
	var last_leg := _auto and _ap_pts.size() <= 3
	if near_stop < 9.0 and absf(_v) < 1.5 or last_leg and near_stop < 15.0 and absf(_v) < 3.0 \
			or (not _auto and _pos.distance_to(_dest) < 16.0 and absf(_v) < 2.5):
		_auto = false
		_ap_pts = PackedVector2Array()
		_clear_dest()
		Audio.play("coin", 0.05, -2.0)
		_show_banner("arrived: " + _dest_name, 3.0)
		Probe.event("arrived", {"to": _dest_name, "secs": int(_dest_t)})

## ---- the address picker: streets, then house numbers ---------------------------------------
## Built for thumbs: no scrolling list (a phone's finger lands on a button, not the list)
## and no typing box (web builds get no reliable on-screen keyboard). Letter chips narrow
## the streets to an initial, pages flip with big arrows. The buttons are only drawn: the
## shell's UI layer sits over every game and would swallow real clicks, so _input() hit-
## tests them and calls the Callable each one carries in its "cb" meta (see _pick_tap).

const PICK_COLS := 2
const PICK_ROWS := 7
const NUM_COLS := 6

func _open_picker() -> void:
	if _picker != null:
		return
	if _streets_list.is_empty():
		_build_street_list()
	_picker = Control.new()
	_picker.size = Vector2(640, 360)
	_picker.z_index = 90
	add_child(_picker)
	var dim := ColorRect.new()
	dim.color = Color(Palette.col("bg"), 0.93)
	dim.size = Vector2(640, 360)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker.add_child(dim)
	var title := UIKit.label("where to?", 16, "player")
	title.position = Vector2(170, 2)
	title.size = Vector2(300, 22)
	_picker.add_child(title)
	_pick_letters = Control.new()
	_pick_letters.position = Vector2(0, 34)   # clear of the shell's sound/menu buttons
	_picker.add_child(_pick_letters)
	_pick_body = Control.new()
	_pick_body.position = Vector2(20, 90)
	_picker.add_child(_pick_body)
	_pick_prev = _bar_button("◀", Vector2(20, 331), 90, func(): _turn(-1))
	_pick_next = _bar_button("▶", Vector2(410, 331), 90, func(): _turn(1))
	_bar_button("close", Vector2(530, 331), 90, _close_picker)
	_pick_page_lbl = UIKit.label("", 12, "ink")
	_pick_page_lbl.add_theme_font_override("font", _font)
	_pick_page_lbl.text_direction = Control.TEXT_DIRECTION_LTR
	_pick_page_lbl.position = Vector2(110, 334)
	_pick_page_lbl.size = Vector2(300, 18)
	_picker.add_child(_pick_page_lbl)
	_pick_mode = "streets"
	_pick_page = 0
	_build_letters()
	_refresh_pick()
	Probe.event("picker")

func _close_picker() -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null

## a drawn button that _pick_tap() can press
func _tap_button(text: String, cb: Callable) -> Button:
	var b := UIKit.button(text, func(): pass)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("cb", cb)
	return b

## a click or tap while the picker is open: whichever of its buttons is under it
func _pick_tap(at: Vector2) -> void:
	for b: Button in _picker.find_children("*", "Button", true, false):
		if b.is_queued_for_deletion() or b.disabled or not b.is_visible_in_tree():
			continue
		if b.get_global_rect().has_point(at):
			Audio.play("click", 0.05, -8.0)
			(b.get_meta("cb") as Callable).call()
			return

func _bar_button(text: String, at: Vector2, w: float, cb: Callable) -> Button:
	var b := _tap_button(text, cb)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 13)
	_picker.add_child(b)
	_put(b, at, Vector2(w, 26))
	return b

## size a button once it is in the tree: set before, Godot keeps the kit's 180x34 minimum
## on record and the "small" buttons came out 180 wide, overlapping their neighbours
func _put(b: Control, at: Vector2, sz: Vector2) -> void:
	b.custom_minimum_size = sz
	b.position = at
	b.size = sz

## every named street, as the roads and the addresses spell it
func _build_street_list() -> void:
	var en := {}
	for r: Dictionary in _roads:
		if r["drive"] and not r["pv"] and r["name"] != "" and not String(r["name"]).is_valid_int():
			en[r["name"]] = r["en"]
	for st: String in _addr:
		if not en.has(st) and not st.is_valid_int():
			en[st] = ""
	for nm: String in en:
		var e: String = en[nm]
		var count := (_addr.get(nm, []) as Array).size()
		var label: String = nm if e == "" or e == nm else "%s · %s" % [e, nm]
		# U+200E (left-to-right mark) after the Hebrew keeps the count at the end, not in it
		_streets_list.append({"name": nm, "en": e, "label": label + ("\u200e  (%d)" % count if count > 0 else "")})
	_streets_list.sort_custom(func(a, b): return _sort_key(a).naturalnocasecmp_to(_sort_key(b)) < 0)

func _sort_key(st: Dictionary) -> String:
	return String(st["en"]) if st["en"] != "" else String(st["name"])

## the initials a street can be found under: of its English name and of its own name
func _initials(st: Dictionary) -> Array:
	var out: Array = []
	for nm: String in [st["en"], st["name"]]:
		if nm != "":
			var c := nm.substr(0, 1).to_upper()
			if not out.has(c):
				out.append(c)
	return out

func _build_letters() -> void:
	for c in _pick_letters.get_children():
		c.queue_free()
	var latin: Array = []
	var other: Array = []
	for st: Dictionary in _streets_list:
		for c: String in _initials(st):
			var bucket: Array = latin if c.unicode_at(0) < 0x0250 else other
			if not bucket.has(c):
				bucket.append(c)
	latin.sort()
	other.sort()
	var rows: Array = [["all"] + latin, other] if not other.is_empty() else [["all"] + latin]
	for r in range(rows.size()):
		var row: Array = rows[r]
		var w := minf(24.0, 560.0 / maxf(1.0, row.size()))
		var total := 0.0
		for c: String in row:
			total += 42.0 if c == "all" else w
		var x := 320.0 - total * 0.5
		for i in range(row.size()):
			var c: String = row[i]
			var key := "" if c == "all" else c
			var b := _tap_button(c, func(): _pick_letter = key; _pick_page = 0; _pick_mode = "streets"; _refresh_pick())
			b.add_theme_font_override("font", _font)
			b.add_theme_font_size_override("font_size", 11)
			b.set_meta("key", key)
			_pick_letters.add_child(b)
			var cw := 42.0 if c == "all" else w
			_put(b, Vector2(x, r * 25), Vector2(cw - 2.0, 22))
			x += cw

func _turn(by: int) -> void:
	_pick_page += by
	_refresh_pick()

## lay out the current page: streets (two columns) or one street's numbers (six columns)
func _refresh_pick() -> void:
	for c in _pick_body.get_children():
		c.queue_free()
	for b in _pick_letters.get_children():
		(b as Control).modulate = Color(1, 1, 1, 1.0 if b.get_meta("key") == _pick_letter else 0.55)
	var items: Array = []   ## [text, callable]
	var cols := PICK_COLS
	if _pick_mode == "streets":
		for st: Dictionary in _streets_list:
			if _pick_letter == "" or _initials(st).has(_pick_letter):
				items.append([st["label"], _pick_numbers.bind(st["name"])])
	else:
		cols = NUM_COLS
		items.append(["← streets", func(): _pick_mode = "streets"; _pick_page = _pick_back_page; _refresh_pick()])
		items.append(["anywhere", _go.bind(_pick_street, -1)])
		var nums: Array = _addr.get(_pick_street, []).duplicate()
		nums.sort_custom(func(a, b): return String(a[0]).naturalnocasecmp_to(String(b[0])) < 0)
		for n: Array in nums:
			items.append([String(n[0]), _go_to.bind(_pick_street + " " + String(n[0]), n[1])])
	var per := cols * PICK_ROWS
	var pages := maxi(1, ceili(float(items.size()) / per))
	_pick_page = clampi(_pick_page, 0, pages - 1)
	var w := 600.0 / cols
	for i in range(_pick_page * per, mini(items.size(), (_pick_page + 1) * per)):
		var k := i - _pick_page * per
		var b := _tap_button(items[i][0], items[i][1])
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 13)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		_pick_body.add_child(b)
		_put(b, Vector2((k % cols) * w, (k / cols) * 33), Vector2(w - 8.0, 28))
	_pick_prev.disabled = _pick_page == 0
	_pick_next.disabled = _pick_page >= pages - 1
	var what := _pick_street if _pick_mode == "numbers" else ("streets" if _pick_letter == "" else "streets · " + _pick_letter)
	_pick_page_lbl.text = "%s\u200e   %d / %d" % [what, _pick_page + 1, pages]

var _pick_back_page := 0

func _pick_numbers(street: String) -> void:
	_pick_back_page = _pick_page
	_pick_street = street
	_pick_mode = "numbers"
	_pick_page = 0
	_refresh_pick()

## a street with no particular number: its nearest point to the car
func _go(street: String, _i: int) -> void:
	var best := INF
	var at := _pos
	for r: Dictionary in _roads:
		if r["name"] != street or not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		for j in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(_pos, pts[j], pts[j + 1])
			if q.distance_to(_pos) < best:
				best = q.distance_to(_pos)
				at = q
	if best == INF and _addr.has(street):
		at = (_addr[street] as Array)[0][1]
	_go_to(street, at)

func _go_to(label: String, at: Vector2) -> void:
	_close_picker()
	_set_dest(at, label)

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
	_speed_lbl.position = Vector2(496, 30)
	_speed_lbl.size = Vector2(100, 40)
	_gear_lbl = _label(16, "warn")
	_gear_lbl.position = Vector2(600, 42)
	_gear_lbl.size = Vector2(24, 22)
	var unit := _label(9, "ink")
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	unit.position = Vector2(496, 66)
	unit.size = Vector2(100, 14)
	unit.text = "km/h"
	_dest_lbl = _label(12, "accent")
	_dest_lbl.text_direction = Control.TEXT_DIRECTION_LTR   # "→ <Hebrew street> 47 · 930 m" reads left to right
	_dest_lbl.position = Vector2(150, 314)
	_dest_lbl.size = Vector2(340, 18)
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
	if _dest_on:
		var left := _pos.distance_to(_dest)
		if _auto and _ap_pts.size() > 1:
			left = _pos.distance_to(_ap_pts[0]) + _ap_len()
		_dest_lbl.text = "→ %s · %s" % [_dest_name, ("%.1f km" % (left / 1000.0)) if left >= 1000.0 else ("%d m" % int(left))]
	else:
		_dest_lbl.text = ""
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
	var go := Palette.col("accent")
	_hud.draw_rect(GOTO_BTN, Color(bg, 0.65))
	_hud.draw_rect(GOTO_BTN, Color(go, 0.9), false, 1.5)
	_hud.draw_string(_font, GOTO_BTN.position + Vector2(0, 15), "go to…", HORIZONTAL_ALIGNMENT_CENTER, GOTO_BTN.size.x, 11, go)
	if _touch_seen:
		var held := _stick_id >= 0
		var c := STICK_C
		var a := 0.85 if held else 0.45
		_hud.draw_circle(c, STICK_R, Color(bg, 0.35 if held else 0.2))
		_hud.draw_arc(c, STICK_R, 0.0, TAU, 48, Color(ink, a * 0.6), 2.0)
		# the top of the ring is gas, the bottom brake / reverse
		_hud.draw_arc(c, STICK_R + 4.0, PI * 1.2, PI * 1.8, 16, Color(Palette.col("friend"), a), 3.0)
		_hud.draw_arc(c, STICK_R + 4.0, PI * 0.2, PI * 0.8, 16, Color(Palette.col("hazard"), a), 3.0)
		_hud.draw_circle(c + _stick * STICK_R, 17.0, Color(Palette.col("player"), 0.75 if held else 0.35))
		if not held:
			_hud.draw_string(_font, c + Vector2(-60, STICK_R + 18), "hold & drag to drive", HORIZONTAL_ALIGNMENT_CENTER, 120, 9, Color(ink, 0.6))

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
	var paths := PackedVector2Array()
	for code: int in _near(_seg_hash, _pos, MAP_R, SEG_CELL):
		var r: Dictionary = _roads[code / 4096]
		var pts: PackedVector2Array = r["pts"]
		var j := code % 4096
		if not r["drive"] or r["pv"]:
			paths.append(pts[j] - _pos)
			paths.append(pts[j + 1] - _pos)
		elif float(r["w"]) >= 9.0:
			major.append(pts[j] - _pos)
			major.append(pts[j + 1] - _pos)
		else:
			minor.append(pts[j] - _pos)
			minor.append(pts[j + 1] - _pos)
	if not paths.is_empty():
		_map.draw_multiline(paths, Color(ink, 0.3), 1.0 / s)
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
	if _dest_on:
		_map.draw_circle(_dest - _pos, 6.0 / s, Palette.col("accent"))
		_map.draw_arc(_dest - _pos, 11.0 / s, 0.0, TAU, 24, Color(Palette.col("accent"), 0.6), 1.5 / s)
	_map.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var c := sz * 0.5
	_map.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 5), c + Vector2(-5, 5)]), Palette.col("player"))
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(ink, 0.5), false, 1.0)

## ---- touch: one stick that stays put on the right -- thumb on it, drag up for gas, down
## to brake (and reverse once stopped), sideways to steer; let go and it centres. Grabbing
## it takes the wheel back from autodrive. ----------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _loaded:
		return
	if _picker != null:   # everything goes to the picker while it is open
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and not Flow.pointer_over_hud():
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_pick_tap(mb.position)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_turn(1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_turn(-1)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not Flow.pointer_over_hud():
			if AUTO_BTN.grow(4).has_point(mb.position):
				_set_auto(not _auto)
			elif GOTO_BTN.grow(4).has_point(mb.position):
				_open_picker.call_deferred()   # after this click, so it does not hit the list
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		_touch_seen = true
		if t.pressed:
			if AUTO_BTN.grow(4).has_point(t.position) or GOTO_BTN.grow(4).has_point(t.position) or t.position.y < 36.0:
				return   # the button (via its emulated click) and the shell's menu/sound row
			if _stick_id < 0 and t.position.distance_to(STICK_C) <= STICK_GRAB:
				_stick_id = t.index
				_stick = ((t.position - STICK_C) / STICK_R).limit_length(1.0)
				if _auto:
					_set_auto(false)
		elif t.index == _stick_id:
			_stick_id = -1
			_stick = Vector2.ZERO
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == _stick_id:
			_stick = ((dr.position - STICK_C) / STICK_R).limit_length(1.0)
