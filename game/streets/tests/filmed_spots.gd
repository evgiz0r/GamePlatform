extends SceneTree
## Filmed spots: the game seen from the places a filmed walk or drive was, to set beside the
## film's own stills. The spots come from a JSON file named by $SPOTS (kept out of the repo:
## a filmed route can start at someone's door) -- a list of
##   {"name": "v040", "x": metres east, "z": metres south, "yaw": radians,
##    "side": "left", "up": 1.35, "tilt": -4}
## in the city file's ground coordinates, yaw as the game's (forward = (cos, sin) on x/z).
## Optional: `side` ("left"/"right" of the way you face) puts the spot on the middle of that
## pavement of the nearest street -- a phone's GPS is good to ~4 m, which on a narrow street
## is the middle of the road; leave it out at a crossing or wherever the spot is right as it
## is. `up` (eye height, default 1.35 m: a phone held at the chest) and `tilt` (degrees,
## default -4). Each spot is saved as $OUT/<name>.png, the 3D view alone (no HUD); the film
## is portrait, so crop the middle 9:16 to compare (the camera's 70 degrees is the vertical
## field, about a phone's main lens held upright). Each spot's line in the output says how
## far `side` moved it.
##
##   SPOTS=/path/spots.json game/streets/tests/run.sh filmed_spots 1
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the middle of the pavement on `side` of the street nearest p, as seen facing yaw
func _on_pavement(p: Vector2, yaw: float, side: String) -> Vector2:
	var hit: Dictionary = g._nearest_seg(p, 30.0, true, true)
	if hit.is_empty():
		return p
	var r: Dictionary = g._roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var along: Vector2 = (pts[hit["seg"] + 1] - pts[hit["seg"]]).normalized()
	var n := Vector2(-along.y, along.x)
	var left := Vector2(sin(yaw), -cos(yaw))
	if n.dot(left) < 0.0:
		n = -n
	if side == "right":
		n = -n
	return Vector2(hit["q"]) + n * (float(r["w"]) * 0.5 + 1.6)

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
		var p := Vector2(s.x, s.z)
		if s.has("side"):
			p = _on_pavement(p, float(s.yaw), String(s.side))
		print("%s: moved %.1f m onto the %s pavement" % [s.name, p.distance_to(Vector2(s.x, s.z)), s.get("side", "(no)")])
		for i in 12:   # held there a few frames: the car's own physics would nudge it
			g._pos = p
			g._prev_pos = g._pos
			g._yaw = float(s.yaw)
			g._v = 0.0
			await process_frame
		await _snap(String(s.name))
	quit(0)
