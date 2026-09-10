extends GameMode3D
## drop -- a neon plaza at night, walkers crossing it, and a Tetris piece hovering in the
## sky where you point. Tap and it falls as a real 3D rigid body; anyone under it is
## squashed and the next piece appears at once. Walkers who make it across cost a life.
## See GAME.md.
##
## The kit's first 3D game: everything 3D comes from GameMode3D (shell/game_mode_3d.gd);
## this file is the game -- walkers, pieces, hits, score.

const HOVER_Y := 8.0                 ## how high the waiting piece floats (and falls from)
const CELL := 1.2                    ## one Tetris cell in world units
const GRAVITY_SCALE := 3.0           ## Earth gravity floats; this reads as a drop
const CURSOR_SPEED := 10.0           ## world units per second on the keys / stick
const DROP_COOLDOWN := 0.3
const WALK_MIN := 1.3                ## walker speed range, units per second
const WALK_MAX := 2.4
const SPAWN_START := 1.6             ## seconds between walkers at the start ...
const SPAWN_MIN := 0.75              ## ... and after SPAWN_RAMP seconds
const SPAWN_RAMP := 60.0
const MAX_WALKERS := 22
const WALKER_R := 0.42               ## how close a falling cell must pass to squash
const HIT_H := 1.7                   ## a cell above this height cannot hit anyone
const HIT_SPEED := 3.0               ## a cell falling slower than this is just resting
const SETTLE := 2.5                  ## seconds a landed piece lies there before sinking away
const MAX_PIECES := 8
const START_LIVES := 3
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const ROT_BTN := Rect2(546, 312, 84, 38)   ## screen px, bottom right, thumb sized
const SHAPES := {
	"I": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"O": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"T": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"L": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)],
	"J": [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 2)],
	"S": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"Z": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
}
const SHAPE_ROLES := {"I": "player", "O": "warn", "T": "accent", "L": "friend",
	"J": "player", "S": "hazard", "Z": "hazard"}

var _cursor: Node3D                  ## where the next piece will land; the bots' "@"
var _hover: Node3D                   ## the piece waiting in the sky
var _shadow: Node3D                  ## its footprint on the ground
var _shape := "T"
var _yaw := 0.0
var _cooldown := 0.0
var _walkers: Array = []             ## Node3D, meta: goal, speed, phase
var _pieces: Array = []              ## RigidBody3D, meta: kills, landed, rest, sink
var _spawn_t := 1.2
var _t := 0.0
var _sfx_was := 0.8
var _hint: Label = null

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
	look_from(Vector3(0, 19, 15.5), Vector3(0, 0, -0.5))
	_build_plaza()
	_build_cursor()
	_next_piece()
	_build_ui()
	for i in 4:
		_spawn_walker(true)
	Probe.event("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the world -------------------------------------------------------------------

func _build_plaza() -> void:
	# something to land on: an infinite floor at Y=0
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	world.add_child(floor_body)

	# the plaza slab, slightly lit so it separates from the sky
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

func _build_cursor() -> void:
	_cursor = Node3D.new()
	_cursor.position = Vector3.ZERO
	world.add_child(_cursor)
	track3d(_cursor, "@")
	_hover = Node3D.new()
	world.add_child(_hover)
	_shadow = Node3D.new()
	world.add_child(_shadow)

func _build_ui() -> void:
	# rotate control: drawn, not a Button -- games read taps in _input() before the GUI, so
	# a real Button would drop a piece underneath itself. The hit test is in _input().
	var rot := ColorRect.new()
	rot.position = ROT_BTN.position
	rot.size = ROT_BTN.size
	rot.color = Color(Palette.col("accent"), 0.22)
	rot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rot)
	var rl := Label.new()
	rl.text = "rotate"
	rl.add_theme_font_size_override("font_size", 13)
	rl.add_theme_color_override("font_color", Palette.col("ink"))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rl.set_anchors_preset(Control.PRESET_FULL_RECT)
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rot.add_child(rl)

	_hint = Label.new()
	_hint.text = "tap where it should fall   ·   arrows aim, A drops, B rotates"
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Palette.col("ink"))
	_hint.modulate.a = 0.7
	_hint.position = Vector2(10, 338)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

