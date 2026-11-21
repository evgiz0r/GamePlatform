extends SceneTree
## Where autodrive (and the cars round it) stop for a traffic light, against where the light
## is: a user (Ashdod, Sderot Menachem Begin by HaMishna, cars standing short of the light
## pole and the bus stop): "why are the cars stopping there". Puts the car down at each of
## CAR="x,z,dx,dz;..." with autodrive on and the traffic about, for SECS (default 45). Every
## stop of 2 s or more: what holds it (`_ap_why`), the lit point it waits for -- how far
## its nose is from that point and from its stop line (`_sig_line`), the point's junction
## radius, what roads meet there -- the light's colour, and the traffic cars standing
## within 40 m and what holds each; a shot from the chase camera (stop_<i>_<n>.png).
## DEST="x,z" drives there (as "go to" does), else wherever autodrive picks.
##   CAR="40,3665,0.87,0.5" RES=1280x720 tests/run.sh light_line 3
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

## the lit points within 70 m ahead along the plan: [along the plan to the point, node]
func _lights_ahead() -> Array:
	var out: Array = []
	var pts: PackedVector2Array = g._ap_pts
	if pts.size() < 2:
		return out
	for n: int in g._near(g._sig_hash, g._pos, 80.0, g.SEG_CELL):
		var c: Vector2 = g._nodes[n]
		var base := -pts[0].distance_to(Geometry2D.get_closest_point_to_segment(g._pos, pts[0], pts[1]))
		for j in range(pts.size() - 1):
			if base > 70.0:
				break
			var cp := Geometry2D.get_closest_point_to_segment(c, pts[j], pts[j + 1])
			if cp.distance_to(c) < float(g._node_r[n]) + 2.0:
				if base + pts[j].distance_to(cp) > -3.0:
					out.append([base + pts[j].distance_to(cp), n, (pts[j + 1] - pts[j]).normalized()])
				break
			base += pts[j].distance_to(pts[j + 1])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out

func _roads_at(n: int) -> String:
	var names: Array = []
	for e: Vector2i in g._node_roads[n]:
		var r: Dictionary = g._roads[e.x]
		var s := "%s (%s)" % [String(r.get("en", "")) if String(r.get("en", "")) != "" else String(r["name"]), r["k"]]
		if not names.has(s):
			names.append(s)
	return ", ".join(names)

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
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 45.0
	var cars := OS.get_environment("CAR").split(";", false)
	var step := Engine.time_scale / Engine.physics_ticks_per_second
	for ci in range(cars.size()):
		var v := cars[ci].split(",")
		g._set_auto(false)
		g._pos = Vector2(float(v[0]), float(v[1]))
		g._yaw = Vector2(float(v[2]), float(v[3])).angle()
		g._v = 0.0
		g._snap_pose()
		await physics_frame
		if OS.get_environment("DEST") != "":
			var dz := OS.get_environment("DEST").split(",")
			g._set_dest(Vector2(float(dz[0]), float(dz[1])), "test")
		g._set_auto(true)
		print("== start %d at %s on '%s'" % [ci, g._pos.round(), g._on_name])
		var t := 0.0
		var still := 0.0
		var shots := 0
		while t < secs:
			await physics_frame
			t += step
			if absf(g._v) >= 0.3:
				still = 0.0
				continue
			still += step
			if still < 2.0 or still - step >= 2.0:
				continue
			var line := "  t %.0f s stood at %s on '%s', why '%s'" % [t, g._pos.round(), g._on_name, g._ap_why]
			for la: Array in _lights_ahead().slice(0, 2):
				var n: int = la[1]
				var stop: float = g._light_line(n, la[2])
				var raw := String(g.SIGNAL_CYCLE[g._sig_phase][g._light_group(n, la[2])])
				line += "\n    light at %s %.1f m ahead of the car's middle (nose %.1f), its stop line %.1f m before it -> nose %.1f m short of the line; junction radius %.1f; shows '%s'; roads: %s" % [
					(g._nodes[n] as Vector2).round(), float(la[0]), float(la[0]) - g.CAR_LEN * 0.5, stop,
					float(la[0]) - g.CAR_LEN * 0.5 - stop, float(g._node_r[n]), raw, _roads_at(n)]
				if OS.get_environment("WAYS") != "":   # (its ways in, and whether it counts as a slip road's light)
					line += "\n      slip road's: %s; ways in: %s" % [g._slip_join(n), (g._sig_line.get(n, []) as Array).map(
						func(w): return "%s from road %d (%s) line %.1f inside %s" % [(w[0] as Vector2).snapped(Vector2(0.01, 0.01)), int(w[2]), g._roads[int(w[2])]["k"], float(w[1]), w[3]])]
			for c in g._traffic.cars:
				if c.alive and c.pos.distance_to(g._pos) < 40.0 and c.v < 0.3:
					line += "\n    a %s standing %.0f m off, its why '%s'" % [c.kind, c.pos.distance_to(g._pos), c.why]
			print(line)
			if shots < 3:
				await _snap("stop_%d_%d" % [ci, shots])
				shots += 1
		print("  drove %.0f m in %.0f s" % [g._odo, secs])
	quit(0)
