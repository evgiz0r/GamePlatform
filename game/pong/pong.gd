extends GameMode
## pong -- you against the machine, first to five. Five machines, each a little sharper.
## See game/pong/GAME.md.
##
## Drag anywhere to move the paddle (it follows the drag, not the touch point), or use
## up/down. Where the ball meets the paddle sets the return angle; paddle movement adds spin.

## One entry per opponent. speed: how fast its paddle can move. spread: how far off its
## aim is at serve speed (it misses once the error passes the paddle's half-height, ~35).
## tire: extra error per px/s the ball has gained this rally -- fast rallies make it
## sloppy. react: how far across the field (0 = your goal, 1 = its goal) the ball has to
## come before it starts tracking. predict: reads the bounce off the walls rather than
## chasing where the ball is right now. serve: ball speed at the start of each point.
const LEVELS := [
	{"name": "rookie", "speed": 190.0, "spread": 36.0, "tire": 0.18, "react": 0.58, "predict": false, "serve": 330.0},
	{"name": "steady", "speed": 230.0, "spread": 30.0, "tire": 0.15, "react": 0.50, "predict": false, "serve": 345.0},
	{"name": "sharp",  "speed": 260.0, "spread": 26.0, "tire": 0.13, "react": 0.50, "predict": true,  "serve": 360.0},
	{"name": "ace",    "speed": 295.0, "spread": 22.0, "tire": 0.11, "react": 0.42, "predict": true,  "serve": 375.0},
	{"name": "wall",   "speed": 335.0, "spread": 16.0, "tire": 0.08, "react": 0.35, "predict": true,  "serve": 390.0},
]

const POINTS_TO_WIN := 5

const FIELD_TOP := 40.0        ## below the shell's HUD row
const FIELD_BOTTOM := 352.0
const PLAYER_X := 26.0
const CPU_X := 614.0
const PAD_HW := 5.0            ## half-width; Blob draws a square of side 2*radius
const PAD_HH := 30.0           ## half-height
const PAD_SPEED := 470.0       ## keyboard / bot speed. A drag moves it directly.

const BALL_R := 5.0
const BALL_GAIN := 18.0        ## px/s added on every paddle hit
const BALL_MAX := 720.0
const MAX_ANGLE := 0.95        ## radians off horizontal when hit on the very end
const MIN_VX := 0.42           ## fraction of speed that must stay horizontal
const SPIN := 0.16             ## fraction of the paddle's own speed passed into the ball
const STEEP_ERR := 0.6         ## how much a steep shot throws off the machine's aim
const SERVE_DELAY := 1.0
const MATCH_DELAY := 1.8       ## banner time before a match's first serve
const RALLY_BONUS_EVERY := 10

## Fraction of whatever volume is currently set, not an absolute level. See CLAUDE.md,
## "things this kit learned the hard way".
const SFX_SCALE := 0.35
const MUSIC_SCALE := 0.31
const MUSIC_TRACK := "chiptune_battle"

var _me: Blob
var _cpu: Blob
var _ball: Blob
var _vel := Vector2.ZERO
var _speed := 330.0

var _level := 1
var _cfg: Dictionary = {}
var _my_pts := 0
var _cpu_pts := 0
var _rally := 0

## "serve": ball parked in the middle, counting down. "play": in flight.
## "between": a match just ended, banner up, next one about to start.
var _state := "serve"
var _state_t := 0.0
var _serve_dir := -1.0         ## -1 toward you, +1 toward the machine

var _cpu_aim := 0.0            ## where on its paddle the machine means to meet the ball
var _me_vy := 0.0
var _cpu_vy := 0.0
var _sq_me := 0.0              ## squash amounts, decay to zero
var _sq_cpu := 0.0

var _drag := false
var _drag_from := 0.0          ## pointer y when the drag started
var _drag_now := 0.0
var _pad_from := 0.0           ## paddle y when the drag started

