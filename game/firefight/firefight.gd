extends GameMode3D
## firefight -- a first-person shooter where you only shoot. You walk down a night street
## on your own, stop where the trouble is, and look around; goblins pop out from behind
## cars, crates and rooftops, take aim (a ring fills around them) and hit you if the ring
## closes. Tap to shoot where you tap. Clear a stop and you walk on. See GAME.md.
##
## The street runs along +X; the camera's x is how far you have walked. Stops sit every
## STOP_GAP units. Each stop builds its own cover and its wave a little before you arrive,
## and everything behind you is freed. Hits are tested in screen space: the shot lands on
## whichever exposed actor's on-screen box contains the tap, nearest first.

const EYE := 1.6                     ## camera height
const FACADE := 12.0                 ## |z| of the building fronts on both sides
const ROAD := 7.0                    ## |z| of the kerbs
const AHEAD := 60.0                  ## how far ahead the street is built
const BEHIND := 10.0                 ## how far behind it is kept
const FIRST_STOP := 16.0
const STOP_GAP := 26.0
const WALK_SPEED := 4.6
const GOBLIN_H := 1.8
const PERSON_H := 1.8
const MAG := 6
const RELOAD_TIME := 1.0
const SHOT_GAP := 0.14               ## fastest you can fire
const TAP_SLOP := 6.0                ## screen px of forgiveness around a body
const CROSS_ASSIST := 40.0           ## keys / pad / bots: the crosshair snaps this far
const CROSS_SPEED := 320.0
const HEADSHOT := 0.22               ## top fraction of the body that counts as the head
const START_LIVES := 5
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const SHOPS := ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h"]
const TOWERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c"]
const CARS := ["sedan", "taxi", "suv", "police", "van"]
const GOBLINS := ["Goblin_Male", "Goblin_Female"]
const PEOPLE := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Female"]
const GUN_REST := Vector2(560, 312)  ## where the gun sits on screen
const GUN_BOX := Rect2(488, 262, 152, 98)   ## tap here to reload

