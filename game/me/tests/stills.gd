extends SceneTree
## Stills of one scene at chosen moments, to check a pose without recording a video:
##   LEVEL=3 AT="1,2.5,6" xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
##     --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 -s res://game/me/tests/stills.gd
## Writes shots/me_<scene>_<t>.png (shots/ is gitignored).

func _initialize() -> void:
	_run()

func _run() -> void:
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	var at: Array = []
	for s in (OS.get_environment("AT") if OS.get_environment("AT") != "" else "1,3").split(","):
		at.append(float(s))
	await create_timer(0.3).timeout
	var flow = root.get_node("Flow")
	flow.start_game("me", {"level": level})
	var g: Node = null
	while g == null:
		await process_frame
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("/me.gd"):
				g = n
	g.film_mode(true)
	flow._layer.visible = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	for want: float in at:
		while g.t < want:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := "res://shots/me_%s_%04.1f.png" % [g.scene, want]
		img.save_png(p)
		print("SHOT ", p, " t=", g.t)
	quit(0)
