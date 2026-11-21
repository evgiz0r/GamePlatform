extends SceneTree
## What lays the ground at a spot: every road whose kerb and pavement band (its half width
## out to half width + a pavement + a shop's extra) reaches the spot, with its kind, name,
## width, whether it is kerbed, its paving code and how far its line is. For "the ground there
## is not what the details say" -- a details area under a neighbour's pavement.
##   AT="x,z;x,z" game/streets/tests/run.sh what_paves 5      (STREETS_BUILD_ALL=0 is enough)
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	for spot in OS.get_environment("AT").split(";"):
		var xy := spot.split(",")
		var p := Vector2(float(xy[0]), float(xy[1]))
		print("at ", p, ":")
		for ri in range(g._roads.size()):
			var r: Dictionary = g._roads[ri]
			var pts: PackedVector2Array = r["pts"]
			var best := INF
			for i in range(pts.size() - 1):
				best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
			var hw := float(r["w"]) * 0.5
			if best <= hw + g.PAVE_W + g.SHOP_PAVE + 0.5:
				print("  road %d %s '%s' w %.1f kerbed %s pave %s: its line %.2f m off (pavement %.1f-%.1f)" % [ri, r["k"],
					r.get("name", ""), float(r["w"]), g._kerbed(r), r.get("pave", "-"), best, hw, hw + g.PAVE_W])
	quit()
