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
const MAX_BALLS := 5
const SPLIT_ANGLE := 0.55      ## radians a split ball fans out from the one it came from

const COLS := 10
const BRICK_H := 16.0
const BRICK_TOP := 52.0
const BRICK_GAP := 3.0
const FIELD_MARGIN := 24.0
## Reaches a brick's 8 grid neighbours and no further. Column pitch at COLS=10 works out
## to ~59.5px centre-to-centre and row pitch to 19px, so the diagonal neighbour sits at
## ~62.5px -- the first radius I picked (42) only ever reached straight up/down and missed
## the brick beside it in the very same row, which is not what "explodes" should mean.
const EXPLODE_RADIUS := 66.0

## The drops are the point of this game, so they have to actually turn up. At 0.16 a
## whole minute of play produced one.
const DROP_CHANCE := 0.24
const DROP_SPEED := 92.0
const DROP_W := 26.0
const DROP_H := 16.0
const BULLET_SPEED := 380.0
const FIRE_COOLDOWN := 0.35
const SFX_VOLUME := 0.28
const MUSIC_VOLUME := 0.22
const MUSIC_TRACK := "jingle_2"

## Everything that can fall out of a brick. `good` drives both the icon and the colour, so
## a drop reads as help-or-harm before you can read the letter on it. "multi" has no
## duration -- it fires once, on the spot, rather than living in _timers.
const DROPS := [
	{"id": "wide",   "good": true,  "mark": "W", "secs": 14.0},
	{"id": "gun",    "good": true,  "mark": "G", "secs": 14.0},
	{"id": "triple", "good": true,  "mark": "3", "secs": 14.0},
	{"id": "slow",   "good": true,  "mark": "S", "secs": 10.0},
	{"id": "multi",  "good": true,  "mark": "M", "secs": 0.0},
	{"id": "narrow", "good": false, "mark": "N", "secs": 10.0},
	{"id": "fast",   "good": false, "mark": "F", "secs": 8.0},
	{"id": "jam",    "good": false, "mark": "X", "secs": 0.0},
]

var paddle: Blob
var _balls: Array = []         ## Blob, meta "vel" -- see notes above _move_balls()
var _bricks: Array = []        ## {rect, hp, row, type}: type is normal/tough/steel/bomb
var _drops: Array = []         ## Blob, meta: id, good, mark
var _bullets: Array = []
var _bits: Array = []          ## small debris chips, purely decorative
var _trail: Array = []         ## {pos, life} -- a fading smear behind every ball

var _stuck := true             ## sitting on the paddle, waiting to launch
var _stuck_t := 0.0
var _level := 0
var _speed := BALL_START
var _timers := {}              ## effect id -> seconds remaining
var _cool := 0.0
var _held := false
var _point := 0.0
var _drag_from := 0.0
var _drag_base := 0.0
var _sfx_was := 0.8
var _music_was := 0.7

func _ready() -> void:
	title = "bricks"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = SFX_VOLUME
	_music_was = float(SaveData.data.get("volume_music", 0.7))
	SaveData.data["volume_music"] = MUSIC_VOLUME

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

	_balls = [_make_ball()]

	_next_level()

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	SaveData.data["volume_music"] = _music_was
	Audio.stop_music()

func _make_ball() -> Blob:
	var b := Blob.new()
	b.role = "warn"
	b.radius = BALL_R
	add_child(b)
	b.set_meta("vel", Vector2.ZERO)
	Probe.track(b, "*")
	return b

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
			var type := _brick_type_for(r)
			_bricks.append({
				"rect": Rect2(FIELD_MARGIN + c * (w + BRICK_GAP),
					BRICK_TOP + r * (BRICK_H + BRICK_GAP), w, BRICK_H),
				"hp": 2 if type == "tough" else 1, "row": r, "type": type})

	_speed = minf(BALL_START + float(_level - 1) * 9.0, BALL_MAX)
	_reset_ball()
	Probe.event("level_start", {"level": _level, "bricks": _bricks.size(), "rows": rows})

## Steel (unbreakable) and bomb (explodes its neighbours) start turning up from level 2,
## sparsely at first so the ramp stays fair. Tough (2-hit) keeps its old rule: the top rows
## once the wall is deep enough. Priority order matters -- a brick is only ever one type.
func _brick_type_for(row: int) -> String:
	if _level >= 2 and randf() < clampf(0.03 + float(_level) * 0.012, 0.03, 0.11):
		return "steel"
	if _level >= 2 and randf() < clampf(0.035 + float(_level) * 0.01, 0.035, 0.09):
		return "bomb"
	if _level >= 3 and row < 1 + (_level - 3) / 2:
		return "tough"
	return "normal"

