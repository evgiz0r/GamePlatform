extends SceneTree
## What stands at a spot: every post within 2 m of each AT point (x,z;x,z...), who put it up,
## its radius, and where it is against the nearest road's asphalt -- for a post the exam says
## traffic drives into ("traffic into a post at (x, z) ... post N").
##   POSTS_FROM=1 LEVEL=3 STREETS_BUILD_ALL=1 AT="-2035,2466;-2966.9,5116.6" $GODOT --headless --path . -s res://game/streets/tests/posts_at.gd
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var at_s := OS.get_environment("AT")
	if OS.get_environment("IDS") != "":   # IDS="52944,...": the posts by number (the exam's / racer's "post N")
		var parts := []
		for sid in OS.get_environment("IDS").split(","):
			var pp: Vector2 = g._posts[int(sid)]
			parts.append("%f,%f" % [pp.x, pp.y])
		at_s = ";".join(parts)
	for s in at_s.split(";"):
		var xz := s.split(",")
		var at := Vector2(float(xz[0]), float(xz[1]))
		print("AT (%.1f, %.1f):" % [at.x, at.y])
		for i in range(g._posts.size()):
			var p: Vector2 = g._posts[i]
			if p.distance_to(at) > float(OS.get_environment("NEAR") if OS.get_environment("NEAR") != "" else "2"):
				continue
			var hit: Dictionary = g._nearest_seg(p, 25.0, true, true)
			var where := "no road near"
			if not hit.is_empty():
				var r: Dictionary = g._roads[hit["road"]]
				var q: Vector2 = hit["q"]
				var edge := p.distance_to(q) - float(r["w"]) * 0.5
				where = "%s (%s, %.1f m wide, %d lanes a way, o%d): centre %.2f m from the road's middle, its edge %.2f m %s the asphalt's edge" % [
					String(r.get("en", r["name"])), r["k"], float(r["w"]), int(g._traffic._lanes_dir(r)), int(r["o"]),
					p.distance_to(q), absf(edge - float(g._post_r[i])), "outside" if edge - float(g._post_r[i]) > 0.0 else "inside"]
			# against every drivable road near, not only the nearest middle
			for code: int in g._near(g._seg_hash, p, 12.0, g.SEG_CELL):
				var r2: Dictionary = g._roads[code / 4096]
				if not r2["drive"]:
					continue
				var pts2: PackedVector2Array = r2["pts"]
				var sj: int = code % 4096
				var q2 := Geometry2D.get_closest_point_to_segment(p, pts2[sj], pts2[sj + 1])
				var e2 := p.distance_to(q2) - float(r2["w"]) * 0.5 - float(g._post_r[i])
				if e2 < 0.6:
					print("      road %d %s (%s, %.1f m wide, seg %d): the post's edge %.2f m %s its asphalt" % [code / 4096, String(r2.get("en", r2["name"])), r2["k"], float(r2["w"]), sj, absf(e2), "outside" if e2 > 0.0 else "INSIDE"])
			print("  post %d at (%.2f, %.2f) r %.2f -- %s -- from %s" % [i, p.x, p.y, g._post_r[i], where,
				g._post_from[i] if i < g._post_from.size() else "(POSTS_FROM=1 to see who)"])
	# ROADS_AT="x,z": every drivable road within 15 m, its width and lanes
	if OS.get_environment("ROADS_AT") != "":
		var xz2 := OS.get_environment("ROADS_AT").split(",")
		var at2 := Vector2(float(xz2[0]), float(xz2[1]))
		var tr2 = g._traffic
		var seen2 := {}
		for code: int in g._near(g._seg_hash, at2, 15.0, g.SEG_CELL):
			var ri2: int = code / 4096
			var r3: Dictionary = g._roads[ri2]
			var pts3: PackedVector2Array = r3["pts"]
			var sj3: int = code % 4096
			var q3 := Geometry2D.get_closest_point_to_segment(at2, pts3[sj3], pts3[sj3 + 1])
			if not r3["drive"] or seen2.has(ri2) or q3.distance_to(at2) > 15.0:
				continue
			seen2[ri2] = true
			print("NEAR road %d %s (%s) %.1f m wide o%d, %d lanes a way, lane_off %.2f, %.1f m from the spot, seg %d (%.0f,%.0f)->(%.0f,%.0f)" % [ri2, String(r3.get("en", r3["name"])), r3["k"], float(r3["w"]), int(r3["o"]), tr2._lanes_dir(r3), tr2._lane(r3), q3.distance_to(at2), sj3, pts3[sj3].x, pts3[sj3].y, pts3[sj3 + 1].x, pts3[sj3 + 1].y])
	# LANES="road,road": where traffic's lanes lie across each (right of the middle, +), and a
	# bus's and a car's sides in the kerb lane against the asphalt's edge
	if OS.get_environment("LANES") != "":
		var tr = g._traffic
		for rs in OS.get_environment("LANES").split(","):
			var r: Dictionary = g._roads[int(rs)]
			var n: int = tr._lanes_dir(r)
			var lane: float = tr._lane(r)
			var row := []
			for idx in range(n):
				row.append("%d: %.2f" % [idx, lane - tr._lane_shift(r, idx)])
			var bus_hw: float = (tr.CORNERS.get("bus", Vector2(1.25, 6)) as Vector2).x
			var k0: float = lane - tr._lane_shift(r, 0)
			print("ROAD %d %s: %.1f m wide, o%d, %d lanes a way (data l=%s), lane_off %.2f; lane centres right of the middle %s; a bus's kerb side %.2f m from the middle, the edge %.2f; bus lane %s" % [
				int(rs), String(r.get("en", r["name"])), float(r["w"]), int(r["o"]), n, str(r.get("l", "-")), lane, ", ".join(row), k0 + bus_hw, float(r["w"]) * 0.5, str(g._has_bus_lane(r))])
	quit(0)