var _trail: Array = []         ## {pos, life}
var _bits: Array = []          ## decorative sparks (Blob, meta "vel")
var _goal_flash := 0.0         ## >0 left goal flashing, <0 right goal flashing
var _banner := ""
var _banner_sub := ""
var _banner_t := 0.0
var _banner_role := "accent"

var _sfx_was := 0.8
var _music_was := 0.7

func _ready() -> void:
	title = "pong"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_music_was = float(SaveData.data.get("volume_music", 0.7))
	SaveData.data["volume_music"] = _music_was * MUSIC_SCALE

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	_me = _make_paddle("player", PLAYER_X)
	_cpu = _make_paddle("hazard", CPU_X)
	Probe.track(_me, "@")
	Probe.track(_cpu, "x")

	_ball = Blob.new()
	_ball.role = "warn"
	_ball.radius = BALL_R
	add_child(_ball)
	_ball.position = center()
	Probe.track(_ball, "*")

	_begin_level(clampi(int(config.get("level", 1)), 1, LEVELS.size()))

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	SaveData.data["volume_music"] = _music_was
	Audio.stop_music()

func _make_paddle(role: String, x: float) -> Blob:
	var p := Blob.new()
	p.role = role
	p.shape = "square"
	p.radius = PAD_HW
	add_child(p)
	p.position = Vector2(x, _mid_y())
	p.scale = Vector2(1.0, PAD_HH / PAD_HW)
	return p

func _mid_y() -> float:
	return (FIELD_TOP + FIELD_BOTTOM) * 0.5

## ---- matches and serves ------------------------------------------------------

func _begin_level(n: int) -> void:
	_level = n
	Flow.current_config["level"] = n
	_cfg = LEVELS[n - 1]
	_my_pts = 0
	_cpu_pts = 0
	set_lives(POINTS_TO_WIN)
	_me.position.y = _mid_y()
	_cpu.position.y = _mid_y()
	_pad_from = _me.position.y
	_drag_from = _drag_now
	_show_banner("vs " + str(_cfg["name"]).to_upper(),
		"match %d of %d  -  first to %d" % [n, LEVELS.size(), POINTS_TO_WIN], "hazard", MATCH_DELAY)
	Audio.play("voice_ready", 0.0, -4.0)
	Probe.event("match_start", {"level": n, "opponent": _cfg["name"]})
	_setup_serve(-1.0, MATCH_DELAY)

func _setup_serve(dir: float, wait: float = SERVE_DELAY) -> void:
	_state = "serve"
	_state_t = wait
	_serve_dir = dir
	_rally = 0
	_speed = float(_cfg["serve"])
	_vel = Vector2.ZERO
	_ball.position = Vector2(320.0, _mid_y() + randf_range(-40.0, 40.0))
	_ball.scale = Vector2.ONE
	_roll_cpu_aim()

func _launch() -> void:
	_state = "play"
	_ball.scale = Vector2.ONE
	var a := randf_range(-0.45, 0.45)
	_vel = Vector2(_serve_dir * cos(a), sin(a)) * _speed
	Audio.play("click", 0.1, -6.0)
	Probe.event("serve", {"toward": "you" if _serve_dir < 0.0 else "machine"})

## The machine picks a spot on its paddle to meet the ball with -- mostly aiming for an
## angle, but the faster this rally has got, the wider that guess, and past the paddle's
## half-height it simply misses. A steep shot (one you hit off the end of your paddle)
## widens it further: that is what makes aiming worth it against the sharper machines,
## which can otherwise reach anything.
func _roll_cpu_aim() -> void:
	var gained := maxf(0.0, _speed - float(_cfg["serve"]))
	var spread := float(_cfg["spread"]) + gained * float(_cfg["tire"])
	if absf(_vel.x) > 1.0:
		spread *= 1.0 + absf(_vel.y / _vel.x) * STEEP_ERR
	_cpu_aim = randf_range(-1.0, 1.0) * spread

