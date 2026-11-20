extends SceneTree
## The raised medians down the middle of wide main roads, from a driver's seat: each place a
## median ends (at a junction or a zebra) and each bend it goes round, from 20 m back in the
## right-hand lane. Prints where; shots in OUT (MAX, default 8).
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var spots: Array = []   # [where, facing, what]
	var n_med := 0
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r.has("mid"):
			continue
		n_med += 1
		var pts: PackedVector2Array = r["pts"]
		for k in range(1, pts.size() - 1):
			var d_in := (pts[k] - pts[k - 1]).normalized()
			var d_out := (pts[k + 1] - pts[k]).normalized()
			if absf(d_in.angle_to(d_out)) > deg_to_rad(25.0):
				spots.append([pts[k], d_in, "bend %d deg on '%s'" % [int(rad_to_deg(d_in.angle_to(d_out))), r["name"]]])
		for run: PackedVector2Array in g._street_runs(r, g.KERB_CUT, true):
			var dir := (run[run.size() - 1] - run[run.size() - 2]).normalized()
			spots.append([run[run.size() - 1] + dir * 4.0, dir, "median end on '%s'" % r["name"]])
	print("roads with a median: %d; places to look: %d" % [n_med, spots.size()])
	for s: Array in spots:
		print("  %s at %s" % [s[2], (s[0] as Vector2).round()])
	if OS.get_environment("OUT") == "":
		quit(0)
		return
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var most := int(OS.get_environment("MAX")) if OS.get_environment("MAX") != "" else 8
	var shot := 0
	for s: Array in spots:
		var at: Vector2 = s[0]
		var dir: Vector2 = s[1]
		var right := Vector2(-dir.y, dir.x)
		var eye := at - dir * 20.0 + right * 2.5
		var y: float = g._h(eye)
		g.look_from(Vector3(eye.x, y + 2.2, eye.y), Vector3(at.x, g._h(at) + 0.5, at.y))
		await _snap("median_%d" % shot)
		shot += 1
		if shot >= most:
			break
	quit(0)
