extends SceneTree
## A hill is not a level: traffic must see the player up or down a slope. On the steepest
## approaches to junctions with no lights (60 m back at least 3.5 m higher or lower than the
## junction), one car is sent at the player, the rest of traffic kept off:
##   "in it": the player standing in the middle of the junction;
##   "queued": the player standing in the same lane 15 m short of the junction (a queue).
## Per case: how far off the car first slowed for the player (or for the junction while the
## player was in it), how hard it braked doing so (over half a second), how close it came,
## and whether it hit.
## Traffic told levels apart by height alone (2.5 m): a car 40-60 m off on a 6-8% street was
## that much higher or lower, and took the player for something on a bridge or under one.
##   LEVEL=7 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/hill_level.gd
## HL_N approaches (default 5). Keeps away from the places tests/pick_routes.py keeps away from.
## PASS: no hit, no car within 5 m of the player (middle to middle) but one going round it a
## lane over, no braking over 5 m/s^2. (The player is held where it stands: nobody at its pedals.)
var g: Node
var T

func _initialize() -> void:
	_run()

## the point `dist` metres along road ri from its point k walking `dir`, and that way; on along
## the straightest road where it ends ([] when the streets run out)
func _along(ri: int, k: int, dir: int, dist: float) -> Array:
	var left := dist
	var i := k
	for guard in range(40):
		var pts: PackedVector2Array = g._roads[ri]["pts"]
		while i + dir >= 0 and i + dir < pts.size():
			var seg := pts[i].distance_to(pts[i + dir])
			if seg >= left:
				var d := (pts[i + dir] - pts[i]).normalized()
				return [pts[i] + d * left, d]
			left -= seg
			i += dir
		var n: int = (g._roads[ri]["ids"] as PackedInt32Array)[i]
		var came := (pts[i] - pts[i - dir]).normalized()
		var best := -0.7
		var nxt := Vector3i(-1, 0, 0)
		for e: Vector2i in g._node_roads[n]:
			if e.x == ri or not g._roads[e.x]["drive"]:
				continue
			var q: PackedVector2Array = g._roads[e.x]["pts"]
			for dd: int in [1, -1]:
				if e.y + dd >= 0 and e.y + dd < q.size() and came.dot((q[e.y + dd] - q[e.y]).normalized()) > best:
					best = came.dot((q[e.y + dd] - q[e.y]).normalized())
					nxt = Vector3i(e.x, e.y, dd)
		if nxt.x < 0:
			return []
		ri = nxt.x
		i = nxt.y
		dir = nxt.z
	return []

func _pick(want: int) -> Array:
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var cand: Array = []
	for n in range(g._nodes.size()):
		if g._sig_set.has(n) or g._node_ways(n) < 3 or not g._in_city(g._nodes[n]) or priv.near(avoid, g._nodes[n]):
			continue
		for e: Vector2i in g._node_roads[n]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"] or r["pv"] or r.has("ys") or r.get("ring", false) or r["k"] == "service":
				continue
			var last := (r["pts"] as PackedVector2Array).size() - 1
			for wd: int in [1, -1]:
				if (e.y == 0 and wd < 0) or (e.y == last and wd > 0):
					continue
				if int(r["o"]) != 0 and int(r["o"]) != -wd:
					continue   # (one way, away from the junction)
				var b60 := _along(e.x, e.y, wd, 60.0)
				var b75 := _along(e.x, e.y, wd, 75.0)
				var b15 := _along(e.x, e.y, wd, 15.0)
				if b75.is_empty() or (b75[0] as Vector2).distance_to(g._nodes[n]) < 68.0:
					continue   # (short, or bent)
				var dh: float = g._h(b60[0]) - g._h(g._nodes[n])
				if absf(dh) >= 3.5:
					cand.append({"n": n, "road": e.x, "dh": dh, "b15": b15, "b75": b75})
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a["dh"]) > absf(b["dh"]))
	var out: Array = []
	for c: Dictionary in cand:
		var crowded := false
		for o: Dictionary in out:
			if (g._nodes[o["n"]] as Vector2).distance_to(g._nodes[c["n"]]) < 150.0:
				crowded = true
		if not crowded:
			out.append(c)
			if out.size() >= want:
				break
	return out

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	T = g._traffic
	var picks := _pick(int(OS.get_environment("HL_N")) if OS.get_environment("HL_N") != "" else 5)
	print("hill level: %d steep approaches in %s" % [picks.size(), g._city_id])
	var bad := 0
	var runs := 0
	for p: Dictionary in picks:
		for how: String in ["in it", "queued"]:
			var res := await _case(p, how)
			if res.is_empty():
				continue
			runs += 1
			if not res["ok"]:
				bad += 1
			print("HILL LEVEL %s" % JSON.stringify(res))
	print("HILL LEVEL: %s (%d of %d bad)" % ["PASS" if bad == 0 and runs > 0 else "FAIL", bad, runs])
	quit(0)

