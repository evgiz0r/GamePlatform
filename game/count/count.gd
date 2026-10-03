extends GameMode
## count -- a herd of critters appears, you pick the animal holding how many there are.
## See GAME.md. Click an animal with the mouse, or steer the paw with the arrow keys and
## touch one. Ten levels, each with its own goal and a prize for clearing it; the tenth is
## a boss. Three lives, topped back up at the start of every level.

const PEN := Rect2(46, 58, 536, 160)      ## where the critters to be counted live
const CRITTER_SCALE := 1.7
const ROW_Y := 282.0                       ## the answer animals sit on this line
const ROW_MARGIN := 90.0
const PICK_RADIUS := 30.0
const PAW_SPEED := 210.0
const REVEAL_TIME := 0.85
const INTRO_TIME := 1.9                    ## "LEVEL 3 / count 8 or more, twice"
const CLEAR_TIME := 2.1                    ## the prize pops up and flies to the shelf
const CROWN_TIME := 4.5                    ## the boss prize gets a proper moment
const SHELF_X := 620.0                     ## prizes collect down the right-hand edge
const SHELF_Y := 78.0
const SHELF_STEP := 22.0
## The shell default (0.8) is loud for a game that beeps every few seconds.
## Set in memory only while count is on screen -- the saved settings file is not touched.
## See CLAUDE.md, "things this kit learned the hard way".
## Fraction of whatever the menu's volume knob is set to, not an absolute level --
## a game that hard-set this ignored the menu control entirely. 0.35 matches the old
## fixed 0.28 at the shipped default (0.8), so nothing sounds different if the knob
## has never been touched.
const SFX_SCALE := 0.35

## Small animals to count. These are the 16x16 sprites, deliberately a different kind of
## picture from the big animal badges that hold the numbers -- if both were badges you
## could not tell the things being counted from the answers.
const CAST := ["crab", "bat", "snail", "spider"]
## How the critters are arranged, easiest first. This -- not the number -- is the ramp.
const LAYOUTS := ["neat rows", "ragged rows", "clumps", "scattered", "jumbled"]
## The ladder. Each level sets the count range, how the herd is laid out (index into
## LAYOUTS), how many answers there are, how close the wrong ones sit, the clock, and the
## goal. Goal kinds:
##   right  -- n right answers               streak -- n right in a row
##   big    -- n right where the count >= min fast  -- n right within `secs` seconds
##   points -- n points scored this level     sum    -- right answers add up to n
## Tuned so an average player clears all ten in three to five minutes: roughly 45-50
## rounds at four or five seconds each, plus the banners between levels.
const LEVELS := [
	{"lo": 1, "hi": 4, "layout": 0, "choices": 3, "spread": 3, "time": 10.0,
		"goal": "right", "need": 3, "text": "get 3 right", "prize": "beehive"},
	{"lo": 2, "hi": 6, "layout": 0, "choices": 3, "spread": 2, "time": 10.0,
		"goal": "streak", "need": 3, "text": "get 3 in a row", "prize": "potion_red"},
	{"lo": 4, "hi": 9, "layout": 1, "choices": 4, "spread": 2, "time": 10.0,
		"goal": "big", "need": 2, "min": 8, "text": "count 8 or more, twice", "prize": "ghost"},
	{"lo": 3, "hi": 8, "layout": 1, "choices": 4, "spread": 2, "time": 10.0,
		"goal": "fast", "need": 3, "secs": 4.0, "text": "3 quick ones: under 4 seconds", "prize": "potion_blue"},
	{"lo": 3, "hi": 9, "layout": 2, "choices": 4, "spread": 2, "time": 10.0,
		"goal": "points", "need": 70, "text": "score 70 points", "prize": "banner"},
	{"lo": 4, "hi": 10, "layout": 2, "choices": 4, "spread": 1, "time": 9.0,
		"goal": "streak", "need": 4, "text": "get 4 in a row", "prize": "potion_green"},
	{"lo": 6, "hi": 12, "layout": 3, "choices": 4, "spread": 1, "time": 9.0,
		"goal": "big", "need": 2, "min": 10, "text": "count 10 or more, twice", "prize": "bow"},
	{"lo": 5, "hi": 10, "layout": 3, "choices": 4, "spread": 1, "time": 8.0,
		"goal": "fast", "need": 3, "secs": 4.0, "text": "3 quick ones: under 4 seconds", "prize": "princess"},
	{"lo": 6, "hi": 12, "layout": 4, "choices": 4, "spread": 1, "time": 8.0,
		"goal": "sum", "need": 40, "text": "right answers add up to 40", "prize": "gold_bar"},
	# the boss: a mixed herd, five answers all one apart, a short clock, no slips
	{"lo": 7, "hi": 13, "layout": 4, "choices": 5, "spread": 1, "time": 7.0,
		"goal": "streak", "need": 5, "text": "BOSS: 5 in a row", "prize": "crown"},
]
const BADGES := ["pig", "rabbit", "monkey", "panda", "penguin", "parrot", "hippo",
	"elephant", "giraffe", "snake"]

