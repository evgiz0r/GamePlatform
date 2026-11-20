extends SceneTree
## Giving way: autodrive comes up a side street to a bigger road (no lights there) and turns
## onto it, while one car is sent along the bigger road to get to the junction at about the
## same moment -- from the left when autodrive turns right (into its lane), from the right when
## it turns left (across the near lane into the far one). The rest of the traffic is taken off
## the streets, so the two meet alone. Per junction and turn: who went in first, how hard the
## car on the main road braked (over 3.5 m/s^2: it had to stop for autodrive pulling out in
## front of it), how close the two came, how long autodrive stood at the line.
##   LEVEL=4 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/give_way.gd
## GW_N junctions (default 6), spread out, picked the same way each run. OUT=dir: a shot of
## each meeting at its closest.
## PASS: no car on the main road braked hard for autodrive, none came within 4 m of it, and
## none hit it. (Before autodrive gave way, traffic always let the player go: it pulled out in
## front of them and they stood on the brakes.)
var g: Node
var T
var cost_ticks := 0      ## ticks driven (the check's own total is the game's _ap_give_us)

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	# (headless, no frame is ever drawn: waiting for one hung the run for good)
	if OS.get_environment("OUT") == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

## the point `dist` metres along road ri from its point k, walking `dir`, and the way it goes
## there; on past the road's end onto whichever road there carries on straightest (OSM cuts a
## street into pieces at every junction). [] when the streets run out.
func _along(ri: int, k: int, dir: int, dist: float) -> Array:
	var left := dist
	var i := k
	var guard := 0
	while guard < 40:
		guard += 1
		var pts: PackedVector2Array = g._roads[ri]["pts"]
		while i + dir >= 0 and i + dir < pts.size():
			var seg := pts[i].distance_to(pts[i + dir])
			if seg >= left:
				var d := (pts[i + dir] - pts[i]).normalized()
				return [pts[i] + d * left, d]
			left -= seg
			i += dir
		# the end of this road: on along the straightest other one
		var n: int = (g._roads[ri]["ids"] as PackedInt32Array)[i]
		var came := (pts[i] - pts[i - dir]).normalized()
		var best := -0.7
		var nxt := Vector3i(-1, 0, 0)
		for e: Vector2i in g._node_roads[n]:
			if e.x == ri or not g._roads[e.x]["drive"]:
				continue
			var q: PackedVector2Array = g._roads[e.x]["pts"]
			for dd: int in [1, -1]:
				if e.y + dd < 0 or e.y + dd >= q.size():
					continue
				var dot := came.dot((q[e.y + dd] - q[e.y]).normalized())
				if dot > best:
					best = dot
					nxt = Vector3i(e.x, e.y, dd)
		if nxt.x < 0:
			return []
		ri = nxt.x
		i = nxt.y
		dir = nxt.z
	return []

func _rank(r: Dictionary) -> int:
	return 10 if r.get("ring", false) else int(g.ROAD_RANK.get(r["k"], 1))

