extends "res://game/streets/tests/perf_dive.gd"
## What a watched level (a walk, a test drive: `LEVEL`, and `ROUTE=n` for a test drive) costs a
## frame as it plays at its own pace: every `STEP` s (10) for `SECS` (60) the view's draw calls,
## triangles and objects and the shadow pass's (Viewport.get_render_info: the same on any
## machine), the frames' mean and slowest over that step (this machine's), and at `KINDS`
## seconds (default 20,40) what is in view by kind (perf_dive's). Then the means -- the numbers
## to set before and after a change to what a watched level draws.
##   LEVEL=10 tests/run.sh watch_cost 10            (a walk)
##   ROUTE=8 tests/run.sh watch_cost 8              (test drive 8)

func _initialize() -> void:
	_watch()

func _rinfo(vp: Viewport, what: int, kind: int) -> int:
	return vp.get_render_info(what, kind)

func _watch() -> void:
	await create_timer(0.3).timeout
	var cfg := {"level": int(OS.get_environment("LEVEL"))}
	if OS.get_environment("ROUTE") != "":
		cfg["route"] = int(OS.get_environment("ROUTE"))
	root.get_node("Flow").start_game("streets", cfg)
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 60.0
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 10.0
	var kinds := (OS.get_environment("KINDS") if OS.get_environment("KINDS") != "" else "20,40").split_floats(",")
	print("watching level %d (%s), quality %d, for %.0f s" % [cfg["level"], g._place.get("name", "?"), g._quality, secs])
	var vp: Viewport = g.view
	var t0 := Time.get_ticks_msec()
	var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var n := 0
	var next_kind := 0
	var el := 0.0
	while el < secs:
		var frames: Array = []
		var s0 := Time.get_ticks_msec()
		while (Time.get_ticks_msec() - s0) / 1000.0 < step:
			var f0 := Time.get_ticks_usec()
			await RenderingServer.frame_post_draw
			frames.append((Time.get_ticks_usec() - f0) / 1000.0)
		el = (Time.get_ticks_msec() - t0) / 1000.0
		var dr := _rinfo(vp, Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var tr := _rinfo(vp, Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		var ob := _rinfo(vp, Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)
		var sd := _rinfo(vp, Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var st := _rinfo(vp, Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		frames.sort()
		var mean := 0.0
		for f: float in frames:
			mean += f
		mean /= maxf(frames.size(), 1)
		var slow: float = frames[int(frames.size() * 0.95)] if frames.size() > 0 else 0.0
		print("%5.0f s: draws %d, triangles %dk, objects %d | shadow draws %d, %dk | frame %.1f ms mean, %.1f slowest 5%%"
			% [el, dr, tr / 1000, ob, sd, st / 1000, mean, slow])
		for i: int in [0, 1, 2, 3, 4, 5]:
			sums[i] += [dr, tr, ob, sd, st, mean][i]
		n += 1
		if next_kind < kinds.size() and el >= kinds[next_kind]:
			_kinds("%.0f s" % el)
			next_kind += 1
	print("WATCH COST mean: draws %d, triangles %dk, objects %d | shadow draws %d, %dk | frame %.1f ms"
		% [sums[0] / n, sums[1] / n / 1000, sums[2] / n, sums[3] / n, sums[4] / n / 1000, sums[5] / n])
	quit()
