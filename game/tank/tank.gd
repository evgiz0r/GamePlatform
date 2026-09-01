extends GameMode
## tank -- a tank in the bottom-left corner lobs shells over the board. Every animal on
## the field is the same species except one. Hit the odd one out and it cries and the
## level advances; hit any other and it just laughs and spins at you. See GAME.md.
##
## No time limit, no shot limit, no lives -- the only thing that goes down is the score
## you get for clearing a level, and only wrong hits cost you that.

const TANK := Vector2(46, 322)
const MUZZLE := Vector2(46, 308)
const G := 520.0                          ## gravity on the shell, px/s^2
const FIELD := Rect2(150, 42, 465, 258)   ## where the animals stand
const SLOT_JITTER := 6.0
const CROSS_SPEED := 240.0
const FIRE_COOLDOWN := 0.3
const HIT_RADIUS := 26.0
const CRY_TIME := 1.7
const LAUGH_TIME := 0.75
const MAX_ANIMALS := 6
const TRAIL_MAX := 26
const GROUND_Y := 338.0                   ## where a shell that hits nothing lands
const ANIMAL_SCALE := 0.13
## The shell default (0.8) is loud for a game that fires this often. In memory only --
## the saved settings file is never written. See reference/README.md.
const SFX_VOLUME := 0.28

## The cast. "penguin" crews the tank and is kept out of the target line-up, so the same
## animal never means two things on screen at once.
const CAST := ["pig", "rabbit", "monkey", "panda", "parrot", "hippo", "elephant",
	"giraffe", "snake"]
const GUNNER := "penguin"

var cross: Blob
var gunner: Blob
var _animals: Array = []       ## Blob, meta: odd, slot, phase, laugh, spin
var _shells: Array = []        ## Blob, meta: vel, trail
var _tears: Array = []         ## Blob, meta: vel
var _level := 0
var _crying := 0.0
var _cool := 0.0
var _wrong_this_level := 0
var _t := 0.0
var _sfx_was := 0.8

func _ready() -> void:
	title = "tank"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = SFX_VOLUME

	var cam := Camera2D.new()
	cam.position = center()
	add_child(cam)
	cam.make_current()

	# no lives: this game cannot be lost, so an empty lives display is honest
	set_lives(0)

	cross = Blob.new()
	cross.role = "player"
	cross.radius = 6.0
	cross.shape = "circle"
	add_child(cross)
	cross.position = Vector2(380, 190)
	Probe.track(cross, "@")

	gunner = Blob.new()
	gunner.role = "player"
	add_child(gunner)
	# smaller than a target, so the crew never reads as one of the animals to shoot
	gunner.set_sprite(GUNNER, ANIMAL_SCALE * 0.72)
	gunner.position = Vector2(98, 306)

	_next_level()
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- levels ---------------------------------------------------------------

func _next_level() -> void:
	_level += 1
	_wrong_this_level = 0
	_crying = 0.0
	for a in _animals:
		if is_instance_valid(a):
			a.queue_free()
	_animals.clear()

	var n := clampi(3 + (_level - 1) / 2, 3, MAX_ANIMALS)
	var species: Array = CAST.duplicate()
	species.shuffle()
	var herd: String = species[0]
	var odd: String = species[1]

	var slots := _slots(n)
	var odd_at := randi() % n
	for i in n:
		var is_odd: bool = i == odd_at
		var b := Blob.new()
		b.role = "prize" if is_odd else "friend"
		b.radius = 15.0
		add_child(b)
		b.set_sprite(odd if is_odd else herd, ANIMAL_SCALE)
		b.position = slots[i]
		b.set_meta("odd", is_odd)
		b.set_meta("slot", slots[i])
		b.set_meta("phase", randf() * TAU)
		b.set_meta("laugh", 0.0)
		_animals.append(b)
		# the wrong animals are tagged "o", not "x": nothing here can hurt you, and a bot
		# that treats them as hazards spends the run fleeing between them instead of
		# walking to the target. The report warns there are no threats -- correctly.
		Probe.track(b, "*" if is_odd else "o")

	Probe.event("level_start", {"level": _level, "animals": n, "wobble": _wobble()})
	if _level % 4 == 1:
		Probe.capture("level %d" % _level)

## Six slots on a 3x2 grid, jittered. Taking n of them shuffled keeps the layouts varied
## while guaranteeing the animals never end up on top of each other.
func _slots(n: int) -> Array:
	var cw := FIELD.size.x / 3.0
	var ch := FIELD.size.y / 2.0
	var cells: Array = []
	for r in 2:
		for c in 3:
			cells.append(FIELD.position + Vector2((c + 0.5) * cw, (r + 0.5) * ch))
	cells.shuffle()
	var out: Array = []
	for i in n:
		out.append(cells[i] + Vector2(randf_range(-SLOT_JITTER, SLOT_JITTER),
			randf_range(-SLOT_JITTER, SLOT_JITTER)))
	return out

## Animals hold still for the first two levels, then wander a little more each level.
func _wobble() -> float:
	return clampf(float(_level - 2) * 4.0, 0.0, 26.0)

