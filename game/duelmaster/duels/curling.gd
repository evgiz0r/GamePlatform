extends "res://game/duelmaster/duels/duel.gd"
## curling -- hold to charge (the meter rises and falls), release to slide the puck to the
## line. Off the end of the lane is a miss.

const LANE_Y := 210.0
const START_X := 64.0
const END_X := 600.0
const FRICTION := 260.0
const VMAX := 620.0

var _target := 400.0
var _cycle := 1.4                 ## seconds for the meter to go up and back down
var _charging := false
var _charge_t := 0.0
var _power := 0.0
var _vel := 0.0
var _sliding := false
var _puck: Blob
var _line: Node2D

func _init() -> void:
	title = "CURLING"
	hint = "hold to charge, let go to slide to the line"
	tie = 3.0

func _build() -> void:
	limit = 7.0
	_target = rng.randf_range(300.0, 540.0)
	_cycle = rng.randf_range(1.1, 1.7)
	_line = Node2D.new()
	add_child(_line)
	_line.position = Vector2(_target, LANE_Y)
	Probe.track(_line, "*")
	_puck = Blob.new()
	_puck.role = role
	_puck.radius = 10.0
	add_child(_puck)
	_puck.position = Vector2(START_X, LANE_Y)
	Probe.track(_puck, "@")

func press() -> void:
	if over or _charging:
		return
	_charging = true
	_charge_t = 0.0
	Audio.play("select")

func release() -> void:
	if over or not _charging:
		return
	_charging = false
	over = true
	_sliding = true
	_vel = _power * VMAX
	Audio.play("impact_soft")

func step(delta: float) -> void:
	if _charging:
		_charge_t += delta
		var ph := fmod(_charge_t / _cycle, 1.0)
		_power = 1.0 - absf(ph * 2.0 - 1.0)
		_puck.position.x = START_X - _power * 14.0
		_puck.scale = Vector2(1.0 + _power * 0.25, 1.0 - _power * 0.2)
	if not _sliding:
		return
	_puck.scale = Vector2.ONE
	_puck.position.x += _vel * delta
	_vel = maxf(0.0, _vel - FRICTION * delta)
	if _puck.position.x > END_X + 10.0:
		_sliding = false
		Juice.shake(4.0)
		Audio.play("thud")
		report(MISS)
	elif _vel <= 0.0:
		_sliding = false
		Juice.pop(_puck, 1.6)
		Audio.play("impact_plate")
		report(absf(_puck.position.x - _target))

func describe(err: float) -> String:
	return "off the end" if err >= MISS and _puck.position.x > END_X else super(err)

func _draw() -> void:
	var lane := Rect2(START_X - 24, LANE_Y - 26, END_X - START_X + 24, 52)
	draw_rect(lane, Palette.col("bg_alt"))
	draw_line(Vector2(END_X, LANE_Y - 30), Vector2(END_X, LANE_Y + 30), Palette.col("hazard"), 3.0)
	var p := Palette.col("prize")
	draw_line(Vector2(_target, LANE_Y - 30), Vector2(_target, LANE_Y + 30), p, 3.0)
	draw_rect(Rect2(_target - 10, LANE_Y - 26, 20, 52), Color(p.r, p.g, p.b, 0.15))
	# the power meter
	var m := Rect2(START_X - 20, 120, 160, 10)
	draw_rect(m, Palette.col("bg_alt"))
	draw_rect(Rect2(m.position, Vector2(m.size.x * _power, m.size.y)), Palette.col(role))
	draw_rect(m, Palette.col("ink"), false, 1.0)
	if not over:
		time_bar()
