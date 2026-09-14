extends GameMode3D
## bowling -- ten frames of ten-pin bowling on one neon lane, against nobody but your own
## best. Swipe up to roll: the angle of the swipe aims, its speed is the ball's speed, and
## a swipe that bends makes the ball hook the same way. Real rigid bodies: the ball rolls,
## the pins tumble, scatter and take each other out. Keys and pad slide the ball along the
## foul line and A rolls it straight, which is also how the bots play. See GAME.md.

const LANE_W := 2.6                  ## a real lane is 1.05 m wide; one unit is ~0.4 m
const LANE_LEN := 18.0               ## foul line at z=0, the pit starts at z=-LANE_LEN
const APPROACH := 3.0                ## lane surface behind the foul line where the ball waits
const GUTTER_W := 0.6
const GUTTER_DEPTH := 0.3
const BALL_R := 0.27
const BALL_MASS := 7.0
const BALL_START_Z := 1.2
const PIN_H := 0.95
const PIN_R := 0.13                  ## collision cylinder; the drawn pin bulges past it
const PIN_MASS := 1.6
const PIN_SPACING := 0.76            ## between neighbouring pins, like the real 12 inches
const HEAD_PIN_Z := -15.6
const PIT_Z := -LANE_LEN - 1.2       ## anything past here (or under the floor) is gone
const SPEED_MIN := 9.0               ## slowest and fastest a swipe can send the ball
const SPEED_MAX := 19.0
const KEY_SPEED := 15.0              ## the A button (and the bots) roll at this
const AIM_MAX_DEG := 7.0             ## how far off straight the ball can go (6 degrees is a gutter)
const AIM_SCALE := 0.3               ## swipe angle -> aim angle; a swipe has to be fairly straight
const HOOK_MAX := 2.6                ## sideways acceleration of a fully bent swipe, units/s^2
const SLIDE_SPEED := 2.4             ## foul-line slide on the keys, units per second
const SWIPE_MIN_PX := 28.0           ## shorter than this is a tap, not a roll
const SWIPE_HOOK_PX := 70.0          ## a swipe needs this much length before its bend counts
const GRAVITY_SCALE := 2.5           ## Earth gravity at this scale looks like the moon
const SETTLE := 0.7                  ## everything quiet this long -> count the pins
const ROLL_TIMEOUT := 6.0            ## a wobbling pin does not get to hold the game up
const RESET_DELAY := 1.0             ## seconds to admire the wreckage before the pinsetter
const FRAMES := 10
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const PHYSICS_HZ := 120              ## a fast ball through thin pins needs it; restored on exit

var _ball: RigidBody3D
var _guide: MeshInstance3D           ## the aim line on the lane while you swipe
var _pins: Array = []                ## RigidBody3D, meta: spot (int)
var _spots: Array = []               ## Vector3, the ten pin positions
var _standing: Array = []            ## spot indices still up (set at the start of each roll)
var _rolls: Array = []               ## pins knocked per roll, the whole game
var _frame := 0                      ## 0..9
var _roll_in_frame := 0
var _state := "aim"                  ## aim | rolling | reset | over
var _roll_t := 0.0
var _quiet_t := 0.0
var _hook := 0.0                     ## sideways acceleration on the ball this roll
var _aim_x := 0.0
var _gutter := false
var _sfx_t := 0.0                    ## throttle for pin clatter
var _cam_pos := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _drag := false
var _drag_pts: Array = []            ## [Vector2 screen, float seconds]
var _strip: Label
var _hint: Label
var _sfx_was := 0.8
var _hz_was := 60

## Set at construction: the shell sizes its backdrop off play_area before _ready runs.
func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-(LANE_W * 0.5 + GUTTER_W), -LANE_LEN - 3.2, LANE_W + GUTTER_W * 2.0, APPROACH + LANE_LEN + 3.2)

