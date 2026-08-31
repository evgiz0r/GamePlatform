extends Node
## Headless self-play. Runs a game with a bot at the controls and prints a compact
## text report. Invoked from the command line, never from the menu:
##
##   godot --headless --fixed-fps 60 -- --sim=dodge --bot=smart --seconds=30
##
## Token budget is the whole point: the report is a couple of thousand characters,
## and it explains WHY something happened, which a screenshot cannot.

var game_id := "dodge"
var policy := "smart"
var seconds := 30.0
var seed_value := 12345

var _t := 0.0
var _ended := false
var _won := false
var _score := 0
var _done := false
var _bot: SimBot

func _ready() -> void:
	seed(seed_value)
	Probe.enabled = true
	Probe.reset(game_id)
	_bot = SimBot.new()
	_bot.policy = policy
	PInput.bot = _bot
	Bus.game_over.connect(_on_over)
	Flow.start_game(game_id)

func _on_over(won: bool, score: int) -> void:
	_won = won
	_score = score
	_ended = true

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _ended or _t >= seconds:
		_finish()

func _finish() -> void:
	_done = true
	# a timed-out run never fired game_over, so read the live score off the game
	if not _ended and Flow.current_game != null and is_instance_valid(Flow.current_game):
		_score = Flow.current_game.score
	Probe.capture("final")
	var checks := SimChecks.run(policy, _t, _ended, _won, _score)

	var lines: Array = []
	lines.append(Probe.report({
		"bot": policy,
		"seed": seed_value,
		"result": ("won" if _won else ("lost" if _ended else "survived to time limit")),
		"score": _score,
	}))
	lines.append("")
	lines.append("-- CHECKS --")
	for c in checks:
		lines.append("  %-4s %s" % [c[0], c[1]])
	lines.append("")
	lines.append("=== END REPORT ===")

	print("\n".join(lines))
	get_tree().quit(0)
