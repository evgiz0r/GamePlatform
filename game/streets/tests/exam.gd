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
## and the checks ("check: ..."), which should all read 0. Each one is a kind of bug fixed
## before that a check like it would have caught at once; they measure bodies, not middles
## (tests/bodies.gd), so a bus counts as a bus:
##   bodies overlapping -- two traffic cars, autodrive and a car, or a car's body into a
##     building, a wall, a hedge or a post (traffic is on rails: nothing else stops it)
##   over the line at a red -- stopped for the light, the front more than a metre past the
##     stop line (a bus once stopped with its middle at the line, 4 m into the junction)
##   pushing -- autodrive's foot on the gas, not moving, 3 s in all before it gets 4 m away
##     (forward into a post, back, forward again went on for 90 s)
##   held by nothing -- standing 10 s+ with no named reason: what holds it (and whatever
##     holds that, down a queue) is the speed limit, a curve, a car that is gone, or a loop
##     of cars each waiting for the next
## Per minute driven, so runs of different lengths compare; and the worst places, each with
## the drive log of the moments before (user://drive_logs/exam-*.json: draw them with
## tests/drive_log_map.py). The loop: run it, look at the top of the list, fix, run it again.
##
##   game/streets/tests/run.sh exam 3
##   LEVEL=3 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s \
##       res://game/streets/tests/exam.gd     the same numbers, no window, several times faster
##   EXAM_AT=-25,160 EXAM_STAND=70 ...   one junction watched: no driving, the car put down off
##       the road by AT (traffic comes and goes round it), the traffic's checks alone, and only
##       what happens within EXAM_STAND metres of AT (Tel Aviv's Begin x Kaplan)
const Bodies = preload("res://game/streets/tests/bodies.gd")
const CHECKS := ["check: bodies overlapping, traffic", "check: bodies overlapping, autodrive and a car",
	"check: traffic body into a building", "check: traffic body into a wall", "check: traffic body into a post",
	"check: autodrive body into a building", "check: autodrive body into a wall", "check: autodrive body into a post",
	"check: over the line at a red, traffic", "check: over the line at a red, autodrive",
	"check: autodrive pushing 3 s+", "check: held by nothing 10 s+, traffic", "check: held by nothing 10 s+, autodrive"]
## what may hold a car standing still (anything else -- the limit, a curve -- is nothing)
const NAMED := ["light", "zebra", "people", "sign", "junction", "player", "bus stop", "squeezing past",
	"blocked", "choice", "turning", "backing", "pushing"]
var g: Node
var T
var counts := {}
var where: Array = []                ## [what, Vector2, detail, log file]
var logs_saved := 0
var _watch_r := 0.0                    ## EXAM_STAND: watching one junction from beside it, this far
var _at := Vector2.INF               ## EXAM_AT
var saved_kind := {}

func _initialize() -> void:
	_run()

func _count(k: String, n := 1) -> void:
	if _watch_r > 0.0 and k != "traffic: sent away (stuck) ticks":
		_pending.append([k, n])   # (counted if the incident that follows is near the junction)
		return
	counts[k] = int(counts.get(k, 0)) + n

var _pending: Array = []

