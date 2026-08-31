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
## How many screenshots to capture across the run. Requires running WITHOUT --headless,
## because the headless display driver renders nothing and would save black frames.
var shots := 0

var _t := 0.0
var _ended := false
var _won := false
var _score := 0
var _done := false
var _bot: SimBot

func _ready() -> void:
	seed(seed_value)
	if shots > 0:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
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

var _shots_taken := 0

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if shots > 0 and _shots_taken < shots:
		# spread captures evenly, skipping the first moment when the fade is still up
		var due := 0.6 + float(_shots_taken) * (seconds - 0.8) / float(shots)
		if _t >= due:
			_shots_taken += 1
			_capture(_shots_taken)
	if _ended or _t >= seconds:
		_finish()

func _capture(idx: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "res://shots/%s_%02d.png" % [game_id, idx]
	img.save_png(path)
	print("[shot] " + ProjectSettings.globalize_path(path))

func _finish() -> void:
	_done = true
	# a timed-out run never fired game_over, so read the live score off the game.
	# guarded: a game whose script failed to compile instantiates without these members,
	# and an error here used to leave the process hanging instead of reporting.
	var g := Flow.current_game
	if g != null and is_instance_valid(g):
		if not g.has_method("start"):
			Probe.note("the game scene loaded but has no GameMode script attached -- "
				+ "it almost certainly failed to compile. Check the parse errors above.")
		elif not _ended and "score" in g:
			_score = g.score
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
