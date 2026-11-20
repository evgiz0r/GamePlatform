extends SceneTree
## The first seconds of a run as a player sees them: the city loaded as the game loads it
## (start squares first, the rest while driving), autodrive switched on at the start, a shot
## every STEP seconds (default 1.5) for SECS (default 12) -- drive_*.png, the car's place
## printed with each -- then every railing panel and wall within 40 m of the way driven
## (what stood across Tel Aviv's Kaplan in a user's screenshot: "weird borders").
##   STREETS_BUILD_ALL=0 tests/run.sh start_drive 7
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	g._set_auto(true)
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 1.5
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 12.0
	var path: Array = []
	var t := 0.0
	var i := 0
	while t < secs:
		await create_timer(step).timeout
		t += step
		path.append(g._pos)
		print("t %.1f s: at %s heading %s, %.0f km/h, on '%s'" % [t, (g._pos as Vector2).round(), g._fwd().snapped(Vector2(0.01, 0.01)), g._v * 3.6, g._on_name])
		await _snap("drive_%02d" % i)
		i += 1
	var near := func(p: Vector2) -> float:
		var best := INF
		for q: Vector2 in path:
			best = minf(best, q.distance_to(p))
		return best
	# the walls (fences, railings) and the posts near the way driven, with whether each is on
	# the asphalt by the game's own reckoning
	var walls := 0
	var ws: PackedVector2Array = g._walls   # (two points a wall)
	for wi in range(0, ws.size() - 1, 2):
		var a: Vector2 = ws[wi]
		var b: Vector2 = ws[wi + 1]
		var m := (a + b) * 0.5
		if near.call(m) < 40.0:
			walls += 1
			if walls <= 25:
				print("  wall %s - %s, %.1f m, off the road: %s" % [a.round(), b.round(), a.distance_to(b), g._off_road(m, 0.0)])
	print("walls within 40 m of the way: %d" % walls)
	quit(0)
