extends SceneTree
## The time-of-day button's three looks -- day, evening (golden hour), night -- over the same
## views: down a long main road towards the evening sun and away from it (the lit fronts),
## a side street from a car, and the city from the zoom-out's height. Shots tod_<view>_<time>.png
## in $OUT, and each view's draws and triangles (night should cost no more than day: its sun
## lights nothing); prints how long switching to the evening took. Both suns' far shadows are drawn
## ahead now, a few ms a frame after the car (_far_ahead), so it waits for them first: drawn at
## the click they held it a second and more, and once the city was built they failed -- and
## the night's light pools, made ahead too (_make_pools(true)).
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var tw := Time.get_ticks_msec()
	while not (g._fs_cache.has("day") and g._fs_cache.has("evening") and g._pools_made and not g._pools_busy) and Time.get_ticks_msec() - tw < 400000:
		await create_timer(0.5).timeout
	print("both suns' far shadows drawn and the night's pools made %.0f s after the car: %s" % [(Time.get_ticks_msec() - tw) / 1000.0, str(g._fs_cache.keys())])
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	var p: Vector2 = g._pos
	var f: Vector2 = g._fwd()
	# a street near the start that runs roughly east-west, among the houses (a residential or
	# a main road, its straightest long piece within 300 m), looked along from a car's height
	var best := 0.0
	var a := p
	var d := Vector2(1, 0)
	for r: Dictionary in g._roads:
		if not r["drive"] or not (String(r["k"]) in ["residential", "tertiary", "secondary"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		for i in range(pts.size() - 1):
			var L := pts[i].distance_to(pts[i + 1])
			var dd := (pts[i + 1] - pts[i]) / maxf(L, 0.01)
			if L > 30.0 and L * absf(dd.x) > best and pts[i].distance_to(p) < 300.0:
				best = L * absf(dd.x)
				a = pts[i] + dd * L * 0.5
				d = dd if dd.x < 0.0 else -dd   # (looking west: into the evening sun)
	print("a street %d m east-west" % int(best))
	var views := {
		"west": [Vector3(a.x, g._h(a) + 2.4, a.y), Vector3(a.x + d.x * 120, g._h(a + d * 120) + 5.0, a.y + d.y * 120)],
		"east": [Vector3(a.x, g._h(a) + 2.4, a.y), Vector3(a.x - d.x * 120, g._h(a - d * 120) + 5.0, a.y - d.y * 120)],
		"street": [Vector3(p.x - f.x * 6, g._h(p) + 3.2, p.y - f.y * 6), Vector3(p.x + f.x * 80, g._h(p + f * 80), p.y + f.y * 80)],
		"zoom": [Vector3(p.x - f.x * 150, g._h(p) + 165, p.y - f.y * 150), Vector3(p.x, g._h(p), p.y)],
	}
	for time: String in ["day", "evening", "night"]:
		if time == "evening":
			var t0 := Time.get_ticks_msec()
			await g._set_evening(true)
			print("to the evening in %d ms" % (Time.get_ticks_msec() - t0))
		elif time == "night":
			await g._next_time()
		for v: String in views:
			g.look_from(views[v][0], views[v][1])
			g._sky_follow()
			await _snap("tod_%s_%s" % [v, time])
			print("%s %s: %d draws, %d k triangles" % [v, time,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	quit(0)
