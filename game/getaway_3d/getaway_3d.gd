extends GameMode3D
## getaway 3d -- the 3D version of getaway: a bigger neon city at night, seen from high
## above. Jobs against the clock (a hot case, a fare, a car to steal), cash on the streets,
## knock-over street lamps, people who walk, cross and dodge, and police who multiply with
## every job you finish. A cop on you fills the bust meter; three busts end the run.
## See GAME.md.
##
## Everything happens on the ground plane in 2D (x, z) -- positions and velocities are
## Vector2 -- and is copied onto Node3Ds each frame. The city is a grid of 3.5-unit tiles:
## every sixth row/column pair is a two-lane road, the 4x4 tiles between are a block, and
## a few neighbouring blocks are joined over the road between them (T-junctions, big
## parks, plazas and car parks). Solids are rectangles and circles in a per-tile hash;
## cars are circles pushed out of them. Cops follow a breadth-first flow field over the
## drivable tiles; traffic rides its lane tile to tile. The camera is north-up, so the
## arrow keys mean compass directions, exactly as in the 2D game.

const TILE := 3.5
const PERIOD := 6                ## tiles from one road to the next
const CELL := 21.0               ## PERIOD * TILE
const ROAD := 7.0                ## two lanes
const BLOCKS_X := 9
const BLOCKS_Y := 7
const COLS := BLOCKS_X * PERIOD + 2
const ROWS := BLOCKS_Y * PERIOD + 2
const MAP_W := COLS * TILE
const MAP_D := ROWS * TILE
const MERGES := 8                ## neighbouring blocks joined over their road
const SIDEWALK := 1.6
const KERB := 0.15
const COP_TOP := 16.5
const COP_DELAY := 3.0
const START_LIVES := 3
const MAX_STARS := 5
const INVULN := 2.5
const RETREAT := 2.6             ## after a bust the cops drive away this long
const BUST_TIME := 0.9           ## seconds of a cop on you (half that if you are stopped)
const TRAFFIC := 34
const PEDS := 24
const COINS := 12
const SFX_SCALE := 0.28          ## the shell default is loud; in memory only, see CLAUDE.md
const MUSIC_SCALE := 0.45
const MUSIC := "chiptune_battle"
const PEOPLE := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Female"]
const SHOPS := ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h"]
const TOWERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c"]
const HOUSES := ["building-type-a", "building-type-b", "building-type-c", "building-type-d", "building-type-e"]
const TRAFFIC_CARS := ["sedan", "taxi", "suv", "van", "delivery", "truck", "sedan", "taxi", "garbage-truck"]
const PARKED := ["sedan", "suv", "van", "taxi", "truck"]
const STEAL := ["ambulance", "taxi", "suv", "firetruck", "police", "van", "truck"]
const NEON := ["accent", "prize", "friend", "player", "warn"]
## How each car drives. len is the model's length; the collision radius follows from it.
const CARS := {
	"sedan": {"top": 26.0, "accel": 38.0, "grip": 10.0, "len": 2.6},
	"taxi": {"top": 25.5, "accel": 37.0, "grip": 10.5, "len": 2.75},
	"suv": {"top": 24.5, "accel": 35.0, "grip": 11.0, "len": 2.7},
	"van": {"top": 22.0, "accel": 30.0, "grip": 9.0, "len": 2.75},
	"truck": {"top": 23.5, "accel": 33.0, "grip": 9.5, "len": 2.95},
	"delivery": {"top": 21.0, "accel": 28.0, "grip": 9.0, "len": 3.25},
	"garbage-truck": {"top": 19.0, "accel": 24.0, "grip": 8.5, "len": 3.45},
	"ambulance": {"top": 28.5, "accel": 36.0, "grip": 8.0, "len": 3.25},
	"firetruck": {"top": 22.0, "accel": 27.0, "grip": 8.0, "len": 3.4},
	"police": {"top": 28.0, "accel": 41.0, "grip": 11.0, "len": 3.1},
}
const JOBS := {
	"case": {"pick": "answer the ringing phone", "drop": "deliver the hot case", "role": "prize", "pay": 200, "tip": 10},
	"fare": {"pick": "pick up the fare", "drop": "drop off the fare", "role": "friend", "pay": 150, "tip": 15},
	"steal": {"pick": "steal the hot car", "drop": "bring it to the garage", "role": "accent", "pay": 300, "tip": 10},
}
const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

## A car: its state lives on the ground plane, its looks on `node`.
class Car extends RefCounted:
	var node: Node3D
	var body: Node3D             ## the model pivot (rolls in corners)
	var kind := "sedan"
	var top := 26.0
	var accel := 38.0
	var grip := 10.0
	var r := 1.0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var heading := 0.0           ## radians in the x/z plane, 0 = +x (east), PI/2 = +z (south)
	var spin := 0.0
	var roll := 0.0
	var y := 0.0
	var stun := 0.0
	var stuck := 0.0
	var crash_cd := 0.0
	var bar_a: MeshInstance3D
	var bar_b: MeshInstance3D
	var light: OmniLight3D
	var lights_on := false
	# traffic: drives from `from` to the centre of tile `to`, prog 0..1
	var to := Vector2i.ZERO
	var dir := Vector2i.RIGHT
	var from := Vector2.ZERO
	var prog := 0.0
	var speed := 8.0
	var wait := 0.0
	var knocked := 0.0
	var skid_l := Vector2.INF
	var skid_r := Vector2.INF

	func sync() -> void:
		node.position = Vector3(pos.x, y, pos.y)
		node.rotation.y = PI * 0.5 - (heading + spin)
		if body != null:
			body.rotation.z = roll

var _crng := RandomNumberGenerator.new()   ## the city: same every run
var _rng := RandomNumberGenerator.new()
var _tiles := PackedInt32Array()          ## -1 road, else the block index it belongs to
var _blocks: Array = []                   ## {rect, kind, raised, merged}
var _solids: Array = []                   ## {rect} or {c, r, lamp, on}
var _hash := {}                           ## Vector2i tile -> Array of solid indices
var _drive_map := PackedByteArray()
var _flow := PackedInt32Array()          ## steps to the player, for the cops
var _route := PackedInt32Array()         ## steps to the job, for the GPS
var _guide: Node3D                        ## where the GPS says to go next (the bots' "*")
var _guide_p := Vector2.ZERO
var _flow_t := 0.0
var _lamps: Array = []                    ## {node, bulb, head, solid, alive}
var _pools: MultiMesh
var _skid_mm: MultiMesh
var _skid_next := 0
var _player: Car
var _cops: Array = []
var _traffic: Array = []
var _peds: Array = []
var _coins: Array = []                    ## {node, pos}
var _marker: Node3D
var _ring: MeshInstance3D
var _pillar: MeshInstance3D
var _gem: MeshInstance3D
var _arrow: MeshInstance3D
var _prop: Node3D                         ## payphone / waiting fare / car to steal
var _smoke: CPUParticles3D
var _sparks: Array = []
var _spark_i := 0
var _headlight: SpotLight3D
var _job := "case"
var _stage := "pick"
var _target := Vector2.ZERO
var _job_t := 0.0
var _job_n := 0
var _deliveries := 0
var _stars := 1
var _invuln := 0.0
var _bust := 0.0
var _cop_near := false
var _t := 0.0
var _siren_t := 0.0
var _cam_t := Vector3.ZERO
var _cam_h := 28.0
var _view := Rect2()
var _stick_on := false
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _hud: Node2D
var _job_label: Label
var _banner: Label
var _banner_tw: Tween
var _cmats := {}                          ## key -> [material, role_a, role_b, t, emission]
var _gmats := {}                          ## key -> [material, role, alpha]
var _radial: GradientTexture2D
var _beam: GradientTexture2D
var _started := false
var _sfx_was := 0.8
var _music_was := 0.7

func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(0, 0, MAP_W, MAP_D)

func _ready() -> void:
	title = "getaway 3d"
	super()

func start(_config: Dictionary) -> void:
	_started = true
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_music_was = float(SaveData.data.get("volume_music", 0.7))
	SaveData.data["volume_music"] = _music_was * MUSIC_SCALE
	_rng.randomize()
	_crng.seed = 2077

	_radial = _gradient_tex(true)
	_beam = _gradient_tex(false)
	_setup_light()
	Bus.palette_changed.connect(_retint_all)

	_build_city()
	_build_ground()
	_build_blocks()
	_build_markings()
	_build_skyline()
	_build_lamps()
	_build_drive_map()
	_build_fx()

	_player = _make_car("sedan")
	_player.pos = Vector2(24 * TILE + TILE, 18 * TILE + TILE)   # a junction near the middle
	_player.heading = -PI * 0.5
	_player.sync()
	_dress_player()
	track3d(_player.node, "@")
	_cam_t = Vector3(_player.pos.x, 0, _player.pos.y)
	_update_camera(1.0)

	_build_marker()
	for i in TRAFFIC:
		_spawn_traffic()
	for i in PEDS:
		_spawn_ped()
	for i in COINS:
		_spawn_coin()
	_build_hud()

	set_lives(START_LIVES)
	_stars = 1
	_new_job()
	_rebuild_flow()
	Audio.play("voice_go")
	Probe.event("start")

func _exit_tree() -> void:
	if not _started:
		return
	SaveData.data["volume_sfx"] = _sfx_was
	SaveData.data["volume_music"] = _music_was
	Audio.stop_music()

## ---- light and materials ---------------------------------------------------------

func _setup_light() -> void:
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 0.55
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	_retint_light()

func _retint_light() -> void:
	sun.light_color = Palette.col("ink").lerp(Palette.col("prize"), 0.35)
	env.ambient_light_color = Palette.col("ink").lerp(Palette.col("prize"), 0.45)
	env.fog_light_color = Palette.col("bg_alt").lerp(Palette.col("accent"), 0.15)

func _retint_all() -> void:
	_retint_light()
	for k in _cmats:
		_tint_c(_cmats[k])
	for k in _gmats:
		_tint_g(_gmats[k])

## A material mixed from two palette roles, so dim surfaces (asphalt, pavement, grass)
## still follow /look. Cached, like mat().
func _cmat(a: String, b: String, t: float, emission: float = 0.0, rough: float = 0.85) -> StandardMaterial3D:
	var key := "%s|%s|%.2f|%.2f" % [a, b, t, emission]
	if _cmats.has(key):
		return _cmats[key][0]
	var m := StandardMaterial3D.new()
	m.roughness = rough
	_cmats[key] = [m, a, b, t, emission]
	_tint_c(_cmats[key])
	return m

func _tint_c(e: Array) -> void:
	var m: StandardMaterial3D = e[0]
	var c := Palette.col(e[1]).lerp(Palette.col(e[2]), e[3])
	m.albedo_color = c
	m.emission_enabled = float(e[4]) > 0.0
	m.emission = c
	m.emission_energy_multiplier = e[4]

