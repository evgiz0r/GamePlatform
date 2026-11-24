extends SceneTree
## The small things on the pavements (24 Nov 2026): pigeons and crows (birds.gd) and the
## shared e-scooters and gas cages (furniture.gd's street_extras). The eye stood on a
## pavement a while, counting the flocks that land round it and checking every frame that no
## bird on the ground is on the asphalt or in a wall and that none landed in plain view;
## then walked at the nearest flock, which must go up; the e-scooters and cages counted and
## checked off the asphalt. Shots when drawn: a flock up close, e-scooters, a gas cage.
##
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 10 --path . -s res://game/streets/tests/small_life.gd
##   FULL=1 RES=1280x720 OUT=/tmp/sl game/streets/tests/run.sh small_life 7
##
## Good (level 7): 4-6 flocks down within a minute, birds on the asphalt 0, in a wall 0,
## landed in view 0; the flock walked at goes up within 2 s; e-scooters some thousands, gas
## cages hundreds, none on the asphalt. Ends in one REGRESS line.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

var on_road := 0
var in_wall := 0
var pops := 0
var low_perch := 0
var _seen := {}
var _last_p := Vector2.ZERO

func _frame(p: Vector2, yaw: float) -> void:
	g._pos = p
	g._prev_pos = p
	g._yaw = yaw
	g._prev_yaw = yaw
	g._v = 0.0
	# (the eye set down somewhere new this frame: a flock landed out of sight of where it was is
	# not a landing in view -- nobody jumps 50 m)
	var jump := p.distance_to(_last_p) > 3.0
	_last_p = p
	await process_frame
	for fl: Dictionary in g._birds.flocks:
		var id: int = fl["id"]
		if not _seen.has(id):
			_seen[id] = true
			if not jump and not g._spawn_ok(fl["c"]):
				pops += 1
				print("  landed in view at %s, %.0f m off" % [fl["c"].round(), (fl["c"] as Vector2).distance_to(p)])
		if fl["up"]:
			continue
		if fl.get("perch", false):   # (on a wire: high over the ground, over the road as like as not)
			for bd: Dictionary in fl["birds"]:
				if float(bd["h"]) - float(g._h(bd["p"])) < 4.0:
					low_perch += 1
			continue
		for bd: Dictionary in fl["birds"]:
			var q: Vector2 = bd["p"]
			if not g._off_road(q, 0.0):
				on_road += 1
			if g._push_out(q, 0.05, false, false) != Vector2.ZERO:
				in_wall += 1