func _incident(what: String, at: Vector2, detail: String, save := true) -> void:
	if _watch_r > 0.0:
		var keep := at.distance_to(_at) <= _watch_r
		for pc: Array in _pending:
			if keep:
				counts[pc[0]] = int(counts.get(pc[0], 0)) + int(pc[1])
		_pending.clear()
		if not keep:
			return
	var file := ""
	# a drive log of the moments before, for the first few of each kind (the recorder keeps
	# every car near the player and what holds each: draw it with drive_log_map.py)
	var kind_n := int(saved_kind.get(what, 0))
	if save and kind_n < 3 and logs_saved < int(OS.get_environment("EXAM_LOGS") if OS.get_environment("EXAM_LOGS") != "" else "20"):
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
	for k: String in CHECKS:
		counts[k] = 0   # (printed even when nothing was found: a 0 says the check ran)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + lvl
	var spots: Array = [g._pos]
	if OS.get_environment("EXAM_AT") != "":
		var xz := OS.get_environment("EXAM_AT").split(",")
		_at = Vector2(float(xz[0]), float(xz[1]))
		spots = [_at]
		starts = 1
		_watch_r = float(OS.get_environment("EXAM_STAND")) if OS.get_environment("EXAM_STAND") != "" else 0.0
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
		if _watch_r > 0.0:
			_stand_by(spots[si])
			await physics_frame
		elif si > 0 or _at != Vector2.INF:
			g._set_auto(false)
			g._land_on_road(spots[si], 40.0, Vector2.ZERO)
			await physics_frame
		if _watch_r <= 0.0:
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
	var checks_found := 0
	for k: String in CHECKS:
		checks_found += int(counts[k])
	print("CHECKS: %d found (0 is good)" % checks_found)
	# the places, a few of each kind (one kind found everywhere does not hide the rest)
	print("worst places:")
	var shown := {}
	for w: Array in where:
		var n := int(shown.get(w[0], 0))
		if n >= 4:
			continue
		shown[w[0]] = n + 1
		print("  %-26s at %-14s %s %s" % [w[0], str(Vector2i(w[1])), w[2], ("[" + String(w[3]) + "]") if String(w[3]) != "" else ""])
	quit(0)

## the car put down off the road beside the junction at `at` -- on the pavement or a plaza,
## clear of buildings -- and left there: the traffic is made round it
func _stand_by(at: Vector2) -> void:
	g._set_auto(false)
	for r: float in [22.0, 30.0, 40.0, 55.0]:
		for k in range(24):
			var p := at + Vector2.from_angle(k * TAU / 24.0) * r
			var on: Dictionary = g._nearest_seg(p, 30.0, true)
			if not on.is_empty() and float(on["edge"]) < 3.0:
				continue
			if g._push_out(p, 2.5, true, true, g._h(p)) != Vector2.ZERO:
				continue
			g._pos = p
			g._prev_pos = p
			g._y = g._h(p)
			g._v = 0.0
			g._snap_pose()
			print("  watching from %s, %.0f m from %s" % [Vector2i(p), r, Vector2i(at)])
			return
	print("  no spot off the road near %s: watching from the road" % Vector2i(at))

func _drive(secs: float) -> void:
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
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
		_check(dt)
		if _watch_r > 0.0:
			_watch_traffic(dt, t, car_still, overlapping, inside, came_dir)
			continue
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
		# (at the car's own level: up on a bridge, the nearest road at the ground's level is
		# the one under it, and the HaShalom bridge read as "15.8 m off the asphalt")
		var on: Dictionary = g._nearest_seg(p, 30.0, true, true, float(g._y))
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
		_watch_traffic(dt, t, car_still, overlapping, inside, came_dir)
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


## one traffic car, all a watched junction's incident needs: where, which way, how fast, on
## what road and lane, how far shifted off its lane line (changing lanes, filtering), what
## holds it and who
func _car_line(i: int) -> String:
	var c = T.cars[i]
	var rd: int = c.rd[clampi(c.k, 0, c.rd.size() - 1)] if c.rd.size() > 0 else -1
	var road: String = ("%s (%s, %d lanes a way)" % [g._roads[rd]["en"] if g._roads[rd]["en"] != "" else g._roads[rd]["name"],
		g._roads[rd]["k"], g._lanes_each_way(g._roads[rd])]) if rd >= 0 else "?"
	var ahead: Array = []   # the roads its plan runs on from here: [road, which way along it]
	for j in range(c.k, mini(c.rd.size(), c.k + 12)):
		var rj: int = c.rd[j]
		if rj < 0 or (not ahead.is_empty() and int(ahead[-1][0]) == rj):
			continue
		var rp: PackedVector2Array = g._roads[rj]["pts"]
		var way := "?"
		if j + 1 < c.pts.size():
			var seg: Vector2 = c.pts[j + 1] - c.pts[j]
			var best := INF
			for q in range(rp.size() - 1):
				var dq: float = Geometry2D.get_closest_point_to_segment(c.pts[j], rp[q], rp[q + 1]).distance_to(c.pts[j])
				if dq < best:
					best = dq
					way = "+" if (rp[q + 1] - rp[q]).dot(seg) >= 0.0 else "-"
		ahead.append([rj, way])
	var plan := " > ".join(ahead.map(func(a): return "%s%s(o%d)" % [g._roads[a[0]]["en"] if g._roads[a[0]]["en"] != "" else g._roads[a[0]]["name"], a[1], int(g._roads[a[0]]["o"])]))
	return "car %d %s at (%.1f, %.1f) heading %.0f, %.1f m/s, %s, lane %d shift %.2f -> %.2f%s, held by %s (blocker %d), k %d of %d; plan %s" % [
		i, c.kind, c.pos.x, c.pos.y, rad_to_deg(c.yaw), c.v, road, c.lane_i, c.shift, c.shift_to,
		", filtering" if c.split else "", c.why, c.blocker, c.k, c.pts.size(), plan]

