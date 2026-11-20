extends GameMode3D
## firefight -- a first-person shooter where you only shoot. You walk down a bending night
## street without ever stopping. Goblins come at you from everywhere: they sprint out of
## alleys and cross streets to dive behind cars and crates, pop up over them to shoot, run
## at you down the road, appear on rooftops, and pile out of a van that screeches to a halt
## in front of you. A ring fills around each one while it aims; if it closes, you are hit.
## Tap to shoot where you tap. See GAME.md.
##
## The street is a curve, like drive_by's: everything has road coordinates (u = distance
## along the road, lat = sideways, + is right of the walking line, y = height) and
## _frame(u) turns them into world space. The camera walks along u. The street is built
## ahead and freed behind; fog and the bends hide where it ends. Hits are tested in screen
## space against each exposed goblin's on-screen box, nearest first.

const EYE := 1.6
const FACADE := 12.0                 ## |lat| of the building fronts
const ROAD := 7.0                    ## |lat| of the kerbs
const AHEAD := 75.0                  ## street is built this far ahead (fog hides the end)
const BEHIND := 10.0
const WALK_MIN := 2.6                ## walking pace at the start ...
const WALK_MAX := 4.2                ## ... and after RAMP seconds
const RAMP := 150.0
const GOBLIN_H := 1.8
const PERSON_H := 1.8
const RUN_SPEED := 6.5
const MAG := 6
const RELOAD_TIME := 1.0
const SHOT_GAP := 0.14
const TAP_SLOP := 6.0
const CROSS_ASSIST := 40.0
const CROSS_SPEED := 320.0
const HEADSHOT := 0.22
const START_LIVES := 5
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const SHOPS := ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h"]
const TOWERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c"]
const CARS := ["sedan", "taxi", "suv", "police"]
const GOBLINS := ["Goblin_Male", "Goblin_Female"]
const PEOPLE := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Female"]
const GUN_REST := Vector2(560, 312)
const GUN_BOX := Rect2(488, 262, 152, 98)   ## tap here to reload

var _dist := 0.0                     ## how far you have walked (the camera's u)
var _speed := 0.0
var _road_u := -BEHIND
var _strip := {-1.0: -BEHIND, 1.0: -BEHIND}   ## building strip built up to here, per side
var _next_cross := 70.0              ## the next cross street starts here
var _street: Array = []              ## static Node3D, meta u, w (freed once behind)
var _buildings: Array = []           ## {u, w, h, side}
var _openings: Array = []            ## alleys and cross streets: {u, side, lat} -- where goblins come from
var _cover: Array = []               ## {u, lat, top, depth, taken}
var _foes: Array = []                ## goblins: Dictionaries, see _new_goblin
var _people: Array = []              ## civilians crossing: {node, u, lat, dir, mark}
var _van: Dictionary = {}            ## the ambush van while it is driving
var _van_cd := 30.0
var _spawn_t := 2.5
var _look := Vector3.ZERO
var _t := 0.0
var _intro := 1.6
var _ammo := MAG
var _reload := 0.0
var _shot_cd := 0.0
var _cross: Node2D                   ## the crosshair (and the bots' "@")
var _ov: Node2D                      ## overlay: rings, tracers, ammo, edge arrows
var _gun: Node2D
var _red: ColorRect
var _ground: MeshInstance3D
var _tracers: Array = []
var _sparks: Array = []
var _flash_t := 0.0
var _kick := 0.0
var _streak := 0
var _kills := 0
var _sfx_was := 0.8

func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(0, -FACADE, 60, FACADE * 2.0)