func _ready() -> void:
	title = "bowling"
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	_hz_was = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = PHYSICS_HZ
	set_lives(0)   # nothing can hurt you here; the game is ten frames long, that is all
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.rotation_degrees = Vector3(-58, 24, 0)
	_cam_pos = _rest_cam_pos()
	_cam_target = _rest_cam_target()
	look_from(_cam_pos, _cam_target)
	_build_lane()
	_build_ball()
	_build_spots()
	_set_pins(range(10))
	_build_ui()
	_refresh_strip()
	Probe.event("start")
	Probe.event("frame", {"n": 1})

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	Engine.physics_ticks_per_second = _hz_was

## ---- the alley ---------------------------------------------------------------------

func _box(size: Vector3, at: Vector3, m: Material, solid: bool = false) -> Node3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	if not solid:
		mi.position = at
		world.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.add_child(mi)
	body.position = at
	world.add_child(body)
	return body

func _build_lane() -> void:
	var length := LANE_LEN + APPROACH
	var mid_z := (APPROACH - LANE_LEN) * 0.5
	# the lane: a polished slab from the approach to the pit
	_box(Vector3(LANE_W, 0.4, length), Vector3(0, -0.2, mid_z), mat("bg_alt", 0.18, 0.22), true)
	# gutters either side, a step down, with a glowing rail outside each
	for side: float in [-1.0, 1.0]:
		var gx := side * (LANE_W * 0.5 + GUTTER_W * 0.5)
		_box(Vector3(GUTTER_W, 0.2, length), Vector3(gx, -GUTTER_DEPTH - 0.1, mid_z), mat("bg", 0.0, 0.8), true)
		var rx := side * (LANE_W * 0.5 + GUTTER_W + 0.08)
		_box(Vector3(0.16, 0.5, length), Vector3(rx, 0.0, mid_z), mat("accent", 0.85), true)
		# the neighbouring lanes, dim, so this is an alley and not a plank in space
		_box(Vector3(LANE_W, 0.3, length), Vector3(side * (LANE_W + GUTTER_W * 2.0 + 0.4), -0.25, mid_z), mat("bg_alt", 0.05, 0.4))
	# foul line and the seven aiming arrows
	_box(Vector3(LANE_W, 0.012, 0.06), Vector3(0, 0.006, 0.0), mat("hazard", 0.9))
	for i in range(-3, 4):
		var ax := i * (LANE_W / 7.0)
		var az := -4.6 - (3 - absi(i)) * 0.45
		_box(Vector3(0.09, 0.012, 0.42), Vector3(ax, 0.006, az), mat("accent", 0.9))
	# the pit: a floor well below the deck so knocked pins tumble out of sight
	_box(Vector3(LANE_W + GUTTER_W * 2.0 + 0.4, 0.2, 3.0), Vector3(0, -1.6, -LANE_LEN - 1.5), mat("bg", 0.0), true)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.2, 2.2, 3.0), Vector3(side * 2.2, -0.6, -LANE_LEN - 1.5), mat("bg_alt", 0.05, 0.4), true)
	# back wall and the masking unit above the pins: a glowing bar and a row of bulbs
	_box(Vector3(LANE_W + GUTTER_W * 2.0 + 0.4, 4.0, 0.3), Vector3(0, 0.4, -LANE_LEN - 3.0), mat("bg_alt", 0.12), true)
	_box(Vector3(LANE_W + GUTTER_W * 2.0 + 0.4, 0.9, 0.25), Vector3(0, 2.45, -LANE_LEN - 2.4), mat("bg_alt", 0.3))
	_box(Vector3(LANE_W + GUTTER_W * 2.0 + 0.4, 0.06, 0.06), Vector3(0, 2.0, -LANE_LEN - 2.28), mat("prize", 0.9))
	_box(Vector3(LANE_W + GUTTER_W * 2.0 + 0.4, 0.06, 0.06), Vector3(0, 2.9, -LANE_LEN - 2.28), mat("prize", 0.9))
	for i in 9:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		sm.material = mat("accent" if i % 2 == 0 else "warn", 1.0)
		bulb.mesh = sm
		bulb.position = Vector3(-2.0 + i * 0.5, 2.45, -LANE_LEN - 2.25)
		world.add_child(bulb)
	# a wide dark floor under everything so the world has a ground
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(60, 60)
	gm.material = mat("bg", 0.0, 1.0)
	ground.mesh = gm
	ground.position = Vector3(0, -1.8, -8)
	world.add_child(ground)