## True while at least one brick still needs breaking. Steel bricks never count -- without
## this a wall that rolled even one of them could never be cleared.
func _breakable_left() -> bool:
	for b in _bricks:
		if b["type"] != "steel":
			return true
	return false

## Every ball is parked and this one becomes the single stuck ball waiting to launch.
## Anything mid-flight from a multi-ball split is gone -- a fresh level is a fresh start.
func _reset_ball() -> void:
	for b in _balls:
		if is_instance_valid(b):
			b.queue_free()
	_balls = [_make_ball()]
	_stuck = true
	_stuck_t = 0.0
	_balls[0].position = paddle.position + Vector2(0, -BALL_R - PADDLE_H - 1.0)

func _launch() -> void:
	if not _stuck or _balls.is_empty():
		return
	_stuck = false
	var a := randf_range(-0.5, 0.5)
	_balls[0].set_meta("vel", Vector2(sin(a), -cos(a)) * _ball_speed())
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
	# Godot's ogg jingles are not set to loop, and touching that shared import setting
	# would also loop them wherever else they play (menu wins, other games' stings). This
	# reissues playback once the clip ends instead -- Audio.music() no-ops while it is
	# still going, so calling it every frame is cheap and does not touch shared assets.
	Audio.music(MUSIC_TRACK)

	_cool = maxf(0.0, _cool - delta)
	_tick_timers(delta)
	_tick_trail(delta)
	_move_paddle(delta)

	if _stuck:
		if not _balls.is_empty():
			_balls[0].position = paddle.position + Vector2(0, -BALL_R - PADDLE_H - 1.0)
		_stuck_t += delta
		if PInput.just_pressed("action_a") or _held or _stuck_t >= LAUNCH_DELAY:
			_launch()
	else:
		_move_balls(delta)

	if _timers.has("gun") and (PInput.pressed("action_a") or _held) and _cool <= 0.0:
		_fire()

	_move_drops(delta)
	_move_bullets(delta)
	_move_bits(delta)

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

## One ball or several, all handled the same way. Bails out the moment `finished` or
## `_stuck` flips true partway through: breaking the last brick starts the next level and
## re-parks a fresh single ball, and the rest of this frame's snapshot would then be
## touching freed nodes from the level that just ended.
func _move_balls(delta: float) -> void:
	var speed := _ball_speed()
	for b in _balls.duplicate():
		if not is_instance_valid(b):
			continue
		var v: Vector2 = b.get_meta("vel", Vector2.ZERO)
		if v == Vector2.ZERO:
			continue
		v = v.normalized() * speed
		b.set_meta("vel", v)
		_trail.append({"pos": b.position, "life": 1.0})

		# step along each axis separately, so a brick can tell which face was hit
		_step_ball(b, Vector2(v.x * delta, 0.0), true)
		if _stuck or finished:
			return
		v = b.get_meta("vel")
		_step_ball(b, Vector2(0.0, v.y * delta), false)
		if _stuck or finished:
			return

		v = b.get_meta("vel")
		if b.position.x < BALL_R:
			b.position.x = BALL_R
			v.x = absf(v.x)
		elif b.position.x > play_area.size.x - BALL_R:
			b.position.x = play_area.size.x - BALL_R
			v.x = -absf(v.x)
		if b.position.y < BALL_R:
			b.position.y = BALL_R
			v.y = absf(v.y)
		b.set_meta("vel", v)

		_bounce_paddle(b)

		if b.position.y > play_area.size.y + 20.0:
			_balls.erase(b)
			b.queue_free()
			Probe.event("ball_lost", {"level": _level, "balls_left": _balls.size()})
			if _balls.is_empty():
				lose_life()
				if not finished:
					_reset_ball()
				return

## Bounce off the paddle at an angle set by WHERE it hit: the middle sends it back up,
## the edges send it out wide. That is the whole steering mechanism in breakout.
func _bounce_paddle(b: Blob) -> void:
	var v: Vector2 = b.get_meta("vel")
	if v.y <= 0.0:
		return
	var half := _paddle_half()
	if absf(b.position.x - paddle.position.x) > half + BALL_R:
		return
	if absf(b.position.y - PADDLE_Y) > PADDLE_H + BALL_R:
		return
	var off := clampf((b.position.x - paddle.position.x) / half, -1.0, 1.0)
	var a := off * 1.05
	b.set_meta("vel", Vector2(sin(a), -cos(a)) * _ball_speed())
	b.position.y = PADDLE_Y - PADDLE_H - BALL_R - 0.5
	Audio.play("impact_soft", 0.15, -6.0)
	Juice.shake(1.2)

func _step_ball(b: Blob, step: Vector2, horizontal: bool) -> void:
	b.position += step
	var hit := _brick_at(b.position)
	if hit < 0:
		return
	var v: Vector2 = b.get_meta("vel")
	if horizontal:
		v.x = -v.x
	else:
		v.y = -v.y
	b.set_meta("vel", v)
	b.position -= step
	_damage_brick(hit)