func _ready() -> void:
	title = "firefight"
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	set_lives(START_LIVES)
	cam.fov = 64.0
	cam.far = 90.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.rotation_degrees = Vector3(-48, 30, 0)
	# fog the colour of the horizon: the far street fades out instead of popping in
	env.fog_enabled = true
	env.fog_light_color = Palette.col("bg_alt").lerp(Palette.col("accent"), 0.18)
	env.fog_density = 0.022
	env.fog_sky_affect = 0.0
	_ground = MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(220, 220)
	gm.material = mat("bg", 0.0, 1.0)
	_ground.mesh = gm
	world.add_child(_ground)
	_extend()
	_build_overlay()
	_aim_camera(0.0, true)
	Audio.play("voice_ready")
	Probe.event("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the road as a curve --------------------------------------------------------------

func _wander(u: float) -> float:
	return 8.0 * sin(u / 38.0) + 4.0 * sin(u / 19.0 + 1.3)

func _wander_slope(u: float) -> float:
	return 8.0 / 38.0 * cos(u / 38.0) + 4.0 / 19.0 * cos(u / 19.0 + 1.3)

## World transform of the road at u: +X forward along the road, +Z = +lat (right).
func _frame(u: float) -> Transform3D:
	var fwd := Vector3(1.0, 0.0, _wander_slope(u)).normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	return Transform3D(Basis(fwd, Vector3.UP, side), Vector3(u, 0.0, _wander(u)))

func _road_pos(u: float, lat: float, y: float = 0.0) -> Vector3:
	return _frame(u) * Vector3(0.0, y, lat)

## ---- the street ------------------------------------------------------------------

func _extend() -> void:
	while _next_cross < _dist + AHEAD + 10.0:
		_add_cross(_next_cross)
		_next_cross += randf_range(60.0, 110.0)
	while _road_u < _dist + AHEAD:
		_road_segment(_road_u)
		_road_u += 4.0
	for side: float in [-1.0, 1.0]:
		while _strip[side] < _dist + AHEAD:
			_strip[side] = _strip[side] + _add_lot(_strip[side], side)
	for n: Node3D in _street.duplicate():
		if n.get_meta("u") + n.get_meta("w") * 0.5 < _dist - BEHIND:
			_street.erase(n)
			n.queue_free()
	for list: Array in [_buildings, _openings, _cover]:
		for e: Dictionary in list.duplicate():
			if e["u"] + e.get("w", 0.0) < _dist - BEHIND:
				list.erase(e)
	_ground.position = _road_pos(_dist, 0.0, -0.05)

func _place(n: Node3D, u: float, lat: float, w: float, y: float = 0.0, flip: bool = false) -> void:
	n.transform = _frame(u)
	n.position = _road_pos(u, lat, y)
	if flip:
		n.rotate_object_local(Vector3.UP, PI)
	n.set_meta("u", u)
	n.set_meta("w", w)
	world.add_child(n)
	_street.append(n)

func _box(size: Vector3, role: String, emission: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat(role, emission, 1.0)
	m.mesh = bm
	return m

func _road_segment(u: float) -> void:
	var mid := u + 2.0
	var crossing := _cross_at(mid) or _cross_at(mid - 2.0) or _cross_at(mid + 2.0)
	for side: float in [-1.0, 1.0]:
		if not crossing:
			_place(_box(Vector3(4.15, 0.08, FACADE - ROAD), "bg_alt", 0.15), mid, side * (ROAD + FACADE) * 0.5, 4.0, 0.04)
			_place(_box(Vector3(4.15, 0.14, 0.16), "accent", 0.8), mid, side * ROAD, 4.0, 0.07)
	_place(_box(Vector3(1.8, 0.02, 0.14), "ink", 0.4), mid, 0.0, 4.0, 0.01)
	# little things that make it a street, and that goblins hide behind
	if not crossing and u > 12.0 and randf() < 0.42:
		var side := -1.0 if randf() < 0.5 else 1.0
		if randf() < 0.55:
			var car := model(CARS[randi() % CARS.size()], 4.0)
			var lat := side * (ROAD - 1.4)
			_place(car, mid, lat, 4.0)
			car.rotate_object_local(Vector3.UP, PI * 0.5 * side)
			_cover.append({"u": mid, "lat": lat, "top": 2.0, "depth": 2.6, "taken": false})
		else:
			var lat := side * randf_range(2.6, ROAD - 1.0)
			_place(_crate(), mid, lat, 1.6)
			_cover.append({"u": mid, "lat": lat, "top": 0.85, "depth": 1.0, "taken": false})

func _crate() -> Node3D:
	var crate := Node3D.new()
	var body := _box(Vector3(1.0, 0.85, 1.6), "bg_alt", 0.2)
	body.position.y = 0.425
	crate.add_child(body)
	var rim := _box(Vector3(1.04, 0.08, 1.64), "accent", 0.9)
	rim.position.y = 0.85
	crate.add_child(rim)
	return crate

## Cross streets are 10 units wide, every 60-110 units; both sides open there, and
## goblins come running out of them.
var _crosses: Array = []             ## [u0, u1] pairs
func _cross_at(u: float) -> bool:
	for c: Array in _crosses:
		if u >= c[0] and u <= c[1]:
			return true
	return false

func _add_cross(u: float) -> void:
	_crosses.append([u, u + 10.0])
	var seg := _box(Vector3(10.0, 0.02, 46.0), "bg", 0.0)
	_place(seg, u + 5.0, 0.0, 10.0, -0.02)
	for s: float in [-1.0, 1.0]:
		_openings.append({"u": u + 5.0, "side": s, "lat": s * 20.0})
		_place(model("light-square", 4.4), u - 0.4, s * (ROAD + 0.5), 0.5, 0.0, s > 0.0)

## One lot on one side starting at u: a building (with an alley after it now and then),
## or the gap of a cross street. Returns how much street it used.
func _add_lot(u: float, side: float) -> float:
	for c: Array in _crosses:
		if u >= c[0] - 0.01 and u < c[1]:
			return c[1] - u + 0.01
	var tower := randf() < 0.22
	var name: String = TOWERS[randi() % TOWERS.size()] if tower else SHOPS[randi() % SHOPS.size()]
	var b := model(name, randf_range(10.0, 13.0) if tower else randf_range(5.5, 8.0))
	var box: AABB = b.get_meta("aabb")
	for c: Array in _crosses:
		if c[0] > u and c[0] < u + box.size.x + 0.3:
			b.free()
			return c[0] - u

	var bu := u + box.size.x * 0.5
	_place(b, bu, side * (FACADE + box.size.z * 0.5), box.size.x, 0.0, side > 0.0)
	_buildings.append({"u": u, "w": box.size.x, "h": box.size.y, "side": side})
	var used := box.size.x + 0.3
	if randf() < 0.3:
		_openings.append({"u": u + box.size.x + 1.2, "side": side, "lat": side * (FACADE + 1.5)})
		used += 2.4
	elif randf() < 0.35:
		_place(model("light-square", 4.4), u + used - 0.2, side * (ROAD + 0.5), 0.5, 0.0, side > 0.0)
	return used

## ---- goblins ---------------------------------------------------------------------------

## A goblin record. Everything is in road coordinates; _move_goblin() keeps the node there.
func _new_goblin(u: float, lat: float, y: float = 0.0) -> Dictionary:
	var g := Actor3D.new()
	world.add_child(g)
	g.set_character(GOBLINS[randi() % GOBLINS.size()], GOBLIN_H)
	# a small glowing marker over the head: goblins are dark and the street is foggy
	var tag := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.0
	cm.height = 0.26
	cm.radial_segments = 4
	cm.material = mat("hazard", 1.4)
	tag.mesh = cm
	tag.position.y = GOBLIN_H + 0.35
	g.add_child(tag)
	var m := Node2D.new()
	m.position = Vector2(-2000, -2000)
	add_child(m)
	Probe.track(m, "*")
	var f := {"node": g, "mark": m, "u": u, "lat": lat, "y": y, "state": "run", "t": 0.0,
		"to_u": u, "to_lat": lat, "cover": {}, "top": -1.0, "hide_y": 0.0, "stand_y": y,
		"aim": _aim_time(), "alive": true, "rush": false}
	_foes.append(f)
	_move_goblin(f)
	Probe.event("goblin")
	return f

func _aim_time() -> float:
	return lerpf(1.9, 0.95, clampf(_t / 120.0, 0.0, 1.0)) * randf_range(0.9, 1.15)

func _move_goblin(f: Dictionary) -> void:
	var g: Actor3D = f["node"]
	g.position = _road_pos(f["u"], f["lat"], f["y"])

func _face_player(f: Dictionary) -> void:
	var g: Actor3D = f["node"]
	var d := cam.global_position - g.global_position
	d.y = 0.0
	if d.length() > 0.01:
		g.face(d.normalized())

## Send a goblin running to (u, lat); with cover, it crouches behind it on arrival.
func _run_to(f: Dictionary, u: float, lat: float, cover: Dictionary = {}) -> void:
	if not (f["cover"] as Dictionary).is_empty():
		f["cover"]["taken"] = false
	f["cover"] = cover
	if not cover.is_empty():
		cover["taken"] = true
		u = cover["u"] + cover["depth"]
		lat = cover["lat"]
	f["to_u"] = u
	f["to_lat"] = lat
	f["state"] = "run"
	f["top"] = -1.0
	var g: Actor3D = f["node"]
	g.play("Run", true, 1.3)
	var d := _road_pos(u, lat) - _road_pos(f["u"], f["lat"])
	if d.length() > 0.01:
		g.face(d.normalized())

## Free cover between lo and hi units ahead of you, nearest to `lat` first, or {}.
func _find_cover(lo: float, hi: float, lat: float) -> Dictionary:
	var best := {}
	var best_d := INF
	for c: Dictionary in _cover:
		if c["taken"]:
			continue
		var ahead: float = c["u"] - _dist
		if ahead < lo or ahead > hi:
			continue
		var d: float = absf(c["lat"] - lat) + absf(ahead - (lo + hi) * 0.5) * 0.3
		if d < best_d:
			best_d = d
			best = c
	return best

func _opening(lo: float, hi: float) -> Dictionary:
	var pool: Array = []
	for o: Dictionary in _openings:
		var ahead: float = o["u"] - _dist
		if ahead >= lo and ahead <= hi:
			pool.append(o)
	return {} if pool.is_empty() else pool[randi() % pool.size()]

## ---- the director: who comes next, and from where ----------------------------------------

func _spawn_something() -> void:
	var cap := mini(2 + int(_t / 18.0), 7)
	if _alive() >= cap:
		return
	var r := randf()
	if r < 0.1 and _t > 20.0 and _van.is_empty() and _van_cd <= 0.0:
		_spawn_van()
	elif r < 0.2 and _t > 12.0:
		_spawn_rusher()
	elif r < 0.33:
		_spawn_roof()
	elif r < 0.42 and _people.size() < 1:
		_spawn_civilian()
	else:
		_spawn_runner()

## Out of an alley or a cross street (or a doorway), sprinting to the nearest cover.
func _spawn_runner() -> void:
	var o := _opening(16.0, 34.0)
	var u: float = _dist + randf_range(20.0, 30.0)
	var lat: float = (FACADE - 0.6) * (-1.0 if randf() < 0.5 else 1.0)
	if not o.is_empty():
		u = o["u"]
		lat = o["lat"]
	var f := _new_goblin(u, lat)
	var c := _find_cover(9.0, 24.0, -lat * 0.4)
	if c.is_empty():
		_run_to(f, u - randf_range(1.0, 5.0), randf_range(-5.5, 5.5))
	else:
		_run_to(f, 0.0, 0.0, c)
	Probe.event("runner")

## Straight down the road at you, firing once it is close.
func _spawn_rusher() -> void:
	var f := _new_goblin(_dist + randf_range(28.0, 34.0), randf_range(-4.0, 4.0))
	f["rush"] = true
	_run_to(f, _dist + 8.0, f["lat"] * 0.5)
	Probe.event("rusher")

## On the front edge of a roof ahead, rising up to shoot down at you.
func _spawn_roof() -> void:
	var pool: Array = []
	for b: Dictionary in _buildings:
		var ahead: float = b["u"] + b["w"] * 0.5 - _dist
		if ahead > 14.0 and ahead < 30.0 and b["h"] < 9.0:
			pool.append(b)
	if pool.is_empty():
		_spawn_runner()
		return
	var b: Dictionary = pool[randi() % pool.size()]
	var h: float = b["h"]
	var f := _new_goblin(b["u"] + randf_range(1.0, b["w"] - 1.0), b["side"] * (FACADE + 0.7), h - GOBLIN_H - 0.2)
	f["stand_y"] = h
	f["hide_y"] = h - GOBLIN_H - 0.2
	f["top"] = h
	f["state"] = "duck"
	f["t"] = randf_range(0.2, 0.6)
	f["cover"] = {"roof": true, "taken": true, "top": h}
	_face_player(f)
	(f["node"] as Actor3D).play("Idle", true)
	Probe.event("roof")

## A van comes down the other lane, screeches sideways ahead of you and goblins pile out.
func _spawn_van() -> void:
	var van := model("van", 4.6)
	world.add_child(van)
	_van = {"node": van, "u": _dist + 60.0, "lat": 3.5, "turn": 0.0, "stopping": false}
	_van_cd = randf_range(22.0, 32.0)
	_place_van()
	Probe.event("van")

func _place_van() -> void:
	var van: Node3D = _van["node"]
	van.transform = _frame(_van["u"])
	van.position = _road_pos(_van["u"], _van["lat"])
	van.rotate_object_local(Vector3.UP, -PI * 0.5 + _van["turn"])

func _drive_van(delta: float) -> void:
	if _van.is_empty():
		return
	var ahead: float = _van["u"] - _dist
	if ahead > 19.0:
		_van["u"] = _van["u"] - 11.0 * delta
	else:
		if not _van["stopping"]:
			_van["stopping"] = true
			Audio.play("impact_metal", 0.1)
			shake3d(1.5)
		_van["turn"] = minf(PI * 0.5, _van["turn"] + delta * 3.5)
		_van["lat"] = lerpf(_van["lat"], 1.2, delta * 3.0)
		if _van["turn"] >= PI * 0.5:
			var u: float = _van["u"]
			var c := {"u": u, "lat": _van["lat"], "top": 2.2, "depth": 1.6, "taken": false}
			_cover.append(c)
			var van: Node3D = _van["node"]
			van.set_meta("u", u)
			van.set_meta("w", 5.0)
			_street.append(van)
			var n := 2 + (1 if _t > 60.0 else 0)
			for i in n:
				var f := _new_goblin(u + 1.4, _van["lat"] + randf_range(-1.0, 1.0))
				if i == 0:
					_run_to(f, 0.0, 0.0, c)
				else:
					var cc := _find_cover(8.0, 22.0, (-1.0 if i % 2 == 0 else 1.0) * 5.0)
					if cc.is_empty():
						_run_to(f, u - randf_range(1.0, 4.0), (-1.0 if i % 2 == 0 else 1.0) * randf_range(3.0, 6.0))
					else:
						_run_to(f, 0.0, 0.0, cc)
			_van = {}
			Probe.event("van_stop")
			return
	_place_van()

func _spawn_civilian() -> void:
	var p := Actor3D.new()
	world.add_child(p)
	p.set_character(PEOPLE[randi() % PEOPLE.size()], PERSON_H)
	var dir := -1.0 if randf() < 0.5 else 1.0
	var rec := {"node": p, "u": _dist + randf_range(14.0, 22.0), "lat": -dir * (FACADE - 1.0), "dir": dir}
	var m := Node2D.new()
	add_child(m)
	Probe.track(m, "x")
	rec["mark"] = m
	p.play("Run", true, 1.2)
	_people.append(rec)
	Probe.event("civilian")

func _alive() -> int:
	return _foes.size()

## ---- goblins, per frame --------------------------------------------------------------

func _run_goblins(delta: float) -> void:
	for f: Dictionary in _foes.duplicate():
		var g: Actor3D = f["node"]
		f["t"] = f["t"] - delta
		var ahead: float = f["u"] - _dist
		if ahead < 2.5:
			_drop(f)            # slipped past you
			continue
		match f["state"]:
			"run":
				if f["rush"]:
					f["to_u"] = maxf(f["to_u"], _dist + 8.0)
				var here := Vector2(f["u"], f["lat"])
				var to := Vector2(f["to_u"], f["to_lat"])
				var step := RUN_SPEED * delta
				if here.distance_to(to) <= step:
					f["u"] = to.x
					f["lat"] = to.y
					if not (f["cover"] as Dictionary).is_empty():
						f["top"] = f["cover"]["top"]
						f["hide_y"] = minf(0.0, f["top"] - GOBLIN_H - 0.15)
						f["state"] = "duck"
						f["t"] = randf_range(0.3, 1.0)
						g.play("Idle", true)
					else:
						_start_aim(f)
				else:
					here += (to - here).normalized() * step
					f["u"] = here.x
					f["lat"] = here.y
			"duck":
				f["y"] = lerpf(f["y"], f["hide_y"], clampf(delta * 10.0, 0.0, 1.0))
				if f["t"] <= 0.0:
					f["state"] = "rise"
					f["t"] = 0.25
			"rise":
				f["y"] = lerpf(f["y"], f["stand_y"], clampf(delta * 14.0, 0.0, 1.0))
				if f["t"] <= 0.0:
					f["y"] = f["stand_y"]
					_start_aim(f)
			"aim":
				_face_player(f)
				if f["rush"]:
					# a rusher keeps walking at you while it aims
					f["u"] = maxf(_dist + 6.0, f["u"] - 1.2 * delta)
				if f["t"] <= 0.0:
					_goblin_fires(f)
			"fire":
				if f["t"] <= 0.0:
					_after_fire(f)
		_move_goblin(f)
		var m: Node2D = f["mark"]
		m.position = to_screen(_road_pos(f["u"], f["lat"], f["stand_y"] + GOBLIN_H * 0.78))

func _start_aim(f: Dictionary) -> void:
	f["state"] = "aim"
	f["aim"] = _aim_time() * (0.8 if f["rush"] else 1.0)
	f["t"] = f["aim"]
	(f["node"] as Actor3D).play("Idle", true)
	_face_player(f)
	Probe.event("aim")

func _goblin_fires(f: Dictionary) -> void:
	var g: Actor3D = f["node"]
	f["state"] = "fire"
	f["t"] = 0.45
	g.play("Shoot_OneHanded", false, 1.6)
	_tracers.append({"from": to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.62, 0)),
		"to": Vector2(320 + randf_range(-60, 60), 300), "t": 0.12, "role": "hazard"})
	_red.color = Palette.col("hazard")
	_red.color.a = 0.38
	_streak = 0
	Audio.play("hurt")
	hit3d(5.0)
	Juice.text(self, Vector2(320, 210), "hit!", Palette.col("hazard"))
	Probe.event("player_hit")
	lose_life()

