extends GameMode
## memory -- a row of shapes flashes up, the screen goes blank, then you pick which of the
## cards shows the exact row you just saw. See GAME.md. Click a card with the mouse, or
## steer the glowing cursor with the arrow keys onto one. The row gets longer, the look is
## shorter, the blank wait is longer, and the wrong cards get closer to right.

const STAGE_Y := 140.0                     ## the shapes you have to remember sit here
const STAGE_RADIUS := 24.0
const ROW_Y := 288.0                       ## the answer cards sit on this line
const ROW_MARGIN := 88.0
const PICK_RADIUS := 34.0
const CURSOR_SPEED := 230.0
const CURSOR_HOME := Vector2(320, 210)
const REVEAL_TIME := 0.9
## The shell default (0.8) is loud for a game that beeps every few seconds. Set in
## memory only while memory is on screen -- the saved settings file is not touched.
## A fraction of whatever the sound setting is, so the setting still matters.
const SFX_SCALE := 0.35

const SHAPES := ["circle", "square", "triangle", "diamond"]
## Early on every shape has its own colour, so there is only the shape to remember.
const HOME_ROLE := {"circle": "player", "square": "friend", "triangle": "warn", "diamond": "prize"}
## Later any shape can wear any of these, so colour has to be remembered too.
const ROLES := ["player", "friend", "warn", "prize"]

## What is on screen right now. show -> wait -> choose -> reveal -> show ...
enum Phase { SHOW, WAIT, CHOOSE, REVEAL }

var cursor: Blob
var _phase := Phase.SHOW
var _phase_left := 0.0
var _phase_total := 1.0
var _sequence: Array = []          ## Array of {"shape": String, "role": String}
var _stage: Array = []             ## Blobs showing the sequence big
var _cards: Array = []             ## Card nodes, each with `seq` and `right`
var _round := 0
var _streak := 0
var _hover := -1
var _sfx_was := 0.8
var _wait_pulse := 0.0

func _ready() -> void:
	title = "memory"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	set_lives(3)
	cursor = Blob.new()
	cursor.role = "player"
	cursor.radius = 8.0
	cursor.shape = "diamond"
	add_child(cursor)
	cursor.position = CURSOR_HOME
	cursor.visible = false
	Probe.track(cursor, "@")

	_new_round()
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the ramp ---------------------------------------------------------------
## Four things get harder, on purpose one at a time so each step is felt:
## the row gets longer, the look gets shorter, the blank gets longer, and the wrong
## cards stop being obviously wrong.

func _length() -> int:
	return clampi(1 + (_round - 1) / 2, 1, 7)

func _show_time() -> float:
	var per_shape := maxf(0.26, 0.5 - _round * 0.02)
	return maxf(0.55, 1.0 - _round * 0.04) + per_shape * _length()

func _wait_time() -> float:
	return clampf(0.5 + _round * 0.3, 0.5, 4.0)

func _choose_time() -> float:
	return 5.0 + 0.6 * _length()

func _n_cards() -> int:
	return 2 if _round <= 2 else (3 if _round <= 5 else 4)

func _colour_matters() -> bool:
	return _round > 4

## ---- the round ----------------------------------------------------------------

