extends SceneTree
## The quality ladder fed made-up frame times: a smooth 50 fps PC with a hitch every few
## seconds; a slow phone that each step down helps; a PC that recovers; a level that keeps
## failing; a machine the levels do not help at all (a user's PC in Tel Aviv: quality 0 at 25-27
## fps, it never came back up) and one that only the first step helps.
##   STREETS_BUILD_ALL=0 $GODOT --headless --path . -s res://game/streets/tests/quality_ladder.gd
## Good: [2]; [2, 1, 0]; [0, 1, 2, 3]; down to 1 and kept there (the top fails, 2 is no better);
## [2, 1, 0, 2] staying at 2 for FLOOR_S, then tried again; [2, 1, 0, 1]; and two CHECK lines
## PASS: the ladder steps down while the rest of the city builds in the background (it never
## did: a work laptop sat at quality 2 and 7 fps for the build's hour), and holds while the
## squares round the car are still catching up.
var g: Node
var fails := 0

## through the gate in front of the ladder (_watch_fps), as a browser runs it; the lowest
## level it reached
func feed_watched(label: String, secs: float, fps: float) -> int:
	var t := 0.0
	var lowest: int = g._quality
	var trail: Array = []
	while t < secs:
		var dt := 1.0 / fps
		g._watch_fps(dt)
		t += dt
		lowest = mini(lowest, g._quality)
		if trail.is_empty() or trail.back()[0] != g._quality:
			trail.append([g._quality, int(t)])
	print("%s: levels [level, at s] %s" % [label, str(trail)])
	return lowest

func check(what: String, ok: bool) -> void:
	print("CHECK %s: %s" % [what, "PASS" if ok else "FAIL"])
	if not ok:
		fails += 1
func _initialize() -> void:
	_run()
## frame: seconds a frame, or an Array of the frame rate at each level (0..3)
func feed(label: String, secs: float, frame: Variant, hitch_every := 0.0) -> void:
	var t := 0.0
	var next_hitch := hitch_every
	var trail: Array = []
	while t < secs:
		var dt: float = 1.0 / float(frame[g._quality]) if frame is Array else float(frame)
		if hitch_every > 0.0 and t >= next_hitch:
			dt = 0.48
			next_hitch += hitch_every
		g._judge_fps(dt)
		t += dt
		if trail.is_empty() or trail.back()[0] != g._quality:
			trail.append([g._quality, int(t)])
	print("%s: levels [level, at s] %s" % [label, str(trail)])

func fresh() -> void:   # a new drive's ladder
	g._set_quality(2)
	g._fps_wait = 0.0
	g._fps_low = 0
	g._fps_good = 0.0
	g._q_descent = {}
	g._q_on_trial = false
	g._q_floor_until = 0.0
	g._q_fails = {}
	g._q_retry_at = {}
	g._q_clock = 0.0
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 1})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g.set_process(false)
	g._set_quality(2)
	g._fps_wait = 0.0
	feed("PC at 50 fps, a 0.48 s hitch every 5 s, 60 s", 60.0, 0.02, 5.0)
	feed("then slow: 35 fps at 2, 40 at 1, 55 at 0, 30 s", 30.0, [55.0, 40.0, 35.0, 30.0])
	feed("then 60 fps again, 120 s", 120.0, 1.0 / 60.0)
	feed("a level that fails each time: 60 fps but 30 at the top, 6 min", 0.0, 0.0)
	var t := 0.0
	var trail: Array = []
	while t < 360.0:
		var dt := 1.0 / 30.0 if g._quality >= 2 else 1.0 / 60.0
		g._judge_fps(dt)
		t += dt
		if trail.is_empty() or trail.back()[0] != g._quality:
			trail.append([g._quality, int(t)])
	print("  levels [level, at s]: %s" % str(trail))
	fresh()
	feed("a machine the levels do not help: 26 fps at every level, 10 min", 600.0, [26.0, 26.0, 26.0, 26.0])
	fresh()
	feed("only the first step helps: 26 fps at 2, 33 at 1 and 0, 2 min", 120.0, [33.0, 33.0, 26.0, 26.0])
	# the gate: what the background build left the ladder to do
	var was := [g._bg_build, g._catch_up, g._zoom_v]
	g._ladder_native = true
	g._zoom_v = 0.0
	fresh()
	g._fps_wait = 6.0   # (as a drive starts)
	g._bg_build = true
	g._catch_up = false
	var low := feed_watched("the rest of the city building in the background, a slow laptop at 7 fps, 60 s", 60.0, 7.0)
	check("the ladder steps down while the city builds in the background", low < 2)
	fresh()
	g._fps_wait = 6.0
	g._catch_up = true
	low = feed_watched("the squares round the car still bare (catching up) at 7 fps, 20 s", 20.0, 7.0)
	check("the ladder holds while the squares round the car catch up", low == 2)
	g._ladder_native = false
	g._bg_build = was[0]
	g._catch_up = was[1]
	g._zoom_v = was[2]
	print("the perf view's ladder line: %s" % " · ".join(g._q_log))
	check("the perf view says what the ladder did", g._q_log.size() > 0)
	print("QUALITY LADDER: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