## After a shot: duck back down, or break for other cover further on, or (in the open)
## sidestep and go again.
func _after_fire(f: Dictionary) -> void:
	var cover: Dictionary = f["cover"]
	if cover.has("roof"):
		f["state"] = "duck"
		f["t"] = randf_range(0.8, 1.6)
	elif not cover.is_empty() and randf() < 0.6:
		f["state"] = "duck"
		f["t"] = randf_range(0.7, 1.6)
	else:
		var c := _find_cover(8.0, 22.0, -f["lat"])
		if not c.is_empty() and not f["rush"]:
			_run_to(f, 0.0, 0.0, c)
		else:
			_run_to(f, maxf(_dist + 8.0, f["u"] + randf_range(-2.0, 2.0)), clampf(f["lat"] + randf_range(-3.5, 3.5), -6.0, 6.0))
		f["rush"] = false

func _drop(f: Dictionary) -> void:
	_foes.erase(f)
	if not (f["cover"] as Dictionary).is_empty():
		f["cover"]["taken"] = false
	(f["mark"] as Node2D).queue_free()
	(f["node"] as Node3D).queue_free()

func _exposed(f: Dictionary) -> bool:
	return f["y"] > f["hide_y"] + 0.55 or (f["cover"] as Dictionary).is_empty() or f["state"] == "run"

