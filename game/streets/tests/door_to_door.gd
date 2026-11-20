extends SceneTree
## A trip as a player makes one: from a house on a side street to a house on another side
## street a real drive away, by "go to" and autodrive. The two addresses are picked from the
## city's own house numbers on residential streets, at least FROM_START metres from the
## start corner and ROUTE_MIN apart (SEED picks another pair). Prints the route, the trip
## (arrived or not, time, metres, standstills and what held them, hits, red lights,
## rescues), saves the drive log of every two minutes (user://drive_logs/trip-*.json) and
## screenshots at the start, every 30 s and at the end.
var g: Node
const FROM_START := 800.0
const ROUTE_MIN := 900.0

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _save_log(tag: String) -> String:
	var f: String = g._log.save(g)
	var named := f.get_base_dir() + "/trip-%s-%s.json" % [g._city_id, tag]
	DirAccess.rename_absolute(f, named)
	return named

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var start: Vector2 = g._pos
	# houses on residential streets, away from the start corner
	var homes: Array = []   # [label, where]
	for street: String in g._addr:
		for a: Array in g._addr[street]:
			var at: Vector2 = a[1]
			if at.distance_to(start) < FROM_START:
				continue
			var hit: Dictionary = g._nearest_seg(at, 40.0, true, true)
			if hit.is_empty() or not ((g._roads[hit["road"]] as Dictionary)["k"] in ["residential", "living_street"]):
				continue
			homes.append(["%s %s" % [street, a[0]], at])
	homes.sort_custom(func(x, y): return String(x[0]) < String(y[0]))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3
	var from: Array = []
	var to: Array = []
	for _try in range(500):
		var a: Array = homes[rng.randi() % homes.size()]
		var b: Array = homes[rng.randi() % homes.size()]
		if (a[1] as Vector2).distance_to(b[1]) >= ROUTE_MIN and (a[1] as Vector2).distance_to(b[1]) < ROUTE_MIN * 1.8:
			from = a
			to = b
			break
	print("from %s (%s), to %s (%s): %.0f m apart, as the crow flies" % [from[0], Vector2i(from[1]), to[0], Vector2i(to[1]), (from[1] as Vector2).distance_to(to[1])])
	g._land_on_road(from[1], 60.0, Vector2.ZERO)
	await physics_frame
	g._set_dest(to[1], to[0])
	g._set_auto(true)
	await create_timer(0.5).timeout
	print("route planned: %d points, %.0f m" % [g._ap_pts.size(), g._ap_len()])
	await _snap("trip_start")
	var t := 0.0
	var dt := 1.0 / 60.0
	var odo0: float = g._odo
	var still := 0.0
	var held := ""
	var stills: Array = []
	var hits: Array = []
	var last_hit := ""
	var last_v := 0.0
	var reds0: int = g._reds
	var events0: int = g._log.events.size()
	var arrived := false
	var next_shot := 30.0
	var next_log := 120.0
	var limit := float(OS.get_environment("TRIP_SECS")) if OS.get_environment("TRIP_SECS") != "" else 420.0
	while t < limit:
		await physics_frame
		t += dt
		if not g._dest_on:
			arrived = true
			break
		if absf(g._v) < 0.3:
			if still == 0.0:
				held = g._log._why(g)   # (what held it as it stopped: a zebra, a car, turning round...)
			still += dt
		else:
			if still >= 3.0:
				stills.append("%.0f s at %s, held by %s" % [still, Vector2i(g._pos), held])
			still = 0.0
		var h: String = g._last_hit
		if h != last_hit and h != "" and g._crash_cool > 0.35 and absf(last_v) > 1.0:
			hits.append("%s at %.0f km/h, %s" % [h, absf(last_v) * 3.6, Vector2i(g._pos)])
		last_hit = h
		last_v = g._v
		if t >= next_shot:
			next_shot += 30.0
			await _snap("trip_%03d" % int(t))
		if t >= next_log:
			next_log += 120.0
			print("  log: ", _save_log("%03d" % int(t)))
		if not g._auto:   # (autodrive gave up or arrived without clearing the destination)
			break
	await _snap("trip_end")
	var rescues: Array = []
	for ev: Array in g._log.events.slice(events0):
		if String(ev[1]) in ["rescue", "unstuck", "red light", "hit"]:
			rescues.append("%s %s" % [ev[1], ev[2]])
	print("TRIP %s in %.0f s, %.0f m driven (left %.0f m from the door)" % [
		"ARRIVED" if arrived else "NOT arrived", t, g._odo - odo0, g._pos.distance_to(to[1])])
	print("  standstills of 3 s or more: %d" % stills.size())
	for x in stills:
		print("    ", x)
	print("  hits: %d" % hits.size())
	for x in hits:
		print("    ", x)
	print("  red lights run: %d" % (g._reds - reds0))
	print("  events: %s" % str(rescues))
	print("  log: ", _save_log("end"))
	quit(0)
