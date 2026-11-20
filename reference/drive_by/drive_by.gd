extends GameMode3D
## drive_by -- you are in a car, looking out of the side window and a little ahead. The
## road bends left and right; buildings line it, with goblins perched on windowsills and
## roofs. Tap and you lob a banana that explodes where it lands: goblins in the blast are
## done for. Every goblin that slides out of view alive costs a life. People on the
## sidewalk are NOT targets. See GAME.md.
##
## A rail shooter on GameMode3D. The street is a curve: everything on it has a road
## coordinate (u = distance along the road, lat = sideways offset) and _frame(u) turns
## that into a world transform. The car (camera) drives along u; things behind it are
## freed and the street is built ahead of it. Nothing scrolls -- the camera moves.

const FACADE := -13.0                ## lat of the building fronts
const WALK := -11.0                  ## lat of the sidewalk, where people stroll
const KERB := -9.8
const CREATURE := FACADE + 0.55      ## goblins stand just in front of the facades
const AHEAD := 42.0                  ## how far ahead of the car the street is built
const BEHIND := 8.0                  ## how far behind it is kept
const SPAWN_AHEAD := 31.0            ## goblins appear this far ahead, small, where the road vanishes
const GONE_BEHIND := 7.0             ## ... and are gone this far behind the window pillar
const BASE_SPEED := 5.0              ## car speed at the start, units per second ...
const MAX_SPEED := 11.0              ## ... and after SPEED_RAMP seconds
const SPEED_RAMP := 100.0
const CREATURE_EVERY := 2.0          ## seconds between goblins at the start ...
const CREATURE_EVERY_MIN := 0.75     ## ... and after CREATURE_RAMP seconds
const CREATURE_RAMP := 90.0
const PEOPLE_EVERY := 2.6
const AIM_ASSIST := 70.0             ## a tap this close (screen px) to a goblin targets it -- thumbs are wide
const CROSS_ASSIST := 130.0          ## the hidden aim point (keys / pad / bots) snaps harder
const CROSS_SPEED := 300.0
const THROW_TIME := 0.55             ## seconds a banana is in the air
const THROW_ARC := 1.6               ## how high it arcs above the straight line
const BLAST_R := 2.6                 ## goblins this close to the burst are hit
const OOPS_R := 2.0                  ## people this close get a fright (and cost you 5)
const COMBO_WINDOW := 1.3            ## a kill this soon after the last one chains
const LOOK_AHEAD := 5.3              ## the view turns toward where the car is going (about 22 degrees)
const INTRO := 3.0                   ## seconds of the opening shot: from the street into the seat
const GOBLIN_H := 1.7
const PERSON_H := 1.8
const START_LIVES := 3
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const SHOPS := ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h"]
const TOWERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c"]
const GOBLINS := ["Goblin_Male", "Goblin_Female"]
const PEOPLE := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Female"]

var _dist := 0.0                     ## how far the car has driven (its u)
var _speed := BASE_SPEED
var _traffic := 0.0                  ## seconds left of a slow-down
var _next_traffic := 9.0
var _street: Array = []              ## static Node3D on the road: meta u, w (freed once behind)
var _road_u := 0.0                   ## the road surface is built in segments up to here
var _strip_u := -BEHIND              ## where the next building goes
var _far_u := -30.0                  ## far skyline built up to here
var _creatures: Array = []           ## Actor3D, meta: alive, u
var _people: Array = []              ## Actor3D, meta: u, lat, dir, speed, scared
var _bananas: Array = []             ## Node3D, meta: t, from, to, spin
var _cross: Node2D                   ## hidden aim point for keys / pad; the bots' "@"
var _hand: Node3D                    ## the banana in your hand (bottom right of the view)
var _flash: Blob
var _interior: Node2D
var _car: Node3D
var _ground: MeshInstance3D
var _creature_t := 1.5
var _people_t := 0.5
var _combo := 0
var _combo_t := 0.0
var _t := 0.0
var _intro_t := 0.0
var _sfx_was := 0.8

func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)