func _case(p: Dictionary, how: String) -> Dictionary:
	var n: int = p["n"]
	var node: Vector2 = g._nodes[n]
	var b15: Array = p["b15"]
	var b75: Array = p["b75"]
	for c in T.cars:
		c.alive = false
		c.retry = 1000.0
	g._set_auto(false)
	var into := -(b15[1] as Vector2)   # the way the car comes into the junction
	var ok_land: bool
	if how == "in it":
		ok_land = g._land_on_road(node, 8.0, Vector2(-into.y, into.x))   # (across its way, in the middle)
	else:
		ok_land = g._land_on_road(b15[0], 6.0, into)
	if not ok_land:
		return {}
	g._v = 0.0
	var me0: Vector2 = g._pos
	for k in range(30):
		await physics_frame
		g._pos = me0   # (held where it stands: with nobody at the pedals it rolls down a 15% street)
		g._v = 0.0
	if not T.send(b75[0], -(b75[1] as Vector2)):
		return {}
	var sent = null
	for c in T.cars:
		if c.alive:
			sent = c
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var seen_at := -1.0
	var brake := 0.0
	var side := 0.0
	var vs: Array = []   # (its speed, the last half second: braking is read over that -- traffic
	                     # follows its plan in steps at up to 7.5 m/s^2, a tick at a time)
	var closest := INF
	var hits := 0
	var last_hit: String = g._last_hit
	var dy0: float = sent.y - float(g._y)
	while t < 25.0:
		await physics_frame
		g._pos = me0
		g._v = 0.0
		t += dt
		var d: float = sent.pos.distance_to(g._pos)
		if d < closest:
			closest = d
			var cf := Vector2(sin(sent.yaw), cos(sent.yaw))
			side = absf(((g._pos as Vector2) - sent.pos).dot(Vector2(-cf.y, cf.x)))
		var why := String(sent.why)
		if seen_at < 0.0 and (why == "player" or (why == "junction" and how == "in it")):
			seen_at = d
		vs.append(float(sent.v))
		if vs.size() > 30:
			vs.pop_front()
			# for me: the player in the way, or the junction I stand in (not its own corners)
			if t > 1.0 and (why == "player" or (why == "junction" and how == "in it")):
				brake = maxf(brake, (float(vs[0]) - float(sent.v)) / (29.0 * dt))
		if g._last_hit != last_hit and String(g._last_hit).begins_with("car"):
			hits += 1
		last_hit = g._last_hit
		if sent.v < 0.1 and t > 6.0 and d < 30.0:
			break   # (standing, waiting for the player)
		if not sent.alive:
			break
	# (queued: one that went round, a lane over, is no fault)
	var ok := hits == 0 and (closest >= 5.0 or side > 2.2) and brake <= 5.0
	return {"node": n, "how": how, "street": String(g._roads[p["road"]].get("en", "")), "rise_60m": snappedf(p["dh"], 0.1),
		"height_apart_at_75m": snappedf(dy0, 0.1), "slowed_for_me_at": snappedf(seen_at, 0.1), "hardest_brake_for_me": snappedf(brake, 0.1), "beside": snappedf(side, 0.1),
		"closest": snappedf(closest, 0.1), "hits": hits, "me_rolled": snappedf((g._pos as Vector2).distance_to(me0), 0.1), "ok": ok}
