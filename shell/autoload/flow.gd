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
var _sound_btn: Button
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

	_build_sound_toggle()

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
	# deliberately faint: it is a diagnostic, not part of the game's look. "ink" dimmed
	# rather than a palette role, so it stays unobtrusive whichever palette is active.
	var stamp := UIKit.label(_build_stamp(), 9, "ink")
	stamp.modulate.a = 0.3
	nodes.append(stamp)
	var col := UIKit.center_column(nodes)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(col)
	_ui.mouse_filter = Control.MOUSE_FILTER_PASS

## Which build is on screen. An installed web app updates silently in the background and
## only swaps over on a later launch, so without this there is no way to tell from the
## device whether a change has actually landed. Written by tools/publish_web.sh.
func _build_stamp() -> String:
	if not FileAccess.file_exists("res://build.txt"):
		return "dev build"
	var f := FileAccess.open("res://build.txt", FileAccess.READ)
	if f == null:
		return "dev build"
	return "build " + f.get_as_text().strip_edges()

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

## ---- sound toggle -----------------------------------------------------------

## A plain on/off, not a volume level -- the menu-level percentage slider this replaced
## required backing out of whatever game you were in to reach it, which made no sense
## mid-game. This lives directly on _layer, a sibling of _ui rather than a child of it, so
## _clear_stage() (which frees every child of _ui on every menu<->game transition) never
## touches it: it is built once and is on screen for the rest of the run, menu or game.
func _build_sound_toggle() -> void:
	_sound_btn = UIKit.button("", _toggle_sound)
	_sound_btn.name = "SoundButton"
	# "at all times" includes while a game is paused -- everything else under _layer
	# defaults to pausable and the pause screen has to opt out the same way (see
	# toggle_pause() below), so this needs the same explicit opt-out.
	_sound_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	# sits directly left of where the per-game "menu" button appears (566,8 size 62x22)
	_sound_btn.custom_minimum_size = Vector2(56, 22)
	_sound_btn.size = Vector2(56, 22)
	_sound_btn.position = Vector2(502, 8)
	_sound_btn.add_theme_font_size_override("font_size", 12)
	_layer.add_child(_sound_btn)
	_update_sound_btn()

func _update_sound_btn() -> void:
	var on := not Audio.muted()
	_sound_btn.text = "sound" if on else "muted"
	_sound_btn.modulate.a = 1.0 if on else 0.55

func _toggle_sound() -> void:
	SaveData.set_value("muted", not Audio.muted())
	if Audio.muted():
		Audio.stop_music()
	else:
		Audio.play("select")
	_update_sound_btn()

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

	# Always-available way out. Pause has one too, but on a phone there is no Escape key,
	# so without this the only exit from a game is the browser's back button.
	var out := UIKit.button("menu", goto_menu)
	out.name = "MenuButton"
	# Fixed position in the 640x360 design space, like the score row above. Anchoring it to
	# the right edge did not render at all here; this is the idiom that works in this file.
	out.custom_minimum_size = Vector2(62, 22)
	out.size = Vector2(62, 22)
	out.position = Vector2(566, 8)
	out.add_theme_font_size_override("font_size", 12)
	_hud.add_child(out)

	_ui.add_child(_hud)
	_ui.mouse_filter = Control.MOUSE_FILTER_PASS

## True while the pointer is over the shell's own HUD controls.
##
## Games read mouse clicks in _input(), which runs BEFORE the GUI gets a look, so a tap on
## the menu button would otherwise also fire the game's action underneath it. Every game
## that acts on a click should bail out when this is true.
func pointer_over_hud() -> bool:
	# the sound toggle is present even outside a game (see _build_sound_toggle), so check
	# it whether or not _hud exists
	if _sound_btn != null and is_instance_valid(_sound_btn) and _sound_btn.visible \
			and _sound_btn.get_global_rect().has_point(_sound_btn.get_global_mouse_position()):
		return true
	if _hud == null or not is_instance_valid(_hud):
		return false
	var b := _hud.find_child("MenuButton", true, false) as Control
	if b == null or not b.is_visible_in_tree():
		return false
	return b.get_global_rect().has_point(b.get_global_mouse_position())

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
