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
	for key: String in ["night_shutters", "roof_dishes", "roof_aerials", "roof_acs", "solar"]:
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
	# walk at the nearest flock on the ground: it must go up
	var target: Dictionary = {}
	for fl: Dictionary in g._birds.flocks:
		if not fl["up"] and (target.is_empty() or (fl["c"] as Vector2).distance_to(stand) < (target["c"] as Vector2).distance_to(stand)):
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
	var ok: bool = most >= 3 and on_road == 0 and in_wall == 0 and pops == 0 and flew and bad_extras == 0 \
		and int(nx["escooters"]) > 100 and int(nx["night_shutters"]) > 100 and int(nx["roof_dishes"]) > 100
	print("REGRESS small_life: %s (flocks down %d want 3+; birds on the asphalt %d, in a wall %d, landed in view %d want 0; walked-at flock up %s; e-scooters %d, gas cages %d, on the asphalt %d want 0; fountains %d, night shutters %d, roof dishes %d)" % [
		"PASS" if ok else "FAIL", most, on_road, in_wall, pops, flew, int(nx["escooters"]), int(nx["gas_cages"]), bad_extras, int(nx["fountains"]), int(nx["night_shutters"]), int(nx["roof_dishes"])])
	quit()
