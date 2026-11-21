extends SceneTree
## People's lights put up twice: two walk-light poles within 3 m of each other facing the same
## way. A user (Ashdod, a divided road's zebra by a corner island): "two red lights to the same
## direction for the people". Counts the pairs among the lights the city built (`_walk_spots`)
## and, for each of the first ones, the zebras (crossing points) whose spans put them there and
## the road. Expect 0. AT=x,z lists the walk lights within 40 m of it; OUT gets a shot of the
## first pair from across the street (twins_<i>.png).
##   tests/run.sh walk_twins 3
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

## the zebras whose walk lights stand at p facing `across`: "node (road, span length)"
func _whose(p: Vector2, across: Vector2) -> String:
	var out: Array = []
	for ni: int in g._crossing_nodes:
		if (g._nodes[ni] as Vector2).distance_to(p) > 60.0:
			continue
		var z: Array = g._zebra_geom(ni)
		if z.is_empty() or g._zebra_light(ni) < 0:
			continue
		var span: Array = g._zebra_span(z)
		if span.is_empty():
			continue
		for k in range(2):
			var a: Vector2 = span[k]
			var dir: Vector2 = ((span[1 - k] as Vector2) - a).normalized()
			if (a - dir * 0.35).distance_to(p) < 0.5 and dir.dot(across) > 0.99:
				var r: Dictionary = g._roads[int(z[4])]
				out.append("%d at %s ('%s' %s, one-way %s, median %s, span %.1f m)" % [ni, (g._nodes[ni] as Vector2).round(),
					r["name"], r["k"], r["o"], r.get("median", "-"), (span[0] as Vector2).distance_to(span[1])])
	return "; ".join(out)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	var at := Vector2.INF
	if OS.get_environment("AT") != "":
		var xz := OS.get_environment("AT").split(",")
		at = Vector2(float(xz[0]), float(xz[1]))
	var spots: Array = g._walk_spots
	var pairs: Array = []
	for i in range(spots.size()):
		var pi := Vector2((spots[i][0] as Vector3).x, (spots[i][0] as Vector3).z)
		var fi: Vector2 = spots[i][1]
		if at != Vector2.INF and pi.distance_to(at) < 40.0:
			print("  near AT: walk light at %s facing %s" % [pi.round(), fi.snapped(Vector2(0.01, 0.01))])
		for j in range(i + 1, spots.size()):
			var pj := Vector2((spots[j][0] as Vector3).x, (spots[j][0] as Vector3).z)
			if pi.distance_to(pj) < 3.0 and fi.dot(spots[j][1]) > 0.8:
				pairs.append([pi, pj, fi])
	print("walk lights %d; pairs within 3 m facing the same way: %d" % [spots.size(), pairs.size()])
	for k in range(mini(pairs.size(), 10)):
		var pr: Array = pairs[k]
		print("  pair %d: %s and %s (%.1f m apart)\n    first by: %s\n    second by: %s" % [k, (pr[0] as Vector2).round(),
			(pr[1] as Vector2).round(), (pr[0] as Vector2).distance_to(pr[1]), _whose(pr[0], pr[2]), _whose(pr[1], pr[2])])
	if OS.get_environment("OUT") != "" and not pairs.is_empty():
		g.set_physics_process(false)
		process_frame.disconnect(g._frame)
		for k in range(mini(pairs.size(), 2)):
			var pr: Array = pairs[k]
			var mid: Vector2 = ((pr[0] as Vector2) + (pr[1] as Vector2)) * 0.5
			var f: Vector2 = pr[2]
			var eye: Vector2 = mid + f * 9.0 + Vector2(-f.y, f.x) * 3.0
			var y: float = g._h(mid)
			g.look_from(Vector3(eye.x, g._h(eye) + 2.0, eye.y), Vector3(mid.x, y + 2.0, mid.y))
			await _snap("twins_%d" % k)
	quit(0)
