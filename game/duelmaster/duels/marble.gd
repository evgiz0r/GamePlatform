extends "res://game/duelmaster/duels/duel.gd"
## marble drop -- a dropper swings across the top, tap to let go. The marble keeps the
## dropper's sideways speed, so you have to lead it onto the bullseye.

const TOP := 88.0
const FLOOR := 300.0
const GRAVITY := 720.0
const CARRY := 0.45               ## how much of the dropper's speed the marble keeps

var _amp := 200.0
var _speed := 2.0
var _phase := 0.0
var _target := 320.0
var _dropper: Blob
var _marble: Blob
var _bull: Blob
var _falling := false
var _vel := Vector2.ZERO
var _land_x := -1.0

func _init() -> void:
	title = "MARBLE DROP"
	hint = "tap to drop -- it keeps moving sideways"
	tie = 2.0

func _build() -> void:
	limit = 7.0
	_amp = rng.randf_range(170.0, 250.0)
	_speed = rng.randf_range(1.7, 2.7)
	_phase = rng.randf() * TAU
	_target = rng.randf_range(150.0, 490.0)

	_bull = Blob.new()
	_bull.role = "prize"
	_bull.radius = 6.0
	_bull.shape = "diamond"
	add_child(_bull)
	_bull.position = Vector2(_target, FLOOR)
	Probe.track(_bull, "*")

	_dropper = Blob.new()
	_dropper.role = role
	_dropper.radius = 10.0
	_dropper.shape = "triangle"
	_dropper.rotation = PI
	add_child(_dropper)

	_marble = Blob.new()
	_marble.role = role
	_marble.radius = 7.0
	add_child(_marble)
	Probe.track(_marble, "@")
	_place()

func _dropper_x() -> float:
	return 320.0 + _amp * sin(_speed * t + _phase)

func _dropper_vx() -> float:
	return _amp * _speed * cos(_speed * t + _phase)

func _place() -> void:
	_dropper.position = Vector2(_dropper_x(), TOP - 14.0)
	if not _falling:
		_marble.position = Vector2(_dropper_x(), TOP)

func press() -> void:
	if over or _falling:
		return
	_falling = true
	over = true
	_vel = Vector2(_dropper_vx() * CARRY, 0.0)
	Audio.play("click")

func step(delta: float) -> void:
	_place()
	if not _falling or _land_x >= 0.0:
		return
	_vel.y += GRAVITY * delta
	_marble.position += _vel * delta
	_marble.position.x = clampf(_marble.position.x, 24.0, 616.0)
	if _marble.position.y >= FLOOR:
		_marble.position.y = FLOOR
		_land_x = _marble.position.x
		Juice.pop(_marble, 1.8)
		Juice.shake(3.0)
		Audio.play("impact_glass")
		report(absf(_land_x - _target))

func _draw() -> void:
	var ink := Palette.col("ink")
	draw_line(Vector2(20, FLOOR + 8), Vector2(620, FLOOR + 8), Palette.col("bg_alt"), 3.0)
	draw_line(Vector2(40, TOP - 26), Vector2(600, TOP - 26), Palette.col("bg_alt"), 2.0)
	var p := Palette.col("prize")
	# a bullseye seen side-on: nested bands, brightest in the middle
	for i in 4:
		var w := 120.0 - i * 32.0
		var c := Color(p.r, p.g, p.b, 0.15 + i * 0.22)
		draw_rect(Rect2(_target - w * 0.5, FLOOR + 4, w, 8.0), c)
	draw_line(Vector2(_target, FLOOR - 10), Vector2(_target, FLOOR + 16), p, 2.0)
	if _land_x >= 0.0:
		draw_line(Vector2(_land_x, FLOOR + 14), Vector2(_target, FLOOR + 14), ink, 1.0)
	if not over:
		time_bar()
