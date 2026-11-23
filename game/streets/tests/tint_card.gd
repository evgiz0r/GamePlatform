extends SceneTree
## The scene's colour cast (a "slight pink over everything"): two neutral grey cards (albedo 0.5,
## no colour, fully rough) in front of the car, one lying in the sun, one standing in its own
## shadow facing you; prints each card's colour on screen and the lights' colours (the sun, the
## shade's ambient, the fog). Shot tint.png.
## Good: the sunlit card warm (r >= g >= b, a little) and the shaded one cool (b >= g >= r) --
## never green the lowest of the three (a magenta, pink cast).
##   OUT=... game/streets/tests/run.sh tint_card 1
var g: Node

func _initialize() -> void:
	_run()

func _px(img: Image, p: Vector2) -> Color:
	var c := Color(0, 0, 0)
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			c += img.get_pixel(clampi(int(p.x) + dx, 0, img.get_width() - 1), clampi(int(p.y) + dy, 0, img.get_height() - 1))
	return c / 49.0

func _cast(c: Color) -> String:
	var lo := "r" if c.r <= c.g and c.r <= c.b else ("g" if c.g <= c.b else "b")
	return "%3d %3d %3d (lowest %s, g-(r+b)/2 %+.1f)" % [c.r8, c.g8, c.b8, lo, (c.g - (c.r + c.b) * 0.5) * 255.0]

func _run() -> void:
	create_timer(300.0).timeout.connect(func(): print("TIMEOUT"); quit(1))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(2.0).timeout
	print("loaded")
	var p: Vector2 = g._pos
	var fw := Vector3(cos(g._yaw), 0, sin(g._yaw))
	var rt := fw.cross(Vector3.UP)
	var base := Vector3(p.x, g._h(p), p.y) + fw * 5.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.5, 0.5).srgb_to_linear().linear_to_srgb()
	m.roughness = 1.0
	m.metallic_specular = 0.0
	var sunlit := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 0.04, 1.2)
	bm.material = m
	sunlit.mesh = bm
	g.world.add_child(sunlit)
	sunlit.global_position = base - rt * 1.6 + Vector3(0, 0.3, 0)
	# the standing one in a box's shade: a roof over it
	var shaded := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.0, 1.0, 0.04)
	sm.material = m
	shaded.mesh = sm
	g.world.add_child(shaded)
	shaded.global_position = base + rt * 0.9 + Vector3(0, 0.6, 0)
	shaded.look_at(shaded.global_position - fw, Vector3.UP)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(1.6, 0.1, 1.6)   # (over the standing card alone)
	roof.mesh = rm
	g.world.add_child(roof)
	roof.global_position = shaded.global_position + Vector3(0, 1.4, 0) - g.sun.global_transform.basis.z * 0.0
	# (its shade falls where the sun says: the roof moved back along the sun's way down)
	var down: Vector3 = g.sun.global_transform.basis.z   # (the light shines along -z: towards the sun is +z)
	if down.y > 0.05:
		roof.global_position = shaded.global_position + down / down.y * 1.4
	print("cards up")
	await create_timer(0.5).timeout
	process_frame.disconnect(g._frame)
	var eye := base - fw * 3.5 + Vector3(0, 1.7, 0)
	g.look_from(eye, base + Vector3(0, 0.8, 0))
	g._sky_follow()
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("OUT") + "/tint.png")
	var cam: Camera3D = g.cam
	var k := Vector2(img.get_size()) / Vector2(cam.get_viewport().get_visible_rect().size)   # (the 3D view is a viewport of its own)
	print("sun card:   ", _cast(_px(img, cam.unproject_position(sunlit.global_position + Vector3(0, 0.03, 0)) * k)))
	print("shade card: ", _cast(_px(img, cam.unproject_position(shaded.global_position - fw * 0.03) * k)))
	print("sun light:  ", _cast(g.sun.light_color), " x%.2f" % g.sun.light_energy)
	print("ambient:    ", _cast(g.env.ambient_light_color), " x%.2f" % g.env.ambient_light_energy)
	print("fog:        ", _cast(g.env.fog_light_color))
	print("ink:        ", _cast(root.get_node("Palette").col("ink")))
	quit(0)