func _new_round() -> void:
	_round += 1
	_clear_round()

	_sequence = _random_sequence(_length())
	for i in _sequence.size():
		var s: Dictionary = _sequence[i]
		var b := Blob.new()
		b.role = s["role"]
		b.shape = s["shape"]
		b.radius = STAGE_RADIUS
		add_child(b)
		b.position = _stage_slot(i, _sequence.size())
		b.scale = Vector2.ZERO
		_stage.append(b)
		# they land one after another, left to right, with a rising click each
		var tw := b.create_tween()
		tw.tween_interval(0.07 * i)
		tw.tween_callback(Audio.play.bind("click", 0.04, float(i) * 1.5))
		tw.tween_property(b, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Probe.track(b, "o")

	cursor.visible = false
	cursor.position = CURSOR_HOME
	_set_phase(Phase.SHOW, _show_time())
	Probe.event("round_start", {"round": _round, "length": _sequence.size(),
		"show": snappedf(_show_time(), 0.01), "wait": snappedf(_wait_time(), 0.01),
		"cards": _n_cards()})

func _clear_round() -> void:
	for n in _stage:
		if is_instance_valid(n):
			n.queue_free()
	_stage.clear()
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()
	_hover = -1

func _set_phase(p: Phase, secs: float) -> void:
	_phase = p
	_phase_left = secs
	_phase_total = maxf(secs, 0.01)

func _random_item() -> Dictionary:
	var shape: String = SHAPES[randi() % SHAPES.size()]
	var role: String = ROLES[randi() % ROLES.size()] if _colour_matters() else HOME_ROLE[shape]
	return {"shape": shape, "role": role}

func _random_sequence(n: int) -> Array:
	var out: Array = []
	for i in n:
		var item := _random_item()
		# no two of the same thing side by side -- "circle circle" reads as a mistake
		var tries := 0
		while i > 0 and _same(item, out[i - 1]) and tries < 12:
			item = _random_item()
			tries += 1
		out.append(item)
	return out

func _same(a: Dictionary, b: Dictionary) -> bool:
	return a["shape"] == b["shape"] and a["role"] == b["role"]

func _same_seq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not _same(a[i], b[i]):
			return false
	return true

## A wrong card. Early rounds it is a different row altogether; then it is the right row
## with one shape changed; then it can also be the right row with two neighbours swapped,
## which is the meanest kind of wrong there is.
func _decoy(taken: Array) -> Array:
	for _attempt in 40:
		var d: Array = _sequence.duplicate(true)
		var mode := 0
		if _round <= 3:
			mode = 0
		elif _round <= 7 or d.size() < 2:
			mode = 1
		else:
			mode = 1 if randf() < 0.55 else 2
		match mode:
			0:
				d = _random_sequence(d.size())
			1:
				var i := randi() % d.size()
				var item := _random_item()
				var tries := 0
				while _same(item, d[i]) and tries < 12:
					item = _random_item()
					tries += 1
				d[i] = item
			_:
				var i := randi() % (d.size() - 1)
				var tmp: Dictionary = d[i]
				d[i] = d[i + 1]
				d[i + 1] = tmp
		var clash := _same_seq(d, _sequence)
		for t in taken:
			if _same_seq(d, t):
				clash = true
		if not clash:
			return d
	# a one-shape row with only four shapes can run out of different rows; fall back to
	# anything that is not the answer
	var d: Array = _sequence.duplicate(true)
	d[0] = _random_item()
	while _same(d[0], _sequence[0]):
		d[0] = _random_item()
	return d

func _deal_cards() -> void:
	var n := _n_cards()
	var rows: Array = [_sequence.duplicate(true)]
	for i in n - 1:
		rows.append(_decoy(rows))
	var right_at := randi() % n
	# the answer goes in a random slot; the decoys fill the rest in order
	var slots := _slot_positions(n)
	var decoy_i := 1
	for i in n:
		var is_right := i == right_at
		var card := Card.new()
		card.seq = rows[0] if is_right else rows[decoy_i]
		if not is_right:
			decoy_i += 1
		card.right = is_right
		add_child(card)
		card.position = slots[i]
		card.scale = Vector2(0.2, 0.2)
		var tw := card.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_cards.append(card)
		Probe.track(card, "*" if is_right else "o")
	cursor.visible = true
	cursor.position = CURSOR_HOME
	Audio.play("open")
	_set_phase(Phase.CHOOSE, _choose_time())

func _slot_positions(n: int) -> Array:
	var out: Array = []
	var span := play_area.size.x - ROW_MARGIN * 2.0
	for i in n:
		var f := 0.5 if n == 1 else float(i) / float(n - 1)
		out.append(Vector2(ROW_MARGIN + span * f, ROW_Y))
	return out

func _stage_slot(i: int, n: int) -> Vector2:
	var gap := 72.0 if n <= 5 else 62.0
	return Vector2(320.0 - (n - 1) * gap * 0.5 + i * gap, STAGE_Y)

## ---- play ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	_wait_pulse += delta
	_phase_left -= delta

	match _phase:
		Phase.SHOW:
			_breathe(delta)
			if _phase_left <= 0.0:
				for b in _stage:
					if is_instance_valid(b):
						var tw: Tween = b.create_tween()
						tw.tween_property(b, "scale", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
						tw.tween_callback(b.queue_free)
				_stage.clear()
				Audio.play("thud", 0.05, -6.0)
				_set_phase(Phase.WAIT, _wait_time())
				Probe.event("hidden", {"round": _round})
		Phase.WAIT:
			if _phase_left <= 0.0:
				_deal_cards()
				Probe.event("cards_out", {"round": _round})
		Phase.CHOOSE:
			cursor.position += PInput.dir() * CURSOR_SPEED * delta
			cursor.position = cursor.position.clamp(play_area.position, play_area.end)
			_update_hover()
			for c in _cards:
				if is_instance_valid(c) and cursor.position.distance_to(c.position) < PICK_RADIUS:
					_answer_with(c)
					return
			if _phase_left <= 0.0:
				Probe.event("timeout", {"round": _round})
				Audio.play("voice_time_over")
				_streak = 0
				_reveal()
				lose_life()
		Phase.REVEAL:
			if _phase_left <= 0.0:
				_new_round()

## The shapes on the stage sway a little so a still screen still feels alive.
func _breathe(_delta: float) -> void:
	for i in _stage.size():
		var b: Blob = _stage[i]
		if is_instance_valid(b):
			b.rotation = sin(_wait_pulse * 2.4 + i * 0.9) * 0.08

## Mouse and finger are the main way in; the cursor exists so keyboard, gamepad and
## bots can play the same game.
func _input(event: InputEvent) -> void:
	if finished or _phase != Phase.CHOOSE or _cards.is_empty():
		return
	if Flow.pointer_over_hud():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := get_global_mouse_position()
	for c in _cards:
		if is_instance_valid(c) and c.hit(p):
			_answer_with(c)
			return

func _update_hover() -> void:
	var p := get_global_mouse_position()
	_hover = -1
	for i in _cards.size():
		var c: Card = _cards[i]
		if not is_instance_valid(c):
			continue
		if c.hit(p):
			_hover = i
		c.hovered = _hover == i
		c.queue_redraw()

func _answer_with(card: Card) -> void:
	if card.right:
		_streak += 1
		var points := 10 * _sequence.size() + int(_phase_left)
		add_score(points)
		Juice.pop(card, 1.25)
		Juice.text(self, card.position + Vector2(-10, -58), "+%d" % points, Palette.col("warn"))
		Audio.play("coin")
		Audio.play("voice_correct")
		Juice.shake(3.0)
		Probe.event("correct", {"round": _round, "length": _sequence.size(), "streak": _streak})
		_reveal(card)
	else:
		_streak = 0
		Juice.flash(card, Palette.col("hazard"))
		Audio.play("voice_wrong")
		Probe.event("wrong", {"round": _round, "length": _sequence.size()})
		_reveal()
		lose_life()

## Kill the round and hold the right card on screen for a beat before the next one.
func _reveal(keep: Card = null) -> void:
	_set_phase(Phase.REVEAL, REVEAL_TIME)
	cursor.visible = false
	for c in _cards:
		if not is_instance_valid(c):
			continue
		if c.right:
			c.hovered = false
			c.revealed = true
			c.queue_redraw()
			if keep == null:
				Juice.pop(c, 1.3)
		else:
			c.queue_free()
	_cards = _cards.filter(func(c): return is_instance_valid(c) and c.right)
	if _round % 5 == 0:
		Probe.capture("round %d" % _round)

## ---- the screen ------------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var accent := Palette.col("accent")
	var frac := clampf(_phase_left / _phase_total, 0.0, 1.0)

	match _phase:
		Phase.SHOW:
			_text(f, 320, 30, "REMEMBER", 20, accent)
			draw_rect(Rect2(90, 40, 460, 8), Palette.col("bg_alt"))
			draw_rect(Rect2(90, 40, 460 * frac, 8), Palette.col("friend"))
		Phase.WAIT:
			_text(f, 320, 30, "WAIT", 20, Palette.col("ink"))
			draw_rect(Rect2(90, 40, 460, 8), Palette.col("bg_alt"))
			draw_rect(Rect2(90, 40, 460 * (1.0 - frac), 8), Palette.col("warn"))
			# three slow dots where the shapes were, so the blank does not read as a crash
			for i in 3:
				var a := 0.25 + 0.55 * maxf(0.0, sin(_wait_pulse * 4.0 - i * 1.0))
				var c := Palette.col("ink")
				draw_circle(Vector2(320 - 26 + i * 26, STAGE_Y), 5.0, Color(c.r, c.g, c.b, a))
		Phase.CHOOSE:
			_text(f, 320, 30, "WHICH ONE?", 20, accent)
			var role := "friend" if frac > 0.5 else ("warn" if frac > 0.25 else "hazard")
			draw_rect(Rect2(90, 40, 460, 8), Palette.col("bg_alt"))
			draw_rect(Rect2(90, 40, 460 * frac, 8), Palette.col(role))
		Phase.REVEAL:
			_text(f, 320, 30, "", 20, accent)

	var colour_note := "shape + colour" if _colour_matters() else "shape"
	_text(f, 320, 352, "round %d    %d in a row    %s    streak %d"
		% [_round, _length(), colour_note, _streak], 12, accent)

func _text(f: Font, cx: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(cx - 160, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 320, size, col)

## An answer card: a tile with a small copy of one row of shapes on it.
class Card extends Node2D:
	const SIZE := Vector2(132, 62)
	const SHAPE_RADIUS := 8.0
	const SHAPE_GAP := 19.0

	var seq: Array = []
	var right := false
	var hovered := false
	var revealed := false

	## One shape in a palette role, the same drawing Blob does for its placeholder, so the
	## small copies on the cards match the big ones on the stage.
	static func draw_shape(ci: CanvasItem, pos: Vector2, shape: String, role: String, r: float) -> void:
		var c := Palette.col(role)
		ci.draw_circle(pos, r * 1.6, Color(c.r, c.g, c.b, 0.14))
		match shape:
			"square":
				ci.draw_rect(Rect2(pos.x - r, pos.y - r, r * 2, r * 2), c)
			"triangle":
				ci.draw_colored_polygon(PackedVector2Array([
					pos + Vector2(0, -r), pos + Vector2(r, r), pos + Vector2(-r, r)]), c)
			"diamond":
				ci.draw_colored_polygon(PackedVector2Array([
					pos + Vector2(0, -r), pos + Vector2(r, 0), pos + Vector2(0, r), pos + Vector2(-r, 0)]), c)
			_:
				ci.draw_circle(pos, r, c)
				ci.draw_circle(pos, r * 0.45, Color(1, 1, 1, 0.55))

	func _ready() -> void:
		Bus.palette_changed.connect(queue_redraw)

	func hit(p: Vector2) -> bool:
		return Rect2(position - SIZE * 0.5, SIZE).grow(4.0).has_point(p)

	func _draw() -> void:
		var rect := Rect2(-SIZE * 0.5, SIZE)
		var edge_role := "prize" if revealed else ("ink" if hovered else "accent")
		var edge := Palette.col(edge_role)
		var fill := Palette.col("bg_alt")
		if hovered:
			fill = fill.lightened(0.12)
		draw_rect(rect.grow(6.0), Color(edge.r, edge.g, edge.b, 0.16 if not revealed else 0.35))
		draw_rect(rect, fill)
		draw_rect(rect, edge, false, 2.0)
		# short rows get big shapes; long rows shrink to fit the tile
		var n := seq.size()
		var r := 14.0 if n <= 1 else (12.0 if n <= 3 else (10.0 if n <= 5 else (SHAPE_RADIUS if n <= 6 else 7.5)))
		var gap := 34.0 if n <= 3 else (24.0 if n <= 5 else (SHAPE_GAP if n <= 6 else 16.5))
		for i in n:
			var s: Dictionary = seq[i]
			var x := -(n - 1) * gap * 0.5 + i * gap
			draw_shape(self, Vector2(x, 0), s["shape"], s["role"], r)
