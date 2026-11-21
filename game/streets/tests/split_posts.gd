extends SceneTree
## Posts standing where the cars drive at the split of a divided road. OSM starts both halves
## of a divided road at the two-way road's middle, so for some metres past the split a car in
## the two-way road's lane drives on past the narrower half's asphalt, beside it -- and the
## half's "one way" arrow, planted 1 m off that asphalt, stood in that lane (Ashdod's Shlomo
## Ben Yosef: autodrive knocked it flat at 50 km/h on every drive, 19 km/h gone in a tenth
## of a second, and the route set did not count it: a sign bent is no crash).
## For every point where a two-way road ends and a narrower one-way half of its name goes on
## within 37 degrees of straight, the line the cars drive along each half -- from the two-way
## road's lane (`_lane_off`) at the point over to the half's own lane line 25 m on, as
## autodrive does -- and any post (sign, bin, bollard, lamp) within the car's half width, the
## post's radius and a quarter metre of it is printed. PASS: none.
##   LEVEL=3 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/split_posts.gd
## DRIVE=1: then autodrive through each split that has any, as it really drives -- how close
## its body comes to each post (under 0.05 m: touched) and anything it knocks over.
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
	var drives: Array = []   # [from, heading, to, posts near its line] -- DRIVE=1
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
			# the halves: one going on out of here (my way on), one coming in beside it
			var halves: Array = []   # [road, the next point along it from here, +1 out / -1 in]
			for h: Vector2i in g._node_roads[ni]:
				var hr: Dictionary = g._roads[h.x]
				var hp: PackedVector2Array = hr["pts"]
				if h.x == e.x or int(hr["o"]) == 0 or String(hr.get("name", "")) != String(r["name"]) or float(hr["w"]) > float(r["w"]) - 2.0:
					continue
				for k: int in [h.y - 1, h.y + 1]:
					if k >= 0 and k < hp.size() and (hp[k] - c).normalized().dot(t) > 0.8:
						halves.append([hr, hp[k], 1 if k == h.y + int(hr["o"]) else -1])
			if halves.is_empty():
				continue
			splits += 1
			var off: float = g._lane_off(r)
			for hv: Array in halves:
				var hr: Dictionary = hv[0]
				var u: Vector2 = ((hv[1] as Vector2) - c).normalized()   # along the half, away from here
				var way: int = hv[2]
				# the line the cars drive: the two-way road's lane at the point, over to the
				# half's own lane line 25 m on (as autodrive does: Shlomo Ben Yosef, 2.4 m right
				# of the half's middle at the split, 1.2 m at 12 m, 0.1 m at 24)
				var trav := u * float(way)                     # which way the cars go along it
				var right := Vector2(-trav.y, trav.x)
				var tw := t * float(way)                       # ...and along the two-way road
				var at0 := (Vector2(-tw.y, tw.x) * off).dot(right)
				var off_h: float = g._lane_off(hr)
				var line := PackedVector2Array()
				for i in range(0, 26):
					var sd := float(i)
					line.append(c + u * sd + right * lerpf(at0, off_h, sd / 25.0))
				var near_line: Array = []
				for pi: int in g._near(g._post_hash, c, 30.0, g.BLD_CELL):
					var q: Vector2 = g._posts[pi]
					var pr: float = g._post_r[pi]
					if pr <= 0.0 or seen.has(pi):
						continue
					var d := INF
					for i in range(line.size() - 1):
						d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, line[i], line[i + 1])))
					if d < 0.9 + pr + 0.25:
						near_line.append(pi)
						seen[pi] = true
						found += 1
						var what := "sign " + str(g._signs_at[pi][0]) if g._signs_at.has(pi) else ("knockable" if g._knockable.has(pi) else "post")
						if priv.near(avoid, q):
							print("  (one at a place the tests keep away from)")
						else:
							print("  %s r %.2f at (%.1f, %.1f), %.2f m from the line %s the half %s %s, %.1f m from the split" % [what, pr, q.x, q.y, d,
								"out along" if way > 0 else "in along", String(hr.get("en", hr["name"])), "(one-way out)" if way > 0 else "(one-way in)", q.distance_to(c)])
				if not near_line.is_empty() and not priv.near(avoid, c):
					# out along the half: from 50 m back on the two-way road to 40 m along it; in
					# along it: from 40 m along it back out onto the two-way road, 50 m
					if way > 0:
						drives.append([c - t * 50.0, t, c + u * 40.0, near_line, String(hr.get("en", hr["name"])) + " out"])
					else:
						drives.append([c + u * 40.0, -u, c - t * 50.0, near_line, String(hr.get("en", hr["name"])) + " in"])
	print("SPLIT POSTS: %d splits of a two-way road into a narrower half, %d posts in a lane line past them -- %s" % [splits, found, "PASS" if found == 0 else "FAIL"])
	if OS.get_environment("DRIVE") != "":
		await _drive(drives)
	quit()

## DRIVE=1: autodrive through each split with posts near the line, as it really drives: how
## close its body comes to each of them (metres between them; under 0 it hit), and what it
## knocked over on the way
func _drive(drives: Array) -> void:
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var touched := 0
	for dv: Array in drives:
		g._set_auto(false)
		if not g._land_on_road(dv[0], 8.0, dv[1]):
			print("  %s: no road to start on" % dv[4])
			continue
		g._v = 0.0
		await physics_frame
		g._set_dest(dv[2], "split test")
		g._set_auto(true)
		var k0: int = g._knocked_n
		var best := {}
		var t := 0.0
		while t < 30.0 and g._dest_on and g._pos.distance_to(dv[2]) > 12.0:
			await physics_frame
			t += dt
			for pi: int in dv[3]:
				var r0: float = g._post_r[pi]
				for off: float in [g.CAR_OFF, -g.CAR_OFF]:
					var gap: float = (g._pos + g._fwd() * off).distance_to(g._posts[pi]) - g.CAR_R - maxf(r0, 0.06)
					best[pi] = minf(float(best.get(pi, INF)), gap)
		var parts: Array = []
		for pi: int in dv[3]:
			parts.append("%.2f" % float(best.get(pi, INF)))
			if float(best.get(pi, INF)) < 0.05:
				touched += 1
		print("  %s: %.0f s, knocked %d (%s); closest to each post %s" % [dv[4], t, g._knocked_n - k0, g._knocked_what if g._knocked_n > k0 else "-", ", ".join(parts)])
	print("SPLIT DRIVES: %d drives, %d posts touched" % [drives.size(), touched])
