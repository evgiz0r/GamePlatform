extends "res://game/duelmaster/duels/duel.gd"
## slice -- a log slides under the knife, faster and faster. Tap to chop at the mark.

const KNIFE_X := 320.0
const LOG_Y := 220.0
const LOG_H := 34.0

var _len := 260.0
var _mark := 0.5                  ## where the mark sits along the log, 0..1
var _x0 := 300.0                  ## log's left end at t=0
var _v0 := 120.0
var _acc := 60.0
var _cut_at := -1.0               ## log-local x of the cut, once made
var _knife_y := 0.0               ## 0 = raised, 1 = down
var _split := 0.0                 ## how far the two halves have drifted apart
var _mark_node: Node2D
var _blade: Blob

func _init() -> void:
	title = "SLICE"
	hint = "tap to chop on the mark"
	tie = 1.5

func _build() -> void:
	limit = 9.0
	_len = rng.randf_range(220.0, 300.0)
	_mark = rng.randf_range(0.3, 0.75)
	_v0 = rng.randf_range(90.0, 140.0)
	_acc = rng.randf_range(40.0, 80.0)
	# the log starts already under the knife, so the race is to the mark, not to the log
	_x0 = 300.0

	_mark_node = Node2D.new()
	add_child(_mark_node)
	Probe.track(_mark_node, "*")
	_blade = Blob.new()
	_blade.role = role
	_blade.radius = 8.0
	_blade.shape = "diamond"
	add_child(_blade)
	Probe.track(_blade, "@")
	_sync()

func _log_x() -> float:
	return _x0 - (_v0 * t + 0.5 * _acc * t * t)

func _sync() -> void:
	_mark_node.position = Vector2(_log_x() + _len * _mark, LOG_Y)
	_blade.position = Vector2(KNIFE_X, LOG_Y - 70.0 + _knife_y * 60.0)

func press() -> void:
	if over:
		return
	over = true
	_cut_at = KNIFE_X - _log_x()
	Juice.hit(4.0)
	Audio.play("impact_wood")
	var err := absf(_cut_at - _len * _mark)
	# chopping thin air (log not under the knife yet, or already gone) is a miss
	report(err if _cut_at > 0.0 and _cut_at < _len else MISS)

func step(delta: float) -> void:
	if over:
		_knife_y = minf(1.0, _knife_y + delta * 12.0)
		_split = minf(26.0, _split + delta * 70.0)
	elif _log_x() + _len < -20.0:
		# the whole log went by
		report(MISS)
	_sync()

func _draw() -> void:
	var wood := Palette.col("warn")
	var ink := Palette.col("ink")
	var x := _log_x()
	if _cut_at > 0.0 and _cut_at < _len:
		var a := Rect2(x - _split, LOG_Y - LOG_H * 0.5, _cut_at, LOG_H)
		var b := Rect2(x + _cut_at + _split, LOG_Y - LOG_H * 0.5, _len - _cut_at, LOG_H)
		draw_rect(a, wood.darkened(0.45))
		draw_rect(b, wood.darkened(0.45))
		draw_rect(a, wood, false, 2.0)
		draw_rect(b, wood, false, 2.0)
	else:
		var r := Rect2(x, LOG_Y - LOG_H * 0.5, _len, LOG_H)
		draw_rect(r, wood.darkened(0.45))
		draw_rect(r, wood, false, 2.0)
	var mx := x + _len * _mark - (_split if _cut_at > _len * _mark else -_split if _cut_at >= 0.0 else 0.0)
	draw_line(Vector2(mx, LOG_Y - LOG_H * 0.5 - 6), Vector2(mx, LOG_Y + LOG_H * 0.5 + 6),
		Palette.col("prize"), 3.0)
	# the knife's line
	var k := Palette.col(role)
	draw_line(Vector2(KNIFE_X, LOG_Y - 64.0 + _knife_y * 60.0), Vector2(KNIFE_X, 120.0),
		Color(k.r, k.g, k.b, 0.6), 2.0)
	draw_line(Vector2(20, LOG_Y + LOG_H * 0.5 + 4), Vector2(620, LOG_Y + LOG_H * 0.5 + 4),
		Palette.col("bg_alt"), 3.0)
	if not over:
		time_bar()
