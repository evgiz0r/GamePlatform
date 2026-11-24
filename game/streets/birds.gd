extends RefCounted
## Pigeons and crows on the pavements round you (the user, 24 Nov 2026: "more object people
## animals"). A flock of pigeons (5-12) or a few hooded crows is put down on a pavement or a
## square out of sight (streets.gd's _spawn_ok), 20-60 m off; they walk about slowly, turn,
## and peck at the ground; when you come near -- on foot within FLEE_FOOT, in a moving car
## within FLEE_CAR, or someone walks through them -- the whole flock goes up at once, wings
## beating, away from what scared it, and is gone over the roofs; another lands somewhere
## you are not looking. By day only: at night they roost.
##
## Drawn as three MultiMeshes (standing, wings up, wings down: a flap is the two swapped
## every FLAP s), so all of them together cost three draws. A bird not in use has a zero
## transform. Nothing here is solid: the car and people go through where a bird was, and it
## is up and away by then.
const MAX_BIRDS := 72
const MAX_FLOCKS := 6
const FLEE_FOOT := 4.5
const FLEE_CAR := 14.0
const SEEN := 70.0                  ## drawn to (a pigeon is a speck past that)
const GONE := 95.0                  ## a flock further than this is taken up (out of sight) and landed again
const FLAP := 0.09

var g: Node
var rng := RandomNumberGenerator.new()
var flocks: Array = []              ## {c, birds: [{p, y, yaw, h, peck, walk, v: Vector3, crow}], up: bool, t}
var count := {"landed": 0, "flew": 0, "crows": 0}
var _mm: Array = []                 ## standing, wings up, wings down
var _free_ix: Array = []            ## bird slots not in use
var _t := 0.0
var _land_t := 0.0
var _next_id := 0

func _init(game: Node) -> void:
	g = game
	rng.seed = 24112026

## the flutter of a flock going up (sounds/flap.wav), two players so two flocks can overlap
var _flaps: Array = []

func setup() -> void:
	var f = g._furn
	for k in range(2):
		var ap := AudioStreamPlayer3D.new()
		ap.stream = load("res://game/streets/sounds/flap.wav")
		ap.unit_size = 6.0
		ap.max_distance = 60.0
		g.world.add_child(ap)
		_flaps.append(ap)
	var meshes := [_bird_mesh(f, 0), _bird_mesh(f, 1), _bird_mesh(f, 2)]
	for m: ArrayMesh in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = m
		mm.instance_count = MAX_BIRDS
		var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
		for i in range(MAX_BIRDS):
			mm.set_instance_transform(i, zero)
			mm.set_instance_color(i, Color.WHITE)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-1e5, -100, -1e5), Vector3(2e5, 400, 2e5))   # (instances anywhere: never culled as a whole)
		mi.visibility_range_end = 0.0
		g.world.add_child(mi)
		_mm.append(mm)
	for i in range(MAX_BIRDS):
		_free_ix.append(i)

## a bird facing +Z, its feet at y = 0, about 0.32 m long; drawn white (each copy's colour is
## its plumage). part 0 standing (wings folded, legs), 1 flying wings up, 2 wings down
func _bird_mesh(f, part: int) -> ArrayMesh:
	var b = g.new_buf()
	var w := Color.WHITE
	var dark := Color(0.55, 0.55, 0.58)
	var y0 := 0.06 if part == 0 else 0.0
	f._ellipsoid(b, Vector3(0, y0 + 0.08, 0), Vector3(0.075, 0.068, 0.14), w, Basis(Vector3.RIGHT, -0.25 if part == 0 else 0.0))
	f._ellipsoid(b, Vector3(0, y0 + 0.17 if part == 0 else y0 + 0.11, 0.12 if part == 0 else 0.15), Vector3(0.042, 0.042, 0.046), w)
	f._box(b, Vector3(0, y0 + (0.165 if part == 0 else 0.105), 0.17 if part == 0 else 0.2), Vector3(0.016, 0.014, 0.04), Color(0.3, 0.28, 0.26))   # the beak
	f._box(b, Vector3(0, y0 + 0.09, -0.17), Vector3(0.07, 0.016, 0.1), dark, Basis(Vector3.RIGHT, -0.2 if part == 0 else 0.0))   # the tail
	if part == 0:
		for x: float in [-0.025, 0.025]:
			f._box(b, Vector3(x, 0.035, 0.01), Vector3(0.012, 0.07, 0.012), Color(0.7, 0.35, 0.35))
		for x: float in [-0.07, 0.07]:   # the folded wings, a shade darker along the sides
			f._box(b, Vector3(x, y0 + 0.09, -0.03), Vector3(0.02, 0.06, 0.18), dark, Basis(Vector3.RIGHT, -0.25))
	else:
		var lift := 0.55 if part == 1 else -0.35
		for sg: float in [-1.0, 1.0]:
			var bs := Basis(Vector3.BACK, sg * lift)
			f._box(b, Vector3(sg * 0.2 * cos(lift), y0 + 0.09 + 0.2 * sin(lift), 0.0), Vector3(0.3, 0.015, 0.13), dark, bs)
	return f._mesh(b)

