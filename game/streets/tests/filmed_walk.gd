extends SceneTree
## The filmed walk (the place with a "walk" in LEVELS: level 5): it loads, walks on its own
## and stops where its film did. At each of AT (seconds into the walk, default the
## landmarks below) it jumps there, lets the eye settle and saves a shot, printing where it
## is and the nearest wall -- the shots are what to put beside the film's frames at the
## same seconds. RECORD=1 instead plays the whole walk from the start and saves every frame,
## named by the walk's own clock (run with --fixed-fps 10 for a frame per 0.1 s): the game's
## half of a side-by-side video (DEV.md, "The filmed walk").
var g: Node
const LANDMARKS := "8,28,40,55,70,84,94"   # the zebra, the forecourt, the passage, its end, the little street, Sheinkin, Ha-Meri

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 5})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var out := OS.get_environment("OUT")
	if g._film.is_empty():
		print("FAIL no walk: is this the walk's level?")
		quit(1)
		return
	var last: float = g._film[g._film.size() - 1].z
	print("walk of %.0f s, %d points, from %s to %s, on foot %s, hud shown %s" % [last, g._film.size(),
		Vector2i(g._film_at(0.0)), Vector2i(g._film_at(last)), g._walking, g._hud.visible])
	if OS.get_environment("RECORD") == "1":
		while g._film_t <= last + 0.5:
			await RenderingServer.frame_post_draw
			var t: float = g._film_t
			root.get_viewport().get_texture().get_image().save_jpg(out + "/f%05d.jpg" % int(round(t * 10.0)), 0.88)
		print("recorded to ", out)
		quit()
		return
	var at := OS.get_environment("AT") if OS.get_environment("AT") != "" else LANDMARKS
	for s: String in at.split(","):
		var t := float(s)
		g._film_t = t - 1.5   # a moment before, for the head to turn the way it walks
		for i in range(20):
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out + "/t%03d.png" % int(t))
		# what is nearest: anything solid within a step means the walk goes through it
		var hit: Vector2 = g._push_out(g._pos, 0.3, true, false)
		print("t=%3d s at %s  facing %3d deg  %s" % [int(t), Vector2i(g._pos), int(rad_to_deg(g._yaw)),
			"clear" if hit == Vector2.ZERO else "INSIDE %s (%.2f m)" % [g._last_hit, hit.length()]])
	g._film_t = last + 1.0
	for i in range(30):
		await physics_frame
	print("at the end: done %s, standing at %s, speed %.2f" % [g._film_done, Vector2i(g._pos), g._v])
	quit()