var paw: Blob
var _choices: Array = []          ## Blob, each with meta "value" and "right"
var _critters: Array = []
var _answer := 0
var _round := 0
var _streak := 0
var _round_time := 10.0
var _time_left := 10.0
var _hover := -1
var _level := 0                   ## 1-based once the game starts
var _progress := 0                ## towards this level's goal
## "intro" (level banner) -> "play" -> "reveal" -> "play" ... -> "clear" -> "intro" ...
## and after the boss, "crown" -> win().
var _phase := "intro"
var _phase_left := 0.0
var _shelf: Array = []            ## prize Blobs already won
var _crown_pos := Vector2.ZERO
var _crown_size := 0.0            ## 0 = no crown on screen
var _sfx_was := 0.8

func _ready() -> void:
	title = "count"
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
	paw = Blob.new()
	paw.role = "player"
	paw.radius = 8.0
	paw.shape = "diamond"
	add_child(paw)
	paw.position = Vector2(320, 215)
	Probe.track(paw, "@")

	_begin_level(1)
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the round ------------------------------------------------------------

func _new_round() -> void:
	_round += 1
	_clear_round()

	# The level sets the range, but the arrangement is what really makes it hard -- six
	# critters in a tidy row are trivial, the same six in two clumps genuinely are not.
	var lv: Dictionary = _lv()
	var n_choices: int = lv.choices
	_answer = randi_range(lv.lo, lv.hi)
	# a "count 8 or more" level that never shows an 8 is just a wait, so lean on it
	if lv.goal == "big" and randf() < 0.5:
		_answer = randi_range(lv.min, lv.hi)
	_spawn_herd(_answer)
	var spread: int = lv.spread

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

	_round_time = lv.time
	_time_left = _round_time
	_phase = "play"
	paw.position = Vector2(320, 215)
	Probe.event("round_start", {"round": _round, "level": _level, "answer": _answer,
		"layout": LAYOUTS[_layout_mode()]})

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

func _lv() -> Dictionary:
	return LEVELS[clampi(_level - 1, 0, LEVELS.size() - 1)]

func _is_boss() -> bool:
	return _level == LEVELS.size()

func _layout_mode() -> int:
	return _lv().layout

func _spawn_herd(n: int) -> void:
	var who: String = CAST[_round % CAST.size()]
	for p in _layout(n):
		var b := Blob.new()
		b.role = "friend"
		b.radius = 9.0
		add_child(b)
		# the boss herd is a mix of kinds -- you count all of them, which is harder than
		# it sounds when your eye keeps grouping the crabs
		b.set_sprite(CAST.pick_random() if _is_boss() else who, CRITTER_SCALE)
		b.position = p
		b.set_meta("phase", randf() * TAU)
		b.set_meta("home", p)
		b.set_meta("mood", "idle")
		_critters.append(b)
		Probe.track(b, "o")

