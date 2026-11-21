extends SceneTree
## Posts standing where the cars drive at the split of a divided road. OSM starts both halves
## of a divided road at the two-way road's middle, so for some metres past the split a car in
## the two-way road's lane drives on past the narrower half's asphalt, beside it -- and the
## half's "one way" arrow, planted 1 m off that asphalt, stood in that lane (Ashdod's Shlomo
## Ben Yosef: autodrive knocked it flat at 50 km/h on every drive, 19 km/h gone in a tenth
## of a second, and the route set did not count it: a sign bent is no crash).
## For every point where a two-way road ends and a narrower one-way half of its name goes on
## within 37 degrees of straight, both of the two-way road's lane lines (`_lane_off`) run
## 5 m back and 14 m on past the point; any post (sign, bin, bollard, lamp) within the
## car's half width, the post's radius and a quarter metre of either is printed. PASS: none.
##   LEVEL=3 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/split_posts.gd
## (STREETS_BUILD_ALL=1: the posts are planted as the squares build -- without it, only
## those round the start.) The places tests/pick_routes.py keeps away from are counted, not
## printed.
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
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var splits := 0
	var found := 0
	var seen := {}
	for ni in range(g._nodes.size()):
		if ni >= g._node_roads.size():
			continue
		var c: Vector2 = g._nodes[ni]
		for e: Vector2i in g._node_roads[ni]:
			var r: Dictionary = g._roads[e.x]
			var pts: PackedVector2Array = r["pts"]
			if int(r["o"]) != 0 or not r["drive"] or String(r.get("name", "")) == "" or (e.y != 0 and e.y != pts.size() - 1):
				continue
			var prev: int = 1 if e.y == 0 else e.y - 1
			if prev < 0 or prev >= pts.size():
				continue
			var t: Vector2 = (c - pts[prev]).normalized()   # along the two-way road, out past its end
			var half := false
			for h: Vector2i in g._node_roads[ni]:
				var hr: Dictionary = g._roads[h.x]
				var hp: PackedVector2Array = hr["pts"]
				if h.x == e.x or int(hr["o"]) == 0 or String(hr.get("name", "")) != String(r["name"]) or float(hr["w"]) > float(r["w"]) - 2.0:
					continue
				for k: int in [h.y - 1, h.y + 1]:
					if k >= 0 and k < hp.size() and (hp[k] - c).normalized().dot(t) > 0.8:
						half = true
			if not half:
				continue
			splits += 1
			var right := Vector2(-t.y, t.x)
			var off: float = g._lane_off(r)
			for sd: float in [1.0, -1.0]:
				var a := c - t * 5.0 + right * sd * off
				var b := c + t * 14.0 + right * sd * off
				for pi in range(g._posts.size()):
					var q: Vector2 = g._posts[pi]
					var pr: float = g._post_r[pi]
					if pr <= 0.0 or q.distance_to(c) > 20.0 or seen.has(pi):
						continue
					var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))
					if d < 0.9 + pr + 0.25:
						seen[pi] = true
						found += 1
						var what := "sign " + str(g._signs_at[pi][0]) if g._signs_at.has(pi) else ("knockable" if g._knockable.has(pi) else "post")
						if priv.near(avoid, q):
							print("  (one at a place the tests keep away from)")
						else:
							print("  %s r %.2f at (%.1f, %.1f), %.2f m from the %s lane line of %s, %.1f m from its end" % [what, pr, q.x, q.y, d,
								"right" if sd > 0.0 else "left", String(r.get("en", r["name"])), q.distance_to(c)])
	print("SPLIT POSTS: %d splits of a two-way road into a narrower half, %d posts in a lane line past them -- %s" % [splits, found, "PASS" if found == 0 else "FAIL"])
	quit()
