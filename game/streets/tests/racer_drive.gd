extends SceneTree
## Racer on a real drive, in live traffic (the user, 22 Nov, from Givatayim's start on
## Katznelson to Rambam, 1.3 km: "the racer is really passive ... there was only a bus and it
## didnt want to pass ... waiting in traffic"). Level LEVEL (1) as it starts, racer on, to the
## street TO (default Rambam), one line a second: where, how fast, what held it, the car in
## front. Then how long it took, the time it stood (under 1 m/s) and why.
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/racer_drive.gd
## PASS: there within SECS (150), standing under a quarter of the time, no crash.
var g: Node

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

## what it hit, where that stood from the plan the car had each half second before, and
## how far the car was off that plan: a plan through it, or a car that strayed off a clear one
func _crash_detail(hit: String, hist: Array) -> void:
	var at := Vector2.INF
	var r := 0.0
	if hit.begins_with("post "):
		var i := int(hit.substr(5))
		at = g._posts[i]
		r = g._post_r[i]
	elif hit.begins_with("car "):
		var c = g._traffic.cars[int(hit.substr(4))]
		at = c.pos
		r = 0.9
		var cd := Vector2(sin(c.yaw), cos(c.yaw))
		print("      its heading against ours %.2f (1 same way, -1 at us), v %.1f, why %s, its path: %s %s %s" % [cd.dot(g._fwd()),
			float(c.v), c.why, g._car_path_at(c, 4.0), g._car_path_at(c, 8.0), g._car_path_at(c, 14.0)])
	if at == Vector2.INF:
		return
	print("      hit %s at %s r %.2f" % [hit, at, r])
	if OS.get_environment("PLAN") != "" and not hist.is_empty():
		var hp: PackedVector2Array = hist[0][5]
		var line := ""
		for j in range(mini(hp.size(), 40)):
			line += "(%.1f,%.1f) " % [hp[j].x, hp[j].y]
		print("        the plan 3 s before: %s" % line)
	for h: Array in hist.slice(0, hist.size(), 15):
		var pts: PackedVector2Array = h[5]
		var to_plan := INF
		var me_off := INF
		for j in range(pts.size() - 1):
			if pts[j].distance_to(h[1]) > 40.0:
				break
			to_plan = minf(to_plan, Geometry2D.get_closest_point_to_segment(at, pts[j], pts[j + 1]).distance_to(at))
			me_off = minf(me_off, Geometry2D.get_closest_point_to_segment(h[1], pts[j], pts[j + 1]).distance_to(h[1]))
		print("        %5.1f s  car %s %4.1f km/h %-8s lead %5.1f  it from the plan %.2f m, car off the plan %.2f m, from it %.1f m  road %s" % [
			h[0], h[1], float(h[2]) * 3.6, h[3], h[4], to_plan, me_off, (h[1] as Vector2).distance_to(at), h[6]])

## a car in the way that autodrive does not see as the car in front: its middle within 1.5 m
## of the plan, 8-60 m ahead of the car, going the same way -- once a second per car
var _miss_told := {}
func _missed(t: float) -> void:
	var pts: PackedVector2Array = g._ap_pts
	if pts.size() < 2:
		return
	for i in range(g._traffic.cars.size()):
		var c = g._traffic.cars[i]
		if not c.alive or i == int(g._ap_lead_i):
			continue
		var ahead: float = (c.pos - g._pos).dot(g._fwd())
		if ahead < 8.0 or ahead > 60.0:
			continue
		var off := INF
		var seg := -1
		for j in range(pts.size() - 1):
			var dd := Geometry2D.get_closest_point_to_segment(c.pos, pts[j], pts[j + 1]).distance_to(c.pos)
			if dd < off:
				off = dd
				seg = j
		var cd := Vector2(sin(c.yaw), cos(c.yaw))
		if off > 1.5 or cd.dot(g._fwd()) < 0.6:
			continue
		if float(_miss_told.get(i, -10.0)) > t - 1.0:
			continue
		_miss_told[i] = t
		# the first stretch lead_on would have stopped at for its middle
		var first := -1
		for j in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(c.pos, pts[j], pts[j + 1]).distance_to(c.pos) < 1.5:
				first = j
				break
		var sd: Vector2 = (pts[seg + 1] - pts[seg]).normalized()
		print("    MISSED %5.1f s  car %d %s %.0f m ahead, %.2f m off the plan (seg %d of %d, its way %.2f; first near seg %d), lead is %d at %.1f, v %.1f" % [
			t, i, c.kind, ahead, off, seg, pts.size(), sd.dot(cd), first, int(g._ap_lead_i), float(g._ap_lead), float(c.v)])

