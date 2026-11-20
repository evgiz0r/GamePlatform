extends SceneTree
## The quality ladder fed made-up frame times: a smooth 50 fps PC with a hitch every few
## seconds; a slow phone at 35; a PC that recovers; a level that keeps failing.
var g: Node
func _initialize() -> void:
	_run()
func feed(label: String, secs: float, frame: float, hitch_every := 0.0) -> void:
	var t := 0.0
	var next_hitch := hitch_every
	var trail: Array = []
	while t < secs:
		var dt := frame
		if hitch_every > 0.0 and t >= next_hitch:
			dt = 0.48
			next_hitch += hitch_every
		g._judge_fps(dt)
		t += dt
		if trail.is_empty() or trail.back() != g._quality:
			trail.append(g._quality)
	print("%s: levels %s" % [label, str(trail)])
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
	feed("then slow, 35 fps, 20 s", 20.0, 1.0 / 35.0)
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
	quit(0)