## ---- pieces ----------------------------------------------------------------------

## Cells of a shape as local offsets, centred on the piece's centroid so it spins on itself.
func _cell_offsets(shape: String) -> Array:
	var cells: Array = SHAPES[shape]
	var c := Vector2.ZERO
	for v in cells:
		c += Vector2(v)
	c /= float(cells.size())
	var out: Array = []
	for v in cells:
		out.append(Vector3((v.x - c.x) * CELL, 0.0, (v.y - c.y) * CELL))
	return out

func _build_cells(into: Node3D, shape: String, with_collision: bool, thin: bool) -> void:
	var m := mat(SHAPE_ROLES[shape], 0.15 if thin else 0.55)
	var s := CELL * 0.94
	for pos in _cell_offsets(shape):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, 0.05 if thin else s, s)
		bm.material = m
		mi.mesh = bm
		mi.position = pos
		into.add_child(mi)
		if with_collision:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(s, s, s)
			cs.shape = bs
			cs.position = pos
			into.add_child(cs)

func _next_piece() -> void:
	var names: Array = SHAPES.keys()
	_shape = names[randi() % names.size()]
	for c in _hover.get_children():
		c.queue_free()
	for c in _shadow.get_children():
		c.queue_free()
	_build_cells(_hover, _shape, false, false)
	_build_cells(_shadow, _shape, false, true)

func _rotate() -> void:
	_yaw += PI * 0.5
	Audio.play("click")

func _drop() -> void:
	if _cooldown > 0.0 or finished:
		return
	_cooldown = DROP_COOLDOWN
	var body := RigidBody3D.new()
	body.gravity_scale = GRAVITY_SCALE
	body.mass = 3.0
	body.contact_monitor = true
	body.max_contacts_reported = 4
	_build_cells(body, _shape, true, false)
	body.set_meta("kills", 0)
	body.set_meta("landed", false)
	body.set_meta("rest", 0.0)
	body.set_meta("sink", -1.0)
	world.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, _yaw), _cursor.position + Vector3(0, HOVER_Y, 0))
	body.angular_velocity = Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
	body.body_entered.connect(func(_other: Node) -> void: _on_land(body))
	_pieces.append(body)
	while _pieces.size() > MAX_PIECES:
		var old = _pieces.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	Audio.play("open")
	Probe.event("drop", {"shape": _shape})
	_next_piece()

func _on_land(body: RigidBody3D) -> void:
	if not is_instance_valid(body) or body.get_meta("landed"):
		return
	body.set_meta("landed", true)
	hit3d(3.5)
	Audio.play("thud")
	# body_entered runs inside the physics flush; spawn debris once it is over
	_spawn_debris.call_deferred(body.global_position, SHAPE_ROLES[_shape_of(body)], 5)

func _shape_of(body: RigidBody3D) -> String:
	for c in body.get_children():
		if c is MeshInstance3D:
			var role: String = c.mesh.material.get_meta("role")
			for s in SHAPE_ROLES:
				if SHAPE_ROLES[s] == role:
					return s
	return "T"