func tick(dt: float) -> void:
	if _mm.is_empty():
		return
	_t += dt
	var night: bool = g._night
	var me: Vector2 = g._pos
	var car_moving: bool = not g._walking and absf(g._v) > 2.0
	# land a new flock now and then, out of sight, while there are fewer than enough
	_land_t -= dt
	if not night and _land_t <= 0.0 and flocks.size() < MAX_FLOCKS and _free_ix.size() >= 5:
		_land_t = 0.6
		_land(me)
	var flap := int(_t / FLAP) % 2
	for fi in range(flocks.size() - 1, -1, -1):
		var fl: Dictionary = flocks[fi]
		var c: Vector2 = fl["c"]
		var d := c.distance_to(me)
		if not fl["up"]:
			var scare := Vector2.INF
			if d < FLEE_FOOT + 2.5 or (car_moving and d < FLEE_CAR + 2.5) or night:
				scare = me
			else:
				for q: Vector2 in g._people_at:
					if q.distance_to(c) < 1.8:
						scare = q
						break
			if scare.is_finite():
				_fly(fl, scare)
			elif d > GONE and g._unseen(c):
				_retire(fi)
				continue
		var all_gone := true
		for bd: Dictionary in fl["birds"]:
			var i: int = bd["i"]
			if fl["up"]:
				fl["t"] = float(fl["t"]) + dt / float((fl["birds"] as Array).size())
				var v: Vector3 = bd["v"]
				v.y = minf(v.y + 2.0 * dt, 6.0)
				bd["v"] = v
				var p3: Vector3 = bd["p3"] + v * dt
				bd["p3"] = p3
				if p3.y - float(bd["h"]) < 30.0:
					all_gone = false
				var yaw := atan2(v.x, v.z)
				var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.35).scaled(Vector3.ONE * float(bd["s"])), p3)
				_show(i, 1 + (flap + (i % 2)) % 2, xf)
			else:
				all_gone = false
				_ground(bd, dt)
				var p: Vector2 = bd["p"]
				var pitch := 0.55 if float(bd["peck"]) > 0.0 else 0.0
				var xf := Transform3D(Basis(Vector3.UP, float(bd["yaw"])) * Basis(Vector3.RIGHT, pitch).scaled(Vector3.ONE * float(bd["s"])),
					Vector3(p.x, float(bd["h"]) + float(bd["hop"]), p.y))
				_show(i, 0, xf)
		if fl["up"] and (all_gone or float(fl["t"]) > 9.0):
			_retire(fi)

## a bird on the ground: a few steps, a stop, a peck, a turn; now and then a hop
func _ground(bd: Dictionary, dt: float) -> void:
	bd["peck"] = maxf(float(bd["peck"]) - dt, 0.0)
	bd["hop"] = maxf(float(bd["hop"]) - dt * 0.6, 0.0)
	bd["next"] = float(bd["next"]) - dt
	if float(bd["next"]) <= 0.0:
		var r := rng.randf()
		if r < 0.45:
			bd["peck"] = 0.25
			bd["next"] = rng.randf_range(0.4, 1.2)
		elif r < 0.75:
			bd["walk"] = rng.randf_range(0.6, 1.8)
			bd["yaw"] = float(bd["yaw"]) + rng.randf_range(-1.2, 1.2)
			bd["next"] = float(bd["walk"]) + rng.randf_range(0.2, 0.8)
		elif r < 0.85:
			bd["hop"] = 0.06
			bd["next"] = rng.randf_range(0.5, 1.5)
		else:
			bd["yaw"] = float(bd["yaw"]) + rng.randf_range(-2.5, 2.5)
			bd["next"] = rng.randf_range(0.6, 2.0)
	if float(bd["walk"]) > 0.0:
		bd["walk"] = float(bd["walk"]) - dt
		var yaw: float = bd["yaw"]
		var step := Vector2(sin(yaw), cos(yaw)) * 0.3 * dt
		var p: Vector2 = bd["p"]
		var np := p + step
		# stays on its own ground: off the asphalt, out of walls, near the flock
		if g._off_road(np, 0.1) and g._push_out(np, 0.1, false, false) == Vector2.ZERO and np.distance_to(bd["home"]) < 3.5:
			bd["p"] = np
		else:
			bd["yaw"] = yaw + PI * 0.8
			bd["walk"] = 0.0

