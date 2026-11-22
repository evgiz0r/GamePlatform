extends SceneTree
## A scenario level played through (scenario.gd): LEVEL picks it (17-20 the towns' tours, 21-22
## the getaways). Prints the script's beats, then as it runs every caption, the stops reached,
## and how it ended; shots ($OUT/scen_<n>.png) at each stop's look and every 8 s of a chase.
##   LEVEL=18 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/scenario.gd
## SECS (default 900) the most it runs. PASS: a tour reached most of its stops (all but one)
## and ended; a getaway ended lost, caught or gave up (a chaser ran) -- and nobody was hit.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 18
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	var probe = root.get_node("Probe")
	probe.enabled = true
	var e0: int = probe._events.size()
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var sc = g._scenario
	if sc == null:
		print("SCENARIO: FAIL (level %d has none)" % level)
		quit(0)
		return
	print("SCENARIO %s, %d beats:" % [sc.kind, sc.beats.size()])
	for b: Array in sc.beats:
		print("   %s %s" % [b[0], str(b.slice(1)).left(110)])
	var out := OS.get_environment("OUT")
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 900.0
	var t := 0.0
	var seen := 0
	var last_i := -1
	var shot := 0
	var shot_t := 0.0
	while t < secs and sc.on:
		await process_frame
		t += get_process_time_step()
		while seen < sc.shown.size():
			print("  [%5.1f s] %s" % [t, sc.shown[seen]])
			seen += 1
		var b: Array = sc.beats[clampi(sc.i, 0, sc.beats.size() - 1)]
		if out != "" and sc.i != last_i and String(b[0]) == "look":
			await create_timer(2.5).timeout
			root.get_viewport().get_texture().get_image().save_png(out + "/scen_%d.png" % shot)
			shot += 1
		if out != "" and String(b[0]) == "chase" and sc._back_cam != null and t - shot_t > 2.5:   # (in the look-back cut)
			shot_t = t
			root.get_viewport().get_texture().get_image().save_png(out + "/scen_%d.png" % shot)
			shot += 1
		last_i = sc.i
	while seen < sc.shown.size():
		print("  [%5.1f s] %s" % [t, sc.shown[seen]])
		seen += 1
	var people := 0
	for k in range(e0, probe._events.size()):
		var ev: Dictionary = probe._events[k]
		if String(ev["kind"]) == "crash" and String((ev["data"] as Dictionary).get("hit", "")) == "person":
			people += 1
	var stops := 0
	for b: Array in sc.beats:
		stops += 1 if String(b[0]) == "look" else 0
	var ok := people == 0
	if sc.kind == "tour":
		ok = ok and sc.reached >= stops - 1 and not sc.on
	else:
		ok = ok and sc.result in ["lost", "caught", "gave up"]
	print("SCENARIO %s ended: %s, %d of %d stops reached, %d people hit, %.0f s" % [sc.kind, sc.result, sc.reached, stops, people, t])
	print("SCENARIO: %s" % ("PASS" if ok else "FAIL"))
	quit(0)

func get_process_time_step() -> float:
	return root.get_process_delta_time()
