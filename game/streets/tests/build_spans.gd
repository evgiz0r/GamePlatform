extends SceneTree
## Where the background build holds a frame: the city's rest is built while you drive, a few
## ms a frame (BUILD_US), every builder handing the frame back when `_over()` says so. A
## stretch with no check in it runs past that budget -- on a phone (Adreno 740, Chrome) single
## stretches of 1-1.5 s, each a freeze of 2-3 s with the GPU work after it. This drives a
## level with the build in the background (as a player has it) and prints the stretches that
## ran more than 20 ms past the budget, longest first, with the call sites that paused after
## them. Natively a phone is ~3-4x slower: 300 ms here is a second there.
##
##   STREETS_SPANS=1 STREETS_BUILD_ALL=0 LEVEL=3 SECS=90 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/build_spans.gd
##
## 22 Nov 2026, before the fix: see PERF.md ("A phone").
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	g._set_auto(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	var t := 0.0
	var worst_frame := 0.0
	var w := Time.get_ticks_usec()
	while t < secs:
		await process_frame
		var now := Time.get_ticks_usec()
		worst_frame = maxf(worst_frame, (now - w) / 1000.0)
		w = now
		t += 1.0 / 60.0
	var sp: Array = g._spans.duplicate()
	sp.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var total := 0.0
	for s: Array in sp:
		total += float(s[0])
	print("BUILD SPANS %s: %d stretches over budget by 20+ ms in %.0f s, %.0f ms past it in all; worst frame %.0f ms" % [
		g._city_name, sp.size(), secs, total, worst_frame])
	# by call site: how often and how long
	var by := {}
	for s: Array in sp:
		var k: String = s[1]
		if not by.has(k):
			by[k] = [0, 0.0, 0.0]
		by[k][0] += 1
		by[k][1] += float(s[0])
		by[k][2] = maxf(by[k][2], float(s[0]))
	var keys := by.keys()
	keys.sort_custom(func(a, b) -> bool: return by[a][2] > by[b][2])
	for k in keys.slice(0, 20):
		print("  worst %6.0f ms  n %3d  sum %7.0f ms   %s" % [by[k][2], by[k][0], by[k][1], k])
	quit(0)
