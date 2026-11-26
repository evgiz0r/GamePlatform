extends SceneTree
## Every furniture model the flat uses, in a row, seen from +Z (the side a piece should face
## the room with). Good: you see fronts -- the sofa's seat, the TV's screen, the stove's
## knobs -- not backs.  OUT=/tmp/shots tests/run.sh models
func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): quit(1))
	var vp := root
	var w := Node3D.new()
	vp.add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.3, 0.35)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	w.add_child(sun)
	var names := []
	for f in DirAccess.get_files_at("res://assets/models/furniture"):
		if f.ends_with(".glb"):
			names.append(f.get_basename())
	var cols := 8
	for i in names.size():
		var s: PackedScene = load("res://assets/models/furniture/%s.glb" % names[i])
		var n: Node3D = s.instantiate()
		n.position = Vector3((i % cols) * 1.3, 0, (i / cols) * -1.6)
		w.add_child(n)
		var l := Label3D.new()
		l.text = names[i]
		l.font_size = 24
		l.pixel_size = 0.004
		l.position = n.position + Vector3(0, -0.12, 0.4)
		w.add_child(l)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(4.5, 3.2, 4.5)
	cam.look_at(Vector3(4.5, 0, -2.5))
	cam.current = true
	for k in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/models.png")
	quit(0)
