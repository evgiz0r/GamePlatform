extends SceneTree
## The light poles _build_signals put up in its second round of spots (where every spot at the
## corner was a wall, a lane or a corner's asphalt: further onto the pavement, the left kerb,
## nearer the junction, or across it as a far-side light), seen as a driver coming in sees
## them: the camera on the way in, BACK m (default 22) short of the junction, at a driver's
## eye, facing in. Prints each pole (where, which side, how far past the junction's middle)
## and saves $OUT/far_<n>.png for the first N (default 4). Needs a renderer (not --headless).
##   LEVEL=7 OUT=dir STREETS_BUILD_ALL=1 $GODOT --path . -s res://game/streets/tests/far_lights.gd
## Good: each pole on a pavement, facing the way in, plain to see from the driver's seat.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.2,0,-2")
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	var far: Array = g._light_far
	print("poles from the second round: %d" % far.size())
	var back := float(OS.get_environment("BACK")) if OS.get_environment("BACK") != "" else 22.0
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 4
	g._car.visible = false
	for i in range(far.size()):
		var p: Vector2 = far[i][0]
		var c: Vector2 = far[i][1]
		var dir: Vector2 = far[i][2]
		var past := (p - c).dot(dir)
		var side := (p - c).dot(Vector2(-dir.y, dir.x))
		print("  %d: pole %s, junction %s, %.1f m %s of the way in's middle, %.1f m %s the junction's middle" % [i, p.round(),
			c.round(), absf(side), "right" if side > 0.0 else "left", absf(past), "past" if past > 0.0 else "short of"])
		if i >= n or OS.get_environment("OUT") == "":
			continue
		var at := c - dir * back + Vector2(-dir.y, dir.x) * 1.8
		for _k in 12:
			g._pos = at
			g._prev_pos = at
			g._yaw = atan2(dir.y, dir.x)
			g._v = 0.0
			await process_frame
		await _snap("far_%d" % i)
	quit(0)