func _view(name: String, p: Vector2, at: Vector2, up: float, tilt: float) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = tilt
	for i in 4:
		await _frame(p, (at - p).angle())
	await _snap(name)

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.6,0,0")
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while not g._tiles_todo.is_empty():
		await create_timer(0.5).timeout
	g._car.visible = false
	g._night = false
	# the extras: counted, and none of them on the asphalt
	var bad_extras := 0
	var nx := {}
	for name: String in ["escooters", "gas_cages"]:
		var xs: Array = g._furn.where.get(name, [])
		nx[name] = xs.size()
		for xf: Transform3D in xs:
			if not g._off_road(Vector2(xf.origin.x, xf.origin.z), 0.0):
				bad_extras += 1
	nx["fountains"] = (g._furn.where.get("fountains", []) as Array).size()
	var mapped_pts: int = (g._city_data.get("street_points", []) as Array).size() / 3
	for key: String in ["post_boxes", "drinking_taps", "bumps"]:
		nx[key] = (g._furn.where.get(key, []) as Array).size()
	nx["street_points_in_file"] = mapped_pts
	for xf: Transform3D in g._furn.where.get("post_boxes", []) + g._furn.where.get("drinking_taps", []):
		if not g._off_road(Vector2(xf.origin.x, xf.origin.z), 0.0):
			bad_extras += 1
	var bumps_off := 0   # a bump's middle must be on its road's asphalt
	for bm: Array in g.bumps:
		if g._off_road(bm[0], 0.0):
			bumps_off += 1
	nx["bumps_off_the_road"] = bumps_off
	for key: String in ["night_shutters", "roof_dishes", "roof_aerials", "roof_acs", "solar", "balcony_plants", "towels"]:
		nx[key] = int(g._dressing.get(key, 0))
	print("extras: ", nx, ", on the asphalt ", bad_extras)
	# on a pavement near the start: the start point's nearest street, onto its pavement
	var start: Vector2 = g._pos
	var hit: Dictionary = g._nearest_seg(start, 60.0, true, true)
	var stand := start
	var along := Vector2.RIGHT
	if not hit.is_empty():
		var r: Dictionary = g._roads[hit["road"]]
		var q: Vector2 = hit["q"]
		var pts: PackedVector2Array = r["pts"]
		along = (pts[int(hit["seg"]) + 1] - pts[int(hit["seg"])]).normalized()
		stand = q + Vector2(-along.y, along.x) * (float(r["w"]) * 0.5 + 1.5)
	g._dev_cam[2] = 1.7
	g._dev_cam[4] = -2.0
	var most := 0
	var secs := float(OS.get_environment("STAY")) if OS.get_environment("STAY") != "" else 60.0
	for i in range(int(secs * 10.0)):
		await _frame(stand, along.angle() + (PI if (i / 100) % 2 == 1 else 0.0))
		var down := 0
		for fl: Dictionary in g._birds.flocks:
			if not fl["up"]:
				down += 1
		most = maxi(most, down)
	print("birds: flocks down at most %d; %s; on the asphalt %d, in a wall %d, landed in view %d" % [most, g._birds.count, on_road, in_wall, pops])
	var n_spans := 0
	for k in g._furn.perches:
		n_spans += (g._furn.perches[k] as Array).size()
	print("birds on wires: %d flocks perched (of %d wires' spans), birds under 4 m up %d" % [int(g._birds.count["perched"]), n_spans, low_perch])
	# walk at the nearest flock on the ground: it must go up
	var target: Dictionary = {}
	for i in range(100):   # (none on the ground just now: wait up to 10 s for one to land)
		if g._birds.flocks.any(func(f: Dictionary) -> bool: return not f["up"] and not f.get("perch", false)):
			break
		await _frame(stand, along.angle())
	for fl: Dictionary in g._birds.flocks:
		if not fl["up"] and not fl.get("perch", false) and (target.is_empty() or (fl["c"] as Vector2).distance_to(stand) < (target["c"] as Vector2).distance_to(stand)):
			target = fl
	var flew := false
	var shot_done := false
	if not target.is_empty():
		var c: Vector2 = target["c"]
		await _view("pigeons", c + (stand - c).normalized() * 9.0, c, 1.4, -6.0)
		shot_done = true
		var p := c + (stand - c).normalized() * 12.0
		for i in range(40):
			p = p.move_toward(c, 0.15)   # (1.5 m/s)
			await _frame(p, (c - p).angle())
			if target["up"]:
				flew = true
				break
		for i in 6:
			await _frame(p, (c - p).angle())
		await _snap("pigeons_up")
	print("the flock walked at went up: %s" % flew)
	for fl: Dictionary in g._birds.flocks:
		if fl.get("perch", false) and not fl["up"]:
			var c: Vector2 = fl["c"]
			var b0: Dictionary = fl["birds"][0]
			var from := c + Vector2(cos(float(b0["yaw"])), sin(float(b0["yaw"]))).orthogonal() * 3.0 + (c - stand).normalized() * -8.0
			await _view("pigeons_wire", from, c, 1.6, 26.0)
			break
	# shots of the extras
	for name: String in ["escooters", "gas_cages"]:
		var xs: Array = g._furn.where.get(name, [])
		if xs.is_empty():
			continue
		var o: Vector3 = (xs[xs.size() / 2] as Transform3D).origin
		var at := Vector2(o.x, o.z)
		var h2: Dictionary = g._nearest_seg(at, 20.0, true, true)
		var from := at + Vector2(6, 0)
		if not h2.is_empty():
			var q: Vector2 = h2["q"]
			var pts: PackedVector2Array = g._roads[h2["road"]]["pts"]
			var t: Vector2 = (pts[int(h2["seg"]) + 1] - pts[int(h2["seg"])]).normalized()
			from = q - t * 6.0 + (at - q) * 0.3
		await _view(name, from, at, 1.6, 4.0)
	# a fountain; the roofs from above; a shopping street by night, its shutters down
	var fx: Array = g._furn.where.get("fountains", [])
	if not fx.is_empty():
		var o: Vector3 = (fx[0] as Transform3D).origin
		await _view("fountain", Vector2(o.x, o.z) + Vector2(7, 4), Vector2(o.x, o.z), 1.6, -2.0)
	for name: String in ["bumps", "post_boxes"]:
		var bx: Array = g._furn.where.get(name, [])
		if not bx.is_empty():
			var o: Vector3 = (bx[bx.size() / 2] as Transform3D).origin
			var at := Vector2(o.x, o.z)
			var hh: Dictionary = g._nearest_seg(at, 20.0, true, true)
			var from := at + Vector2(8, 0)
			if not hh.is_empty():
				var pts: PackedVector2Array = g._roads[hh["road"]]["pts"]
				var t: Vector2 = (pts[int(hh["seg"]) + 1] - pts[int(hh["seg"])]).normalized()
				from = (hh["q"] as Vector2) - t * 10.0
			await _view(name, from, at, 1.5, -4.0)
	var pl: Array = g.wall_things.get("plants", [])
	if not pl.is_empty():
		var bt: Transform3D = pl[pl.size() / 2]
		var out3: Vector3 = bt.basis.z
		var b2 := Vector2(bt.origin.x, bt.origin.z)
		var from := b2 + Vector2(out3.x, out3.z) * 12.0
		await _view("balconies", from, b2, maxf(bt.origin.y - g._h(from) - 1.0, 1.6), 0.0)
	await _view("asphalt", stand - Vector2(-along.y, along.x) * 1.0, stand + along * 25.0, 1.6, -14.0)
	await _view("roofs", stand, stand + along * 60.0, 40.0, -30.0)
	if g._pois.size() > 0 and DisplayServer.get_name() != "headless":
		g._set_night(true)
		var sh: Array = g._shop_lights
		var best := stand
		if not sh.is_empty():
			best = (sh[sh.size() / 2] as Array)[0]
		var hh: Dictionary = g._nearest_seg(best, 30.0, true, true)
		if not hh.is_empty():
			var q: Vector2 = hh["q"]
			var pts: PackedVector2Array = g._roads[hh["road"]]["pts"]
			var t: Vector2 = (pts[int(hh["seg"]) + 1] - pts[int(hh["seg"])]).normalized()
			await _view("shops_night", q - t * 20.0, q + t * 10.0 + (best - q) * 0.8, 1.7, 0.0)
		g._set_night(false)
	# Shabbat (24 Nov): a Saturday by day in an Israeli town, the shops that stay open late
	# shut too; a Sunday, they open
	var shab_n := int(g._dressing.get("shabbat_shutters", 0))
	var shab_ok := true
	if g._country() == "il":
		g._weekday = 6
		g._update_day()
		var up_sat: bool = g._shabbat_now() and g._night_shut_nodes.all(func(n: Node3D) -> bool: return n.visible) \
			and g._shabbat_shut_nodes.all(func(n: Node3D) -> bool: return n.visible) and g._traffic.cap == g.SHABBAT_CARS
		if DisplayServer.get_name() != "headless" and g._pois.size() > 0:
			var sh: Array = g._shop_lights
			var best: Vector2 = (sh[sh.size() / 2] as Array)[0] if not sh.is_empty() else stand
			var hh: Dictionary = g._nearest_seg(best, 30.0, true, true)
			if not hh.is_empty():
				var q: Vector2 = hh["q"]
				var pts: PackedVector2Array = g._roads[hh["road"]]["pts"]
				var t: Vector2 = (pts[int(hh["seg"]) + 1] - pts[int(hh["seg"])]).normalized()
				await _view("shabbat", q - t * 20.0, q + t * 10.0 + (best - q) * 0.8, 1.7, 0.0)
		g._weekday = 0
		g._update_day()
		var open_sun: bool = not g._shabbat_now() and g._night_shut_nodes.all(func(n: Node3D) -> bool: return not n.visible) \
			and g._shabbat_shut_nodes.all(func(n: Node3D) -> bool: return not n.visible) and g._traffic.cap == g._traffic.COUNT
		# Friday night: the windows of the shops shut for Shabbat light no pavement; Thursday's do
		if not g._pools_made:
			g._make_pools()
		g._night = true
		g._weekday = 5
		g._update_day()
		var dark_fri: bool = g._shabbat_dark_nodes.all(func(n: Node3D) -> bool: return not n.visible)
		g._weekday = 4
		g._update_day()
		var lit_thu: bool = g._shabbat_dark_nodes.all(func(n: Node3D) -> bool: return n.visible)
		g._night = false
		g._weekday = 0
		g._update_day()
		print("shabbat window light: %d nodes, dark friday night %s, lit thursday night %s" % [g._shabbat_dark_nodes.size(), dark_fri, lit_thu])
		shab_ok = up_sat and open_sun and shab_n > 20 and dark_fri and lit_thu and not g._shabbat_dark_nodes.is_empty()
		print("shabbat: %d shutters that close only on shabbat; saturday all down and the streets quiet %s, sunday all up and full %s" % [shab_n, up_sat, open_sun])
	# a car over a speed bump: lifted 8 cm with both axles on top of a table, tipped nose up
	# with only its front on a bump
	var lift_ok := true
	if not g.bumps.is_empty():
		var bm: Array = g.bumps[g.bumps.size() / 2]
		var bq: Vector2 = bm[0]
		var bd: Vector2 = bm[1]
		var half: float = g.WHEELBASE * 0.5
		var on_front: Vector2 = g.bump_lift(bq + bd * 0.0, bq - bd * g.WHEELBASE)
		var clear: Vector2 = g.bump_lift(bq + bd * 6.0, bq + bd * 6.0 - bd * g.WHEELBASE)
		lift_ok = absf(on_front.x - 0.08) < 0.001 and on_front.y == 0.0 and clear == Vector2.ZERO
		print("bump lift: front wheels on it %s, clear of it %s" % [on_front, clear])
		if DisplayServer.get_name() != "headless":
			g._car.visible = true
			var side := Vector2(-bd.y, bd.x)
			var cp := bq - bd * half
			g._pos = cp
			g._yaw = bd.angle()
			g._pose_car(cp, bd.angle())
			var eye := cp + side * 6.5 + bd * 1.0
			g._dev_cam[2] = 0.9
			g._dev_cam[4] = -4.0
			for i in 3:
				g._pos = eye
				g._prev_pos = eye
				g._yaw = (cp - eye).angle()
				g._prev_yaw = g._yaw
				g._pose_car(cp, bd.angle())
				await process_frame
			await _snap("car_on_bump")
			g._car.visible = false
	var ok: bool = shab_ok and lift_ok and low_perch == 0 and most >= 3 and on_road == 0 and in_wall == 0 and pops == 0 and flew and bad_extras == 0 \
		and int(nx["escooters"]) > 100 and int(nx["night_shutters"]) > 100 and (g._country() != "il" or int(nx["roof_dishes"]) > 100) and bumps_off == 0 \
		and (mapped_pts == 0 or int(nx["post_boxes"]) + int(nx["drinking_taps"]) + int(nx["bumps"]) > 0)
	print("REGRESS small_life: %s (shabbat %s, bump lift %s; perched %d, low %d want 0; flocks down %d want 3+; birds on the asphalt %d, in a wall %d, landed in view %d want 0; walked-at flock up %s; e-scooters %d, gas cages %d, on the asphalt %d want 0; fountains %d, night shutters %d, roof dishes %d; post boxes %d, taps %d, bumps %d, off the road %d want 0)" % [
		"PASS" if ok else "FAIL", shab_ok, lift_ok, int(g._birds.count["perched"]), low_perch, most, on_road, in_wall, pops, flew, int(nx["escooters"]), int(nx["gas_cages"]), bad_extras, int(nx["fountains"]), int(nx["night_shutters"]), int(nx["roof_dishes"]),
		int(nx["post_boxes"]), int(nx["drinking_taps"]), int(nx["bumps"]), bumps_off])
	quit()
