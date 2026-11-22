extends SceneTree
## Does the background build keep up with autodrive on a slow machine? A work laptop's browser
## ran Tel Aviv at 10-20 fps and read "building the city 30%" after minutes of driving (22 Nov
## 2026). The build's budget is wall time a frame (BUILD_US, half when frames are slow,
## BUILD_FAR_US once all within SEE_M is built), so a machine at 12 fps gets a fifth of the
## building a second that one at 60 does. Run with --fixed-fps 12: each frame is then 1/12 s
## of game time and gets that frame's budget, as the laptop's did; this machine's native
## GDScript is about as fast as that laptop's wasm (the container ~3x slower than a laptop,
## wasm ~2-3x slower than native), so the game seconds here are roughly the laptop's seconds.
## Every 10 game seconds: squares built, the bare ones near the car and within sight (_see_m),
## whether the car is in one, whether the far ones are held (_far_hold: slow frames), the HUD's line.
## Q=0 drops to quality 0 first (its reach: sight 450 m).
##   LEVEL=7 SECS=240 $GODOT --headless --fixed-fps 12 --path . -s res://game/streets/tests/build_pace.gd
##   (Tel Aviv; about 2 minutes. FPS=60 for a fast machine's pace, same command.)
## Good: "car in a bare square" never, "bare within 320 m" back to 0 within a square's drive;
## at 12 fps FAR HELD once all in sight is up (22 Nov 2026, before the hold: 33 of 150 built
## after 240 s at 12 fps, all within 900 m at 179 s; at 60 fps all 150 at 219 s).
var g: Node

func _initialize() -> void:
	_run()

func _bare_within(m: float) -> int:
	var n := 0
	for t: Vector2i in g._tiles_todo:
		if g._tile_dist(t, g._pos) < m:
			n += 1
	return n

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	if OS.get_environment("Q") != "":
		g._set_quality(int(OS.get_environment("Q")))
	g._set_auto(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 240.0
	var t := 0.0
	var next := 0.0
	var driven := 0.0
	var last: Vector2 = g._pos
	var in_bare := 0.0
	var worst_near := 0
	var seen_at := -1.0
	var done_at := -1.0
	print("BUILD PACE (level %s): %d squares, %d built at the start" % [OS.get_environment("LEVEL"), g._build_total, g._tiles_done.size()])
	var w0 := Time.get_ticks_msec()
	while t < secs:
		await process_frame
		var dt: float = g.get_process_delta_time()
		t += dt
		driven += g._pos.distance_to(last)
		last = g._pos
		var mine: Vector2i = g._tile_of(g._pos)
		if g._tiles_todo.has(mine):
			in_bare += dt
		var near := _bare_within(g.NEAR_FIRST)
		worst_near = maxi(worst_near, near)
		if seen_at < 0.0 and _bare_within(g._see_m()) == 0:
			seen_at = t
		if done_at < 0.0 and g._tiles_todo.is_empty():
			done_at = t
		if t >= next:
			next += 10.0
			print("  %4.0f s  built %3d/%d  bare within 320 m %d, %.0f m %2d  car in a bare square: %s  budget %5d us%s%s  driven %5.0f m  \"%s\"" % [
				t, g._tiles_done.size(), g._build_total, near, g._see_m(), _bare_within(g._see_m()), "YES" if g._tiles_todo.has(mine) else "no",
				g._build_us, " catch-up" if g._catch_up else "", " FAR HELD" if g._far_held else "", driven, g._build_near_txt])
	print("BUILD PACE: %.0f game s (%.0f s wall), driven %.0f m; every square within sight built %s; all built %s; %d of %d built; car in a bare square %.1f s; most bare within 320 m %d" % [
		t, (Time.get_ticks_msec() - w0) / 1000.0, driven, ("at %.0f s" % seen_at) if seen_at >= 0.0 else "never",
		("at %.0f s" % done_at) if done_at >= 0.0 else "not yet", g._tiles_done.size(), g._build_total, in_bare, worst_near])
	quit(0)
