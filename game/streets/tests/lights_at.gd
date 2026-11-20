extends SceneTree
## One junction with lights, seen from the driver's seat of a car waiting at its line, through
## the cycle: a shot at each step for the car's own light (green, flashing green, amber, red,
## red-and-amber), with the walk lights and the other way's light in view.
##
##   AT=x,z[,dx,dz] tests/run.sh lights_at 1     the site nearest x,z; the way in nearest (dx,dz)
##
## Prints the site: its points, its two axes, every way in (group, stop line, from inside),
## the walk lights' groups. Default: the Arvey Nahal junction in Givatayim (two divided roads,
## four points), reported by the user.
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var spec := OS.get_environment("AT").split(",") if OS.get_environment("AT") != "" else PackedStringArray(["-845", "-950", "-0.83", "-0.55"])
	var at := Vector2(float(spec[0]), float(spec[1]))
	var want := Vector2(float(spec[2]), float(spec[3])).normalized() if spec.size() >= 4 else Vector2.ZERO
	var best := INF
	var site := -1
	for n: int in g._lit:
		if g._nodes[n].distance_to(at) < best:
			best = g._nodes[n].distance_to(at)
			site = g._site_of[n]
	if site < 0:
		print("no lights")
		quit(1)
		return
	var st: Dictionary = g._sites[site]
	print("site %d: %d points round %s, group 1 the ways from %d to %d degrees%s" % [site, (st["nodes"] as Array).size(), (st["c"] as Vector2).round(),
			int(rad_to_deg(st["lo"])), int(rad_to_deg(st["hi"])), " (groups swapped)" if st.has("flip") else ""])
	var pick: Array = []
	var pick_n := -1
	var pick_dot := -2.0
	for n: int in st["nodes"]:
		for way: Array in g._sig_line[n]:
			var r: Dictionary = g._roads[int(way[2])]
			print("  point %d %s: in %s along '%s' -> group %d, line %.1f m%s" % [n, g._nodes[n].round(), (way[0] as Vector2).snapped(Vector2(0.01, 0.01)),
					r["name"], g._light_group(n, way[0]), way[1], " (from inside: no light)" if way[3] else ""])
			var dt: float = (way[0] as Vector2).dot(want) if want != Vector2.ZERO else 0.0
			if not way[3] and dt > pick_dot:
				pick_dot = dt
				pick = way
				pick_n = n
	for ni: int in g._crossing_nodes:
		if g._zebra_light(ni) >= 0 and g._site_of.get(g._zebra_light(ni), -1) == site:
			var z: Array = g._zebra_geom(ni)
			if not z.is_empty():
				print("  zebra %d %s across %s: walk light with group %d red" % [ni, g._nodes[ni].round(), (z[3] as Vector2).snapped(Vector2(0.01, 0.01)), g._light_group(g._zebra_light(ni), z[3])])
	if pick.is_empty() or OS.get_environment("OUT") == "":
		quit(0)
		return
	# the car at the line, its nose a metre short, in the right-hand lane
	var din: Vector2 = pick[0]
	var line: float = pick[1]
	var c: Vector2 = g._nodes[pick_n]
	g._land_on_road(c - din * (float(line) + 1.0 + g.CAR_LEN * 0.5), 12.0, din)
	g._v = 0.0
	var grp: int = g._light_group(pick_n, din)
	print("the car at point %d, way in %s, group %d" % [pick_n, din.snapped(Vector2(0.01, 0.01)), grp])
	await create_timer(2.0).timeout
	g.set_physics_process(false)
	# a step of the cycle for each thing the car's own light shows
	var shown := {}
	for i in range(g.SIGNAL_CYCLE.size()):
		var s: String = g.SIGNAL_CYCLE[i][grp]
		var other: String = g.SIGNAL_CYCLE[i][3 - grp]
		var key := s + "_" + other
		if shown.has(key):
			continue
		shown[key] = true
		g._sig_phase = i
		g._sig_t = 0.2
		g._sig_blink = true
		g._apply_signals()
		print("step %d: mine %s, across %s, my light reads %s" % [i, s, other, g._light_at(pick_n, din)])
		await _snap("%d_%s" % [i, key])
	g.set_physics_process(true)
	quit(0)
