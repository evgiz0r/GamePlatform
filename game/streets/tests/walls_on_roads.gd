extends SceneTree
## Walls the car collides with (garden walls at the back of the pavement, fences, hedges,
## bus shelters' backs) that stand on a road's asphalt, where nothing should stand: counted by
## kind (by their thickness), with the worst places. Medians are walls in the road on
## purpose and are left out. Autodrive once turned left onto a main road and drove into a
## garden wall belonging to the side street running alongside, laid on the main road.
## WALL_AT="x,z" also lists every wall within 6 m of that point.
var g: Node

func _initialize() -> void:
	_run()

func _kind(half: float) -> String:
	if half <= 0.07:
		return "fence"
	if half <= 0.1:
		return "shelter back"
	if half <= 0.2:
		return "garden wall"
	if is_equal_approx(half, 0.4):
		return "hedge"
	return "median"

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var counts := {}
	var worst: Array = []
	var near_at := Vector2.INF
	if OS.get_environment("WALL_AT") != "":
		var xz := OS.get_environment("WALL_AT").split(",")
		near_at = Vector2(float(xz[0]), float(xz[1]))
	for i in range(g._wall_r.size()):
		var a: Vector2 = g._walls[i * 2]
		var b: Vector2 = g._walls[i * 2 + 1]
		var half: float = g._wall_r[i]
		var kind := _kind(half)
		var mid := (a + b) * 0.5
		if near_at != Vector2.INF and Geometry2D.get_closest_point_to_segment(near_at, a, b).distance_to(near_at) < 6.0:
			print("  wall %d (%s, %.2f thick) %s -> %s" % [i, kind, half * 2.0, a, b])
		if kind == "median":
			continue
		# how far into a drivable road's asphalt (negative: inside it), at its ends and middle
		# (by the middle alone, one from the middle of a street to its pavement was missed)
		var into := -INF
		var on := {}
		for q: Vector2 in [a, mid, b]:
			var hit: Dictionary = g._nearest_seg(q, 20.0, true, false)
			if not hit.is_empty() and -float(hit["edge"]) - half > into:
				into = -float(hit["edge"]) - half
				on = hit
		if on.is_empty():
			continue
		if into > 0.3:
			counts[kind] = int(counts.get(kind, 0)) + 1
			worst.append([into, kind, mid, (g._roads[on["road"]] as Dictionary)["en"], i])
	worst.sort_custom(func(x, y): return x[0] > y[0])
	print("WALLS ON ROADS (%d walls in all): %s" % [g._wall_r.size(), str(counts)])
	for w: Array in worst.slice(0, 15):
		print("  %.1f m into %s: %s at %s (wall %d)" % [w[0], w[3] if String(w[3]) != "" else "a road", w[1], Vector2i(w[2]), w[4]])
	quit(0)
