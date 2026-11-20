extends SceneTree
## Zooming out from where you are: the view rises off the car over the city and the city holds
## still; dragged about, turned, higher; back down to the car and the city goes on. Then the
## pause button alone, the same from the driver's seat (lands back in it) and on foot.
## Prints what held still and what moved, the camera's height and the frame time at each step;
## screenshots zoom_*.png in $OUT. Good: "held" lines all 0.00 m, "landed" with the city
## moving again, the camera back at chase height, and the seat restored; one notch of zooming
## in at the lowest does not come down, a second of it does; draw ranges lifted while up and
## all put back after; the lowest view never inside a building as it is dragged over them.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the city's moving things, for checking they held still
func _state() -> Dictionary:
	var cars: Array = []
	for c in g._traffic.cars:
		if c.alive:
			cars.append(c.pos)
	var people: Array = []
	for w: Dictionary in g._walkers:
		people.append((w["actor"] as Node3D).position)
	return {"car": g._pos, "cars": cars, "people": people}

func _moved(a: Dictionary, b: Dictionary) -> Array:
	var cm := 0.0
	for i in range(mini(a["cars"].size(), b["cars"].size())):
		cm = maxf(cm, (a["cars"][i] as Vector2).distance_to(b["cars"][i]))
	var pm := 0.0
	for i in range(mini(a["people"].size(), b["people"].size())):
		pm = maxf(pm, (a["people"][i] as Vector3).distance_to(b["people"][i]))
	return [(a["car"] as Vector2).distance_to(b["car"]), cm, pm]

func _say(what: String) -> void:
	var c: Camera3D = g.cam
	print("%-22s zoom %.2f  paused %s  cam %.0f m over the car, %.0f m from it  near %.2f  fog %.5f  fps %d  draws %d  ranges lifted %d" % [
		what, g._zoom_v, g._paused, c.global_position.y - g._view_y,
		Vector2(c.global_position.x, c.global_position.z).distance_to(g._view_pos), c.near,
		g.env.fog_density, Engine.get_frames_per_second(),
		g.view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		g._zoom_ranges.size()])

## the camera inside a building's walls?
func _in_building() -> bool:
	var e: Vector3 = g.cam.global_position
	var p := Vector2(e.x, e.z)
	for i: int in g._near(g._bld_hash, p, 0.1, g.BLD_CELL):
		if (g._bld_box[i] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, g._blds[i]) \
				and e.y < g._h(p) + g._bld_top[i] + 0.5:
			return true
	return false

func _wait_zoom() -> void:
	var t := 0
	while absf(g._zoom_v - g._zoom) > 0.0 and t < 400:
		await process_frame
		t += 1
	await create_timer(0.4).timeout

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	g._set_auto(true)
	await create_timer(4.0).timeout
	await _snap("zoom_0_start")
	_say("driving")
	var chase_y: float = g.cam.global_position.y - g._view_y

	# up: the city holds
	var before := _state()
	g._zoom_set(g.ZOOM_UP)
	await _wait_zoom()
	await create_timer(1.0).timeout
	var m := _moved(before, _state())
	print("held while up: car %.2f m, traffic %.2f m, people %.2f m" % m)
	_say("up")
	await _snap("zoom_1_up")
	g._zoom_set(1.0)
	await _wait_zoom()
	_say("top")
	await _snap("zoom_2_top")

	# dragged about and turned
	g._zoom_set(g.ZOOM_UP)
	await _wait_zoom()
	for i in range(10):
		g._zoom_pan(Vector2(-25, 18))
	await create_timer(0.5).timeout
	print("dragged: centre %.0f m from the car" % g._zoom_off.length())
	await _snap("zoom_3_dragged")
	g._zoom_turn(PI / 2.0)
	await create_timer(1.0).timeout
	await _snap("zoom_4_turned")
	m = _moved(before, _state())
	print("held after looking round: car %.2f m, traffic %.2f m, people %.2f m" % m)

	# the lowest view, dragged over the blocks: never inside one
	g._zoom_set(g.ZOOM_MIN)
	await _wait_zoom()
	var inside := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(16):
		g._zoom_off = Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250))
		g._zoom_keep_in()
		for f in range(4):
			await process_frame
		if _in_building():
			inside += 1
	print("lowest view dragged to 16 spots: inside a building at %d (want 0)" % inside)
	await _snap("zoom_4b_lowest")
	g._zoom_off = Vector2.ZERO
	await create_timer(0.5).timeout

	# at the lowest: a notch more does not come down; a second of zooming in does
	g._zoom_by(-g.ZOOM_STEP)
	await create_timer(0.3).timeout
	print("one notch in at the lowest: zoom %.2f (want %.2f, still up)" % [g._zoom, g.ZOOM_MIN])
	await create_timer(1.0).timeout
	for i in range(14):   # (real milliseconds apart, as a wheel turned for 1.4 s)
		g._zoom_by(-g.ZOOM_STEP)
		OS.delay_msec(100)
	print("a second and more of zooming in: zoom %.2f (want 0, coming down)" % g._zoom)

	# back down: the city goes on
	g._zoom_set(0.0)
	await _wait_zoom()
	print("ranges put back: %s (lifted %d)" % [g._zoom_ranges_n == -1, g._zoom_ranges.size()])
	_say("landed")
	print("landed: centre %.1f m from the car, camera %.1f m up (chase was %.1f)" % [
		g._zoom_off.length(), g.cam.global_position.y - g._view_y, chase_y])
	before = _state()
	await create_timer(2.0).timeout
	m = _moved(before, _state())
	print("moving again: car %.2f m, traffic %.2f m, people %.2f m" % m)
	await _snap("zoom_5_landed")

	# the pause button alone
	g._toggle_pause()
	before = _state()
	await create_timer(1.5).timeout
	m = _moved(before, _state())
	print("held by pause: car %.2f m, traffic %.2f m, people %.2f m" % m)
	await _snap("zoom_6_paused")
	g._toggle_pause()
	await create_timer(1.0).timeout

	# from the driver's seat: up via the chase cam, back into the seat
	g._set_cockpit(true)
	await create_timer(0.5).timeout
	g._zoom_set(g.ZOOM_UP)
	await _wait_zoom()
	print("seat, up: cockpit %s (want false)" % g._cockpit)
	g._zoom_set(0.0)
	await _wait_zoom()
	print("seat, landed: cockpit %s (want true), paused %s (want false)" % [g._cockpit, g._paused])
	g._set_cockpit(false)

	# on foot: you and the car marked
	g._set_auto(false)
	await create_timer(2.0).timeout
	g._toggle_walk()
	await create_timer(1.5).timeout
	g._zoom_set(0.55)
	await _wait_zoom()
	_say("on foot, up")
	await _snap("zoom_7_on_foot")
	g._zoom_set(0.0)
	await _wait_zoom()
	_say("on foot, landed")
	quit()