func _physics_process(delta: float) -> void:
	for body in _pieces:
		if not is_instance_valid(body):
			continue
		var sink: float = body.get_meta("sink")
		if sink >= 0.0:
			sink += delta
			body.set_meta("sink", sink)
			body.position.y -= 3.0 * delta
			if sink > 1.0:
				body.queue_free()
			continue
		# a fast-falling cell passing through a walker squashes it
		if body.linear_velocity.y < -HIT_SPEED:
			for c in body.get_children():
				if not (c is MeshInstance3D):
					continue
				var cp: Vector3 = c.global_position
				if cp.y > HIT_H + CELL * 0.5:
					continue
				for w: Node3D in _walkers.duplicate():
					var d := Vector2(cp.x - w.position.x, cp.z - w.position.z).length()
					if d < CELL * 0.5 + WALKER_R:
						_squash(w, body)
		# a landed piece that has stopped moving sinks away after a moment
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
	_pieces = _pieces.filter(func(b): return is_instance_valid(b))

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
	var w := Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.32
	cm.height = 1.2
	cm.material = mat("prize", 0.5)
	body.mesh = cm
	body.position = Vector3(0, 0.75, 0)
	body.name = "Body"
	w.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	sm.material = mat("ink", 0.3)
	head.mesh = sm
	head.position = Vector3(0, 1.5, 0)
	head.name = "Head"
	w.add_child(head)

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
	w.set_meta("goal", goal)
	w.set_meta("speed", randf_range(WALK_MIN, WALK_MAX))
	w.set_meta("phase", randf() * TAU)
	world.add_child(w)
	w.position = from
	_walkers.append(w)
	track3d(w, "*")
	Probe.event("walker_spawn")

func _walk(delta: float) -> void:
	for w: Node3D in _walkers.duplicate():
		var goal: Vector3 = w.get_meta("goal")
		var to := goal - w.position
		to.y = 0.0
		var step: float = w.get_meta("speed") * delta
		if to.length() <= step:
			_escape(w)
			continue
		var phase: float = w.get_meta("phase") + delta * 9.0
		w.set_meta("phase", phase)
		var side := Vector3(-to.z, 0, to.x).normalized() * sin(phase * 0.35) * 0.35
		w.position += (to.normalized() + side * 0.4).normalized() * step
		# a little bob and lean so they read as walking, not sliding
		var body := w.get_node("Body") as Node3D
		body.position.y = 0.75 + absf(sin(phase)) * 0.08
		w.rotation.z = sin(phase) * 0.06

func _escape(w: Node3D) -> void:
	_walkers.erase(w)
	var at := w.position
	w.queue_free()
	Probe.event("escaped")
	Juice.text(self, to_screen(at + Vector3(0, 1.6, 0)), "escaped!", Palette.col("hazard"))
	shake3d(3.0)
	lose_life()

func _squash(w: Node3D, body: RigidBody3D) -> void:
	_walkers.erase(w)
	var kills: int = body.get_meta("kills") + 1
	body.set_meta("kills", kills)
	var pts := 10 * kills
	add_score(pts)
	Probe.event("squash", {"combo": kills})
	var msg := "+%d" % pts + ("  x%d!" % kills if kills > 1 else "")
	Juice.text(self, to_screen(w.position + Vector3(0, 1.8, 0)), msg,
		Palette.col("warn" if kills > 1 else "ink"))
	Audio.play("impact_punch" if kills == 1 else "explode")
	if kills > 1:
		Probe.event("combo")
	hit3d(2.5 + kills)
	_spawn_debris(w.position + Vector3(0, 0.6, 0), "prize", 7)
	# flatten, then vanish
	var tw := w.create_tween()
	tw.tween_property(w, "scale", Vector3(1.5, 0.05, 1.5), 0.1)
	tw.tween_interval(0.6)
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
	if PInput.just_pressed("action_b"):
		_rotate()

	_hover.position = _cursor.position + Vector3(0, HOVER_Y + sin(_t * 2.2) * 0.25, 0)
	_hover.rotation.y = _yaw
	_shadow.position = _cursor.position + Vector3(0, 0.04, 0)
	_shadow.rotation.y = _yaw

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
		if ROT_BTN.has_point(e.position):
			_rotate()
			return
		_aim_at(e.position)
		_drop()

func _aim_at(screen: Vector2) -> void:
	var g := ground_point(screen)
	if g.is_finite():
		_cursor.position = clamp_to_area(Vector3(g.x, 0, g.z), 0.8)
