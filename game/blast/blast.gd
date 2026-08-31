extends GameMode
## Shooter example: hold the fire button, clear the waves, do not let them land.
## Shows a firing cooldown, a bullet pool and wave escalation.

const MOVE_SPEED := 175.0
const FIRE_COOLDOWN := 0.22
const BULLET_SPEED := 320.0
const ENEMY_SPEED := 26.0

var player: Blob
var bullets: Array = []
var enemies: Array = []
var _cool := 0.0
var _wave := 0
var _between := 1.0

func _ready() -> void:
	title = "blast"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	var cam := Camera2D.new()
	cam.position = center()
	cam.make_current()
	add_child(cam)

	set_lives(3)
	player = Blob.new()
	player.role = "player"
	player.radius = 9.0
	add_child(player)
	player.set_sprite("soldier", 1.8)
	player.position = Vector2(play_area.size.x * 0.5, play_area.end.y - 28.0)
	Probe.track(player, "@")
	Probe.capture("start")

func _process(delta: float) -> void:
	if finished:
		return

	player.position.x = clampf(player.position.x + PInput.dir().x * MOVE_SPEED * delta,
		14.0, play_area.size.x - 14.0)

	_cool -= delta
	if PInput.pressed("action_a") and _cool <= 0.0:
		_cool = FIRE_COOLDOWN
		_fire()

	if enemies.is_empty():
		_between -= delta
		if _between <= 0.0:
			_between = 1.2
			_spawn_wave()

	_move_bullets(delta)
	_move_enemies(delta)

func _fire() -> void:
	var b := Blob.new()
	b.role = "warn"
	b.radius = 2.5
	b.shape = "square"
	add_child(b)
	b.position = player.position + Vector2(0, -12)
	bullets.append(b)
	Audio.play("hit")
	Probe.event("shot")

func _spawn_wave() -> void:
	_wave += 1
	Probe.event("wave", {"n": _wave})
	var cols: int = mini(4 + _wave, 9)
	var kinds := ["bat", "spider", "skull", "ghost"]
	for i in cols:
		var e := Blob.new()
		e.role = "hazard"
		e.radius = 8.0
		e.shape = "triangle"
		add_child(e)
		e.set_sprite(kinds[_wave % kinds.size()], 1.6)
		var x: float = 60.0 + float(i) * (play_area.size.x - 120.0) / float(maxi(1, cols - 1))
		e.position = Vector2(x, 30.0 + randf_range(0.0, 26.0))
		e.set_meta("phase", randf_range(0.0, TAU))
		enemies.append(e)
		Probe.track(e, "x")

func _move_bullets(delta: float) -> void:
	var keep: Array = []
	for b in bullets:
		if not is_instance_valid(b):
			continue
		b.position.y -= BULLET_SPEED * delta
		if b.position.y < -10.0:
			b.queue_free()
			continue
		var hit := false
		for e in enemies:
			if is_instance_valid(e) and e.position.distance_to(b.position) < 13.0:
				_kill(e)
				hit = true
				break
		if hit:
			b.queue_free()
			continue
		keep.append(b)
	bullets = keep

func _kill(e: Blob) -> void:
	Probe.event("enemy_killed")
	add_score(10 + _wave * 2)
	Juice.hit(5.0)
	Juice.text(self, e.position, "+%d" % (10 + _wave * 2), Palette.col("warn"))
	Audio.play("explode")
	enemies.erase(e)
	e.queue_free()

func _move_enemies(delta: float) -> void:
	var keep: Array = []
	var speed: float = ENEMY_SPEED + float(_wave) * 5.0
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var ph: float = e.get_meta("phase") + delta * 2.0
		e.set_meta("phase", ph)
		e.position.y += speed * delta
		e.position.x += sin(ph) * 26.0 * delta
		if e.position.distance_to(player.position) < 16.0 or e.position.y > play_area.end.y - 12.0:
			Probe.event("enemy_landed")
			e.queue_free()
			lose_life()
			continue
		keep.append(e)
	enemies = keep
