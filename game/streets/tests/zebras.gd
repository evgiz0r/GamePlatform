extends SceneTree
## People at the zebras over 60 s of autodrive: crossings started and finished, times the
## player's car was called out, seconds autodrive and traffic stood for someone crossing.
## Then a look at someone mid-crossing.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)
func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_auto(true)
	var started := 0
	var finished := 0
	var backs := 0
	var ap_wait := 0.0
	var car_wait := 0.0
	var last := {}
	var t := 0.0
	var shot := false
	while t < 60.0:
		await physics_frame
		t += 1.0 / 60.0
		for i in range(g._crossers.size()):
			var st: String = g._crossers[i]["state"]
			var was: String = last.get(i, "off")
			if st != was:
				if st == "cross":
					started += 1
				elif st == "back":
					backs += 1
				elif st == "away" and was == "cross":
					finished += 1
			last[i] = st
		if not shot:
			for cr in g._crossers:
				if cr["state"] == "cross" and float(cr["s"]) > 0.4 and float(cr["s"]) < 0.6:
					shot = true
					process_frame.disconnect(g._frame)
					var z: Array = g._zebra_geom(int(cr["ni"]))
					var mid: Vector2 = z[0]
					var d: Vector2 = z[3]
					var eye: Vector2 = mid - d * 10.0 + (z[1] as Vector2) * 1.2
					g.look_from(Vector3(eye.x, g._h(eye) + 1.7, eye.y), Vector3(mid.x, g._h(mid) + 0.9, mid.y))
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/z_live_%d.png" % lvl)
					print("shot live")
					process_frame.connect(g._frame)
					break
		if g._ap_zebra_v() < 1.0 and absf(g._v) < 0.5:
			ap_wait += 1.0 / 60.0
		for c in g._traffic.cars:
			if c.alive and c.v < 0.3 and g._traffic._zebra_ahead(c) < 0.5:
				car_wait += 1.0 / 60.0
	var extra := 0.0
	while extra < 30.0:
		var any := false
		for cr in g._crossers:
			if cr["state"] == "cross" and float(cr["s"]) > 0.3 and float(cr["s"]) < 0.7:
				any = true
		if any:
			break
		await physics_frame
		extra += 1.0 / 60.0
	print("60 s: crossings started %d, finished %d, hurried back %d; autodrive stood %.1f s, traffic stood %.1f car-s for crossers" % [started, finished, backs, ap_wait, car_wait])
	g._set_auto(false)
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	for cr in g._crossers:
		if cr["state"] == "cross":
			var z: Array = g._zebra_geom(int(cr["ni"]))
			var mid: Vector2 = z[0]
			var d: Vector2 = z[3]
			var eye: Vector2 = mid - d * 11.0 + (z[1] as Vector2) * 1.5
			g._pos = eye
			g.look_from(Vector3(eye.x, g._h(eye) + 1.8, eye.y), Vector3(mid.x, g._h(mid) + 0.9, mid.y))
			await _snap("z_%d" % lvl)
			break
	quit(0)
