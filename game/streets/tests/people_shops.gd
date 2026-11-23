extends SceneTree
## In and out of the shops (streets.gd _shop_try / _shop_visit), and the shop doors: first 40 s
## of the car standing still among the shops, counting visits begun on their own and finished;
## then one visit staged -- the walker nearest a door near you sent in -- filmed from across the
## pavement: sh_0 on the way, sh_1 gone in, sh_2 come out, sh_3 back on the pavement. sh_door is
## a door close up.
## Good: some visits on their own (a few in 40 s on a street of shops), each ended back on the
## pavement; the staged one goes to, in, back, turn (on the spot) and on; the door a dark frame on the glass.
##   OUT=... game/streets/tests/run.sh people_shops 1   (the test town has too few walkers by its shops)
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(2.0).timeout
	print("doors: %d in the town, %d near" % [g._shop_doors.size(), g._doors_near.size()])
	if g._shop_doors.is_empty():
		print("no shops")
		quit(0)
		return
	# the car among the most doors: by the door with the most others within 40 m
	var best := -1
	var at: Vector2 = g._pos
	for d: Array in g._shop_doors:
		var n := 0
		for e: Array in g._shop_doors:
			if (e[0] as Vector2).distance_to(d[0]) < 40.0:
				n += 1
		if n > best:
			best = n
			at = (d[0] as Vector2) + (d[1] as Vector2) * 6.0
	g._pos = at
	g._prev_pos = at
	g._v = 0.0
	g._snap_pose()
	await create_timer(3.0).timeout
	var begun := 0
	var ended := 0
	var was := {}
	var passes := {}   # walker/door -> the nearest it came
	var t := 0.0
	while t < 40.0:
		await create_timer(0.25).timeout
		t += 0.25
		g._v = 0.0
		for w: Dictionary in g._walkers:
			var id: int = (w["actor"] as Node3D).get_instance_id()
			var now := w.has("shop")
			if now and not was.get(id, false):
				begun += 1
			if not now and was.get(id, false):
				ended += 1
			was[id] = now
			var wp := Vector2((w["actor"] as Node3D).position.x, (w["actor"] as Node3D).position.z)
			if (w["actor"] as Node3D).visible:
				for di in range(g._doors_near.size()):
					var k := "%d/%d" % [id, di]
					passes[k] = minf(float(passes.get(k, INF)), wp.distance_to(g._doors_near[di][0]))
	print("on their own, 40 s among %d doors: %d visits begun, %d ended" % [best, begun, ended])
	var bands := [0, 0, 0, 0]
	for k: String in passes:
		var l: float = passes[k]
		for b in range(4):
			if l < [2.0, 3.2, 5.0, 8.0][b]:
				bands[b] += 1
				break
	print("walkers passing a door: within 2 m %d, 2-3.2 m %d, 3.2-5 m %d, 5-8 m %d" % bands)
	# one staged
	var w: Dictionary = {}
	var door: Array = []
	var bd := INF
	for c: Dictionary in g._walkers:
		var a: Node3D = c["actor"]
		if not a.visible or c.has("with") or c.has("mate") or c.has("shop") or c.has("dog") or c.has("pram"):
			continue
		var p := Vector2(a.position.x, a.position.z)
		for d: Array in g._doors_near:
			var l := p.distance_to(d[0])
			if l < bd and l > 2.0:
				bd = l
				w = c
				door = d
	if w.is_empty():
		print("no walker near a door")
		quit(0)
		return
	var a: Node3D = w["actor"]
	var from := Vector2(a.position.x, a.position.z)
	w["shop"] = {"door": door[0], "out": door[1], "from": from, "phase": "to", "t": 0.0}
	var out: Vector2 = door[1]
	var dq: Vector2 = door[0]
	var mid: Vector2 = (from + dq) * 0.5
	var eye := Vector3(dq.x, g._h(dq) + 1.3, dq.y) + Vector3(out.x, 0, out.y) * 8.0 + Vector3(-out.y, 0, out.x) * 3.0   # (low and out past the awnings and the parked cars)
	var look := Vector3(dq.x, g._h(dq) + 1.0, dq.y)
	process_frame.disconnect(g._frame)
	var phases := []
	var shots := 0
	t = 0.0
	g.look_from(eye, look)
	g._sky_follow()
	await _snap("sh_0")
	while t < 70.0 and shots < 4:
		await process_frame
		t += g.get_process_delta_time()
		var ph: String = (w["shop"] as Dictionary)["phase"] if w.has("shop") else "done"
		if phases.is_empty() or phases[-1] != ph:
			phases.append(ph)
			print("  %.1f s: %s" % [t, ph])
			if ph in ["in", "back", "done"]:
				if ph == "in":
					await create_timer(0.3).timeout
				shots += 1
				g.look_from(eye, look)
				g._sky_follow()
				await _snap("sh_%d" % shots)
				if ph == "done":
					await create_timer(1.0).timeout
					g.look_from(eye, look)
					await _snap("sh_%d" % (shots + 1))
					shots = 9
		if ph == "in":   # (the time inside cut short)
			(w["shop"] as Dictionary)["t"] = minf(float((w["shop"] as Dictionary)["t"]), 0.5)
	var dc: Vector3 = Vector3(dq.x, g._h(dq) + 1.1, dq.y)
	g.look_from(dc + Vector3(out.x, 0, out.y) * 2.4 + Vector3(0, 0.3, 0), dc)
	g._sky_follow()
	await _snap("sh_door")
	var ok := phases == ["to", "in", "back", "turn", "done"]
	print("staged: %s -- %s" % [" -> ".join(phases), "ok" if ok else "WRONG"])
	print("PASS doors %d, visits begun %d ended %d, staged %s" % [g._shop_doors.size(), begun, ended, "ok" if ok else "wrong"])
	quit(0)
