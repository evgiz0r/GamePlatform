extends SceneTree
## Traffic at junctions over 90 s of autodrive: crossing collisions (two cars overlapping,
## pointing different ways), cars stalled over 10 s, cars that crept through.
var g: Node
func _initialize() -> void:
	_run()
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_auto(true)
	var T = g._traffic
	var stall := {}
	var stalls := 0
	var crossing_hits := 0
	var follow_close := 0
	var seen := {}
	var crept := 0
	var moving_sum := 0.0
	var samples := 0
	for f in range(60 * 50):
		await physics_frame
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive:
				continue
			samples += 1
			if c.v > 0.5:
				moving_sum += 1.0
			if c.jwait > 6.0 and c.jwait < 6.0 + 1.0 / 59.0:
				crept += 1
			if c.v < 0.3:
				stall[i] = stall.get(i, 0.0) + 1.0 / 60.0
				if is_equal_approx(stall[i], 10.0) or (stall[i] > 10.0 and stall[i] < 10.0 + 1.0 / 59.0):
					stalls += 1
					print("stall: %s light %.0f blocker %d wait %.0f holding %s" % [c.kind, T._light_ahead(c), c.blocker, c.wait, c.holding])
			else:
				stall[i] = 0.0
			for k in range(i + 1, T.cars.size()):
				var o = T.cars[k]
				if not o.alive:
					continue
				var d: float = c.pos.distance_to(o.pos)
				if d < 2.6:
					var key := "%d-%d" % [i, k]
					if seen.has(key) and f - int(seen[key]) < 180:
						continue
					seen[key] = f
					if absf(angle_difference(c.yaw, o.yaw)) > 0.6 and absf(angle_difference(c.yaw, o.yaw)) < 2.6:
						crossing_hits += 1
					elif absf(angle_difference(c.yaw, o.yaw)) <= 0.6:
						follow_close += 1
						print("close: %s/%s d %.1f split %s/%s lanes %d/%d shift %.1f/%.1f" % [c.kind, o.kind, d, c.split, o.split, c.lane_i, o.lane_i, c.shift, o.shift])
	print("50 s: crossing collisions %d, same-way too close %d, stalls over 10 s %d, crept through %d, moving %d%% of the time" % [crossing_hits, follow_close, stalls, crept, int(100.0 * moving_sum / maxf(samples, 1))])
	quit(0)
