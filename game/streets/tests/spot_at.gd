extends SceneTree
## What stands at one spot, and the roads there: each post within R m of AT (who put it up, its radius, how far
## inside the nearest road's asphalt) and the roads there (name, kind, width, one-way).
## Made for the racer's knocks on the way from Bialik into Kirinitsi, Givatayim, every drive.
##   POSTS_FROM=1 LEVEL=1 STREETS_BUILD_ALL=1 AT=537,-992 R=8 $GODOT --headless --path . -s res://game/streets/tests/spot_at.gd
var g: Node

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(_env("LEVEL", "1"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var xy := _env("AT", "537,-992").split(",")
	var at := Vector2(float(xy[0]), float(xy[1]))
	var r := float(_env("R", "8"))
	print("POSTS_AT %s within %.0f m" % [at, r])
	for i in range(g._roads.size()):
		var rd: Dictionary = g._roads[i]
		var pts: PackedVector2Array = rd["pts"]
		var best := INF
		for j in range(pts.size() - 1):
			best = minf(best, Geometry2D.get_closest_point_to_segment(at, pts[j], pts[j + 1]).distance_to(at))
		if best < r + 6.0:
			print("  road %d '%s' %s w %.1f one-way %d drive %s, its line %.1f m away, lane off %.1f" % [i, rd["name"], rd["k"],
				float(rd["w"]), int(rd["o"]), rd["drive"], best, float(g._lane_off(rd))])
	for i in range(g._posts.size()):
		var p: Vector2 = g._posts[i]
		if p.distance_to(at) > r:
			continue
		var hit: Dictionary = g._nearest_seg(p, 14.0, true)
		var edge := float(hit["edge"]) if not hit.is_empty() else INF
		var who: String = String(g._post_from[i]) if i < g._post_from.size() else "?"
		print("  post %d at %s r %.2f  edge %.2f (<0: on the asphalt)  knockable %s  from %s" % [i, p, float(g._post_r[i]), edge,
			g._knockable.has(i), who])
	quit(0)
