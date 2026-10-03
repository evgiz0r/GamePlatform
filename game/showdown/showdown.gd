extends GameMode
## showdown -- a 1v1 battle royale. You and one rival in an arena, a storm ring closing
## in, loot on the floor and rocks to hide behind. Shots aim themselves at the rival;
## the player chooses where to stand and when to pull the trigger. Beat the rival and a
## tougher one drops in with a fresh storm. See GAME.md.

const MAX_HEARTS := 5
const PLAYER_SPEED := 125.0
const PLAYER_COOLDOWN := 0.32
const RAPID_COOLDOWN := 0.13
const RAPID_TIME := 6.0
const PLAYER_BULLET_SPEED := 330.0
const BULLET_LIFE := 1.6
const BODY_R := 11.0
const STORM_TICK := 1.4                ## seconds between storm damage while outside
const LOOT_EVERY := 5.5
const LOOT_MAX := 3
const TRAIL := 0.045                   ## seconds of bullet trail drawn behind each shot
const ROUND_BREAK := 2.2
const SFX_SCALE := 0.35

## Storm phases: [hold seconds, shrink seconds, radius it shrinks to]
const STORM := [[4.0, 7.0, 190.0], [3.0, 7.0, 120.0], [3.0, 6.0, 70.0], [2.0, 6.0, 34.0]]

var player: Blob
var rival: Blob
var _hearts := MAX_HEARTS
var _rival_hearts := MAX_HEARTS
var _round := 0
var _bullets: Array = []       ## Blob, meta: vel, life, mine
var _loot: Array = []          ## Blob, meta: kind
var _bits: Array = []          ## Blob, meta: vel  (sparks and debris)
var _rocks: Array = []         ## [Vector2 pos, float r]
var _cool := 0.0
var _rapid := 0.0
var _storm_hurt := 0.0
var _rival_storm_hurt := 0.0
var _loot_t := 0.0
var _break := 0.0
var _t := 0.0

## storm ring
var _zc := Vector2.ZERO
var _zr := 400.0
var _from_c := Vector2.ZERO
var _from_r := 400.0
var _to_c := Vector2.ZERO
var _to_r := 400.0
var _phase := 0
var _phase_t := 0.0
var _shrinking := false

## rival brain
var _r_cool := 1.2
var _r_orbit := 1.0
var _r_orbit_t := 0.0
var _r_dodge := Vector2.ZERO
var _r_dodge_t := 0.0
var _r_speed := 100.0
var _r_cooldown := 0.8
var _r_aim_err := 0.16

## touch: left half drags a floating stick, right half holds the trigger
var _stick_id := -1
var _stick_from := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _fire_ids := {}
var _mouse_fire := false

var _sfx_was := 0.8
var _music_was := 0.8

