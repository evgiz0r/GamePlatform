extends SceneTree
## Filmed spots: the game seen from the places a filmed walk or drive was, to set beside the
## film's own stills. The spots come from a JSON file named by $SPOTS (kept out of the repo:
## a filmed route can start at someone's door) -- a list of
##   {"name": "v040", "x": metres east, "z": metres south, "yaw": radians, "up": 1.35, "tilt": -4}
## in the city file's ground coordinates, yaw as the game's (forward = (cos, sin) on x/z).
## `up` (eye height, default 1.35 m: a phone held at the chest) and `tilt` (degrees, default
## -4) are optional. Each spot is saved as $OUT/<name>.png at the window's size; the film is
## portrait, so crop the middle 9:16 of the frame to compare (the camera's 70 degrees is the
## vertical field, about a phone's main lens held upright).
##
##   SPOTS=/path/spots.json game/streets/tests/run.sh filmed_spots 1
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	var spots: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SPOTS")))
	OS.set_environment("STREETS_CAM", "0,0,1.35,0,-4")
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._car.visible = false   # the camera stands where the car is put
	for s: Dictionary in spots:
		g._dev_cam[2] = float(s.get("up", 1.35))
		g._dev_cam[4] = float(s.get("tilt", -4.0))
		for i in 12:   # held there a few frames: the car's own physics would nudge it
			g._pos = Vector2(s.x, s.z)
			g._prev_pos = g._pos
			g._yaw = float(s.yaw)
			g._v = 0.0
			await process_frame
		await _snap(String(s.name))
	quit(0)
