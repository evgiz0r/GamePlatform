extends SceneTree
## Parked cars standing in the middle of the road: a street's parked car with asphalt on BOTH
## sides of it (within 2.6 m of its middle, across it) stands between two carriageways -- on
## a divided road's median, where nobody parks. A user (Tel Aviv, Katznelson by Manara): "a
## lot of parked cars in the middle of somewhat main roads". Each half of a divided road is a
## one-way road of its own, and parked both its sides: its left side is the median. Expect 0
## (a few at odd corners at most); prints the first ones, the road beside each, and the city's
## count of parked cars. AT=x,z (optional) lists the parked cars within 60 m of it.
##   tests/run.sh parked_median 7
var g: Node
func _initialize() -> void:
	_run()

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
	var cars := 0
	var between := 0
	for i in range(g._parked_at.size()):
		var p: Vector2 = g._parked_at[i]
		var f: Vector2 = g._parked_face[i]
		var lx := Vector2(-f.y, f.x)
		cars += 1
		var hit: Dictionary = g._nearest_seg(p, 14.0, true)
		var ri := int(hit["road"]) if not hit.is_empty() else -1
		var r: Dictionary = g._roads[ri] if ri >= 0 else {}
		var both: bool = not g._off_road(p + lx * 2.6, 0.0) and not g._off_road(p - lx * 2.6, 0.0)
		if at != Vector2.INF and p.distance_to(at) < 60.0:
			print("  near AT: %s by '%s'%s" % [p.round(), r.get("name", "?"), " -- between two roads" if both else ""])
		if both:
			between += 1
			if between <= 12:
				print("  between two roads: %s, by '%s' (%s, one-way %s, median %s)" % [p.round(),
					r.get("name", "?"), r.get("k", "?"), r.get("o", "?"), r.get("median", "-")])
	# and in a bus stop: within BUS_CLEAR along its kerb of a stop's spot, on its side
	var at_stop := 0
	for ri: int in g._stops_by_road:
		var pts: PackedVector2Array = g._roads[ri]["pts"]
		for c: Vector2 in g._stops_by_road[ri]:
			var best := INF
			var dir := Vector2.ZERO
			for j in range(pts.size() - 1):
				var q := Geometry2D.get_closest_point_to_segment(c, pts[j], pts[j + 1])
				if q.distance_squared_to(c) < best:
					best = q.distance_squared_to(c)
					dir = (pts[j + 1] - pts[j]).normalized()
			for i in range(g._parked_at.size()):
				var p: Vector2 = g._parked_at[i]
				if absf((p - c).dot(dir)) < g.BUS_CLEAR and absf((p - c).dot(Vector2(-dir.y, dir.x))) < 4.0:
					at_stop += 1
	print("parked by the streets: %d; standing between two roads (a median): %d; in a bus stop (12 m either side, its kerb): %d" % [cars, between, at_stop])
	quit(0)
