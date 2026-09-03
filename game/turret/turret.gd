extends GameMode
## turret -- a gun on the ground that fires by itself once a second. Things fall out of
## the sky. All you control is which way it is pointing. See game/turret/GAME.md.
##
## Hold anywhere and the barrel swings towards your finger; left and right work too.

const BASE := Vector2(320, 334)
const GROUND_Y := 330.0
const MAX_ANGLE := 1.32          ## radians either side of straight up (~76 degrees)
const TURN_SPEED := 2.1          ## radians per second
const SIGHT_RANGE := 210.0

const FIRE_EVERY := 1.0
## Fast on purpose. At 430 the flight took long enough that a falling enemy dropped
## further than the hit radius, so every shot needed leading -- brutal when you only get
## one a second. This is a gun, not a mortar.
const SHELL_SPEED := 900.0
const SHELL_R := 3.5
const HIT_R := 20.0

const SPAWN_START := 2.6
const SPAWN_MIN := 0.9
const FALL_START := 28.0
const FALL_MAX := 88.0
const SFX_VOLUME := 0.28

const FOES := ["bat", "spider", "ghost", "skull", "goblin", "skeleton", "crab", "snail"]

var sight: Blob                  ## where the barrel is pointing -- this is what you steer
var _angle := 0.0
var _foes: Array = []
var _shells: Array = []
var _puffs: Array = []
var _fire_t := 0.0
var _spawn_t := 0.0
var _elapsed := 0.0
var _held := false
var _point := Vector2.ZERO
var _sfx_was := 0.8

func _ready() -> void:
	title = "turret"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = SFX_VOLUME

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	set_lives(3)

	# The sight is the thing the player actually moves, so it is what gets tracked as the
	# player. A bot steering "@" towards a target is then steering the barrel, which is
	# exactly the control a person has.
	sight = Blob.new()
	sight.role = "player"
	sight.radius = 4.0
	sight.shape = "diamond"
	add_child(sight)
	Probe.track(sight, "@")
	_update_sight()

	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- aiming ----------------------------------------------------------------

func _update_sight() -> void:
	sight.position = BASE + Vector2(sin(_angle), -cos(_angle)) * SIGHT_RANGE

func _aim(delta: float) -> void:
	var turn := PInput.dir().x
	if turn == 0.0 and _held:
		# swing towards the finger rather than snapping to it, so it still feels like
		# turning a gun and not dragging a cursor
		# clamp first, then compare against the clamped value -- comparing against the raw
		# one means a finger below the barrel's limit never satisfies the deadzone and the
		# gun jitters against the stop
		var want := clampf(atan2(_point.x - BASE.x, BASE.y - _point.y), -MAX_ANGLE, MAX_ANGLE)
		turn = 0.0 if absf(want - _angle) < 0.03 else signf(want - _angle)
	_angle = clampf(_angle + turn * TURN_SPEED * delta, -MAX_ANGLE, MAX_ANGLE)
	_update_sight()

## ---- play ------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_elapsed += delta
	queue_redraw()
	_aim(delta)

	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = FIRE_EVERY
		_fire()

	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = maxf(SPAWN_MIN, SPAWN_START - _elapsed * 0.018)
		_spawn_foe()

	_move_shells(delta)
	_move_foes(delta)
	_move_puffs(delta)

	if _elapsed >= 8.0 and int(_elapsed) % 15 == 0 and _elapsed - floorf(_elapsed) < delta:
		Probe.capture("t=%ds" % int(_elapsed))

func _fire() -> void:
	var s := Blob.new()
	s.role = "warn"
	s.radius = SHELL_R
	add_child(s)
	s.position = BASE + Vector2(sin(_angle), -cos(_angle)) * 22.0
	s.set_meta("vel", Vector2(sin(_angle), -cos(_angle)) * SHELL_SPEED)
	_shells.append(s)
	Probe.track(s, "!")
	Probe.event("fire")
	Audio.play("thud", 0.2, -6.0)
	Juice.shake(1.8)

