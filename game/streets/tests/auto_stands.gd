extends SceneTree
## Autodrive standing still: every stop of WAIT seconds or more (default 4; not at a red
## light), what the game says holds it (`_ap_why`) and what is really ahead -- the car it
## follows (how far, its kind and speed, how long it has stood, what holds IT, a delivery
## standing in the street, how far its middle is off my lane), the car it gives way to, the
## sign, the nearest person on the lane, and how far the lane ahead is free of any car.
## A user: "after some standing behind cars, the autodrive just stops and waits for a while
## while there is a big distance ahead it can drive" (Tel Aviv, Shenkin, traffic about).
## Starts on STREET (its English name, default Shenkin) the way it runs, then on RUNS-1 more
## streets near it (default 3 in all), SECS each (default 120).
##   LEVEL=7 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/auto_stands.gd
var g: Node

func _initialize() -> void:
	_run()

## the distance along the plan to the first traffic car whose body is within 2.5 m of it
func _free_ahead(reach: float) -> float:
	var pts: PackedVector2Array = g._ap_pts
	if pts.size() < 2:
		return -1.0
	var best := reach
	for c in g._traffic.cars:
		if not c.alive or c.pos.distance_to(g._pos) > reach + 10.0:
			continue
		var base := -pts[0].distance_to(Geometry2D.get_closest_point_to_segment(g._pos, pts[0], pts[1]))
		for j in range(pts.size() - 1):
			if base > best:
				break
			var cp := Geometry2D.get_closest_point_to_segment(c.pos, pts[j], pts[j + 1])
			if cp.distance_to(c.pos) < 2.5:
				var along: float = base + pts[j].distance_to(cp) - float(c.len) * 0.5
				if along > 0.0:
					best = minf(best, along)
				break
			base += pts[j].distance_to(pts[j + 1])
	return best

func _lat(p: Vector2) -> float:
	var pts: PackedVector2Array = g._ap_pts
	var d := INF
	for j in range(pts.size() - 1):
		d = minf(d, Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p))
		if pts[j].distance_to(g._pos) > 40.0:
			break
	return d

func _what() -> String:
	var parts: Array = ["why '%s'" % g._ap_why]
	var lead: Array = g._traffic.lead_on(g._ap_pts, g._pos, 30.0, g._ap_wait > 3.0, g._y)
	if float(lead[0]) < 30.0 and int(lead[3]) >= 0:
		var c = g._traffic.cars[int(lead[3])]
		parts.append("lead %s %.1f m on, v %.1f, still %.0f s, its why '%s', blocker %d, delivery %s, its middle %.1f m off my lane" % [
			c.kind, float(lead[0]), c.v, c.still, c.why, c.blocker, g._traffic._parked_double(c), _lat(c.pos)])
	if g._ap_give_car >= 0 and g._ap_give_car < g._traffic.cars.size():
		var c = g._traffic.cars[g._ap_give_car]
		parts.append("giving way to %s %.0f m off at %.1f m/s" % [c.kind, c.pos.distance_to(g._pos), c.v])
	if not g._ap_giving.is_empty():
		parts.append("at a junction it gives way at (%d points)" % g._ap_giving.size())
	var pv: float = g._ap_people_v()
	if pv < 5.0:
		parts.append("people hold %.1f m/s" % pv)
	var zv: float = g._ap_zebra_v()
	if zv < 5.0:
		parts.append("zebra hold %.1f m/s" % zv)
	if g._ap_light_v() < 5.0:
		parts.append("light hold")
	parts.append("free ahead %.0f m" % _free_ahead(60.0))
	if g._ap_back > 0.0 or g._ap_turn > 0.0:
		parts.append("backing/turning")
	if not g._cross.is_empty():
		parts.append("choosing a way")
	return ", ".join(parts)

func _drive(label: String, secs: float, wait: float) -> Array:
	g._set_auto(true)
	var t := 0.0
	var still := 0.0
	var told := 0
	var stops := 0
	var stood := 0.0
	var longest := 0.0
	var step := Engine.time_scale / Engine.physics_ticks_per_second
	while t < secs:
		await physics_frame
		t += step
		if absf(g._v) < 0.3 and g._ap_light_v() > 0.5:
			still += step
			if still >= wait and int(still) > told and (told < int(wait) or int(still) % 5 == 0):
				if told < int(wait):
					stops += 1
				told = int(still)
				print("  %s t %.0f s: stood %d s at %s on '%s': %s" % [label, t, told, g._pos.round(), g._on_name, _what()])
		else:
			if still >= wait:
				stood += still
				longest = maxf(longest, still)
			still = 0.0
			told = 0
	if still >= wait:
		stood += still
		longest = maxf(longest, still)
	print("%s: %d stops of %.0f s or more (not at lights), %.0f s in all, the longest %.0f s; drove %.0f m" % [label, stops, wait, stood, longest, g._odo])
	return [stops, stood]

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var street := OS.get_environment("STREET") if OS.get_environment("STREET") != "" else "Shenkin"
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 3
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 120.0
	var wait := float(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 4.0
	var starts: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if r["drive"] and String(r["en"]) == street and (r["pts"] as PackedVector2Array).size() >= 2:
			starts.append(ri)
			break
	if starts.is_empty():
		print("no street '%s'" % street)
		quit(1)
		return
	var here: Vector2 = (g._roads[starts[0]]["pts"] as PackedVector2Array)[0]
	var near: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if r["drive"] and not r["pv"] and r["k"] in ["residential", "tertiary", "secondary", "unclassified"] \
				and (r["pts"] as PackedVector2Array).size() >= 2 and (r["pts"] as PackedVector2Array)[0].distance_to(here) < 600.0 \
				and (r["pts"] as PackedVector2Array)[0].distance_to((r["pts"] as PackedVector2Array)[1]) > 15.0:
			near.append(ri)
	seed(7)
	near.shuffle()
	starts.append_array(near.slice(0, runs - 1))
	var all_stops := 0
	var all_s := 0.0
	for i in range(starts.size()):
		var r: Dictionary = g._roads[starts[i]]
		var pts: PackedVector2Array = r["pts"]
		var dir := 1 if int(r["o"]) >= 0 else -1
		var a: Vector2 = pts[0] if dir > 0 else pts[pts.size() - 1]
		var b: Vector2 = pts[1] if dir > 0 else pts[pts.size() - 2]
		var d := (b - a).normalized()
		g._set_auto(false)
		g._pos = a + d * 6.0 + Vector2(-d.y, d.x) * float(g._lane_off(r))
		g._yaw = d.angle()
		g._v = 0.0
		g._snap_pose()
		await physics_frame
		var res: Array = await _drive("%s_%d" % [String(r["en"]).replace(" ", ""), i], secs, wait)
		all_stops += int(res[0])
		all_s += float(res[1])
	print("in all: %d stops of %.0f s or more (not at lights), %.0f s standing" % [all_stops, wait, all_s])
	quit(0)
