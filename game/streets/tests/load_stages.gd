extends SceneTree
## Where the build time goes: the file's parse and every stage of building the city
## (_stage_ms), slowest first, with how much each is of the whole; then a look along a main
## street with a median (the latest addition) if the city has one. Run it with
## STREETS_BUILD_ALL=0 for what a player waits for (the squares round the start only).
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)
func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	var t0 := Time.get_ticks_msec()
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:
		await create_timer(0.1).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var wall := Time.get_ticks_msec() - t0
	var st: Dictionary = g._stage_ms
	var keys := st.keys()
	keys.sort_custom(func(a, b): return int(st[a]) > int(st[b]))
	var total := 0
	for k in keys:
		if not String(k).contains(":"):   # ("kerbs: corners" is a part of "kerbs")
			total += int(st[k])
	print("%s: ready after %.1f s; stages add up to %.1f s" % [g._city_name, wall / 1000.0, total / 1000.0])
	for k in keys:
		if int(st[k]) >= 50:
			print("  %6d ms  %4.1f%%  %s" % [int(st[k]), 100.0 * int(st[k]) / maxf(total, 1), k])
	print("median: %s m" % str(g._dressing.get("median_m", 0)))
	if OS.get_environment("OUT") != "":
		for r: Dictionary in g._roads:
			if r.has("mid"):
				var pts: PackedVector2Array = r["pts"]
				if pts.size() < 2 or pts[0].distance_to(pts[pts.size() - 1]) < 80.0:
					continue
				var d := (pts[1] - pts[0]).normalized()
				var eye := pts[0] + d * 10.0 + Vector2(-d.y, d.x) * float(g._lane_off(r))
				g.set_physics_process(false)
				process_frame.disconnect(g._frame)
				g.look_from(Vector3(eye.x, g._h(eye) + 1.8, eye.y), Vector3(eye.x + d.x * 30.0, g._h(eye) + 0.5, eye.y + d.y * 30.0))
				await _snap("median_%d" % lvl)
				break
	quit(0)
