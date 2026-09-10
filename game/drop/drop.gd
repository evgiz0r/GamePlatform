extends GameMode3D
## drop -- a little neon town square at night, people crossing it, and something absurd
## hovering in the sky where you point: a taxi, a garbage truck, a fork, a spaceship. Tap
## and it falls as a real 3D rigid body; anyone under it is squashed and the next thing
## appears at once. People who make it across cost a life. See GAME.md.
##
## The kit's first 3D game and the reference for GameMode3D (shell/game_mode_3d.gd):
## model() for the things and the scenery, Actor3D for the walking people.

const HOVER_Y := 8.0                 ## how high the waiting thing floats (and falls from)
const GRAVITY_SCALE := 3.0           ## Earth gravity floats; this reads as a drop
const CURSOR_SPEED := 10.0           ## world units per second on the keys / stick
const DROP_COOLDOWN := 0.3
const WALK_MIN := 1.3                ## walker speed range, units per second
const WALK_MAX := 2.4
const SPAWN_START := 1.6             ## seconds between walkers at the start ...
const SPAWN_MIN := 0.75              ## ... and after SPAWN_RAMP seconds
const SPAWN_RAMP := 60.0
const MAX_WALKERS := 22
const WALKER_R := 0.35               ## a falling thing this close to a walker's centre squashes it
const WALKER_H := 1.8
const HIT_SPEED := 3.0               ## falling slower than this is just resting
const SETTLE := 2.5                  ## seconds a landed thing lies there before sinking away
const MAX_THINGS := 8
const START_LIVES := 3
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
## What can fall. `size` is the longest side in world units (a walker is 1.8 tall).
const THINGS := [
	{"model": "sedan", "size": 3.2, "mass": 6.0, "sfx": "impact_metal"},
	{"model": "taxi", "size": 3.2, "mass": 6.0, "sfx": "impact_metal"},
	{"model": "police", "size": 3.2, "mass": 6.0, "sfx": "impact_metal"},
	{"model": "suv", "size": 3.4, "mass": 7.0, "sfx": "impact_metal"},
	{"model": "van", "size": 3.5, "mass": 7.0, "sfx": "impact_metal"},
	{"model": "ambulance", "size": 3.8, "mass": 8.0, "sfx": "impact_metal"},
	{"model": "delivery", "size": 4.0, "mass": 9.0, "sfx": "impact_metal"},
	{"model": "truck", "size": 4.2, "mass": 9.0, "sfx": "impact_metal"},
	{"model": "firetruck", "size": 4.4, "mass": 10.0, "sfx": "impact_metal"},
	{"model": "garbage-truck", "size": 4.4, "mass": 10.0, "sfx": "impact_metal"},
	{"model": "utensil-fork", "size": 4.5, "mass": 2.0, "sfx": "impact_plate"},
	{"model": "utensil-knife", "size": 4.5, "mass": 2.0, "sfx": "impact_plate"},
	{"model": "utensil-spoon", "size": 4.5, "mass": 2.0, "sfx": "impact_plate"},
	{"model": "plate", "size": 3.2, "mass": 3.0, "sfx": "impact_glass"},
	{"model": "frying-pan", "size": 3.6, "mass": 4.0, "sfx": "impact_metal"},
	{"model": "craft_speederA", "size": 4.0, "mass": 7.0, "sfx": "explode"},
	{"model": "craft_racer", "size": 4.0, "mass": 7.0, "sfx": "explode"},
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
var _t := 0.0
var _sfx_was := 0.8

## Set at construction: the shell sizes its backdrop off play_area before _ready runs.
func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-12, -7, 24, 14)

func _ready() -> void:
	title = "drop"
	super()

func start(_config: Dictionary) -> void:
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
	for i in 4:
		_spawn_walker(true)
	Probe.event("start")

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
	var hint := Label.new()
	hint.text = "tap where it should fall   ·   arrows aim, A drops"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Palette.col("ink"))
	hint.modulate.a = 0.7
	hint.position = Vector2(10, 338)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

## ---- the things that fall ------------------------------------------------------------

func _next_thing() -> void:
	_thing = THINGS[randi() % THINGS.size()]
	for c in _hover.get_children():
		c.queue_free()
	var pivot := model(_thing["model"], _thing["size"])
	_hover.add_child(pivot)
	var b: AABB = pivot.get_meta("aabb")
	(_shadow.mesh as BoxMesh).size = Vector3(b.size.x, 0.04, b.size.z)

func _drop() -> void:
	if _cooldown > 0.0 or finished:
		return
	_cooldown = DROP_COOLDOWN
	var body := RigidBody3D.new()
	body.gravity_scale = GRAVITY_SCALE
	body.mass = _thing["mass"]
	body.contact_monitor = true
	body.max_contacts_reported = 4
	var pivot := model(_thing["model"], _thing["size"])
	body.add_child(pivot)
	add_box_collision(body, pivot, 0.9)
	body.set_meta("aabb", pivot.get_meta("aabb"))
	body.set_meta("sfx", _thing["sfx"])
	body.set_meta("kills", 0)
	body.set_meta("landed", false)
	body.set_meta("rest", 0.0)
	body.set_meta("sink", -1.0)
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
	Probe.event("drop", {"thing": _thing["model"]})
	_next_thing()

func _on_land(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.get_meta("landed"):
		return
	body.set_meta("landed", true)
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

## ---- walkers ---------------------------------------------------------------------

func _spawn_walker(mid_way: bool = false) -> void:
	var w := Actor3D.new()
	world.add_child(w)
	w.set_character(PEOPLE[randi() % PEOPLE.size()], WALKER_H)

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
	if mid_way:
		from = from.lerp(goal, randf_range(0.2, 0.7))
	var speed := randf_range(WALK_MIN, WALK_MAX)
	w.set_meta("goal", goal)
	w.set_meta("speed", speed)
	w.set_meta("phase", randf() * TAU)
	w.position = from
	w.face(goal - from)
	w.play("Walk", true, speed / 1.7)
	_walkers.append(w)
	track3d(w, "*")
	Probe.event("walker_spawn")

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
	Probe.event("escaped")
	Juice.text(self, to_screen(at + Vector3(0, 2.0, 0)), "escaped!", Palette.col("hazard"))
	shake3d(3.0)
	lose_life()

func _squash(w: Actor3D, body: RigidBody3D) -> void:
	_walkers.erase(w)
	var kills: int = body.get_meta("kills") + 1
	body.set_meta("kills", kills)
	var pts := 10 * kills
	add_score(pts)
	Probe.event("squash", {"combo": kills})
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

	var d := PInput.dir()
	if d != Vector2.ZERO:
		_cursor.position = clamp_to_area(_cursor.position + Vector3(d.x, 0, d.y) * CURSOR_SPEED * delta, 0.8)
	if PInput.just_pressed("action_a"):
		_drop()

	_hover.position = _cursor.position + Vector3(0, HOVER_Y + sin(_t * 2.2) * 0.25, 0)
	_hover.rotation.y = _t * 0.35   # slow idle spin; it falls at whatever angle it has
	_shadow.position = _cursor.position + Vector3(0, 0.03, 0)
	_shadow.rotation.y = _hover.rotation.y

	_walk(delta)

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = lerpf(SPAWN_START, SPAWN_MIN, clampf(_t / SPAWN_RAMP, 0.0, 1.0))
		if _walkers.size() < MAX_WALKERS:
			_spawn_walker()

func _input(e: InputEvent) -> void:
	if finished:
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
