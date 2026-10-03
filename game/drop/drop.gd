extends GameMode3D
## drop -- a little neon town square at night, people crossing it, and a pocket monster
## hovering in the sky where you point (our own designs, built in _monster()). Tap and it
## falls as a real 3D rigid body; anyone under it is squashed and the next one appears at
## once. People who make it across cost a life. Fifteen levels, each with its
## own goal, some against the clock, some with only so many things to drop. See GAME.md.
##
## The kit's first 3D game and the reference for GameMode3D (shell/game_mode_3d.gd):
## model() for the scenery, shapes built from palette materials for the monsters, Actor3D
## for the walking people.

const HOVER_Y := 8.0                 ## how high the waiting thing floats (and falls from)
const GRAVITY_SCALE := 3.0           ## Earth gravity floats; this reads as a drop
const CURSOR_SPEED := 10.0           ## world units per second on the keys / stick
const DROP_COOLDOWN := 0.3
const WALK_MIN := 1.3                ## walker speed range, units per second
const WALK_MAX := 2.4
const SPAWN_RAMP := 60.0             ## a level's spawn gap shrinks to 75% over this long
const MAX_WALKERS := 22
const WALKER_R := 0.35               ## a falling thing this close to a walker's centre squashes it
const WALKER_H := 1.8
const HIT_SPEED := 3.0               ## falling slower than this is just resting
const SETTLE := 2.5                  ## seconds a landed thing lies there before sinking away
const MAX_THINGS := 8
const START_LIVES := 3
const INTRO_TIME := 2.4              ## the "LEVEL 4 / squash 6 with 10 drops" banner
const CLEAR_TIME := 2.2              ## prize pops up and flies to the shelf
const FAIL_TIME := 1.6               ## "TIME'S UP" stays up this long before game over
const CROWN_TIME := 4.5
const RESOLVE_TIME := 0.6            ## after landing, a drop that squashed nobody is a miss
const SHELF_X := 624.0               ## prizes collect down the right-hand edge
const SHELF_Y := 66.0
const SHELF_STEP := 17.0
## The ladder. Goals:
##   squash -- squash `need` people           combo  -- `need` drops that squash 2+ at once
##   streak -- `need` hits in a row; a drop that squashes nobody resets it
##   survive -- last `need` seconds (escapes still cost lives)
## Modifiers, mixed in on some levels only:
##   time   -- seconds to do it in (0 = no clock)     drops -- things you get (0 = unlimited)
##   friends -- share of walkers wearing a halo: squash one and it costs a life
##   groups -- chance a walker comes with company (what makes combos possible)
##   spawn  -- seconds between walkers            speed -- walking speed multiplier
const LEVELS := [
	{"goal": "squash", "need": 5, "spawn": 2.4, "speed": 0.7, "prize": "beehive"},
	{"goal": "squash", "need": 10, "spawn": 1.8, "speed": 0.85, "prize": "potion_red"},
	{"goal": "squash", "need": 8, "time": 40, "spawn": 1.4, "speed": 1.0, "prize": "ghost"},
	{"goal": "squash", "need": 6, "drops": 10, "spawn": 1.4, "speed": 1.0, "groups": 0.25, "prize": "potion_blue"},
	{"goal": "combo", "need": 2, "spawn": 1.6, "speed": 1.0, "groups": 0.6, "prize": "banner"},
	{"goal": "survive", "need": 40, "spawn": 1.25, "speed": 1.1, "prize": "crab"},
	{"goal": "squash", "need": 10, "friends": 0.3, "spawn": 1.3, "speed": 1.1, "prize": "potion_green"},
	{"goal": "streak", "need": 4, "spawn": 1.3, "speed": 1.1, "prize": "bow"},
	{"goal": "squash", "need": 10, "time": 50, "drops": 18, "spawn": 1.1, "speed": 1.15, "groups": 0.3, "prize": "princess"},
	{"goal": "combo", "need": 3, "drops": 15, "spawn": 1.4, "speed": 1.15, "groups": 0.6, "prize": "gold_bar"},
	{"goal": "squash", "need": 12, "time": 45, "friends": 0.4, "spawn": 1.0, "speed": 1.25, "prize": "wizard"},
	{"goal": "streak", "need": 5, "friends": 0.25, "spawn": 1.2, "speed": 1.3, "prize": "snail"},
	{"goal": "survive", "need": 60, "friends": 0.2, "spawn": 0.95, "speed": 1.25, "prize": "sword"},
	{"goal": "combo", "need": 4, "time": 60, "spawn": 1.2, "speed": 1.3, "groups": 0.7, "prize": "potion_red"},
	# the last one: everything at once
	{"goal": "squash", "need": 20, "time": 75, "drops": 32, "friends": 0.3, "spawn": 1.1, "speed": 1.15,
		"groups": 0.35, "prize": "crown"},
]
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
## What can fall: little pocket monsters, our own designs, built from spheres and cones in
## _monster() so they reskin with the palette. `size` is the longest side in world units (a
## walker is 1.8 tall), `role` the main body colour.
const THINGS := [
	{"name": "sparkit", "size": 2.6, "mass": 3.0, "role": "warn", "sfx": "impact_soft"},
	{"name": "blubbo", "size": 2.7, "mass": 4.0, "role": "accent", "sfx": "impact_soft"},
	{"name": "embear", "size": 2.8, "mass": 5.0, "role": "hazard", "sfx": "impact_punch"},
	{"name": "leafpup", "size": 2.7, "mass": 4.0, "role": "friend", "sfx": "impact_soft"},
	{"name": "spikoon", "size": 2.5, "mass": 4.0, "role": "player", "sfx": "impact_wood"},
	{"name": "owlbit", "size": 2.5, "mass": 3.0, "role": "prize", "sfx": "impact_soft"},
	{"name": "snoozle", "size": 3.3, "mass": 8.0, "role": "player", "sfx": "impact_punch"},
	{"name": "cloudy", "size": 2.8, "mass": 2.0, "role": "ink", "sfx": "impact_light"},
]
const PEOPLE := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Female"]

