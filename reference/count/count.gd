extends GameMode
## count -- a herd of critters appears, you pick the animal holding how many there are.
## See GAME.md. Click an animal with the mouse, or steer the paw with the arrow keys and
## touch one. Ten seconds a round, three lives, numbers grow.

const PEN := Rect2(50, 62, 540, 145)      ## where the critters to be counted live
const ROW_Y := 282.0                       ## the answer animals sit on this line
const ROW_MARGIN := 90.0
const PICK_RADIUS := 30.0
const PAW_SPEED := 210.0
const ROUND_TIME := 10.0
const REVEAL_TIME := 0.85
## The shell default (0.8) is loud for a game that beeps every few seconds.
## Set in memory only while count is on screen -- the saved settings file is not touched.
const SFX_VOLUME := 0.28

const HERD := ["crab", "bat", "snail", "spider", "ghost", "goblin", "skull", "bat"]
const BADGES := ["pig", "rabbit", "monkey", "panda", "penguin", "parrot", "hippo",
	"elephant", "giraffe", "snake"]

var paw: Blob
var _choices: Array = []          ## Blob, each with meta "value" and "right"
var _critters: Array = []
var _answer := 0
var _round := 0
var _streak := 0
var _time_left := ROUND_TIME
var _reveal_left := 0.0
var _hover := -1
var _sfx_was := 0.8

func _ready() -> void:
	title = "count"
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
	paw = Blob.new()
	paw.role = "player"
	paw.radius = 8.0
	paw.shape = "diamond"
	add_child(paw)
	paw.position = Vector2(320, 215)
	Probe.track(paw, "@")

	_new_round()
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the round ------------------------------------------------------------

func _new_round() -> void:
	_round += 1
	_clear_round()

	var hi := clampi(3 + _round, 4, 15)
	var lo := clampi(1 + (_round - 1) / 2, 1, maxi(1, hi - 3))
	var n_choices := 3 if _round <= 2 else 4
	var spread := 3 if _round <= 3 else (2 if _round <= 6 else 1)

	_answer = randi_range(lo, hi)
	_spawn_herd(_answer)

	var values: Array = _pick_decoys(_answer, n_choices - 1, spread)
	values.append(_answer)
	values.shuffle()

	var badges: Array = BADGES.duplicate()
	badges.shuffle()
	var slots := _slot_positions(n_choices)
	for i in n_choices:
		var value: int = values[i]
		var right: bool = value == _answer
		var b := Blob.new()
		b.role = "prize"
		b.radius = 14.0
		add_child(b)
		b.set_sprite(badges[i], 0.12)
		b.position = slots[i]
		b.set_meta("value", value)
		b.set_meta("right", right)
		_choices.append(b)
		Probe.track(b, "*" if right else "x")

	_time_left = ROUND_TIME
	_reveal_left = 0.0
	paw.position = Vector2(320, 215)
	Probe.event("round_start", {"round": _round, "answer": _answer})

func _clear_round() -> void:
	for c in _choices:
		if is_instance_valid(c):
			c.queue_free()
	_choices.clear()
	for c in _critters:
		if is_instance_valid(c):
			c.queue_free()
	_critters.clear()
	_hover = -1

## Wrong answers sit near the right one, and creep closer as the rounds go on.
func _pick_decoys(correct: int, want: int, spread: int) -> Array:
	var pool: Array = []
	var s := spread
	while pool.size() < want:
		pool.clear()
		for v in range(maxi(1, correct - s), correct + s + 1):
			if v != correct:
				pool.append(v)
		s += 1
	pool.shuffle()
	return pool.slice(0, want)

func _slot_positions(n: int) -> Array:
	var out: Array = []
	var span := play_area.size.x - ROW_MARGIN * 2.0
	for i in n:
		var f := 0.5 if n == 1 else float(i) / float(n - 1)
		out.append(Vector2(ROW_MARGIN + span * f, ROW_Y))
	return out

## A tidy jittered grid, so the herd is actually countable rather than a pile.
func _spawn_herd(n: int) -> void:
	var sprite: String = HERD[_round % HERD.size()]
	var cols := mini(clampi(ceili(sqrt(float(n) * 1.8)), 1, 6), n)
	var rows := ceili(float(n) / float(cols))
	var sx := 78.0
	var sy := 60.0
	var mid := PEN.position + PEN.size * 0.5
	var left := n
	for r in rows:
		var in_row := mini(cols, left)
		left -= in_row
		var y := mid.y - (rows - 1) * sy * 0.5 + r * sy
		for c in in_row:
			var x := mid.x - (in_row - 1) * sx * 0.5 + c * sx
			var b := Blob.new()
			b.role = "friend"
			b.radius = 9.0
			add_child(b)
			b.set_sprite(sprite, 1.6)
			b.position = Vector2(x + randf_range(-5, 5), y + randf_range(-5, 5))
			b.set_meta("phase", randf() * TAU)
			b.set_meta("home", b.position)
			_critters.append(b)
			Probe.track(b, "o")