func _spawn_foe() -> void:
	var f := Blob.new()
	f.role = "hazard"
	f.radius = 9.0
	add_child(f)
	f.set_sprite(FOES[randi() % FOES.size()], 1.6)
	f.position = Vector2(randf_range(34.0, play_area.size.x - 34.0), -18.0)
	f.set_meta("fall", minf(FALL_START + _elapsed * 0.85, FALL_MAX) * randf_range(0.85, 1.2))
	f.set_meta("sway", randf() * TAU)
	_foes.append(f)
	Probe.track(f, "x")
	Probe.event("foe_spawn")

func _move_shells(delta: float) -> void:
	var keep: Array = []
	for s in _shells:
		if not is_instance_valid(s):
			continue
		s.position += s.get_meta("vel") * delta
		var hit := _foe_at(s.position)
		if hit != null:
			_kill(hit)
			s.queue_free()
			continue
		if not in_play_area(s.position, 30.0):
			s.queue_free()
			continue
		keep.append(s)
	_shells = keep

func _foe_at(p: Vector2) -> Blob:
	for f in _foes:
		if is_instance_valid(f) and p.distance_to(f.position) < HIT_R:
			return f
	return null

func _move_foes(delta: float) -> void:
	var keep: Array = []
	for f in _foes:
		if not is_instance_valid(f):
			continue
		var ph: float = f.get_meta("sway") + delta * 1.6
		f.set_meta("sway", ph)
		f.position.y += float(f.get_meta("fall")) * delta
		f.position.x += sin(ph) * 14.0 * delta
		if f.position.y >= GROUND_Y:
			Probe.event("foe_landed")
			_puff(Vector2(f.position.x, GROUND_Y), "hazard", 10)
			f.queue_free()
			Audio.play("explode", 0.15, -3.0)
			Juice.hit(8.0)
			lose_life()
			continue
		keep.append(f)
	_foes = keep

func _kill(f: Blob) -> void:
	add_score(10)
	Probe.event("foe_killed")
	_puff(f.position, "warn", 8)
	Audio.play("impact_light", 0.25, -4.0)
	Juice.shake(2.5)
	f.queue_free()

## ---- debris ----------------------------------------------------------------

func _puff(at: Vector2, role: String, n: int) -> void:
	for i in n:
		var d := Blob.new()
		d.role = role
		d.radius = randf_range(1.5, 3.0)
		add_child(d)
		d.position = at
		d.set_meta("vel", Vector2(randf_range(-90, 90), randf_range(-120, -20)))
		_puffs.append(d)

func _move_puffs(delta: float) -> void:
	var keep: Array = []
	for d in _puffs:
		if not is_instance_valid(d):
			continue
		var v: Vector2 = d.get_meta("vel")
		v.y += 260.0 * delta
		d.set_meta("vel", v)
		d.position += v * delta
		d.modulate.a = maxf(0.0, d.modulate.a - delta * 1.3)
		if d.modulate.a <= 0.03 or d.position.y > play_area.size.y:
			d.queue_free()
			continue
		keep.append(d)
	_puffs = keep

func _input(event: InputEvent) -> void:
	if finished or Flow.pointer_over_hud():
		_held = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_held = mb.pressed
			_point = get_global_mouse_position()
	elif event is InputEventMouseMotion and _held:
		_point = get_global_mouse_position()

## ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	var ink := Palette.col("ink")
	var accent := Palette.col("accent")
	var player := Palette.col("player")

	draw_line(Vector2(0, GROUND_Y), Vector2(play_area.size.x, GROUND_Y),
		Color(ink.r, ink.g, ink.b, 0.35), 2.0)

	# where it is pointing, faint, all the way out -- without this you are guessing
	var dir := Vector2(sin(_angle), -cos(_angle))
	draw_line(BASE + dir * 34.0, BASE + dir * SIGHT_RANGE,
		Color(accent.r, accent.g, accent.b, 0.28), 1.5)

	draw_line(BASE, BASE + dir * 34.0, player, 8.0)
	draw_circle(BASE + Vector2(0, -4), 11.0, player)
	draw_rect(Rect2(BASE.x - 20, BASE.y - 4, 40, 12), player)
	for i in 5:
		draw_circle(Vector2(BASE.x - 15 + i * 7.5, BASE.y + 9), 3.0, player)

	var f: Font = ThemeDB.fallback_font
	draw_string(f, Vector2(120, 22), "hold to aim", HORIZONTAL_ALIGNMENT_CENTER, 400, 13,
		Color(accent.r, accent.g, accent.b, 0.75))