func _walk_people(delta: float) -> void:
	for p: Dictionary in _people.duplicate():
		p["lat"] = p["lat"] + p["dir"] * 4.2 * delta
		var n: Actor3D = p["node"]
		n.transform = _frame(p["u"])
		n.position = _road_pos(p["u"], p["lat"])
		n.face(_frame(p["u"]).basis.z * p["dir"])
		(p["mark"] as Node2D).position = to_screen(n.global_position + Vector3(0, PERSON_H * 0.6, 0))
		if absf(p["lat"]) > FACADE or p["u"] < _dist + 2.0:
			_people.erase(p)
			(p["mark"] as Node2D).queue_free()
			n.queue_free()

## ---- shooting -----------------------------------------------------------------------

## The nearest body whose on-screen box contains p, above its cover: [record, is_person, headshot].
func _hit_test(p: Vector2, slop: float) -> Array:
	var best := {}
	var best_d := INF
	var head := false
	var person := false
	var bodies: Array = []
	for f: Dictionary in _foes:
		if _exposed(f):
			bodies.append([f, false, GOBLIN_H, f["top"] if f["state"] != "run" else -1.0])
	for q: Dictionary in _people:
		bodies.append([q, true, PERSON_H, -1.0])
	for b: Array in bodies:
		var g: Node3D = b[0]["node"]
		if cam.is_position_behind(g.global_position):
			continue
		var h: float = b[2]
		var feet := to_screen(g.global_position)
		var top := to_screen(g.global_position + Vector3(0, h, 0))
		var hpx := feet.y - top.y
		if hpx <= 1.0:
			continue
		var low := feet.y
		var cover_top: float = b[3]
		if cover_top > g.global_position.y:
			low = minf(low, to_screen(Vector3(g.global_position.x, cover_top, g.global_position.z)).y)
		var half := hpx * 0.2 + slop
		if absf(p.x - top.x) > half or p.y < top.y - slop or p.y > low + slop * 0.5:
			continue
		var d := cam.global_position.distance_to(g.global_position)
		if d < best_d:
			best_d = d
			best = b[0]
			person = b[1]
			head = p.y < top.y + hpx * HEADSHOT
	return [best, person, head]