## ---- play -----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	_bob(delta)

	if _reveal_left > 0.0:
		_reveal_left -= delta
		if _reveal_left <= 0.0:
			_new_round()
		return

	paw.position += PInput.dir() * PAW_SPEED * delta
	paw.position = paw.position.clamp(play_area.position, play_area.end)
	_update_hover()

	for c in _choices:
		if is_instance_valid(c) and paw.position.distance_to(c.position) < PICK_RADIUS:
			_answer_with(c)
			return

	_time_left -= delta
	if _time_left <= 0.0:
		Probe.event("timeout", {"round": _round})
		Audio.play("lose")
		_streak = 0
		_reveal()
		lose_life()

func _bob(delta: float) -> void:
	for c in _critters:
		if not is_instance_valid(c):
			continue
		var ph: float = c.get_meta("phase") + delta * 3.0
		c.set_meta("phase", ph)
		var home: Vector2 = c.get_meta("home")
		c.position = home + Vector2(0, sin(ph) * 3.0)

## Mouse is the main way in; the paw exists so keyboard, gamepad and bots can play too.
func _input(event: InputEvent) -> void:
	if finished or _reveal_left > 0.0 or _choices.is_empty():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := get_global_mouse_position()
	for c in _choices:
		if is_instance_valid(c) and p.distance_to(c.position) < 42.0:
			_answer_with(c)
			return

func _update_hover() -> void:
	var p := get_global_mouse_position()
	_hover = -1
	for i in _choices.size():
		var c: Blob = _choices[i]
		if is_instance_valid(c) and p.distance_to(c.position) < 42.0:
			_hover = i
		if is_instance_valid(c):
			c.modulate = Color(1.4, 1.4, 1.4) if _hover == i else Color.WHITE

func _answer_with(choice: Blob) -> void:
	var value: int = choice.get_meta("value")
	if choice.get_meta("right"):
		_streak += 1
		var points := 10 + int(_time_left)
		add_score(points)
		Juice.pop(choice, 1.5)
		Juice.text(self, choice.position + Vector2(-10, -46), "+%d" % points, Palette.col("warn"))
		Audio.play("coin")
		Juice.shake(3.0)
		Probe.event("correct", {"answer": _answer, "streak": _streak})
		_reveal(choice)
	else:
		_streak = 0
		Juice.flash(choice, Palette.col("hazard"))
		Juice.text(self, choice.position + Vector2(-10, -46), str(value), Palette.col("hazard"))
		Probe.event("wrong", {"picked": value, "answer": _answer})
		_reveal()
		lose_life()

## Kill the round and hold the right answer on screen for a beat before the next one.
func _reveal(keep: Blob = null) -> void:
	_reveal_left = REVEAL_TIME
	for c in _choices:
		if not is_instance_valid(c):
			continue
		if c.get_meta("right"):
			if keep == null:
				Juice.pop(c, 1.4)
			c.modulate = Color.WHITE
		else:
			c.queue_free()
	if _round % 5 == 0:
		Probe.capture("round %d" % _round)

## ---- the screen ------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")

	_text(f, 320, 30, "HOW MANY?", 20, Palette.col("accent"))

	# countdown bar -- friend, then warn, then hazard as it drains
	var frac := clampf(_time_left / ROUND_TIME, 0.0, 1.0)
	var role := "friend" if frac > 0.5 else ("warn" if frac > 0.25 else "hazard")
	draw_rect(Rect2(90, 40, 460, 8), Palette.col("bg_alt"))
	draw_rect(Rect2(90, 40, 460 * frac, 8), Palette.col(role))

	for c in _choices:
		if not is_instance_valid(c):
			continue
		var v: int = c.get_meta("value")
		_text(f, c.position.x, ROW_Y + 44, str(v), 30, ink)

	_text(f, 320, 352, "round %d    streak %d" % [_round, _streak], 12, Palette.col("accent"))

func _text(f: Font, cx: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(cx - 160, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 320, size, col)
