extends SceneTree
## Autodrive on the main road past a side street: where does it slow or stand, and what holds it.
## A user: "the car weirdly stops in the middle of the run. yes there is a street but it's the
## main road" (Givatayim, Hafetz Haim at the short side street on its left).
## Lands on STREET (English name, default Hafetz Haim) at its start, the way it runs, and drives it
## with autodrive, a destination 250 m on along it; every quarter second within 40 m of a side
## street it prints the speed and what holds it (`_ap_why`, the car it gives way to, the points it
## gives way at). TRAFFIC=0 for no traffic; QUALITY (default 0; the game's own is 2) builds the street's
## furniture too; PASSES drives it that many times (traffic differs each time); DEST=x,y another
## destination.
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/side_street.gd
## PASS: never below 2 m/s for more than a second within 30 m of a side street, unless a car is
## in front or a red light is near (35 m). (It was the light 80 m on, at Nachalat Itzhak: a green
## ending that far off stopped the car at the side street -- see _ap_brake_for.)
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(int(OS.get_environment("QUALITY")) if OS.get_environment("QUALITY") != "" else 0)
	var street := OS.get_environment("STREET") if OS.get_environment("STREET") != "" else "Hafetz Haim"
	if OS.get_environment("TRAFFIC") == "0":
		for c in g._traffic.cars:
			c.alive = false
			c.retry = 1.0e9
	var ri := -1
	for i in range(g._roads.size()):
		var r: Dictionary = g._roads[i]
		if r["drive"] and String(r["en"]) == street and (r["pts"] as PackedVector2Array).size() >= 3:
			ri = i
			if int(r["o"]) != 0:
				break
	if ri < 0:
		print("no street '%s'" % street)
		quit(1)
		return
	var r: Dictionary = g._roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	if int(r["o"]) < 0:
		pts.reverse()
		ids.reverse()
	# the side streets along it: its points where another drivable road meets it
	var sides: Array = []
	for k in range(1, ids.size() - 1):
		var n := ids[k]
		for e: Vector2i in g._node_roads[n]:
			if e.x != ri and g._roads[e.x]["drive"]:
				sides.append(n)
				print("side street at point %d (%s): '%s' %s, ways %d, lit %s" % [n, pts[k].round(), g._roads[e.x]["en"], g._roads[e.x]["k"], g._node_ways(n), g._sig_set.has(n)])
				break
	var d0 := (pts[1] - pts[0]).normalized()
	var far: Vector2 = pts[pts.size() - 1] + (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized() * 120.0
	if OS.get_environment("DEST") != "":
		var xy := OS.get_environment("DEST").split(",")
		far = Vector2(float(xy[0]), float(xy[1]))
	var passes := int(OS.get_environment("PASSES")) if OS.get_environment("PASSES") != "" else 1
	var worst := 0.0
	var worst_why := ""
	for pass_i in range(passes):
		var res: Array = await _pass(pts, d0, far, sides)
		if res.is_empty():
			print("could not land")
			continue
		print("pass %d: longest under 2 m/s by a side street %.1f s ('%s')" % [pass_i, res[0], res[1]])
		if float(res[0]) > worst:
			worst = res[0]
			worst_why = res[1]
	print("SIDE STREET: %s (longest under 2 m/s by a side street %.1f s, '%s', in %d passes)" % ["PASS" if worst <= 1.0 else "FAIL", worst, worst_why, passes])
	quit(0)

## one drive from the street's start: [the longest time under 2 m/s by a side street, its why]
func _pass(pts: PackedVector2Array, d0: Vector2, far: Vector2, sides: Array) -> Array:
	g._set_auto(false)
	if not g._land_on_road(pts[0] + d0 * 6.0, 6.0, d0):
		return []
	g._v = 0.0
	await physics_frame
	g._set_dest(far, "side street test")
	g._set_auto(true)
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var slow := 0.0
	var worst := 0.0
	var worst_why := ""
	var tick := 0
	var last_side := pts[0]
	for n: int in sides:
		last_side = g._nodes[n]
	while t < 60.0:
		await physics_frame
		t += dt
		tick += 1
		var near := INF
		var at := -1
		for n: int in sides:
			var dd: float = (g._nodes[n] as Vector2).distance_to(g._pos)
			if dd < near:
				near = dd
				at = n
		if near < 40.0 and tick % 15 == 0 and (OS.get_environment("VERBOSE") != "" or g._v < 2.0):
			var give := ""
			if g._ap_give_car >= 0 and g._ap_give_car < g._traffic.cars.size():
				var c = g._traffic.cars[g._ap_give_car]
				give = ", giving way to a %s %.0f m off at %.1f m/s" % [c.kind, c.pos.distance_to(g._pos), c.v]
			print("  t %.2f: %.1f m from %d, %.1f m/s, why '%s'%s, gives way at %d points, mid %s, lead %.1f, last hit '%s'" % [t, near, at, g._v, g._ap_why, give, g._ap_giving.size(), g._ap_mid, g._ap_lead, g._last_hit])
		var lit_near := false
		for n: int in g._sig_set:
			if (g._nodes[n] as Vector2).distance_to(g._pos) < 35.0:
				lit_near = true
		if near < 30.0 and g._v < 2.0 and g._ap_why != "car" and not (g._ap_why == "light" and lit_near):
			slow += dt
			if slow > worst:
				worst = slow
				worst_why = g._ap_why
		else:
			slow = 0.0
		if g._pos.distance_to(far) < 20.0 or ((g._pos - last_side).dot(d0) > 40.0 and g._pos.distance_to(last_side) > 40.0):
			break
	return [worst, worst_why]
