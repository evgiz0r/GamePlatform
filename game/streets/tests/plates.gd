extends SceneTree
## The number plates up close (CAR_SHADER's plate, its digits from _plate_font): your car's
## back from the chase view, then the parked cars nearest the start from 3 m behind and
## in front -- each a number of its own, made up -- and from its side, three quarters on (its
## wheels, doors, roof fittings, wear) (shots plate_*.png in $OUT).
##   FULL=1 STREETS_BUILD_ALL=0 RES=1280x720 OUT=<dir> game/streets/tests/run.sh plates 1
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
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
	await create_timer(1.0).timeout
	await _snap("plate_chase")
	# the parked cars: their end posts (0.85 m, 2.8 m apart, one after the other)
	var cars: Array = []
	for i in range(g._posts.size() - 1):
		if is_equal_approx(g._post_r[i], 0.85) and is_equal_approx(g._post_r[i + 1], 0.85) \
				and absf(g._posts[i].distance_to(g._posts[i + 1]) - 2.8) < 0.02:
			cars.append([(g._posts[i] + g._posts[i + 1]) * 0.5, (g._posts[i] - g._posts[i + 1]).normalized()])
	var start: Vector2 = g._pos
	cars.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(start) < (b[0] as Vector2).distance_to(start))
	print("parked cars: %d" % cars.size())
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	for k in range(mini(3, cars.size())):
		var c: Vector2 = cars[k][0]
		var u: Vector2 = cars[k][1]
		for end: float in [1.0, -1.0]:
			var plate := c + u * end * 2.25
			var eye := c + u * end * 5.2
			var y: float = g._h(c)
			g.look_from(Vector3(eye.x, y + 1.0, eye.y), Vector3(plate.x, y + 0.55, plate.y))
			g._sky_follow()
			await _snap("plate_%d_%s" % [k, "a" if end > 0.0 else "b"])
		# and from its side, three quarters on (its wheels, doors, roof, the dust on it)
		var side := Vector2(-u.y, u.x)
		for sd: float in [1.0, -1.0]:
			var eye2 := c + side * sd * 4.2 + u * 1.6
			if g._push_out(eye2, 0.3, false) != Vector2.ZERO:
				continue   # (a wall there)
			var y2: float = g._h(c)
			g.look_from(Vector3(eye2.x, y2 + 1.5, eye2.y), Vector3(c.x, y2 + 0.7, c.y))
			g._sky_follow()
			await _snap("plate_%d_side" % k)
			break
	print("shots in ", OS.get_environment("OUT"))
	quit()