func _shoot(at: Vector2) -> void:
	if finished or _intro > 0.0 or _shot_cd > 0.0 or _reload > 0.0:
		return
	if _ammo <= 0:
		_start_reload()
		return
	_shot_cd = SHOT_GAP
	_ammo -= 1
	_cross.position = at
	_kick = 1.0
	_flash_t = 0.06
	_tracers.append({"from": _muzzle(), "to": at, "t": 0.06, "role": "warn"})
	Audio.play("impact_punch", 0.12)
	shake3d(1.2)
	Probe.event("shot")
	var r := _hit_test(at, TAP_SLOP)
	var who: Dictionary = r[0]
	if who.is_empty():
		_sparks.append({"at": at, "t": 0.18, "role": "ink"})
		_streak = 0
		Probe.event("miss")
	elif r[1]:
		_shot_civilian(who)
	else:
		_kill(who, r[2])
	if _ammo <= 0:
		_start_reload()

func _start_reload() -> void:
	if _reload > 0.0 or _ammo >= MAG:
		return
	_reload = RELOAD_TIME
	Audio.play("click")
	Probe.event("reload")

func _kill(f: Dictionary, head: bool) -> void:
	var g: Actor3D = f["node"]
	_foes.erase(f)
	if not (f["cover"] as Dictionary).is_empty():
		f["cover"]["taken"] = false
	(f["mark"] as Node2D).queue_free()
	_streak += 1
	_kills += 1
	var pts := (150 if head else 100) + 10 * mini(_streak - 1, 10) + (50 if f["state"] == "run" else 0)
	add_score(pts)
	_sparks.append({"at": to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.6, 0)), "t": 0.3, "role": "hazard"})
	var tag := "headshot! +%d" if head else ("on the run! +%d" if f["state"] == "run" else "+%d")
	Juice.text(self, to_screen(g.global_position + Vector3(0, GOBLIN_H + 0.3, 0)), tag % pts,
		Palette.col("warn" if head else "ink"))
	Audio.play("impact_bell" if head else "hit", 0.1)
	hit3d(2.0)
	Probe.event("headshot" if head else "kill")
	if _kills % 10 == 0:
		Audio.play("voice_power_up")
	if not g.play("Death", false, 1.4):
		g.scale = Vector3(1.2, 0.1, 1.2)
	var tw := g.create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(g, "position:y", g.position.y - 2.2, 0.6)
	tw.tween_callback(g.queue_free)

