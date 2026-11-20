extends SceneTree
## Trips that start at a dead end -- a house at the closed end of a cul-de-sac, the car
## parked facing the end (the worst way round). For DEAD_ENDS of the city's dead-end side
## streets (public, residential or living street, at least 35 m long): land 8 m from the
## closed end facing it, "go to" a house 400-900 m away, and drive 40 s. Per start: metres
## away from the dead end by then, hits, seconds off the asphalt. Good: every car out of its
## street (40 m+), no hits, ~0 s off the road. The test trip once started from one of these,
## planned on to the closed end and a U-turn there, swung into the fence and crept along the
## footpath beside the road for a minute and a half.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if OS.get_environment("OUT") == "":
		return
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
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var want := int(OS.get_environment("DEAD_ENDS")) if OS.get_environment("DEAD_ENDS") != "" else 8
	# dead ends: the last point of a drivable public side street that meets nothing else
	var ends: Array = []   # [end point, the way in (toward the end)]
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"] or int(r["o"]) != 0 or not (r["k"] in ["residential", "living_street"]):
			continue
		var ids: PackedInt32Array = r["ids"]
		var pts: PackedVector2Array = r["pts"]
		for side: int in [0, pts.size() - 1]:
			if g._node_ways(ids[side]) != 1:
				continue
			var inner := 1 if side == 0 else pts.size() - 2
			var L := 0.0
			for k in range(pts.size() - 1):
				L += pts[k].distance_to(pts[k + 1])
			if L < 35.0 or pts[side].distance_to(pts[inner]) < 10.0 or not g._in_city(pts[side]):
				continue
			ends.append([pts[side], (pts[side] - pts[inner]).normalized()])
	ends.sort_custom(func(a, b): return (a[0] as Vector2).x < (b[0] as Vector2).x)
	var picked: Array = []
	var step := maxi(1, ends.size() / want)
	for i in range(0, ends.size(), step):
		picked.append(ends[i])
		if picked.size() >= want:
			break
	print("dead ends in the city: %d, trying %d" % [ends.size(), picked.size()])
	var homes: Array = []
	for street: String in g._addr:
		for a: Array in g._addr[street]:
			homes.append(a[1])
	var out_ok := 0
	var total_hits := 0
	var total_off := 0.0
	for i in range(picked.size()):
		var e: Vector2 = picked[i][0]
		var into: Vector2 = picked[i][1]
		g._set_auto(false)
		g._clear_dest()
		g._land_on_road(e - into * 8.0, 20.0, into)
		await physics_frame
		var dest := Vector2.INF
		for h: Vector2 in homes:
			var d := h.distance_to(e)
			if d > 400.0 and d < 900.0:
				dest = h
				break
		if dest == Vector2.INF:
			continue
		var start: Vector2 = g._pos
		g._set_dest(dest, "test")
		var hits := 0
		var off := 0.0
		var last_hit: String = g._last_hit
		var t := 0.0
		var dt := 1.0 / 60.0
		var far := 0.0
		while t < 40.0 and g._dest_on:
			await physics_frame
			t += dt
			if g._last_hit != last_hit and g._last_hit != "" and g._crash_cool > 0.35:
				hits += 1
			last_hit = g._last_hit
			var on: Dictionary = g._nearest_seg(g._pos, 30.0, true, true)
			if on.is_empty() or float(on["edge"]) > 1.0:
				off += dt
			far = maxf(far, (g._pos as Vector2).distance_to(e))
			if t > 3.0 and t < 3.0 + dt * 1.5 and i < 3:
				await _snap("dead_end_%d" % i)
		var ok := far >= 40.0
		out_ok += 1 if ok else 0
		total_hits += hits
		total_off += off
		print("  %s dead end at %s: %.0f m out in 40 s, %d hit(s) %s, %.1f s off the road" % [
			"OK  " if ok and hits == 0 else "BAD ", Vector2i(e), far, hits, last_hit if hits > 0 else "", off])
	print("DEAD ENDS: %d of %d out of their street, %d hits, %.1f s off the road in all" % [out_ok, picked.size(), total_hits, total_off])
	quit(0)