func _point(you_won: bool) -> void:
	_trail.clear()
	if you_won:
		_my_pts += 1
		add_score(10 * _level)
		_goal_flash = -1.0
		_burst(Vector2(play_area.size.x, _ball.position.y), "player", 18, -1.0)
		Audio.play("coin", 0.1, -2.0)
		Juice.hit(4.0)
		Juice.text(self, Vector2(260, 150), "POINT  +%d" % (10 * _level), Palette.col("player"))
		Probe.event("point_won", {"you": _my_pts, "machine": _cpu_pts, "rally": _rally})
		if _my_pts >= POINTS_TO_WIN:
			_match_won()
			return
		_setup_serve(1.0)
	else:
		_cpu_pts += 1
		_goal_flash = 1.0
		_burst(Vector2(0.0, _ball.position.y), "hazard", 18, 1.0)
		Probe.event("point_lost", {"you": _my_pts, "machine": _cpu_pts, "rally": _rally})
		lose_life()
		if finished:
			return
		_setup_serve(-1.0)

func _match_won() -> void:
	add_score(50 * _level)
	Probe.event("match_won", {"level": _level, "opponent": _cfg["name"], "lost": _cpu_pts})
	if _level >= LEVELS.size():
		Audio.play("voice_congratulations")
		win()
		return
	Audio.play("voice_level_up")
	_show_banner("beat " + str(_cfg["name"]).to_upper() + "!",
		"+%d" % (50 * _level), "player", MATCH_DELAY)
	_state = "between"
	_state_t = MATCH_DELAY
	_vel = Vector2.ZERO
	_ball.position = Vector2(320.0, _mid_y())

func _show_banner(big: String, small: String, role: String, secs: float) -> void:
	_banner = big
	_banner_sub = small
	_banner_role = role
	_banner_t = secs

## ---- per frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	queue_redraw()
	# no-ops while the track is playing, restarts it once it ends -- a loop. See CLAUDE.md.
	Audio.music(MUSIC_TRACK)

	_banner_t = maxf(0.0, _banner_t - delta)
	_goal_flash = move_toward(_goal_flash, 0.0, delta * 1.8)
	_sq_me = move_toward(_sq_me, 0.0, delta * 5.0)
	_sq_cpu = move_toward(_sq_cpu, 0.0, delta * 5.0)
	_tick_trail(delta)
	_move_bits(delta)

	_move_me(delta)
	_move_cpu(delta)

	match _state:
		"serve":
			_state_t -= delta
			# a slow pulse while it waits, so the eye finds it before it moves
			var s := 1.0 + 0.25 * sin(_state_t * 14.0)
			_ball.scale = Vector2(s, s)
			if _state_t <= 0.0 or (PInput.just_pressed("action_a") and _banner_t <= 0.0):
				_launch()
		"play":
			_move_ball(delta)
		"between":
			_state_t -= delta
			if _state_t <= 0.0:
				_begin_level(_level + 1)

	_me.scale = Vector2(1.0 + _sq_me * 0.9, PAD_HH / PAD_HW * (1.0 - _sq_me * 0.18))
	_cpu.scale = Vector2(1.0 + _sq_cpu * 0.9, PAD_HH / PAD_HW * (1.0 - _sq_cpu * 0.18))

func _clamp_pad(y: float) -> float:
	return clampf(y, FIELD_TOP + PAD_HH, FIELD_BOTTOM - PAD_HH)

func _move_me(delta: float) -> void:
	var was := _me.position.y
	var dy := PInput.dir().y
	var y := was
	if dy != 0.0:
		y += dy * PAD_SPEED * delta
		# keys took over mid-drag: re-anchor so the drag carries on from here, not jumps back
		_drag_from = _drag_now
		_pad_from = y
	elif _drag:
		y = _pad_from + (_drag_now - _drag_from)
	var c := _clamp_pad(y)
	if _drag and c != y:
		# dragged past the wall: slide the anchor along, so reversing moves it at once
		# instead of first having to "unwind" the overshoot
		_pad_from += c - y
	_me.position.y = c
	_me_vy = (c - was) / maxf(delta, 0.001)

