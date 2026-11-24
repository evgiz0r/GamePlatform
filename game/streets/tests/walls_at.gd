extends SceneTree
## What thin walls stand at a spot: every wall segment (fences, railings, hedges, garden
## walls, a shelter's back) within R m (default 4) of AT (x,z), its ends, thickness, whether
## it gives (railing, low wall, hedge), and how far into or clear of the nearest road's
## asphalt each end is -- for a hit on "wall N" in a drive log or the route set.
##   LEVEL=1 STREETS_BUILD_ALL=1 AT="709,202" $GODOT --headless --path . -s res://game/streets/tests/walls_at.gd
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	var a := OS.get_environment("AT").split(",")
	var at := Vector2(float(a[0]), float(a[1]))
	var R := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 4.0
	for i in range(g._wall_r.size()):
		var p: Vector2 = g._walls[i * 2]
		var q: Vector2 = g._walls[i * 2 + 1]
		if Geometry2D.get_closest_point_to_segment(at, p, q).distance_to(at) > R:
			continue
		var ends: Array = []
		for e: Vector2 in [p, q]:
			var hit: Dictionary = g._nearest_seg(e, 15.0, true, true)
			if hit.is_empty():
				ends.append("no road near")
				continue
			var r: Dictionary = g._roads[hit["road"]]
			ends.append("%.2f m %s %s's asphalt" % [absf(float(hit["edge"])), "into" if float(hit["edge"]) < 0.0 else "clear of", r["name"]])
		print("WALL %d (%.2f, %.2f) - (%.2f, %.2f) %.1f m, half %.2f, gives %d, rail %d, hedge %d: ends %s" % [i, p.x, p.y, q.x, q.y, p.distance_to(q),
			g._wall_r[i], g._wall_give[i], g._wall_rail[i] if i < g._wall_rail.size() else -1, g._wall_soft[i], " / ".join(ends)])
	quit(0)