var _dist := 0.0                     ## how far you have walked (the camera's x)
var _speed := 0.0
var _built_x := -BEHIND              ## buildings built up to here, each side
var _built_r := -BEHIND
var _road_x := -BEHIND
var _street: Array = []              ## Node3D, meta x, w (freed once behind)
var _buildings: Array = []           ## {x, w, h, side} for roof spots
var _stop_i := 0                     ## stops reached so far
var _next_stop := FIRST_STOP
var _built_stop := -1                ## index of the last stop whose wave is built
var _waves := {}                     ## stop index -> {"actors": [...], "yaw": float}
var _at_stop := false
var _actors: Array = []              ## the current stop's actors (Dictionaries, see _actor)
var _look := Vector3(20, EYE, 0)     ## where the camera is looking, smoothed
var _yaw := 0.0                      ## the current stop's look direction
var _t := 0.0
var _intro := 1.6
var _ammo := MAG
var _reload := 0.0
var _shot_cd := 0.0
var _cross: Node2D                   ## the crosshair (and the bots' "@")
var _ov: Node2D                      ## overlay: aim rings, tracers, ammo
var _gun: Node2D
var _red: ColorRect                  ## the screen flash when you are hit
var _ground: MeshInstance3D
var _tracers: Array = []             ## {from, to, t, role}
var _sparks: Array = []              ## {at, t, role}
var _flash_t := 0.0
var _kick := 0.0
var _streak := 0
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
	cam.fov = 62.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.rotation_degrees = Vector3(-48, 30, 0)
	_ground = MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(200, 200)
	gm.material = mat("bg", 0.0, 1.0)
	_ground.mesh = gm
	_ground.position = Vector3(0, -0.05, 0)
	world.add_child(_ground)
	_extend()
	_build_overlay()
	_aim_camera(0.0, true)
	Audio.play("voice_ready")
	Probe.event("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the street ------------------------------------------------------------------

func _extend() -> void:
	while _road_x < _dist + AHEAD:
		_road_segment(_road_x)
		_road_x += 4.0
	while _built_x < _dist + AHEAD:
		_built_x += _add_building(_built_x, -1.0)
	while _built_r < _dist + AHEAD:
		_built_r += _add_building(_built_r, 1.0)
	# each stop's cover and wave, built while it is still far away
	while FIRST_STOP + (_built_stop + 1) * STOP_GAP < _dist + AHEAD - 10.0:
		_built_stop += 1
		_build_wave(_built_stop)
	for n: Node3D in _street.duplicate():
		if n.get_meta("x") + n.get_meta("w") * 0.5 < _dist - BEHIND:
			_street.erase(n)
			n.queue_free()
	for b: Dictionary in _buildings.duplicate():
		if b["x"] + b["w"] < _dist - BEHIND:
			_buildings.erase(b)
	_ground.position.x = _dist

func _keep(n: Node3D, x: float, w: float) -> void:
	n.set_meta("x", x)
	n.set_meta("w", w)
	if n.get_parent() == null:
		world.add_child(n)
	_street.append(n)

func _box(size: Vector3, role: String, emission: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat(role, emission, 1.0)
	m.mesh = bm
	return m

func _road_segment(x: float) -> void:
	var mid := x + 2.0
	for side: float in [-1.0, 1.0]:
		var walk := _box(Vector3(4.05, 0.08, FACADE - ROAD), "bg_alt", 0.15)
		walk.position = Vector3(mid, 0.04, side * (ROAD + FACADE) * 0.5)
		_keep(walk, mid, 4.0)
		var kerb := _box(Vector3(4.05, 0.14, 0.16), "accent", 0.8)
		kerb.position = Vector3(mid, 0.07, side * ROAD)
		_keep(kerb, mid, 4.0)
	var dash := _box(Vector3(1.8, 0.02, 0.14), "ink", 0.4)
	dash.position = Vector3(mid, 0.01, 0.0)
	_keep(dash, mid, 4.0)

## One building on one side starting at x; returns how much street it used. Sometimes a
## parked car and a street light in front of it, unless a stop's cover lives there.
func _add_building(x: float, side: float) -> float:
	var tower := randf() < 0.22
	var name: String = TOWERS[randi() % TOWERS.size()] if tower else SHOPS[randi() % SHOPS.size()]
	var b := model(name, randf_range(10.0, 13.0) if tower else randf_range(5.5, 8.0))
	var box: AABB = b.get_meta("aabb")
	var bx := x + box.size.x * 0.5
	b.position = Vector3(bx, 0.0, side * (FACADE + box.size.z * 0.5))
	if side > 0.0:
		b.rotation.y = PI
	_keep(b, bx, box.size.x)
	_buildings.append({"x": x, "w": box.size.x, "h": box.size.y, "side": side})
	var used := box.size.x + 0.4
	if randf() < 0.4 and not _near_stop(x + used * 0.5):
		var lamp := model("light-square", 4.4)
		lamp.position = Vector3(x + used - 0.2, 0.0, side * (ROAD + 0.5))
		if side > 0.0:
			lamp.rotation.y = PI
		_keep(lamp, x + used, 0.5)
	elif randf() < 0.45 and not _near_stop(x + used * 0.5):
		var car := model(CARS[randi() % CARS.size()], 4.0)
		car.position = Vector3(x + used * 0.5, 0.0, side * (ROAD - 1.3))
		car.rotation.y = PI * 0.5 if randf() < 0.5 else -PI * 0.5
		_keep(car, x + used * 0.5, 4.0)
	return used

func _near_stop(x: float) -> bool:
	var k := roundf((x - FIRST_STOP - 12.0) / STOP_GAP)
	return absf(x - (FIRST_STOP + 12.0 + k * STOP_GAP)) < 14.0

func _roof_at(x: float, side: float) -> Dictionary:
	for b: Dictionary in _buildings:
		if b["side"] == side and x > b["x"] + 0.8 and x < b["x"] + b["w"] - 0.8:
			return b
	return {}

## ---- a stop: where you look, the cover and who hides behind it -------------------------

func _build_wave(i: int) -> void:
	var sx := FIRST_STOP + i * STOP_GAP
	var yaw := 0.0                                  # 0 = straight ahead, + = right (+Z)
	if i > 0:
		yaw = [-0.75, -0.35, 0.0, 0.35, 0.75][randi() % 5]
	var n := clampi(2 + i / 2, 2, 6)
	var civ := i >= 2 and randf() < 0.4
	var actors: Array = []
	var aim := maxf(0.85, 2.1 - 0.11 * i)
	var tries := 0
	while actors.size() < n + (1 if civ else 0) and tries < 60:
		tries += 1
		var a := yaw + randf_range(-0.42, 0.42)
		var d := randf_range(6.5, 12.5)
		var p := Vector3(sx + cos(a) * d, 0.0, sin(a) * d)
		if p.x < sx + 4.0:
			continue
		p.z = clampf(p.z, -FACADE + 1.6, FACADE - 1.6)
		if absf(p.z) < 3.2:                         # keep the walking line clear
			p.z = 3.2 * (1.0 if p.z >= 0.0 else -1.0)
		var clash := false
		for o: Dictionary in actors:
			if (o["peek"] as Vector3).distance_to(p) < 3.0:
				clash = true
		if clash:
			continue
		var is_civ := civ and actors.size() == 0
		var kind := "crate"
		var roll := randf()
		if not is_civ and roll < 0.25 and absf(p.z) > 5.0:
			kind = "roof"
		elif roll < 0.6:
			kind = "car"
		var act := _make_cover(kind, p, Vector3(sx, 0.0, 0.0))
		if act.is_empty():
			continue
		act["civ"] = is_civ
		act["aim"] = aim * randf_range(0.9, 1.15)
		act["t"] = randf_range(0.4, 1.0) + actors.size() * randf_range(0.5, 0.9)
		actors.append(act)
	_waves[i] = {"actors": actors, "yaw": yaw, "x": sx}

## Cover of one kind around p, seen from the stop. Returns the actor record (no body yet:
## the character is spawned when you arrive, so hidden goblins cost nothing on the way).
func _make_cover(kind: String, p: Vector3, stop: Vector3) -> Dictionary:
	var away := Vector3(p.x - stop.x, 0.0, p.z).normalized()
	var face := -away
	match kind:
		"roof":
			var side := signf(p.z)
			var b := _roof_at(p.x, side)
			if b.is_empty():
				return {}
			var h: float = b["h"]
			var at := Vector3(p.x, h, side * (FACADE + 0.7))
			return {"kind": kind, "hide": at - Vector3(0, GOBLIN_H + 0.2, 0), "peek": at,
				"top": h, "face": Vector3(stop.x - p.x, 0, -at.z).normalized()}
		"car":
			var car := model(CARS[randi() % CARS.size()], 4.0)
			# parked across the line of fire, so it hides whoever crouches behind it
			var across := Vector3(-away.z, 0.0, away.x)
			if minf(absf(p.z + across.z * 2.3), absf(p.z - across.z * 2.3)) < 1.6:
				car.free()                              # it would block the walking line
				return {}
			car.position = p
			car.rotation.y = atan2(across.x, across.z)
			_keep(car, p.x, 4.0)
			var hide := p + away * 1.6
			var out := 2.9 if randf() < 0.5 else -2.9
			return {"kind": kind, "hide": hide, "peek": hide + across * out, "top": -1.0, "face": face}
		_:
			var crate := Node3D.new()
			var body := _box(Vector3(1.6, 0.85, 1.0), "bg_alt", 0.2)
			body.position.y = 0.425
			crate.add_child(body)
			var rim := _box(Vector3(1.64, 0.08, 1.04), "accent", 0.9)
			rim.position.y = 0.85
			crate.add_child(rim)
			crate.position = p
			crate.rotation.y = atan2(away.x, away.z)
			_keep(crate, p.x, 1.6)
			var at := p + away * 0.9
			return {"kind": kind, "hide": at - Vector3(0, GOBLIN_H * 0.62, 0), "peek": at,
				"top": 0.85, "face": face}

## Arriving at a stop: the hidden characters take their places.
func _arrive() -> void:
	_at_stop = true
	_stop_i += 1
	var w: Dictionary = _waves.get(_stop_i - 1, {"actors": [], "yaw": 0.0})
	_waves.erase(_stop_i - 1)
	_yaw = w["yaw"]
	_actors = w["actors"]
	for a: Dictionary in _actors:
		var g := Actor3D.new()
		world.add_child(g)
		if a["civ"]:
			g.set_character(PEOPLE[randi() % PEOPLE.size()], PERSON_H)
		else:
			g.set_character(GOBLINS[randi() % GOBLINS.size()], GOBLIN_H)
		g.position = a["hide"]
		g.face(a["face"])
		g.play("Idle", true, randf_range(0.9, 1.2))
		a["node"] = g
		a["state"] = "wait"
		a["alive"] = true
		a["pops"] = 0
		a["k"] = 0.0
		# the bots' view: a 2D marker on the actor's chest while it is out, and where it
		# will pop out while it hides -- a player covers the spot, so does the bot
		var m := Node2D.new()
		m.position = Vector2(-2000, -2000)
		add_child(m)
		Probe.track(m, "x" if a["civ"] else "*")
		a["mark"] = m
	Probe.event("stop", {"n": _stop_i, "enemies": _foes()})
	Juice.text(self, Vector2(320, 80), "area %d" % _stop_i, Palette.col("accent"))

func _foes() -> int:
	var n := 0
	for a: Dictionary in _actors:
		if a["alive"] and not a["civ"]:
			n += 1
	return n

## Done with a stop: bonus, and the civilians go home.
func _clear() -> void:
	_at_stop = false
	var bonus := 25 * _stop_i
	add_score(bonus)
	Juice.text(self, Vector2(320, 120), "clear!  +%d" % bonus, Palette.col("prize"))
	Audio.play("coin")
	Probe.event("clear", {"n": _stop_i})
	for a: Dictionary in _actors:
		if a["civ"] and is_instance_valid(a["node"]):
			(a["node"] as Node3D).queue_free()
		if is_instance_valid(a.get("mark")):
			(a["mark"] as Node2D).queue_free()
	_actors = []
	_next_stop += STOP_GAP

## ---- the actors: hide, step out, aim, fire, duck ------------------------------------

func _run_actors(delta: float) -> void:
	for a: Dictionary in _actors:
		if not a["alive"]:
			continue
		var g: Actor3D = a["node"]
		a["t"] = a["t"] - delta
		match a["state"]:
			"wait":
				if a["t"] <= 0.0:
					if a["civ"] and a["pops"] >= 2:
						a["t"] = 99.0
						continue
					a["state"] = "out"
					a["k"] = 0.0
					g.play("Run" if a["kind"] == "car" else "Idle", true, 1.4)
			"out", "back":
				var out: bool = a["state"] == "out"
				a["k"] = minf(1.0, a["k"] + delta / (0.42 if a["kind"] == "car" else 0.3))
				var e := ease(a["k"], -1.8)
				var from: Vector3 = a["hide"] if out else a["peek"]
				var to: Vector3 = a["peek"] if out else a["hide"]
				g.position = from.lerp(to, e)
				if a["k"] >= 1.0:
					if out:
						a["state"] = "aim"
						a["t"] = a["aim"] * (1.4 if a["civ"] else 1.0)
						a["pops"] += 1
						g.face(a["face"])
						g.play("Idle", true, 1.0)
						Probe.event("peek")
					else:
						a["state"] = "wait"
						a["t"] = randf_range(0.7, 1.8)
			"aim":
				if a["t"] <= 0.0:
					if a["civ"]:
						a["state"] = "back"
						a["k"] = 0.0
					else:
						_enemy_fires(a)
			"fire":
				if a["t"] <= 0.0:
					a["state"] = "back"
					a["k"] = 0.0
					g.play("Run" if a["kind"] == "car" else "Idle", true, 1.4)

func _enemy_fires(a: Dictionary) -> void:
	var g: Actor3D = a["node"]
	a["state"] = "fire"
	a["t"] = 0.45
	g.play("Shoot_OneHanded", false, 1.6)
	var from := to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.62, 0))
	_tracers.append({"from": from, "to": Vector2(320 + randf_range(-60, 60), 300), "t": 0.12, "role": "hazard"})
	_red.color = Palette.col("hazard")
	_red.color.a = 0.38
	_streak = 0
	Audio.play("hurt")
	hit3d(5.0)
	Juice.text(self, Vector2(320, 210), "hit!", Palette.col("hazard"))
	Probe.event("player_hit")
	lose_life()