## ---- firing ---------------------------------------------------------------

## Solve the lob. Flight time is fixed (and grows a little with range) rather than muzzle
## speed, which keeps every arc on the board and keeps the lead on a moving animal
## predictable. Real parabola, real gravity -- only the charge varies, like real artillery.
func _flight_time(to: Vector2) -> float:
	return clampf(0.85 + MUZZLE.distance_to(to) / 1400.0, 0.85, 1.45)

func _launch_velocity(to: Vector2) -> Vector2:
	var t := _flight_time(to)
	var d := to - MUZZLE
	return Vector2(d.x / t, (d.y - 0.5 * G * t * t) / t)

func _fire(at: Vector2) -> void:
	var s := Blob.new()
	s.role = "warn"
	s.radius = 4.0
	s.shape = "circle"
	add_child(s)
	s.position = MUZZLE
	s.set_meta("vel", _launch_velocity(at))
	s.set_meta("trail", PackedVector2Array([MUZZLE]))
	s.set_meta("life", _flight_time(at))
	_shells.append(s)
	Probe.track(s, "!")
	Probe.event("fire")
	Audio.play("thud")
	Audio.play("impact_metal", 0.15, -6.0)
	if is_instance_valid(gunner):
		Juice.pop(gunner, 1.35, 0.22)
	Juice.shake(3.5)
	_cool = FIRE_COOLDOWN

## ---- play -----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	queue_redraw()
	_cool = maxf(0.0, _cool - delta)

	_move_animals(delta)
	_move_shells(delta)
	_move_tears(delta)

	if _crying > 0.0:
		_crying -= delta
		if _crying <= 0.0:
			_next_level()
		return

	cross.position += PInput.dir() * CROSS_SPEED * delta
	cross.position = cross.position.clamp(play_area.position, play_area.end)

	if PInput.just_pressed("action_a") and _cool <= 0.0:
		_fire(cross.position)

## Static badges, animated by hand: a sway when they are standing, a proper hop when they
## wander, a droop when one of them is crying. Kenney's animal art has no frames at all,
## so every bit of life here is position, rotation and squash.
func _move_animals(delta: float) -> void:
	var amp := _wobble()
	var w := clampf(float(_level - 2) * 0.3, 0.0, 1.9)
	for a in _animals:
		if not is_instance_valid(a):
			continue
		var laugh: float = a.get_meta("laugh")
		if laugh > 0.0:
			a.set_meta("laugh", maxf(0.0, laugh - delta))
			# bouncing on the spot, hooting
			a.position = a.get_meta("slot") + Vector2(0, -absf(sin(_t * 17.0)) * 9.0)
			continue
		var slot: Vector2 = a.get_meta("slot")
		var ph: float = a.get_meta("phase")
		if _crying > 0.0:
			if a.get_meta("odd"):
				a.rotation = 0.26
				a.position = slot + Vector2(sin(_t * 34.0) * 3.0, 4.0)
			continue
		a.rotation = 0.0
		if amp <= 0.0:
			a.position = slot + Vector2(0, sin(_t * 1.9 + ph) * 2.0)
			continue
		var was: float = a.position.x
		var drift := Vector2(sin(_t * w + ph) * amp, cos(_t * w * 0.8 + ph) * amp * 0.7)
		# hop along rather than glide -- a sliding animal reads as broken
		var hop := absf(sin(_t * (2.2 + w) + ph)) * (3.0 + amp * 0.28)
		a.position = slot + drift - Vector2(0, hop)
		var dx: float = a.position.x - was
		if absf(dx) > 0.02:
			a.flip_h = dx < 0.0

func _move_shells(delta: float) -> void:
	var keep: Array = []
	for s in _shells:
		if not is_instance_valid(s):
			continue
		var v: Vector2 = s.get_meta("vel")
		v.y += G * delta
		s.set_meta("vel", v)
		s.position += v * delta

		var trail: PackedVector2Array = s.get_meta("trail")
		trail.append(s.position)
		if trail.size() > TRAIL_MAX:
			trail = trail.slice(trail.size() - TRAIL_MAX)
		s.set_meta("trail", trail)

		# The fuse marks the aim point: up to there the shell is inert, so a lob cannot clip
		# an animal it merely flew over on the way up (that read as broken -- you click the
		# odd one and something else explodes). Past the aim point it stays in the air and
		# keeps falling, live, until it hits somebody or reaches the ground.
		var life: float = float(s.get_meta("life")) - delta
		s.set_meta("life", life)
		if life > 0.0:
			keep.append(s)
			continue

		var struck: Blob = null if _crying > 0.0 else _animal_at(s.position)
		if struck != null:
			_impact(struck)
			s.queue_free()
			continue
		if s.position.y < GROUND_Y and in_play_area(s.position, 80.0):
			keep.append(s)
			continue
		Probe.event("miss")
		Audio.play("impact_light")
		Juice.shake(2.0)
		_puff(Vector2(s.position.x, minf(s.position.y, GROUND_Y)))
		s.queue_free()
	_shells = keep

