extends SceneTree
## Autodrive's back end at a corner: does it clear what stands at the corner of the pavement?
## Route 3 (Givatayim, Reines 70 right into Ben Gurion, 24 Nov 2026) touched a sign post 1.3 m
## off the kerb at 11-19 km/h every run: going round a corner the car points along the way
## it came, so its back swings inside the corner. Lands the car as route_set does (FROM),
## sends it to TO on autodrive for SECS (12) s, and prints, every 0.25 s near POST, the car's
## speed and the gap from each of its two body circles to the post (good: over 0, the
## circles' edges clear), and the nearest plan point's gap.
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/corner_post.gd
## Good: no "TOUCH", the closest gap over 0.1 m. Before: the back circle 0.25 m into the post.
var g: Node

func _initialize() -> void:
	_run()

func _vec(env: String, def: Vector2) -> Vector2:
	var s := OS.get_environment(env)
	if s == "":
		return def
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	var from := _vec("FROM", Vector2(692.2, 211.3))
	var to := _vec("TO", Vector2(-1180.3, 372.3))
	var post_at := _vec("POST", Vector2(708.75, 202.98))
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 12.0
	# the post: the nearest round solid thing to POST
	var pi := -1
	for i in range(g._posts.size()):
		if g._posts[i].distance_to(post_at) < 1.0 and (pi < 0 or g._posts[i].distance_to(post_at) < g._posts[pi].distance_to(post_at)):
			pi = i
	if pi < 0:
		print("no post near %s" % post_at)
		quit(1)
		return
	var post: Vector2 = g._posts[pi]
	var pr: float = g._post_r[pi]
	g._land_on_road(from, 60.0, Vector2.ZERO)
	await physics_frame
	g._set_dest(to, "")
	g._set_auto(true)
	var t := 0.0
	var next := 0.0
	var worst := INF
	var worst_v := 0.0
	var touches := 0
	while t < secs:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var fwd: Vector2 = g._fwd()
		var gaps: Array = []
		for off: float in [g.CAR_OFF, -g.CAR_OFF]:
			gaps.append((g._pos + fwd * off).distance_to(post) - g.CAR_R - pr)
		var gap: float = minf(gaps[0], gaps[1])
		if gap < worst:
			worst = gap
			worst_v = absf(g._v)
		if gap < 0.0:
			touches += 1
		if g._pos.distance_to(post) < 12.0 and t >= next:
			next = t + 0.25
			var pg := INF
			var pp: PackedVector2Array = g._ap_pts
			for k in range(pp.size() - 1):   # (its line, not only its points: they can be 5 m apart)
				pg = minf(pg, Geometry2D.get_closest_point_to_segment(post, pp[k], pp[k + 1]).distance_to(post))
			if OS.get_environment("PLAN") != "":
				var pl := ""
				for p: Vector2 in g._ap_pts:
					if p.distance_to(post) < 8.0:
						pl += " (%.1f,%.1f)" % [p.x, p.y]
				print("   plan:" + pl)
			print("t %.2f at (%.1f, %.1f) %.1f km/h yaw %.2f: front %.2f back %.2f m clear%s; plan's line %.2f m from the post" % [
				t, g._pos.x, g._pos.y, absf(g._v) * 3.6, g._yaw, gaps[0], gaps[1], "  TOUCH" if gap < 0.0 else "", pg])
	print("REGRESS corner_post: %s -- autodrive round a corner past a post at the corner (Givatayim, Reines into Ben Gurion): closest %.2f m clear at %.0f km/h, %d ticks touching (the bug: 0.25 m into it at 11-19 km/h)" % [
		"PASS" if worst > 0.0 else "FAIL", worst, worst_v * 3.6, touches])
	quit(0)
