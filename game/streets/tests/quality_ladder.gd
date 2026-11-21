extends SceneTree
## The quality ladder fed made-up frame times: a smooth 50 fps PC with a hitch every few
## seconds; a slow phone that each step down helps; a PC that recovers; a level that keeps
## failing; a phone the levels do not help at all (a user's, in Tel Aviv: quality 0 at 25-27
## fps, it never came back up) and one that only the first step helps.
##   STREETS_BUILD_ALL=0 $GODOT --headless --path . -s res://game/streets/tests/quality_ladder.gd
## Good: [2]; [2, 1, 0]; [0, 1, 2, 3]; down to 1 and kept there (the top fails, 2 is no better);
## [2, 1, 0, 2] staying at 2 for FLOOR_S, then tried again; [2, 1, 0, 1].
var g: Node
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
	feed("a phone the levels do not help: 26 fps at every level, 10 min", 600.0, [26.0, 26.0, 26.0, 26.0])
	fresh()
	feed("only the first step helps: 26 fps at 2, 33 at 1 and 0, 2 min", 120.0, [33.0, 33.0, 26.0, 26.0])
	quit(0)
