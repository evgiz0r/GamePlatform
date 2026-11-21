extends SceneTree
## The street's goings-on (traffic.gd "the street's goings-on"), on autodrive from the start:
## 1. a van sent onto the player's street ahead to make a delivery 25 m on: when it stands
##    (hazards), who goes round it (traffic cars over the centre line, autodrive: pass_van),
##    how long autodrive stood behind it, and the nearest anything came to its body;
## 2. a car set to pull out ahead (its timer run down): where it was parked, when it pulled
##    out, how near the player's car came to it after, and whether they touched -- and the
##    one getting in beside its driver first (put there by hand if the dice said no): their
##    door open, when they got in (the player how far behind), the door shut, the car backing
##    up with its reversing lights, then out; the nearest the player came while the door was
##    open (it should be shut well before).
## Good: the van stands 25-50 s with hazards; autodrive goes round it within a few seconds
## when nothing comes (or waits, then goes); nothing drives through it; the parked car pulls
## out with the player 18-45 m behind and they never touch. Run it headless.
var g: Node
var tr

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	tr = g._traffic
	g._set_auto(true)
	await create_timer(3.0).timeout
	await _run_rest()

func _delivery(label: String, ri: int) -> void:
	var vi := -1
	for i in range(tr.cars.size()):
		var c = tr.cars[i]
		if (c.kind == "van" or c.kind == "truck") and (not c.alive or c.pos.distance_to(g._pos) > 60.0) and c.dbl_s < 0.0:
			vi = i
			break
	if vi < 0:
		print("no van or truck among the traffic")
		return
	var van = tr.cars[vi]
	var hit: Dictionary
	var r: Dictionary
	var p: PackedVector2Array
	var dir := 1
	var ahead := 45.0
	var sent_behind := false
	if ri < 0:
		hit = g._nearest_seg(g._pos, 8.0, true, true)
		r = g._roads[hit["road"]]
		p = r["pts"]
		dir = 1 if (p[int(hit["seg"]) + 1] - p[hit["seg"]]).dot(g._fwd()) >= 0.0 else -1
	else:   # the player put at the street's start, facing along it, the van 110 m on
		r = g._roads[ri]
		p = r["pts"]
		var st := p[0].lerp(p[1], 0.1) if p[0].distance_to(p[1]) > 10.0 else p[0]
		g._set_auto(false)
		g._pos = st
		g._yaw = (p[1] - p[0]).angle()
		g._snap_pose()
		g._v = 0.0
		await physics_frame
		g._set_auto(true)
		hit = g._nearest_seg(g._pos, 8.0, true, true)
		dir = 1
		ahead = 110.0
		sent_behind = true
	var spot: Array = tr._along_road(p, hit["seg"], hit["q"], dir, ahead)
	if spot.is_empty() or not tr._start_on(van, hit["road"], spot[1], spot[0], dir):
		print("%s: no room for the van ahead" % label)
		return
	van.alive = true
	van.dbl_s = 20.0
	van.dbl = 35.0
	print("%s: a %s sent %d m ahead on %s (%s, %d lane(s) each way), to stop 20 m on" % [label, van.kind, int(ahead), r.get("name", "?"), r["k"], g._lanes_each_way(r)])
	if sent_behind:   # a car between the player and it
		var bspot: Array = tr._along_road(p, hit["seg"], hit["q"], dir, 60.0)
		if not bspot.is_empty() and tr.send(bspot[0], (p[1] - p[0]) * float(dir)):
			print("   and a car sent in 60 m ahead of the player, behind the van")
	var t := 0.0
	var stood_at := -1.0
	var hazards_seen := false
	var rounders := {}
	var ap_wait := 0.0
	var nearest := INF
	var passed_at := -1.0
	while t < 75.0:
		await physics_frame
		var dt := 1.0 / 60.0
		t += dt
		var standing: bool = tr._parked_double(van)
		if stood_at < 0.0 and standing:
			stood_at = t
			print("%5.1f s  the %s stands, %d m ahead of the player" % [t, van.kind, int(van.pos.distance_to(g._pos))])
		hazards_seen = hazards_seen or (standing and van.blink == 2)
		for j in range(tr.cars.size()):
			var c = tr.cars[j]
			if c.pass_i == vi and not rounders.has(j):
				rounders[j] = true
				print("%5.1f s  a %s goes round it, over the centre line" % [t, c.kind])
			if j != vi and c.alive and standing:
				nearest = minf(nearest, c.pos.distance_to(van.pos))
		var rel: Vector2 = van.pos - g._pos
		if standing and absf(g._v) < 0.3 and rel.length() < 25.0 and rel.dot(g._fwd()) > 0.0 and g._ap_why == "car":
			ap_wait += dt
			if absf(ap_wait - 3.0) < dt * 0.5:   # (what holds it: once, three seconds in)
				var lead: Array = tr.lead_on(g._ap_pts, g._pos, 40.0, false, g._y)
				var lat := INF
				for k in range(g._ap_pts.size() - 1):
					lat = minf(lat, Geometry2D.get_closest_point_to_segment(van.pos, g._ap_pts[k], g._ap_pts[k + 1]).distance_to(van.pos))
				var li: int = int(lead[3])
				print("   held 3 s: by car %d (%s, the van is %d) at %.1f m; the van's middle %.2f m off autodrive's path; passed %d; turn ahead %d" % [
					li, tr.cars[li].kind if li >= 0 else "-", vi, float(lead[0]), lat, g._ap_passed, g._ap_turn_ahead()])
		if passed_at < 0.0 and g._ap_passed == vi:
			passed_at = t
			print("%5.1f s  autodrive goes round it (stood %.1f s behind first)" % [t, ap_wait])
		if stood_at >= 0.0 and not standing and van.dbl_s < 0.0:
			print("%5.1f s  the %s goes on (stood %.0f s)" % [t, van.kind, t - stood_at])
			break
	if stood_at < 0.0:
		print("   the van never stood (held by: %s)" % van.why)
	print("   hazards seen: %s; cars that went round over the line: %d; nearest a car's middle came to the van's: %.1f m; autodrive stood behind it %.1f s" % [hazards_seen, rounders.size(), nearest, ap_wait])