func _exposed(a: Dictionary) -> bool:
	return a["alive"] and a["state"] in ["aim", "fire", "out", "back"]

## ---- shooting -----------------------------------------------------------------------

## What a shot at `p` hits: [actor, headshot] for the nearest exposed actor whose on-screen
## body contains p (above its cover), or [{}, false].
func _hit_test(p: Vector2, slop: float) -> Array:
	var best := {}
	var best_d := INF
	var head := false
	for a: Dictionary in _actors:
		if not _exposed(a):
			continue
		var g: Actor3D = a["node"]
		var h := PERSON_H if a["civ"] else GOBLIN_H
		var feet := to_screen(g.global_position)
		var top := to_screen(g.global_position + Vector3(0, h, 0))
		var hpx := feet.y - top.y
		if hpx <= 1.0:
			continue
		var low := feet.y
		if a["top"] > g.global_position.y:
			low = minf(low, to_screen(Vector3(g.global_position.x, a["top"], g.global_position.z)).y)
		var half := hpx * 0.2 + slop
		if absf(p.x - top.x) > half or p.y < top.y - slop or p.y > low + slop * 0.5:
			continue
		var d := cam.global_position.distance_to(g.global_position)
		if d < best_d:
			best_d = d
			best = a
			head = p.y < top.y + hpx * HEADSHOT
	return [best, head]

