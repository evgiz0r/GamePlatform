extends SceneTree
## A traffic car meeting your standing car: does it stop, or shove it? (Route 7, 21 Nov 2026:
## a traffic SUV at 2 m/s pushed autodrive, standing in a junction's tangle, 8 m sideways into
## posts; the test town's exam once had "traffic shoves your standing car" 3 a run.) Your car
## stands on the start's street, in its lane and then over towards the middle by 0.8 and 1.6 m
## (part of it in the next lane, as a car half turned in a junction stands), and askew by 35
## degrees; each time a traffic car is sent along the lane from 35 m behind. Prints how far
## your car was moved (it is held at 0 km/h: only the traffic can move it), the nearest the
## two bodies came, and what the traffic car did.
##   LEVEL=4 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/traffic_shove.gd
## Good: moved 0.0 m every time.
var g: Node
var T

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	g._set_auto(false)
	T = g._traffic
	var start: Vector2 = g._pos
	var hit: Dictionary = g._nearest_seg(start, 20.0, true, true)
	var r: Dictionary = g._roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var d: Vector2 = (pts[int(hit["seg"]) + 1] - pts[int(hit["seg"])]).normalized()
	if int(r["o"]) < 0:
		d = -d
	var right := Vector2(-d.y, d.x)
	var mid: Vector2 = hit["q"]
	var lane: float = g._lane_off(r)
	var worst := 0.0
	var cases := 0
	for spec: Array in [[0.0, 0.0], [0.8, 0.0], [1.6, 0.0], [0.8, 35.0], [1.6, -35.0]]:
		cases += 1
		# everyone else out of the way
		for c in T.cars:
			c.alive = false
		var at: Vector2 = mid + right * (lane - float(spec[0]))
		var yaw := d.rotated(deg_to_rad(float(spec[1]))).angle()
		g._pos = at
		g._yaw = yaw
		g._v = 0.0
		g._v_lat = 0.0
		for k in range(20):
			await physics_frame
			g._pos = at
			g._yaw = yaw
			g._v = 0.0
		T.send(at - d * 35.0, d)
		var near := INF
		var t := 0.0
		var sent = null
		for c in T.cars:
			if c.alive:
				sent = c
		while t < 20.0:
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			g._v = 0.0
			g._v_lat = 0.0
			if sent != null and sent.alive:
				near = minf(near, (sent.pos as Vector2).distance_to(g._pos))
		var moved: float = (g._pos as Vector2).distance_to(at)
		worst = maxf(worst, moved)
		var what := "gone"
		if sent != null and sent.alive:
			var past: float = ((sent.pos as Vector2) - at).dot(d)
			what = "%s, %.1f m %s, %.1f km/h, held by %s" % [sent.kind, absf(past), "past" if past > 0.0 else "behind", sent.v * 3.6, sent.why]
		print("SHOVE case %d: your car %.1f m over from its lane, askew %.0f deg -- moved %.2f m; the traffic car came within %.1f m (middles); now %s" % [
			cases, float(spec[0]), float(spec[1]), moved, near, what])
	print("TRAFFIC SHOVE: %d cases, your standing car moved %.2f m at most (good 0)" % [cases, worst])
	quit(0)
