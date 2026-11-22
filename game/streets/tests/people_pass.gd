extends SceneTree
## People passing each other (streets.gd's walkers): the street left to run for $SECS (40) of
## game time with you standing still, every pair of walkers (not a walker and their mate)
## closer than 0.5 m between their middles logged -- the bodies overlap below ~0.45 -- with how
## close and for how long. Prints each meeting, the counts, and a shot of the closest
## (pp_closest.png) from beside it, in $OUT.
## Good: no pair under 0.4 m; meetings under 0.5 m short (a brush past, < 0.5 s).
##   OUT=... game/streets/tests/run.sh people_pass 1
var g: Node

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
	await create_timer(2.0).timeout
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 40.0
	var t := 0.0
	var open := {}       # "i|j" -> [start t, min d, where]
	var done := []       # [min d, length s, where]
	var worst := [INF, Vector3.ZERO, null, null]
	while t < secs:
		await process_frame
		t += g.get_process_delta_time()
		var ws: Array = g._walkers
		var seen := {}
		for i in range(ws.size()):
			var a: Node3D = ws[i]["actor"]
			if not a.visible:
				continue
			for j in range(i + 1, ws.size()):
				var b: Node3D = ws[j]["actor"]
				if not b.visible or int(ws[i].get("mate", -1)) == b.get_instance_id() or int(ws[j].get("mate", -1)) == a.get_instance_id():
					continue
				var d := Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length()
				if d < 0.5 and absf(a.position.y - b.position.y) < 1.0:
					var k := "%d|%d" % [i, j]
					seen[k] = true
					if not open.has(k):
						open[k] = [t, d, a.position]
					open[k][1] = minf(open[k][1], d)
					if d < worst[0]:
						worst = [d, (a.position + b.position) * 0.5, a, b]
		for k: String in open.keys():
			if not seen.has(k):
				done.append([open[k][1], t - float(open[k][0]), open[k][2]])
				open.erase(k)
	for k: String in open:
		done.append([open[k][1], t - float(open[k][0]), open[k][2]])
	var under4 := 0
	var long := 0
	for m: Array in done:
		print("meeting: %.2f m apart at closest, %.2f s under 0.5 m, at %s" % [m[0], m[1], m[2]])
		if float(m[0]) < 0.4:
			under4 += 1
		if float(m[1]) > 0.5:
			long += 1
	print("PASS %d meetings under 0.5 m in %.0f s of %d walkers: %d under 0.4 m, %d longer than 0.5 s" % [done.size(), secs, g._walkers.size(), under4, long])
	if worst[2] != null:
		var c: Vector3 = worst[1] + Vector3(0, 1.0, 0)
		var a: Node3D = worst[2]
		var b: Node3D = worst[3]
		var across := Vector3(a.position.z - b.position.z, 0, b.position.x - a.position.x).normalized()
		if across == Vector3.ZERO:
			across = Vector3.RIGHT
		g.set_physics_process(false)
		process_frame.disconnect(g._frame)
		g.look_from(c + across * 3.0 + Vector3(0, 0.5, 0), c)
		g._sky_follow()
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/pp_closest.png")
	quit(0)