func _ready() -> void:
	title = "drive by"
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	set_lives(START_LIVES)
	cam.fov = 52.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50.0
	sun.rotation_degrees = Vector3(-42, 24, 0)
	_build_street()
	_build_car()
	for i in 3:
		_spawn_person(true)
	_car = Node3D.new()
	_car.transform = _frame(0.0)
	var sedan := model("sedan", 4.6)
	sedan.rotation.y = PI * 0.5
	_car.add_child(sedan)
	world.add_child(_car)
	_speed = 0.0
	_intro_step(0.0)
	Probe.event("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the road as a curve --------------------------------------------------------------

## Sideways wander of the road centre line at distance u: gentle, never straight for long.
func _wander(u: float) -> float:
	return 9.0 * sin(u / 45.0) + 5.0 * sin(u / 23.0 + 1.3)

func _wander_slope(u: float) -> float:
	return 9.0 / 45.0 * cos(u / 45.0) + 5.0 / 23.0 * cos(u / 23.0 + 1.3)

## World transform of the road at u: origin on the centre line, local +X = forward along
## the road, local +Y up, local +Z sideways (so lat < 0 is the building side).
func _frame(u: float) -> Transform3D:
	var fwd := Vector3(1.0, 0.0, _wander_slope(u)).normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	return Transform3D(Basis(fwd, Vector3.UP, side), Vector3(u, 0.0, _wander(u)))

func _road_pos(u: float, lat: float, y: float = 0.0) -> Vector3:
	return _frame(u) * Vector3(0.0, y, lat)

## Rough road coordinates of a world point (the road is nearly a function of x).
func _lat_of(p: Vector3) -> float:
	return (p.z - _wander(p.x)) / sqrt(1.0 + pow(_wander_slope(p.x), 2.0))

## ---- the street ------------------------------------------------------------------

func _build_street() -> void:
	_ground = MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(160, 160)
	gm.material = mat("bg", 0.0, 1.0)
	_ground.mesh = gm
	_ground.position = Vector3(0, -0.05, 0)
	world.add_child(_ground)
	_road_u = -BEHIND
	_extend()

## Build road, sidewalk, buildings and skyline ahead of the car; free what is behind.
func _extend() -> void:
	while _road_u < _dist + AHEAD:
		_road_segment(_road_u)
		_road_u += 4.0
	while _strip_u < _dist + AHEAD:
		_add_building()
	while _far_u < _dist + AHEAD + 30.0:
		_add_far()
	for n: Node3D in _street.duplicate():
		if n.get_meta("u") + n.get_meta("w") * 0.5 < _dist - BEHIND:
			_street.erase(n)
			n.queue_free()

func _place(n: Node3D, u: float, lat: float, w: float, y: float = 0.0) -> void:
	n.transform = _frame(u)
	n.position = _road_pos(u, lat, y)
	n.set_meta("u", u)
	n.set_meta("w", w)
	world.add_child(n)
	_street.append(n)

func _road_segment(u: float) -> void:
	var mid := u + 2.0
	_place(_box(Vector3(4.15, 0.02, 14.0), "bg", 0.0), mid, -4.0, 4.0)          # road
	_place(_box(Vector3(4.15, 0.04, 3.2), "bg_alt", 0.2), mid, WALK - 0.4, 4.0)   # sidewalk
	_place(_box(Vector3(4.15, 0.12, 0.15), "accent", 0.8), mid, KERB, 4.0, 0.06) # kerb
	_place(_box(Vector3(2.0, 0.02, 0.14), "ink", 0.4), mid, -7.0, 4.0, 0.02)     # lane dash

func _box(size: Vector3, role: String, emission: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat(role, emission, 1.0)
	m.mesh = bm
	return m

func _add_building() -> void:
	var tower := randf() < 0.25
	var name: String = TOWERS[randi() % TOWERS.size()] if tower else SHOPS[randi() % SHOPS.size()]
	var b := model(name, randf_range(9.0, 12.0) if tower else randf_range(4.5, 7.5))
	var box: AABB = b.get_meta("aabb")
	var u := _strip_u + box.size.x * 0.5
	_place(b, u, FACADE - box.size.z * 0.5, box.size.x)
	b.set_meta("h", box.size.y)
	_strip_u += box.size.x + 0.3
	# something on the sidewalk between buildings now and then: a tree or a street light
	var roll := randf()
	if roll < 0.45:
		var tree := model("tree-large" if randf() < 0.5 else "tree-small", randf_range(2.4, 3.6))
		_place(tree, _strip_u - 0.15, WALK - 0.9, 1.0)
		tree.rotate_y(randf() * TAU)
	elif roll < 0.7:
		var lamp := model("light-square", 4.2)
		_place(lamp, _strip_u - 0.15, KERB - 0.4, 0.5)

## The far skyline and clouds: further from the road, so they slide past more slowly.
func _add_far() -> void:
	var b := model(TOWERS[randi() % TOWERS.size()] if randf() < 0.5 else SHOPS[randi() % SHOPS.size()], randf_range(9.0, 17.0))
	var w: float = (b.get_meta("aabb") as AABB).size.x
	_place(b, _far_u + w * 0.5, -30.0 - randf_range(0.0, 6.0), w)
	if randf() < 0.6:
		var c := Node3D.new()
		for j in 3:
			var puff := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = randf_range(1.2, 2.2)
			sm.height = sm.radius * 1.4
			sm.material = mat("ink", 0.25, 1.0)
			puff.mesh = sm
			puff.position = Vector3(j * 1.6 - 1.6, randf_range(-0.2, 0.3), 0)
			c.add_child(puff)
		_place(c, _far_u + randf_range(0.0, 8.0), randf_range(-42.0, -34.0), 6.0, randf_range(14.0, 21.0))
	_far_u += w + randf_range(0.2, 1.5)

## The building whose facade spans road distance u, or null.
func _building_at(u: float) -> Node3D:
	for n: Node3D in _street:
		if not n.has_meta("h"):
			continue
		if absf(n.get_meta("u") - u) <= n.get_meta("w") * 0.5 - 0.4:
			return n
	return null

## ---- the car: camera, interior, the banana in your hand -------------------------------

## Where the car is right now, with the view turned a little ahead plus a slow drift, the
## way a head moves in a moving car, and a bob that grows with speed.
func _aim_camera() -> void:
	var f := _frame(_dist)
	var bob := sin(_t * 9.0) * 0.012 * _speed / MAX_SPEED
	var drift := Vector3(2.2 * sin(_t * 0.47) + 1.1 * sin(_t * 0.83 + 1.0),
		0.9 * sin(_t * 0.37 + 2.0) + 0.4 * sin(_t * 1.1),
		0.6 * sin(_t * 0.29 + 0.7))
	look_from(f * Vector3(0, 1.55 + bob, 0), f * (Vector3(LOOK_AHEAD, 4.2 + bob, FACADE) + drift))

## The opening shot: a wide view of the street from across the road, swooping into the
## driver's seat. The interior fades in as we arrive, the car model vanishes once we are in.
func _intro_step(k: float) -> void:
	var e := ease(clampf(k, 0.0, 1.0), -2.2)
	var f := _frame(0.0)
	var pos := (f * Vector3(-9.0, 5.5, 13.0)).lerp(f * Vector3(0, 1.55, 0), e)
	var look := (f * Vector3(0.0, 1.2, 0.0)).lerp(f * Vector3(LOOK_AHEAD, 4.2, FACADE), e)
	look_from(pos, look)
	_interior.modulate.a = clampf((k - 0.72) / 0.22, 0.0, 1.0)
	if is_instance_valid(_car):
		_car.visible = k < 0.86
	_update_hand()

func _build_car() -> void:
	var dark := Palette.col("bg").darkened(0.35)
	var trim := Palette.col("bg_alt")
	_interior = Node2D.new()
	_interior.modulate.a = 0.0
	add_child(_interior)
	# pillars, roof and door sill: the window frame, drawn over the 3D view
	for pts in [PackedVector2Array([Vector2(0, 0), Vector2(78, 0), Vector2(52, 360), Vector2(0, 360)]),
			PackedVector2Array([Vector2(640, 0), Vector2(640, 360), Vector2(608, 360), Vector2(626, 0)]),
			PackedVector2Array([Vector2(0, 0), Vector2(640, 0), Vector2(640, 26), Vector2(0, 26)])]:
		var p := Polygon2D.new()
		p.polygon = pts
		p.color = dark
		_interior.add_child(p)
	var sill := Polygon2D.new()
	sill.polygon = PackedVector2Array([Vector2(0, 318), Vector2(200, 330), Vector2(440, 330), Vector2(640, 318), Vector2(640, 360), Vector2(0, 360)])
	sill.color = trim
	_interior.add_child(sill)

	# the banana in your hand, bottom right, in 3D so it matches the light
	_hand = model("item-banana", 0.3)
	world.add_child(_hand)

	_flash = Blob.new()
	_flash.role = "warn"
	_flash.radius = 16.0
	_flash.shape = "circle"
	_flash.glow = true
	_flash.visible = false
	add_child(_flash)

	# the aim point for keys / stick and the bots. Deliberately invisible: a crosshair
	# floating over the street annoyed the player, and taps aim by themselves.
	_cross = Node2D.new()
	_cross.position = Vector2(340, 170)
	add_child(_cross)
	Probe.track(_cross, "@")

	var hint := Label.new()
	hint.text = "tap a goblin to throw   ·   not the people"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Palette.col("ink"))
	hint.modulate.a = 0.7
	hint.position = Vector2(10, 338)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interior.add_child(hint)

func _hand_pos() -> Vector3:
	return cam.global_transform * Vector3(0.95, -0.66, -2.3)

func _update_hand() -> void:
	if _hand == null:
		return
	_hand.visible = _interior.modulate.a > 0.5
	_hand.global_position = _hand_pos()
	_hand.rotation = cam.rotation + Vector3(0.5, 0.3, -0.9 + sin(_t * 1.7) * 0.08)

## ---- goblins --------------------------------------------------------------------------

func _spawn_creature() -> void:
	var u := _dist + SPAWN_AHEAD
	var b := _building_at(u)
	if b == null:
		return
	var h: float = b.get_meta("h")
	var g := Actor3D.new()
	world.add_child(g)
	g.set_character(GOBLINS[randi() % GOBLINS.size()], GOBLIN_H)
	# a windowsill, or the roof
	var y := h if randf() < 0.3 else randf_range(1.2, maxf(1.3, minf(h - 1.0, 6.5)))
	g.transform = _frame(u)
	g.position = _road_pos(u, CREATURE, y)
	g.face(_frame(u).basis.z)   # toward the road
	g.set_meta("alive", true)
	g.set_meta("u", u)
	g.play("Idle" if randf() < 0.6 else "Punch", true, randf_range(0.9, 1.3))
	_creatures.append(g)
	track3d(g, "x", true)
	Probe.event("creature_spawn")

func _escaped(g: Actor3D) -> void:
	_creatures.erase(g)
	g.queue_free()
	Probe.event("escaped")
	Juice.text(self, Vector2(60, 120), "missed one!", Palette.col("hazard"))
	shake3d(2.5)
	lose_life()

func _kill(g: Actor3D) -> void:
	g.set_meta("alive", false)
	_creatures.erase(g)
	if _combo_t > 0.0:
		_combo += 1
	else:
		_combo = 1
	_combo_t = COMBO_WINDOW
	var pts := 10 * _combo
	add_score(pts)
	Probe.event("kill", {"combo": _combo})
	if _combo > 1:
		Probe.event("combo")
	Juice.text(self, to_screen(g.global_position + Vector3(0, GOBLIN_H + 0.4, 0)),
		"+%d" % pts + ("  x%d!" % _combo if _combo > 1 else ""),
		Palette.col("warn" if _combo > 1 else "ink"))
	if not g.play("Death", false, 1.5):
		g.scale = Vector3(1.2, 0.1, 1.2)
	var tw := g.create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(g.queue_free)

## ---- people on the sidewalk ----------------------------------------------------------

func _spawn_person(anywhere: bool = false) -> void:
	var w := Actor3D.new()
	world.add_child(w)
	w.set_character(PEOPLE[randi() % PEOPLE.size()], PERSON_H)
	var dir := -1.0 if randf() < 0.5 else 1.0
	var u := _dist + (randf_range(-4.0, AHEAD - 6.0) if anywhere else AHEAD - 4.0)
	w.set_meta("u", u)
	w.set_meta("lat", WALK + randf_range(-0.6, 0.6))
	w.set_meta("dir", dir)
	w.set_meta("speed", randf_range(1.0, 1.9))
	w.set_meta("scared", 0.0)
	_place_person(w)
	w.play("Walk", true, w.get_meta("speed") / 1.7)
	_people.append(w)
	Probe.event("person_spawn")

func _place_person(w: Actor3D) -> void:
	var u: float = w.get_meta("u")
	w.transform = _frame(u)
	w.position = _road_pos(u, w.get_meta("lat"))
	w.face(_frame(u).basis.x * w.get_meta("dir"))

func _walk_people(delta: float) -> void:
	for w: Actor3D in _people.duplicate():
		var scared: float = w.get_meta("scared")
		if scared > 0.0:
			scared -= delta
			w.set_meta("scared", scared)
			if scared <= 0.0:
				w.play("Walk", true, w.get_meta("speed") / 1.7)
			continue
		var u: float = w.get_meta("u") + w.get_meta("dir") * w.get_meta("speed") * delta
		w.set_meta("u", u)
		if u < _dist - BEHIND or u > _dist + AHEAD:
			_people.erase(w)
			w.queue_free()
			continue
		_place_person(w)

## ---- bananas --------------------------------------------------------------------------

## Where a tap lands: a goblin near the tap (aim assist), else the first thing the camera
## ray meets -- a facade, or the ground.
func _target_for(screen: Vector2, assist: float) -> Vector3:
	var best: Actor3D = null
	var best_d := INF
	for g: Actor3D in _creatures:
		if not g.get_meta("alive"):
			continue
		var sp := to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.5, 0))
		var d := sp.distance_to(screen)
		var px := absf(to_screen(g.global_position + Vector3(0, GOBLIN_H, 0)).y - to_screen(g.global_position).y)
		if d < maxf(assist, px * 0.8) and d < best_d:
			best_d = d
			best = g
	if best != null:
		return best.global_position + Vector3(0, GOBLIN_H * 0.5, 0)
	var ray := screen_ray(screen)
	var p: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	for i in 90:
		p += dir * 0.5
		if p.y <= 0.05 or _lat_of(p) <= FACADE + 0.3:
			return p
	return p