func _shoot(at: Vector2) -> void:
	if finished or _intro > 0.0 or _shot_cd > 0.0:
		return
	if _reload > 0.0:
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
	var a: Dictionary = r[0]
	if a.is_empty():
		_sparks.append({"at": at, "t": 0.18, "role": "ink"})
		_streak = 0
		Probe.event("miss")
	elif a["civ"]:
		_shot_civilian(a)
	else:
		_kill(a, r[1])
	if _ammo <= 0:
		_start_reload()

func _start_reload() -> void:
	if _reload > 0.0 or _ammo >= MAG:
		return
	_reload = RELOAD_TIME
	Audio.play("click")
	Probe.event("reload")

func _kill(a: Dictionary, head: bool) -> void:
	var g: Actor3D = a["node"]
	a["alive"] = false
	(a["mark"] as Node2D).queue_free()
	_streak += 1
	var pts := (150 if head else 100) + 10 * mini(_streak - 1, 10)
	add_score(pts)
	_sparks.append({"at": to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.6, 0)), "t": 0.3, "role": "hazard"})
	Juice.text(self, to_screen(g.global_position + Vector3(0, GOBLIN_H + 0.3, 0)),
		("headshot! +%d" if head else "+%d") % pts, Palette.col("warn" if head else "ink"))
	Audio.play("impact_bell" if head else "hit", 0.1)
	hit3d(2.0)
	Probe.event("headshot" if head else "kill")
	if not g.play("Death", false, 1.4):
		g.scale = Vector3(1.2, 0.1, 1.2)
	var tw := g.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(g, "position:y", g.position.y - 2.2, 0.6)
	tw.tween_callback(g.queue_free)

