extends SceneTree
## A town's landmarks (landmarks.gd) in Tel Aviv (level 7): what was found -- the
## landmarks by name, Sarona's houses given tile roofs, the roofs with red lights and how
## many lights -- and views by day and night: Azrieli's three towers from Sarona and from
## above Begin, the Kirya's Matcal and Marganit towers, Sarona's houses from above and from
## its lawns, the skyline at night.
##
##   OUT=/tmp/lm game/streets/tests/run.sh landmarks 7
##   LEVEL=7 $GODOT --headless --path . -s res://game/streets/tests/landmarks.gd   the numbers only
##
## Good: 5 landmarks, some 40-50 Sarona houses tiled, every tower over 90 m lit; in the
## shots the three Azrieli towers in one glass with a metal band at the top (lit at night),
## the Marganit tower's shaft and striped mast, red tile roofs among Sarona's trees, red
## points along the skyline at night.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the eye at (x, z), `up` over the surface, facing `at`, tilted `tilt` degrees
func _view(name: String, p: Vector2, at: Vector2, up: float, tilt: float) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = tilt
	var yaw := (at - p).angle()
	for i in 10:
		g._pos = p
		g._prev_pos = p
		g._yaw = yaw
		g._prev_yaw = yaw
		g._v = 0.0
		await process_frame
	await _snap(name)

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.6,0,0")
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var M = g._marks
	print("landmarks: ", M.count)
	for f: Array in M.found:
		print("  %s: building %d, %.0f m, at %s, %s" % f)
	if DisplayServer.get_name() == "headless" or g._city_id != "tel_aviv":
		quit()
		return
	g._car.visible = false   # (run.sh has the whole town built first: the far towers stand)
	for night: bool in [false, true]:
		if night:
			g._set_night(true)
			await create_timer(0.5).timeout
		var sfx := "_night" if night else ""
		# (each from over an open road: Kaplan, Begin, the Ayalon, so nothing near stands in the way)
		await _view("azrieli_from_kaplan" + sfx, Vector2(-430, 160), Vector2(110, 50), 30.0, 9.0)
		await _view("azrieli_from_ayalon" + sfx, Vector2(330, -330), Vector2(110, 60), 25.0, 10.0)
		await _view("kirya_from_kaplan" + sfx, Vector2(-200, 158), Vector2(-200, -40), 40.0, 13.0)
		if not night:
			await _view("azrieli_close", Vector2(-40, 160), Vector2(100, 40), 1.6, 26.0)
			await _view("sarona_above", Vector2(-380, 150), Vector2(-370, 330), 55.0, -30.0)
			await _view("sarona_lawn", Vector2(-310, 340), Vector2(-450, 260), 1.7, 2.0)
	quit()
