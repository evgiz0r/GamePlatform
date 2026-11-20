extends SceneTree
## The driving exam: autodrive from several places in a city (the start and EXAM_STARTS-1
## more spread over the town), EXAM_SECS each, with the traffic and the people about, and
## everything that went wrong counted:
##   autodrive -- stuck (8 s+ standing, not for a light, a zebra or a queue that moves), hits
##     by kind (over 2 m/s), off the asphalt, left of the middle of a two-way street, red
##     lights run, rescues ("back on the road" / "unstuck"), harsh braking (over 6 m/s^2:
##     the times it happened, and what for)
##   traffic -- stalls (20 s+ not at a red light), two cars overlapping, red lights run,
##     cars sent away for being stuck
##   people -- a moving car within a metre of someone
## Per minute driven, so runs of different lengths compare; and the worst places, each with
## the drive log of the moments before (user://drive_logs/exam-*.json: draw them with
## tests/drive_log_map.py). The loop: run it, look at the top of the list, fix, run it again.
var g: Node
var T
var counts := {}
var where: Array = []                ## [what, Vector2, detail, log file]
var logs_saved := 0
var saved_kind := {}

func _initialize() -> void:
	_run()

func _count(k: String, n := 1) -> void:
	counts[k] = int(counts.get(k, 0)) + n

func _incident(what: String, at: Vector2, detail: String, save := true) -> void:
	var file := ""
	# a drive log of the moments before, for the first few of each kind (the recorder keeps
	# every car near the player and what holds each: draw it with drive_log_map.py)
	var kind_n := int(saved_kind.get(what, 0))
	if save and kind_n < 3 and logs_saved < int(OS.get_environment("EXAM_LOGS") if OS.get_environment("EXAM_LOGS") != "" else "12"):
		saved_kind[what] = kind_n + 1
		logs_saved += 1
		file = g._log.save(g).replace(".json", "")
		var parts := file.split("/")
		var named := "exam-%s-%d-%s.json" % [g._city_id, logs_saved, what.replace(" ", "_")]
		DirAccess.rename_absolute(file + ".json", "/".join(parts.slice(0, parts.size() - 1)) + "/" + named)
		file = named
	where.append([what, at, detail, file])

func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	var starts := int(OS.get_environment("EXAM_STARTS")) if OS.get_environment("EXAM_STARTS") != "" else 4
	var secs := float(OS.get_environment("EXAM_SECS")) if OS.get_environment("EXAM_SECS") != "" else 75.0
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	T = g._traffic
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + lvl
	var spots: Array = [g._pos]
	var b: Rect2 = g._bounds.grow(-300.0)
	for _i in range(200):
		if spots.size() >= starts:
			break
		var p := b.position + Vector2(rng.randf() * b.size.x, rng.randf() * b.size.y)
		var hit: Dictionary = g._nearest_seg(p, 40.0, true, true)
		if hit.is_empty() or (g._roads[hit["road"]] as Dictionary)["k"] == "service" or not g._in_city(p):
			continue
		var far := true
		for q: Vector2 in spots:
			if q.distance_to(p) < 600.0:
				far = false
		if far:
			spots.append(hit["q"])
	var metres := 0.0
	for si in range(spots.size()):
		if si > 0:
			g._set_auto(false)
			g._land_on_road(spots[si], 40.0, Vector2.ZERO)
			await physics_frame
		g._set_auto(true)
		var odo0: float = g._odo
		await _drive(secs)
		metres += g._odo - odo0
		print("  start %d at %s: %.0f m" % [si, Vector2i(spots[si]), g._odo - odo0])
	var mins := secs * spots.size() / 60.0
	print("EXAM %s: %d starts x %.0f s, %.1f km driven" % [g._city_name, spots.size(), secs, metres / 1000.0])
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		print("  %-34s %5d   %.2f a minute" % [k, int(counts[k]), int(counts[k]) / mins])
	print("worst places:")
	for w: Array in where.slice(0, 25):
		print("  %-18s at %-14s %s %s" % [w[0], str(Vector2i(w[1])), w[2], ("[" + String(w[3]) + "]") if String(w[3]) != "" else ""])
	quit(0)