func _run_rest() -> void:
	if OS.get_environment("KERB_ONLY") != "":
		await _kerb_street()
		await _kerb_part()
		return
	# 1. a delivery van ahead, on the start's street
	await _delivery("the start's street", -1)
	# ... and on a street of one lane each way, a car sent in between: over the centre line
	var best := -1
	for ri in range(g._roads.size()):
		var rr: Dictionary = g._roads[ri]
		var pp: PackedVector2Array = rr["pts"]
		if String(rr["k"]) != "residential" or int(rr["o"]) != 0 or g._lanes_each_way(rr) != 1 or not rr["drive"]:
			continue
		var L := 0.0
		for k in range(pp.size() - 1):
			L += pp[k].distance_to(pp[k + 1])
		if L > 190.0 and pp[0].distance_to(g._pos) < 260.0:
			best = ri
			break
	if best < 0:
		print("no residential street of one lane each way, 190 m long, near the start")
	else:
		await _delivery("a one-lane street", best)
	await _kerb_part()

## KERB_ONLY: the player put at the start of a long residential street of one lane each way
## with cars parked along it, on autodrive, for the kerb car alone
func _kerb_street() -> void:
	var best := -1
	var best_d := INF
	for ri in range(g._roads.size()):
		var rr: Dictionary = g._roads[ri]
		var pp: PackedVector2Array = rr["pts"]
		if String(rr["k"]) != "residential" or int(rr["o"]) != 0 or g._lanes_each_way(rr) != 1 or not rr["drive"]:
			continue
		var L := 0.0
		for k in range(pp.size() - 1):
			L += pp[k].distance_to(pp[k + 1])
		var parked := 0
		for pi: int in g._near(g._post_hash, pp[0].lerp(pp[pp.size() - 1], 0.5), 30.0, g.BLD_CELL):
			if is_equal_approx(float(g._post_r[pi]), 0.85):
				parked += 1
		var d: float = pp[0].distance_to(g._pos)
		if L > 280.0 and parked >= 10 and d < best_d:
			best = ri
			best_d = d
	if best < 0:
		print("no long residential street with parked cars")
		return
	var r: Dictionary = g._roads[best]
	var p: PackedVector2Array = r["pts"]
	var st := p[0].lerp(p[1], 0.1) if p[0].distance_to(p[1]) > 10.0 else p[0]
	g._set_auto(false)
	g._pos = st
	g._yaw = (p[1] - p[0]).angle()
	g._snap_pose()
	g._v = 0.0
	await physics_frame
	g._set_auto(true)
	print("the player put at the start of %s (%d m from the start), on autodrive" % [r.get("name", "?"), int(best_d)])
	for k in range(120):   # (up to speed first: the kerb car waits for a car moving 4 m/s)
		await physics_frame

