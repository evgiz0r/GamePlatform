extends SceneTree
## The shadows past the real ones (the game's _build_far_shadows / far_shade): the picture of
## the whole city's building shadows it paints at load (far_shadow_map.png), then the same
## views with them on and off -- down the street from a driver's height, and over the city
## from 60 m up and from the zoom-out's 165 m -- at the top quality (real shadows to 75 m, these past them) and the lowest
## (no real shadows: these everywhere). EVENING=1: in the evening's light. Prints the stage's load time and how much of each
## picture they darkened. Shots far_<view>_q<quality>_on/off.png in $OUT.
var g: Node

func _initialize() -> void:
	_run()

func _shot() -> Image:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func _switch(on: bool) -> void:
	for m: ShaderMaterial in g._far_mats:
		m.set_shader_parameter("fs_dark", (g.FS_DARK_EVE if g._evening else g.FS_DARK) if on else 0.0)

func _ab(name: String, eye: Vector3, tgt: Vector3) -> void:
	g.look_from(eye, tgt)
	g._sky_follow()
	_switch(true)
	var on: Image = await _shot()
	_switch(false)
	var off: Image = await _shot()
	_switch(true)
	on.save_png(OS.get_environment("OUT") + "/far_%s_on.png" % name)
	off.save_png(OS.get_environment("OUT") + "/far_%s_off.png" % name)
	var darker := 0
	var n := 0
	for y in range(0, on.get_height(), 4):
		for x in range(0, on.get_width(), 4):
			n += 1
			if off.get_pixel(x, y).get_luminance() - on.get_pixel(x, y).get_luminance() > 0.02:
				darker += 1
	print("%s: %.1f%% of the picture darker" % [name, 100.0 * darker / n])

## how much a kind of shadow leaves of the light: the middle of shadowed / unshadowed over
## the pixels it darkened by more than 15% (the real and the painted should match)
func _ratio(name: String, img: Image, none: Image) -> void:
	var r: Array = []
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var a := img.get_pixel(x, y).get_luminance()
			var b := none.get_pixel(x, y).get_luminance()
			if b > 0.05 and a < b * 0.85:
				r.append(a / b)
	r.sort()
	print("%s shadows: %d pixels, they leave %.2f of the light (middle), %.2f-%.2f (quartiles)" % [name, r.size(),
		r[r.size() / 2] if not r.is_empty() else 0.0, r[r.size() / 4] if not r.is_empty() else 0.0, r[r.size() * 3 / 4] if not r.is_empty() else 0.0])

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("EVENING") == "1":   # the evening's sun and shadows instead
		await g._set_evening(true)
		await create_timer(0.5).timeout
	print("far shadows: built in %d ms, %d of it work (the rest frames), picture %s" % [int(g._stage_ms.get("far shadows", -1)),
		int(g._stage_ms.get("far shadows: work, not the frames", -1)), g._fs_tex.get_size() if g._fs_tex != null else "none"])
	if g._fs_tex != null:
		var img: Image = g._fs_tex.get_image()
		img.resize(img.get_width() / 2, img.get_height() / 2)
		img.save_png(OS.get_environment("OUT") + "/far_shadow_map.png")
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	var p: Vector2 = g._pos
	var f: Vector2 = g._fwd()
	# the same block from above: the real shadows alone (these off), then these alone (the
	# sun's shadows switched off): they should fall in the same places
	var up := Vector3(p.x - f.x * 20.0, g._h(p) + 45.0, p.y - f.y * 20.0)
	var down := Vector3(p.x + f.x * 15.0, g._h(p), p.y + f.y * 15.0)
	g.look_from(up, down)
	g._sky_follow()
	g._set_quality(3)
	_switch(false)
	await create_timer(0.5).timeout
	(await _shot()).save_png(OS.get_environment("OUT") + "/far_check_real.png")
	g.sun.shadow_enabled = false
	g._far_update()
	(await _shot()).save_png(OS.get_environment("OUT") + "/far_check_painted.png")
	_switch(false)   # and neither: how dark each makes the ground (see _ratio)
	var none: Image = await _shot()
	none.save_png(OS.get_environment("OUT") + "/far_check_none.png")
	_ratio("real", Image.load_from_file(OS.get_environment("OUT") + "/far_check_real.png"), none)
	_ratio("painted", Image.load_from_file(OS.get_environment("OUT") + "/far_check_painted.png"), none)
	g._set_quality(3)
	# the longest straight piece of a main road near the start, looked along from a car
	var best_len := 0.0
	var long_a := p
	var long_d := f
	for r: Dictionary in g._roads:
		if not r["drive"] or not (String(r["k"]) in ["primary", "secondary", "tertiary"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		for i in range(pts.size() - 1):
			var L := pts[i].distance_to(pts[i + 1])
			if L > best_len and pts[i].distance_to(p) < 600.0:
				best_len = L
				long_a = pts[i]
				long_d = (pts[i + 1] - pts[i]) / L
	print("a straight %d m long" % int(best_len))
	for q: int in [3, 0]:
		g._set_quality(q)
		var la := long_a + long_d * 5.0
		await _ab("long_q%d" % q, Vector3(la.x, g._h(la) + 2.2, la.y), Vector3(la.x + long_d.x * 200.0, g._h(la + long_d * 200.0) + 1.0, la.y + long_d.y * 200.0))
		var e := p - f * 6.0
		await _ab("street_q%d" % q, Vector3(e.x, g._h(e) + 3.2, e.y), Vector3(p.x + f.x * 80.0, g._h(p + f * 80.0), p.y + f.y * 80.0))
		var hi := p - f * 120.0
		await _ab("over_q%d" % q, Vector3(hi.x, g._h(hi) + 60.0, hi.y), Vector3(p.x + f.x * 200.0, g._h(p), p.y + f.y * 200.0))
		var zo := p - f * 150.0   # (about where the zoom-out button puts the camera)
		await _ab("zoom_q%d" % q, Vector3(zo.x, g._h(zo) + 165.0, zo.y), Vector3(p.x, g._h(p), p.y))
	quit(0)