## Additive light: lamp pools on the road, headlight beams, the job's light pillar.
func _gmat(role: String, alpha: float, tex: Texture2D) -> StandardMaterial3D:
	var key := "%s|%.2f|%d" % [role, alpha, tex.get_instance_id()]
	if _gmats.has(key):
		return _gmats[key][0]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_texture = tex
	_gmats[key] = [m, role, alpha]
	_tint_g(_gmats[key])
	return m

func _tint_g(e: Array) -> void:
	var m: StandardMaterial3D = e[0]
	var c := Palette.col(e[1])
	m.albedo_color = Color(c.r, c.g, c.b, e[2])

## A white-to-clear mask: radial for pools, linear for beams. Tinted by the material.
func _gradient_tex(radial: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	if radial:
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
	else:
		t.fill_from = Vector2(0.5, 0.0)
		t.fill_to = Vector2(0.5, 1.0)
	return t

func _box(size: Vector3, at: Vector3, m: Material, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi

func _flat(size: Vector2, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = m
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	return mi

## ---- the city layout ---------------------------------------------------------------

func _build_city() -> void:
	_tiles.resize(COLS * ROWS)
	for y in ROWS:
		for x in COLS:
			var road := x % PERIOD < 2 or y % PERIOD < 2
			_tiles[y * COLS + x] = -1 if road else floori(y / float(PERIOD)) * BLOCKS_X + floori(x / float(PERIOD))
	_blocks.clear()
	for by in BLOCKS_Y:
		for bx in BLOCKS_X:
			_blocks.append({
				"rect": Rect2(bx * CELL + ROAD, by * CELL + ROAD, CELL - ROAD, CELL - ROAD),
				"kind": "", "raised": false, "merged": false, "gone": false,
			})

	# Join some neighbours over the road between them. Each junction loses at most one arm,
	# so every junction keeps three: T-junctions, never dead ends.
	var touched := {}
	var made := 0
	var tries := 0
	while made < MERGES and tries < 400:
		tries += 1
		var bx := _crng.randi_range(0, BLOCKS_X - 1)
		var by := _crng.randi_range(0, BLOCKS_Y - 1)
		var horiz := _crng.randf() < 0.5
		var nx := bx + (1 if horiz else 0)
		var ny := by + (0 if horiz else 1)
		if nx >= BLOCKS_X or ny >= BLOCKS_Y:
			continue
		var ai := by * BLOCKS_X + bx
		var bi := ny * BLOCKS_X + nx
		var a: Dictionary = _blocks[ai]
		var b: Dictionary = _blocks[bi]
		if a["merged"] or b["merged"]:
			continue
		var j1 := Vector2i(nx, by) if horiz else Vector2i(bx, ny)
		var j2 := Vector2i(nx, by + 1) if horiz else Vector2i(bx + 1, ny)
		if touched.has(j1) or touched.has(j2):
			continue
		touched[j1] = true
		touched[j2] = true
		a["merged"] = true
		b["merged"] = true
		b["gone"] = true
		if horiz:
			for y in range(by * PERIOD + 2, by * PERIOD + 6):
				for x in [nx * PERIOD, nx * PERIOD + 1]:
					_tiles[y * COLS + x] = ai
		else:
			for x in range(bx * PERIOD + 2, bx * PERIOD + 6):
				for y in [ny * PERIOD, ny * PERIOD + 1]:
					_tiles[y * COLS + x] = ai
		for y in range(ny * PERIOD + 2, ny * PERIOD + 6):
			for x in range(nx * PERIOD + 2, nx * PERIOD + 6):
				_tiles[y * COLS + x] = ai
		a["rect"] = (a["rect"] as Rect2).merge(b["rect"])
		made += 1

	# what each block is: towers in the middle, shops around them, houses at the edge
	var mid := Vector2(MAP_W, MAP_D) * 0.5
	for b in _blocks:
		if b["gone"]:
			continue
		var r: Rect2 = b["rect"]
		var d := (r.get_center() - mid).length() / mid.length()
		var roll := _crng.randf()
		var kind := ""
		if b["merged"]:
			kind = ["park", "plaza", "parking", "park", "towers"][_crng.randi() % 5]
		elif d < 0.3:
			kind = "towers" if roll < 0.75 else "shops"
		elif d < 0.66:
			if roll < 0.62:
				kind = "shops"
			elif roll < 0.74:
				kind = "park"
			elif roll < 0.85:
				kind = "plaza"
			else:
				kind = "parking"
		else:
			if roll < 0.58:
				kind = "houses"
			elif roll < 0.74:
				kind = "park"
			elif roll < 0.87:
				kind = "shops"
			else:
				kind = "parking"
		b["kind"] = kind
		b["raised"] = kind in ["towers", "shops", "houses"]

func _in_grid(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < COLS and t.y < ROWS

func _is_road(t: Vector2i) -> bool:
	return _in_grid(t) and _tiles[t.y * COLS + t.x] == -1

func _drivable(t: Vector2i) -> bool:
	return _in_grid(t) and _drive_map[t.y * COLS + t.x] == 1

func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(p.x / TILE), 0, COLS - 1), clampi(floori(p.y / TILE), 0, ROWS - 1))

func _center(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)

func _block_at(p: Vector2) -> Dictionary:
	var t := _tile_of(p)
	var i := _tiles[t.y * COLS + t.x]
	return {} if i < 0 else _blocks[i]

func _ground_y(p: Vector2) -> float:
	var b := _block_at(p)
	if b.is_empty() or not b["raised"]:
		return 0.0
	return KERB if (b["rect"] as Rect2).has_point(p) else 0.0

func _on_grass(p: Vector2) -> bool:
	var b := _block_at(p)
	return not b.is_empty() and b["kind"] == "park"

## Which way traffic flows on a road tile (right-hand traffic). Junction tiles have two.
func _lane_dirs(t: Vector2i) -> Array:
	var out: Array = []
	if not _is_road(t):
		return out
	match t.y % PERIOD:
		0: out.append(Vector2i(-1, 0))
		1: out.append(Vector2i(1, 0))
	match t.x % PERIOD:
		0: out.append(Vector2i(0, 1))
		1: out.append(Vector2i(0, -1))
	return out

## ---- solids ---------------------------------------------------------------------

func _add_rect(r: Rect2) -> void:
	_solids.append({"rect": r})
	_hash_add(_solids.size() - 1, r)

func _add_circle(c: Vector2, rad: float, lamp: int = -1) -> int:
	_solids.append({"c": c, "r": rad, "lamp": lamp, "on": true})
	_hash_add(_solids.size() - 1, Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0))
	return _solids.size() - 1

func _hash_add(i: int, r: Rect2) -> void:
	for tx in range(floori(r.position.x / TILE), floori(r.end.x / TILE) + 1):
		for tz in range(floori(r.position.y / TILE), floori(r.end.y / TILE) + 1):
			var k := Vector2i(tx, tz)
			if not _hash.has(k):
				_hash[k] = []
			(_hash[k] as Array).append(i)

func _solid_at(p: Vector2, m: float) -> bool:
	var arr = _hash.get(_tile_of(p))
	if arr == null:
		return false
	for i in arr:
		var s: Dictionary = _solids[i]
		if s.has("rect"):
			if (s["rect"] as Rect2).grow(m).has_point(p):
				return true
		elif s["on"] and p.distance_to(s["c"]) < float(s["r"]) + m:
			return true
	return false

func _clear(a: Vector2, b: Vector2, m: float) -> bool:
	var d := b - a
	var steps := int(d.length() / 1.2) + 1
	for i in range(1, steps + 1):
		if _solid_at(a + d * (float(i) / float(steps)), m):
			return false
	return true

func _build_drive_map() -> void:
	_drive_map.resize(COLS * ROWS)
	for y in ROWS:
		for x in COLS:
			var t := Vector2i(x, y)
			var ok := _is_road(t) or not _solid_at(_center(t), 0.9)
			_drive_map[y * COLS + x] = 1 if ok else 0

## ---- building the city -------------------------------------------------------------

func _build_ground() -> void:
	var outside := MeshInstance3D.new()
	var om := PlaneMesh.new()
	om.size = Vector2(MAP_W + 260, MAP_D + 260)
	om.material = _cmat("bg", "bg_alt", 0.3)
	outside.mesh = om
	outside.position = Vector3(MAP_W * 0.5, -0.05, MAP_D * 0.5)
	world.add_child(outside)
	var road := MeshInstance3D.new()
	var rm := PlaneMesh.new()
	rm.size = Vector2(MAP_W, MAP_D)
	rm.material = _cmat("bg_alt", "ink", 0.06, 0.0, 0.7)
	road.mesh = rm
	road.position = Vector3(MAP_W * 0.5, 0.0, MAP_D * 0.5)
	world.add_child(road)
	# a low neon barrier round the edge of town
	var bar := mat("hazard", 0.9)
	_box(Vector3(MAP_W, 0.5, 0.3), Vector3(MAP_W * 0.5, 0.25, -0.15), bar)
	_box(Vector3(MAP_W, 0.5, 0.3), Vector3(MAP_W * 0.5, 0.25, MAP_D + 0.15), bar)
	_box(Vector3(0.3, 0.5, MAP_D), Vector3(-0.15, 0.25, MAP_D * 0.5), bar)
	_box(Vector3(0.3, 0.5, MAP_D), Vector3(MAP_W + 0.15, 0.25, MAP_D * 0.5), bar)

func _build_blocks() -> void:
	for b in _blocks:
		if b["gone"]:
			continue
		var r: Rect2 = b["rect"]
		var c := r.get_center()
		var kind: String = b["kind"]
		if b["raised"]:
			_box(Vector3(r.size.x, KERB, r.size.y), Vector3(c.x, KERB * 0.5, c.y), _cmat("bg_alt", "ink", 0.16), false)
			_box(Vector3(r.size.x - SIDEWALK * 2.0 + 0.4, 0.02, r.size.y - SIDEWALK * 2.0 + 0.4),
				Vector3(c.x, KERB + 0.01, c.y), _cmat("bg", "bg_alt", 0.5), false)
		match kind:
			"towers": _build_towers(r)
			"shops": _build_shops(r)
			"houses": _build_houses(r)
			"park": _build_park(r)
			"plaza": _build_plaza(r)
			"parking": _build_parking(r)

## A model scaled so its footprint is `foot` wide, turned to face `face` (an axis), with
## its footprint registered as a solid. Returns its height.
func _place(name: String, foot: float, at: Vector2, face: Vector2, base_y: float, solid: bool = true) -> float:
	var m := model(name, 1.0)
	var bb: AABB = m.get_meta("aabb")
	var k := foot / maxf(bb.size.x, bb.size.z)
	m.scale = Vector3.ONE * k
	m.rotation.y = atan2(face.x, face.y)
	m.position = Vector3(at.x, base_y, at.y)
	world.add_child(m)
	var sx := bb.size.x * k
	var sz := bb.size.z * k
	if absf(face.x) > absf(face.y):
		var tmp := sx
		sx = sz
		sz = tmp
	if solid:
		_add_rect(Rect2(at - Vector2(sx, sz) * 0.5, Vector2(sx, sz)))
	return bb.size.y * k

## A tree `tall` units high (trees are scaled by height, not footprint).
func _tree(at: Vector2, tall: float, base_y: float, solid: bool = true) -> void:
	var m := model("tree-large" if _crng.randf() < 0.55 else "tree-small", tall)
	m.position = Vector3(at.x, base_y, at.y)
	m.rotation.y = _crng.randf() * TAU
	world.add_child(m)
	if solid:
		_add_circle(at, 0.45)

## The street side a spot in a block is nearest to, as an axis.
func _outward(r: Rect2, p: Vector2) -> Vector2:
	var dl := p.x - r.position.x
	var dr := r.end.x - p.x
	var dt := p.y - r.position.y
	var db := r.end.y - p.y
	var m := minf(minf(dl, dr), minf(dt, db))
	if m == dl:
		return Vector2.LEFT
	if m == dr:
		return Vector2.RIGHT
	if m == dt:
		return Vector2.UP
	return Vector2.DOWN

## Cell centres of an even grid over `r`, about `cell` apart.
func _grid(r: Rect2, cell: float) -> Array:
	var nx := maxi(1, roundi(r.size.x / cell))
	var nz := maxi(1, roundi(r.size.y / cell))
	var step := Vector2(r.size.x / nx, r.size.y / nz)
	var out: Array = []
	for i in nx:
		for j in nz:
			out.append({"p": r.position + step * Vector2(i + 0.5, j + 0.5), "edge": i == 0 or j == 0 or i == nx - 1 or j == nz - 1, "step": step})
	return out

func _build_towers(r: Rect2) -> void:
	var inner := r.grow(-SIDEWALK)
	for g in _grid(inner, 5.6):
		var p: Vector2 = g["p"]
		var face := _outward(inner, p)
		var h := _place(TOWERS[_crng.randi() % TOWERS.size()], minf(g["step"].x, g["step"].y) - 0.5, p, face, KERB)
		# a neon band round the top
		var role: String = NEON[_crng.randi() % NEON.size()]
		var w: float = minf(g["step"].x, g["step"].y) - 0.5
		var top := KERB + h + 0.08
		var m := mat(role, 1.3)
		_box(Vector3(w, 0.16, 0.16), Vector3(p.x, top, p.y - w * 0.5), m, false)
		_box(Vector3(w, 0.16, 0.16), Vector3(p.x, top, p.y + w * 0.5), m, false)
		_box(Vector3(0.16, 0.16, w), Vector3(p.x - w * 0.5, top, p.y), m, false)
		_box(Vector3(0.16, 0.16, w), Vector3(p.x + w * 0.5, top, p.y), m, false)

func _build_shops(r: Rect2) -> void:
	var inner := r.grow(-SIDEWALK)
	for g in _grid(inner, 3.6):
		if not g["edge"]:
			_tree(g["p"], 3.6, KERB, false)
			continue
		var p: Vector2 = g["p"]
		var face := _outward(inner, p)
		var foot: float = minf(g["step"].x, g["step"].y) - 0.15
		var h := _place(SHOPS[_crng.randi() % SHOPS.size()], foot, p, face, KERB)
		if _crng.randf() < 0.55:
			# a neon sign over the shop front
			var role: String = NEON[_crng.randi() % NEON.size()]
			var front := p + face * (foot * 0.5 + 0.06)
			var size := Vector3(foot * 0.55, 0.35, 0.08) if absf(face.y) > 0.5 else Vector3(0.08, 0.35, foot * 0.55)
			_box(size, Vector3(front.x, KERB + minf(h * 0.55, 2.6), front.y), mat(role, 1.4), false)

func _build_houses(r: Rect2) -> void:
	var inner := r.grow(-SIDEWALK - 0.6)
	var cells := _grid(inner, 5.4)
	for g in cells:
		var p: Vector2 = g["p"]
		var face := _outward(inner, p)
		var foot: float = minf(g["step"].x, g["step"].y) - 1.6
		_place(HOUSES[_crng.randi() % HOUSES.size()], foot, p - face * 0.5, face, KERB)
	# trees in the gaps between houses
	var c := r.get_center()
	for k in 4:
		var tp := c + Vector2(_crng.randf_range(-0.8, 0.8), _crng.randf_range(-0.8, 0.8))
		if k > 0:
			tp = r.position + Vector2(SIDEWALK + 0.6, SIDEWALK + 0.6) + Vector2(_crng.randf(), _crng.randf()) * (r.size - Vector2.ONE * (SIDEWALK + 0.6) * 2.0)
			if _solid_at(tp, 0.6):
				continue
		_tree(tp, _crng.randf_range(3.0, 4.2), KERB)

func _build_park(r: Rect2) -> void:
	var c := r.get_center()
	_flat(r.size - Vector2(0.6, 0.6), Vector3(c.x, 0.02, c.y), _cmat("bg_alt", "friend", 0.22, 0.05))
	var path := _cmat("bg_alt", "ink", 0.22)
	_flat(Vector2(r.size.x - 0.6, 2.2), Vector3(c.x, 0.03, c.y), path)
	_flat(Vector2(2.2, r.size.y - 0.6), Vector3(c.x, 0.03, c.y), path)
	# fountain
	var bowl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.2
	cm.bottom_radius = 2.4
	cm.height = 0.6
	cm.material = _cmat("bg_alt", "ink", 0.3)
	bowl.mesh = cm
	bowl.position = Vector3(c.x, 0.3, c.y)
	world.add_child(bowl)
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 1.9
	wm.bottom_radius = 1.9
	wm.height = 0.05
	wm.material = mat("player", 0.8)
	water.mesh = wm
	water.position = Vector3(c.x, 0.62, c.y)
	world.add_child(water)
	var jet := MeshInstance3D.new()
	var jm := CylinderMesh.new()
	jm.top_radius = 0.08
	jm.bottom_radius = 0.3
	jm.height = 2.2
	jm.material = mat("ink", 0.9)
	jet.mesh = jm
	jet.position = Vector3(c.x, 1.6, c.y)
	world.add_child(jet)
	_add_circle(c, 2.4)
	var n := int(r.get_area() / 22.0)
	for k in n:
		var tp := r.position + Vector2(1.2, 1.2) + Vector2(_crng.randf(), _crng.randf()) * (r.size - Vector2(2.4, 2.4))
		if absf(tp.x - c.x) < 2.2 or absf(tp.y - c.y) < 2.2 or _solid_at(tp, 1.4):
			continue
		_tree(tp, _crng.randf_range(3.2, 4.8), 0.0)

func _build_plaza(r: Rect2) -> void:
	var c := r.get_center()
	_flat(r.size - Vector2(0.4, 0.4), Vector3(c.x, 0.02, c.y), _cmat("bg_alt", "accent", 0.16))
	for k in 3:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 3.0 + k * 2.2
		tm.outer_radius = 3.25 + k * 2.2
		tm.material = mat(NEON[k % NEON.size()], 0.9)
		ring.mesh = tm
		ring.scale = Vector3(1, 0.05, 1)
		ring.position = Vector3(c.x, 0.04, c.y)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(ring)
	# the monument: a glowing obelisk
	_box(Vector3(2.0, 0.6, 2.0), Vector3(c.x, 0.3, c.y), _cmat("bg_alt", "ink", 0.3))
	_box(Vector3(0.9, 6.5, 0.9), Vector3(c.x, 3.6, c.y), mat("accent", 0.7))
	_add_circle(c, 1.3)
	var spots := 8 if r.get_area() < 300.0 else 14
	for k in spots:
		var a := TAU * k / spots
		var rad := minf(r.size.x, r.size.y) * 0.5 - 1.6
		var p := c + Vector2(cos(a) * (r.size.x * 0.5 - 1.6), sin(a) * (r.size.y * 0.5 - 1.6)) if r.size.x != r.size.y else c + Vector2(cos(a), sin(a)) * rad
		if absf(p.x - c.x) < 2.0 or absf(p.y - c.y) < 2.0:
			continue   # leave the four ways in open
		_place("planter", 1.6, p, Vector2.DOWN, 0.0)
		_tree(p, 2.4, 0.15, false)

func _build_parking(r: Rect2) -> void:
	var c := r.get_center()
	_flat(r.size - Vector2(0.4, 0.4), Vector3(c.x, 0.02, c.y), _cmat("bg", "bg_alt", 0.7))
	var line := _cmat("ink", "bg_alt", 0.4, 0.2)
	var along_x := r.size.x >= r.size.y
	var length := r.size.x if along_x else r.size.y
	var depth := r.size.y if along_x else r.size.x
	var n := int((length - 2.0) / 2.6)
	for side in [-1.0, 1.0]:
		var row := depth * 0.5 - 2.6
		for i in n:
			var s := -length * 0.5 + 1.0 + (i + 0.5) * (length - 2.0) / n
			var p := c + (Vector2(s, side * row) if along_x else Vector2(side * row, s))
			var lp := c + (Vector2(s - 1.3, side * row) if along_x else Vector2(side * row, s - 1.3))
			var lsize := Vector2(0.1, 3.6) if along_x else Vector2(3.6, 0.1)
			_flat(lsize, Vector3(lp.x, 0.04, lp.y), line)
			if _crng.randf() < 0.7:
				var face := Vector2(0, -side) if along_x else Vector2(-side, 0)
				var kind: String = PARKED[_crng.randi() % PARKED.size()]
				var len: float = CARS[kind]["len"]
				_place(kind, len, p, face, 0.0)

## Buildings beyond the barrier, so the edge of town is a skyline, not a void.
func _build_skyline() -> void:
	var pts: Array = []
	var x := -4.0
	while x < MAP_W + 8.0:
		pts.append([Vector2(x, -9.0), Vector2.DOWN])
		pts.append([Vector2(x, MAP_D + 9.0), Vector2.UP])
		x += 9.0
	var z := 6.0
	while z < MAP_D - 2.0:
		pts.append([Vector2(-9.0, z), Vector2.RIGHT])
		pts.append([Vector2(MAP_W + 9.0, z), Vector2.LEFT])
		z += 9.0
	for e in pts:
		var names: Array = TOWERS if _crng.randf() < 0.4 else SHOPS
		_place(names[_crng.randi() % names.size()], _crng.randf_range(6.0, 8.0), e[0], e[1], 0.0, false)

## ---- street lamps -------------------------------------------------------------------

func _build_lamps() -> void:
	var spots: Array = []
	for b in _blocks:
		if b["gone"]:
			continue
		var r: Rect2 = (b["rect"] as Rect2).grow(-0.55)
		var y := KERB if b["raised"] else 0.0
		for side in 4:
			var a: Vector2
			var bb: Vector2
			var out: Vector2
			match side:
				0:
					a = r.position
					bb = Vector2(r.end.x, r.position.y)
					out = Vector2.UP
				1:
					a = Vector2(r.end.x, r.position.y)
					bb = r.end
					out = Vector2.RIGHT
				2:
					a = r.end
					bb = Vector2(r.position.x, r.end.y)
					out = Vector2.DOWN
				_:
					a = Vector2(r.position.x, r.end.y)
					bb = r.position
					out = Vector2.LEFT
			var n := maxi(1, roundi(a.distance_to(bb) / 12.0))
			for k in n:
				var p := a.lerp(bb, (k + 0.5) / n)
				if _solid_at(p, 0.5):
					continue
				spots.append([p, out, y])
	_pools = MultiMesh.new()
	_pools.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	_pools.mesh = pm
	_pools.instance_count = spots.size()
	var pool_node := MultiMeshInstance3D.new()
	pool_node.multimesh = _pools
	pool_node.material_override = _gmat("warn", 0.28, _radial)
	pool_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(pool_node)
	var bulb_mat := mat("warn", 2.0)
	for i in spots.size():
		var p: Vector2 = spots[i][0]
		var out: Vector2 = spots[i][1]
		var lamp := Node3D.new()
		lamp.position = Vector3(p.x, spots[i][2], p.y)
		world.add_child(lamp)
		var m := model("light-square", 5.0)
		# the arm reaches along the model's -Z; turn it out over the road
		m.rotation.y = atan2(-out.x, -out.y)
		lamp.add_child(m)
		var head := out * 1.75
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.3
		bulb.mesh = sm
		bulb.material_override = bulb_mat
		bulb.position = Vector3(head.x, 4.6, head.y)
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(bulb)
		var hp := p + head
		_pools.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(hp.x, 0.05 + spots[i][2], hp.y)))
		var s := _add_circle(p, 0.25, _lamps.size())
		_lamps.append({"node": lamp, "bulb": bulb, "pool": i, "solid": s, "alive": true})