var _cursor: Node3D                  ## where the next thing will land; the bots' "@"
var _hover: Node3D                   ## the thing waiting in the sky
var _shadow: MeshInstance3D          ## its footprint on the ground
var _thing: Dictionary = {}
var _cooldown := 0.0
var _walkers: Array = []             ## Actor3D, meta: goal, speed
var _things: Array = []              ## RigidBody3D, meta: kills, landed, rest, sink, sfx, aabb
var _spawn_t := 1.2
var _t := 0.0                        ## time since the game began (drives the hover bob)
var _lt := 0.0                       ## time into the current level's play
var _sfx_was := 0.8
var _level := 1
var _progress := 0
var _drops_left := 0                 ## only meaningful when the level sets "drops"
var _time_left := 0.0                ## only meaningful when the level sets "time"
## "intro" -> "play" -> "clear" -> "intro" ...; "fail" -> lose(); after the last, "crown" -> win()
var _phase := "intro"
var _phase_left := 0.0
var _fail_msg := ""
var _overlay: Node2D                 ## draws on top of the 3D view (this node's own _draw is under it)
var _shelf := {}                     ## level -> prize Blob
var _crown_size := 0.0

## Set at construction: the shell sizes its backdrop off play_area before _ready runs.
func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-12, -7, 24, 14)

func _ready() -> void:
	title = "drop"
	super()

func start(config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	set_lives(START_LIVES)
	look_from(Vector3(0, 17, 16), Vector3(0, 0.5, -1.0))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = Vector3(-48, -28, 0)
	_build_square()
	_build_cursor()
	_next_thing()
	_build_ui()
	Probe.event("start")
	_begin_level(clampi(int(config.get("level", 1)), 1, LEVELS.size()))

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the town square --------------------------------------------------------------

func _build_square() -> void:
	# something to land on: an infinite floor at Y=0
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	world.add_child(floor_body)

	# the ground beyond the square, so the world does not end at the kerb
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(90, 90)
	gm.material = mat("bg", 0.0, 1.0)
	ground.mesh = gm
	ground.position = Vector3(0, -0.02, 0)
	world.add_child(ground)

	# the paved square itself
	var slab := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = world_area.size
	pm.material = mat("bg_alt", 0.25, 0.9)
	slab.mesh = pm
	slab.position = Vector3(world_area.get_center().x, 0.0, world_area.get_center().y)
	world.add_child(slab)

	# neon kerb around it
	var w := world_area.size.x
	var d := world_area.size.y
	for edge in [[Vector3(0, 0.08, -d * 0.5), Vector3(w, 0.16, 0.18)],
			[Vector3(0, 0.08, d * 0.5), Vector3(w, 0.16, 0.18)],
			[Vector3(-w * 0.5, 0.08, 0), Vector3(0.18, 0.16, d)],
			[Vector3(w * 0.5, 0.08, 0), Vector3(0.18, 0.16, d)]]:
		var kerb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = edge[1]
		bm.material = mat("accent", 0.9)
		kerb.mesh = bm
		kerb.position = slab.position + edge[0]
		world.add_child(kerb)

	# a row of houses behind the square, street lights on the corners, trees down the sides
	var houses := ["building-type-a", "building-type-b", "building-type-c", "building-type-d", "building-type-e"]
	for i in 6:
		var h := model(houses[i % houses.size()], 5.5)
		h.position = Vector3(-14.0 + i * 5.6, 0, -11.5)
		world.add_child(h)
	for corner in [Vector3(-12.6, 0, -7.6), Vector3(12.6, 0, -7.6), Vector3(-12.6, 0, 7.6), Vector3(12.6, 0, 7.6)]:
		var lamp := model("light-square", 3.8)
		lamp.position = corner
		lamp.rotation.y = PI * 0.25 if corner.x < 0 else -PI * 0.25
		world.add_child(lamp)
	for i in 5:
		for side in [-1.0, 1.0]:
			var tree := model("tree-large" if i % 2 == 0 else "tree-small", 3.0 if i % 2 == 0 else 2.2)
			tree.position = Vector3(side * randf_range(14.5, 17.0), 0, -6.0 + i * 3.2)
			tree.rotation.y = randf() * TAU
			world.add_child(tree)

func _build_cursor() -> void:
	_cursor = Node3D.new()
	world.add_child(_cursor)
	track3d(_cursor, "@")
	_hover = Node3D.new()
	world.add_child(_hover)
	_shadow = MeshInstance3D.new()
	var sm := BoxMesh.new()
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0, 0, 0, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	_shadow.mesh = sm
	world.add_child(_shadow)

func _build_ui() -> void:
	_overlay = Node2D.new()
	_overlay.z_index = 10
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)

## ---- the things that fall ------------------------------------------------------------

func _next_thing() -> void:
	_thing = THINGS[randi() % THINGS.size()]
	for c in _hover.get_children():
		c.queue_free()
	var pivot := _monster(_thing)
	_hover.add_child(pivot)
	var b: AABB = pivot.get_meta("aabb")
	(_shadow.mesh as BoxMesh).size = Vector3(b.size.x, 0.04, b.size.z)

