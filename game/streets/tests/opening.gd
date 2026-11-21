extends SceneTree
## The opening (opening.gd), staged as a player gets it: STREETS_OPENING=1 (a test has none
## otherwise) and STREETS_BUILD_ALL=0 (the near-first build it hides). Prints how many squares
## within NEAR_FIRST of the car were still bare as the car was shown -- what used to go up in
## view -- how long the opening ran and how many were still bare when it came down (0 is the
## point of it), then shots: up there at 1 s and 3 s, and at the car 3 s after landing.
##   STREETS_OPENING=1 STREETS_BUILD_ALL=0 LEVEL=1 $GODOT --path . -s res://game/streets/tests/opening.gd
## PASS: an opening ran, came down within MAX_S with 0 bare squares near the car (or at MAX_S),
## and the city runs afterwards (the car's clock moves).
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.05).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	var bare := 0
	for t: Vector2i in g._tiles_todo:
		if g._tile_dist(t, g._pos) < g.NEAR_FIRST:
			bare += 1
	print("OPENING bare squares near the car as it was shown: %d" % bare)
	var out := OS.get_environment("OUT")
	var t0 := Time.get_ticks_msec()
	var shot := 0
	while g._opening != null and g._opening.on and Time.get_ticks_msec() - t0 < 40000:
		await process_frame
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		if out != "" and ((shot == 0 and secs > 1.0) or (shot == 1 and secs > 3.0)):
			root.get_viewport().get_texture().get_image().save_png(out + "/opening_%d.png" % shot)
			shot += 1
	if g._opening == null:
		print("OPENING: FAIL (none ran -- STREETS_OPENING=1?)")
		quit(0)
		return
	print("OPENING ran %.1f s, bare squares near the car when it came down: %d" % [g._opening.t, g._opening.squares_at_end])
	await create_timer(3.0).timeout
	if out != "":
		root.get_viewport().get_texture().get_image().save_png(out + "/opening_landed.png")
	var clock0: float = g._sig_t
	var ph0: int = g._sig_phase
	await create_timer(2.0).timeout
	var runs: bool = g._sig_t != clock0 or g._sig_phase != ph0
	var ok: bool = (g._opening.squares_at_end == 0 or g._opening.t >= g._opening.MAX_S - 0.1) and runs and not g._paused
	print("OPENING: %s (city running after: %s)" % ["PASS" if ok else "FAIL", runs])
	quit(0)