func _knock_lamp(i: int, vel: Vector2, by_you: bool) -> void:
	var l: Dictionary = _lamps[i]
	if not l["alive"]:
		return
	l["alive"] = false
	_solids[l["solid"]]["on"] = false
	_pools.set_instance_transform(l["pool"], Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	var bulb: MeshInstance3D = l["bulb"]
	bulb.material_override = mat("warn", 0.0)
	var node: Node3D = l["node"]
	var d := vel.normalized()
	var axis := Vector3(d.y, 0.0, -d.x).normalized()
	var tw := node.create_tween()
	tw.tween_method(func(a: float) -> void: node.basis = Basis(axis, a), 0.0, 1.45, 0.45) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var at := Vector3(node.position.x, 1.0, node.position.z)
	_spark(at)
	Probe.count("lamp_down")
	if by_you:
		Audio.play("impact_metal", 0.2, -6.0)
		add_score(10)
		Juice.text(self, to_screen(at + Vector3(0, 1.5, 0)), "+$10", Palette.col("warn"))

## ---- road markings -------------------------------------------------------------------

func _build_markings() -> void:
	var dashes: Array = []     # Transform3D
	var stripes: Array = []
	for j in BLOCKS_Y + 1:
		var z := j * CELL + ROAD * 0.5
		for i in BLOCKS_X:
			if not _is_road(Vector2i(i * PERIOD + 3, j * PERIOD)):
				continue
			var x := i * CELL + ROAD + 2.4
			while x < (i + 1) * CELL - 2.4:
				dashes.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 1, 0.16)), Vector3(x + 0.7, 0.03, z)))
				x += 3.0
	for i in BLOCKS_X + 1:
		var x := i * CELL + ROAD * 0.5
		for j in BLOCKS_Y:
			if not _is_road(Vector2i(i * PERIOD, j * PERIOD + 3)):
				continue
			var z := j * CELL + ROAD + 2.4
			while z < (j + 1) * CELL - 2.4:
				dashes.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.16, 1, 1.4)), Vector3(x, 0.03, z + 0.7)))
				z += 3.0
	for i in BLOCKS_X + 1:
		for j in BLOCKS_Y + 1:
			var o := Vector2(i * CELL, j * CELL)
			for k in 7:
				var s := 0.6 + k * 0.97
				if i < BLOCKS_X and _is_road(Vector2i(i * PERIOD + 2, j * PERIOD)):
					stripes.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 1, 0.45)), Vector3(o.x + ROAD + 0.9, 0.03, o.y + s)))
				if i > 0 and _is_road(Vector2i(i * PERIOD - 1, j * PERIOD)):
					stripes.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 1, 0.45)), Vector3(o.x - 0.9, 0.03, o.y + s)))
				if j < BLOCKS_Y and _is_road(Vector2i(i * PERIOD, j * PERIOD + 2)):
					stripes.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.45, 1, 1.2)), Vector3(o.x + s, 0.03, o.y + ROAD + 0.9)))
				if j > 0 and _is_road(Vector2i(i * PERIOD, j * PERIOD - 1)):
					stripes.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.45, 1, 1.2)), Vector3(o.x + s, 0.03, o.y - 0.9)))
	_multi(dashes, mat("warn", 0.5))
	_multi(stripes, _cmat("ink", "bg_alt", 0.55, 0.1))

