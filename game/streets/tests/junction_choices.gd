extends SceneTree
## Junction choices over 100 s of autodrive (nobody picking): how many, and how many came
## within 45 m and 15 s of the one before (one junction asking twice).
var g: Node
func _initialize() -> void:
	_run()
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
	g._set_auto(true)
	var asks := 0
	var again := 0
	var multi := 0
	var last_node := -1
	var last_at := Vector2.INF
	var last_t := -100.0
	var t := 0.0
	var max_ways := 0
	var start: Vector2 = g._pos
	var far := 0.0
	for f in range(60 * 100):
		await physics_frame
		t += 1.0 / 60.0
		far = maxf(far, g._pos.distance_to(start))
		if g._cross.is_empty():
			continue
		var node: int = g._cross["node"]
		if node == last_node:
			continue
		asks += 1
		var at: Vector2 = g._nodes[node]
		var ways: Array = g._cross["ways"]
		max_ways = maxi(max_ways, ways.size())
		var legs := 0
		for w in ways:
			legs = maxi(legs, (w["legs"] as Array).size())
		if legs > 1:
			multi += 1
		var names := []
		for w in ways:
			names.append("%s%+d°x%d" % [w["name"], int(rad_to_deg(w["turn"])), (w["legs"] as Array).size()])
		if at.distance_to(last_at) < 45.0 and t - last_t < 15.0:
			again += 1
			print("  again %.0f m after the last: %s" % [at.distance_to(last_at), names])
		elif legs > 1:
			print("  knot: %s" % [names])
		last_node = node
		last_at = at
		last_t = t
	print("asked %d times, %d within 45 m of the last, %d across several points, at most %d ways; drove %.0f m out" % [asks, again, multi, max_ways, far])
	quit(0)
