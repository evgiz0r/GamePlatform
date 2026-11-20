extends SceneTree
## Frames that hang, as a player meets them: the city loaded as for a player (run with
## STREETS_BUILD_ALL=0), DRIVE seconds of autodrive (default 60) while the squares further
## out are built behind, then up over the city (the view from above, paused) and dragged
## round for UP seconds (default 30), then back down. Every frame over 250 ms is counted
## with what took it (the game's own [hitch] line: the script's parts, and "rest" -- the
## engine: drawing, uploading new meshes, compiling shaders). Prints, per phase: frames,
## hitches over 250 ms / 1 s, the worst; `hitch_parts.py <log>` sums the game's [hitch] lines
## per phase (what took the time: a script part, or "rest", the engine).
##   STREETS_BUILD_ALL=0 tests/run.sh hitches 7
var g: Node
var phase := "load"
var stats := {}       # phase -> {frames, over250, over1000, worst, time}
var last := 0

func _initialize() -> void:
	_run()

func _process(_dt: float) -> bool:
	var now := Time.get_ticks_usec()
	if last > 0 and g != null and g._loaded:
		var ms := (now - last) / 1000.0
		var s: Dictionary = stats.get(phase, {"frames": 0, "over250": 0, "over1000": 0, "worst": 0.0, "time": 0.0})
		s["frames"] += 1
		s["time"] += ms
		if ms > 250.0:
			s["over250"] += 1
		if ms > 1000.0:
			s["over1000"] += 1
		s["worst"] = maxf(float(s["worst"]), ms)
		stats[phase] = s
	last = now
	return false

func _drag(from: Vector2, to: Vector2, steps: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = from
	ev.global_position = from
	root.push_input(ev, true)
	for i in range(1, steps + 1):
		var m := InputEventMouseMotion.new()
		var p := from.lerp(to, float(i) / steps)
		m.position = p
		m.global_position = p
		m.relative = (to - from) / steps
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m, true)
		await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	root.push_input(up, true)

func _report() -> void:
	for ph: String in ["drive", "up", "down"]:
		if not stats.has(ph):
			continue
		var s: Dictionary = stats[ph]
		print("%-6s %4d frames in %.0f s, %.0f ms a frame; over 250 ms: %d, over 1 s: %d, worst %.0f ms" % [ph,
			s["frames"], float(s["time"]) / 1000.0, float(s["time"]) / maxf(1.0, float(s["frames"])), s["over250"], s["over1000"],
			s["worst"]])
	print("squares built %d, still to build %d" % [g._tiles_done.size(), g._tiles_todo.size()])

func _run() -> void:
	await create_timer(0.3).timeout
	var t0 := Time.get_ticks_msec()
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	print("loaded in %.1f s (wall); the game's own: %s" % [(Time.get_ticks_msec() - t0) / 1000.0, g._load_text()])
	var drive := float(OS.get_environment("DRIVE")) if OS.get_environment("DRIVE") != "" else 60.0
	var upt := float(OS.get_environment("UP")) if OS.get_environment("UP") != "" else 30.0
	phase = "drive"
	print("PHASE drive")   # (the game's [hitch] lines after this belong to it: hitch_parts.py)
	g._set_auto(true)
	await create_timer(drive).timeout
	phase = "up"
	print("PHASE up")
	g._zoom_set(g.ZOOM_UP)
	var t := 0.0
	var k := 0
	while t < upt:
		var a := Vector2(320, 180)
		var b := a + Vector2.from_angle(k * 1.3) * 140.0
		await _drag(a, b, 20)
		await create_timer(1.5).timeout
		t += 3.0
		k += 1
	phase = "down"
	print("PHASE down")
	g._zoom_set(0.0)
	await create_timer(15.0).timeout
	_report()
	quit(0)
