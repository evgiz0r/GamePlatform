extends SceneTree
## The roads round one spot near the map's edge, for autodrive's edge rules: each road within
## R metres of AT (x,z), its kind, one-way, ends, and for each way along it whether
## _edge_bound calls it a way that only runs off the map.
##   LEVEL=7 AT=1190,-1330 R=60 STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/edge_pocket.gd
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
	var a := OS.get_environment("AT").split(",")
	var at := Vector2(float(a[0]), float(a[1]))
	var rad := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 60.0
	var rim: Rect2 = g._bounds.grow(-g.EDGE - g.EDGE_ROOM)
	print("rim ", rim)
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var near := INF
		for k in range(pts.size() - 1):
			near = minf(near, Geometry2D.get_closest_point_to_segment(at, pts[k], pts[k + 1]).distance_to(at))
		if near > rad:
			continue
		var ids: PackedInt32Array = r["ids"]
		var ends := []
		for e in [0, pts.size() - 1]:
			ends.append("%s (%d ways)" % [str(pts[e].round()), g._node_ways(ids[e])])
		var legs := []
		for d in [1, -1]:
			if int(r["o"]) != 0 and int(r["o"]) != d:
				continue
			var leg := Vector3i(ri, 1 if d > 0 else pts.size() - 2, d)
			legs.append("%s: %s" % ["fwd" if d > 0 else "back", "OFF THE MAP" if g._edge_bound(leg) else "leads on"])
		print("road %d %s '%s' o=%d pv=%s mate=%d %d m away, %s -> %s; %s" % [ri, r["k"], r["name"], int(r["o"]), str(r["pv"]), int(r.get("mate", -1)), near, ends[0], ends[1], ", ".join(legs)])
	if OS.get_environment("POSTS") != "":
		# (POSTS=1, with POSTS_FROM=1: the posts and walls within 6 m, and who put each post up)
		for i in range(g._posts.size()):
			if g._posts[i].distance_to(at) < 6.0:
				print("post %d at %s r %.2f %s" % [i, str(g._posts[i].snapped(Vector2(0.1, 0.1))), g._post_r[i], g._post_from[i] if i < g._post_from.size() else ""])
		for i in range(0, g._walls.size(), 2):
			var q := Geometry2D.get_closest_point_to_segment(at, g._walls[i], g._walls[i + 1])
			if q.distance_to(at) < 6.0:
				print("wall %d %s -> %s, %.1f m off" % [i / 2, str(g._walls[i].round()), str(g._walls[i + 1].round()), q.distance_to(at)])
	quit()