func _throw(at: Vector2, assist: float = AIM_ASSIST) -> void:
	if finished or _intro_t < INTRO:
		return
	_cross.position = at
	var target := _target_for(at, assist)
	var b := model("item-banana", 0.4)
	world.add_child(b)
	b.set_meta("t", 0.0)
	b.set_meta("from", _hand_pos())
	b.set_meta("to", target)
	b.set_meta("spin", Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)))
	b.global_position = _hand_pos()
	_bananas.append(b)
	_flash.position = to_screen(_hand_pos() + Vector3(0, 0.2, 0))
	_flash.visible = true
	_flash.scale = Vector2.ONE
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "scale", Vector2.ONE * 0.2, 0.12)
	tw.tween_callback(func(): _flash.visible = false)
	_hand.scale = Vector3.ONE * 0.2
	var hw := _hand.create_tween()
	hw.tween_property(_hand, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("jump", 0.15)
	Probe.event("throw")

func _fly_bananas(delta: float) -> void:
	for b: Node3D in _bananas.duplicate():
		var t: float = b.get_meta("t") + delta
		b.set_meta("t", t)
		var k := clampf(t / THROW_TIME, 0.0, 1.0)
		var from: Vector3 = b.get_meta("from")
		var to: Vector3 = b.get_meta("to")
		b.global_position = from.lerp(to, k) + Vector3.UP * (THROW_ARC * 4.0 * k * (1.0 - k))
		b.rotation += b.get_meta("spin") * delta
		if k >= 1.0:
			_bananas.erase(b)
			_explode(to)
			b.queue_free()

func _explode(at: Vector3) -> void:
	# the burst: a yellow sphere that swells and vanishes, debris, a thump
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.material = mat("warn", 1.2)
	s.mesh = sm
	world.add_child(s)
	s.global_position = at
	s.scale = Vector3.ONE * 0.3
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * BLAST_R * 0.55, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", Vector3.ONE * 0.01, 0.12)
	tw.tween_callback(s.queue_free)
	_spawn_debris(at, "warn", 8)
	Audio.play("explode", 0.12)
	hit3d(3.0)
	Probe.event("burst")

	var hit := 0
	for g: Actor3D in _creatures.duplicate():
		if g.get_meta("alive") and g.global_position.distance_to(at) <= BLAST_R + GOBLIN_H * 0.5:
			_kill(g)
			hit += 1
	for w: Actor3D in _people:
		if w.get_meta("scared") <= 0.0 and w.global_position.distance_to(at) <= OOPS_R + PERSON_H * 0.5:
			w.set_meta("scared", 1.2)
			w.play("RecieveHit", false)
			add_score(-5)
			Probe.event("oops")
			Juice.text(self, to_screen(w.global_position + Vector3(0, PERSON_H + 0.3, 0)), "oops! -5", Palette.col("hazard"))
	if hit == 0:
		Probe.event("miss")

func _spawn_debris(at: Vector3, role: String, n: int) -> void:
	for i in n:
		var d := RigidBody3D.new()
		d.mass = 0.2
		var sz := randf_range(0.12, 0.26)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * sz
		bm.material = mat(role, 0.9)
		mi.mesh = bm
		d.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * sz
		cs.shape = bs
		d.add_child(cs)
		world.add_child(d)
		d.global_position = at + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
		d.linear_velocity = Vector3(randf_range(-4, 4), randf_range(3, 8), randf_range(-4, 4))
		d.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		get_tree().create_timer(1.3).timeout.connect(d.queue_free)

## ---- per frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	if _intro_t < INTRO:
		_intro_t += delta
		_intro_step(_intro_t / INTRO)
		if _intro_t >= INTRO:
			Probe.event("drive")
			Audio.play("select")
		return
	_t += delta
	_combo_t -= delta

	# the car: a slow ramp, a gentle sway, and traffic that slows it right down now and then
	_next_traffic -= delta
	if _next_traffic <= 0.0:
		_traffic = randf_range(2.0, 3.5)
		_next_traffic = randf_range(9.0, 16.0)
	var wanted := lerpf(BASE_SPEED, MAX_SPEED, clampf(_t / SPEED_RAMP, 0.0, 1.0)) * (1.0 + 0.25 * sin(_t * 0.31))
	if _traffic > 0.0:
		_traffic -= delta
		wanted *= 0.45
	_speed = lerpf(_speed, wanted, 1.5 * delta)
	_dist += _speed * delta
	_extend()
	_aim_camera()
	_update_hand()
	_ground.position.x = _dist
	_ground.position.z = _wander(_dist)

	# aim point on keys / stick, throw on A
	var d := PInput.dir()
	if d != Vector2.ZERO:
		_cross.position = (_cross.position + d * CROSS_SPEED * delta).clamp(Vector2(40, 30), Vector2(600, 320))
	if PInput.just_pressed("action_a"):
		_throw(_cross.position, CROSS_ASSIST)

	_fly_bananas(delta)
	_walk_people(delta)
	for g: Actor3D in _creatures.duplicate():
		if g.get_meta("alive") and g.get_meta("u") < _dist - GONE_BEHIND:
			_escaped(g)

	_creature_t -= delta
	if _creature_t <= 0.0:
		_creature_t = lerpf(CREATURE_EVERY, CREATURE_EVERY_MIN, clampf(_t / CREATURE_RAMP, 0.0, 1.0))
		_spawn_creature()
	_people_t -= delta
	if _people_t <= 0.0:
		_people_t = PEOPLE_EVERY
		if _people.size() < 12:
			_spawn_person()

func _input(e: InputEvent) -> void:
	if finished or _intro_t < INTRO:
		return
	if e is InputEventMouseMotion:
		_cross.position = e.position
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if Flow.pointer_over_hud():
			return
		_throw(e.position)
