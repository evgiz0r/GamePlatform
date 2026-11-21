extends SceneTree
## Bus lanes (OSM's bus:lanes and kin, baked as bf / bb) in Tel Aviv (level 7): which road
## pieces have one, how many words were painted; where autodrive's lane line lies on each
## (never in the bus lane); then the car parked off Kaplan by its westbound bus lane while
## the traffic runs for SECS (default 90): seconds each kind spent in a bus lane, and the
## times a car that may not use one was in it other than before a right turn. Views of
## Kaplan's bus lane (shots).
##
##   OUT=/tmp/bus game/streets/tests/run.sh bus_lanes 7     the lists and the shots (no traffic
##       count: drawn, its 90 s took 20 minutes; SECS=90 to have it anyway)
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s \
##       res://game/streets/tests/bus_lanes.gd     the lists and the traffic count, ~4 min
##
## Good: Kaplan's westbound pieces and the Ayalon's listed, words painted, autodrive's lane
## on each not a bus lane; buses most of their time in the bus lane, 0 seconds of cars that
## may not use it in it but for right turns; in the shots the solid line and the word.
var g: Node
var T

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _view(name: String, p: Vector2, at: Vector2, up: float, tilt: float) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = tilt
	var yaw := (at - p).angle()
	for i in 10:
		g._pos = p
		g._prev_pos = p
		g._yaw = yaw
		g._prev_yaw = yaw
		g._v = 0.0
		await process_frame
	await _snap(name)

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.6,0,0")
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	T = g._traffic
	var n_bus := 0
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or not g._has_bus_lane(r):
			continue
		n_bus += 1
		var pts: PackedVector2Array = r["pts"]
		var n: int = g._lanes_each_way(r)
		var way := 1 if int(r["o"]) >= 0 else -1
		# autodrive's line: which lane of the n it is in
		var off: float = g._lane_off(r)
		var span: float = float(r["w"]) if int(r["o"]) != 0 else float(r["w"]) * 0.5
		var ap_i := clampi(int(floor((float(r["w"]) * 0.5 - off) / (span / n))), 0, n - 1)
		print("%s (%s, %d lanes a way) %s -> %s: bf '%s' bb '%s'; autodrive in lane %d%s" % [r["en"] if r["en"] != "" else r["name"],
			r["k"], n, Vector2i(pts[0]), Vector2i(pts[pts.size() - 1]), r["bf"], r["bb"], ap_i,
			" -- a BUS LANE" if g._bus_lane(r, ap_i, way) else ""])
	print("road pieces with a bus lane: %d; words painted: %d" % [n_bus, g._bus_words])
	if g._city_id != "tel_aviv":
		quit()
		return
	if DisplayServer.get_name() != "headless":
		g._car.visible = false
		await _view("kaplan_bus_lane", Vector2(-290, 160), Vector2(-420, 154), 1.6, -4.0)
		await _view("kaplan_bus_lane_above", Vector2(-300, 175), Vector2(-380, 152), 14.0, -28.0)
		for wa: Array in g._bus_word_at:   # a painted word, from behind it as a driver reads it
			var wp: Vector2 = wa[0]
			if wp.distance_to(Vector2(-400, 152)) < 200.0:
				var wd: Vector2 = wa[1]
				await _view("bus_word", wp - wd * 14.0, wp, 4.0, -14.0)
				break
		g._car.visible = true
		if OS.get_environment("SECS") == "":
			quit()
			return
	# the traffic beside Kaplan's westbound bus lane
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	g._set_auto(false)
	var spot := Vector2(-400, 140)
	if OS.get_environment("AT") != "":   # (another town's bus lane: AT=x,z beside it)
		var at := OS.get_environment("AT").split(",")
		spot = Vector2(float(at[0]), float(at[1]))
	for k in range(30):   # a spot off the asphalt by it
		var p := spot + Vector2(0, -2.0 * k)
		var on: Dictionary = g._nearest_seg(p, 30.0, true)
		if (on.is_empty() or float(on["edge"]) > 3.0) and g._push_out(p, 2.5, true, true, g._h(p)) == Vector2.ZERO:
			spot = p
			break
	g._pos = spot
	g._prev_pos = spot
	g._v = 0.0
	g._snap_pose()
	var in_bus := {}       # kind -> seconds in a bus lane
	var on_bus_road := {}  # kind -> seconds on a road piece with one, that way
	var wrong := 0.0
	var wrong_at: Array = []
	var dt := 1.0 / 60.0
	var t := 0.0
	while t < secs:
		await physics_frame
		t += dt
		for c in T.cars:
			if not c.alive or c.rd.is_empty():
				continue
			var r: Dictionary = g._roads[c.rd[clampi(c.k, 0, c.rd.size() - 1)]]
			if not g._has_bus_lane(r):
				continue
			var way: int = T._way_on(c, r)
			var any := false
			for idx in range(g._lanes_each_way(r)):
				any = any or g._bus_lane(r, idx, way)
			if not any:
				continue
			on_bus_road[c.kind] = float(on_bus_road.get(c.kind, 0.0)) + dt
			if absf(c.shift - c.shift_to) < 0.3 and g._bus_lane(r, c.lane_i, way):
				in_bus[c.kind] = float(in_bus.get(c.kind, 0.0)) + dt
				var turn: Array = T._turn_ahead(c)
				if not c.bus_ok and not (int(turn[0]) > 0 and float(turn[1]) < T.BUS_TURN_IN + 20.0):
					wrong += dt
					if wrong_at.size() < 6 and (wrong_at.is_empty() or (wrong_at[-1] as Vector2).distance_to(c.pos) > 30.0):
						wrong_at.append(c.pos)
	print("over %.0f s, seconds on a road with a bus lane (that way) / in the bus lane, by kind:" % secs)
	for kind: String in on_bus_road:
		print("  %-6s %6.1f / %6.1f" % [kind, float(on_bus_road[kind]), float(in_bus.get(kind, 0.0))])
	print("cars that may not use it, in it but for a right turn: %.1f s%s" % [wrong, (" at %s" % [wrong_at.map(func(p): return Vector2i(p))]) if wrong > 0.0 else ""])
	quit()
