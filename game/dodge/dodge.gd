extends GameMode
## Starter game: survive, grab prizes, avoid hazards.
## Reference implementation of the contract -- read this before writing a new game.

const PLAYER_SPEED := 165.0
const HAZARD_SPEED := 62.0

var player: Blob
var hazards: Array = []
var prizes: Array = []
var _spawn_t := 0.0
var _prize_t := 0.0
var _elapsed := 0.0

func _ready() -> void:
	title = "dodge"
	play_area = Rect2(0, 0, 640, 360)
	super()

func start(_config: Dictionary) -> void:
	var cam := Camera2D.new()
	cam.position = center()
	cam.make_current()
	add_child(cam)

	set_lives(3)
	player = _blob("player", 9.0, "circle", "ranger", 1.7)
	player.position = center()
	Probe.track(player, "@")

	Probe.capture("start")

func _process(delta: float) -> void:
	if finished:
		return
	_elapsed += delta

	player.position += PInput.dir() * PLAYER_SPEED * delta
	player.position = player.position.clamp(play_area.position, play_area.end)

	# difficulty ramps with time -- the whole game is this one line
	var rate: float = maxf(0.28, 0.95 - _elapsed * 0.02)
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = rate
		_spawn_hazard()
	_prize_t -= delta
	if _prize_t <= 0.0:
		_prize_t = 1.7
		_spawn_prize()

	_move_hazards(delta)
	_check_prizes()

	if _elapsed >= 5.0 and int(_elapsed) % 10 == 0 and _elapsed - floorf(_elapsed) < delta:
		Probe.capture("mid-game")

func _spawn_hazard() -> void:
	var h := _blob("hazard", 8.0, "triangle", "spider", 1.5)
	h.position = random_edge_point(-10.0)
	h.set_meta("vel", (player.position - h.position).normalized() * HAZARD_SPEED)
	hazards.append(h)
	Probe.track(h, "x")
	Probe.event("hazard_spawn")

func _spawn_prize() -> void:
	var p := _blob("prize", 6.0, "diamond", "gold_bar", 1.2)
	p.position = Vector2(randf_range(30, play_area.size.x - 30), randf_range(30, play_area.size.y - 30))
	prizes.append(p)
	Probe.track(p, "*")
	Probe.event("prize_spawn")

func _move_hazards(delta: float) -> void:
	var keep: Array = []
	for h in hazards:
		if not is_instance_valid(h):
			continue
		h.position += h.get_meta("vel") * delta
		if h.position.distance_to(player.position) < 15.0:
			Probe.event("player_hit")
			h.queue_free()
			lose_life()
			continue
		if not in_play_area(h.position, 40.0):
			Probe.event("hazard_escaped")
			h.queue_free()
			continue
		keep.append(h)
	hazards = keep

func _check_prizes() -> void:
	var keep: Array = []
	for p in prizes:
		if not is_instance_valid(p):
			continue
		if p.position.distance_to(player.position) < 14.0:
			Probe.event("prize_taken")
			add_score(10)
			Juice.pop(player)
			Audio.play("coin")
			p.queue_free()
			continue
		keep.append(p)
	prizes = keep

## sprite is optional -- pass "" and you get the glowing placeholder shape instead
func _blob(role: String, radius: float, shape: String, sprite: String = "", scale: float = 2.0) -> Blob:
	var b := Blob.new()
	b.role = role
	b.radius = radius
	b.shape = shape
	add_child(b)
	if sprite != "":
		b.set_sprite(sprite, scale)
	return b