func _shot_civilian(p: Dictionary) -> void:
	var n: Actor3D = p["node"]
	_people.erase(p)
	(p["mark"] as Node2D).queue_free()
	n.play("RecieveHit", false)
	var tw := n.create_tween()
	tw.tween_interval(0.8)
	tw.tween_callback(n.queue_free)
	_streak = 0
	Juice.text(self, to_screen(n.global_position + Vector3(0, PERSON_H + 0.3, 0)), "not them!", Palette.col("hazard"))
	Audio.play("voice_wrong")
	Probe.event("civilian_hit")
	lose_life()

## ---- camera -------------------------------------------------------------------------

## Eyes down the road with a step bob and a slow look around, pulled toward whoever is
## aiming at you: you turn to the danger.
func _aim_camera(delta: float, snap: bool = false) -> void:
	var f := _frame(_dist)
	var walk := clampf(_speed / WALK_MAX, 0.0, 1.0)
	var bob := sin(_t * 8.0) * 0.06 * walk
	var eye := f * Vector3(0, EYE + bob, sin(_t * 4.0) * 0.04 * walk)
	var want := _road_pos(_dist + 14.0, 2.2 * sin(_t * 0.37) + 1.0 * sin(_t * 0.81 + 1.0), 1.7 + 0.3 * sin(_t * 0.5))
	var sum := Vector3.ZERO
	var w := 0.0
	for e: Dictionary in _foes:
		var k := 2.5 if e["state"] == "aim" else (0.5 if e["state"] == "run" else 0.3)
		k *= clampf(1.0 - (e["u"] - _dist) / 40.0, 0.1, 1.0)
		sum += _road_pos(e["u"], e["lat"], e["stand_y"] + 1.0) * k
		w += k
	if w > 0.0:
		want = want.lerp(sum / w, clampf(w / (w + 1.5), 0.0, 0.6))
		want.y = minf(want.y, 4.0)          # glance up at a roof, don't stare at the sky
	_look = want if snap else _look.lerp(want, clampf(delta * 2.5, 0.0, 1.0))
	look_from(eye, _look)