## the traffic's own checks: stalls, cars sent away, red lights run, cars overlapping
var site_was := {}   ## traffic car -> the junction with lights it was last in, as the game had it while outside every lit point

func _watch_traffic(dt: float, t: float, car_still: Dictionary, overlapping: Dictionary, inside: Dictionary, came_dir: Dictionary) -> void:
	# -- traffic
	for i in range(T.cars.size()):
		var c = T.cars[i]
		if not c.alive:
			car_still.erase(i)
			continue
		if c.v < 0.3 and T._light_ahead(c) > 0.5 and not _queued_at_light(c):
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
			var knot: int = g._site_of.get(n, n)
			var key := "%d:%d" % [i, knot]
			if not inside.has(key) and c.v > 2.0:
				var came: Vector2 = came_dir.get(i, Vector2(sin(c.yaw), cos(c.yaw)))
				# already in this junction, by another of its lights whose middle it went
				# wide of (the game's own record, from before it came to this point): going on
				# through its inner points is not running their red
				if int(site_was.get(i, -1)) == knot:
					inside[key] = t
					continue
				if g._light_at(n, came) == "r":
					_count("traffic: red lights run")
					_incident("traffic red", c.pos, c.kind)
					if _watch_r > 0.0 and c.pos.distance_to(_at) <= _watch_r:
						print("    red at point %d (%s, r %.1f), came heading %.0f; last site %d (this %d), %.1f m since its last light\n    %s" % [
							n, Vector2i(g._nodes[n]), g._node_r[n], rad_to_deg(atan2(came.x, came.y)), c.last_site, knot,
							c.s - c.last_light, _car_line(i)])
			inside[key] = t
		if not in_any:
			came_dir[i] = Vector2(sin(c.yaw), cos(c.yaw))
			site_was[i] = c.last_site
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

func _lead_moving() -> bool:
	if g._ap_lead < 0.0:
		return false
	var lead: Array = T.lead_on(g._ap_pts, g._pos, 30.0, false)
	if int(lead[3]) < 0:
		return false
	var c = T.cars[int(lead[3])]
	return c.wait < 6.0   # (a queue that is moving now and then: not stuck)

## standing in a queue whose front car waits at a red light: waiting, not stalled (with the
## side streets' longer red, the third car back waited 25 s and read as a stall)
func _queued_at_light(c) -> bool:
	var seen := 0
	var o = c
	while o.blocker >= 0 and seen < 12:
		o = T.cars[o.blocker]
		seen += 1
		if o.alive and T._light_ahead(o) < 0.5:
			return true
	return false

## ---- the checks: bodies, not middles (see the top of this file and tests/bodies.gd) -------

var _tick := 0
var _pairs := {}        ## "i:j" / "ap:i": bodies overlapping last tick (counted on the way in)
var _in_solid := {}     ## car index / "ap" -> the tick its body was last seen in a building, wall or post
var _over := {}         ## "i:node" / "ap:node" -> the tick it was counted standing over that line
var _stop_why := {}     ## traffic car -> what held it the moment it came to a stop
var _ap_stop_why := ""
var _last_pos := {}     ## traffic car -> where it was last tick (a jump: put down elsewhere)
var _stand := {}        ## traffic car -> seconds standing
var _ap_stand := 0.0
var _push_at := Vector2.INF
var _push_s := 0.0
var _push_counted := false