func _multi(xfs: Array, m: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	mm.mesh = pm
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)

## ---- effects ------------------------------------------------------------------------

func _build_fx() -> void:
	_skid_mm = MultiMesh.new()
	_skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	_skid_mm.mesh = pm
	_skid_mm.instance_count = 700
	for i in 700:
		_skid_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	var sk := MultiMeshInstance3D.new()
	sk.multimesh = _skid_mm
	var skm := StandardMaterial3D.new()
	skm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dark := Palette.col("bg").darkened(0.6)
	skm.albedo_color = Color(dark.r, dark.g, dark.b, 0.55)
	sk.material_override = skm
	sk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(sk)

	_smoke = CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	var smm := StandardMaterial3D.new()
	smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smm.vertex_color_use_as_albedo = true
	sm.material = smm
	_smoke.mesh = sm
	_smoke.amount = 40
	_smoke.lifetime = 0.9
	_smoke.local_coords = false
	_smoke.emitting = false
	_smoke.direction = Vector3.UP
	_smoke.spread = 50.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.6
	_smoke.gravity = Vector3(0, 1.2, 0)
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.6
	var ramp := Gradient.new()
	var ink := Palette.col("ink")
	ramp.set_color(0, Color(ink.r, ink.g, ink.b, 0.35))
	ramp.set_color(1, Color(ink.r, ink.g, ink.b, 0.0))
	_smoke.color_ramp = ramp
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_smoke)

	for i in 4:
		var sp := CPUParticles3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * 0.09
		bm.material = mat("warn", 2.5)
		sp.mesh = bm
		sp.amount = 16
		sp.lifetime = 0.45
		sp.one_shot = true
		sp.explosiveness = 1.0
		sp.emitting = false
		sp.local_coords = false
		sp.direction = Vector3.UP
		sp.spread = 180.0
		sp.initial_velocity_min = 5.0
		sp.initial_velocity_max = 11.0
		sp.gravity = Vector3(0, -18, 0)
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(sp)
		_sparks.append(sp)

func _spark(at: Vector3) -> void:
	var sp: CPUParticles3D = _sparks[_spark_i]
	_spark_i = (_spark_i + 1) % _sparks.size()
	sp.position = at
	sp.restart()

func _skid(c: Car, hb: bool) -> void:
	var fwd := Vector2.from_angle(c.heading)
	var right := fwd.orthogonal()
	var lat := absf(c.vel.dot(right))
	var sliding := lat > 6.0 or (hb and c.vel.length() > 7.0)
	if c == _player:
		_smoke.emitting = sliding
		var rear := c.pos - fwd * c.r
		_smoke.position = Vector3(rear.x, 0.3, rear.y)
	if not sliding:
		c.skid_l = Vector2.INF
		return
	var rear := c.pos - fwd * (c.r * 0.85)
	var l := rear + right * 0.6
	var r := rear - right * 0.6
	if c.skid_l != Vector2.INF:
		_skid_seg(c.skid_l, l)
		_skid_seg(c.skid_r, r)
	c.skid_l = l
	c.skid_r = r

func _skid_seg(a: Vector2, b: Vector2) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.05:
		return
	var u := d / len
	var basis := Basis(Vector3(u.y, 0, -u.x) * 0.28, Vector3.UP, Vector3(u.x, 0, u.y) * len)
	var m := (a + b) * 0.5
	_skid_mm.set_instance_transform(_skid_next, Transform3D(basis, Vector3(m.x, 0.035, m.y)))
	_skid_next = (_skid_next + 1) % _skid_mm.instance_count

## ---- cars -------------------------------------------------------------------------

func _make_car(kind: String) -> Car:
	var c := Car.new()
	c.node = Node3D.new()
	world.add_child(c.node)
	_set_model(c, kind)
	# headlight beams on the road
	var beam := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.2, 7.0)
	beam.mesh = pm
	beam.material_override = _gmat("warn", 0.22, _beam)
	beam.position = Vector3(0, 0.06, c.r + 3.6)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.node.add_child(beam)
	return c

func _set_model(c: Car, kind: String) -> void:
	if c.body != null:
		c.body.queue_free()
	var st: Dictionary = CARS[kind]
	c.kind = kind
	c.top = st["top"]
	c.accel = st["accel"]
	c.grip = st["grip"]
	c.r = float(st["len"]) * 0.38
	c.body = model(kind, st["len"])
	c.node.add_child(c.body)

func _dress_player() -> void:
	var glow := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.4, 4.6)
	glow.mesh = pm
	glow.material_override = _gmat("player", 0.55, _radial)
	glow.position = Vector3(0, 0.04, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.node.add_child(glow)
	_headlight = SpotLight3D.new()
	_headlight.light_color = Palette.col("warn").lerp(Palette.col("ink"), 0.6)
	_headlight.light_energy = 5.0
	_headlight.spot_range = 22.0
	_headlight.spot_angle = 34.0
	_headlight.position = Vector3(0, 1.1, 1.2)
	_headlight.rotation_degrees = Vector3(-14, 180, 0)
	_player.node.add_child(_headlight)

func _dress_cop(c: Car) -> void:
	c.bar_a = MeshInstance3D.new()
	c.bar_b = MeshInstance3D.new()
	for k in 2:
		var mi: MeshInstance3D = c.bar_a if k == 0 else c.bar_b
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.16, 0.32)
		mi.mesh = bm
		mi.position = Vector3(-0.3 if k == 0 else 0.3, 1.38, -0.15)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.node.add_child(mi)
	c.light = OmniLight3D.new()
	c.light.omni_range = 9.0
	c.light.light_energy = 3.0
	c.light.position = Vector3(0, 2.2, 0)
	c.node.add_child(c.light)
	_flash_cop(c)

func _flash_cop(c: Car) -> void:
	c.lights_on = not c.lights_on
	c.bar_a.material_override = mat("hazard", 3.0 if c.lights_on else 0.2)
	c.bar_b.material_override = mat("player", 0.2 if c.lights_on else 3.0)
	c.light.light_color = Palette.col("hazard") if c.lights_on else Palette.col("player")