## junctions with no lights where a side street ends at a bigger two-way road running through
## them, with room on both: [node, side road, its point at the node, main road, its point]
func _pick(want: int) -> Array:
	var out: Array = []
	for n in range(g._nodes.size()):
		if g._sig_set.has(n) or g._node_ways(n) < 3 or not g._signs.get(n, []).is_empty():
			continue
		if OS.get_environment("GW_NODE") != "" and n != int(OS.get_environment("GW_NODE")):
			continue   # (just the one junction)
		# the side street: the smallest road ending here that comes at it straight for 34 m;
		# the main road: the biggest two-way one carrying on through it both ways (a street is
		# often cut in two at a junction: both pieces end at it)
		var side := Vector2i(-1, -1)
		var main := Vector2i(-1, -1)
		var side_rank := 99
		var main_rank := -1
		for e: Vector2i in g._node_roads[n]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"] or r["pv"] or r.get("ring", false):
				continue
			var last := (r["pts"] as PackedVector2Array).size() - 1
			if (e.y == 0 or e.y == last) and _rank(r) < side_rank:
				var into := 1 if e.y == last else -1
				if int(r["o"]) != 0 and int(r["o"]) != into:
					continue
				var back := _along(e.x, e.y, -into, 34.0)
				if back.is_empty() or (back[0] as Vector2).distance_to(g._nodes[n]) < 30.0:
					continue   # (short, or bent: the car would not come at it straight)
				side = e
				side_rank = _rank(r)
		for e: Vector2i in g._node_roads[n]:
			var r: Dictionary = g._roads[e.x]
			if e.x == side.x or not r["drive"] or r["pv"] or r.get("ring", false) or int(r["o"]) != 0 or _rank(r) <= main_rank:
				continue
			if _along(e.x, e.y, 1, 95.0).is_empty() or _along(e.x, e.y, -1, 95.0).is_empty():
				continue
			main = e
			main_rank = _rank(r)
		if side.x < 0 or main.x < 0 or main_rank < side_rank:
			continue
		# a side street of its own, meeting the main road at an angle (a piece of the main road
		# itself, cut at the junction, was taken for one: autodrive drove straight on through)
		var sr: Dictionary = g._roads[side.x]
		var mr: Dictionary = g._roads[main.x]
		if String(sr.get("name", "")) != "" and sr.get("name", "") == mr.get("name", ""):
			continue
		var sp: PackedVector2Array = sr["pts"]
		var mp: PackedVector2Array = mr["pts"]
		var sd := (sp[side.y] - sp[1 if side.y == 0 else side.y - 1]).normalized()
		var md := (mp[mini(main.y + 1, mp.size() - 1)] - mp[maxi(main.y - 1, 0)]).normalized()
		if absf(sd.dot(md)) > 0.6:
			continue
		if not g._in_city(g._nodes[n]) or g._nodes[n].distance_to(g._bounds.get_center()) > minf(g._bounds.size.x, g._bounds.size.y) * 0.42:
			continue
		var crowded := false
		for o: Array in out:
			if (g._nodes[o[0]] as Vector2).distance_to(g._nodes[n]) < 200.0:
				crowded = true
		if crowded:
			continue
		out.append([n, side.x, side.y, main.x, main.y])
		if out.size() >= want:
			break
	return out

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	T = g._traffic
	var want := int(OS.get_environment("GW_N")) if OS.get_environment("GW_N") != "" else 6
	var js := _pick(want)
	print("give way: %d junctions in %s" % [js.size(), g._city_id])
	var bad := 0
	var runs := 0
	for j: Array in js:
		for turn: String in ["right", "left"]:
			var res := await _case(j, turn)
			if res.is_empty():
				continue
			runs += 1
			if not res["ok"]:
				bad += 1
			print("GIVE WAY %s" % JSON.stringify(res))
	print("give way: the check took %.0f us a tick on average" % (float(g._ap_give_us) / maxf(cost_ticks, 1)))
	print("GIVE WAY: %s (%d of %d meetings bad)" % ["PASS" if bad == 0 and runs > 0 else "FAIL", bad, runs])
	quit(0)