func _drop() -> void:
	if _cooldown > 0.0 or finished or _phase != "play":
		return
	if _lv().get("drops", 0) > 0:
		if _drops_left <= 0:
			return
		_drops_left -= 1
		if _drops_left == 0:
			_hover.visible = false
			_shadow.visible = false
	_cooldown = DROP_COOLDOWN
	var body := RigidBody3D.new()
	body.gravity_scale = GRAVITY_SCALE
	body.mass = _thing["mass"]
	body.contact_monitor = true
	body.max_contacts_reported = 4
	var pivot := _monster(_thing)
	body.add_child(pivot)
	add_box_collision(body, pivot, 0.9)
	body.set_meta("aabb", pivot.get_meta("aabb"))
	body.set_meta("sfx", _thing["sfx"])
	body.set_meta("kills", 0)
	body.set_meta("landed", false)
	body.set_meta("rest", 0.0)
	body.set_meta("sink", -1.0)
	body.set_meta("resolved", false)
	world.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, _hover.rotation.y), _cursor.position + Vector3(0, HOVER_Y, 0))
	body.angular_velocity = Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))
	body.body_entered.connect(func(_other: Node) -> void: _on_land(body))
	_things.append(body)
	while _things.size() > MAX_THINGS:
		var old = _things.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	Audio.play("open")
	Probe.event("drop", {"thing": _thing["name"]})
	_next_thing()

