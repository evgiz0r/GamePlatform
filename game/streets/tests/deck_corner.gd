extends SceneTree
## A deck (bridge, embankment, cutting) that starts at street level at a junction: its walls
## near the junction's point (`AT=x,z`, `R` metres round it) are listed, then autodrive is
## sent through the turn on each route in `ROUTES` ("x,z>x,z;...": put down on the road at
## the first point facing the junction, the destination at the second) for up to 40 s, and
## every crash is counted with what it hit. Good: no wall listed in the side street's mouth,
## no crash. Defaults: Bedford, Union Street meeting Bedford Highway where its bridge starts
## (autodrive turning out of Union Street hit the bridge's parapet).   tests/run.sh deck_corner 2
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _v2(s: String) -> Vector2:
	var xz := s.split(",")
	return Vector2(float(xz[0]), float(xz[1]))

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var at := _v2(OS.get_environment("AT") if OS.get_environment("AT") != "" else "448,-1125")
	var rad := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 15.0
	var near := 0
	for w: Array in g._decks._walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		if Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < rad:
			near += 1
			print("  wall '%s' %s - %s, %.1f m from the junction" % [w[7], a.round(), b.round(), Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at)])
	print("deck walls within %.0f m of %s: %d" % [rad, at, near])
	# the decks there: each point's surface over the ground
	for ri: int in g._decks.decks:
		var r: Dictionary = g._roads[ri]
		var pts: PackedVector2Array = r["pts"]
		if not Array(pts).any(func(q): return (q as Vector2).distance_to(at) < 40.0):
			continue
		var rises: Array = []
		for j in range(pts.size()):
			rises.append("%s %.1f" % [pts[j].round(), float(r["ys"][j]) - float(r["gs"][j])])
		print("  deck %d '%s' (%s, %s, w %.1f, side %.1f): %s" % [ri, r["name"], r["deck"], r["k"], r["w"], r["side"], ", ".join(rises)])
	if OS.get_environment("PROBE") != "":   # (debugging: what the walls' street check sees at points)
		for q: String in OS.get_environment("PROBE").split(";", false):
			var p := _v2(q)
			var seen: Array = []
			for code: int in g._near(g._seg_hash, p, 8.0, g.SEG_CELL):
				var r: Dictionary = g._roads[code / 4096]
				var pts: PackedVector2Array = r["pts"]
				var sj: int = code % 4096
				var d := Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1]).distance_to(p)
				if d < 8.0:
					seen.append("%d '%s' %s w %.1f %.1f m%s" % [code / 4096, r["name"], r["k"], r["w"], d, " deck" if r.has("ys") else ""])
			print("probe %s: street_at %s; %s" % [p, g._decks._street_at(p, -1), "; ".join(seen)])
	var routes := (OS.get_environment("ROUTES") if OS.get_environment("ROUTES") != "" else
		"476,-1185>498,-1158;476,-1185>416,-1094;416,-1094>476,-1185;495,-1156>476,-1185").split(";", false)
	var total := 0
	for i in range(routes.size()):
		var ends := routes[i].split(">")
		var from := _v2(ends[0])
		var to := _v2(ends[1])
		g._clear_dest()
		g._set_auto(false)
		g._land_on_road(from, 12.0, (at - from).normalized())
		g._v = 0.0
		await create_timer(0.5).timeout
		g._set_dest(to, "route %d" % i)
		var hits: Array = []
		var t := 0.0
		var was := 0.0
		while t < 40.0 and g._pos.distance_to(to) > 12.0:
			await physics_frame
			t += 1.0 / 60.0
			if g._crash_cool > was + 0.01:
				hits.append("%s at %s" % [g._last_hit, g._pos.round()])
			was = g._crash_cool
		total += hits.size()
		print("route %d %s > %s: %s in %.0f s, crashes %d %s" % [i, from, to, "arrived" if g._pos.distance_to(to) <= 12.0 else "not there (%.0f m off)" % g._pos.distance_to(to),
			t, hits.size(), ", ".join(hits)])
		if OS.get_environment("OUT") != "" and i == 0:
			await _snap("route_0_end")
	print("crashes on all routes: %d" % total)
	quit(0)