func _drive(secs: float) -> void:
	var dt := 1.0 / 60.0
	var t := 0.0
	var still := 0.0
	var off := 0.0
	var last_hit := ""
	var last_v: float = g._v
	var car_still := {}
	var overlapping := {}
	var inside := {}      ## "car:junction" -> when it was last inside one of its points
	var came_dir := {}    ## car -> its heading when last outside every signalled point
	var near_people := {}
	var rescues: int = g._log.events.size()
	var left_t := 0.0
	var harsh := false
	var last_p: Vector2 = g._pos
	var events_seen: int = g._log.events.size()
	while t < secs:
		await physics_frame
		t += dt
		var p: Vector2 = g._pos
		# -- autodrive
		var held: String = g._ap_why
		if absf(g._v) < 0.3 and not held in ["light", "zebra", "people"] and not (held == "car" and _lead_moving()):
			still += dt
			if absf(still - 8.0) < dt * 0.5:
				_count("autodrive: stuck 8 s+")
				_incident("stuck", p, "held by %s, last hit %s" % [held, g._last_hit])
		else:
			if still >= 8.0:
				_count("autodrive: seconds stuck", int(still))
			still = 0.0
		var h: String = g._last_hit
		if h != last_hit and h != "" and g._crash_cool > 0.35 and absf(last_v) > 2.0:
			var kind := h.split(" ")[0]
			_count("autodrive: hit " + kind)
			_incident("hit " + kind, p, "%.0f km/h, held by %s" % [absf(last_v) * 3.6, held])
		last_hit = h
		var dv: float = (g._v - last_v) / dt
		# harsh braking: each time it starts (frames of it overstated a single stop by 30x),
		# and what for (a bump stops the car too: that is a hit, counted above; a lift back
		# onto the road sets the speed to 0 -- not braking at all)
		if dv < -6.0 and absf(last_v) > 3.0 and g._pos.distance_to(last_p) < 2.0:
			if not harsh:
				_count("autodrive: harsh braking")
				_count("autodrive: harsh braking, %s" % ("a bump" if g._crash_cool > 0.0 else "for " + held))
				harsh = true
		elif dv > -3.0:
			harsh = false
		last_p = g._pos
		last_v = g._v
		var on: Dictionary = g._nearest_seg(p, 30.0, true, true)
		if not on.is_empty() and float(on["edge"]) > 1.0:
			off += dt
			if absf(off - 2.0) < dt * 0.5:
				_count("autodrive: off the asphalt 2 s+")
				_incident("off road", p, "%.1f m off" % float(on["edge"]))
		else:
			off = 0.0
		if not on.is_empty() and absf(g._v) > 3.0:
			var r: Dictionary = g._roads[on["road"]]
			if int(r["o"]) == 0 and not r.get("ring", false):
				var pts: PackedVector2Array = r["pts"]
				var sj: int = on["seg"]
				var d: Vector2 = (pts[sj + 1] - pts[sj]).normalized()
				if d.dot(g._fwd()) < 0.0:
					d = -d
				var near_j := false
				for n2: int in [(r["ids"] as PackedInt32Array)[sj], (r["ids"] as PackedInt32Array)[sj + 1]]:
					if g._node_ways(n2) >= 3 and g._nodes[n2].distance_to(p) < g._node_r[n2] + 10.0:
						near_j = true
				if not near_j and (p - (on["q"] as Vector2)).dot(Vector2(-d.y, d.x)) < -0.5:
					_count("autodrive: ticks left of the middle")
					left_t += dt
					if absf(left_t - 1.5) < dt * 0.5:
						_incident("left of middle", p, "%s, %.1f m wide, %d lane(s) a way, held by %s" % [
							r["en"], float(r["w"]), g._lanes_each_way(r), held], false)
				else:
					left_t = 0.0
		# events the game logged: red lights, rescues
		while events_seen < g._log.events.size():
			var ev: Array = g._log.events[events_seen]
			events_seen += 1
			match String(ev[1]):
				"red light":
					_count("autodrive: red lights run")
					_incident("red light", p, "", true)
				"rescue", "unstuck":
					_count("autodrive: " + String(ev[1]))
					_incident(String(ev[1]), p, "")
		# -- traffic
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive:
				car_still.erase(i)
				continue
			if c.v < 0.3 and T._light_ahead(c) > 0.5:
				car_still[i] = float(car_still.get(i, 0.0)) + dt
				if absf(float(car_still[i]) - 20.0) < dt * 0.5:
					_count("traffic: stalls 20 s+")
					_incident("traffic stall", c.pos, "%s, held by %s, blocker %d" % [c.kind, c.why, c.blocker])
			else:
				car_still.erase(i)
			if c.wait > 25.0:
				_count("traffic: sent away (stuck) ticks")
			# a red light run: into a junction's first signalled point on red, by the way the
			# car came in (its heading before it got there). The points of one junction (a
			# divided road's are several, 10-30 m apart) are one: a car that went in on
			# green and turned, judged at the next point by the way it faced mid-turn, read
			# as running the cross street's red.
			var in_any := false
			for n: int in g._near(g._sig_hash, c.pos, 30.0, g.SEG_CELL):
				if g._nodes[n].distance_to(c.pos) >= g._node_r[n] + 1.0:
					continue
				in_any = true
				var knot: int = g._sig_owner.get(n, n)
				var key := "%d:%d" % [i, knot]
				if not inside.has(key) and c.v > 2.0:
					var came: Vector2 = came_dir.get(i, Vector2(sin(c.yaw), cos(c.yaw)))
					if g._light_at(n, came) == "r":
						_count("traffic: red lights run")
						_incident("traffic red", c.pos, c.kind)
				inside[key] = t
			if not in_any:
				came_dir[i] = Vector2(sin(c.yaw), cos(c.yaw))
				for key: String in inside.keys():
					if key.begins_with("%d:" % i) and t - float(inside[key]) > 8.0:
						inside.erase(key)
			for j in range(i + 1, T.cars.size()):
				var o = T.cars[j]
				if not o.alive or o.pos.distance_squared_to(c.pos) > 64.0:
					continue
				var fwd := Vector2(sin(c.yaw), cos(c.yaw))
				var rel: Vector2 = o.pos - c.pos
				var lon := absf(rel.dot(fwd))
				var lat := absf(rel.dot(Vector2(fwd.y, -fwd.x)))
				var key := "%d:%d" % [i, j]
				if lat < 1.6 and lon < (c.len + o.len) * 0.5 - 0.4 and (c.v > 0.5 or o.v > 0.5):
					if not overlapping.has(key):
						overlapping[key] = true
						_count("traffic: cars overlapping")
						_incident("traffic overlap", c.pos, "%s (%s) & %s (%s)" % [c.kind, c.why, o.kind, o.why])
				else:
					overlapping.erase(key)
		# -- people
		var movers: Array = [[p, absf(g._v)]]
		for c in T.cars:
			if c.alive:
				movers.append([c.pos, c.v])
		var people: Array = []
		for w: Dictionary in g._walkers:
			if (w["actor"] as Node3D).visible:
				people.append(w["actor"])
		for cr: Dictionary in g._crossers:
			if (cr["actor"] as Node3D).visible:
				people.append(cr["actor"])
		for a: Node3D in people:
			var q := Vector2(a.position.x, a.position.z)
			var key := a.get_instance_id()
			var close := false
			for m: Array in movers:
				if float(m[1]) > 2.0 and (m[0] as Vector2).distance_to(q) < 1.0 + 1.0:
					close = true
			if close and not near_people.has(key):
				near_people[key] = true
				_count("people: a moving car within a metre")
				_incident("person close", q, "", false)
			elif not close:
				near_people.erase(key)
	if still >= 8.0:
		_count("autodrive: seconds stuck", int(still))

func _lead_moving() -> bool:
	if g._ap_lead < 0.0:
		return false
	var lead: Array = T.lead_on(g._ap_pts, g._pos, 30.0, false)
	if int(lead[3]) < 0:
		return false
	var c = T.cars[int(lead[3])]
	return c.wait < 6.0   # (a queue that is moving now and then: not stuck)