## ---- the frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished or _player == null:
		return
	var dt := minf(delta, 0.05)
	_t += dt
	Audio.music(MUSIC)
	_update_player(dt)
	_update_cops(dt)
	if finished:
		return
	_update_traffic(dt)
	_update_peds(dt)
	_update_coins(dt)
	_update_job(dt)
	_update_camera(dt)
	_update_marker()
	_siren_t += dt
	if _siren_t > 0.13:
		_siren_t = 0.0
		for x in _cops:
			_flash_cop(x)
	_hud.queue_redraw()

## Shared by the player and the cops: steer towards a compass direction, at a limited
## turn rate; sideways speed bleeds off by `grip`, which is the drift.
func _drive(c: Car, want: Vector2, top: float, accel: float, grip: float, corner: float,
		turn_mul: float, dt: float) -> void:
	var mag := minf(1.0, want.length())
	var spd := c.vel.dot(Vector2.from_angle(c.heading))
	if mag > 0.15:
		var diff := wrapf(want.angle() - c.heading, -PI, PI)
		var k := clampf(absf(spd) / maxf(top, 1.0), 0.0, 1.0)
		var rate := lerpf(5.0, 3.1, k) * turn_mul * clampf(0.4 + absf(spd) / 5.5, 0.4, 1.0)
		c.heading += clampf(diff, -rate * dt, rate * dt)
	var fwd := Vector2.from_angle(c.heading)
	var right := fwd.orthogonal()
	spd = c.vel.dot(fwd)
	var lat := c.vel.dot(right)
	if mag > 0.15:
		var off := absf(wrapf(want.angle() - c.heading, -PI, PI))
		if off > 2.0:
			spd = move_toward(spd, 2.7, accel * 1.6 * dt)
		else:
			var goal := top * mag * clampf(1.0 - corner * off, 0.3, 1.0)
			spd = move_toward(spd, goal, (accel if spd < goal else accel * 1.2) * dt)
	else:
		spd = move_toward(spd, 0.0, 18.5 * dt)
	lat *= exp(-grip * dt)
	c.vel = fwd * spd + right * lat
	c.roll = lerpf(c.roll, clampf(-lat * 0.012, -0.12, 0.12), 1.0 - exp(-8.0 * dt))

func _update_player(dt: float) -> void:
	var p := _player
	var want := PInput.dir()
	if _stick_on and _stick_vec != Vector2.ZERO:
		want = _stick_vec
	var hb := PInput.pressed("action_a")
	var top := p.top * (0.66 if _on_grass(p.pos) else 1.0)
	_drive(p, want, top, p.accel, 2.0 if hb else p.grip, 0.25, 1.45 if hb else 1.0, dt)
	if hb:
		var fwd := Vector2.from_angle(p.heading)
		p.vel -= fwd * minf(p.vel.dot(fwd), 15.0 * dt)
	p.pos += p.vel * dt
	var impact := _hit_solids(p, dt)
	for x in _traffic:
		var t: Car = x
		var hit := _bump(p, t, 0.0)
		if hit > 12.0 and t.knocked <= 0.0:
			t.knocked = 1.2
			t.spin = _rng.randf_range(-1.4, 1.4)
			Audio.play("impact_plate", 0.15, -4.0)
		impact = maxf(impact, hit)
	p.crash_cd -= dt
	if impact > 9.0 and p.crash_cd <= 0.0:
		p.crash_cd = 0.25
		shake3d(clampf(impact / 4.0, 2.0, 7.0))
		if impact > 22.0:
			Juice.hitstop(0.05)
		Audio.play("impact_metal", 0.15, clampf(-14.0 + impact / 2.0, -14.0, 0.0))
		var f := Vector2.from_angle(p.heading) * p.r
		_spark(Vector3(p.pos.x + f.x, 0.6, p.pos.y + f.y))
		Probe.count("crash")
	p.y = lerpf(p.y, _ground_y(p.pos), 1.0 - exp(-12.0 * dt))
	_skid(p, hb)
	p.sync()
	if _invuln > 0.0:
		_invuln -= dt
		p.node.visible = int(_invuln * 10.0) % 2 == 1 or _invuln <= 0.0

## Pushes a car out of every solid it overlaps and off the edge of town; returns how
## hard it hit. A lamp post hit at speed falls over instead of stopping you. Hitting a
## wall square-on nudges the car along it towards the nearer corner, so steering
## straight into a building slides round it instead of sticking.
func _hit_solids(c: Car, dt: float) -> float:
	var r := c.r
	var p := c.pos
	var impact := 0.0
	for tx in range(floori((p.x - r) / TILE), floori((p.x + r) / TILE) + 1):
		for tz in range(floori((p.y - r) / TILE), floori((p.y + r) / TILE) + 1):
			var arr = _hash.get(Vector2i(tx, tz))
			if arr == null:
				continue
			for i in arr:
				var s: Dictionary = _solids[i]
				var n := Vector2.ZERO
				var along_bias := Vector2.ZERO
				if s.has("rect"):
					var rect: Rect2 = s["rect"]
					if not rect.grow(r).has_point(p):
						continue
					var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
					var d := p - q
					var dl := d.length()
					if dl > 0.001:
						if dl >= r:
							continue
						n = d / dl
						p = q + n * r
					else:
						var gl := p.x - rect.position.x
						var gr := rect.end.x - p.x
						var gt := p.y - rect.position.y
						var gb := rect.end.y - p.y
						var m := minf(minf(gl, gr), minf(gt, gb))
						if m == gl:
							n = Vector2.LEFT
							p.x = rect.position.x - r
						elif m == gr:
							n = Vector2.RIGHT
							p.x = rect.end.x + r
						elif m == gt:
							n = Vector2.UP
							p.y = rect.position.y - r
						else:
							n = Vector2.DOWN
							p.y = rect.end.y + r
					var along := n.orthogonal()
					var side := signf((p - rect.get_center()).dot(along))
					along_bias = along * (side if side != 0.0 else 1.0)
				else:
					if not s["on"]:
						continue
					var cc: Vector2 = s["c"]
					var rr: float = r + float(s["r"])
					var d := p - cc
					var dl := d.length()
					if dl >= rr:
						continue
					if int(s["lamp"]) >= 0 and c.vel.length() > 5.0:
						_knock_lamp(s["lamp"], c.vel, c == _player)
						c.vel *= 0.8
						continue
					n = d / dl if dl > 0.001 else Vector2.UP
					p = cc + n * rr
				var vn := c.vel.dot(n)
				if vn < 0.0:
					c.vel -= n * vn * 1.3
					c.vel *= 0.94
					impact = maxf(impact, -vn)
					c.vel += along_bias * 28.0 * dt
	if p.x < r:
		p.x = r
		impact = maxf(impact, -c.vel.x)
		c.vel.x = absf(c.vel.x) * 0.3
	elif p.x > MAP_W - r:
		p.x = MAP_W - r
		impact = maxf(impact, c.vel.x)
		c.vel.x = -absf(c.vel.x) * 0.3
	if p.y < r:
		p.y = r
		impact = maxf(impact, -c.vel.y)
		c.vel.y = absf(c.vel.y) * 0.3
	elif p.y > MAP_D - r:
		p.y = MAP_D - r
		impact = maxf(impact, c.vel.y)
		c.vel.y = -absf(c.vel.y) * 0.3
	c.pos = p
	return impact

## Two cars overlapping: separate them. `share` is how much of the shove `b` takes
## (0 for traffic, which stays on its lane). Returns the closing speed.
func _bump(a: Car, b: Car, share: float) -> float:
	var d := a.pos - b.pos
	var dl := d.length()
	var r := a.r + b.r
	if dl >= r or dl < 0.001:
		return 0.0
	var n := d / dl
	var pen := r - dl
	a.pos += n * pen * (1.0 - share)
	b.pos -= n * pen * share
	var rel := (a.vel - b.vel).dot(n)
	if rel >= 0.0:
		return 0.0
	a.vel -= n * rel * (1.0 - share) * 1.3
	b.vel += n * rel * share * 1.3
	return -rel

## ---- the police ----------------------------------------------------------------------

func _update_cops(dt: float) -> void:
	_flow_t -= dt
	if _flow_t <= 0.0:
		_flow_t = 0.25
		_rebuild_flow()
	if _t > COP_DELAY and _cops.size() < _stars:
		_spawn_cop()
	var top := minf(COP_TOP + 1.5 * _stars + minf(3.0, _t * 0.02), 24.5)
	_cop_near = false
	for x in _cops:
		var c: Car = x
		if c.stun > 0.0:
			c.stun -= dt
			_drive(c, (c.pos - _player.pos).normalized(), top * 0.85, 32.0, 11.0, 0.55, 1.0, dt)
		else:
			var goal := _cop_goal(c)
			_drive(c, (goal - c.pos).normalized(), top, 33.0, 11.0, 0.55, 1.0, dt)
		c.pos += c.vel * dt
		var hit := _hit_solids(c, dt)
		if hit > 16.0 and c.pos.distance_to(_player.pos) < 40.0:
			var f := Vector2.from_angle(c.heading) * c.r
			_spark(Vector3(c.pos.x + f.x, 0.6, c.pos.y + f.y))
		for t in _traffic:
			_bump(c, t, 0.0)
		_skid(c, false)
		if c.stun <= 0.0 and c.vel.length() < 2.0:
			c.stuck += dt
			if c.stuck > 1.2:
				c.stuck = 0.0
				c.vel = -Vector2.from_angle(c.heading) * 11.0
				c.heading += _rng.randf_range(-1.2, 1.2)
		else:
			c.stuck = 0.0
		if c.pos.distance_to(_player.pos) < 28.0:
			_cop_near = true
		c.y = lerpf(c.y, _ground_y(c.pos), 1.0 - exp(-12.0 * dt))
		c.sync()
	for i in _cops.size():
		for j in range(i + 1, _cops.size()):
			_bump(_cops[i], _cops[j], 0.5)
	# a cop on you fills the bust meter; get away before it is full
	var touching := false
	for x in _cops:
		var c: Car = x
		if c.stun <= 0.0 and c.pos.distance_to(_player.pos) < c.r + _player.r + 0.6:
			touching = true
		_bump(_player, c, 0.5)
	if touching and _invuln <= 0.0:
		var slow := _player.vel.length() < 5.0
		_bust += dt / BUST_TIME * (2.0 if slow else 1.0)
		if _bust >= 1.0:
			_busted()
	else:
		_bust = maxf(0.0, _bust - dt * 0.8)

## Straight at you when it can see you, otherwise down the flow field.
func _cop_goal(c: Car) -> Vector2:
	var pp := _player.pos
	if c.pos.distance_to(pp) < 20.0 and _clear(c.pos, pp, 0.7):
		return pp + _player.vel * 0.25
	return _follow(_flow, c.pos, 4, pp)

