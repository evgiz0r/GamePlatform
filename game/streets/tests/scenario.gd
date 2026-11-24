extends SceneTree
## A scenario level played through (scenario.gd): LEVEL picks it (17-20 the towns' tours, 21-22
## the getaways). Prints the script's beats, then as it runs every caption, the stops reached,
## and how it ended; shots ($OUT/scen_<n>.png) at each stop's look and every 8 s of a chase.
##   LEVEL=18 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/scenario.gd
## SECS (default 900) the most it runs. PASS: a tour reached most of its stops (all but one)
## and ended; a getaway ended lost, caught or gave up (a chaser ran) -- and nobody was hit.
var g: Node
var off_fast := 0.0

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
		if out != "" and (String(b[0]) in ["chase", "drive_for", "dragons"]) and t - shot_t > (3.0 if String(b[0]) == "dragons" else 6.0):   # (a shot every 6 s while it drives)
			shot_t = t
			root.get_viewport().get_texture().get_image().save_png(out + "/scen_%d.png" % shot)
			shot += 1
		last_i = sc.i
		# off the road at speed (the ambulance drove a Tel Aviv pavement at 67 km/h, 24 Nov):
		# the car's middle beyond every drivable road's edge, over 8 m/s
		if absf(g._v) > 8.0:
			var hit: Dictionary = g._nearest_seg(g._pos, 15.0, true, false, g._y)
			if hit.is_empty() or float(hit["edge"]) > 0.4:
				off_fast += get_process_time_step()
		if out != "" and sc.i == 0 and t > 1.5 and not FileAccess.file_exists(out + "/title.png"):
			root.get_viewport().get_texture().get_image().save_png(out + "/title.png")   # (the title card)
		if sc.kind == "getaway" and sc._chaser != null and int(t / 5.0) != int((t - get_process_time_step()) / 5.0):
			print("   [%5.1f s] gap %.0f m, you %.1f m/s, chaser %.1f m/s" % [t, sc._gap, g._v, sc._vc])
		if OS.get_environment("VERBOSE") != "" and int(t * 60.0) % 600 == 0:
			print("   t %.0f v %.1f why %s auto %s dest %s %.0f m style %s lead %.1f" % [t, g._v, g._ap_why, g._auto, g._dest_on,
				(g._pos as Vector2).distance_to(g._dest_stop), g._ap_style, g._ap_lead])
	while seen < sc.shown.size():
		print("  [%5.1f s] %s" % [t, sc.shown[seen]])
		seen += 1
	if out != "" and not sc.card_lines.is_empty():
		await create_timer(1.2).timeout
		root.get_viewport().get_texture().get_image().save_png(out + "/end_card.png")
	var people := 0
	for k in range(e0, probe._events.size()):
		var ev: Dictionary = probe._events[k]
		if String(ev["kind"]) == "crash" and String((ev["data"] as Dictionary).get("hit", "")) == "person":
			people += 1
	var stops := 0
	for b: Array in sc.beats:
		stops += 1 if String(b[0]) == "look" else 0
	var ok := people == 0
	match String(sc.kind):
		"tour", "night_tour":
			ok = ok and sc.reached >= stops - 1 and not sc.on
		"getaway":
			ok = ok and sc.result in ["lost", "caught", "gave up", "home"]
		"delivery", "taxi":
			ok = ok and sc.drops_done >= 2 and not sc.on
		"ambulance":
			ok = ok and sc.reached >= 1 and sc.yielded > 0 and not sc.on
		"day":
			ok = ok and not sc.on and sc.shots_seen.size() >= 3
		"dragons":
			ok = ok and not sc.on and sc._dragons != null and int(sc._dragons.events.get("fire", 0)) >= 2 				and int(sc._dragons.events.get("cam_in_building", 0)) == 0
	print("SCENARIO shots: %s; cars that pulled over: %d; time now: %s" % [JSON.stringify(sc.shots_seen), sc.yielded,
		"night" if g._night else ("evening" if g._evening else "day")])
	print("SCENARIO %s ended: %s, %d of %d stops reached, %d people hit, %.0f s" % [sc.kind, sc.result, sc.reached, stops, people, t])
	print("SCENARIO camera frames inside a building: %d" % sc.cam_in_building)
	print("SCENARIO off the road over 8 m/s: %.1f s" % off_fast)
	print("SCENARIO card: %s; stars %d, %.0f s run, close calls %d, tips %d, tour cuts %d" % [" | ".join(sc.card_lines), sc.stars, sc.run_t,
		sc.close_calls, sc.tips, sc.skips])
	ok = ok and not sc.card_lines.is_empty() and off_fast < 2.0   # (no car of a scenario drives the pavement at speed)
	ok = ok and sc.cam_in_building == 0
	if sc._dragons != null:
		print("SCENARIO dragons: %s" % JSON.stringify(sc._dragons.events))
	print("SCENARIO: %s" % ("PASS" if ok else "FAIL"))
	quit(0)

func get_process_time_step() -> float:
	return root.get_process_delta_time()