func _layout(n: int) -> Array:
	match _layout_mode():
		0: return _rows(n, 0.0)
		1: return _rows(n, 11.0)
		2: return _clumps(n)
		3: return _scatter(n, 58.0)
		_: return _scatter(n, 38.0)

## Tidy grid, optionally shaken. The easy end of the ramp.
func _rows(n: int, jitter: float) -> Array:
	var cols := mini(clampi(ceili(sqrt(float(n) * 1.8)), 1, 6), n)
	var rows := ceili(float(n) / float(cols))
	var sx := 74.0
	var sy := 56.0
	var mid := PEN.position + PEN.size * 0.5
	var out: Array = []
	var left := n
	for r in rows:
		var in_row := mini(cols, left)
		left -= in_row
		var y := mid.y - (rows - 1) * sy * 0.5 + r * sy
		for c in in_row:
			var x := mid.x - (in_row - 1) * sx * 0.5 + c * sx
			out.append(Vector2(x + randf_range(-jitter, jitter), y + randf_range(-jitter, jitter)))
	return out

## Two or three clumps. Counting a clump means counting a shape, which is the hard part.
func _clumps(n: int) -> Array:
	var k := mini(2 if n <= 6 else 3, n)
	var sizes: Array = []
	for i in k:
		sizes.append(1)
	for i in range(n - k):
		sizes[randi() % k] += 1
	var out: Array = []
	for i in k:
		var f := (float(i) + 0.5) / float(k)
		var centre := Vector2(
			PEN.position.x + PEN.size.x * f + randf_range(-26, 26),
			PEN.position.y + PEN.size.y * randf_range(0.3, 0.7))
		var take: int = sizes[i]
		for j in take:
			var ang := randf() * TAU
			var rad := sqrt(randf()) * (16.0 + float(take) * 6.0)
			out.append(centre + Vector2(cos(ang) * rad, sin(ang) * rad * 0.75))
	return _relax(out, 30.0)

## Free scatter with a minimum gap, relaxed if the pen gets crowded.
func _scatter(n: int, gap: float) -> Array:
	var out: Array = []
	var g := gap
	var tries := 0
	while out.size() < n and tries < 3000:
		tries += 1
		var p := Vector2(randf_range(PEN.position.x + 18, PEN.end.x - 18),
			randf_range(PEN.position.y + 20, PEN.end.y - 20))
		var ok := true
		for q in out:
			if p.distance_to(q) < g:
				ok = false
				break
		if ok:
			out.append(p)
		elif tries % 400 == 0:
			g = maxf(30.0, g - 5.0)
	return out

## Push any overlapping pair apart, so "hard to count" never becomes "impossible to see".
func _relax(points: Array, gap: float) -> Array:
	for _pass in 8:
		for i in points.size():
			for j in range(i + 1, points.size()):
				var d: Vector2 = points[j] - points[i]
				var l: float = d.length()
				if l < 0.01:
					d = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
					l = 0.01
				if l < gap:
					var push: Vector2 = d.normalized() * (gap - l) * 0.5
					points[i] = points[i] - push
					points[j] = points[j] + push
	for i in points.size():
		points[i] = Vector2(
			clampf(points[i].x, PEN.position.x + 18, PEN.end.x - 18),
			clampf(points[i].y, PEN.position.y + 20, PEN.end.y - 20))
	return points

## ---- play -----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	_bob(delta)
	paw.visible = _phase == "play" or _phase == "reveal"

	if _phase != "play":
		_phase_left -= delta
		if _phase_left <= 0.0:
			_next_phase()
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
		Audio.play("voice_time_over")
		_herd_play("hurt")
		_missed()
		_reveal()
		lose_life()

## The whole crowd reacts together -- that shared beat is most of the payoff.
func _herd_play(mood: String) -> void:
	for c in _critters:
		if is_instance_valid(c):
			c.set_meta("mood", mood)