func _rebuild_flow() -> void:
	_flow = _bfs(_tile_of(_player.pos))

## Steps from `src` to every drivable tile (-1 = cannot get there). Diagonal steps only
## where both sides are open, so nothing cuts a building's corner.
func _bfs(src: Vector2i) -> PackedInt32Array:
	var field := PackedInt32Array()
	field.resize(COLS * ROWS)
	field.fill(-1)
	field[src.y * COLS + src.x] = 0
	var q: Array[Vector2i] = [src]
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var d := field[cur.y * COLS + cur.x]
		for nt in _steps(cur):
			var i: int = nt.y * COLS + nt.x
			if field[i] != -1:
				continue
			field[i] = d + 1
			q.append(nt)
	return field

func _steps(cur: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in N8:
		var off: Vector2i = o
		var nt := cur + off
		if not _drivable(nt):
			continue
		if off.x != 0 and off.y != 0 and (not _drivable(Vector2i(cur.x + off.x, cur.y))
				or not _drivable(Vector2i(cur.x, cur.y + off.y))):
			continue
		out.append(nt)
	return out

func _field_at(field: PackedInt32Array, t: Vector2i) -> int:
	if not _in_grid(t) or field.is_empty():
		return -1
	return field[t.y * COLS + t.x]

## The tiles downhill from `from` on `field`, at most `steps` of them.
func _descend(field: PackedInt32Array, from: Vector2, steps: int) -> Array:
	var cur := _tile_of(from)
	var path: Array = []
	for step in steps:
		var best := cur
		var bd := _field_at(field, cur)
		if bd < 0:
			bd = 1 << 30
		for nt in _steps(cur):
			var d := _field_at(field, nt)
			if d >= 0 and d < bd:
				bd = d
				best = nt
		if best == cur:
			break
		cur = best
		path.append(cur)
	return path

## Where to steer to follow `field`: the furthest of the next few tiles with a clear line.
func _follow(field: PackedInt32Array, from: Vector2, steps: int, fallback: Vector2) -> Vector2:
	var path := _descend(field, from, steps)
	if path.is_empty():
		return fallback
	for i in range(path.size() - 1, -1, -1):
		var p := _center(path[i])
		if i == 0 or _clear(from, p, 0.6):
			return p
	return fallback

## A new police car comes round a corner just out of sight: off screen, but not across town.
func _spawn_cop() -> void:
	var view := _view.grow(6.0)
	var spots: Array = []
	var fallback := Vector2.INF
	for attempt in 300:
		var t := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		if not _is_road(t):
			continue
		var p := _center(t)
		if view.has_point(p):
			continue
		var d := p.distance_to(_player.pos)
		if d >= 32.0 and d <= 60.0:
			spots.append(p)
		elif d > 60.0 and fallback == Vector2.INF:
			fallback = p
	if spots.is_empty() and fallback == Vector2.INF:
		return
	var p: Vector2 = spots[_rng.randi() % spots.size()] if not spots.is_empty() else fallback
	var c := _make_car("police")
	_dress_cop(c)
	c.pos = p
	c.heading = (_player.pos - p).angle()
	c.sync()
	_cops.append(c)
	track3d(c.node, "x")
	Probe.event("cop_spawn", {"cops": _cops.size()})
	Audio.play("impact_bell", 0.05, -10.0)

func _set_stars(n: int) -> void:
	var was := _stars
	_stars = clampi(n, 1, MAX_STARS)
	if _stars > was:
		Probe.event("wanted_up", {"stars": _stars})
	while _cops.size() > _stars:
		var far: Car = _cops[0]
		for x in _cops:
			var c: Car = x
			if c.pos.distance_to(_player.pos) > far.pos.distance_to(_player.pos):
				far = c
		_cops.erase(far)
		far.node.queue_free()

func _busted() -> void:
	Probe.event("busted", {"stars": _stars, "lives": lives - 1})
	Probe.capture("busted")
	_show_banner("BUSTED", "hazard")
	Audio.play("impact_punch")
	lose_life()
	hit3d(6.0)
	if finished:
		return
	_invuln = INVULN
	_bust = 0.0
	for x in _cops:
		var c: Car = x
		c.stun = RETREAT
	_player.vel *= 0.2
	_set_stars(_stars - 1)

## ---- traffic ---------------------------------------------------------------------------

func _spawn_traffic() -> void:
	for attempt in 120:
		var t := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		var dirs := _lane_dirs(t)
		if dirs.size() != 1:
			continue
		var p := _center(t)
		if _player != null and p.distance_to(_player.pos) < 18.0:
			continue
		var crowded := false
		for x in _traffic:
			if (x as Car).pos.distance_to(p) < 6.0:
				crowded = true
				break
		if crowded:
			continue
		var c := _make_car(TRAFFIC_CARS[_rng.randi() % TRAFFIC_CARS.size()])
		c.dir = dirs[0]
		c.to = t + c.dir
		c.from = p
		c.pos = p
		c.heading = Vector2(c.dir).angle()
		c.speed = _rng.randf_range(7.0, 10.0) * (0.8 if c.kind in ["garbage-truck", "delivery"] else 1.0)
		c.sync()
		_traffic.append(c)
		track3d(c.node, "o")
		return

func _next_dir(t: Vector2i, cur: Vector2i) -> Vector2i:
	var opts: Array = []
	for d in _lane_dirs(t):
		var dv: Vector2i = d
		if dv == -cur:
			continue
		if _is_road(t + dv):
			opts.append(dv)
	if opts.is_empty():
		return -cur
	if opts.has(cur) and _rng.randf() < 0.55:
		return cur
	return opts[_rng.randi() % opts.size()]

func _ahead_blocked(c: Car) -> bool:
	var f := Vector2(c.dir)
	var side := f.orthogonal()
	var others: Array = [_player]
	others.append_array(_cops)
	others.append_array(_traffic)
	for x in others:
		var o: Car = x
		if o == c:
			continue
		var d := o.pos - c.pos
		var ahead := d.dot(f)
		if ahead > 0.3 and ahead < c.r + o.r + 1.6 and absf(d.dot(side)) < 1.4:
			return true
	for pd in _peds:
		if pd["mode"] != "cross":
			continue
		var d: Vector2 = (pd["pos"] as Vector2) - c.pos
		var ahead := d.dot(f)
		if ahead > 0.3 and ahead < c.r + 3.0 and absf(d.dot(side)) < 1.6:
			return true
	return false

func _update_traffic(dt: float) -> void:
	for x in _traffic:
		var c: Car = x
		var moving := false
		if c.knocked > 0.0:
			c.knocked -= dt
		else:
			var blocked := _ahead_blocked(c)
			c.wait = c.wait + dt if blocked else 0.0
			if not blocked or c.wait > 2.5:
				moving = true
				c.prog += c.speed * dt / TILE
				while c.prog >= 1.0:
					c.prog -= 1.0
					c.from = _center(c.to)
					c.dir = _next_dir(c.to, c.dir)
					c.to = c.to + c.dir
		c.pos = c.from.lerp(_center(c.to), c.prog)
		c.heading = lerp_angle(c.heading, Vector2(c.dir).angle(), 1.0 - exp(-10.0 * dt))
		c.spin *= exp(-2.0 * dt)
		c.vel = Vector2(c.dir) * c.speed if moving else Vector2.ZERO
		c.sync()

## ---- people -----------------------------------------------------------------------------

func _perim(r: Rect2, t: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	t = fposmod(t, 2.0 * (w + h))
	if t < w:
		return r.position + Vector2(t, 0)
	t -= w
	if t < h:
		return r.position + Vector2(w, t)
	t -= h
	if t < w:
		return r.position + Vector2(w - t, h)
	t -= w
	return r.position + Vector2(0, h - t)

func _perim_t(r: Rect2, p: Vector2) -> float:
	var w := r.size.x
	var h := r.size.y
	var dl := absf(p.x - r.position.x)
	var dr := absf(r.end.x - p.x)
	var dt := absf(p.y - r.position.y)
	var db := absf(r.end.y - p.y)
	var m := minf(minf(dl, dr), minf(dt, db))
	if m == dt:
		return clampf(p.x - r.position.x, 0.0, w)
	if m == dr:
		return w + clampf(p.y - r.position.y, 0.0, h)
	if m == db:
		return w + h + clampf(r.end.x - p.x, 0.0, w)
	return 2.0 * w + h + clampf(r.end.y - p.y, 0.0, h)

func _side_of(r: Rect2, t: float) -> int:
	var w := r.size.x
	var h := r.size.y
	t = fposmod(t, 2.0 * (w + h))
	if t < w:
		return 0
	if t < w + h:
		return 1
	if t < 2.0 * w + h:
		return 2
	return 3

func _spawn_ped() -> void:
	var a := Actor3D.new()
	world.add_child(a)
	a.set_character(PEOPLE[_rng.randi() % PEOPLE.size()], _rng.randf_range(1.9, 2.25))
	var pd := {"a": a, "path": Rect2(), "t": 0.0, "spd": 1.4, "mode": "walk", "timer": 0.0,
		"off": Vector2.ZERO, "offv": Vector2.ZERO, "pos": Vector2.ZERO, "goal": Vector2.ZERO,
		"next": Rect2(), "resume": "walk", "y": 0.0}
	_peds.append(pd)
	_place_ped(pd, true)

## Puts a person on a pavement near you, out of sight if it can.
func _place_ped(pd: Dictionary, first: bool) -> void:
	for attempt in 40:
		var b: Dictionary = _blocks[_rng.randi() % _blocks.size()]
		if b["gone"]:
			continue
		var r: Rect2 = b["rect"]
		if r.get_center().distance_to(_player.pos) > 70.0:
			continue
		var path := r.grow(-0.8)
		var t := _rng.randf() * 2.0 * (path.size.x + path.size.y)
		var p := _perim(path, t)
		var d := p.distance_to(_player.pos)
		if d < (6.0 if first else 20.0) or d > 55.0:
			continue
		if not first and _view.grow(2.0).has_point(p) and attempt < 30:
			continue
		if _solid_at(p, 0.3):
			continue
		pd["path"] = path
		pd["t"] = t
		pd["spd"] = _rng.randf_range(1.1, 1.8) * (1.0 if _rng.randf() < 0.5 else -1.0)
		pd["off"] = Vector2.ZERO
		pd["offv"] = Vector2.ZERO
		pd["pos"] = p
		var idle := _rng.randf() < 0.18
		_ped_mode(pd, "idle" if idle else "walk", _rng.randf_range(3.0, 7.0))
		var a: Actor3D = pd["a"]
		a.position = Vector3(p.x, _ground_y(p), p.y)
		return

func _ped_mode(pd: Dictionary, mode: String, timer: float = 0.0) -> void:
	pd["mode"] = mode
	pd["timer"] = timer
	var a: Actor3D = pd["a"]
	var spd: float = absf(pd["spd"])
	match mode:
		"walk", "cross":
			a.play("Walk", true, spd / 1.4)
		"idle":
			a.play("Idle", true, 1.0)
		"flee":
			a.play("Run", true, 1.2)
		"down":
			a.play("Death", false, 1.6)
		"up":
			a.play("StandUp", false, 1.3)

func _update_peds(dt: float) -> void:
	var cars: Array = [_player]
	cars.append_array(_cops)
	for pd in _peds:
		var a: Actor3D = pd["a"]
		var mode: String = pd["mode"]
		var prev: Vector2 = pd["pos"]
		var off: Vector2 = pd["off"]
		var offv: Vector2 = pd["offv"]
		pd["timer"] = float(pd["timer"]) - dt
		var path: Rect2 = pd["path"]
		var base := prev
		match mode:
			"walk":
				var t0: float = pd["t"]
				var t1: float = t0 + float(pd["spd"]) * dt
				pd["t"] = t1
				off *= exp(-0.9 * dt)
				base = _perim(path, t1)
				if _side_of(path, t0) != _side_of(path, t1):
					_maybe_cross(pd, base)
			"idle":
				base = _perim(path, pd["t"])
				if float(pd["timer"]) <= 0.0:
					_ped_mode(pd, "walk")
			"cross":
				var goal: Vector2 = pd["goal"]
				var cp: Vector2 = pd["pos"] - off
				var step := goal - cp
				var adv := absf(float(pd["spd"])) * 1.25 * dt
				if step.length() <= adv:
					pd["path"] = pd["next"]
					pd["t"] = _perim_t(pd["next"], goal)
					base = goal
					_ped_mode(pd, "walk")
				else:
					base = cp + step.normalized() * adv
			"flee", "down", "up":
				base = prev - off
				if mode == "flee" and float(pd["timer"]) <= 0.0:
					_ped_mode(pd, pd["resume"])
				elif mode == "down" and float(pd["timer"]) <= 0.0:
					_ped_mode(pd, "up", 1.6)
				elif mode == "up" and float(pd["timer"]) <= 0.0:
					_ped_mode(pd, pd["resume"])
		off += offv * dt
		offv *= exp(-5.0 * dt)
		var pos := base + off
		mode = pd["mode"]
		if mode in ["walk", "idle", "cross", "flee"]:
			for x in cars:
				var c: Car = x
				var d := pos - c.pos
				var sp := c.vel.length()
				if d.length() < c.r + 0.45 and sp > 4.0:
					_knock_ped(pd, c, pos)
					offv = pd["offv"]
					break
				if mode != "flee" and d.length() < 5.5 and sp > 6.0 and c.vel.dot(d) > 0.0:
					pd["resume"] = "cross" if mode == "cross" else "walk"
					var away := c.vel.orthogonal().normalized()
					if away.dot(d) < 0.0:
						away = -away
					offv = away * 6.0
					_ped_mode(pd, "flee", 0.8)
					if _rng.randf() < 0.3:
						Juice.text(self, to_screen(Vector3(pos.x, 2.2, pos.y)), "!", Palette.col("ink"))
					break
		pd["off"] = off
		pd["offv"] = offv
		pd["pos"] = pos
		var y: float = lerpf(pd["y"], _ground_y(pos), 1.0 - exp(-10.0 * dt))
		pd["y"] = y
		a.position = Vector3(pos.x, y, pos.y)
		var mv := pos - prev
		if mv.length() > 0.002 and pd["mode"] in ["walk", "cross", "flee"]:
			a.face(Vector3(mv.x, 0, mv.y))
		if pos.distance_to(_player.pos) > 62.0 and pd["mode"] != "down":
			_place_ped(pd, false)

## At a corner, now and then someone crosses the road to the block opposite.
func _maybe_cross(pd: Dictionary, at: Vector2) -> void:
	if _rng.randf() > 0.35:
		return
	var path: Rect2 = pd["path"]
	var c := path.get_center()
	var dirs := [Vector2(signf(at.x - c.x), 0), Vector2(0, signf(at.y - c.y))]
	var d: Vector2 = dirs[_rng.randi() % 2]
	var goal := at + d * (ROAD + 1.6)
	var b := _block_at(goal)
	if b.is_empty() or b["gone"] or not _is_road(_tile_of(at + d * (ROAD * 0.5 + 0.8))):
		return
	var next: Rect2 = (b["rect"] as Rect2).grow(-0.8)
	if not next.grow(0.2).has_point(goal):
		return
	pd["goal"] = goal
	pd["next"] = next
	pd["off"] = Vector2.ZERO
	_ped_mode(pd, "cross")

func _knock_ped(pd: Dictionary, c: Car, pos: Vector2) -> void:
	pd["resume"] = "walk"
	if pd["mode"] == "cross":
		# whoever was crossing ends up back on the pavement they set out for
		pd["path"] = pd["next"]
		pd["t"] = _perim_t(pd["next"], pd["goal"])
	pd["offv"] = c.vel.normalized() * minf(c.vel.length(), 14.0) * 0.9
	_ped_mode(pd, "down", 2.6)
	Audio.play("impact_punch", 0.2, -4.0)
	if c == _player:
		shake3d(2.5)
		Juice.text(self, to_screen(Vector3(pos.x, 2.0, pos.y)), ["ow!", "hey!", "oof"][_rng.randi() % 3], Palette.col("ink"))
	Probe.count("ped_knocked")

## ---- cash -----------------------------------------------------------------------------

func _spawn_coin() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.55
	cm.height = 0.14
	cm.material = mat("warn", 1.3)
	mi.mesh = cm
	mi.rotation.x = PI * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	var coin := {"node": mi, "pos": Vector2.ZERO}
	_coins.append(coin)
	_place_coin(coin)

func _place_coin(coin: Dictionary) -> void:
	for attempt in 100:
		var t := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		if not _drivable(t):
			continue
		var p := _center(t)
		if p.distance_to(_player.pos) < 25.0 or _solid_at(p, 1.0):
			continue
		coin["pos"] = p
		return

func _update_coins(dt: float) -> void:
	for coin in _coins:
		var mi: MeshInstance3D = coin["node"]
		var p: Vector2 = coin["pos"]
		mi.position = Vector3(p.x, 1.0 + 0.2 * sin(_t * 3.0 + p.x), p.y)
		mi.rotation.y += dt * 3.0
		if p.distance_to(_player.pos) < 2.2:
			add_score(25)
			Audio.play("coin", 0.1, -8.0)
			Juice.text(self, to_screen(Vector3(p.x, 2.0, p.y)), "+$25", Palette.col("warn"))
			Probe.count("cash")
			_place_coin(coin)

## ---- jobs ---------------------------------------------------------------------------

## A lane tile with pavement beside it, a decent drive from you. Returns [lane centre,
## the pavement spot next to it].
func _kerb_spot(near: float, far: float) -> Array:
	for attempt in 400:
		var t := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		var dirs := _lane_dirs(t)
		if dirs.size() != 1:
			continue
		var lane: Vector2i = dirs[0]
		var p := _center(t)
		var d := p.distance_to(_player.pos)
		if d < near or d > far:
			continue
		# the side of the lane that is not road is the pavement
		var side := Vector2i(lane.y, -lane.x)
		if _is_road(t + side) or not _in_grid(t + side):
			side = -side
		if _is_road(t + side) or not _in_grid(t + side):
			continue
		var walk := p + Vector2(side) * (TILE * 0.5 + 0.8)
		if _solid_at(walk, 0.4):
			continue
		return [p, walk, lane]
	return [_center(Vector2i(1, 9)), _center(Vector2i(1, 9)), Vector2i(0, 1)]

func _new_job() -> void:
	var kinds := JOBS.keys()
	_job = kinds[_job_n % kinds.size()] if _job_n < 3 else kinds[_rng.randi() % kinds.size()]
	_job_n += 1
	_stage = "pick"
	var spot := _kerb_spot(30.0, 85.0)
	_target = spot[0]
	if _prop != null:
		_prop.queue_free()
		_prop = null
	var walk: Vector2 = spot[1]
	var lane: Vector2i = spot[2]
	match _job:
		"case":
			_prop = Node3D.new()
			world.add_child(_prop)
			_prop.position = Vector3(walk.x, KERB, walk.y)
			var booth := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 2.3, 0.9)
			booth.mesh = bm
			booth.material_override = mat("prize", 0.8)
			booth.position = Vector3(0, 1.15, 0)
			_prop.add_child(booth)
			var top := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(1.1, 0.25, 1.1)
			top.mesh = tm
			top.material_override = mat("ink", 1.5)
			top.position = Vector3(0, 2.4, 0)
			_prop.add_child(top)
		"fare":
			var a := Actor3D.new()
			world.add_child(a)
			a.set_character(PEOPLE[_rng.randi() % PEOPLE.size()])
			a.position = Vector3(walk.x, KERB, walk.y)
			a.play("Victory", true, 0.8)
			a.face(Vector3(_target.x - walk.x, 0, _target.y - walk.y))
			_prop = a
		"steal":
			var kind: String = STEAL[_rng.randi() % STEAL.size()]
			var m := model(kind, CARS[kind]["len"])
			world.add_child(m)
			m.position = Vector3(_target.x, 0, _target.y)
			m.rotation.y = PI * 0.5 - Vector2(lane).angle()
			m.set_meta("kind", kind)
			_prop = m
	_set_marker(JOBS[_job]["role"])
	_route = _bfs(_tile_of(_target))
	_job_label.text = JOBS[_job]["pick"]
	_show_banner(JOBS[_job]["pick"], JOBS[_job]["role"])
	Probe.event("job_offered", {"kind": _job})

func _start_drop() -> void:
	_stage = "drop"
	var spot := _kerb_spot(55.0, 400.0)
	_target = spot[0]
	_job_t = 10.0 + _target.distance_to(_player.pos) / 6.0
	_set_marker("warn")
	_route = _bfs(_tile_of(_target))
	_show_banner(JOBS[_job]["drop"], "warn")

func _update_job(dt: float) -> void:
	if _stage == "drop":
		_job_t -= dt
		if _job_t <= 0.0:
			_show_banner("too slow", "hazard")
			Audio.play("voice_mission_failed")
			Probe.event("job_failed", {"kind": _job})
			_new_job()
			return
		_job_label.text = "%s   %d" % [JOBS[_job]["drop"], ceili(_job_t)]
	if _player.pos.distance_to(_target) > 3.0:
		return
	var at := Vector3(_target.x, 2.0, _target.y)
	if _stage == "pick":
		add_score(50)
		Juice.text(self, to_screen(at), "+$50", Palette.col(JOBS[_job]["role"]))
		Audio.play("pickup")
		Probe.event("job_taken", {"kind": _job})
		if _job == "steal" and _prop != null:
			var kind: String = _prop.get_meta("kind")
			_set_model(_player, kind)
			_spark(Vector3(_player.pos.x, 1.0, _player.pos.y))
			Juice.text(self, to_screen(at + Vector3(0, 1.5, 0)), kind, Palette.col("accent"))
		if _prop != null:
			_prop.queue_free()
			_prop = null
		_start_drop()
	else:
		var pay: int = int(JOBS[_job]["pay"]) + ceili(_job_t) * int(JOBS[_job]["tip"])
		add_score(pay)
		_deliveries += 1
		Juice.text(self, to_screen(at), "+$%d" % pay, Palette.col("prize"))
		shake3d(3.0)
		Audio.play("coin")
		Audio.play("voice_mission_completed")
		Probe.event("delivered", {"kind": _job, "pay": pay, "deliveries": _deliveries})
		_set_stars(_stars + 1)
		if _job == "fare":
			_drop_fare()
		_new_job()
		_show_banner("paid $%d" % pay, "prize")

## The fare gets out and walks off.
func _drop_fare() -> void:
	var a := Actor3D.new()
	world.add_child(a)
	a.set_character(PEOPLE[_rng.randi() % PEOPLE.size()])
	var p := _player.pos + Vector2.from_angle(_player.heading).orthogonal() * 1.6
	a.position = Vector3(p.x, 0.0, p.y)
	a.play("Walk", true, 1.0)
	var away := Vector3(p.x - _player.pos.x, 0, p.y - _player.pos.y).normalized()
	a.face(away)
	var tw := a.create_tween()
	tw.tween_property(a, "position", a.position + away * 5.0, 3.0)
	tw.tween_callback(a.queue_free)

## ---- the marker, the arrow, the camera ------------------------------------------------

func _build_marker() -> void:
	_marker = Node3D.new()
	world.add_child(_marker)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.2
	tm.outer_radius = 2.6
	_ring.mesh = tm
	_ring.scale = Vector3(1, 0.3, 1)
	_ring.position = Vector3(0, 0.12, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_ring)
	_pillar = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.2
	cm.height = 40.0
	cm.cap_top = false
	cm.cap_bottom = false
	_pillar.mesh = cm
	_pillar.position = Vector3(0, 20.0, 0)
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_pillar)
	_gem = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.6
	sm.radial_segments = 4
	sm.rings = 2
	_gem.mesh = sm
	_gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(_gem)
	# The bots seek "*". They have no pathfinding, so they get what the player gets: the
	# GPS point a few tiles down the road towards the job, not the job behind a building.
	_guide = Node3D.new()
	world.add_child(_guide)
	track3d(_guide, "*")
	# a flat chevron pointing along +Z, wound both ways so it shows from any angle
	_arrow = MeshInstance3D.new()
	var tip := Vector3(0, 0, 1.6)
	var lw := Vector3(-1.1, 0, -0.9)
	var rw := Vector3(1.1, 0, -0.9)
	var notch := Vector3(0, 0, -0.3)
	var verts := PackedVector3Array([tip, rw, notch, tip, notch, lw, tip, notch, rw, tip, lw, notch])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	for v in verts:
		normals.append(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_arrow.mesh = am
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_arrow)

