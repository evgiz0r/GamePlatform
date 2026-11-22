extends SceneTree
## Where traffic's line lies across a two-way street, point by point: for the road nearest AT
## ("x,z"), a car started on it each way (traffic's own `_start_on`), and each point of its path
## while still on that road -- how far right of the road's middle (left: negative), the
## road's width and lane offset, and what `_clear_lane` gave there. For the exam's "traffic
## left of the middle" (22 Nov 2026: Ein Gedi, Yavnieli, HaArava -- every case a car on the
## first stretch of its path, shift 0).
##   LEVEL=1 AT="706,867" STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/lane_points.gd
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
	await create_timer(1.0).timeout
	var tr = g._traffic
	for sp in OS.get_environment("AT").split(";", false):
		var xz := sp.split(",")
		var at := Vector2(float(xz[0]), float(xz[1]))
		var hit: Dictionary = g._nearest_seg(at, 10.0, true, true)
		if hit.is_empty():
			print("AT (%.0f, %.0f): no road" % [at.x, at.y])
			continue
		var ri: int = hit["road"]
		var r: Dictionary = g._roads[ri]
		var p: PackedVector2Array = r["pts"]
		print("AT (%.0f, %.0f): road %d %s (%s) %.1f m wide o%d, %d points, lane %.2f" % [at.x, at.y, ri, String(r.get("en", r["name"])), r["k"], float(r["w"]), int(r["o"]), p.size(), tr._lane(r)])
		for dir: int in [1, -1]:
			var c = null
			for cc in tr.cars:
				if not cc.alive:
					c = cc
					break
			if c == null:
				c = tr.cars[0]
			if not tr._start_on(c, ri, hit["seg"], hit["q"], dir):
				print("  dir %d: could not start" % dir)
				continue
			var row := []
			for k in range(mini(c.pts.size(), 14)):
				if c.rd[k] != ri:
					break
				var q: Vector2 = c.pts[k]
				# right of the road's middle, along the way it goes
				var best := INF
				var off := 0.0
				for j in range(p.size() - 1):
					var cp := Geometry2D.get_closest_point_to_segment(q, p[j], p[j + 1])
					if cp.distance_to(q) < best:
						best = cp.distance_to(q)
						var d := (p[j + 1] - p[j]).normalized() * dir
						off = (q - cp).dot(Vector2(-d.y, d.x))
				row.append("%d:%+.2f" % [k, off])
			print("  dir %+d: right of the middle %s" % [dir, "  ".join(row)])
			c.alive = false
	quit(0)