func _move_cpu(delta: float) -> void:
	var was := _cpu.position.y
	var target := _mid_y()
	var speed := float(_cfg["speed"])
	var coming := _state == "play" and _vel.x > 0.0
	if coming and _ball.position.x > play_area.size.x * float(_cfg["react"]):
		var ty := _predict_y(CPU_X - PAD_HW - BALL_R) if _cfg["predict"] else _ball.position.y
		target = ty + _cpu_aim
	elif _state == "play" and _vel.x > 0.0:
		target = lerpf(_mid_y(), _ball.position.y, 0.3)
		speed *= 0.5
	else:
		speed *= 0.4   # drift home while the ball is going the other way
	var step := clampf(target - was, -speed * delta, speed * delta)
	_cpu.position.y = _clamp_pad(was + step)
	_cpu_vy = (_cpu.position.y - was) / maxf(delta, 0.001)

## Where the ball will be, vertically, when it reaches `line_x`, folding in every bounce
## off the top and bottom walls on the way.
func _predict_y(line_x: float) -> float:
	if absf(_vel.x) < 1.0:
		return _ball.position.y
	var t := (line_x - _ball.position.x) / _vel.x
	if t < 0.0:
		return _ball.position.y
	var lo := FIELD_TOP + BALL_R
	var h := FIELD_BOTTOM - BALL_R - lo
	var y := fposmod(_ball.position.y + _vel.y * t - lo, 2.0 * h)
	if y > h:
		y = 2.0 * h - y
	return lo + y

## Small steps so a fast ball cannot skip clean through a paddle in one frame.
func _move_ball(delta: float) -> void:
	_trail.append({"pos": _ball.position, "life": 1.0})
	var travel := _vel.length() * delta
	var steps := maxi(1, int(ceil(travel / 4.0)))
	var dt := delta / float(steps)
	for i in steps:
		_ball.position += _vel * dt
		var p := _ball.position
		if p.y < FIELD_TOP + BALL_R:
			_ball.position.y = FIELD_TOP + BALL_R
			_vel.y = absf(_vel.y)
			_wall_bounce()
		elif p.y > FIELD_BOTTOM - BALL_R:
			_ball.position.y = FIELD_BOTTOM - BALL_R
			_vel.y = -absf(_vel.y)
			_wall_bounce()

		if _vel.x < 0.0 and _touches(_me):
			_hit(_me, 1.0)
		elif _vel.x > 0.0 and _touches(_cpu):
			_hit(_cpu, -1.0)

		if _ball.position.x < -BALL_R * 3.0:
			_point(false)
			return
		if _ball.position.x > play_area.size.x + BALL_R * 3.0:
			_point(true)
			return

## Overlap with the paddle's face, and only while the ball has not already gone past the
## paddle's centre -- a ball that slipped by is not saved by clipping the back corner.
func _touches(pad: Blob) -> bool:
	var p := _ball.position
	if absf(p.y - pad.position.y) > PAD_HH + BALL_R:
		return false
	if absf(p.x - pad.position.x) > PAD_HW + BALL_R:
		return false
	return (p.x - pad.position.x) * signf(320.0 - pad.position.x) >= 0.0

