extends GameMode
## bricks -- breakout, with things that fall out of the wall. Half of them help and half
## of them hurt, and you can tell which at a glance. See game/bricks/GAME.md.
##
## Swipe left and right to move. With a gun, tap or press space to shoot upward.

const PADDLE_Y := 330.0
const PADDLE_H := 7.0          ## half-height; Blob draws a square of side 2*radius
const PADDLE_W := 72.0         ## normal full width
const PADDLE_WIDE := 116.0
const PADDLE_NARROW := 44.0
const PADDLE_SPEED := 420.0

const BALL_R := 5.0
const BALL_START := 235.0
const BALL_MAX := 365.0
const LAUNCH_DELAY := 1.2      ## auto-launch, so nothing can ever sit stuck waiting

const COLS := 10
const BRICK_H := 16.0
const BRICK_TOP := 52.0
const BRICK_GAP := 3.0
const FIELD_MARGIN := 24.0

## The drops are the point of this game, so they have to actually turn up. At 0.16 a
## whole minute of play produced one.
const DROP_CHANCE := 0.24
const DROP_SPEED := 92.0
const DROP_W := 26.0
const DROP_H := 16.0
const BULLET_SPEED := 380.0
const FIRE_COOLDOWN := 0.35
const SFX_VOLUME := 0.28

## Everything that can fall out of a brick. `good` drives both the icon and the colour, so
## a drop reads as help-or-harm before you can read the letter on it.
const DROPS := [
	{"id": "wide",   "good": true,  "mark": "W", "secs": 14.0},
	{"id": "gun",    "good": true,  "mark": "G", "secs": 14.0},
	{"id": "triple", "good": true,  "mark": "3", "secs": 14.0},
	{"id": "slow",   "good": true,  "mark": "S", "secs": 10.0},
	{"id": "narrow", "good": false, "mark": "N", "secs": 10.0},
	{"id": "fast",   "good": false, "mark": "F", "secs": 8.0},
	{"id": "jam",    "good": false, "mark": "X", "secs": 0.0},
]

var paddle: Blob
var ball: Blob
var _bricks: Array = []        ## {rect, hp, row}
var _drops: Array = []         ## Blob, meta: id, good, mark
var _bullets: Array = []

var _ball_vel := Vector2.ZERO
var _stuck := true             ## sitting on the paddle, waiting to launch
var _stuck_t := 0.0
var _level := 0
var _speed := BALL_START
var _timers := {}              ## effect id -> seconds remaining
var _cool := 0.0
var _held := false
var _point := 0.0
var _sfx_was := 0.8

func _ready() -> void:
	title = "bricks"
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

	paddle = Blob.new()
	paddle.role = "player"
	paddle.shape = "square"
	paddle.radius = PADDLE_H
	add_child(paddle)
	paddle.position = Vector2(320, PADDLE_Y)
	Probe.track(paddle, "@")

	ball = Blob.new()
	ball.role = "warn"
	ball.radius = BALL_R
	add_child(ball)
	Probe.track(ball, "*")

	_next_level()

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- the wall --------------------------------------------------------------

func _next_level() -> void:
	_level += 1
	for d in _drops:
		if is_instance_valid(d):
			d.queue_free()
	_drops.clear()
	_timers.clear()

	var rows := clampi(2 + _level, 3, 7)
	var w := (play_area.size.x - FIELD_MARGIN * 2.0 - BRICK_GAP * (COLS - 1)) / float(COLS)
	_bricks.clear()
	for r in rows:
		for c in COLS:
			# a couple of rows of tougher bricks once the wall is deep enough
			var hp := 2 if _level >= 3 and r < 1 + (_level - 3) / 2 else 1
			_bricks.append({
				"rect": Rect2(FIELD_MARGIN + c * (w + BRICK_GAP),
					BRICK_TOP + r * (BRICK_H + BRICK_GAP), w, BRICK_H),
				"hp": hp, "row": r})

	_speed = minf(BALL_START + float(_level - 1) * 9.0, BALL_MAX)
	_reset_ball()
	Probe.event("level_start", {"level": _level, "bricks": _bricks.size(), "rows": rows})

func _reset_ball() -> void:
	_stuck = true
	_stuck_t = 0.0
	ball.position = paddle.position + Vector2(0, -BALL_R - PADDLE_H - 1.0)

func _launch() -> void:
	if not _stuck:
		return
	_stuck = false
	var a := randf_range(-0.5, 0.5)
	_ball_vel = Vector2(sin(a), -cos(a)) * _ball_speed()
	Audio.play("jump", 0.1, -4.0)

func _ball_speed() -> float:
	var s := _speed
	if _timers.has("slow"):
		s *= 0.72
	if _timers.has("fast"):
		s *= 1.32
	return s

