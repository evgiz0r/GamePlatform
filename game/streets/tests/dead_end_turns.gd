extends SceneTree
## How autodrive turns round at a dead end. Every cul-de-sac's end in the city (up to N=,
## default 12, picked at random past that), the car set down on autodrive up to 60 m short of
## it, heading in. For each: what it hit and how fast, how it turned round (moves forward and
## back, seconds, or the rest on the spot), how near the end its nose got, how far off the
## asphalt it went while turning, and whether it was driving back out within 60 s.
## (tests/dead_ends.gd: trips that start at a dead end, and whether it gets out at all.)
##
## It once drove at the end, found only the way back offered, and tried to swing round in one
## go -- a turn twice as wide as a 6.5 m street -- into a tree or garden wall beside the road
## at ~20-30 km/h (the test town's HaTzabar, 2026-11). Good now: no hits, a three-point turn
## in a 6.5 m street (five or seven moves in narrower ones), ~0 m past the asphalt's edge.
##
## ONLY=<part of a street's name> for just that one, VERBOSE=1 for the car's state twice a second.
## Runs headless too, without screenshots (faster):
##   STREETS_BUILD_ALL=1 LEVEL=4 $GODOT --headless --path . -s res://game/streets/tests/dead_end_turns.gd
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

## the way in to dead end `node` (its one road), walked back from the end: [points from the
## end inward, the road's name], or [] when it is not one autodrive would drive into
func _way_in(node: int) -> Array:
	var es: Array = []
	for e: Vector2i in g._node_roads[node]:
		if (g._roads[e.x] as Dictionary)["drive"]:
			es.append(e)
	if es.size() != 1:
		return []
	var e: Vector2i = es[0]
	var r: Dictionary = g._roads[e.x]
	if r["pv"] or int(r["o"]) != 0 or r["k"] == "service":
		return []
	var out := PackedVector2Array()
	var ri := e.x
	var i := e.y
	var dir := 1 if i == 0 else -1
	var L := 0.0
	var seen := {}
	out.append((r["pts"] as PackedVector2Array)[i])
	while L < 60.0:
		var rr: Dictionary = g._roads[ri]
		var pts: PackedVector2Array = rr["pts"]
		var j := i + dir
		if j < 0 or j >= pts.size():
			# the road's other end: on along the next piece of the same street (two ways at
			# the node), else a junction -- stop short of it
			var n: int = (rr["ids"] as PackedInt32Array)[i]
			if g._node_ways(n) != 2 or seen.has(n):
				break
			seen[n] = true
			var nxt := Vector2i(-1, 0)
			for e2: Vector2i in g._node_roads[n]:
				if e2.x != ri and (g._roads[e2.x] as Dictionary)["drive"]:
					nxt = e2
			if nxt.x < 0:
				break
			ri = nxt.x
			i = nxt.y
			dir = 1 if i == 0 else -1
			continue
		L += pts[i].distance_to(pts[j])
		out.append(pts[j])
		i = j
		var nj: int = (rr["ids"] as PackedInt32Array)[j]
		if g._node_ways(nj) >= 3:
			break
	return [out, String(r["en"]) if String(r["en"]) != "" else String(r["name"])]

## the point s metres in from the end along the way in, and the direction toward the end there
func _along(way: PackedVector2Array, s: float) -> Array:
	var left := s
	for k in range(1, way.size()):
		var L := way[k - 1].distance_to(way[k])
		if L >= left:
			return [way[k - 1].lerp(way[k], left / maxf(L, 0.001)), (way[k - 1] - way[k]).normalized()]
		left -= L
	return [way[way.size() - 1], (way[way.size() - 2] - way[way.size() - 1]).normalized()]

func _len(way: PackedVector2Array) -> float:
	var L := 0.0
	for k in range(1, way.size()):
		L += way[k - 1].distance_to(way[k])
	return L