func _shot_civilian(a: Dictionary) -> void:
	var g: Actor3D = a["node"]
	a["state"] = "back"
	a["k"] = 0.0
	a["pops"] = 99
	g.play("RecieveHit", false)
	_streak = 0
	Juice.text(self, to_screen(g.global_position + Vector3(0, PERSON_H + 0.3, 0)), "not them!", Palette.col("hazard"))
	Audio.play("voice_wrong")
	Probe.event("civilian_hit")
	lose_life()

## ---- camera -------------------------------------------------------------------------

## Walking: eyes ahead with a step bob and a slow look around. At a stop: the stop's
## direction, pulled toward whoever is out and aiming -- you look where the danger is.
func _aim_camera(delta: float, snap: bool = false) -> void:
	var walk := clampf(_speed / WALK_SPEED, 0.0, 1.0)
	var bob := sin(_t * 8.5) * 0.05 * walk
	var eye := Vector3(_dist, EYE + bob, sin(_t * 4.25) * 0.04 * walk)
	var want: Vector3
	if _at_stop:
		want = eye + Vector3(cos(_yaw), 0.0, sin(_yaw)) * 12.0 + Vector3(0, 0.6, 0)
		var sum := Vector3.ZERO
		var w := 0.0
		for a: Dictionary in _actors:
			if a["alive"] and not a["civ"]:
				var k := 2.0 if a["state"] == "aim" else 0.6
				sum += ((a["peek"] as Vector3) + Vector3(0, 1.0, 0)) * k
				w += k
		if w > 0.0:
			want = want.lerp(sum / w, 0.45)
	else:
		var glance := Vector3(0, 0.25 * sin(_t * 0.6), 2.6 * sin(_t * 0.45) + 1.2 * sin(_t * 0.9 + 1.0))
		want = eye + Vector3(14.0, 0.4, 0.0) + glance
		# start turning toward the next stop's direction as you get close
		var w2: Dictionary = _waves.get(_stop_i, {})
		if not w2.is_empty():
			var near := clampf(1.0 - (_next_stop - _dist) / 9.0, 0.0, 1.0)
			var y: float = w2["yaw"]
			want = want.lerp(eye + Vector3(cos(y), 0.05, sin(y)) * 12.0, near)
	_look = want if snap else _look.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
	look_from(eye, _look)