## ---- play ------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	_cool = maxf(0.0, _cool - delta)
	_tick_timers(delta)
	_move_paddle(delta)

	if _stuck:
		ball.position = paddle.position + Vector2(0, -BALL_R - PADDLE_H - 1.0)
		_stuck_t += delta
		if PInput.just_pressed("action_a") or _held or _stuck_t >= LAUNCH_DELAY:
			_launch()
	else:
		_move_ball(delta)

	if _timers.has("gun") and (PInput.pressed("action_a") or _held) and _cool <= 0.0:
		_fire()

	_move_drops(delta)
	_move_bullets(delta)

func _tick_timers(delta: float) -> void:
	for id in _timers.keys():
		_timers[id] -= delta
		if _timers[id] <= 0.0:
			_timers.erase(id)

func _paddle_half() -> float:
	var w := PADDLE_W
	if _timers.has("wide"):
		w = PADDLE_WIDE
	elif _timers.has("narrow"):
		w = PADDLE_NARROW
	return w * 0.5

func _move_paddle(delta: float) -> void:
	var half := _paddle_half()
	paddle.scale = Vector2(half / PADDLE_H, 1.0)   # Blob draws a square; stretch it wide
	var dir := PInput.dir().x
	if dir != 0.0:
		paddle.position.x += dir * PADDLE_SPEED * delta
	elif _held:
		# swipe: the paddle chases your finger rather than teleporting under it
		var want: float = _point
		var step := PADDLE_SPEED * delta
		paddle.position.x += clampf(want - paddle.position.x, -step, step)
	paddle.position.x = clampf(paddle.position.x, half, play_area.size.x - half)

func _move_ball(delta: float) -> void:
	var speed := _ball_speed()
	_ball_vel = _ball_vel.normalized() * speed
	# step along each axis separately, so a brick can tell which face was hit
	_step_ball(Vector2(_ball_vel.x * delta, 0.0), true)
	# breaking the last brick starts the next level and parks the ball again; carrying on
	# would move the fresh ball off the paddle on the same frame
	if _stuck or finished:
		return
	_step_ball(Vector2(0.0, _ball_vel.y * delta), false)
	if _stuck or finished:
		return

	if ball.position.x < BALL_R:
		ball.position.x = BALL_R
		_ball_vel.x = absf(_ball_vel.x)
	elif ball.position.x > play_area.size.x - BALL_R:
		ball.position.x = play_area.size.x - BALL_R
		_ball_vel.x = -absf(_ball_vel.x)
	if ball.position.y < BALL_R:
		ball.position.y = BALL_R
		_ball_vel.y = absf(_ball_vel.y)

	_bounce_paddle()

	if ball.position.y > play_area.size.y + 20.0:
		Probe.event("ball_lost", {"level": _level})
		lose_life()
		if not finished:
			_reset_ball()

## Bounce off the paddle at an angle set by WHERE it hit: the middle sends it back up,
## the edges send it out wide. That is the whole steering mechanism in breakout.
func _bounce_paddle() -> void:
	if _ball_vel.y <= 0.0:
		return
	var half := _paddle_half()
	if absf(ball.position.x - paddle.position.x) > half + BALL_R:
		return
	if absf(ball.position.y - PADDLE_Y) > PADDLE_H + BALL_R:
		return
	var off := clampf((ball.position.x - paddle.position.x) / half, -1.0, 1.0)
	var a := off * 1.05
	_ball_vel = Vector2(sin(a), -cos(a)) * _ball_speed()
	ball.position.y = PADDLE_Y - PADDLE_H - BALL_R - 0.5
	Audio.play("impact_soft", 0.15, -6.0)
	Juice.shake(1.2)

func _step_ball(step: Vector2, horizontal: bool) -> void:
	ball.position += step
	var hit := _brick_at(ball.position)
	if hit < 0:
		return
	if horizontal:
		_ball_vel.x = -_ball_vel.x
	else:
		_ball_vel.y = -_ball_vel.y
	ball.position -= step
	_damage_brick(hit)

func _brick_at(p: Vector2) -> int:
	for i in _bricks.size():
		if _bricks[i]["rect"].grow(BALL_R * 0.8).has_point(p):
			return i
	return -1

func _damage_brick(i: int) -> void:
	var b: Dictionary = _bricks[i]
	b["hp"] = int(b["hp"]) - 1
	if int(b["hp"]) > 0:
		Audio.play("impact_light", 0.15, -4.0)
		return
	var r: Rect2 = b["rect"]
	add_score(10)
	Audio.play("impact_wood", 0.2, -3.0)
	Juice.shake(1.6)
	_bricks.remove_at(i)
	if randf() < DROP_CHANCE:
		_spawn_drop(r.get_center())
	if _bricks.is_empty():
		add_score(100)
		Audio.play("voice_level_up")
		Probe.event("level_clear", {"level": _level})
		_next_level()

## ---- things that fall ------------------------------------------------------