func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "" and DisplayServer.get_name() != "headless":
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	var probe = root.get_node("Probe")
	probe.enabled = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + lvl
	var ends: Array = []
	for n in range(g._nodes.size()):
		if g._node_ways(n) != 1:
			continue
		var w := _way_in(n)
		if w.is_empty():
			continue
		var way: PackedVector2Array = w[0]
		if _len(way) < 20.0:
			continue   # (a stub off a junction: nowhere to come in from)
		var end: Vector2 = way[0]
		if not g._bounds.grow(-25.0).has_point(end):
			continue   # (cut off by the map's edge: the barrier, another matter)
		if OS.get_environment("ONLY") != "" and not String(w[1]).containsn(OS.get_environment("ONLY")):
			continue
		ends.append([n, w])
	var want := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 12
	while ends.size() > want:
		ends.remove_at(rng.randi() % ends.size())
	print("dead ends: %d" % ends.size())
	var bad := 0
	var outs := 0
	var times: Array = []
	var moves_all: Array = []
	for di in range(ends.size()):
		var way: PackedVector2Array = ends[di][1][0]
		var street: String = ends[di][1][1]
		var end: Vector2 = way[0]
		var run_in := minf(60.0, _len(way) - 4.0)
		var a: Array = _along(way, run_in)
		g._set_auto(false)
		if not g._land_on_road(a[0], 8.0, a[1]):
			print("  %s: could not set the car down" % street)
			continue
		if g._fwd().dot(a[1]) < 0.5:
			print("  %s: set down facing the wrong way, skipped" % street)
			continue
		probe._events.clear()
		await physics_frame
		g._set_auto(true)
		var t := 0.0
		var vmax_near := 0.0
		var nose_gap := INF
		var off_max := -INF
		var moves := 0
		var turned_t := -1.0
		var out_t := -1.0
		var turn_at := Vector2.INF
		var shot := false
		while t < 60.0:
			await physics_frame
			t += 1.0 / 60.0
			var fwd: Vector2 = g._fwd()
			var to_end: Vector2 = (end - g._pos)
			var toward: Vector2 = a[1]
			if to_end.length() < 25.0:
				vmax_near = maxf(vmax_near, absf(g._v))
			nose_gap = minf(nose_gap, (end - (g._pos + fwd * g.CAR_LEN * 0.5)).dot(toward))
			if OS.get_environment("VERBOSE") != "" and int(t * 60.0) % 30 == 0:
				print("    t %.1f: %.1f m to the end, v %.1f, gear %d, heading %.2f, why %s, stop %s, turning %s, plan %d, slope %.2f, steer %.2f, touching %s" % [t,
					to_end.dot(toward), g._v, g._gear, fwd.dot(toward), g._ap_why, str(g._ap_dead), str(g._ap_kt.get("n", "-")), g._ap_pts.size(),
					g._slope, g._steer, g._last_hit if g._touch_t > 0.0 else "-"])
			if to_end.length() < 30.0 and fwd.dot(toward) < 0.9:
				for off: float in [g.CAR_OFF, -g.CAR_OFF]:
					var on: Dictionary = g._nearest_seg(g._pos + fwd * off, 20.0, true, false)
					if not on.is_empty():
						off_max = maxf(off_max, float(on["edge"]) + g.CAR_R)
				if not shot and absf(fwd.dot(toward)) < 0.3 and di < 4:
					shot = true
					await _snap("dead_end_turn_%d_%d" % [lvl, di])
			if turned_t < 0.0 and fwd.dot(toward) < -0.8:
				turned_t = t
				turn_at = g._pos
			if turned_t >= 0.0 and g._v > 2.0 and g._pos.distance_to(turn_at) > 20.0:
				out_t = t
				break
		var crashes: Array = []
		var trouble: Array = []
		var turn := ""
		for e: Dictionary in probe._events:
			if e["kind"] == "turned_round":
				turn = ", turned round in %d moves%s, %.1f s" % [e["data"]["moves"], " and the rest ON THE SPOT" if e["data"]["on_the_spot"] else "", e["data"]["secs"]]
				moves = int(e["data"]["moves"])
			elif e["kind"] == "crash":
				crashes.append("%s at %d km/h" % [e["data"]["hit"], e["data"]["kmh"]])
			elif e["kind"] in ["autodrive_stuck", "autodrive_rescue", "autodrive_unstuck"]:
				trouble.append(e["kind"])
		if not crashes.is_empty() or out_t < 0.0:
			bad += 1
		if out_t >= 0.0:
			outs += 1
			times.append(snappedf(out_t, 0.1))
			moves_all.append(moves)
		print("  %s (%.0f, %.0f), in from %.0f m: %s; %s; nose %.1f m short of the end, top %.0f km/h in the last 25 m, %.1f m past the asphalt's edge turning%s%s" % [
			street, end.x, end.y, run_in,
			("out again in %.1f s (turned by %.1f s)" % [out_t, turned_t]) if out_t >= 0.0 else ("NOT out in 60 s" + (" (turned by %.1f s)" % turned_t if turned_t >= 0.0 else ", never turned")),
			("hit " + ", ".join(crashes)) if not crashes.is_empty() else "no hits",
			nose_gap, vmax_near * 3.6, off_max, turn, (", " + ", ".join(trouble)) if not trouble.is_empty() else ""])
	print("dead ends: %d of %d out again, %d with a hit or not out; times %s; moves %s" % [outs, ends.size(), bad, str(times), str(moves_all)])
	quit(0)