## stood 8 s behind a car: who holds it, and who holds that one, to the front of the jam
func _chain(i: int) -> void:
	print("      the jam, from the car in front:")
	var seen := {}
	while i >= 0 and not seen.has(i) and seen.size() < 12:
		seen[i] = true
		var c = g._traffic.cars[i]
		print("        car %d %s at %s v=%.1f why=%s wait %.0f s blocker %d  %.0f m from racer" % [i, c.kind, c.pos,
			float(c.v), c.why, float(c.wait), int(c.blocker), c.pos.distance_to(g._pos)])
		i = int(c.blocker) if String(c.why) == "car" else -1

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(_env("LEVEL", "1"))
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	var to := _env("TO", "רמב\"ם")
	var want := float(_env("DIST", "1300"))
	var best := Vector2.INF
	var bd := INF
	for r: Dictionary in g._roads:
		if not String(r["name"]).contains(to) or not r["drive"]:
			continue
		for p: Vector2 in r["pts"]:
			var d := absf(p.distance_to(g._pos) - want)
			if d < bd:
				bd = d
				best = p
	if best == Vector2.INF:
		print("RACER_DRIVE: FAIL (no street %s)" % to)
		quit(1)
		return
	print("RACER_DRIVE to %s at %s, %.0f m as the crow flies" % [to, best, best.distance_to(g._pos)])
	g._set_racer(true)
	g._ap_style = "racer"
	g._set_dest(best, to)
	var secs := float(_env("SECS", "150"))
	g._race_by_why = ""
	var t := 0.0
	var stood := 0.0
	var why := {}
	var crashes := 0
	var next := 0.0
	var probe = root.get_node("Probe")
	probe.enabled = true   # (off, it records nothing: no crashes counted, no moves seen)
	var e0: int = probe._events.size()
	var e_seen := e0
	var trace := 0
	var still := 0.0
	var chained := false
	var ppl_told := false
	var hist: Array = []   # the last 3 s: [t, pos, v, why, lead, plan's offset from the car]
	while t < secs:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		var nh: Dictionary = g._nearest_seg(g._pos, 14.0, true)
		_missed(t)
		hist.append([t, g._pos, float(g._v), String(g._ap_why), float(g._ap_lead), g._ap_pts.duplicate(),
			"%s %s edge %.1f" % [nh.get("road", -1), String(g._roads[int(nh["road"])]["name"]) if not nh.is_empty() else "", float(nh.get("edge", INF))]])
		if hist.size() > 180:
			hist.pop_front()
		if absf(float(g._v)) < 1.0:
			still += dt
			if still >= 8.0 and not chained and int(g._ap_lead_i) >= 0:
				chained = true
				_chain(int(g._ap_lead_i))
			if still >= 8.0 and not ppl_told and String(g._ap_why) == "people":
				ppl_told = true
				var ch: Dictionary = g._nearest_seg(g._pos, 14.0, true)
				print("      stood 8 s for people, the car %.1f m past the asphalt's edge (<0 on it), plan %d points:" % [
					float(ch.get("edge", INF)), g._ap_pts.size()])
				for w: Dictionary in g._walkers + g._crossers:
					var a: Node3D = w["actor"]
					var wp := Vector2(a.position.x, a.position.z)
					if a.visible and wp.distance_to(g._pos) < 15.0:
						var off := INF
						for j in range(g._ap_pts.size() - 1):
							off = minf(off, Geometry2D.get_closest_point_to_segment(wp, g._ap_pts[j], g._ap_pts[j + 1]).distance_to(wp))
						var we: Dictionary = g._nearest_seg(wp, 14.0, true)
						print("        person at %s %.1f m ahead, %.1f m off the plan, %.1f m past the edge, state %s" % [wp,
							(wp - g._pos).dot(g._fwd()), off, float(we.get("edge", INF)), w.get("state", "walk")])
		else:
			still = 0.0
		if absf(float(g._v)) < 1.0:
			stood += dt
			why[g._ap_why] = float(why.get(g._ap_why, 0.0)) + dt
		while e_seen < probe._events.size():
			var ev: Dictionary = probe._events[e_seen]
			e_seen += 1
			var k := String(ev["kind"])
			if k.begins_with("racer_") or k.begins_with("pass_") or k == "crash":
				print("    event %5.1f s  %s %s" % [t, k, JSON.stringify(ev["data"])])
			if k == "crash":
				_crash_detail(String(ev["data"].get("hit", "")), hist)
				if OS.get_environment("TRACE") != "":
					trace = 20
		if trace > 0 and int(g._ap_lead_i) >= 0:
			trace -= 1
			var tc = g._traffic.cars[int(g._ap_lead_i)]
			var toff := INF
			var tp: PackedVector2Array = g._ap_pts
			for j in range(tp.size() - 1):
				toff = minf(toff, Geometry2D.get_closest_point_to_segment(tc.pos, tp[j], tp[j + 1]).distance_to(tc.pos))
			print("      tick: lead %.1f off %.2f pts %d passed %d" % [float(g._ap_lead), toff, tp.size(), int(g._ap_passed)])
		if t >= next:
			next += 1.0
			var hit: Dictionary = g._nearest_seg(g._pos, 12.0, true)
			var rn := String(g._roads[int(hit["road"])]["name"]) if not hit.is_empty() else "?"
			var lk := ""
			if int(g._ap_lead_i) >= 0:
				var c = g._traffic.cars[int(g._ap_lead_i)]
				lk = "%s v=%.1f %s" % [c.kind, float(c.v), c.why]
				var off := INF
				var pts: PackedVector2Array = g._ap_pts
				for j in range(pts.size() - 1):
					off = minf(off, Geometry2D.get_closest_point_to_segment(c.pos, pts[j], pts[j + 1]).distance_to(c.pos))
				lk += " off %.1f/%d" % [off, pts.size()]
				lk += " nose %.1f gave %d" % [float(g._race_nose_t), int(g._race_gave)]
			print("  %5.1f s  %5.1f km/h  %-10s lead %5.1f m %-14s  %s  to go %.0f m" % [t, float(g._v) * 3.6,
				g._ap_why, float(g._ap_lead), lk, rn, g._pos.distance_to(best)])
			if lk != "" and (absf(float(g._v)) < 1.0 or OS.get_environment("VERBOSE") != ""):
				print("           by: %s | queue: %s | up: %s" % [g._race_by_why, g._race_q_why, g._mount_why])
		if g._pos.distance_to(best) < 25.0 or not g._dest_on:
			break
	var there: bool = g._pos.distance_to(best) < 40.0 or not g._dest_on
	for i in range(e0, probe._events.size()):
		if String(probe._events[i]["kind"]) == "crash":
			crashes += 1
			print("  crash: %s" % JSON.stringify(probe._events[i]["data"]))
	print("RACER_DRIVE %s in %.0f s, stood %.0f s (%.0f%%), why: %s, crashes %d" % ["there" if there else "NOT there",
		t, stood, 100.0 * stood / maxf(t, 1.0), JSON.stringify(why), crashes])
	print("RACER_DRIVE across: %s" % g._across_why)
	print("RACER_DRIVE plan points eased off solids: %d, passes %d" % [int(g._ap_cleared), int(g._racer.passes)])
	print("RACER_DRIVE: %s" % ("PASS" if there and stood < t * 0.25 and crashes == 0 else "FAIL"))
	quit(0)