func _case(j: Array, turn: String) -> Dictionary:
	var n: int = j[0]
	var node: Vector2 = g._nodes[n]
	var side: Dictionary = g._roads[j[1]]
	var last := (side["pts"] as PackedVector2Array).size() - 1
	var into := 1 if int(j[2]) == last else -1
	var start: Array = _along(j[1], j[2], -into, 34.0)
	var h := (node - (start[0] as Vector2)).normalized()   # my way in
	var right := Vector2(-h.y, h.x)                          # (the side the lanes keep to)
	# the main road each way from the junction: which of its directions is my right
	var ka: Array = _along(j[3], j[4], 1, 12.0)
	var dir_r := 1 if ((ka[0] as Vector2) - node).dot(right) > 0.0 else -1
	var go_dir := dir_r if turn == "right" else -dir_r
	var dest: Array = _along(j[3], j[4], go_dir, 110.0)
	# everyone else off the streets (and kept off), the player at the start
	for c in T.cars:
		c.alive = false
		c.retry = 1000.0
	g._set_auto(false)
	if not g._land_on_road(start[0], 10.0, h):
		return {}
	await physics_frame
	g._set_dest(dest[0], "give way test")
	g._set_auto(true)
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var sent: Variant = null
	var from_dir := -dir_r if turn == "right" else dir_r     # where the car comes from
	var c_prev := 0.0
	var c_brake := 0.0
	var c_brake_any := 0.0
	var c_brake_why := ""
	var gap := INF
	var me_in := -1.0
	var it_in := -1.0
	var stood := 0.0
	var hits := 0                     # into the car on the main road (or any other)
	var bumps := 0                    # into anything else
	var last_hit: String = g._last_hit
	var last_v := 0.0
	var shot_at := INF
	var c_straight := true
	var c_v0 := 0.0
	var r_n: float = g._node_r[n]
	while t < 30.0:
		await physics_frame
		t += dt
		cost_ticks += 1
		if OS.get_environment("VERBOSE") != "" and int(t * 60.0) % 60 == 0:
			print("  t %.0f  wall %d ms  me %.0f m from it at %.1f m/s (%s)  car %s" % [t, Time.get_ticks_msec(), (g._pos as Vector2).distance_to(node),
				g._v, g._ap_why, "-" if sent == null else "%.0f m at %.1f m/s (%s)" % [sent.pos.distance_to(node), sent.v, sent.why]])
			print("     junctions on the plan %s, giving way at %s, plan %d points" % [str(g._ap_js.slice(0, 4)), str(g._ap_giving.keys()), g._ap_pts.size()])
		var my_d: float = (g._pos as Vector2).distance_to(node)
		if sent == null and my_d < 36.0:
			# the car: where it gets to the junction when autodrive would, at its pace
			var eta := (my_d - r_n) / maxf(absf(g._v), 4.5)
			var lim := float(g._roads[j[3]]["speed"])
			var far := clampf(lim * 0.85 * eta + r_n, 30.0, 90.0)
			var at: Array = _along(j[3], j[4], from_dir, far)
			if at.is_empty() or not T.send(at[0], -(at[1] as Vector2)):
				return {}
			for c in T.cars:
				if c.alive:
					sent = c
			c_prev = sent.v
			c_v0 = sent.v
			# (from the side, not along autodrive's own street: where the main road bends at the
			# junction the car was sent up behind autodrive, and braked behind it at its turn)
			var c_dir := Vector2(sin(sent.yaw), cos(sent.yaw))
			if absf(c_dir.dot(h)) > 0.7:
				print("  (skipped: the car would come along autodrive's own street, %s at %d)" % [turn, n])
				return {}
		if absf(g._v) < 0.3 and my_d < r_n + 12.0 and me_in < 0.0:
			stood += dt
		if me_in < 0.0 and my_d < r_n + 0.5:
			me_in = t
		# (as route_set.gd counts them: a new thing hit, at speed)
		if g._last_hit != last_hit and g._last_hit != "" and g._crash_cool > 0.35 and absf(last_v) > 1.0:
			if String(g._last_hit).begins_with("car"):
				hits += 1
			else:
				bumps += 1
		last_hit = g._last_hit
		last_v = g._v
		if sent != null:
			var cd: float = sent.pos.distance_to(node)
			var dec: float = (c_prev - sent.v) / dt
			c_prev = sent.v
			# (its braking for autodrive only: for the player in its way, or at the junction
			# while autodrive is coming into it -- not for its own bend, which traffic takes
			# hard on its own account at some corners)
			var for_me: bool = sent.why == "player" or (sent.why == "junction" and g._ap_giving.is_empty() and my_d < 30.0)
			if it_in < 0.0 and cd < 45.0:
				if dec > c_brake_any:
					c_brake_any = dec
					c_brake_why = String(sent.why)
				if for_me:
					c_brake = maxf(c_brake, dec)
			if it_in < 0.0 and cd < r_n + 0.5:
				it_in = t
			if it_in > 0.0 and t - it_in > 2.0 and t - it_in < 2.1:
				c_straight = absf(Vector2(sin(sent.yaw), cos(sent.yaw)).dot((dest[1] as Vector2))) > 0.7
			var d: float = sent.pos.distance_to(g._pos)
			if d < gap:
				gap = d
				shot_at = t
			if me_in > 0.0 and it_in > 0.0 and t > maxf(me_in, it_in) + 4.0:
				break
	var first := "nobody"
	if me_in > 0.0 and (it_in < 0.0 or me_in < it_in):
		first = "autodrive"
	elif it_in > 0.0:
		first = "the car"
	var ok := c_brake <= 3.5 and gap >= 4.0 and hits == 0
	await _snap("give_way_%d_%s" % [n, turn])
	return {"node": n, "turn": turn, "side": String(side.get("name", "")), "main": String(g._roads[j[3]].get("name", "")),
		"first": first, "car_brake": snappedf(c_brake, 0.1), "car_brake_any": "%.1f (%s)" % [c_brake_any, c_brake_why], "car_v0": snappedf(c_v0 * 3.6, 1), "closest": snappedf(gap, 0.1),
		"stood": snappedf(stood, 0.1), "hits": hits, "bumps": bumps, "car_straight": c_straight, "ok": ok}