func _build_ball() -> void:
	_ball = RigidBody3D.new()
	_ball.mass = BALL_MASS
	_ball.gravity_scale = GRAVITY_SCALE
	_ball.continuous_cd = true
	_ball.linear_damp = 0.04
	_ball.angular_damp = 0.05
	_ball.contact_monitor = true
	_ball.max_contacts_reported = 4
	_ball.can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	pm.bounce = 0.05
	_ball.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = BALL_R
	cs.shape = ss
	_ball.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.material = mat("player", 0.45, 0.12)
	mi.mesh = sm
	_ball.add_child(mi)
	# three finger holes: the only way a rolling sphere shows that it is rolling
	for off in [Vector3(-0.09, 0.0, 0.06), Vector3(0.09, 0.0, 0.06), Vector3(0.0, 0.0, -0.1)]:
		var hole := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.05
		hm.height = 0.1
		hm.material = mat("bg", 0.0, 0.9)
		hole.mesh = hm
		hole.position = (Vector3(0, BALL_R, 0) + off).normalized() * BALL_R
		_ball.add_child(hole)
	_ball.freeze = true
	world.add_child(_ball)
	_ball.global_position = Vector3(_aim_x, BALL_R, BALL_START_Z)
	_ball.body_entered.connect(_on_ball_hit)
	track3d(_ball, "@")

	_guide = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.05, 0.01, 7.0)
	gm.material = mat("player", 0.7)
	_guide.mesh = gm
	_guide.visible = false
	world.add_child(_guide)

func _build_spots() -> void:
	# row 0 is the head pin, then 2, 3 and 4 pins back, 12 inches apart (the real layout)
	_spots.clear()
	var row_d := PIN_SPACING * sqrt(0.75)
	for row in 4:
		for k in row + 1:
			var x := (k - row * 0.5) * PIN_SPACING
			_spots.append(Vector3(x, 0, HEAD_PIN_Z - row * row_d))

func _build_ui() -> void:
	var back := ColorRect.new()
	var c := Palette.col("bg")
	c.a = 0.62
	back.color = c
	back.position = Vector2(0, 308)
	back.size = Vector2(640, 52)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_strip = Label.new()
	_strip.add_theme_font_size_override("font_size", 13)
	_strip.add_theme_color_override("font_color", Palette.col("ink"))
	_strip.position = Vector2(0, 314)
	_strip.size = Vector2(640, 20)
	_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_hint = Label.new()
	_hint.text = "swipe up to roll  ·  bend the swipe to hook  ·  arrows slide, A rolls"
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Palette.col("ink"))
	_hint.modulate.a = 0.6
	_hint.position = Vector2(0, 338)
	_hint.size = Vector2(640, 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

## ---- pins ----------------------------------------------------------------------------

func _make_pin(spot: int) -> RigidBody3D:
	var p := RigidBody3D.new()
	p.mass = PIN_MASS
	p.gravity_scale = GRAVITY_SCALE
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, 0.36, 0)   # a real pin is bottom-heavy
	p.contact_monitor = true
	p.max_contacts_reported = 2
	p.angular_damp = 0.4
	p.linear_damp = 0.15
	var pm := PhysicsMaterial.new()
	pm.friction = 0.5
	pm.bounce = 0.12
	p.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = PIN_R
	cyl.height = PIN_H
	cs.shape = cyl
	cs.position = Vector3(0, PIN_H * 0.5, 0)
	p.add_child(cs)
	# the drawn pin: base, belly, neck, head, and the classic band round the neck
	var body_m := mat("ink", 0.22, 0.35)
	var base := CylinderMesh.new()
	base.top_radius = 0.14
	base.bottom_radius = 0.10
	base.height = 0.25
	_part(p, base, Vector3(0, 0.125, 0), body_m)
	var belly := SphereMesh.new()
	belly.radius = 0.16
	belly.height = 0.42
	_part(p, belly, Vector3(0, 0.36, 0), body_m)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.07
	neck.bottom_radius = 0.115
	neck.height = 0.3
	_part(p, neck, Vector3(0, 0.66, 0), body_m)
	var head := SphereMesh.new()
	head.radius = 0.095
	head.height = 0.19
	_part(p, head, Vector3(0, 0.86, 0), body_m)
	var band := CylinderMesh.new()
	band.top_radius = 0.1
	band.bottom_radius = 0.105
	band.height = 0.05
	_part(p, band, Vector3(0, 0.6, 0), mat("hazard", 0.6))
	p.set_meta("spot", spot)
	p.set_meta("t", 0.0)
	world.add_child(p)
	p.global_position = _spots[spot]
	p.body_entered.connect(_on_pin_hit)
	track3d(p, "*")
	return p