func _spawn_drop(at: Vector2) -> void:
	var kind: Dictionary = DROPS[randi() % DROPS.size()]
	var d := Blob.new()
	# shape and colour both carry the meaning, so it reads instantly and still reads for
	# anyone who cannot pick the colours apart
	d.role = "prize" if kind["good"] else "hazard"
	d.shape = "diamond" if kind["good"] else "square"
	d.radius = 9.0
	# behind this node's own _draw(), so the + / - sign lands ON the capsule. A child Blob
	# draws after its parent, so at the default z the sign was hidden underneath it.
	d.z_index = -1
	add_child(d)
	d.position = at
	d.set_meta("id", kind["id"])
	d.set_meta("good", kind["good"])
	d.set_meta("mark", kind["mark"])
	d.set_meta("secs", kind["secs"])
	_drops.append(d)
	Probe.track(d, "*" if kind["good"] else "x")
	Probe.event("drop_spawn", {"id": kind["id"], "good": kind["good"]})

func _move_drops(delta: float) -> void:
	var keep: Array = []
	for d in _drops:
		if not is_instance_valid(d):
			continue
		d.position.y += DROP_SPEED * delta
		if absf(d.position.x - paddle.position.x) < _paddle_half() + DROP_W * 0.4 \
				and absf(d.position.y - PADDLE_Y) < PADDLE_H + DROP_H * 0.5:
			_collect(d)
			d.queue_free()
			continue
		if d.position.y > play_area.size.y + 20.0:
			d.queue_free()
			continue
		keep.append(d)
	_drops = keep

func _collect(d: Blob) -> void:
	var id: String = d.get_meta("id")
	var good: bool = d.get_meta("good")
	if id == "jam":
		_timers.erase("gun")
		_timers.erase("triple")
	else:
		_timers[id] = float(d.get_meta("secs"))
		if id == "wide":
			_timers.erase("narrow")
		elif id == "narrow":
			_timers.erase("wide")
		elif id == "slow":
			_timers.erase("fast")
		elif id == "fast":
			_timers.erase("slow")
	if good:
		add_score(20)
	Audio.play("coin" if good else "impact_metal", 0.2, -3.0)
	Juice.pop(paddle, 1.2, 0.2)
	Juice.text(self, paddle.position + Vector2(-22, -34), id.to_upper(),
		Palette.col("prize" if good else "hazard"))
	Probe.event("drop_taken", {"id": id, "good": good})

## ---- shooting --------------------------------------------------------------

func _fire() -> void:
	_cool = FIRE_COOLDOWN
	var spread: Array = [0.0] if not _timers.has("triple") else [-0.26, 0.0, 0.26]
	for a in spread:
		var b := Blob.new()
		b.role = "friend"
		b.radius = 2.5
		add_child(b)
		b.position = paddle.position + Vector2(0, -PADDLE_H - 3.0)
		b.set_meta("vel", Vector2(sin(a), -cos(a)) * BULLET_SPEED)
		_bullets.append(b)
		Probe.track(b, "!")
	Audio.play("click", 0.25, -8.0)
	Probe.event("shot")

func _move_bullets(delta: float) -> void:
	var keep: Array = []
	for b in _bullets:
		if not is_instance_valid(b):
			continue
		b.position += b.get_meta("vel") * delta
		var hit := _brick_at(b.position)
		if hit >= 0:
			_damage_brick(hit)
			b.queue_free()
			continue
		if b.position.y < -10.0:
			b.queue_free()
			continue
		keep.append(b)
	_bullets = keep

## ---- input -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if finished or Flow.pointer_over_hud():
		_held = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_held = mb.pressed
			_point = get_global_mouse_position().x
	elif event is InputEventMouseMotion and _held:
		_point = get_global_mouse_position().x

## ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	for b in _bricks:
		var r: Rect2 = b["rect"]
		var palette: Array = ["accent", "prize", "friend", "warn", "player", "accent", "prize"]
		var role: String = "hazard" if int(b["hp"]) > 1 else palette[int(b["row"]) % 7]
		draw_rect(r, Palette.col(role))
		draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)),
			Color(1, 1, 1, 0.25 if int(b["hp"]) > 1 else 0.14))

	for d in _drops:
		if is_instance_valid(d):
			_draw_drop(d)

	var f2 := _timers.keys()
	f2.sort()
	var line := "  ".join(f2)
	draw_string(f, Vector2(120, 22), "level %d" % _level, HORIZONTAL_ALIGNMENT_CENTER,
		400, 13, Palette.col("accent"))
	if line != "":
		draw_string(f, Vector2(120, 352), line, HORIZONTAL_ALIGNMENT_CENTER, 400, 12,
			Palette.col("ink"))

## The sign is the important part -- a plus or a minus, big, before you read anything else.
func _draw_drop(d: Blob) -> void:
	var good: bool = d.get_meta("good")
	var col := Palette.col("prize" if good else "hazard")
	var p: Vector2 = d.position
	var arm := 5.5
	var white := Color(1, 1, 1, 0.98)
	draw_line(p + Vector2(-arm, 0), p + Vector2(arm, 0), white, 3.0)
	if good:
		draw_line(p + Vector2(0, -arm), p + Vector2(0, arm), white, 3.0)
	var f: Font = ThemeDB.fallback_font
	draw_string(f, p + Vector2(-20, 20), d.get_meta("mark"), HORIZONTAL_ALIGNMENT_CENTER,
		40, 11, col)
