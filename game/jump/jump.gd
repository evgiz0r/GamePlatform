extends GameMode
## Platformer example: run, jump, collect every gem, do not fall.
## Shows gravity + AABB platform collision without any physics nodes.

const GRAVITY := 900.0
const MOVE_SPEED := 135.0
const JUMP_FORCE := 330.0
const HALF := Vector2(7, 9)

var player: Blob
var _vel := Vector2.ZERO
var _on_ground := false
var _spawn := Vector2(40, 240)

var platforms: Array[Rect2] = []
var prizes: Array = []
var hazards: Array = []

func _ready() -> void:
	title = "jump"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	var cam := Camera2D.new()
	cam.position = center()
	cam.make_current()
	add_child(cam)

	set_lives(3)
	_build_level()

	player = Blob.new()
	player.role = "player"
	player.radius = 8.0
	add_child(player)
	player.set_sprite("villager", 1.7)
	player.position = _spawn
	Probe.track(player, "@")
	Probe.capture("start")
	queue_redraw()

func _build_level() -> void:
	platforms.assign([
		Rect2(0, 330, 220, 30),      # start ledge
		Rect2(270, 330, 370, 30),    # far ledge, with a gap between
		Rect2(150, 260, 110, 14),
		Rect2(330, 235, 120, 14),
		Rect2(60, 190, 110, 14),
		Rect2(500, 175, 110, 14),
		Rect2(250, 130, 120, 14),
	])
	# invisible markers so platform geometry shows up in the ASCII playtest maps --
	# without these a platformer report is unreadable
	for r in platforms:
		var x := r.position.x + 8.0
		while x < r.end.x:
			var m := Node2D.new()
			add_child(m)
			m.position = Vector2(x, r.position.y + 2.0)
			Probe.track(m, "#")
			x += 26.0

	var spots := [Vector2(205, 240), Vector2(390, 215), Vector2(115, 170),
				  Vector2(555, 155), Vector2(310, 110), Vector2(310, 312)]
	for s in spots:
		var p := Blob.new()
		p.role = "prize"
		p.radius = 6.0
		p.shape = "diamond"
		add_child(p)
		p.set_sprite("potion_blue", 1.4)
		p.position = s
		prizes.append(p)
		Probe.track(p, "*")

	for pair in [[Vector2(455, 315), 430.0, 565.0], [Vector2(360, 220), 340.0, 440.0]]:
		var h := Blob.new()
		h.role = "hazard"
		h.radius = 7.0
		add_child(h)
		h.set_sprite("spider", 1.5)
		h.position = pair[0]
		h.set_meta("x0", pair[1])
		h.set_meta("x1", pair[2])
		h.set_meta("dir", 1.0)
		hazards.append(h)
		Probe.track(h, "x")

func _draw() -> void:
	var c := Palette.col("friend")
	for r in platforms:
		draw_rect(Rect2(r.position - Vector2(0, 2), Vector2(r.size.x, 3)),
			Color(c.r, c.g, c.b, 0.85))          # glowing top edge
		draw_rect(r, Color(c.r, c.g, c.b, 0.18))  # body

func _process(delta: float) -> void:
	if finished:
		return

	_vel.x = PInput.dir().x * MOVE_SPEED
	_vel.y += GRAVITY * delta
	if PInput.just_pressed("action_a") and _on_ground:
		_vel.y = -JUMP_FORCE
		_on_ground = false
		Audio.play("jump")
		Probe.event("jump")

	_move(delta)
	_move_hazards(delta)
	_check_pickups()

	if player.position.y > play_area.end.y + 20.0:
		Probe.event("fell_off")
		_respawn()

func _move(delta: float) -> void:
	player.position.x += _vel.x * delta
	for r in platforms:
		if _hits(r):
			if _vel.x > 0.0:
				player.position.x = r.position.x - HALF.x
			elif _vel.x < 0.0:
				player.position.x = r.end.x + HALF.x
	player.position.x = clampf(player.position.x, HALF.x, play_area.size.x - HALF.x)

	player.position.y += _vel.y * delta
	_on_ground = false
	for r in platforms:
		if _hits(r):
			if _vel.y > 0.0:
				player.position.y = r.position.y - HALF.y
				_on_ground = true
			elif _vel.y < 0.0:
				player.position.y = r.end.y + HALF.y
			_vel.y = 0.0

func _hits(r: Rect2) -> bool:
	return absf(player.position.x - (r.position.x + r.size.x * 0.5)) < HALF.x + r.size.x * 0.5 \
		and absf(player.position.y - (r.position.y + r.size.y * 0.5)) < HALF.y + r.size.y * 0.5

func _move_hazards(delta: float) -> void:
	for h in hazards:
		if not is_instance_valid(h):
			continue
		var d: float = h.get_meta("dir")
		h.position.x += d * 48.0 * delta
		if h.position.x > float(h.get_meta("x1")):
			h.set_meta("dir", -1.0)
		elif h.position.x < float(h.get_meta("x0")):
			h.set_meta("dir", 1.0)
		if h.position.distance_to(player.position) < 14.0:
			Probe.event("player_hit")
			_respawn()
			lose_life()

func _check_pickups() -> void:
	var keep: Array = []
	for p in prizes:
		if not is_instance_valid(p):
			continue
		if p.position.distance_to(player.position) < 15.0:
			Probe.event("prize_taken")
			add_score(25)
			Juice.pop(player)
			Audio.play("coin")
			p.queue_free()
			continue
		keep.append(p)
	prizes = keep
	if prizes.is_empty() and not finished:
		Probe.event("all_collected")
		Audio.play("win")
		win()

func _respawn() -> void:
	player.position = _spawn
	_vel = Vector2.ZERO
	Juice.hit(6.0)
