extends SceneTree
## One drive of the route set (tests/routes.json, picked by pick_routes.py): ROUTE=n. The car
## set down at its "from" address, "go to" its "to", autodrive there (TRIP_SECS, default 600).
## Prints one line "ROUTE RESULT {...}" (arrived, seconds, metres, hits, standstills of 5 s+
## and what held them, red lights run, rescues, seconds off the asphalt) for
## route_report.py, and saves the drive logs (user://drive_logs/route-<n>-*.json, every two
## minutes and at the end) to draw it. Run headless and fast (run_routes.sh does):
##   ROUTE=3 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/route_set.gd
var g: Node

func _initialize() -> void:
	_run()

func _save_log(n: int, tag: String) -> String:
	var f: String = g._log.save(g)
	var named := f.get_base_dir() + "/route-%d-%s.json" % [n, tag]
	DirAccess.rename_absolute(f, named)
	return named

func _run() -> void:
	var n := int(OS.get_environment("ROUTE")) if OS.get_environment("ROUTE") != "" else 1
	var f := FileAccess.open("res://game/streets/tests/routes.json", FileAccess.READ)
	var all: Dictionary = JSON.parse_string(f.get_as_text())
	var route: Dictionary = {}
	for r: Dictionary in all["routes"]:
		if int(r["id"]) == n:
			route = r
	if route.is_empty():
		print("no route %d" % n)
		quit(1)
		return
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(route["level"])})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var from := Vector2(float(route["from_at"][0]), float(route["from_at"][1]))
	var to := Vector2(float(route["to_at"][0]), float(route["to_at"][1]))
	g._land_on_road(from, 60.0, Vector2.ZERO)
	await physics_frame
	g._set_dest(to, String(route["to"]))
	g._set_auto(true)
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var odo0: float = g._odo
	var still := 0.0
	var held := ""
	var stills: Array = []
	var hits: Array = []
	var last_hit: String = g._last_hit
	var last_v := 0.0
	var reds0: int = g._reds
	var events0: int = g._log.events.size()
	var off := 0.0
	var arrived := false
	var next_log := 120.0
	var limit := float(OS.get_environment("TRIP_SECS")) if OS.get_environment("TRIP_SECS") != "" else 600.0
	while t < limit:
		await physics_frame
		dt = Engine.time_scale / Engine.physics_ticks_per_second
		t += dt
		if not g._dest_on:
			arrived = true
			break
		if absf(g._v) < 0.3:
			if still == 0.0:
				held = g._log._why(g)
			still += dt
		else:
			if still >= 5.0:
				stills.append([snappedf(still, 0.1), held, [int(g._pos.x), int(g._pos.y)], g._on_name])
			still = 0.0
		var h: String = g._last_hit
		if h != last_hit and h != "" and g._crash_cool > 0.35 and absf(last_v) > 1.0:
			hits.append([h, int(absf(last_v) * 3.6), [int(g._pos.x), int(g._pos.y)], g._on_name])
		last_hit = h
		last_v = g._v
		var on: Dictionary = g._nearest_seg(g._pos, 30.0, true, false)
		if on.is_empty() or float(on["edge"]) > 1.0:
			off += dt
		if t >= next_log:
			next_log += 120.0
			_save_log(n, "%03d" % int(t))
		if not g._auto:
			break
	var rescues: Array = []
	for ev: Array in g._log.events.slice(events0):
		if String(ev[1]) in ["rescue", "unstuck"]:
			rescues.append([String(ev[1]), int(ev[0])])
	var longest := 0.0
	for s: Array in stills:
		longest = maxf(longest, float(s[0]))
	var res := {"id": n, "city": route["city"], "from": route["from"], "to": route["to"],
		"arrived": arrived, "secs": int(t), "metres": int(g._odo - odo0),
		"left_m": int(g._pos.distance_to(to)), "hits": hits, "stills": stills,
		"longest_wait": snappedf(longest, 0.1), "reds": g._reds - reds0, "rescues": rescues,
		"off_road_s": snappedf(off, 0.1)}
	_save_log(n, "end")
	print("ROUTE RESULT " + JSON.stringify(res))
	quit(0)
