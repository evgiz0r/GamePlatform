extends Node
## Owns the whole app shell: menu -> game -> pause -> game over -> menu, with fades.
## Games never manage any of this. A game that crashes drops you back to a working menu.

const GAMES_DIR := "res://game/"

var current_game: Node = null
var current_id := ""
var _stage: Node = null
var _layer: CanvasLayer
var _fade: ColorRect
var _ui: Control
var _hud: Control
var _score := 0
var _lives := 0
var _in_game := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build.call_deferred()

func _build() -> void:
	_stage = Node.new()
	_stage.name = "Stage"
	get_tree().root.add_child(_stage)

	_layer = CanvasLayer.new()
	_layer.layer = 10
	get_tree().root.add_child(_layer)

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_ui)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)

	Bus.score_changed.connect(_on_score)
	Bus.lives_changed.connect(_on_lives)
	Bus.game_over.connect(_on_game_over)

	if _maybe_start_sim():
		return
	goto_menu()

## Command line: -- --sim=<game> --bot=<policy> --seconds=<n> --seed=<n>
func _maybe_start_sim() -> bool:
	var a := {}
	for raw in OS.get_cmdline_user_args():
		var kv := raw.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			a[kv[0]] = kv[1]
	if not a.has("sim"):
		return false
	var runner = load("res://shell/sim/sim_runner.gd").new()
	runner.game_id = a["sim"]
	runner.policy = a.get("bot", "smart")
	runner.seconds = float(a.get("seconds", "30"))
	runner.seed_value = int(a.get("seed", "12345"))
	runner.shots = int(a.get("shots", "0"))
	get_tree().root.add_child(runner)
	return true

func _unhandled_input(_e: InputEvent) -> void:
	if _in_game and PInput.just_pressed("pause"):
		toggle_pause()

## ---- transitions -----------------------------------------------------------

func _fade_to(cb: Callable, dur: float = 0.18) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, dur)
	tw.tween_callback(cb)
	tw.tween_property(_fade, "color:a", 0.0, dur)

func _clear_stage() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	_in_game = false
	current_game = null
	for c in _stage.get_children():
		c.queue_free()
	for c in _ui.get_children():
		c.queue_free()

## ---- screens ---------------------------------------------------------------

func goto_menu() -> void:
	_fade_to(_show_menu)

func _show_menu() -> void:
	_clear_stage()
	Palette.use(SaveData.data.get("palette", "neon_candy"))
	var games := list_games()
	var nodes: Array = [
		UIKit.label("GAME PLATFORM", 34, "player"),
		UIKit.label("pick a game", 13, "accent"),
	]
	if games.is_empty():
		nodes.append(UIKit.label("no games in res://game/ yet -- ask your AI for one", 12, "warn"))
	for g in games:
		var id: String = g["id"]
		var best := SaveData.best_for(id)
		var caption: String = g["title"] + ("   best %d" % best if best > 0 else "")
		nodes.append(UIKit.button(caption, func(): start_game(id)))
	nodes.append(UIKit.button("look: " + Palette.active, _cycle_palette))
	if not OS.has_feature("web"):
		nodes.append(UIKit.button("quit", func(): get_tree().quit()))
	var col := UIKit.center_column(nodes)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(col)
	_ui.mouse_filter = Control.MOUSE_FILTER_PASS

func _cycle_palette() -> void:
	var all := Palette.names()
	var i := all.find(Palette.active)
	Palette.use(all[(i + 1) % all.size()])
	SaveData.set_value("palette", Palette.active)
	_show_menu()

## Every subfolder of res://game/ holding a <name>.tscn is a game. No registry to maintain.
func list_games() -> Array:
	var out: Array = []
	var d := DirAccess.open(GAMES_DIR)
	if d == null:
		return out
	for sub in d.get_directories():
		var path := GAMES_DIR + sub + "/" + sub + ".tscn"
		if ResourceLoader.exists(path):
			out.append({"id": sub, "path": path, "title": sub.replace("_", " ")})
	return out

func start_game(id: String) -> void:
	current_id = id
	_fade_to(func(): _launch(id))

func _launch(id: String) -> void:
	_clear_stage()
	var path := GAMES_DIR + id + "/" + id + ".tscn"
	if not ResourceLoader.exists(path):
		push_error("no such game: " + path)
		_show_menu()
		return
	var scn: PackedScene = load(path)
	current_game = scn.instantiate()
	var bd := Backdrop.new()
	if "play_area" in current_game:
		bd.area = current_game.play_area
	_stage.add_child(bd)
	_stage.add_child(current_game)
	_in_game = true
	_score = 0
	_lives = 0
	_build_hud()
	if current_game.has_method("start"):
		current_game.start({})
	else:
		push_error("game '%s' has no GameMode script (compile error?)" % id)
		Probe.note("game '%s' failed to load its script" % id)
		Bus.game_over.emit(false, 0)
	Probe.event("game_start", {"id": id})

func restart() -> void:
	if current_id != "":
		start_game(current_id)

## ---- hud / pause / game over ----------------------------------------------

func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.position = Vector2(10, 8)
	row.add_theme_constant_override("separation", 18)
	var score := UIKit.label("0", 18, "ink")
	score.name = "Score"
	var lives := UIKit.label("", 18, "hazard")
	lives.name = "Lives"
	row.add_child(score)
	row.add_child(lives)
	_hud.add_child(row)
	_ui.add_child(_hud)

func _on_score(v: int) -> void:
	_score = v
	if _hud != null and is_instance_valid(_hud):
		var l := _hud.find_child("Score", true, false)
		if l != null:
			l.text = str(v)

func _on_lives(v: int) -> void:
	_lives = v
	if _hud != null and is_instance_valid(_hud):
		var l := _hud.find_child("Lives", true, false)
		if l != null:
			l.text = "*".repeat(maxi(0, v))

func toggle_pause() -> void:
	if not _in_game:
		return
	var tree := get_tree()
	tree.paused = not tree.paused
	if tree.paused:
		var p := UIKit.center_column([
			UIKit.label("PAUSED", 28, "player"),
			UIKit.button("resume", toggle_pause),
			UIKit.button("restart", func(): toggle_pause(); restart()),
			UIKit.button("menu", func(): toggle_pause(); goto_menu()),
		])
		p.name = "PauseUI"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		_ui.add_child(p)
		_ui.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		var existing := _ui.find_child("PauseUI", false, false)
		if existing != null:
			existing.queue_free()

func _on_game_over(won: bool, score: int) -> void:
	if not _in_game:
		return
	_in_game = false
	Engine.time_scale = 1.0
	Probe.event("game_over", {"won": won, "score": score})
	var record := SaveData.submit_score(current_id, score)
	var head := "YOU WIN" if won else "GAME OVER"
	var col := UIKit.center_column([
		UIKit.label(head, 30, "player" if won else "hazard"),
		UIKit.label("score %d%s" % [score, "   NEW BEST!" if record else ""], 16, "warn" if record else "ink"),
		UIKit.button("play again", restart),
		UIKit.button("menu", goto_menu),
	])
	col.process_mode = Node.PROCESS_MODE_ALWAYS
	_ui.add_child(col)
	_ui.mouse_filter = Control.MOUSE_FILTER_PASS