func _kerb_part() -> void:
	# 2. a car pulling out ahead
	var seen := false
	var out_at := -1.0
	var ki := -1
	var closest := INF
	var touched := false
	var boarded := false
	var shut := false
	var backed := false
	var door_near := INF
	var t2 := 0.0
	while t2 < 90.0:
		if ki < 0 and int(t2 * 60.0) % 120 == 0:
			tr._kerb_t = 0.0   # (one now, if the street allows)
		await physics_frame
		t2 += 1.0 / 60.0
		if ki < 0:
			for j in range(tr.cars.size()):
				if tr.cars[j].kerb:
					ki = j
					var c = tr.cars[j]
					print("%5.1f s  a %s parked at the kerb %d m ahead (%.1f m off the lane line)" % [t2, c.kind, int(c.pos.distance_to(g._pos)), -c.shift])
					if c.door <= 0.0:   # (the dice said nobody: someone put there, for the test)
						var stand: Vector2 = tr._board_spot(c, 0.0)
						if g.boarder_at(stand, Vector2(cos(c.yaw), -sin(c.yaw)), false):
							c.door = 1.0
							c.passenger = false
							print("        (someone put at its door for the test)")
					print("        its door open: %s, someone at it: %s" % [c.door > 0.0, (g._boarders[0]["actor"] as Node3D).visible if not g._boarders.is_empty() else false])
		else:
			var c = tr.cars[ki]
			var behind: float = -(g._pos - c.pos).dot(Vector2(sin(c.yaw), cos(c.yaw)))
			if c.door > 0.0:
				door_near = minf(door_near, c.pos.distance_to(g._pos))
			if not boarded and c.passenger and c.board_t > 0.0:
				boarded = true
				print("%5.1f s  they get in (the player %d m behind)" % [t2, int(behind)])
			if boarded and not shut and c.door <= 0.0:
				shut = true
				print("%5.1f s  the door shut" % t2)
			if not backed and c.rev_t > 0.0:
				backed = true
				print("%5.1f s  it backs up, reversing lights on (the player %d m behind)" % [t2, int(behind)])
			if out_at < 0.0 and not c.kerb:
				out_at = t2
				var rel: Vector2 = g._pos - c.pos
				print("%5.1f s  it signals and pulls out, the player %d m behind at %d km/h" % [t2, int(-rel.dot(Vector2(sin(c.yaw), cos(c.yaw)))), int(absf(g._v) * 3.6)])
			if out_at >= 0.0:
				closest = minf(closest, c.pos.distance_to(g._pos))
				if String(g._last_hit) == "car %d" % ki:
					touched = true
				if t2 - out_at > 15.0:
					break
	if ki < 0:
		print("no car could be parked ahead in 90 s (the streets driven: not a residential one with parking, or no gap)")
	else:
		print("after it pulled out: the player's car came within %.1f m of its middle; touched: %s" % [closest, touched])
		print("while its door was open the player came within %.1f m of it" % door_near)
	quit(0)
