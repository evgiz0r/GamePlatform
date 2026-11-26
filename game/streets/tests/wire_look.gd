extends SceneTree
## The overhead wires from the street (24 Nov 2026): the span nearest the start (furniture.gd's
## perches), looked at from 8 and 15 m beside it, up. They were one-sided ribbons merged into
## the square's batch, whose shader culls back faces: from the street they did not show at all,
## and pigeons sat in a row on nothing. Good: three dark wires across wire_15.png, from the pole.
##   OUT=/tmp/w FULL=1 RES=1280x720 game/streets/tests/run.sh wire_look 1
##   (headless, STREETS_BUILD_ALL=1: prints the span and the nearest pole, 0.75 m from its end)
var g: Node
func _initialize() -> void:
	_run()
func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.6,0,0")
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while not g._tiles_todo.is_empty():
		await create_timer(0.5).timeout
	g._car.visible = false
	print("cable colour ", g._tone.get("cable"), " mat ", g._surface("cable"))
	var best: Array = []
	for k in g._furn.perches:
		for sp: Array in g._furn.perches[k]:
			var m := Vector2((sp[0] as Vector3).x + (sp[1] as Vector3).x, (sp[0] as Vector3).z + (sp[1] as Vector3).z) * 0.5
			if best.is_empty() or m.distance_to(g._pos) < (best[1] as Vector2).distance_to(g._pos):
				best = [sp, m]
	var sp: Array = best[0]
	var a: Vector3 = sp[0]
	var e: Vector3 = sp[1]
	print("span ", a, " -> ", e)
	var mid: Vector2 = best[1]
	var poles: Array = g._furn.where.get("power_poles", [])
	var near := INF
	for xf: Transform3D in poles:
		near = minf(near, Vector2(xf.origin.x, xf.origin.z).distance_to(Vector2(a.x, a.z)))
	print("poles ", poles.size(), " nearest to the span's end ", near, " ground there ", g._h(Vector2(a.x, a.z)), " start ", g._pos, " eye y ", g._h(mid))
	if DisplayServer.get_name() == "headless":
		quit()
		return
	var dir := Vector2(e.x - a.x, e.z - a.z).normalized()
	var side := dir.orthogonal()
	for d: float in [8.0, 15.0]:
		var p := mid + side * d
		g._dev_cam[2] = 1.6
		g._dev_cam[4] = 25.0 if d < 10.0 else 15.0
		for i in 5:
			g._pos = p
			g._prev_pos = p
			g._yaw = (mid - p).angle()
			g._prev_yaw = g._yaw
			await process_frame
		await RenderingServer.frame_post_draw
		g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/wire_%d.png" % int(d))
	quit()
