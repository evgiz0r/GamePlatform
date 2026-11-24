extends SceneTree
## A railing the car goes through falls (_break_rail; Evgeni, 24 Nov 2026: "can we just
## crash/destroy such objects", after his ambulance stood a minute against the railings of
## Kaplan's median). Finds the railing panel (a wall with _wall_rail) nearest AT (default the
## Tel Aviv ambulance run's start), puts the car 7 m off it facing it square on, and drives it
## through at KMH (default 18) by hand -- then, racer on, at a crawl (RACER_SMASH_V's case,
## 3 km/h: before, it stood against the railing). Prints the panels down, how far the car got
## past the line, and saves shots (before, after) to OUT when it is set.
##   OUT=/tmp/rb game/streets/tests/run.sh rail_break 25
## Good: by hand and racer through, panels down 1-3 each, the car 4 m past the line; plain
## autodrive at a crawl stopped at it (panels down 0).
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String, at: Vector2, from: Vector2) -> void:
	if OS.get_environment("OUT") == "":
		return
	var cam: Camera3D = g.cam
	for k in range(10):
		# (set just before the frame is drawn: the game's own camera follows the car each frame)
		await RenderingServer.frame_pre_draw
		cam.global_position = Vector3(from.x, float(g._h(from)) + 4.0, from.y)
		cam.look_at(Vector3(at.x, float(g._h(at)) + 0.5, at.y))
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _vec(env: String, def: Vector2) -> Vector2:
	var s := OS.get_environment(env)
	if s == "":
		return def
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 25})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_auto(false)
	var at := _vec("AT", Vector2(-555.0, 156.0))
	var kmh := float(OS.get_environment("KMH")) if OS.get_environment("KMH") != "" else 18.0
	var used := {}
	var done := {}
	# (each kind of run tried at up to four panels: the car parks along the railings fill at
	# random, and a parked car in the way pushed the car back before it reached the railing)
	for run: int in [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2]:
		if done.has(run):
			continue
		var best := -1
		var bd := INF
		for i in range(g._wall_rail.size()):
			if g._wall_rail[i] != 1 or g._wall_give[i] != 1 or used.has(i):
				continue
			var m: Vector2 = (g._walls[i * 2] + g._walls[i * 2 + 1]) * 0.5
			if m.distance_to(at) >= bd:
				continue
			# (the way up to it and past it clear of all but what gives: a parked car in it
			# pushed the car back and the run said nothing about the railing)
			var nn: Vector2 = (g._walls[i * 2 + 1] - g._walls[i * 2]).normalized().orthogonal()
			var clear := true
			g._smash = true
			for d: float in [7.0, 5.0, 3.0, -3.0, -4.5]:
				if g._push_out(m + nn * d, 1.0, true, true, NAN) != Vector2.ZERO:
					clear = false
			g._smash = false
			# ...and solid where the car meets it (a railing standing on a wall or a deck is
			# solid only at its own height: the car went under or past it, nothing to test)
			if g._push_out(m, 0.3, true, false, NAN) == Vector2.ZERO:
				clear = false
			if clear:
				bd = m.distance_to(at)
				best = i
		if best < 0:
			print("no railing near (%.0f, %.0f)" % [at.x, at.y])
			quit(1)
			return
		used[best] = true
		var a: Vector2 = g._walls[best * 2]
		var b: Vector2 = g._walls[best * 2 + 1]
		var mid := (a + b) * 0.5
		var n := (b - a).normalized().orthogonal()
		var from := mid + n * 7.0
		g._pos = from
		g._yaw = (-n).angle()
		g._v = 0.0
		g._v_lat = 0.0
		g._y = float(g._h(from))
		for k in range(10):
			await physics_frame
		# by hand at KMH; racer at a crawl; plain autodrive at a crawl (still stopped: only racer
		# goes through at any pace). The car moved and _collide called here, the game's own
		# physics tick paused, so autodrive's steering stays out of it
		var racer := run == 1
		var v := (kmh if run == 0 else 3.0) / 3.6
		g._auto = run > 0
		if racer:
			g._set_racer(true)
		await _snap("rail_%d_before" % run, mid, mid + n * 9.0 + (b - a).normalized() * 3.0)
		var down0: int = (g._rails_down as Array).size()
		g.set_physics_process(false)
		var t := 0.0
		while t < 14.0:
			await physics_frame
			var dt := 1.0 / Engine.physics_ticks_per_second
			t += dt
			g._v = v
			g._yaw = (-n).angle()
			g._pos += g._fwd() * v * dt
			g._collide()
			if (g._pos - mid).dot(-n) > 4.0:
				break
		g.set_physics_process(true)
		var past: float = (g._pos - mid).dot(-n)
		var down: int = (g._rails_down as Array).size() - down0
		var slid: float = absf((g._pos - mid).dot((b - a).normalized()))
		if down == 0 and (past < -3.5 or slid > 1.2):
			# (stopped short by something else, or pushed along the railing and round its end)
			print("  (run %d: panel %d not met square on -- %.1f m short, %.1f m along: the next one)" % [run, best, -past, slid])
			g._auto = false
			g._set_racer(false)
			g._v = 0.0
			at = mid + (b - a).normalized() * 30.0
			continue
		done[run] = true
		print("RAIL BREAK run %d (%s, %.0f km/h): panel %d at (%.1f, %.1f), %.1f m long; panels down %d, the car %.1f m past its line after %.1f s" % [
			run, ["by hand", "racer", "autodrive"][run], v * 3.6, best, mid.x, mid.y, a.distance_to(b), (g._rails_down as Array).size() - down0, past, t])
		g._auto = false
		g._set_racer(false)
		g._v = 0.0
		for k in range(60):
			await physics_frame
		await _snap("rail_%d_after" % run, mid, mid + n * 9.0 + (b - a).normalized() * 3.0)
		at = mid + (b - a).normalized() * 30.0
	quit(0)
