extends SceneTree
## The island where a divided road meets a street at lights: Ashdod's start, Sderot Herzl x
## HeHalutzim (level 3). From above the junction, three ways round. Bad: white spikes and
## an arrowhead of pavement sticking out of the median's end into the road (a corner laid
## straight across where the cross street goes through the median, then cut up where it
## lay on asphalt). Good: the median's pavement stops short of the crossing, clean.
## Prints how many corners were left out because a road went through them.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout   # draw ranges settle after a camera move
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 3})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	print("corners left out across a road: ", g._dressing.get("corners_across_roads", 0))
	# frozen for stills: the game's own camera would move it back every frame
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var c := Vector2(-1772, 2250)   # the middle of the junction's four light points
	var views := [["n_e", Vector2(18, -26)], ["s_w", Vector2(-20, 24)], ["e", Vector2(30, 4)]]
	for v: Array in views:
		var off: Vector2 = v[1]
		var eye := Vector3(c.x + off.x, g._h(c) + 9.0, c.y + off.y)
		g.look_from(eye, Vector3(c.x, g._h(c), c.y))
		await _snap("nose_" + String(v[0]))
	quit()
