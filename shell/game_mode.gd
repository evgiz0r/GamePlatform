class_name GameMode extends Node2D
## THE CONTRACT. Every game in game/ extends this and overrides `start()`.
## In exchange the shell gives you: main menu, pause, game over, score HUD, high scores,
## palette/reskin, screen shake, and headless self-play. Do not build any of that yourself.
##
## Minimum viable game:
##   extends GameMode
##   func start(_cfg): spawn_stuff()
##   ... later ...  add_score(10)   lose_life()   win()

## Shown on the menu button and in playtest reports.
@export var title := "Untitled"
## Playfield in world coordinates. Used for the ASCII snapshot and out-of-bounds checks.
@export var play_area := Rect2(0, 0, 640, 360)

var score := 0
var lives := 3
var finished := false

func _ready() -> void:
	Probe.world_rect = play_area
	Probe.title = title
	Bus.lives_changed.emit(lives)
	Bus.score_changed.emit(score)

## Override this. Called by the shell once the game is on screen.
func start(_config: Dictionary) -> void:
	pass

## ---- the verbs games should use -------------------------------------------

func add_score(n: int) -> void:
	score += n
	Bus.score_changed.emit(score)
	Probe.event("score", {"total": score})

func set_lives(n: int) -> void:
	lives = n
	Bus.lives_changed.emit(lives)

func lose_life(n: int = 1) -> void:
	if finished:
		return
	lives -= n
	Bus.lives_changed.emit(lives)
	Probe.event("player_hurt", {"lives": lives})
	Juice.hit(7.0)
	Audio.play("hurt")
	if lives <= 0:
		lose()

func win() -> void:
	_finish(true)

func lose() -> void:
	_finish(false)

func _finish(won: bool) -> void:
	if finished:
		return
	finished = true
	Bus.game_over.emit(won, score)

## ---- helpers ---------------------------------------------------------------

func center() -> Vector2:
	return play_area.position + play_area.size * 0.5

func random_edge_point(margin: float = 0.0) -> Vector2:
	var r := play_area.grow(margin)
	match randi() % 4:
		0: return Vector2(randf_range(r.position.x, r.end.x), r.position.y)
		1: return Vector2(randf_range(r.position.x, r.end.x), r.end.y)
		2: return Vector2(r.position.x, randf_range(r.position.y, r.end.y))
		_: return Vector2(r.end.x, randf_range(r.position.y, r.end.y))

func in_play_area(p: Vector2, margin: float = 0.0) -> bool:
	return play_area.grow(margin).has_point(p)