## These sprites have no frames, so the life is all position and rotation: a slow sway
## while you count, jumping for joy when you get it, a sad tilt when you do not.
func _bob(delta: float) -> void:
	for c in _critters:
		if not is_instance_valid(c):
			continue
		var mood: String = c.get_meta("mood")
		var rate := 11.0 if mood == "cheer" else (7.0 if mood == "hurt" else 3.0)
		var ph: float = c.get_meta("phase") + delta * rate
		c.set_meta("phase", ph)
		var home: Vector2 = c.get_meta("home")
		match mood:
			"cheer":
				c.position = home + Vector2(0, -absf(sin(ph)) * 10.0)
				c.rotation = sin(ph * 0.5) * 0.14
			"hurt":
				c.position = home + Vector2(sin(ph) * 1.5, 2.0)
				c.rotation = 0.3
			_:
				c.position = home + Vector2(0, sin(ph) * 3.0)
				c.rotation = sin(ph * 0.4) * 0.05

## Mouse is the main way in; the paw exists so keyboard, gamepad and bots can play too.
func _input(event: InputEvent) -> void:
	if finished or _phase != "play" or _choices.is_empty():
		return
	if Flow.pointer_over_hud():
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
		_scored(points)
		Juice.pop(choice, 1.5)
		Juice.text(self, choice.position + Vector2(-10, -46), "+%d" % points, Palette.col("warn"))
		Audio.play("coin")
		# she says the number itself -- the confirmation and the teaching in one clip.
		# Only one to ten were recorded, so bigger answers fall back to "correct".
		Audio.play("voice_num_%d" % _answer if _answer <= 10 else "voice_correct")
		_herd_play("cheer")
		Juice.shake(3.0)
		Probe.event("correct", {"answer": _answer, "streak": _streak})
		_reveal(choice)
	else:
		_missed()
		Juice.flash(choice, Palette.col("hazard"))
		Juice.text(self, choice.position + Vector2(-10, -46), str(value), Palette.col("hazard"))
		Audio.play("voice_wrong")
		_herd_play("hurt")
		Probe.event("wrong", {"picked": value, "answer": _answer})
		_reveal()
		lose_life()

## Kill the round and hold the right answer on screen for a beat before the next one.
func _reveal(keep: Blob = null) -> void:
	_phase = "reveal"
	_phase_left = REVEAL_TIME
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

## ---- levels and prizes -------------------------------------------------------

func _begin_level(n: int) -> void:
	_level = n
	_progress = 0
	_streak = 0
	_clear_round()
	_herd_play("idle")
	# a fresh three lives every level: losing on level nine to slips made back on level
	# two is not a fair fight, and the level goal is the pressure now
	set_lives(3)
	_phase = "intro"
	_phase_left = INTRO_TIME
	if _is_boss():
		Audio.play("voice_final_round")
		Juice.shake(6.0)
	else:
		Audio.play("voice_level")
	Probe.event("level_start", {"level": n, "goal": _lv().text})

func _next_phase() -> void:
	match _phase:
		"intro":
			_new_round()
		"reveal":
			if _progress >= int(_lv().need):
				_level_clear()
			else:
				_new_round()
		"clear":
			if _is_boss():
				_crown()
			else:
				_begin_level(_level + 1)
		"crown":
			win()

## A right answer: move the goal along by whatever this level counts.
func _scored(points: int) -> void:
	var lv := _lv()
	match String(lv.goal):
		"right":
			_progress += 1
		"streak":
			_progress = _streak
		"big":
			if _answer >= int(lv.min):
				_progress += 1
		"fast":
			if _round_time - _time_left <= float(lv.secs):
				_progress += 1
			else:
				Juice.text(self, Vector2(300, 236), "too slow", Palette.col("warn"))
		"points":
			_progress += points
		"sum":
			_progress += _answer
	_progress = mini(_progress, int(lv.need))
	Probe.event("goal_progress", {"level": _level, "progress": _progress, "need": lv.need})