func _check(dt: float) -> void:
	_tick += 1
	var cars: Array = T.cars
	var boxes := {}
	for i in range(cars.size()):
		if cars[i].alive:
			boxes[i] = Bodies.car_box(cars[i])
	var pb: Array = Bodies.player_box(g)
	# -- bodies overlapping: traffic with traffic (both standing too: put down on each other
	# is as wrong as driving into each other), autodrive with traffic
	var now := {}
	for i: int in boxes:
		var c = cars[i]
		for j: int in boxes:
			if j <= i:
				continue
			var o = cars[j]
			if c.pos.distance_squared_to(o.pos) > 196.0 or absf(c.y - o.y) > 2.5:
				continue
			var d := Bodies.box_depth(boxes[i], boxes[j])
			if d > 0.25:
				var key := "%d:%d" % [i, j]
				now[key] = true
				if not _pairs.has(key):
					_count("check: bodies overlapping, traffic")
					_incident("bodies overlap", (c.pos + o.pos) * 0.5, "%s (%s, %.0f km/h) & %s (%s, %.0f km/h), %.1f m in" % [
						c.kind, c.why, c.v * 3.6, o.kind, o.why, o.v * 3.6, d])
					if _watch_r > 0.0 and (c.pos + o.pos).distance_to(_at * 2.0) <= _watch_r * 2.0:
						print("    %s\n    %s" % [_car_line(i), _car_line(j)])
		if c.pos.distance_squared_to(g._pos) < 196.0 and absf(c.y - g._y) < 2.5:
			var d2 := Bodies.box_depth(pb, boxes[i])
			if d2 > 0.25:
				var key2 := "ap:%d" % i
				now[key2] = true
				if not _pairs.has(key2):
					_count("check: bodies overlapping, autodrive and a car")
					_incident("autodrive in a car", g._pos, "%s (%s), %.1f m in; autodrive %.0f km/h, held by %s" % [
						c.kind, c.why, d2, absf(g._v) * 3.6, g._ap_why])
	_pairs = now
	# -- a body into a building, a wall (fence, hedge, garden wall) or a post (tree, pole,
	# bollard): traffic is on rails, so nothing but the lane it was given keeps it out
	# Once an occasion: a bus brushing a row of street trees is one, not one a tree; it is
	# over when that car has been clear of everything for a second.
	if _tick % 6 == 0:
		for i: int in boxes:
			var c = cars[i]
			if absf(c.y - g._h(c.pos)) > 2.5:
				continue   # (on a bridge, in a tunnel)
			var hit: Array = Bodies.into_solid(g, boxes[i])
			if float(hit[0]) > 0.2:
				var key := "%d" % i
				if _tick - int(_in_solid.get(key, -100000)) > 60:
					var kind := String(hit[1]).split(" ")[0]
					_count("check: traffic body into a " + kind)
					_incident("traffic into a " + kind, c.pos, "%s (%s, %.0f km/h), %.1f m into %s" % [
						c.kind, c.why, c.v * 3.6, float(hit[0]), hit[1]])
					if _watch_r > 0.0 and c.pos.distance_to(_at) <= _watch_r:
						var what := String(hit[1])
						var where_s := ""
						if what.begins_with("post "):
							var pi := int(what.split(" ")[1])
							var on: Dictionary = g._nearest_seg(g._posts[pi], 20.0, true)
							where_s = " -- the post at (%.1f, %.1f), r %.2f, %.2f m %s the asphalt's edge" % [g._posts[pi].x, g._posts[pi].y,
								g._post_r[pi], absf(float(on.get("edge", 99.0))), "inside" if float(on.get("edge", 99.0)) < 0.0 else "outside"]
						print("    %s%s" % [_car_line(i), where_s])
				_in_solid[key] = _tick
		if absf(g._y - g._h(g._pos)) < 2.5 and _watch_r <= 0.0:   # (watching: the car is only parked by the kerb)
			var hit2: Array = Bodies.into_solid(g, pb)
			# (the car is two circles to the game: its corners run a little into what it
			# brushes, so only past 0.3 m)
			if float(hit2[0]) > 0.3:
				if _tick - int(_in_solid.get("ap", -100000)) > 60:
					var kind2 := String(hit2[1]).split(" ")[0]
					_count("check: autodrive body into a " + kind2)
					_incident("autodrive into a " + kind2, g._pos, "%.1f m into %s at %.0f km/h, held by %s" % [
						float(hit2[0]), hit2[1], absf(g._v) * 3.6, g._ap_why])
				_in_solid["ap"] = _tick
	# -- standing at a red, held by the light, with the front over the stop line. Only a car
	# that came to its stop for the light: one that stopped for people on a crossing a little
	# past its line, and saw the light go red meanwhile, is held by the light too (and rightly
	# waits where it stands) -- the first version counted those
	for i: int in boxes:
		var c = cars[i]
		if c.v < 0.3:
			if not _stop_why.has(i):
				_stop_why[i] = c.why
		else:
			_stop_why.erase(i)
	for i: int in _stop_why.keys():
		if not boxes.has(i):
			_stop_why.erase(i)
	for i: int in boxes:
		var c = cars[i]
		if c.v > 0.3 or c.why != "light" or _stop_why.get(i, "") != "light":
			continue
		for j in range(c.k + 1, c.pts.size()):
			var dist: float = c.cum[j] - c.s
			if dist > 60.0:
				break
			var n: int = c.node[j]
			if not g._sig_set.has(n):
				continue
			var dir: Vector2 = T._came(c, j)
			var way: Array = g._way_in(n, dir)
			if way.is_empty() or way[3]:
				continue
			var over: float = float(way[1]) - (dist - c.len * 0.5)
			var key := "%d:%d" % [i, n]
			if over > 1.0 and g._light_at(n, dir) == "r" and _tick - int(_over.get(key, -100000)) > 3600:
				_over[key] = _tick
				_count("check: over the line at a red, traffic")
				_incident("over the line", c.pos, "%s, its front %.1f m past the stop line" % [c.kind, over])
			break
	if absf(g._v) < 0.3:
		if _ap_stop_why == "":
			_ap_stop_why = g._ap_why
	else:
		_ap_stop_why = ""
	if absf(g._v) < 0.3 and g._auto and g._ap_why == "light" and _ap_stop_why == "light":
		var f: Vector2 = g._fwd()
		var nose: Vector2 = g._pos + f * g.CAR_LEN * 0.5
		var best := INF
		var bn := -1
		var bway: Array = []
		for n: int in g._near(g._sig_hash, g._pos, 40.0, g.SEG_CELL):
			var way: Array = g._way_in(n, f)
			if way.is_empty() or way[3]:
				continue
			var rel: Vector2 = g._nodes[n] - g._pos
			var w0: Vector2 = way[0]
			if rel.dot(w0) <= 0.0 or absf(rel.cross(w0)) > g._node_r[n] + 8.0:
				continue   # behind, or off to the side: not the one it waits at
			if rel.dot(w0) < best:
				best = rel.dot(w0)
				bn = n
				bway = way
		if bn >= 0:
			var w1: Vector2 = bway[0]
			var over2: float = (nose - (g._nodes[bn] - w1 * float(bway[1]))).dot(w1)
			var key4 := "ap:%d" % bn
			if over2 > 1.0 and g._light_at(bn, w1) == "r" and _tick - int(_over.get(key4, -100000)) > 3600:
				_over[key4] = _tick
				_count("check: over the line at a red, autodrive")
				_incident("autodrive over the line", g._pos, "its nose %.1f m past the stop line" % over2)
	# -- pushing: foot on the gas against something, not moving; backing off and pushing
	# again is the same occasion until the car gets 4 m away (or is lifted elsewhere)
	var pushing: bool = g._auto and g._ap_back <= 0.0 and g._ap_turn <= 0.0 and g._ap_stuck > 0.3
	if pushing:
		if _push_at == Vector2.INF:
			_push_at = g._pos
		_push_s += dt
		if _push_s >= 3.0 and not _push_counted:
			_push_counted = true
			_count("check: autodrive pushing 3 s+")
			_incident("pushing", g._pos, "against %s" % g._last_hit)
	if _push_at != Vector2.INF and g._pos.distance_to(_push_at) > 4.0:
		_push_at = Vector2.INF
		_push_s = 0.0
		_push_counted = false
	# -- standing 10 s with nothing named holding it (down the queue to whoever is at its front).
	# A slot whose car was taken away and put down elsewhere is a new car: its time starts
	# again (the old one's standing carried over into the new one's)
	for i: int in boxes:
		var c = cars[i]
		if _last_pos.has(i) and (_last_pos[i] as Vector2).distance_to(c.pos) > 15.0:
			_stand.erase(i)
			_stop_why.erase(i)
		_last_pos[i] = c.pos
	for i: int in boxes:
		var c = cars[i]
		if c.v < 0.3:
			_stand[i] = float(_stand.get(i, 0.0)) + dt
			if absf(float(_stand[i]) - 10.0) < dt * 0.5:
				var ch: Array = _chain(i)
				if not ch[0]:
					_count("check: held by nothing 10 s+, traffic")
					var front = T.cars[int(ch[2])] if ch.size() > 2 else c
					_incident("held by nothing", c.pos, "%s; the front one wants %.1f m/s, stood %.0f s, %.0f m from the player%s" % [
						" > ".join(ch[1]), front.want, front.still, front.pos.distance_to(g._pos),
						", out of view" if not T._in_view(front.pos) else ""])
		else:
			_stand.erase(i)
	for i: int in _stand.keys():
		if not boxes.has(i):
			_stand.erase(i)
	if g._auto and absf(g._v) < 0.3:
		_ap_stand += dt
		if absf(_ap_stand - 10.0) < dt * 0.5:
			var why: String = g._log._why(g)
			var parts: Array = ["autodrive (%s)" % why]
			var named := why in NAMED
			if why == "car":
				var lead: Array = T.lead_on(g._ap_pts, g._pos, maxf(g._ap_lead, 0.0) + 1.0, g._ap_wait > 3.0)
				if int(lead[3]) >= 0:
					var ch2: Array = _chain(int(lead[3]))
					named = ch2[0]
					parts.append_array(ch2[1])
				else:
					parts.append("no car ahead")
			if not named:
				_count("check: held by nothing 10 s+, autodrive")
				_incident("autodrive held by nothing", g._pos, " > ".join(parts))
	else:
		_ap_stand = 0.0