func _on_land(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.get_meta("landed"):
		return
	body.set_meta("landed", true)
	# a soft splat: the monster squashes flat and springs back (the collision box does not)
	var look: Node3D = body.get_child(0)
	var tw := look.create_tween()
	tw.tween_property(look, "scale", Vector3(1.3, 0.65, 1.3), 0.07)
	tw.tween_property(look, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(RESOLVE_TIME).timeout.connect(func(): _resolve(body))
	hit3d(3.5)
	Audio.play(body.get_meta("sfx"))
	# body_entered runs inside the physics flush; spawn debris once it is over
	_spawn_debris.call_deferred(body.global_position, "warn", 5)

func _physics_process(delta: float) -> void:
	for body: RigidBody3D in _things:
		if not is_instance_valid(body):
			continue
		var sink: float = body.get_meta("sink")
		if sink >= 0.0:
			sink += delta
			body.set_meta("sink", sink)
			body.position.y -= 3.0 * delta
			if sink > 1.2:
				body.queue_free()
			continue
		# a fast-falling thing squashes any walker inside its box (checked in the body's
		# own space, so a tumbling truck hits with its real footprint)
		if body.linear_velocity.y < -HIT_SPEED:
			var b: AABB = body.get_meta("aabb")
			var inv := body.global_transform.affine_inverse()
			var reach := b.grow(WALKER_R)
			reach.position.y -= WALKER_H * 0.5
			reach.size.y += WALKER_H
			for w: Actor3D in _walkers.duplicate():
				var lp := inv * (w.global_position + Vector3(0, WALKER_H * 0.5, 0))
				if reach.has_point(lp):
					_squash(w, body)
		# a landed thing that has stopped moving sinks away after a moment
		var resting: bool = body.sleeping or (body.linear_velocity.length_squared() < 0.04
			and body.angular_velocity.length_squared() < 0.04)
		var rest: float = body.get_meta("rest") + delta if resting else 0.0
		body.set_meta("rest", rest)
		if rest > SETTLE:
			body.set_meta("sink", 0.0)
			body.freeze = true
			for c in body.get_children():
				if c is CollisionShape3D:
					c.disabled = true
	_things = _things.filter(func(b): return is_instance_valid(b))

func _spawn_debris(at: Vector3, role: String, n: int) -> void:
	for i in n:
		var d := RigidBody3D.new()
		d.mass = 0.2
		var s := randf_range(0.14, 0.3)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * s
		bm.material = mat(role, 0.9)
		mi.mesh = bm
		d.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * s
		cs.shape = bs
		d.add_child(cs)
		world.add_child(d)
		d.global_position = at + Vector3(randf_range(-0.4, 0.4), 0.4, randf_range(-0.4, 0.4))
		d.linear_velocity = Vector3(randf_range(-4, 4), randf_range(4, 9), randf_range(-4, 4))
		d.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		get_tree().create_timer(1.3).timeout.connect(d.queue_free)

## ---- the pocket monsters ---------------------------------------------------------

## Build one monster as a model()-style pivot: bottom centre at the origin, longest side
## `size`, with an "aabb" meta so collision and squash checks treat it like any model.
## Everything is built facing +Z (towards the camera) at about one unit across, then fitted.
func _monster(spec: Dictionary) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = spec.name
	var m := Node3D.new()
	pivot.add_child(m)
	var role: String = spec.role
	match String(spec.name):
		"sparkit":
			_ball(m, role, Vector3(0, 1, 0), Vector3(1.0, 0.95, 0.9))
			for sx in [-1.0, 1.0]:
				_cone(m, role, Vector3(sx * 0.5, 1.95, 0), 0.24, 0.95, Vector3(0, 0, -sx * 0.35))
				_ball(m, "bg", Vector3(sx * 0.66, 2.35, 0), Vector3.ONE * 0.12)
				_ball(m, role, Vector3(sx * 0.45, 0.12, 0.35), Vector3(0.28, 0.16, 0.36))
			_stick(m, Vector3(0, 1.9, 0), 0.5)
			_ball(m, "prize", Vector3(0, 2.25, 0), Vector3.ONE * 0.17, 1.6)
			_ball(m, "accent", Vector3(0, 0.75, -0.9), Vector3.ONE * 0.3)
			_face(m, 1.05, 0.85)
		"blubbo":
			_ball(m, role, Vector3(0, 0.85, 0), Vector3(1.1, 0.85, 1.0))
			_ball(m, "ink", Vector3(0, 0.7, 0.55), Vector3(0.65, 0.55, 0.5), 0.2)
			var fin := _cone(m, "player", Vector3(0, 1.75, -0.1), 0.45, 0.8, Vector3(-0.3, 0, 0))
			fin.scale = Vector3(0.3, 1, 1)
			_ring(m, "player", Vector3(0, 0.7, -1.05), 0.28)
			_face(m, 1.0, 0.95)
		"embear":
			_ball(m, role, Vector3(0, 1, 0))
			for sx in [-1.0, 1.0]:
				_ball(m, role, Vector3(sx * 0.62, 1.78, 0), Vector3.ONE * 0.32)
				_ball(m, "ink", Vector3(sx * 0.62, 1.8, 0.12), Vector3.ONE * 0.16, 0.2)
				_ball(m, role, Vector3(sx * 0.45, 0.12, 0.4), Vector3(0.3, 0.16, 0.38))
			_ball(m, "ink", Vector3(0, 0.8, 0.85), Vector3(0.38, 0.28, 0.25), 0.2)
			_ball(m, "bg", Vector3(0, 0.9, 1.06), Vector3.ONE * 0.09)
			_stick(m, Vector3(0, 0.8, -0.95), 0.6, Vector3(-0.7, 0, 0))
			_cone(m, "warn", Vector3(0, 1.35, -1.3), 0.22, 0.6, Vector3.ZERO, 1.8)
			_face(m, 1.15, 0.9)
		"leafpup":
			_ball(m, role, Vector3(0, 0.9, 0), Vector3(1.1, 0.9, 1.1))
			for sx in [-1.0, 1.0]:
				var ear := _ball(m, "friend", Vector3(sx * 1.0, 1.0, 0.1), Vector3(0.22, 0.55, 0.38))
				ear.rotation.z = sx * 0.4
			_stick(m, Vector3(0, 1.75, 0), 0.35)
			var leaf := _ball(m, "prize", Vector3(0.3, 2.05, 0), Vector3(0.45, 0.07, 0.25), 0.8)
			leaf.rotation.z = 0.5
			_ball(m, "bg", Vector3(0, 0.82, 1.08), Vector3.ONE * 0.1)
			_face(m, 1.05, 0.95)
		"spikoon":
			_ball(m, role, Vector3(0, 1, 0))
			for i in 9:
				var a := TAU * float(i) / 9.0
				var dir := Vector3(cos(a), 0.55 + 0.35 * sin(a * 2.0), sin(a)).normalized()
				if dir.z > 0.55:
					continue   # keep the face clear
				var sp := _cone(m, "accent", Vector3(0, 1, 0) + dir * 1.15, 0.24, 0.65, Vector3.ZERO, 0.8)
				sp.quaternion = Quaternion(Vector3.UP, dir)   # point the cone's tip outwards
			_face(m, 1.0, 0.9)
		"owlbit":
			_ball(m, role, Vector3(0, 1.05, 0), Vector3(0.95, 1.1, 0.9))
			for sx in [-1.0, 1.0]:
				_cone(m, role, Vector3(sx * 0.5, 2.05, 0), 0.2, 0.5, Vector3(0, 0, -sx * 0.5))
				var wing := _ball(m, "accent", Vector3(sx * 0.95, 1.0, -0.1), Vector3(0.2, 0.6, 0.5))
				wing.rotation.z = sx * 0.3
			_ball(m, "ink", Vector3(0, 0.75, 0.6), Vector3(0.55, 0.6, 0.35), 0.2)
			_cone(m, "warn", Vector3(0, 1.0, 0.95), 0.12, 0.3, Vector3(PI * 0.5, 0, 0))
			_face(m, 1.3, 0.85, false, 1.3)
		"snoozle":
			_ball(m, role, Vector3(0, 0.75, 0), Vector3(1.45, 0.75, 1.2))
			_ball(m, "ink", Vector3(0, 0.6, 0.7), Vector3(1.0, 0.5, 0.55), 0.2)
			for sx in [-1.0, 1.0]:
				_ball(m, role, Vector3(sx * 0.75, 1.35, -0.1), Vector3(0.28, 0.3, 0.22))
			_face(m, 1.0, 1.15, true)
		_:  # cloudy
			for o in [Vector3(0, 1.0, 0), Vector3(-0.7, 0.8, 0), Vector3(0.7, 0.8, 0), Vector3(-0.35, 1.45, -0.1),
					Vector3(0.4, 1.4, -0.1), Vector3(0, 0.5, 0)]:
				_ball(m, role, o, Vector3.ONE * 0.62, 0.25)
			for sx in [-1.0, 1.0]:
				var w := _ball(m, "accent", Vector3(sx * 1.25, 1.2, -0.2), Vector3(0.18, 0.38, 0.5), 0.8)
				w.rotation.z = sx * 0.6
			_face(m, 1.05, 0.62)
	fit(m, float(spec.size))
	pivot.set_meta("aabb", fitted_aabb(m))
	return pivot

func _ball(parent: Node3D, role: String, at: Vector3, scl := Vector3.ONE, glow := 0.35) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	sm.material = mat(role, glow)
	return _part(parent, sm, at, scl)

func _cone(parent: Node3D, role: String, at: Vector3, r: float, h: float, rot := Vector3.ZERO,
		glow := 0.35) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.material = mat(role, glow)
	var mi := _part(parent, cm, at)
	mi.rotation = rot
	return mi

func _stick(parent: Node3D, at: Vector3, h: float, rot := Vector3.ZERO) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.05
	cm.height = h
	cm.radial_segments = 6
	cm.material = mat("bg", 0.0)
	var mi := _part(parent, cm, at + Vector3(0, h * 0.5, 0))
	mi.rotation = rot
	return mi

func _ring(parent: Node3D, role: String, at: Vector3, r: float) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.6
	tm.outer_radius = r
	tm.rings = 12
	tm.ring_segments = 8
	tm.material = mat(role, 0.35)
	var mi := _part(parent, tm, at)
	mi.rotation = Vector3(0, 0, PI * 0.5)
	return mi

func _part(parent: Node3D, mesh: Mesh, at: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.scale = scl
	parent.add_child(mi)
	return mi

## Big shiny eyes and a little smile on the front of a body centred at height `y` with
## front surface `z` out. `sleepy` draws closed eyes instead.
func _face(parent: Node3D, y: float, z: float, sleepy := false, eye := 1.0) -> void:
	for sx in [-1.0, 1.0]:
		var at := Vector3(sx * 0.36, y + 0.12, z)
		if sleepy:
			_ball(parent, "bg", at, Vector3(0.24, 0.05, 0.08), 0.0)
			continue
		_ball(parent, "ink", at, Vector3.ONE * 0.22 * eye, 0.3)
		_ball(parent, "bg", at + Vector3(0, -0.02, 0.12 * eye), Vector3.ONE * 0.13 * eye, 0.0)
		_ball(parent, "ink", at + Vector3(0.05, 0.06, 0.22 * eye), Vector3.ONE * 0.045 * eye, 1.2)
	_ball(parent, "bg", Vector3(0, y - 0.22, z - 0.02), Vector3(0.14, 0.06, 0.08), 0.0)

## ---- walkers ---------------------------------------------------------------------

## One walker, or on group levels a little knot of two or three walking together.
func _spawn_group() -> void:
	var lead := _spawn_walker()
	if randf() >= float(_lv().get("groups", 0.0)):
		return
	var goal: Vector3 = lead.get_meta("goal")
	var dir := (goal - lead.position).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	for i in randi_range(1, 2):
		var off := side * (0.7 if i == 1 else -0.7) - dir * randf_range(0.0, 0.6)
		var w := _spawn_walker(false, lead.position + off, goal + off)
		w.set_meta("speed", lead.get_meta("speed"))
		w.set_meta("phase", lead.get_meta("phase"))

func _spawn_walker(mid_way: bool = false, at := Vector3.INF, to := Vector3.INF) -> Actor3D:
	var w := Actor3D.new()
	world.add_child(w)
	w.set_character(PEOPLE[randi() % PEOPLE.size()], WALKER_H)
	# a halo marks someone you must NOT squash; they are allowed across
	var friend := randf() < float(_lv().get("friends", 0.0))
	w.set_meta("friend", friend)
	if friend:
		var halo := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.28
		tm.outer_radius = 0.4
		tm.material = mat("friend", 1.4)
		halo.mesh = tm
		halo.position = Vector3(0, WALKER_H + 0.35, 0)
		w.add_child(halo)

	# in from one edge, out through the opposite one
	var r := world_area.grow(-0.6)
	var from: Vector3
	var goal: Vector3
	match randi() % 4:
		0:
			from = Vector3(randf_range(r.position.x, r.end.x), 0, r.position.y)
			goal = Vector3(randf_range(r.position.x, r.end.x), 0, r.end.y)
		1:
			from = Vector3(randf_range(r.position.x, r.end.x), 0, r.end.y)
			goal = Vector3(randf_range(r.position.x, r.end.x), 0, r.position.y)
		2:
			from = Vector3(r.position.x, 0, randf_range(r.position.y, r.end.y))
			goal = Vector3(r.end.x, 0, randf_range(r.position.y, r.end.y))
		_:
			from = Vector3(r.end.x, 0, randf_range(r.position.y, r.end.y))
			goal = Vector3(r.position.x, 0, randf_range(r.position.y, r.end.y))
	if at.is_finite():
		from = clamp_to_area(at, 0.3)
		goal = clamp_to_area(to, 0.3)
	if mid_way:
		from = from.lerp(goal, randf_range(0.2, 0.7))
	var speed := randf_range(WALK_MIN, WALK_MAX) * float(_lv().get("speed", 1.0))
	w.set_meta("goal", goal)
	w.set_meta("speed", speed)
	w.set_meta("phase", randf() * TAU)
	w.position = from
	w.face(goal - from)
	w.play("Walk", true, speed / 1.7)
	_walkers.append(w)
	track3d(w, "x" if friend else "*")
	Probe.event("walker_spawn", {"friend": friend})
	return w

func _walk(delta: float) -> void:
	for w: Actor3D in _walkers.duplicate():
		var goal: Vector3 = w.get_meta("goal")
		var to := goal - w.position
		to.y = 0.0
		var step: float = w.get_meta("speed") * delta
		if to.length() <= step:
			_escape(w)
			continue
		var phase: float = w.get_meta("phase") + delta * 0.9
		w.set_meta("phase", phase)
		var side := Vector3(-to.z, 0, to.x).normalized() * sin(phase) * 0.35
		var dir := (to.normalized() + side * 0.4).normalized()
		w.position += dir * step
		w.face(dir)

func _escape(w: Actor3D) -> void:
	_walkers.erase(w)
	var at := w.position
	w.queue_free()
	if w.get_meta("friend"):
		Probe.event("friend_home")
		Juice.text(self, to_screen(at + Vector3(0, 2.0, 0)), "safe!", Palette.col("friend"))
		return
	Probe.event("escaped")
	Juice.text(self, to_screen(at + Vector3(0, 2.0, 0)), "escaped!", Palette.col("hazard"))
	shake3d(3.0)
	lose_life()

func _squash(w: Actor3D, body: RigidBody3D) -> void:
	_walkers.erase(w)
	if w.get_meta("friend"):
		_squash_friend(w)
		return
	var kills: int = body.get_meta("kills") + 1
	body.set_meta("kills", kills)
	var pts := 10 * kills
	add_score(pts)
	Probe.event("squash", {"combo": kills})
	_on_squash(kills)
	var msg := "+%d" % pts + ("  x%d!" % kills if kills > 1 else "")
	Juice.text(self, to_screen(w.position + Vector3(0, 2.2, 0)), msg,
		Palette.col("warn" if kills > 1 else "ink"))
	Audio.play("impact_punch" if kills == 1 else "explode")
	if kills > 1:
		Probe.event("combo")
	hit3d(2.5 + kills)
	_spawn_debris(w.position + Vector3(0, 0.8, 0), "prize", 7)
	# fall over, lie there a moment, sink away
	if not w.play("Death", false, 1.6):
		w.scale = Vector3(1.4, 0.06, 1.4)
	var tw := w.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(w, "position:y", -2.2, 0.8)
	tw.tween_callback(w.queue_free)

## ---- per frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	_cooldown -= delta
	_overlay.queue_redraw()
	if _phase != "play":
		_hover.position = _cursor.position + Vector3(0, HOVER_Y + sin(_t * 2.2) * 0.25, 0)
		_hover.rotation.y = _t * 0.35
		# the crowd holds still between levels -- nobody escapes while you read a banner
		_phase_left -= delta
		if _phase_left <= 0.0:
			_next_phase()
		return
	_lt += delta
	_tick_goal(delta)
	if _phase != "play":
		return

	var d := PInput.dir()
	if d != Vector2.ZERO:
		_cursor.position = clamp_to_area(_cursor.position + Vector3(d.x, 0, d.y) * CURSOR_SPEED * delta, 0.8)
	if PInput.just_pressed("action_a"):
		_drop()

	_hover.position = _cursor.position + Vector3(0, HOVER_Y + sin(_t * 2.2) * 0.25, 0)
	_hover.rotation.y = _t * 0.35   # slow idle spin; it falls at whatever angle it has
	var breath := sin(_t * 5.0) * 0.05
	_hover.scale = Vector3(1.0 + breath, 1.0 - breath, 1.0 + breath)   # it is alive up there
	_shadow.position = _cursor.position + Vector3(0, 0.03, 0)
	_shadow.rotation.y = _hover.rotation.y

	_walk(delta)

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		var gap: float = _lv().spawn
		_spawn_t = lerpf(gap, gap * 0.75, clampf(_lt / SPAWN_RAMP, 0.0, 1.0))
		if _walkers.size() < MAX_WALKERS:
			_spawn_group()

func _input(e: InputEvent) -> void:
	if finished or _phase == "fail" or _phase == "crown":
		return
	if e is InputEventMouseMotion:
		_aim_at(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if Flow.pointer_over_hud():
			return
		_aim_at(e.position)
		_drop()

func _aim_at(screen: Vector2) -> void:
	var g := ground_point(screen)
	if g.is_finite():
		_cursor.position = clamp_to_area(Vector3(g.x, 0, g.z), 0.8)

## ---- levels ------------------------------------------------------------------------

func _lv() -> Dictionary:
	return LEVELS[clampi(_level - 1, 0, LEVELS.size() - 1)]

func _is_last() -> bool:
	return _level == LEVELS.size()

func _begin_level(n: int) -> void:
	_level = n
	# "play again" after a game over restarts from here, not from wherever the run began
	Flow.current_config["level"] = n
	_progress = 0
	_lt = 0.0
	var lv := _lv()
	_drops_left = int(lv.get("drops", 0))
	_time_left = float(lv.get("time", 0))
	_hover.visible = true
	_shadow.visible = true
	set_lives(START_LIVES)
	# a fresh square: last level's crowd and wreckage would only muddy the new goal
	for w in _walkers:
		if is_instance_valid(w):
			w.queue_free()
	_walkers.clear()
	for b in _things:
		if is_instance_valid(b):
			b.queue_free()
	_things.clear()
	for i in 4:
		_spawn_walker(true)
	_spawn_t = 1.0
	_phase = "intro"
	_phase_left = INTRO_TIME
	Audio.play("voice_final_round" if _is_last() else "voice_level")
	if _is_last():
		shake3d(5.0)
	Probe.event("level_start", {"level": n, "goal": _goal_text()})

func _next_phase() -> void:
	match _phase:
		"intro":
			_phase = "play"
			Audio.play("voice_go")
		"clear":
			if _is_last():
				_crown()
			else:
				_begin_level(_level + 1)
		"fail":
			lose()
		"crown":
			win()

## "squash 6 with 10 drops in 40 seconds" -- the whole goal in one line.
func _goal_text() -> String:
	var lv := _lv()
	var need: int = lv.need
	var t := ""
	match String(lv.goal):
		"squash": t = "squash %d" % need
		"combo": t = "%d double squashes" % need
		"streak": t = "%d hits in a row, no misses" % need
		"survive": t = "hold out %d seconds" % need
	if lv.get("drops", 0) > 0:
		t += " with %d drops" % lv.drops
	if lv.get("time", 0) > 0:
		t += " in %d seconds" % lv.time
	return t

## Per-frame goal bookkeeping: the clock, the survive timer, running out of drops.
func _tick_goal(delta: float) -> void:
	var lv := _lv()
	if lv.goal == "survive":
		_progress = mini(int(_lt), int(lv.need))
		if _progress >= int(lv.need):
			_level_clear()
			return
	if lv.get("time", 0) > 0:
		var before := _time_left
		_time_left -= delta
		if before > 10.0 and _time_left <= 10.0:
			Audio.play("voice_hurry_up")
		if _time_left <= 0.0:
			_time_left = 0.0
			_fail("TIME'S UP")
			return
	# out of drops: wait for the last one to land and finish squashing before judging
	if lv.get("drops", 0) > 0 and _drops_left <= 0:
		for b in _things:
			if is_instance_valid(b) and not b.get_meta("resolved"):
				return
		_fail("OUT OF DROPS")

func _on_squash(kills: int) -> void:
	var lv := _lv()
	match String(lv.goal):
		"squash":
			_progress += 1
		"combo":
			if kills == 2:
				_progress += 1
				Juice.text(self, Vector2(300, 90), "COMBO!", Palette.col("warn"))
	_progress = mini(_progress, int(lv.need))
	Probe.event("goal_progress", {"level": _level, "progress": _progress})
	if _progress >= int(lv.need) and _phase == "play":
		_level_clear()

## A drop has landed and had its chance: on streak levels a miss resets the count.
func _resolve(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.get_meta("resolved"):
		return
	body.set_meta("resolved", true)
	if _phase != "play" or _lv().goal != "streak":
		return
	if int(body.get_meta("kills")) > 0:
		_progress += 1
		Probe.event("goal_progress", {"level": _level, "progress": _progress})
		if _progress >= int(_lv().need):
			_level_clear()
	else:
		if _progress > 0:
			Juice.text(self, Vector2(300, 90), "missed -- streak lost", Palette.col("hazard"))
		_progress = 0
		Probe.event("streak_lost")

func _squash_friend(w: Actor3D) -> void:
	Probe.event("friend_squashed")
	Juice.text(self, to_screen(w.position + Vector3(0, 2.2, 0)), "not them!", Palette.col("hazard"))
	Audio.play("voice_wrong")
	_spawn_debris(w.position + Vector3(0, 0.8, 0), "friend", 7)
	if not w.play("Death", false, 1.6):
		w.scale = Vector3(1.4, 0.06, 1.4)
	var tw := w.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(w, "position:y", -2.2, 0.8)
	tw.tween_callback(w.queue_free)
	# a thing still tumbling after the level is won does not get to cost you a life
	if _phase != "play":
		return
	if _lv().goal == "streak":
		_progress = 0
	lose_life()

func _fail(msg: String) -> void:
	if _phase != "play":
		return
	_phase = "fail"
	_phase_left = FAIL_TIME
	_fail_msg = msg
	Audio.play("voice_time_over" if msg == "TIME'S UP" else "voice_mission_failed")
	shake3d(4.0)
	Probe.event("level_failed", {"level": _level, "why": msg})

func _level_clear() -> void:
	if _phase != "play":
		return
	_phase = "clear"
	_phase_left = CLEAR_TIME if not _is_last() else 1.4
	add_score(50 * _level)
	Audio.play("voice_congratulations" if _is_last() else "voice_objective_achieved")
	Audio.play("impact_bell")
	shake3d(3.0)
	Probe.event("level_clear", {"level": _level, "score": score, "time": snappedf(_lt, 0.1)})
	if not _is_last():
		_award(_level, String(_lv().prize))

## The prize appears big in the middle, spins, then flies to its slot on the shelf.
func _award(level: int, prize: String) -> void:
	var b := Blob.new()
	b.role = "prize"
	b.radius = 7.0
	b.z_index = 20
	add_child(b)
	b.set_sprite(prize, 1.1)
	b.position = Vector2(320, 175)
	b.scale = Vector2.ZERO
	_shelf[level] = b
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(4.5, 4.5), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "rotation", TAU, 0.6).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.35)
	tw.tween_property(b, "position", _slot(level), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(b, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		Juice.pop(b, 1.6)
		Audio.play("pickup"))
	Probe.event("prize", {"level": level, "prize": prize})

func _slot(level: int) -> Vector2:
	return Vector2(SHELF_X, SHELF_Y + SHELF_STEP * (level - 1))

## Beat the last level: a big golden crown, with every prize won this run dancing round it.
func _crown() -> void:
	_phase = "crown"
	_phase_left = CROWN_TIME
	for w in _walkers:
		if is_instance_valid(w):
			w.queue_free()
	_walkers.clear()
	_hover.visible = false
	_shadow.visible = false
	var tw := create_tween()
	tw.tween_property(self, "_crown_size", 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("voice_you_win")
	Audio.music("jingle_3")
	shake3d(7.0)
	var won: Array = _shelf.values()
	for i in won.size():
		var b: Blob = won[i]
		var ang := TAU * float(i) / float(won.size())
		var t2 := b.create_tween()
		t2.tween_property(b, "position", Vector2(320, 160) + Vector2(cos(ang) * 150.0, sin(ang) * 85.0), 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.parallel().tween_property(b, "scale", Vector2(2.0, 2.0), 0.7)
	for i in 40:
		_confetti()
	Probe.event("final_prize", {"score": score})

func _confetti() -> void:
	var c := Blob.new()
	c.role = ["prize", "accent", "friend", "warn", "player"].pick_random()
	c.shape = ["diamond", "square", "circle"].pick_random()
	c.radius = randf_range(2.5, 4.5)
	c.z_index = 30
	add_child(c)
	c.position = Vector2(320, 160)
	var to := c.position + Vector2(randf_range(-300, 300), randf_range(-150, 190))
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", to, randf_range(0.8, 1.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", randf_range(-8.0, 8.0), 1.6)
	tw.tween_property(c, "modulate:a", 0.0, 1.0).set_delay(1.4)
	tw.chain().tween_callback(c.queue_free)

## ---- the 2D layer over the 3D view ---------------------------------------------------

func _draw_overlay() -> void:
	var o := _overlay
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")
	var lv := _lv()
	var last := _is_last()

	_draw_shelf()
	if _crown_size > 0.0:
		_draw_crown(Vector2(320, 160), 70.0 * _crown_size)
		_text(f, 320, 295, "ALL FIFTEEN!", 30, Palette.col("prize"))
		return

	match _phase:
		"intro":
			o.draw_rect(Rect2(0, 108, 640, 132), Color(0, 0, 0, 0.55))
			_text(f, 320, 152, "FINAL LEVEL" if last else "LEVEL %d" % _level, 38,
				Palette.col("hazard" if last else "accent"))
			_text(f, 320, 188, _goal_text(), 20, ink)
			var tip := ""
			if lv.get("friends", 0.0) > 0.0:
				tip = "don't squash anyone wearing a halo"
			elif lv.goal == "combo":
				tip = "land on two at once"
			elif lv.goal == "streak":
				tip = "every drop has to squash someone"
			elif lv.goal == "survive":
				tip = "don't let them across"
			elif _level == 1:
				tip = "tap where it should fall   ·   arrows aim, A drops"
			_text(f, 320, 218, tip, 12, Palette.col("prize"))
			return
		"clear":
			_text(f, 320, 95, "LEVEL %d CLEAR!" % _level, 32, Palette.col("prize"))
			return
		"fail":
			o.draw_rect(Rect2(0, 128, 640, 70), Color(0, 0, 0, 0.55))
			_text(f, 320, 175, _fail_msg, 34, Palette.col("hazard"))
			return

	# big clock up top on timed levels
	if lv.get("time", 0) > 0:
		var secs := ceili(_time_left)
		var role := "ink" if _time_left > 10.0 else "hazard"
		_text(f, 320, 34, "%d:%02d" % [secs / 60, secs % 60], 22, Palette.col(role))

	# bottom strip: level, goal, drops, progress
	o.draw_rect(Rect2(0, 334, 640, 26), Color(0, 0, 0, 0.45))
	var label := "%s %d/15:  %s" % ["FINAL" if last else "level", _level, _goal_text()]
	_text(f, 250, 352, label, 12, Palette.col("accent"))
	var need: int = lv.need
	var x0 := 470.0
	if lv.goal == "survive":
		_text(f, x0 + 40, 352, "%ds / %ds" % [_progress, need], 13, Palette.col("prize"))
	elif need <= 8:
		for i in need:
			var p := Vector2(x0 + i * 13, 347)
			if i < _progress:
				o.draw_circle(p, 4.5, Palette.col("prize"))
			else:
				o.draw_arc(p, 4.5, 0, TAU, 16, Palette.col("ink"), 1.5)
	else:
		_text(f, x0 + 40, 352, "%d / %d" % [_progress, need], 13, Palette.col("prize"))
	if lv.get("drops", 0) > 0:
		var role := "warn" if _drops_left > 3 else "hazard"
		_text(f, 320, 326, "drops left: %d" % _drops_left, 13, Palette.col(role))

## Fifteen slots down the right edge; empty ones are outlines, the last is the crown's.
func _draw_shelf() -> void:
	for i in LEVELS.size():
		var level := i + 1
		var p := _slot(level)
		var last := level == LEVELS.size()
		var won := _shelf.has(level) or (last and _crown_size > 0.0)
		if not won:
			var c := Palette.col("hazard" if last else "ink")
			_overlay.draw_arc(p, 6.5, 0, TAU, 18, Color(c.r, c.g, c.b, 0.45), 1.2)
		if last:
			_draw_crown(p, 5.5, won)

func _draw_crown(at: Vector2, r: float, lit: bool = true) -> void:
	var o := _overlay
	var gold := Palette.col("prize")
	if not lit:
		gold = Color(gold.r, gold.g, gold.b, 0.3)
	if lit and r > 20.0:
		o.draw_circle(at, r * 1.6, Color(gold.r, gold.g, gold.b, 0.12))
		o.draw_circle(at, r * 1.2, Color(gold.r, gold.g, gold.b, 0.16))
	o.draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r, r * 0.6), at + Vector2(-r, -r * 0.5), at + Vector2(-r * 0.5, 0),
		at + Vector2(0, -r * 0.8), at + Vector2(r * 0.5, 0), at + Vector2(r, -r * 0.5),
		at + Vector2(r, r * 0.6)]), gold)
	if not lit:
		return
	o.draw_rect(Rect2(at + Vector2(-r, r * 0.35), Vector2(r * 2.0, r * 0.25)), Palette.col("warn"))
	var gem := r * 0.13
	o.draw_circle(at + Vector2(-r, -r * 0.5), gem, Palette.col("hazard"))
	o.draw_circle(at + Vector2(0, -r * 0.8), gem * 1.3, Palette.col("friend"))
	o.draw_circle(at + Vector2(r, -r * 0.5), gem, Palette.col("accent"))
	o.draw_circle(at + Vector2(0, r * 0.15), gem * 1.2, Palette.col("player"))

func _text(f: Font, cx: float, y: float, msg: String, size: int, col: Color) -> void:
	_overlay.draw_string(f, Vector2(cx - 220, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 440, size, col)