## A wrong answer or a timeout. Only the in-a-row goals care.
func _missed() -> void:
	_streak = 0
	if _lv().goal == "streak":
		_progress = 0

func _level_clear() -> void:
	_phase = "clear"
	_phase_left = CLEAR_TIME if not _is_boss() else 1.4
	_clear_round()
	add_score(25 * _level)
	Audio.play("voice_objective_achieved" if not _is_boss() else "voice_congratulations")
	Audio.play("impact_bell")
	Juice.shake(4.0)
	Probe.event("level_clear", {"level": _level, "score": score})
	Probe.capture("level %d clear" % _level)
	if not _is_boss():
		_award(_lv().prize)

## The prize appears big in the middle, then flies to its slot on the shelf.
func _award(prize: String) -> void:
	var b := Blob.new()
	b.role = "prize"
	b.radius = 8.0
	b.z_index = 20
	add_child(b)
	b.set_sprite(prize, 1.3)
	b.position = Vector2(320, 175)
	b.scale = Vector2.ZERO
	var slot := Vector2(SHELF_X, SHELF_Y + SHELF_STEP * _shelf.size())
	_shelf.append(b)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(4.0, 4.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "rotation", TAU, 0.6).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.35)
	tw.tween_property(b, "position", slot, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(b, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		Juice.pop(b, 1.6)
		Audio.play("pickup"))
	Probe.event("prize", {"level": _level, "prize": prize})

## The boss prize: a big golden crown, with every prize you won dancing round it.
func _crown() -> void:
	_phase = "crown"
	_phase_left = CROWN_TIME
	_crown_pos = Vector2(320, 165)
	var tw := create_tween()
	tw.tween_property(self, "_crown_size", 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("voice_you_win")
	Audio.music("jingle_3")
	Juice.shake(8.0)
	for i in _shelf.size():
		var b: Blob = _shelf[i]
		var ang := TAU * float(i) / float(_shelf.size())
		var t2 := b.create_tween()
		t2.set_parallel(true)
		t2.tween_property(b, "position", _crown_pos + Vector2(cos(ang) * 120.0, sin(ang) * 70.0), 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_property(b, "scale", Vector2(1.8, 1.8), 0.7)
	for i in 40:
		_confetti()
	Probe.event("boss_prize", {"score": score})

func _confetti() -> void:
	var c := Blob.new()
	c.role = ["prize", "accent", "friend", "warn", "player"].pick_random()
	c.shape = ["diamond", "square", "circle"].pick_random()
	c.radius = randf_range(2.5, 4.5)
	c.z_index = 30
	add_child(c)
	c.position = _crown_pos
	var to := _crown_pos + Vector2(randf_range(-300, 300), randf_range(-150, 190))
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "position", to, randf_range(0.8, 1.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", randf_range(-8.0, 8.0), 1.6)
	tw.tween_property(c, "modulate:a", 0.0, 1.0).set_delay(1.4)
	tw.chain().tween_callback(c.queue_free)

## ---- the screen ------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")
	var lv := _lv()

	_draw_shelf()
	if _crown_size > 0.0:
		_draw_crown(_crown_pos, 70.0 * _crown_size)
		_text(f, 320, 300, "YOU BEAT THE BOSS!", 28, Palette.col("prize"))
		return

	if _phase == "intro":
		var boss := _is_boss()
		_text(f, 320, 140, "BOSS LEVEL" if boss else "LEVEL %d" % _level, 40,
			Palette.col("hazard" if boss else "accent"))
		_text(f, 320, 185, String(lv.text).trim_prefix("BOSS: "), 22, ink)
		_text(f, 320, 250, "prize: the crown" if boss else "prize waiting on the shelf", 12,
			Palette.col("prize"))
		return
	if _phase == "clear":
		_text(f, 320, 95, "LEVEL %d CLEAR!" % _level, 34, Palette.col("prize"))
		return

	_text(f, 320, 30, "HOW MANY?", 20, Palette.col("hazard" if _is_boss() else "accent"))

	# countdown bar -- friend, then warn, then hazard as it drains
	var frac := clampf(_time_left / _round_time, 0.0, 1.0)
	var role := "friend" if frac > 0.5 else ("warn" if frac > 0.25 else "hazard")
	draw_rect(Rect2(90, 40, 460, 8), Palette.col("bg_alt"))
	draw_rect(Rect2(90, 40, 460 * frac, 8), Palette.col(role))
	if lv.goal == "fast":
		# where "quick" runs out, so you can see whether you are still in time
		var mark: float = 90.0 + 460.0 * (1.0 - float(lv.secs) / _round_time)
		draw_rect(Rect2(mark - 1, 36, 2, 16), Palette.col("prize"))

	for c in _choices:
		if not is_instance_valid(c):
			continue
		var v: int = c.get_meta("value")
		_text(f, c.position.x, ROW_Y + 44, str(v), 30, ink)

	# the goal and how far along it you are
	var need: int = lv.need
	var label := "%s %d/10:  %s" % ["BOSS" if _is_boss() else "level", _level, lv.text.trim_prefix("BOSS: ")]
	_text(f, 260, 352, label, 13, Palette.col("accent"))
	if need <= 6:
		for i in need:
			var p := Vector2(470 + i * 14, 347)
			if i < _progress:
				draw_circle(p, 5.0, Palette.col("prize"))
			else:
				draw_arc(p, 5.0, 0, TAU, 16, Palette.col("bg_alt"), 2.0)
	else:
		_text(f, 520, 352, "%d / %d" % [_progress, need], 13, Palette.col("prize"))

## Ten slots down the right edge. Empty ones are outlines so you can see what is left;
## the last is the crown's.
func _draw_shelf() -> void:
	for i in LEVELS.size():
		var p := Vector2(SHELF_X, SHELF_Y + SHELF_STEP * i)
		var boss_slot := i == LEVELS.size() - 1
		var won := i < _shelf.size() or (boss_slot and _crown_size > 0.0)
		if not won:
			draw_arc(p, 8.0, 0, TAU, 20, Palette.col("hazard" if boss_slot else "bg_alt"), 1.5)
		if boss_slot:
			_draw_crown(p, 7.0, won)

## A crown made of a band and three points, gems on top. `r` is half its width.
func _draw_crown(at: Vector2, r: float, lit: bool = true) -> void:
	var gold := Palette.col("prize")
	if not lit:
		gold = Color(gold.r, gold.g, gold.b, 0.25)
	if lit and r > 20.0:
		draw_circle(at, r * 1.6, Color(gold.r, gold.g, gold.b, 0.10))
		draw_circle(at, r * 1.2, Color(gold.r, gold.g, gold.b, 0.14))
	var pts := PackedVector2Array([
		at + Vector2(-r, r * 0.6), at + Vector2(-r, -r * 0.5), at + Vector2(-r * 0.5, 0),
		at + Vector2(0, -r * 0.8), at + Vector2(r * 0.5, 0), at + Vector2(r, -r * 0.5),
		at + Vector2(r, r * 0.6)])
	draw_colored_polygon(pts, gold)
	if not lit:
		return
	draw_rect(Rect2(at + Vector2(-r, r * 0.35), Vector2(r * 2.0, r * 0.25)), Palette.col("warn"))
	var gem := r * 0.13
	draw_circle(at + Vector2(-r, -r * 0.5), gem, Palette.col("hazard"))
	draw_circle(at + Vector2(0, -r * 0.8), gem * 1.3, Palette.col("friend"))
	draw_circle(at + Vector2(r, -r * 0.5), gem, Palette.col("accent"))
	draw_circle(at + Vector2(0, r * 0.15), gem * 1.2, Palette.col("player"))

func _text(f: Font, cx: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(cx - 160, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 320, size, col)
