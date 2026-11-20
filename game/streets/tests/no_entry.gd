extends SceneTree
## No-entry and "turn this way" signs: each no-entry sign must face drivers who would drive
## INTO a one-way street against it. For every one: the road it stands at, and whether the
## way a driver reading it goes is against that road's one-way direction. Good: none wrong.
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
	var counts := {}
	var wrong := 0
	var two_way := 0
	var examples: Array = []
	for e: Array in g._planted:
		var kind: String = e[0]
		counts[kind] = int(counts.get(kind, 0)) + 1
		if kind != "noentry":
			continue
		var p: Vector2 = e[1]
		var reader := -(e[2] as Vector2)   # the driver reading it goes against its face
		# the road it guards: the nearest drivable one whose line runs along the reader
		var best := INF
		var road: Dictionary = {}
		var d := Vector2.ZERO
		for code: int in g._near(g._seg_hash, p, 15.0, g.SEG_CELL):
			var r: Dictionary = g._roads[code / 4096]
			if not r["drive"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			var sj: int = code % 4096
			var sd := (pts[sj + 1] - pts[sj]).normalized()
			if absf(sd.dot(reader)) < 0.7:
				continue
			var q := Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1])
			if q.distance_to(p) < best:
				best = q.distance_to(p)
				road = r
				d = sd
		if e.size() > 3:   # the road it was put up for
			road = g._roads[int(e[3])]
			var pts2: PackedVector2Array = road["pts"]
			var bd := INF
			for j in range(pts2.size() - 1):
				var q2 := Geometry2D.get_closest_point_to_segment(p, pts2[j], pts2[j + 1])
				if q2.distance_to(p) < bd:
					bd = q2.distance_to(p)
					d = (pts2[j + 1] - pts2[j]).normalized()
		if road.is_empty():
			continue
		var o := int(road["o"])
		if o == 0:
			two_way += 1
			if examples.size() < 5:
				examples.append("on two-way %s at %s" % [road["en"], Vector2i(p)])
		elif (d * float(o)).dot(reader) > 0.0:
			wrong += 1
			if examples.size() < 5:
				examples.append("facing drivers going the street's own way, %s at %s" % [road["en"], Vector2i(p)])
	print("signs: %s" % str(counts))
	print("no-entry signs facing drivers who may go in: %d, on two-way streets: %d" % [wrong, two_way])
	for x in examples:
		print("  ", x)
	quit(0)