## what holds traffic car i, down the queue: [named?, ["sedan 4 (car)", "bus 9 (light)"]].
## Not named: the limit or a curve at a standstill, a car that is gone, or a loop.
func _chain(i: int) -> Array:
	var parts: Array = []
	var seen := {}
	while true:
		var c = T.cars[i]
		if seen.has(i):
			parts.append("a loop")
			return [false, parts]
		seen[i] = true
		if not c.alive:
			parts.append("a car that is gone")
			return [false, parts]
		if c.hit > 0.0:
			parts.append("%s %d (stunned by a hit)" % [c.kind, i])
			return [true, parts]
		if c.v < 0.3 and c.want > 0.5 and c.react_t < c.react and not c.why in ["car", "player"]:
			# wants to go, standing only for its moment to notice: its reaction still running
			# (the front of a queue at a light gone green reads "limit" then). The first version
			# took that for nothing at all; the second excused only cars that had stood under
			# 4 s, so one that waited 10 s at a red and had its green that tick read as held by
			# nothing (four in one exam); one that has reacted and still stands is not excused
			parts.append("%s %d (pulling away)" % [c.kind, i])
			return [true, parts, i]
		parts.append("%s %d (%s)" % [c.kind, i, c.why])
		if c.why == "car" and c.v < 0.3:
			if c.blocker < 0 or c.blocker >= T.cars.size():
				parts.append("no car")
				return [false, parts]
			i = c.blocker
			continue
		return [c.why in NAMED or c.why == "car" or c.v > 0.3, parts, i]
	return [false, parts]
