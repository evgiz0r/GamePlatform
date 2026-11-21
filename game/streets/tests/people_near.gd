extends SceneTree
## Autodrive and the people in the street: how close does the car come to anyone? Drives
## TRIPS trips (default 6) by "go to" from FROM to TO (x,z; default the last stretch of the
## route set's route 9 in Bedford, down Hollyhock Way, where it hit a person at 32 km/h on
## 21 Nov), TRIP_SECS each at most, and every tick takes each person (walkers, crossers,
## everyone in the street) whose middle is within REACH m (default 1.6) of the car's body
## outline while it moves faster than 1.5 m/s: a near miss -- or a hit. For each it prints
## who they were (list, state), where, the car's speed, what held autodrive (_ap_why), and
## the person's last 2 s (how far they moved, and towards the car's way or not). Run
## headless, fast:
##   LEVEL=2 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/people_near.gd
## Good: 0 hits, 0 near misses under 1.0 m.
var g: Node

func _initialize() -> void:
	_run()

func _vec(env: String, def: Vector2) -> Vector2:
	var s := OS.get_environment(env)
	if s == "":
		return def
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

func _everyone() -> Array:
	var out: Array = []
	var lists := {"walker": g._walkers, "crosser": g._crossers, "chatter": g._chatters, "sitter": g._sitters,
		"waiter": g._waiters, "keeper": g._keepers, "bather": g._bathers, "boarder": g._boarders}
	for who: String in lists:
		for w: Dictionary in lists[who]:
			var a: Node3D = w["actor"]
			if a.visible:
				var tag: String = who + (":" + str(w["state"]) if w.has("state") else "")
				if w.has("cross") and float(w["cross"]) > 0.0 and float(w.get("s", 99.0)) <= float(w["cross"]):
					tag += ":stepping over"   # (a side street's mouth, _walk_on)
				out.append([a.get_instance_id(), Vector2(a.position.x, a.position.z), tag])
	return out

## distance from p to the car's body: a box CAR_L x CAR_W round its middle
func _to_body(p: Vector2) -> float:
	var f: Vector2 = g._fwd()
	var d: Vector2 = p - g._pos
	var al: float = d.dot(f)
	var lat: float = d.dot(Vector2(-f.y, f.x))
	var ex := maxf(absf(al) - 2.3, 0.0)
	var ey := maxf(absf(lat) - 0.92, 0.0)
	return Vector2(ex, ey).length()

const LANE := 1.7   ## (autodrive's own reach from its plan, _ap_people_v)

## how far along autodrive's plan, from the car's nose, the point within LANE m of p is
## (looking 40 m ahead), or -1 when p is not on the lane ahead
func _in_band(p: Vector2) -> float:
	var pts: PackedVector2Array = g._ap_pts
	if pts.size() < 2 or (p - g._pos).dot(g._fwd()) < 0.0:
		return -1.0
	var base := -pts[0].distance_to(Geometry2D.get_closest_point_to_segment(g._pos, pts[0], pts[1]))
	for j in range(pts.size() - 1):
		if base > 40.0:
			break
		var cp := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
		if cp.distance_to(p) < LANE:
			return maxf(base + pts[j].distance_to(cp) - g.CAR_OFF, 0.0)
		base += pts[j].distance_to(pts[j + 1])
	return -1.0

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 2})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var from := _vec("FROM", Vector2(-2745.0, 60.0))
	var to := _vec("TO", Vector2(-2702.1, 448.2))
	var trips := int(OS.get_environment("TRIPS")) if OS.get_environment("TRIPS") != "" else 6
	var limit := float(OS.get_environment("TRIP_SECS")) if OS.get_environment("TRIP_SECS") != "" else 120.0
	var reach := float(OS.get_environment("REACH")) if OS.get_environment("REACH") != "" else 1.6
	var hits := 0
	var near := 0
	var under1 := 0
	var metres := 0.0
	var late := 0
	var inband := {}   # id -> in the lane band last tick
	var tracks := {}   # id -> [[t, pos], ...] over the last 2 s
	var flagged := {}  # id -> t last printed (once a pass)
	var t := 0.0
	for trip in range(trips):
		g._land_on_road(from, 60.0, Vector2.ZERO)
		await physics_frame
		g._set_dest(to, "there")
		g._set_auto(true)
		var t0 := t
		var odo0: float = g._odo
		var last_hit: String = g._last_hit
		while t - t0 < limit:
			await physics_frame
			t += Engine.time_scale / Engine.physics_ticks_per_second
			if not g._dest_on:
				break
			var all := _everyone()
			for e: Array in all:
				var id: int = e[0]
				var tr: Array = tracks.get(id, [])
				tr.append([t, e[1]])
				while not tr.is_empty() and float(tr[0][0]) < t - 2.0:
					tr.pop_front()
				tracks[id] = tr
				if absf(g._v) < 1.5:
					continue
				# into the lane ahead too late to stop for: within LANE m of the plan, and nearer
				# the nose than the car can stop from its speed (3.5 m/s^2 and 0.3 s), when a
				# tick ago they were not in it
				var band: float = _in_band(e[1])
				var was: bool = inband.get(id, false)
				inband[id] = band >= 0.0
				if band >= 0.0 and not was:
					var need: float = absf(g._v) * 0.3 + g._v * g._v / 7.0
					if band < need:
						late += 1
						var mv: Vector2 = (e[1] as Vector2) - (tr[0][1] as Vector2)
						print("LATE trip %d t %.1f  %s at (%.1f, %.1f) into the lane %.1f m ahead of the nose (needs %.1f to stop)  car %.0f km/h on %s, held by %s  their last 2 s: moved %.1f m (%.1f m/s)" % [
							trip, t - t0, e[2], (e[1] as Vector2).x, (e[1] as Vector2).y, band, need, absf(g._v) * 3.6,
							g._on_name, g._ap_why, mv.length(), mv.length() / 2.0])
				var d := _to_body(e[1])
				if d < reach and t - float(flagged.get(id, -99.0)) > 3.0:
					flagged[id] = t
					near += 1
					if d < 1.0:
						under1 += 1
					var moved: Vector2 = (e[1] as Vector2) - (tr[0][1] as Vector2)
					var f: Vector2 = g._fwd()
					var side := Vector2(-f.y, f.x)
					var lat: float = ((e[1] as Vector2) - g._pos).dot(side)
					var toward: float = -signf(lat) * moved.dot(side)   # + : moved towards the car's line
					print("NEAR trip %d t %.1f  %.2f m from the body  %s at (%.1f, %.1f)  car %.0f km/h on %s, held by %s  their last 2 s: moved %.1f m, %.1f m towards the car's line, now %.1f m beside it" % [
						trip, t - t0, d, e[2], (e[1] as Vector2).x, (e[1] as Vector2).y, absf(g._v) * 3.6,
						g._on_name, g._ap_why, moved.length(), toward, lat])
			var h: String = g._last_hit
			if h != last_hit and h == "person" and g._crash_cool > 0.35:
				hits += 1
				print("HIT trip %d t %.1f at (%.0f, %.0f) on %s, %.0f km/h" % [trip, t - t0, g._pos.x, g._pos.y, g._on_name, absf(g._v) * 3.6])
			last_hit = h
		metres += g._odo - odo0
		print("trip %d: %.0f s, %.0f m, arrived %s" % [trip, t - t0, g._odo - odo0, str(not g._dest_on)])
	print("PEOPLE NEAR: %d hits, %d within %.1f m of the body (%d under 1 m), %d into the lane too late to stop for, over %.1f km" % [hits, near, reach, under1, late, metres / 1000.0])
	quit(0)
