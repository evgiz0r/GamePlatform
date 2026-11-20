extends SceneTree
## Autodrive switched on off the road: in yards and between blocks, eight places near the
## start. For each: seconds to get onto a road, buildings hit on the way, lifted back or not.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + lvl
	var start: Vector2 = g._pos
	var spots: Array = []
	for _try in range(4000):
		if spots.size() >= 8:
			break
		var p := start + Vector2(rng.randf_range(-350, 350), rng.randf_range(-350, 350))
		var on: Dictionary = g._nearest_seg(p, 60.0, true, true)
		if on.is_empty() or float(on["edge"]) < 8.0 or float(on["edge"]) > 45.0:
			continue
		if g._push_out(p, 2.2, true, false) != Vector2.ZERO:
			continue
		var blds := 0
		for i: int in g._near(g._bld_hash, p, 22.0, g.BLD_CELL):
			if (g._bld_box[i] as Rect2).grow(22.0).has_point(p):
				blds += 1
		if blds < 4:
			continue
		spots.append(p)
	print("spots: ", spots.size())
	var total_hits := 0
	var made := 0
	var lifts := 0
	var times: Array = []
	for si in range(spots.size()):
		var p: Vector2 = spots[si]
		g._set_auto(false)
		g._pos = p
		g._yaw = rng.randf() * TAU
		g._v = 0.0
		g._v_lat = 0.0
		g._snap_pose()
		await physics_frame
		var t0 := Time.get_ticks_msec()
		g._set_auto(true)
		var t := 0.0
		var hits := 0
		var last_hit := ""
		var lifted := false
		var prev: Vector2 = g._pos
		var on_road_t := -1.0
		var plan_ms := Time.get_ticks_msec() - t0
		while t < 45.0:
			await physics_frame
			t += Engine.time_scale / Engine.physics_ticks_per_second
			var h = g._last_hit
			if h != "" and h != last_hit and g._crash_cool > 0.35 and String(h).begins_with("building"):
				hits += 1
			last_hit = h
			if g._pos.distance_to(prev) > 6.0:
				lifted = true
			prev = g._pos
			var on: Dictionary = g._nearest_seg(g._pos, 30.0, true, true)
			if not on.is_empty() and float(on["edge"]) < -0.8:
				on_road_t = t
				break
		total_hits += hits
		if on_road_t >= 0.0:
			made += 1
			times.append(snappedf(on_road_t, 0.1))
		if lifted:
			lifts += 1
		print("  spot %d (%.0f m off the road): %s, %d building hits%s" % [si, float(g._nearest_seg(p, 60.0, true, true)["edge"]), ("on the road in %.1f s" % on_road_t) if on_road_t >= 0.0 else "NOT on the road in 45 s", hits, ", lifted back" if lifted else ""])
		if si == 0 and OS.get_environment("OUT") != "":
			await _snap("offroad_%d" % lvl)
	print("off-road: %d of %d reached a road, %d lifted, %d building hits in all, times %s" % [made, spots.size(), lifts, total_hits, str(times)])
	quit(0)