## dirt kicked up where a shell lands on nothing
func _puff(at: Vector2) -> void:
	for i in 5:
		var d := Blob.new()
		d.role = "accent"
		d.radius = 2.5
		add_child(d)
		d.position = at
		d.set_meta("vel", Vector2(randf_range(-70, 70), randf_range(-120, -40)))
		_tears.append(d)

func _animal_at(p: Vector2) -> Blob:
	for a in _animals:
		if is_instance_valid(a) and p.distance_to(a.position) < HIT_RADIUS:
			return a
	return null

func _move_tears(delta: float) -> void:
	var keep: Array = []
	for t in _tears:
		if not is_instance_valid(t):
			continue
		var v: Vector2 = t.get_meta("vel")
		v.y += 340.0 * delta
		t.set_meta("vel", v)
		t.position += v * delta
		t.modulate.a = maxf(0.0, t.modulate.a - delta * 0.8)
		if t.position.y > play_area.end.y or t.modulate.a <= 0.02:
			t.queue_free()
			continue
		keep.append(t)
	_tears = keep

## Mouse is the real way to aim; the crosshair is also driven by PInput so keyboard,
## gamepad and the headless bots can play the same game.
func _input(event: InputEvent) -> void:
	if finished or _crying > 0.0:
		return
	if event is InputEventMouseMotion:
		cross.position = get_global_mouse_position().clamp(play_area.position, play_area.end)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or _cool > 0.0:
		return
	cross.position = get_global_mouse_position().clamp(play_area.position, play_area.end)
	_fire(cross.position)

## ---- getting hit ----------------------------------------------------------

func _impact(a: Blob) -> void:
	if a.get_meta("odd"):
		_cry(a)
	else:
		_laugh(a)

## The odd one out. Tears, a shake, everyone else clears off, then the next level.
func _cry(a: Blob) -> void:
	_crying = CRY_TIME
	var points := maxi(25, 100 - _wrong_this_level * 15)
	add_score(points)
	Probe.event("hit_odd", {"level": _level, "wrong": _wrong_this_level})
	Audio.play("impact_soft")
	# "win" is a two-second jingle (see assets/INDEX.md) -- the voice line is the sting
	Audio.play("voice_level_up" if _level % 5 == 0 else "voice_correct")
	Juice.hit(7.0)
	Juice.pop(a, 1.5)
	Juice.text(self, a.position + Vector2(-12, -52), "+%d" % points, Palette.col("warn"))

	for i in 7:
		var d := Blob.new()
		d.role = "player"
		d.radius = 3.0
		d.shape = "diamond"
		add_child(d)
		d.position = a.position + Vector2(randf_range(-11, 11), randf_range(-6, 6))
		d.set_meta("vel", Vector2(randf_range(-55, 55), randf_range(-135, -55)))
		_tears.append(d)

	for other in _animals:
		if is_instance_valid(other) and not other.get_meta("odd"):
			var tw: Tween = other.create_tween()
			tw.tween_property(other, "modulate:a", 0.0, 0.45)

## A wrong one. It thinks that is very funny.
func _laugh(a: Blob) -> void:
	_wrong_this_level += 1
	a.set_meta("laugh", LAUGH_TIME)
	a.set_meta("laughed", true)
	a.rotation = 0.0
	Probe.event("hit_wrong", {"level": _level})
	Audio.play("impact_light")
	Audio.play("voice_wrong")
	Juice.shake(2.5)
	Juice.pop(a, 1.4, 0.3)
	Juice.text(self, a.position + Vector2(-16, -50), "HA HA!", Palette.col("hazard"))
	var tw: Tween = a.create_tween()
	tw.tween_property(a, "rotation", TAU * 2.0, LAUGH_TIME).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func(): a.rotation = 0.0)

## ---- the screen ------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font

	for s in _shells:
		if not is_instance_valid(s):
			continue
		var trail: PackedVector2Array = s.get_meta("trail")
		var c := Palette.col("warn")
		for i in trail.size():
			var k := float(i) / float(maxi(1, trail.size()))
			draw_circle(trail[i], 1.0 + k * 2.0, Color(c.r, c.g, c.b, k * 0.5))

	_draw_tank()

	_text(f, 320, 26, "hit the one that is different", 14, Palette.col("accent"))
	_text(f, 320, 350, "level %d" % _level, 13, Palette.col("ink"))

func _draw_tank() -> void:
	var body := Palette.col("player")
	var aim := (_launch_velocity(cross.position)).normalized()
	draw_line(MUZZLE, MUZZLE + aim * 30.0, body, 5.0)
	draw_rect(Rect2(TANK.x - 20, TANK.y - 12, 40, 16), body)
	draw_circle(TANK + Vector2(0, -14), 9.0, body)
	draw_rect(Rect2(TANK.x - 22, TANK.y + 4, 44, 7), Palette.col("bg_alt"))
	for i in 5:
		draw_circle(Vector2(TANK.x - 16 + i * 8, TANK.y + 7), 3.0, body)

func _text(f: Font, cx: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(cx - 200, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 400, size, col)