func _brick_at(p: Vector2) -> int:
	for i in _bricks.size():
		if _bricks[i]["rect"].grow(BALL_R * 0.8).has_point(p):
			return i
	return -1

func _damage_brick(i: int) -> void:
	var b: Dictionary = _bricks[i]
	if b["type"] == "steel":
		Audio.play("impact_metal", 0.1, -8.0)
		Juice.shake(0.8)
		return
	b["hp"] = int(b["hp"]) - 1
	if int(b["hp"]) > 0:
		Audio.play("impact_light", 0.15, -4.0)
		return
	var r: Rect2 = b["rect"]
	var was_bomb: bool = b["type"] == "bomb"
	add_score(10)
	Audio.play("impact_wood", 0.2, -3.0)
	Juice.shake(1.6)
	_puff(r.get_center(), "friend", 5)
	_bricks.remove_at(i)
	if randf() < DROP_CHANCE:
		_spawn_drop(r.get_center())
	if was_bomb:
		Probe.event("bomb_triggered", {"level": _level})
		_explode(r.get_center())
	if not _breakable_left():
		add_score(100)
		Audio.play("voice_level_up")
		Probe.event("level_clear", {"level": _level})
		_next_level()

## A bomb brick takes every non-steel brick within EXPLODE_RADIUS with it -- roughly its
## grid neighbours -- regardless of how tough they were. Another bomb in range chains into
## its own explosion, which is why this recurses. remove_at() is safe here because each
## exploding brick is popped by index before the recursive call, and the recursive call
## only ever sees indices that still exist at the moment it runs.
func _explode(at: Vector2) -> void:
	var hit: Array = []
	for i in _bricks.size():
		var b: Dictionary = _bricks[i]
		if b["type"] == "steel":
			continue
		if b["rect"].get_center().distance_to(at) <= EXPLODE_RADIUS:
			hit.append(i)
	if hit.is_empty():
		return
	hit.sort()
	hit.reverse()
	for i in hit:
		var b: Dictionary = _bricks[i]
		var r: Rect2 = b["rect"]
		var chains: bool = b["type"] == "bomb"
		_bricks.remove_at(i)
		add_score(6)
		if chains:
			_explode(r.get_center())
	Audio.play("explode", 0.2, -3.0)
	Juice.shake(4.0)
	_puff(at, "hazard", 12)
	if not _breakable_left():
		add_score(100)
		Audio.play("voice_level_up")
		Probe.event("level_clear", {"level": _level})
		_next_level()

## ---- debris, purely decorative -----------------------------------------------

func _puff(at: Vector2, role: String, n: int) -> void:
	for i in n:
		var d := Blob.new()
		d.role = role
		d.radius = randf_range(1.5, 3.0)
		add_child(d)
		d.position = at
		d.set_meta("vel", Vector2(randf_range(-110, 110), randf_range(-140, -20)))
		_bits.append(d)

func _move_bits(delta: float) -> void:
	var keep: Array = []
	for d in _bits:
		if not is_instance_valid(d):
			continue
		var v: Vector2 = d.get_meta("vel")
		v.y += 300.0 * delta
		d.set_meta("vel", v)
		d.position += v * delta
		d.modulate.a = maxf(0.0, d.modulate.a - delta * 1.6)
		if d.modulate.a <= 0.03 or d.position.y > play_area.size.y:
			d.queue_free()
			continue
		keep.append(d)
	_bits = keep

func _tick_trail(delta: float) -> void:
	var keep: Array = []
	for t in _trail:
		t["life"] -= delta * 2.6
		if t["life"] > 0.0:
			keep.append(t)
	_trail = keep

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
	elif id == "multi":
		_split_balls()
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

## Fans up to two new balls out of whichever ball is currently in flight, at an angle
## either side of its own direction. Caught while the ball is still parked on the paddle
## it does nothing -- there is no direction to split from yet. Capped at MAX_BALLS so a
## run of good luck cannot spawn an unplayable swarm.
func _split_balls() -> void:
	if _stuck or _balls.is_empty():
		return
	var base: Blob = _balls[randi() % _balls.size()]
	var v: Vector2 = base.get_meta("vel", Vector2.ZERO)
	if v == Vector2.ZERO:
		return
	var speed := v.length()
	var base_a := v.angle()
	var room := MAX_BALLS - _balls.size()
	for i in mini(2, room):
		var off := SPLIT_ANGLE * float(i + 1) * (1.0 if i % 2 == 0 else -1.0)
		var nb := _make_ball()
		nb.position = base.position
		nb.set_meta("vel", Vector2.from_angle(base_a + off) * speed)
		_balls.append(nb)
	Juice.pop(base, 1.4, 0.2)
	Audio.play("voice_power_up")

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
			if mb.pressed:
				# Relative drag, not absolute position. The old version snapped the target
				# straight to the touch point, so a tap anywhere on the field yanked the
				# paddle toward it -- a tap that never moves the finger should never move
				# the paddle. Recording where the drag started and where the paddle was
				# means a stationary tap asks for zero movement, and a small drag asks for
				# a proportionally small one.
				_drag_from = get_global_mouse_position().x
				_drag_base = paddle.position.x
				_point = _drag_base
	elif event is InputEventMouseMotion and _held:
		_point = _drag_base + (get_global_mouse_position().x - _drag_from)

## ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	_draw_backdrop()
	_draw_trail()

	var f: Font = ThemeDB.fallback_font
	for b in _bricks:
		_draw_brick(b)

	for d in _drops:
		if is_instance_valid(d):
			_draw_drop(d)

	var f2 := _timers.keys()
	f2.sort()
	var line := "  ".join(f2)
	if _balls.size() > 1:
		line = ("balls x%d   " % _balls.size()) + line
	draw_string(f, Vector2(120, 22), "level %d" % _level, HORIZONTAL_ALIGNMENT_CENTER,
		400, 13, Palette.col("accent"))
	if line != "":
		draw_string(f, Vector2(120, 352), line, HORIZONTAL_ALIGNMENT_CENTER, 400, 12,
			Palette.col("ink"))

## A soft panel behind the wall and a glow along the two walls the ball bounces off --
## the shared starfield behind every game is nice but flat on its own, and this gives the
## arena an edge to play inside rather than an unbounded field.
func _draw_backdrop() -> void:
	var alt := Palette.col("bg_alt")
	var accent := Palette.col("accent")
	draw_rect(Rect2(0, BRICK_TOP - 14.0, play_area.size.x, play_area.size.y - BRICK_TOP + 14.0),
		Color(alt.r, alt.g, alt.b, 0.16))
	for x in [3.0, play_area.size.x - 3.0]:
		draw_rect(Rect2(x - 1.5, 0, 3.0, play_area.size.y), Color(accent.r, accent.g, accent.b, 0.3))

func _draw_trail() -> void:
	var c := Palette.col("warn")
	for t in _trail:
		var a: float = t["life"] * 0.22
		draw_circle(t["pos"], BALL_R * (0.5 + t["life"] * 0.5), Color(c.r, c.g, c.b, a))

func _draw_brick(b: Dictionary) -> void:
	var r: Rect2 = b["rect"]
	var type: String = b["type"]
	match type:
		"steel":
			# a blocked-out panel, not a coloured brick -- the hatch reads as "immovable"
			# even for someone who cannot separate the hue from the wall behind it
			var ink := Palette.col("ink")
			draw_rect(r, Color(ink.r, ink.g, ink.b, 0.16))
			draw_rect(r, Color(ink.r, ink.g, ink.b, 0.5), false, 1.5)
			var step := 6.0
			var x := r.position.x - r.size.y
			while x < r.end.x:
				var p1 := Vector2(maxf(x, r.position.x), minf(r.end.y, r.position.y + (r.end.x - x)))
				var p2 := Vector2(minf(x + r.size.y, r.end.x), maxf(r.position.y, r.end.y - (x + r.size.y - r.position.x)))
				if p1.distance_to(p2) > 1.0:
					draw_line(p1, p2, Color(ink.r, ink.g, ink.b, 0.35), 1.5)
				x += step
		"bomb":
			var warn := Palette.col("warn")
			draw_rect(r, warn)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)), Color(1, 1, 1, 0.2))
			_draw_spark(r.get_center(), Palette.col("bg"))
		_:
			var role: String = "hazard" if type == "tough" else \
				["accent", "prize", "friend", "player"][int(b["row"]) % 4]
			draw_rect(r, Palette.col(role))
			var top_hp := int(b["hp"])
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2.0)),
				Color(1, 1, 1, 0.25 if top_hp > 1 else 0.14))
			if type == "tough" and top_hp == 1:
				# damaged once already -- a crack across the middle to show it
				draw_line(r.position + Vector2(0, r.size.y * 0.5),
					r.end - Vector2(0, r.size.y * 0.5), Color(0, 0, 0, 0.35), 1.5)

## A little four-point spark, drawn with lines rather than a font glyph so it always
## renders the same regardless of what the fallback font happens to cover.
func _draw_spark(p: Vector2, col: Color) -> void:
	var a := 5.0
	draw_line(p + Vector2(-a, -a), p + Vector2(a, a), col, 2.0)
	draw_line(p + Vector2(-a, a), p + Vector2(a, -a), col, 2.0)
	draw_line(p + Vector2(0, -a * 1.3), p + Vector2(0, a * 1.3), col, 2.0)

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
