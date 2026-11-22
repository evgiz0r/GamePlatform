extends SceneTree
## Run by tools/record_video.sh under Godot's movie maker (--write-movie, --fixed-fps): starts
## GAME at LEVEL, waits until the game is ready to be filmed, hides the shell's buttons and asks
## the game to hide its own, prints the frame filming starts at (the wrapper cuts the video
## there), and quits after SECS of game time -- or sooner, a moment after the game says its
## film is done. All three asks are optional: a game that has none is filmed from its first
## frame, as it looks, for SECS.
##   film_ready() -> bool    the world is up (a city built, a level laid out)
##   film_mode(on)           hide the HUD and buttons, keep the captions
##   film_done() -> bool     the scene it plays has ended

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _run() -> void:
	var game_name := _env("GAME", "")
	var level := int(_env("LEVEL", "1"))
	var secs := float(_env("SECS", "60"))
	await create_timer(0.3).timeout
	var flow = root.get_node("Flow")
	flow.start_game(game_name, {"level": level})
	var g: Node = null
	var waited := 0
	while true:
		await process_frame
		waited += 1
		if g == null:
			for n in root.find_children("*", "Node", true, false):
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("/%s.gd" % game_name):
					g = n
					break
		if g != null and (not g.has_method("film_ready") or g.film_ready()):
			break
		if waited > 60 * 60 * 20:
			print("RECORD: the game never got ready")
			quit(1)
			return
	if g.has_method("film_mode"):
		g.film_mode(true)
	if "_layer" in flow and flow._layer != null:
		flow._layer.visible = false   # (the shell's sound and exit buttons)
	await process_frame
	var start := Engine.get_frames_drawn()
	print("RECORD_START %d" % start)
	var frames := 0
	var most := int(secs * float(_env("FPS", "60")))   # (the movie maker's frames: 1/FPS of game time each)
	while frames < most:
		await process_frame
		frames += 1
		if g.has_method("film_done") and g.film_done():
			break
	print("RECORD_END %d (%d frames filmed)" % [Engine.get_frames_drawn(), frames])
	quit(0)
