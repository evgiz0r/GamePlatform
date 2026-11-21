extends SceneTree
## The people in Tel Aviv's market and on its beach (crowds.gd): the eye stood in the Carmel
## market's walkway and then on the sand by the water, a while each (turned away first, as
## you would arrive), counting who is there and checking each frame that nobody stands in a
## stall's post or a wall, that nobody walking the shore is in the sea, and that nobody
## appears in plain view. Shots too, when drawn.
##
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 10 --path . -s res://game/streets/tests/seaside_people.gd
##   STAY=0.3 FULL=1 STREETS_BUILD_ALL=1 RES=1280x720 OUT=/tmp/sp game/streets/tests/run.sh seaside_people 7
##
## Good: the market's lines and stops found (HaCarmel's pieces, ~200 stops); in the market
## 10-15 shoppers within 40 m after a minute and some stopped at stalls; on the beach a few
## walkers/joggers and waders within 90 m; 0 in a post, 0 walkers in the sea, 0 popping in.
## Ends in one REGRESS line. (No Actor3D named in here: a test script that names it compiles
## shell/actor3d.gd before the autoloads exist, and every Actor3D.new() in the game fails.)
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

var bad_post := 0
var bad_sea := 0
var pops := 0
var _was := {}

func _frame(p: Vector2, yaw: float) -> void:
	g._pos = p
	g._prev_pos = p
	g._yaw = yaw
	g._prev_yaw = yaw
	g._v = 0.0
	await process_frame
	for w: Dictionary in g._crowd.everyone():
		var a: Node3D = w["actor"]
		var id := a.get_instance_id()
		var q := Vector2(a.position.x, a.position.z)
		if a.visible and not bool(_was.get(id, false)) and not g._spawn_ok(q):
			pops += 1
			print("  pop: %s at %s, %.0f m off" % [w.get("kind", "wader"), q.round(), q.distance_to(p)])
		_was[id] = a.visible
		if not a.visible or q.distance_to(p) > 90.0:
			continue
		if w.has("kind") and g._push_out(q, 0.12, true, false) != Vector2.ZERO:
			bad_post += 1
		if String(w.get("kind", "")) == "shore":
			for sea: PackedVector2Array in _seas:
				if Geometry2D.is_point_in_polygon(q, sea):
					bad_sea += 1

var _seas: Array = []
## STAY=0.3 for the shots: drawn, a frame here takes a second or more, and the full stays ran 40 min
var _scale := float(OS.get_environment("STAY")) if OS.get_environment("STAY") != "" else 1.0

func _census(p: Vector2, label: String) -> Dictionary:
	var n40 := 0
	var n90 := 0
	var stopped := 0
	var kinds := {}
	for w: Dictionary in g._crowd.everyone():
		var a: Node3D = w["actor"]
		if not a.visible:
			continue
		var d := Vector2(a.position.x, a.position.z).distance_to(p)
		if d < 90.0:
			n90 += 1
			var k: String = w.get("kind", "wader")
			if w.get("run", false):
				k = "jogger"
			kinds[k] = int(kinds.get(k, 0)) + 1
		if d < 40.0:
			n40 += 1
		if float(w.get("stop_t", 0.0)) > 0.0:
			stopped += 1
	print("%s: within 40 m %d, within 90 m %d %s, at a stall now %d" % [label, n40, n90, kinds, stopped])
	return {"n40": n40, "n90": n90, "stopped": stopped, "kinds": kinds}

func _stay(p: Vector2, at: Vector2, secs: float, label: String) -> Dictionary:
	secs *= _scale
	var yaw := (at - p).angle()
	for i in range(int(secs * 0.4 * 10.0)):   # (arriving: looking the other way)
		await _frame(p, yaw + PI)
	var best := {}
	for i in range(int(secs * 0.6 * 10.0)):
		await _frame(p, yaw)
		if i % 50 == 49:
			best = _census(p, label + " %.0f s" % (secs * 0.4 + (i + 1) / 10.0))
	return best

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
	for a: Dictionary in g._city_data.get("areas", []):
		if String(a["k"]) == "water" and a.has("y") and a.has("_ring"):
			_seas.append(a["_ring"])
	var stops := 0
	for ln: Dictionary in g._crowd.lines:
		stops += (ln["stops"] as Array).size()
	print("crowd lines: ", g._crowd.count, ", stops ", stops)
	g._car.visible = false
	g._dev_cam[2] = 1.7
	g._dev_cam[4] = -2.0
	var t0 := Time.get_ticks_msec()
	var mid := Vector2(-2078, 701)
	var along := Vector2(-0.77, 0.63)
	while not g._tiles_todo.is_empty():   # (every square built: the stalls and chairs come with theirs)
		await create_timer(0.5).timeout
	var m := await _stay(mid, mid + along * 30.0, 70.0, "market")
	await _snap("market_people")
	g._dev_cam[2] = 9.0
	g._dev_cam[4] = -18.0
	for i in 3:
		await _frame(mid - along * 14.0, along.angle())
	await _snap("market_people_above")
	g._dev_cam[2] = 1.7
	g._dev_cam[4] = -2.0
	# on the sand: a point up from the water near the seaside test's shore, facing along it
	var shore := Vector2(-2468, 0)
	var best: Array = []
	for ln: Dictionary in g._crowd.lines:
		if String(ln["kind"]) == "shore":
			for q: Vector2 in (ln["pts"] as PackedVector2Array):
				if best.is_empty() or q.distance_to(shore) < (best[0] as Vector2).distance_to(shore):
					best = [q, ln]
	var b := {}
	if not best.is_empty():
		var q: Vector2 = best[0]
		var pts: PackedVector2Array = best[1]["pts"]
		var dir := (pts[pts.size() - 1] - pts[0]).normalized()
		b = await _stay(q - dir * 10.0, q + dir * 40.0, 60.0, "beach")
		g._dev_cam[4] = -6.0
		var side := Vector2(-dir.y, dir.x)
		for i in 3:
			await _frame(q - dir * 10.0, (dir + side * 0.6).angle())
		await _snap("beach_people")
		for i in 3:
			await _frame(q - dir * 10.0, (dir - side * 0.6).angle())
		await _snap("beach_people_other_way")
	print("counts: ", g._crowd.count, "; stall stops taken ", g._crowd.count.get("stops", 0), "; stalls up ", g._crowd.stalls_up.size(), " (", g._marks.count.get("stalls", 0), " built)")
	print("in a post %d, shore walkers in the sea %d, popped in view %d  (%.0f s)" % [bad_post, bad_sea, pops, (Time.get_ticks_msec() - t0) / 1000.0])
	var ok: bool = int(m.get("n40", 0)) >= 10 and int(g._crowd.count.get("stops", 0)) > 0 and int(b.get("n90", 0)) >= 3 \
		and bad_post == 0 and bad_sea == 0 and pops == 0
	print("REGRESS seaside_people: %s (market within 40 m %d, want 10+; stall stops %d, want 1+; beach within 90 m %d, want 3+; in posts %d, in the sea %d, pops %d, want 0)" % [
		"PASS" if ok else "FAIL", int(m.get("n40", 0)), int(g._crowd.count.get("stops", 0)), int(b.get("n90", 0)), bad_post, bad_sea, pops])
	quit()