## ---- 2D overlay ---------------------------------------------------------------------

func _build_overlay() -> void:
	_ov = Node2D.new()
	add_child(_ov)
	_ov.draw.connect(_draw_overlay)

	_gun = Node2D.new()
	_gun.position = GUN_REST
	add_child(_gun)
	# a pistol held in the right hand, pointing up and in toward the middle of the view
	var steel := Palette.col("bg_alt")
	var dark := Palette.col("bg").darkened(0.25)
	var parts := [
		[[Vector2(-4, 6), Vector2(30, 0), Vector2(70, 70), Vector2(30, 80)], Palette.col("bg_alt").darkened(0.35)], # sleeve
		[[Vector2(-30, -20), Vector2(4, -14), Vector2(14, 34), Vector2(-14, 40)], dark],                             # grip
		[[Vector2(-16, 4), Vector2(18, 0), Vector2(36, 44), Vector2(2, 54)], steel.darkened(0.2)],                  # hand
		[[Vector2(-58, -38), Vector2(16, -26), Vector2(10, -6), Vector2(-62, -18)], steel],                         # slide
		[[Vector2(-58, -38), Vector2(16, -26), Vector2(15, -22), Vector2(-59, -33)], Palette.col("accent")],        # rim light
		[[Vector2(-66, -34), Vector2(-58, -38), Vector2(-62, -18), Vector2(-68, -20)], dark],                       # muzzle
		[[Vector2(-20, -10), Vector2(0, -6), Vector2(-4, 6), Vector2(-16, 0)], dark],                               # trigger guard
	]
	for p in parts:
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array(p[0])
		poly.color = p[1]
		_gun.add_child(poly)

	_cross = Node2D.new()
	_cross.position = Vector2(320, 170)
	add_child(_cross)
	Probe.track(_cross, "@")

	_red = ColorRect.new()
	_red.size = play_area.size
	_red.color = Color(0, 0, 0, 0)
	_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_red)

	var hint := Label.new()
	hint.text = "tap to shoot   ·   tap the gun to reload   ·   not the people"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Palette.col("ink"))
	hint.modulate.a = 0.7
	hint.position = Vector2(10, 340)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	var tw := hint.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(hint, "modulate:a", 0.0, 1.0)

func _muzzle() -> Vector2:
	return _gun.position + Vector2(-68, -27).rotated(_gun.rotation)