## ---- 2D overlay: crosshair, gun, rings, tracers, ammo ----------------------------------

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
	# aim rings: fill up as an enemy takes aim; closes = you are hit
	for a: Dictionary in _actors:
		if not a["alive"] or a["civ"] or a["state"] != "aim":
			continue
		var g: Actor3D = a["node"]
		var c := to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.6, 0))
		var k := clampf(1.0 - a["t"] / a["aim"], 0.0, 1.0)
		var r := lerpf(26.0, 14.0, k)
		var col := Palette.col("warn").lerp(Palette.col("hazard"), k)
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
	# crosshair
	var cc := Palette.col("ink")
	var cp := _cross.position
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		_ov.draw_line(cp + d * 5.0, cp + d * 11.0, Color(cc, 0.85), 2.0)
	_ov.draw_circle(cp, 1.5, Palette.col("hazard"))
	# ammo, bottom right above the gun
	for i in MAG:
		var full := i < _ammo and _reload <= 0.0
		var x := 620.0 - i * 9.0
		_ov.draw_rect(Rect2(x, 236, 5, 14), Palette.col("prize") if full else Color(Palette.col("ink"), 0.2))
	if _reload > 0.0:
		var k := 1.0 - _reload / RELOAD_TIME
		_ov.draw_rect(Rect2(570, 254, 55 * k, 3), Palette.col("prize"))

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
	# walk to the next stop, slow into it
	elif not _at_stop:
		var left := _next_stop - _dist
		var want := WALK_SPEED * clampf(left / 3.0, 0.15, 1.0)
		_speed = lerpf(_speed, want, clampf(delta * 3.0, 0.0, 1.0))
		_dist = minf(_next_stop, _dist + _speed * delta)
		if _dist >= _next_stop - 0.02:
			_dist = _next_stop
			_speed = 0.0
			_arrive()
		_extend()
	else:
		_run_actors(delta)
		if _foes() == 0:
			_clear()
	_aim_camera(delta)

	# crosshair on keys / stick, fire on A, reload on B
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
	for a: Dictionary in _actors:
		var m: Node2D = a.get("mark")
		if m != null and is_instance_valid(m):
			var h := PERSON_H if a["civ"] else GOBLIN_H
			var at: Vector3 = (a["node"] as Node3D).global_position if _exposed(a) else a["peek"]
			m.position = to_screen(at + Vector3(0, h * 0.78, 0))
	_ov.queue_redraw()

## Screen position of an exposed enemy's chest within `r` px of p, or (-1, -1).
func _nearest_foe(p: Vector2, r: float) -> Vector2:
	var best := Vector2(-1, -1)
	var best_d := r
	for a: Dictionary in _actors:
		if a["civ"] or not _exposed(a):
			continue
		var g: Actor3D = a["node"]
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