func _part(parent: Node3D, mesh: Mesh, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	mesh.material = m
	mi.mesh = mesh
	mi.position = at
	parent.add_child(mi)

## Fresh pins on the given spots; everything that was there before is gone.
func _set_pins(spots: Array) -> void:
	for p in _pins:
		if is_instance_valid(p):
			p.queue_free()
	_pins.clear()
	for s in spots:
		_pins.append(_make_pin(s))
	_standing = spots.duplicate()

func _pin_up(p: RigidBody3D) -> bool:
	if not is_instance_valid(p):
		return false
	var pos := p.global_position
	if pos.y < -0.15 or pos.z < -LANE_LEN or absf(pos.x) > LANE_W * 0.5 + 0.1:
		return false
	return p.global_transform.basis.y.y > 0.72   # leaning more than ~44 degrees is down

func _pins_up_now() -> Array:
	var up: Array = []
	for p: RigidBody3D in _pins:
		if _pin_up(p):
			up.append(p.get_meta("spot"))
	return up

## ---- the roll ---------------------------------------------------------------------------

func _roll(aim_deg: float, speed: float, hook: float) -> void:
	if _state != "aim" or finished:
		return
	_state = "rolling"
	_roll_t = 0.0
	_quiet_t = 0.0
	_gutter = false
	_hook = hook
	_guide.visible = false
	var a := deg_to_rad(clampf(aim_deg, -AIM_MAX_DEG, AIM_MAX_DEG))
	var dir := Vector3(sin(a), 0, -cos(a))
	speed = clampf(speed, SPEED_MIN, SPEED_MAX)
	_ball.freeze = false
	_ball.linear_velocity = dir * speed
	_ball.angular_velocity = Vector3.UP.cross(dir) * (speed / BALL_R)   # rolling, not sliding
	Audio.play("step_wood", 0.1)
	Probe.event("roll", {"aim": snappedf(aim_deg, 0.1), "speed": snappedf(speed, 0.1), "hook": snappedf(hook, 0.1)})

func _physics_process(delta: float) -> void:
	if _state != "rolling":
		return
	_roll_t += delta
	var bp := _ball.global_position
	# the hook: sideways pull while the ball is still on the lane, ahead of the pins
	if absf(_hook) > 0.01 and bp.y < BALL_R + 0.05 and bp.z > HEAD_PIN_Z + 1.0 and absf(bp.x) < LANE_W * 0.5:
		_ball.apply_central_force(Vector3(_hook * BALL_MASS, 0, 0))
	if not _gutter and bp.y < BALL_R - 0.12 and bp.z > HEAD_PIN_Z + 1.0 and bp.z < 0.0:
		_gutter = true
		Audio.play("thud")
		Juice.text(self, to_screen(bp + Vector3(0, 0.6, 0)), "gutter", Palette.col("hazard"))
		Probe.event("gutter")
	# done when the ball is gone (or stuck) and the pins have stopped moving
	var ball_done: bool = bp.z < PIT_Z or bp.y < -1.0 or (_roll_t > 2.0 and _ball.linear_velocity.length() < 0.4)
	var pins_quiet := true
	for p: RigidBody3D in _pins:
		if is_instance_valid(p) and p.global_position.y > -1.0 and p.global_position.z > PIT_Z:
			if p.linear_velocity.length() > 0.5 or p.angular_velocity.length() > 1.2:
				pins_quiet = false
				break
	_quiet_t = _quiet_t + delta if (ball_done and pins_quiet) else 0.0
	if _quiet_t >= SETTLE or _roll_t >= ROLL_TIMEOUT:
		_tally()

func _on_ball_hit(other: Node) -> void:
	if _state != "rolling" or not (other is RigidBody3D):
		return
	if _sfx_t <= 0.0:
		_sfx_t = 0.08
		Audio.play("impact_wood", 0.2)
	hit3d(2.5)

func _on_pin_hit(other: Node) -> void:
	if _state != "rolling" or not (other is RigidBody3D) or _sfx_t > 0.0:
		return
	_sfx_t = 0.06
	Audio.play("impact_wood", 0.25, -4.0)
	shake3d(1.2)

## ---- counting and the pinsetter -----------------------------------------------------------

func _tally() -> void:
	_state = "reset"
	var up := _pins_up_now()
	var knocked := _standing.size() - up.size()
	_rolls.append(knocked)
	var first_of_frame := _roll_in_frame == 0 or (_frame == FRAMES - 1 and _standing.size() == 10)
	var strike := knocked == 10 and first_of_frame
	var spare := knocked > 0 and up.is_empty() and not strike
	var deck := to_screen(Vector3(0, 1.4, HEAD_PIN_Z - 0.6))
	if strike:
		Probe.event("strike")
		Juice.text(self, deck, "STRIKE!", Palette.col("prize"))
		Audio.play("voice_congratulations")
		hit3d(6.0)
		_sparks(Vector3(0, 0.8, HEAD_PIN_Z - 0.6), 14)
	elif spare:
		Probe.event("spare")
		Juice.text(self, deck, "SPARE!", Palette.col("warn"))
		Audio.play("voice_correct")
		hit3d(4.0)
		_sparks(Vector3(0, 0.8, HEAD_PIN_Z - 0.6), 8)
	elif knocked > 0:
		Juice.text(self, deck, "+%d" % knocked, Palette.col("ink"))
	elif not _gutter:
		Juice.text(self, deck, "miss", Palette.col("hazard"))
	Probe.event("pins_down", {"n": knocked, "left": up.size()})
	add_score(_total() - score)

	# what the pinsetter does next
	var next_spots: Array = up
	var game_over := false
	if _frame < FRAMES - 1:
		if strike or _roll_in_frame == 1:
			_frame += 1
			_roll_in_frame = 0
			next_spots = range(10)
		else:
			_roll_in_frame = 1
	else:
		# tenth frame: a strike or spare earns extra balls on a full rack
		if _roll_in_frame == 0:
			_roll_in_frame = 1
			if strike:
				next_spots = range(10)
		elif _roll_in_frame == 1:
			var first: int = _rolls[_rolls.size() - 2]
			if first == 10 or first + knocked == 10:
				_roll_in_frame = 2
				if up.is_empty():
					next_spots = range(10)
			else:
				game_over = true
		else:
			game_over = true
	_refresh_strip()

	# fallen pins get swept away, the rest are re-spotted after a beat
	for p: RigidBody3D in _pins:
		if is_instance_valid(p) and not up.has(p.get_meta("spot")):
			var tw := p.create_tween()
			tw.tween_interval(RESET_DELAY * 0.5)
			tw.tween_property(p, "scale", Vector3(0.01, 0.01, 0.01), 0.3)
	get_tree().create_timer(RESET_DELAY).timeout.connect(_reset.bind(next_spots, game_over))

func _reset(spots: Array, game_over: bool) -> void:
	if finished:
		return
	if game_over:
		_state = "over"
		_refresh_strip()
		Probe.event("game_end", {"score": score})
		_set_pins([])
		get_tree().create_timer(0.8).timeout.connect(win)
		return
	_set_pins(spots)
	_ball.freeze = true
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_transform = Transform3D(Basis(), Vector3(_aim_x, BALL_R, BALL_START_Z))
	_state = "aim"
	if _roll_in_frame == 0 or spots.size() == 10:
		Probe.event("frame", {"n": _frame + 1})
		if _frame == FRAMES - 1 and _roll_in_frame == 0:
			Audio.play("voice_final_round")

## Standard ten-pin scoring over everything rolled so far; a strike or spare whose bonus
## balls have not been rolled yet counts its ten for now and grows as they come in.
func _total() -> int:
	var t := 0
	var i := 0
	for f in FRAMES:
		if i >= _rolls.size():
			break
		if f == FRAMES - 1:
			for k in range(i, _rolls.size()):
				t += _rolls[k]
			break
		if _rolls[i] == 10:
			t += 10 + _at(i + 1) + _at(i + 2)
			i += 1
		elif i + 1 < _rolls.size() and _rolls[i] + _rolls[i + 1] == 10:
			t += 10 + _at(i + 2)
			i += 2
		else:
			t += _rolls[i] + _at(i + 1)
			i += 2
	return t

func _at(k: int) -> int:
	return _rolls[k] if k < _rolls.size() else 0

## The frame strip: one mark per ball, the way an alley's overhead screen writes them.
func _refresh_strip() -> void:
	var marks: Array = []
	var i := 0
	for f in FRAMES:
		var s := ""
		if f < FRAMES - 1:
			if i < _rolls.size():
				if _rolls[i] == 10:
					s = "X"
					i += 1
				else:
					s = _mark(_rolls[i])
					if i + 1 < _rolls.size():
						s += "/" if _rolls[i] + _rolls[i + 1] == 10 else _mark(_rolls[i + 1])
					i += 2
		else:
			var prev := 0
			var first := true
			for k in range(i, _rolls.size()):
				var r: int = _rolls[k]
				if r == 10 and (first or prev == 10 or prev < 0):
					s += "X"
					prev = -1
				elif not first and prev >= 0 and prev + r == 10:
					s += "/"
					prev = -1
				else:
					s += _mark(r)
					prev = r
				first = false
		if f == _frame and not finished and _state != "over":
			s = "[" + s + "_" + "]" if s.length() < 2 or f == FRAMES - 1 else "[" + s + "]"
		elif s == "":
			s = "·"
		marks.append(s)
	_strip.text = "   ".join(marks)

func _mark(n: int) -> String:
	return "-" if n == 0 else str(n)

func _sparks(at: Vector3, n: int) -> void:
	for i in n:
		var d := RigidBody3D.new()
		d.mass = 0.1
		d.gravity_scale = GRAVITY_SCALE
		var s := randf_range(0.06, 0.14)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * s
		bm.material = mat("prize" if i % 2 == 0 else "accent", 1.0)
		mi.mesh = bm
		d.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * s
		cs.shape = bs
		d.add_child(cs)
		world.add_child(d)
		d.global_position = at + Vector3(randf_range(-0.8, 0.8), 0.2, randf_range(-0.5, 0.5))
		d.linear_velocity = Vector3(randf_range(-3, 3), randf_range(4, 8), randf_range(-3, 1))
		d.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		get_tree().create_timer(1.2).timeout.connect(d.queue_free)

## ---- per frame -----------------------------------------------------------------------------

func _rest_cam_pos() -> Vector3:
	return Vector3(_aim_x * 0.4, 3.1, BALL_START_Z + 5.2)

func _rest_cam_target() -> Vector3:
	return Vector3(_aim_x * 0.2, 0.3, -9.0)

func _process(delta: float) -> void:
	if finished:
		return
	_sfx_t -= delta

	if _state == "aim":
		var d := PInput.dir()
		if d.x != 0.0:
			_aim_x = clampf(_aim_x + d.x * SLIDE_SPEED * delta, -(LANE_W * 0.5 - BALL_R - 0.05), LANE_W * 0.5 - BALL_R - 0.05)
			_ball.global_transform = Transform3D(Basis(), Vector3(_aim_x, BALL_R, BALL_START_Z))
		if PInput.just_pressed("action_a"):
			_roll(0.0, KEY_SPEED, 0.0)
		_guide.visible = _drag
		_guide.position = Vector3(_aim_x, 0.012, BALL_START_Z - 3.6)
		if _drag:
			var aim: float = _stroke()[0]
			_guide.rotation.y = -deg_to_rad(aim)
			_guide.position = Vector3(_aim_x, 0.012, BALL_START_Z) + Vector3(sin(deg_to_rad(aim)), 0, -cos(deg_to_rad(aim))) * 3.6

	# the camera rides down the lane behind the ball and glides home for the next roll
	var want_pos := _rest_cam_pos()
	var want_target := _rest_cam_target()
	if _state == "rolling" or _state == "reset":
		var bp := _ball.global_position
		var bz := clampf(bp.z, HEAD_PIN_Z + 1.5, BALL_START_Z)
		var bx := clampf(bp.x, -1.2, 1.2)
		want_pos = Vector3(bx * 0.5, 2.9, bz + 5.0)
		want_target = Vector3(bx * 0.3, 0.3, bz - 9.0)
		if _state == "reset":
			want_pos = Vector3(0, 2.6, HEAD_PIN_Z + 6.0)
			want_target = Vector3(0, 0.5, HEAD_PIN_Z - 0.8)
	var k := 1.0 - exp(-delta * (5.0 if _state == "rolling" else 3.0))
	_cam_pos = _cam_pos.lerp(want_pos, k)
	_cam_target = _cam_target.lerp(want_target, k)
	look_from(_cam_pos, _cam_target)

## ---- the swipe ---------------------------------------------------------------------------

func _input(e: InputEvent) -> void:
	if finished:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if Flow.pointer_over_hud() or _state != "aim":
				_drag = false
				return
			_drag = true
			_drag_pts = [[e.position, _now()]]
		elif _drag:
			_drag = false
			_drag_pts.append([e.position, _now()])
			_release()
	elif e is InputEventMouseMotion and _drag:
		_drag_pts.append([e.position, _now()])
		if _drag_pts.size() > 96:
			_drag_pts.pop_front()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## [aim degrees, speed, hook] read off the drag so far. The angle is the direction of the
## first half of the stroke and the hook is how much the second half bent away from it:
## the ball starts where the swipe started going and bends the way the swipe bent.
func _stroke() -> Array:
	if _drag_pts.size() < 2:
		return [0.0, 0.0, 0.0]
	var a: Vector2 = _drag_pts[0][0]
	var b: Vector2 = _drag_pts[_drag_pts.size() - 1][0]
	var whole := b - a
	var dt: float = maxf(0.03, _drag_pts[_drag_pts.size() - 1][1] - _drag_pts[0][1])
	var aim := rad_to_deg(atan2(whole.x, -whole.y)) * AIM_SCALE
	var hook := 0.0
	if whole.length() >= SWIPE_HOOK_PX:
		var m: Vector2 = _drag_pts[_drag_pts.size() >> 1][0]
		var first := m - a
		var second := b - m
		if first.length() > 8.0 and second.length() > 8.0:
			var a1 := rad_to_deg(atan2(first.x, -first.y))
			var a2 := rad_to_deg(atan2(second.x, -second.y))
			aim = a1 * AIM_SCALE
			hook = clampf((a2 - a1) / 30.0, -1.0, 1.0) * HOOK_MAX
	var px_per_s := whole.length() / dt
	var speed: float = lerpf(SPEED_MIN, SPEED_MAX, clampf((px_per_s - 250.0) / 1500.0, 0.0, 1.0))
	return [aim, speed, hook]

func _release() -> void:
	if _drag_pts.size() < 2 or _state != "aim":
		return
	var a: Vector2 = _drag_pts[0][0]
	var b: Vector2 = _drag_pts[_drag_pts.size() - 1][0]
	if a.y - b.y < SWIPE_MIN_PX:
		return   # a tap or a sideways fiddle, not a roll
	var st := _stroke()
	var aim: float = st[0]
	var speed: float = st[1]
	var hook: float = st[2]
	_roll(aim, speed, hook)