func _draw_overlay() -> void:
	var view := Rect2(14, 14, 612, 332)
	for f: Dictionary in _foes:
		if f["state"] != "aim":
			continue
		var g: Actor3D = f["node"]
		var wp := g.global_position + Vector3(0, GOBLIN_H * 0.6, 0)
		var k := clampf(1.0 - f["t"] / f["aim"], 0.0, 1.0)
		var col := Palette.col("warn").lerp(Palette.col("hazard"), k)
		var c := to_screen(wp)
		if cam.is_position_behind(wp) or not view.has_point(c):
			# off screen: an arrow on the edge pointing at it, filling the same way
			var from := Vector2(320, 180)
			var dir := (c - from).normalized()
			if cam.is_position_behind(wp):
				dir = -dir
			var e := from + dir * 150.0
			e = e.clamp(view.position + Vector2(10, 10), view.end - Vector2(10, 10))
			_ov.draw_colored_polygon(PackedVector2Array([e + dir * 12.0, e + dir.orthogonal() * 8.0, e - dir.orthogonal() * 8.0]), col)
			_ov.draw_arc(e, 16.0, -PI * 0.5, -PI * 0.5 + TAU * k, 24, col, 3.0)
			continue
		var r := lerpf(26.0, 14.0, k)
		_ov.draw_arc(c, r, 0, TAU, 32, Color(col, 0.25), 2.0)
		_ov.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * k, 32, col, 3.0)
	for t: Dictionary in _tracers:
		_ov.draw_line(t["from"], t["to"], Color(Palette.col(t["role"]), clampf(t["t"] * 12.0, 0.0, 1.0)), 2.0)
	for s: Dictionary in _sparks:
		var k: float = s["t"] / 0.3
		var col := Color(Palette.col(s["role"]), clampf(k * 2.0, 0.0, 1.0))
		for i in 6:
			var d := Vector2.RIGHT.rotated(i * TAU / 6.0 + s["t"] * 3.0)
			_ov.draw_line(s["at"] + d * 3.0, s["at"] + d * (10.0 - k * 6.0), col, 2.0)
	if _flash_t > 0.0:
		var m := _muzzle()
		_ov.draw_circle(m, 14.0, Color(Palette.col("warn"), 0.9))
		_ov.draw_circle(m, 7.0, Palette.col("ink"))
	var cc := Palette.col("ink")
	var cp := _cross.position
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_ov.draw_line(cp + d * 5.0, cp + d * 11.0, Color(cc, 0.85), 2.0)
	_ov.draw_circle(cp, 1.5, Palette.col("hazard"))
	for i in MAG:
		var full := i < _ammo and _reload <= 0.0
		_ov.draw_rect(Rect2(620.0 - i * 9.0, 236, 5, 14), Palette.col("prize") if full else Color(Palette.col("ink"), 0.2))
	if _reload > 0.0:
		_ov.draw_rect(Rect2(570, 254, 55 * (1.0 - _reload / RELOAD_TIME), 3), Palette.col("prize"))

## ---- per frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	if _intro > 0.0:
		_intro -= delta
		if _intro <= 0.0:
			Audio.play("voice_go")
			Probe.event("go")
	else:
		# always walking; easing off a little while someone is close in front of you
		var want := lerpf(WALK_MIN, WALK_MAX, clampf(_t / RAMP, 0.0, 1.0))
		for f: Dictionary in _foes:
			if f["u"] - _dist < 10.0:
				want *= 0.45
				break
		_speed = lerpf(_speed, want, clampf(delta * 2.0, 0.0, 1.0))
		_dist += _speed * delta
		_extend()
		_van_cd -= delta
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_spawn_t = lerpf(2.4, 1.0, clampf(_t / 120.0, 0.0, 1.0)) * randf_range(0.7, 1.3)
			_spawn_something()
		_drive_van(delta)
		_run_goblins(delta)
		_walk_people(delta)
	_aim_camera(delta)

	var d := PInput.dir()
	if d != Vector2.ZERO:
		_cross.position = (_cross.position + d * CROSS_SPEED * delta).clamp(Vector2(20, 30), Vector2(620, 330))
	if PInput.just_pressed("action_a"):
		var snap := _nearest_foe(_cross.position, CROSS_ASSIST)
		_shoot(snap if snap.x >= 0.0 else _cross.position)
	if PInput.just_pressed("action_b"):
		_start_reload()

	_shot_cd -= delta
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			_ammo = MAG
			Audio.play("select", 0.05)
	_flash_t -= delta
	_kick = maxf(0.0, _kick - delta * 7.0)
	var lean := (_cross.position.x - 320.0) / 320.0
	_gun.position = GUN_REST + Vector2(lean * 14.0, (_cross.position.y - 180.0) / 180.0 * 8.0) + Vector2(10, 14) * _kick
	_gun.position.y += sin(_t * 8.0) * 3.0 * clampf(_speed / WALK_MAX, 0.0, 1.0)
	_gun.rotation = -0.18 * _kick + lean * 0.06
	if _reload > 0.0:
		_gun.position.y += 40.0 * sin(PI * (1.0 - _reload / RELOAD_TIME))
	_red.color.a = maxf(0.0, _red.color.a - delta * 1.4)
	for t: Dictionary in _tracers.duplicate():
		t["t"] = t["t"] - delta
		if t["t"] <= 0.0:
			_tracers.erase(t)
	for s: Dictionary in _sparks.duplicate():
		s["t"] = s["t"] - delta
		if s["t"] <= 0.0:
			_sparks.erase(s)
	_ov.queue_redraw()

## Screen position of an exposed goblin's chest within `r` px of p, or (-1, -1).
func _nearest_foe(p: Vector2, r: float) -> Vector2:
	var best := Vector2(-1, -1)
	var best_d := r
	for f: Dictionary in _foes:
		if not _exposed(f):
			continue
		var g: Actor3D = f["node"]
		if cam.is_position_behind(g.global_position):
			continue
		var s := to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.78, 0))
		if s.distance_to(p) < best_d:
			best_d = s.distance_to(p)
			best = s
	return best

func _input(e: InputEvent) -> void:
	if finished:
		return
	if e is InputEventMouseMotion:
		_cross.position = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if Flow.pointer_over_hud():
			return
		if GUN_BOX.has_point(e.position):
			_start_reload()
			return
		_shoot(e.position)