func _fly(fl: Dictionary, from: Vector2) -> void:
	fl["up"] = true
	fl["t"] = 0.0
	count["flew"] = int(count["flew"]) + 1
	if not Audio.muted() and not _flaps.is_empty():
		var ap: AudioStreamPlayer3D = _flaps[0] if not (_flaps[0] as AudioStreamPlayer3D).playing else _flaps[1]
		var c: Vector2 = fl["c"]
		ap.position = Vector3(c.x, float(g._h(c)) + 0.5, c.y)
		ap.pitch_scale = rng.randf_range(0.9, 1.15)
		ap.volume_db = linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8)))) - 6.0
		ap.play()
	for bd: Dictionary in fl["birds"]:
		var p: Vector2 = bd["p"]
		var away := (p - from).normalized() if p.distance_to(from) > 0.05 else Vector2.RIGHT.rotated(rng.randf() * TAU)
		away = away.rotated(rng.randf_range(-0.6, 0.6))
		var sp := rng.randf_range(3.5, 5.5)
		bd["v"] = Vector3(away.x * sp, rng.randf_range(1.8, 3.2), away.y * sp)
		bd["p3"] = Vector3(p.x, float(bd["h"]) + 0.08, p.y)

func _retire(fi: int) -> void:
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for bd: Dictionary in flocks[fi]["birds"]:
		var i: int = bd["i"]
		for k in range(3):
			_mm[k].set_instance_transform(i, zero)
		_free_ix.append(i)
	flocks.remove_at(fi)

## show bird slot i as mesh `k` (the other two hidden)
func _show(i: int, k: int, xf: Transform3D) -> void:
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for m in range(3):
		_mm[m].set_instance_transform(i, xf if m == k else zero)

## a flock put down 20-60 m off, on a pavement or a square, where you cannot see it land
func _land(me: Vector2) -> void:
	for _try in range(4):
		var c := me + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(20.0, 60.0)
		var hit: Dictionary = g._nearest_seg(c, 30.0, true, true)
		if not hit.is_empty():
			var r: Dictionary = g._roads[hit["road"]]
			if r["k"] in ["motorway", "trunk", "motorway_link", "trunk_link"]:
				continue
			var q: Vector2 = hit["q"]
			var out := (c - q).normalized() if c.distance_to(q) > 0.1 else Vector2.RIGHT
			c = q + out * (float(r["w"]) * 0.5 + g.KERB_W + g.PAVE_W * 0.55)
		if not g._off_road(c, 0.4) or g._push_out(c, 0.6, false, false) != Vector2.ZERO or not g._spawn_ok(c):
			continue
		var crow := rng.randf() < 0.25
		var n := rng.randi_range(1, 3) if crow else rng.randi_range(5, 12)
		var birds: Array = []
		for k in range(n):
			if _free_ix.is_empty():
				break
			var p := c + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(0.0, 2.2 if not crow else 3.0)
			if not g._off_road(p, 0.1) or g._push_out(p, 0.1, false, false) != Vector2.ZERO:
				continue
			var i: int = _free_ix.pop_back()
			var col: Color
			if crow:   # a hooded crow: grey with a black head and wings (the mesh's darker parts)
				col = g._tone["metal"].lerp(g._tone["tyre"], 0.35)
			else:      # a pigeon's blue-grey, one in five browner or paler
				var base: Color = g._tone["rim"].lerp(g._tone["signblue"], 0.12)
				var v := rng.randf()
				col = base.lerp(g._tone["woodfence"], 0.4) if v < 0.12 else (base.lerp(g._tone["mark"], 0.45) if v < 0.22 else base)
			for m in range(3):
				_mm[m].set_instance_color(i, col)
			birds.append({"i": i, "p": p, "home": c, "h": g._walk_y(p), "yaw": rng.randf() * TAU, "peck": 0.0, "walk": 0.0,
				"hop": 0.0, "next": rng.randf_range(0.0, 1.5), "s": (1.35 if crow else 1.0) * rng.randf_range(0.92, 1.08), "v": Vector3.ZERO, "p3": Vector3.ZERO})
		if birds.is_empty():
			return
		_next_id += 1
		flocks.append({"id": _next_id, "c": c, "birds": birds, "up": false, "t": 0.0, "crow": crow})
		count["landed"] = int(count["landed"]) + 1
		if crow:
			count["crows"] = int(count["crows"]) + 1
		return

## every bird in use (for tests): [where, up]
func everyone() -> Array:
	var out: Array = []
	for fl: Dictionary in flocks:
		for bd: Dictionary in fl["birds"]:
			out.append([bd["p3"] if fl["up"] else Vector3(bd["p"].x, bd["h"], bd["p"].y), fl["up"], fl["c"]])
	return out
