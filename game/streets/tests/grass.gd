extends SceneTree
## The grass blades near the camera: the same views with them and without -- a walker by the
## front gardens of the start street and by the nearest park, and from the car -- and how
## much they changed of each picture. Shots grass_<view>_<on|off>.png in $OUT.
var g: Node

func _initialize() -> void:
	_run()

func _shot() -> Image:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func _ab(name: String, eye: Vector3, tgt: Vector3) -> void:
	g.look_from(eye, tgt)
	g._sky_follow()
	g._grass_kit._grass.visible = true
	g._sky_follow()
	var on: Image = await _shot()
	g._grass_kit._grass.visible = false
	var off: Image = await _shot()
	g._grass_kit._grass.visible = true
	on.save_png(OS.get_environment("OUT") + "/grass_%s_on.png" % name)
	off.save_png(OS.get_environment("OUT") + "/grass_%s_off.png" % name)
	var changed := 0
	var n := 0
	for y in range(0, on.get_height(), 4):
		for x in range(0, on.get_width(), 4):
			n += 1
			if absf(off.get_pixel(x, y).get_luminance() - on.get_pixel(x, y).get_luminance()) > 0.03:
				changed += 1
	print("%s: %.1f%% of the picture changed" % [name, 100.0 * changed / n])

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if g._grass_kit._grass == null:
		print("no grass (no picture of where it grows)")
		quit(0)
		return
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	var p: Vector2 = g._pos
	var f: Vector2 = g._fwd()
	var side := Vector2(-f.y, f.x)
	# a front garden: from the pavement, looking along the gardens
	var hit: Dictionary = g._nearest_seg(p, 60.0, false)
	var walk := p + side * 6.5
	await _ab("garden", Vector3(walk.x, g._h(walk) + 1.6, walk.y), Vector3(walk.x + side.x * 3 + f.x * 8, g._h(walk), walk.y + side.y * 3 + f.y * 8))
	await _ab("garden_other", Vector3(p.x - side.x * 6.5, g._h(p) + 1.6, p.y - side.y * 6.5), Vector3(p.x - side.x * 9.5 + f.x * 8, g._h(p), p.y - side.y * 9.5 + f.y * 8))
	# the nearest park, from its edge
	var best := Vector2.INF
	for ring: PackedVector2Array in g._area_rings.get("park", []) + g._area_rings.get("grass", []):
		var c := Vector2.ZERO
		for q in ring:
			c += q
		c /= maxf(ring.size(), 1)
		if c.distance_to(p) < best.distance_to(p):
			best = c
	if best != Vector2.INF:
		var from := best + (p - best).normalized() * 9.0
		await _ab("park", Vector3(from.x, g._h(from) + 1.6, from.y), Vector3(best.x, g._h(best), best.y))
	# from the car
	await _ab("car", Vector3(p.x - f.x * 7, g._h(p) + 2.6, p.y - f.y * 7), Vector3(p.x + f.x * 30, g._h(p + f * 30), p.y + f.y * 30))
	quit(0)
