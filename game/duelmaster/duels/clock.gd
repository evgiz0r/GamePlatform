extends "res://game/duelmaster/duels/duel.gd"
## stop the clock -- stop the timer exactly on the target. The digits hide after a second.

const SHOW_FOR := 1.0

var _target := 3.0
var _stopped := -1.0
var _hand: Blob
var _goal: Node2D

func _init() -> void:
	title = "STOP THE CLOCK"
	hint = "tap at exactly the target time"
	tie = 0.02

func _build() -> void:
	_target = snappedf(rng.randf_range(2.5, 5.5), 0.1)
	limit = _target + 3.0
	_goal = Node2D.new()
	add_child(_goal)
	_goal.position = Vector2(320, 110)
	Probe.track(_goal, "*")
	_hand = Blob.new()
	_hand.role = role
	_hand.radius = 6.0
	add_child(_hand)
	Probe.track(_hand, "@")
	_sync()

func describe(err: float) -> String:
	return "missed" if err >= MISS else "%.2fs off" % err

func press() -> void:
	if over:
		return
	_stopped = t
	Juice.pop(_hand, 2.0)
	Juice.shake(3.0)
	Audio.play("impact_bell")
	report(absf(_stopped - _target))

func _shown() -> float:
	return _stopped if _stopped >= 0.0 else t

## The hand goes round once per target, so a hand at the top is the right moment --
## but the dial has no tick marks past the first second, so it is still a feel thing.
func _sync() -> void:
	var a := _shown() / _target * TAU - PI * 0.5
	_hand.position = Vector2(320, 205) + Vector2(cos(a), sin(a)) * 62.0

func step(_delta: float) -> void:
	_sync()

func _draw() -> void:
	var ink := Palette.col("ink")
	label(320, 100, "target  %.1f s" % _target, 18, Palette.col("prize"))
	var c := Vector2(320, 205)
	draw_arc(c, 62.0, 0, TAU, 64, Palette.col("bg_alt"), 4.0)
	draw_circle(c + Vector2(0, -62), 5.0, Palette.col("prize"))
	var txt := "%.2f" % _shown()
	if _stopped < 0.0 and t > SHOW_FOR:
		txt = "?.??"
		# the hand fades once the digits hide, so it is a real feel for time
		_hand.modulate.a = maxf(0.0, 1.0 - (t - SHOW_FOR) * 2.0)
	else:
		_hand.modulate.a = 1.0
	label(320, 214, txt, 26, ink if _stopped < 0.0 else Palette.col(role))
	if not over:
		time_bar()