func _set_marker(role: String) -> void:
	_ring.material_override = mat(role, 1.8)
	_gem.material_override = mat(role, 1.5)
	_arrow.material_override = mat(role, 1.4)
	_pillar.material_override = _gmat(role, 0.16, _beam)

func _update_marker() -> void:
	_marker.position = Vector3(_target.x, 0, _target.y)
	_gem.position = Vector3(0, 3.0 + 0.4 * sin(_t * 3.0), 0)
	_gem.rotation.y = _t * 2.0
	var s := 1.0 + 0.1 * sin(_t * 6.0)
	_ring.scale = Vector3(s, 0.3, s)
	if _player.pos.distance_to(_target) < 14.0 and _clear(_player.pos, _target, 0.5):
		_guide_p = _target
	else:
		_guide_p = _follow(_route, _player.pos, 6, _target)
	_guide.position = Vector3(_guide_p.x, 0, _guide_p.y)
	# the arrow follows the GPS round corners
	var to := _guide_p - _player.pos
	if _guide_p == _target:
		to = _target - _player.pos
	_arrow.visible = _player.pos.distance_to(_target) > 9.0 and to.length() > 0.5
	if _arrow.visible:
		var d := to.normalized()
		var p := _player.pos + d * (4.2 + 0.3 * sin(_t * 8.0))
		_arrow.position = Vector3(p.x, 2.6 + _player.y, p.y)
		_arrow.rotation = Vector3(0, atan2(d.x, d.y), 0)