## `dir` is which way the ball leaves: +1 to the right (you hit it), -1 to the left.
func _hit(pad: Blob, dir: float) -> void:
	var off := clampf((_ball.position.y - pad.position.y) / (PAD_HH + BALL_R), -1.0, 1.0)
	_speed = minf(_speed + BALL_GAIN, BALL_MAX)
	var a := off * MAX_ANGLE
	var v := Vector2(dir * cos(a), sin(a)) * _speed
	var pad_vy := _me_vy if dir > 0.0 else _cpu_vy
	v.y += pad_vy * SPIN
	v = v.normalized() * _speed
	# never let spin steer it close to vertical -- that just bounces between the walls
	if absf(v.x) < _speed * MIN_VX:
		v.x = dir * _speed * MIN_VX
		v.y = signf(v.y) * sqrt(_speed * _speed - v.x * v.x)
	_vel = v
	_ball.position.x = pad.position.x + dir * (PAD_HW + BALL_R + 0.5)

	var heat := clampf((_speed - float(_cfg["serve"])) / 250.0, 0.0, 1.0)
	Juice.shake(1.2 + heat * 2.5)
	Juice.pop(_ball, 1.6, 0.16)
	Juice.flash(pad)
	_burst(_ball.position, "player" if dir > 0.0 else "hazard", 6 + int(heat * 6.0), dir)

	if dir > 0.0:
		_sq_me = 1.0
		_rally += 1
		add_score(1)
		Audio.play("impact_soft", 0.15, -4.0)
		Probe.event("return", {"rally": _rally, "speed": int(_speed)})
		if _rally % RALLY_BONUS_EVERY == 0:
			add_score(_rally)
			Audio.play("pickup", 0.0, -4.0)
			Juice.text(self, _ball.position + Vector2(10, -30), "RALLY %d  +%d" % [_rally, _rally],
				Palette.col("prize"))
			Probe.event("rally_bonus", {"rally": _rally})
		_roll_cpu_aim()
	else:
		_sq_cpu = 1.0
		Audio.play("impact_light", 0.15, -6.0)
		Probe.event("machine_return", {"speed": int(_speed)})

func _wall_bounce() -> void:
	Audio.play("click", 0.2, -12.0)
	Juice.shake(0.6)
	_burst(_ball.position, "accent", 3, 0.0)

## ---- sparks and trail, purely decorative -----------------------------------

## A short spray of sparks, thrown mostly along `dir` (+1 right, -1 left, 0 anywhere).
func _burst(at: Vector2, role: String, n: int, dir: float) -> void:
	if _bits.size() > 90:
		return
	for i in n:
		var d := Blob.new()
		d.role = role
		d.radius = randf_range(1.2, 2.6)
		d.glow = false
		add_child(d)
		d.position = at
		var vx := randf_range(40.0, 220.0) * dir if dir != 0.0 else randf_range(-90.0, 90.0)
		d.set_meta("vel", Vector2(vx, randf_range(-150.0, 150.0)))
		_bits.append(d)

func _move_bits(delta: float) -> void:
	var keep: Array = []
	for d in _bits:
		if not is_instance_valid(d):
			continue
		var v: Vector2 = d.get_meta("vel")
		v *= maxf(0.0, 1.0 - delta * 3.0)
		d.set_meta("vel", v)
		d.position += v * delta
		d.modulate.a -= delta * 1.8
		if d.modulate.a <= 0.03:
			d.queue_free()
			continue
		keep.append(d)
	_bits = keep

func _tick_trail(delta: float) -> void:
	var keep: Array = []
	for t in _trail:
		t["life"] -= delta * 3.2
		if t["life"] > 0.0:
			keep.append(t)
	_trail = keep

## ---- input -----------------------------------------------------------------

## Drag anywhere: the paddle moves by the same amount the pointer has moved since the drag
## began. A plain tap asks for no movement at all, and your thumb never has to cover the
## paddle or the ball. See "Controls" in the game-design skill.
func _input(event: InputEvent) -> void:
	if finished or Flow.pointer_over_hud():
		_drag = false
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			_drag_now = get_global_mouse_position().y
			if mb.pressed:
				_drag_from = _drag_now
				_pad_from = _me.position.y
	elif event is InputEventMouseMotion and _drag:
		_drag_now = get_global_mouse_position().y

## ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	var w := play_area.size.x
	var ink := Palette.col("ink")
	var accent := Palette.col("accent")
	var alt := Palette.col("bg_alt")
	var mine := Palette.col("player")
	var theirs := Palette.col("hazard")
	var f: Font = ThemeDB.fallback_font

	# the court
	draw_rect(Rect2(0, FIELD_TOP, w, FIELD_BOTTOM - FIELD_TOP), Color(alt.r, alt.g, alt.b, 0.16))
	for y in [FIELD_TOP, FIELD_BOTTOM]:
		draw_rect(Rect2(0, y - 1.5, w, 3.0), Color(accent.r, accent.g, accent.b, 0.55))
		draw_rect(Rect2(0, y - 4.0, w, 8.0), Color(accent.r, accent.g, accent.b, 0.08))

	# each goal glows in its owner's colour, and flares when it is scored on
	var lf := maxf(0.0, _goal_flash)
	var rf := maxf(0.0, -_goal_flash)
	draw_rect(Rect2(0, FIELD_TOP, 4.0 + lf * 30.0, FIELD_BOTTOM - FIELD_TOP),
		Color(mine.r, mine.g, mine.b, 0.18 + lf * 0.4))
	draw_rect(Rect2(w - 4.0 - rf * 30.0, FIELD_TOP, 4.0 + rf * 30.0, FIELD_BOTTOM - FIELD_TOP),
		Color(theirs.r, theirs.g, theirs.b, 0.18 + rf * 0.4))

	# the net
	var y0 := FIELD_TOP + 6.0
	while y0 < FIELD_BOTTOM - 6.0:
		draw_rect(Rect2(w * 0.5 - 1.5, y0, 3.0, 9.0), Color(ink.r, ink.g, ink.b, 0.28))
		y0 += 17.0

	# the big old-fashioned scoreboard, faint, behind everything
	draw_string(f, Vector2(w * 0.5 - 130.0, 104.0), str(_my_pts), HORIZONTAL_ALIGNMENT_CENTER,
		110, 54, Color(mine.r, mine.g, mine.b, 0.30))
	draw_string(f, Vector2(w * 0.5 + 20.0, 104.0), str(_cpu_pts), HORIZONTAL_ALIGNMENT_CENTER,
		110, 54, Color(theirs.r, theirs.g, theirs.b, 0.30))

	draw_string(f, Vector2(170, 24), "match %d  -  vs %s" % [_level, str(_cfg.get("name", ""))],
		HORIZONTAL_ALIGNMENT_CENTER, 300, 13, accent)

	_draw_trail()

	if _state == "serve":
		# a little chevron saying which way it is about to go
		var p := _ball.position + Vector2(_serve_dir * 16.0, 0.0)
		var c := Palette.col("warn")
		var k := Color(c.r, c.g, c.b, 0.5 + 0.5 * absf(sin(_state_t * 7.0)))
		draw_line(p + Vector2(-_serve_dir * 4.0, -5.0), p + Vector2(_serve_dir * 2.0, 0.0), k, 2.0)
		draw_line(p + Vector2(-_serve_dir * 4.0, 5.0), p + Vector2(_serve_dir * 2.0, 0.0), k, 2.0)

	if _banner_t > 0.0:
		var a := clampf(_banner_t / 0.4, 0.0, 1.0)
		var bc := Palette.col(_banner_role)
		# below the serve spot (centre +-40), so the waiting ball is never hidden behind it
		draw_rect(Rect2(0, 248, w, 60), Color(0, 0, 0, 0.35 * a))
		draw_string(f, Vector2(0, 283), _banner, HORIZONTAL_ALIGNMENT_CENTER, w, 30,
			Color(bc.r, bc.g, bc.b, a))
		draw_string(f, Vector2(0, 301), _banner_sub, HORIZONTAL_ALIGNMENT_CENTER, w, 12,
			Color(ink.r, ink.g, ink.b, 0.85 * a))

## Longer and brighter the faster the ball is going.
func _draw_trail() -> void:
	var c := Palette.col("warn")
	var heat := clampf((_speed - float(_cfg.get("serve", 330.0))) / 250.0, 0.0, 1.0)
	for t in _trail:
		var life: float = t["life"]
		draw_circle(t["pos"], BALL_R * (0.4 + life * 0.6), Color(c.r, c.g, c.b, life * (0.16 + heat * 0.22)))