func _ready() -> void:
	title = "showdown"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	_music_was = float(SaveData.data.get("volume_music", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	SaveData.data["volume_music"] = _music_was * SFX_SCALE

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	player = Blob.new()
	player.role = "player"
	player.radius = BODY_R
	add_child(player)
	player.set_sprite("ranger", 2.0)
	Probe.track(player, "@")

	set_lives(_hearts)
	_next_round()
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	SaveData.data["volume_music"] = _music_was

## ---- rounds ---------------------------------------------------------------

func _next_round() -> void:
	_round += 1
	_break = 0.0
	for b in _bullets + _loot:
		if is_instance_valid(b):
			b.queue_free()
	_bullets.clear()
	_loot.clear()
	_place_rocks()

	# the drop: you on the left, the rival on the right, swapped every other round
	var left := Vector2(90, randf_range(80, 280))
	var right := Vector2(550, randf_range(80, 280))
	player.position = left if _round % 2 == 1 else right
	player.modulate = Color.WHITE

	if is_instance_valid(rival):
		rival.queue_free()
	rival = Blob.new()
	rival.role = "hazard"
	rival.radius = BODY_R
	add_child(rival)
	rival.set_sprite(["barbarian", "viking", "skeleton", "goblin", "guard"][(_round - 1) % 5], 2.0)
	rival.position = right if _round % 2 == 1 else left
	_rival_last = rival.position
	_player_last = player.position
	Probe.track(rival, "x")

	# tougher every round: more hearts, faster, quicker trigger, better aim
	_rival_hearts = mini(5 + _round, 10)
	_r_speed = minf(105.0 + _round * 8.0, 145.0)
	_r_cooldown = maxf(0.7 - _round * 0.06, 0.38)
	_r_aim_err = maxf(0.08 - _round * 0.01, 0.03)
	_r_cool = 1.4
	_cool = 0.0

	# a fresh storm
	_zc = center()
	_zr = 340.0
	_phase = 0
	_phase_t = 0.0
	_shrinking = false
	_from_c = _zc
	_from_r = _zr
	_pick_next_circle()
	_loot_t = 1.5

	Juice.pop(player, 1.5, 0.3)
	Juice.pop(rival, 1.5, 0.3)
	Juice.text(self, center() + Vector2(-34, -40), "ROUND %d" % _round, Palette.col("warn"))
	Audio.play("voice_final_round" if _round >= 5 else "voice_round")
	Probe.event("round_start", {"round": _round, "rival_hearts": _rival_hearts})

func _place_rocks() -> void:
	_rocks.clear()
	var tries := 0
	while _rocks.size() < 6 and tries < 200:
		tries += 1
		var p := Vector2(randf_range(150, 490), randf_range(50, 310))
		var r := randf_range(14.0, 24.0)
		var ok := true
		for k in _rocks:
			if p.distance_to(k[0]) < r + k[1] + 40.0:
				ok = false
		if ok:
			_rocks.append([p, r])

func _pick_next_circle() -> void:
	var target_r: float = STORM[mini(_phase, STORM.size() - 1)][2]
	# the new circle sits wholly inside the current one (clamped to the arena)
	var room := maxf(0.0, minf(_from_r, 200.0) - target_r)
	var c := _from_c + Vector2.from_angle(randf() * TAU) * randf() * room
	c.x = clampf(c.x, play_area.position.x + 60.0, play_area.end.x - 60.0)
	c.y = clampf(c.y, play_area.position.y + 50.0, play_area.end.y - 50.0)
	_to_c = c
	_to_r = target_r

## ---- frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	_move_bits(delta)
	if finished:
		return
	_move_bullets(delta)

	if _break > 0.0:
		_break -= delta
		if _break <= 0.0:
			_next_round()
		return

	_storm(delta)
	_move_player(delta)
	_rival_think(delta)
	_spawn_loot(delta)
	_grab_loot()
	_storm_damage(delta)

func _move_player(delta: float) -> void:
	var d := PInput.dir()
	if _stick_vec != Vector2.ZERO:
		d = _stick_vec
	player.position = _slide(player.position + d * PLAYER_SPEED * delta)
	if absf(d.x) > 0.1:
		player.flip_h = d.x < 0.0
	if d != Vector2.ZERO:
		player.rotation = sin(_t * 18.0) * 0.12
	else:
		player.rotation = 0.0

	_cool = maxf(0.0, _cool - delta)
	_rapid = maxf(0.0, _rapid - delta)
	var trigger := PInput.pressed("action_a") or not _fire_ids.is_empty() or _mouse_fire
	if trigger and _cool <= 0.0 and is_instance_valid(rival):
		_cool = RAPID_COOLDOWN if _rapid > 0.0 else PLAYER_COOLDOWN
		var aim := _lead(player.position, rival.position, _rival_vel(), PLAYER_BULLET_SPEED)
		_shoot(player.position, aim, PLAYER_BULLET_SPEED, true)

## keep an actor inside the arena and out of the rocks
func _slide(p: Vector2) -> Vector2:
	for k in _rocks:
		var c: Vector2 = k[0]
		var minimum: float = k[1] + BODY_R
		if p.distance_to(c) < minimum:
			p = c + (p - c).normalized() * minimum
	return p.clamp(play_area.position + Vector2(BODY_R, BODY_R), play_area.end - Vector2(BODY_R, BODY_R))

## ---- shooting --------------------------------------------------------------

var _rival_last := Vector2.ZERO
var _rival_v := Vector2.ZERO
var _player_last := Vector2.ZERO
var _player_v := Vector2.ZERO

func _rival_vel() -> Vector2:
	return _rival_v

## Aim where the target will be, not where it is. One iteration is plenty at these speeds.
func _lead(from: Vector2, at: Vector2, vel: Vector2, speed: float) -> Vector2:
	var t := from.distance_to(at) / speed
	var guess := at + vel * t * 0.85
	return (guess - from).normalized()

func _shoot(from: Vector2, dir: Vector2, speed: float, mine: bool) -> void:
	var b := Blob.new()
	b.role = "player" if mine else "hazard"
	b.radius = 3.5
	b.shape = "diamond"
	add_child(b)
	b.position = from + dir * (BODY_R + 4.0)
	b.rotation = dir.angle()
	b.set_meta("vel", dir * speed)
	b.set_meta("life", BULLET_LIFE)
	b.set_meta("mine", mine)
	_bullets.append(b)
	if not mine:
		Probe.track(b, "x")
	Probe.event("shot", {"by": "you" if mine else "rival"})
	Audio.play("impact_metal" if mine else "impact_plate", 0.15, -8.0)
	Juice.pop(player if mine else rival, 1.18, 0.1)

func _move_bullets(delta: float) -> void:
	var keep: Array = []
	for b in _bullets:
		if not is_instance_valid(b):
			continue
		var v: Vector2 = b.get_meta("vel")
		b.position += v * delta
		var life: float = float(b.get_meta("life")) - delta
		b.set_meta("life", life)
		if life <= 0.0 or not in_play_area(b.position, 10.0):
			b.queue_free()
			continue
		var blocked := false
		for k in _rocks:
			if b.position.distance_to(k[0]) < k[1] + 2.0:
				blocked = true
		if blocked:
			_sparks(b.position, "ink", 4)
			Audio.play("impact_wood", 0.2, -10.0)
			b.queue_free()
			continue
		if _break <= 0.0 and not finished:
			var mine: bool = b.get_meta("mine")
			if mine and is_instance_valid(rival) and b.position.distance_to(rival.position) < BODY_R + 4.0:
				_hit_rival(b.position)
				b.queue_free()
				continue
			if not mine and b.position.distance_to(player.position) < BODY_R + 3.0:
				_hurt_player("shot")
				b.queue_free()
				continue
		keep.append(b)
	_bullets = keep

func _hit_rival(at: Vector2) -> void:
	_rival_hearts -= 1
	add_score(10)
	Probe.event("rival_hit", {"left": _rival_hearts})
	Juice.flash(rival)
	Juice.shake(3.0)
	Juice.text(self, at + Vector2(-6, -24), "-1", Palette.col("hazard"))
	_sparks(at, "hazard", 6)
	Audio.play("impact_punch")
	if _rival_hearts <= 0:
		_rival_down()

func _rival_down() -> void:
	var bonus := 100 + _hearts * 20
	add_score(bonus)
	Probe.event("rival_down", {"round": _round, "bonus": bonus})
	Juice.hit(9.0)
	_sparks(rival.position, "hazard", 18)
	_sparks(rival.position, "warn", 10)
	Juice.text(self, rival.position + Vector2(-22, -40), "+%d" % bonus, Palette.col("warn"))
	Audio.play("explode")
	Audio.play("voice_you_win" if _round == 1 else "voice_objective_achieved")
	rival.queue_free()
	# patch up between rounds: two hearts back
	_hearts = mini(_hearts + 2, MAX_HEARTS)
	set_lives(_hearts)
	_break = ROUND_BREAK
	Probe.capture("round %d won" % _round)

func _hurt_player(why: String) -> void:
	_hearts -= 1
	Probe.event("player_hurt", {"by": why, "lives": _hearts})
	Juice.flash(player, Palette.col("hazard"))
	Juice.hit(6.0)
	_sparks(player.position, "player", 6)
	Juice.text(self, player.position + Vector2(-6, -24), "-1", Palette.col("hazard"))
	Audio.play("hurt")
	set_lives(_hearts)
	if _hearts <= 0:
		_sparks(player.position, "player", 20)
		Audio.play("voice_you_lose")
		player.modulate.a = 0.0
		Probe.capture("knocked out")
		lose()

## ---- the rival ---------------------------------------------------------------

func _rival_think(delta: float) -> void:
	if not is_instance_valid(rival):
		return
	_rival_v = (rival.position - _rival_last) / maxf(delta, 0.001)
	_rival_last = rival.position
	_player_v = (player.position - _player_last) / maxf(delta, 0.001)
	_player_last = player.position

	var me := rival.position
	var to_p := player.position - me
	var dist := to_p.length()
	var want := Vector2.ZERO

	# orbit the player at a comfortable range, flipping direction now and then
	_r_orbit_t -= delta
	if _r_orbit_t <= 0.0:
		_r_orbit = -_r_orbit
		_r_orbit_t = randf_range(1.2, 2.8)
	var side := to_p.normalized().orthogonal() * _r_orbit
	var ideal := 150.0
	want = side + to_p.normalized() * clampf((dist - ideal) / 60.0, -1.0, 1.0)

	# loot it can reach first, and it is greedy when hurt
	var best: Blob = null
	for l in _loot:
		if not is_instance_valid(l):
			continue
		var mine_d := me.distance_to(l.position)
		if mine_d < player.position.distance_to(l.position) and mine_d < 170.0:
			if best == null or mine_d < me.distance_to(best.position):
				best = l
	if best != null:
		want = want * 0.4 + (best.position - me).normalized()

	# the storm comes first
	var out := me.distance_to(_zc) - (_zr - 24.0)
	if out > 0.0:
		want = want * 0.3 + (_zc - me).normalized() * 1.5

	# sidestep the player's shots
	_r_dodge_t -= delta
	if _r_dodge_t <= 0.0:
		_r_dodge = Vector2.ZERO
		for b in _bullets:
			if not is_instance_valid(b) or not b.get_meta("mine"):
				continue
			var bv: Vector2 = b.get_meta("vel")
			var rel: Vector2 = me - b.position
			if rel.length() < 90.0 and rel.dot(bv) > 0.0 and randf() < 0.7:
				_r_dodge = bv.normalized().orthogonal() * (1.0 if rel.cross(bv) < 0.0 else -1.0)
				break
		_r_dodge_t = 0.18
	if _r_dodge != Vector2.ZERO:
		want = want * 0.3 + _r_dodge * 1.4

	if want.length() > 1.0:
		want = want.normalized()
	rival.position = _slide(me + want * _r_speed * delta)
	if absf(want.x) > 0.1:
		rival.flip_h = want.x < 0.0
	rival.rotation = sin(_t * 16.0) * 0.1 if want != Vector2.ZERO else 0.0

	# shoot when in range
	_r_cool -= delta
	if _r_cool <= 0.0 and dist < 330.0:
		_r_cool = _r_cooldown * randf_range(0.85, 1.2)
		var aim := _lead(me, player.position, _player_v, 230.0 + _round * 12.0)
		aim = aim.rotated(randf_range(-_r_aim_err, _r_aim_err))
		_shoot(me, aim, 230.0 + _round * 12.0, false)

## ---- the storm -------------------------------------------------------------

func _storm(delta: float) -> void:
	if _phase >= STORM.size():
		return
	var ph: Array = STORM[_phase]
	_phase_t += delta
	if not _shrinking:
		if _phase_t >= ph[0]:
			_shrinking = true
			_phase_t = 0.0
			Juice.text(self, center() + Vector2(-60, -150), "the storm is closing", Palette.col("accent"))
			Audio.play("voice_hurry_up" if _phase >= 2 else "impact_bell")
			Probe.event("storm_closing", {"phase": _phase, "to": _to_r})
		return
	var k := clampf(_phase_t / ph[1], 0.0, 1.0)
	_zc = _from_c.lerp(_to_c, k)
	_zr = lerpf(_from_r, _to_r, k)
	if k >= 1.0:
		_phase += 1
		_phase_t = 0.0
		_shrinking = false
		_from_c = _zc
		_from_r = _zr
		if _phase < STORM.size():
			_pick_next_circle()

func _storm_damage(delta: float) -> void:
	if player.position.distance_to(_zc) > _zr:
		_storm_hurt += delta
		if _storm_hurt >= STORM_TICK:
			_storm_hurt = 0.0
			_hurt_player("storm")
	else:
		_storm_hurt = minf(_storm_hurt, STORM_TICK * 0.5)
	if is_instance_valid(rival) and rival.position.distance_to(_zc) > _zr:
		_rival_storm_hurt += delta
		if _rival_storm_hurt >= STORM_TICK:
			_rival_storm_hurt = 0.0
			_rival_hearts -= 1
			Juice.flash(rival, Palette.col("accent"))
			Juice.text(self, rival.position + Vector2(-6, -24), "-1", Palette.col("accent"))
			Probe.event("rival_storm_hurt")
			if _rival_hearts <= 0:
				_rival_down()
	else:
		_rival_storm_hurt = minf(_rival_storm_hurt, STORM_TICK * 0.5)

## ---- loot -----------------------------------------------------------------

func _spawn_loot(delta: float) -> void:
	_loot_t -= delta
	if _loot_t > 0.0:
		return
	_loot_t = LOOT_EVERY
	var alive: Array = []
	for l in _loot:
		if is_instance_valid(l):
			alive.append(l)
	_loot = alive
	if _loot.size() >= LOOT_MAX:
		return
	for i in 20:
		var p := _zc + Vector2.from_angle(randf() * TAU) * randf() * maxf(_zr - 20.0, 10.0)
		if not in_play_area(p, -24.0):
			continue
		var clear := true
		for k in _rocks:
			if p.distance_to(k[0]) < k[1] + 16.0:
				clear = false
		if not clear:
			continue
		var kind := "heal" if randf() < 0.5 else "rapid"
		var l := Blob.new()
		l.role = "prize" if kind == "heal" else "friend"
		l.radius = 7.0
		l.shape = "diamond"
		add_child(l)
		l.set_sprite("potion_red" if kind == "heal" else "potion_blue", 1.6)
		l.position = p
		l.set_meta("kind", kind)
		_loot.append(l)
		Probe.track(l, "*")
		Juice.pop(l, 1.8, 0.3)
		Probe.event("loot_dropped", {"kind": kind})
		return

func _grab_loot() -> void:
	var keep: Array = []
	for l in _loot:
		if not is_instance_valid(l):
			continue
		l.position.y += sin(_t * 4.0 + l.position.x) * 0.15
		var kind: String = l.get_meta("kind")
		if l.position.distance_to(player.position) < BODY_R + 10.0:
			if kind == "heal":
				_hearts = mini(_hearts + 1, MAX_HEARTS)
				set_lives(_hearts)
				Juice.text(self, l.position + Vector2(-10, -22), "+1", Palette.col("prize"))
			else:
				_rapid = RAPID_TIME
				Juice.text(self, l.position + Vector2(-22, -22), "RAPID!", Palette.col("friend"))
				Audio.play("voice_power_up")
			add_score(5)
			Probe.event("prize_taken", {"kind": kind})
			Audio.play("pickup")
			Juice.pop(player, 1.4)
			l.queue_free()
			continue
		if is_instance_valid(rival) and l.position.distance_to(rival.position) < BODY_R + 10.0:
			if kind == "heal":
				_rival_hearts = mini(_rival_hearts + 1, 5 + _round)
			else:
				_r_cool = 0.0
				_r_cooldown *= 0.85
			Juice.text(self, l.position + Vector2(-20, -22), "stolen!", Palette.col("hazard"))
			Probe.event("rival_looted", {"kind": kind})
			Audio.play("coin", 0.1, -6.0)
			Juice.pop(rival, 1.4)
			l.queue_free()
			continue
		keep.append(l)
	_loot = keep

## ---- particles ----------------------------------------------------------------

func _sparks(at: Vector2, role: String, n: int) -> void:
	for i in n:
		var s := Blob.new()
		s.role = role
		s.radius = randf_range(1.5, 3.0)
		s.glow = false
		add_child(s)
		s.position = at
		s.set_meta("vel", Vector2.from_angle(randf() * TAU) * randf_range(60, 200))
		_bits.append(s)

func _move_bits(delta: float) -> void:
	var keep: Array = []
	for s in _bits:
		if not is_instance_valid(s):
			continue
		var v: Vector2 = s.get_meta("vel")
		v *= 1.0 - 4.0 * delta
		s.set_meta("vel", v)
		s.position += v * delta
		s.modulate.a -= delta * 2.2
		if s.modulate.a <= 0.0:
			s.queue_free()
			continue
		keep.append(s)
	_bits = keep

## ---- touch and mouse -------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var p := _to_world(st.position)
		if st.pressed:
			if Flow.pointer_over_hud():
				return
			if p.x < center().x and _stick_id == -1:
				_stick_id = st.index
				_stick_from = p
				_stick_vec = Vector2.ZERO
			else:
				_fire_ids[st.index] = true
		else:
			if st.index == _stick_id:
				_stick_id = -1
				_stick_vec = Vector2.ZERO
			_fire_ids.erase(st.index)
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _stick_id:
			# a direction, not a destination: how far the finger has moved since it landed
			var d := _to_world(sd.position) - _stick_from
			_stick_vec = d / 36.0 if d.length() < 36.0 else d.normalized()
			if d.length() < 5.0:
				_stick_vec = Vector2.ZERO
		return
	# a real mouse fires on hold; mouse events emulated from a touch are handled above
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and Flow.pointer_over_hud():
			return
		_mouse_fire = mb.pressed

func _to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen

## ---- drawing ----------------------------------------------------------------

func _draw() -> void:
	var ink := Palette.col("ink")
	var bg_alt := Palette.col("bg_alt")
	draw_rect(play_area, bg_alt.darkened(0.25))
	# floor grid
	var grid := Color(ink.r, ink.g, ink.b, 0.05)
	for x in range(0, 641, 40):
		draw_line(Vector2(x, 0), Vector2(x, 360), grid, 1.0)
	for y in range(0, 361, 40):
		draw_line(Vector2(0, y), Vector2(640, y), grid, 1.0)

	# rocks
	for k in _rocks:
		var c: Vector2 = k[0]
		var r: float = k[1]
		draw_circle(c + Vector2(2, 3), r, Color(0, 0, 0, 0.35))
		draw_circle(c, r, bg_alt.lightened(0.18))
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.35, bg_alt.lightened(0.32))

	# a team ring under each fighter, so you never mix them up
	for who in [player, rival]:
		if is_instance_valid(who) and who.modulate.a > 0.0:
			var rc := Palette.col(who.role)
			draw_circle(who.position + Vector2(0, 12), 13.0, Color(rc.r, rc.g, rc.b, 0.22))
			draw_arc(who.position + Vector2(0, 12), 13.0, 0.0, TAU, 24, rc, 2.0)

	# bullet trails
	for b in _bullets:
		if not is_instance_valid(b):
			continue
		var v: Vector2 = b.get_meta("vel")
		var col := Palette.col(b.role)
		draw_line(b.position - v * TRAIL, b.position, Color(col.r, col.g, col.b, 0.5), 2.0)

	# the storm: everything outside the ring is tinted, the edge glows
	var storm := Palette.col("accent")
	var w := 900.0
	draw_arc(_zc, _zr + w * 0.5, 0.0, TAU, 96, Color(storm.r, storm.g, storm.b, 0.16), w)
	draw_arc(_zc, _zr, 0.0, TAU, 96, Color(storm.r, storm.g, storm.b, 0.75 + sin(_t * 6.0) * 0.2), 2.5)
	if _shrinking or _phase < STORM.size():
		draw_arc(_to_c, _to_r, 0.0, TAU, 64, Color(ink.r, ink.g, ink.b, 0.18), 1.0)

	# hearts over the rival
	if is_instance_valid(rival) and _break <= 0.0:
		var hz := Palette.col("hazard")
		for i in _rival_hearts:
			var hx := rival.position.x - (_rival_hearts - 1) * 4.0 + i * 8.0
			draw_circle(Vector2(hx, rival.position.y - 22.0), 2.6, hz)

	# rapid-fire ring around the player
	if _rapid > 0.0 and is_instance_valid(player):
		var fr := Palette.col("friend")
		draw_arc(player.position, 16.0, -PI * 0.5, -PI * 0.5 + TAU * (_rapid / RAPID_TIME), 32, fr, 2.0)

	# touch stick
	if _stick_id != -1:
		var pc := Palette.col("player")
		draw_arc(_stick_from, 36.0, 0.0, TAU, 32, Color(pc.r, pc.g, pc.b, 0.35), 2.0)
		draw_circle(_stick_from + _stick_vec * 36.0, 10.0, Color(pc.r, pc.g, pc.b, 0.4))

	var f: Font = ThemeDB.fallback_font
	var msg := "round %d" % _round
	if _phase < STORM.size() and not _shrinking:
		msg += "  -  storm in %d" % ceili(float(STORM[_phase][0]) - _phase_t)
	draw_string(f, Vector2(120, 352), msg, HORIZONTAL_ALIGNMENT_CENTER, 400, 12, Color(ink.r, ink.g, ink.b, 0.7))