func _update_camera(dt: float) -> void:
	var p := _player
	var spd := p.vel.length()
	var aim := Vector3(p.pos.x + p.vel.x * 0.35, 0.0, p.pos.y + p.vel.y * 0.35)
	_cam_t = _cam_t.lerp(aim, 1.0 - exp(-4.0 * dt))
	var h := lerpf(27.0, 37.0, clampf(spd / p.top, 0.0, 1.0))
	_cam_h = lerpf(_cam_h, h, 1.0 - exp(-1.2 * dt))
	look_from(_cam_t + Vector3(0, _cam_h, _cam_h * 0.22), _cam_t)
	# the slice of ground in view, for spawning things out of sight
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sp in [Vector2(0, 0), Vector2(640, 0), Vector2(0, 360), Vector2(640, 360)]:
		var g := ground_point(sp)
		if not g.is_finite():
			continue
		lo = Vector2(minf(lo.x, g.x), minf(lo.y, g.z))
		hi = Vector2(maxf(hi.x, g.x), maxf(hi.y, g.z))
	if lo.x < INF:
		_view = Rect2(lo, hi - lo)

## ---- touch: a floating thumb-stick wherever the thumb lands ------------------------

func _input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			if Flow.pointer_over_hud():
				return
			_stick_on = true
			_stick_origin = (event as InputEventMouseButton).position
			_stick_vec = Vector2.ZERO
		else:
			_stick_on = false
			_stick_vec = Vector2.ZERO
	elif event is InputEventMouseMotion and _stick_on:
		var at := (event as InputEventMouseMotion).position
		var d := at - _stick_origin
		if d.length() > 56.0:
			_stick_origin = at - d.normalized() * 56.0
			d = at - _stick_origin
		_stick_vec = Vector2.ZERO if d.length() < 8.0 else d.normalized() * minf(1.0, d.length() / 40.0)

## ---- HUD ------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5   # under the shell's own HUD and pause screen
	add_child(layer)
	_hud = Node2D.new()
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_job_label = UIKit.label("", 12, "ink")
	_job_label.position = Vector2(170, 30)
	_job_label.size = Vector2(300, 18)
	layer.add_child(_job_label)
	_banner = UIKit.label("", 28, "hazard")
	_banner.position = Vector2(40, 130)
	_banner.size = Vector2(560, 60)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.modulate.a = 0.0
	layer.add_child(_banner)

func _show_banner(msg: String, role: String) -> void:
	if _banner_tw != null and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner.text = msg
	_banner.add_theme_color_override("font_color", Palette.col(role))
	_banner.modulate.a = 1.0
	_banner.scale = Vector2.ONE * 1.5
	_banner_tw = _banner.create_tween()
	_banner_tw.tween_property(_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tw.tween_interval(0.9)
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.4)

func _draw_hud() -> void:
	var flash := int(_t * 8.0) % 2 == 0
	for i in MAX_STARS:
		var p := Vector2(320.0 + (i - 2) * 22.0, 18.0)
		var c := Palette.col("warn")
		if i < _stars:
			if _cop_near:
				c = Palette.col("hazard") if flash else Palette.col("player")
			_hud.draw_circle(p, 12.0, Color(c.r, c.g, c.b, 0.12))
			_hud.draw_colored_polygon(_star_pts(p, 8.5), c)
		else:
			var pts := _star_pts(p, 8.5)
			pts.append(pts[0])
			_hud.draw_polyline(pts, Color(c.r, c.g, c.b, 0.25), 1.2)
	# bust meter round your car
	if _bust > 0.02:
		var hz := Palette.col("hazard")
		var sp := to_screen(Vector3(_player.pos.x, 0.8, _player.pos.y))
		_hud.draw_circle(sp, 26.0, Color(hz.r, hz.g, hz.b, 0.10 + 0.15 * _bust))
		_hud.draw_arc(sp, 24.0, -PI * 0.5, -PI * 0.5 + TAU * _bust, 40, hz, 3.0)
	_draw_minimap()
	if _stick_on:
		var ink := Palette.col("ink")
		var pl := Palette.col("player")
		_hud.draw_arc(_stick_origin, 40.0, 0.0, TAU, 40, Color(ink.r, ink.g, ink.b, 0.25), 2.0)
		_hud.draw_circle(_stick_origin + _stick_vec * 40.0, 14.0, Color(pl.r, pl.g, pl.b, 0.35))

func _draw_minimap() -> void:
	var k := 0.5
	var o := Vector2(8, 360 - 8 - MAP_D * k)
	var bg := Palette.col("bg")
	var ink := Palette.col("ink")
	_hud.draw_rect(Rect2(o - Vector2(2, 2), Vector2(MAP_W, MAP_D) * k + Vector2(4, 4)), Color(bg.r, bg.g, bg.b, 0.75))
	_hud.draw_rect(Rect2(o, Vector2(MAP_W, MAP_D) * k), Color(ink.r, ink.g, ink.b, 0.10))
	for b in _blocks:
		if b["gone"]:
			continue
		var r: Rect2 = b["rect"]
		var role := "bg_alt"
		match b["kind"]:
			"park": role = "friend"
			"plaza": role = "accent"
			"parking": role = "bg"
		var c := Palette.col(role)
		var a := 0.45 if role != "bg_alt" else 0.9
		_hud.draw_rect(Rect2(o + r.position * k, r.size * k), Color(c.r, c.g, c.b, a))
	var flash := int(_t * 6.0) % 2 == 0
	for x in _cops:
		var c: Car = x
		_hud.draw_circle(o + c.pos * k, 2.0, Palette.col("hazard") if flash else Palette.col("player"))
	var tr := Palette.col("warn" if _stage == "drop" else JOBS[_job]["role"])
	var route := PackedVector2Array([o + _player.pos * k])
	for t in _descend(_route, _player.pos, 160):
		route.append(o + _center(t) * k)
	if route.size() > 1:
		_hud.draw_polyline(route, Color(tr.r, tr.g, tr.b, 0.8), 1.5)
	_hud.draw_circle(o + _target * k, 3.0 + sin(_t * 6.0), tr)
	var pp := o + _player.pos * k
	var f := Vector2.from_angle(_player.heading)
	_hud.draw_colored_polygon(PackedVector2Array([pp + f * 4.0, pp - f * 2.5 + f.orthogonal() * 2.5, pp - f * 2.5 - f.orthogonal() * 2.5]), Palette.col("player"))
	_hud.draw_rect(Rect2(o + _view.position * k, _view.size * k), Color(ink.r, ink.g, ink.b, 0.35), false, 1.0)

func _star_pts(p: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	return pts
