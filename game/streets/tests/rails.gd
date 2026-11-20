extends SceneTree
## The railway (rails.gd) in a town that has one (level 7, Tel Aviv: the Ayalon line): what
## was set up -- tracks, platforms, stations kept, the lines trains run -- how close the
## beds come to a road's asphalt, a train stood at the station nearest STATION (default the
## first), and fixed views: along the tracks from the motorway beside them, each station
## from above, the train at its platform.
##
##   OUT=/tmp/rails game/streets/tests/run.sh rails 7
##   LEVEL=7 $GODOT --headless --path . -s res://game/streets/tests/rails.gd   the numbers only
##
## Good: the tracks and both stations there, a line or more through the town, 0 bed points
## over a road's asphalt; in the shots the beds on the ground between the carriageways, the
## train on its rails, the platforms at its floor.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the camera at (x, z), `up` over the surface, facing yaw, tilted `tilt` degrees
func _view(name: String, p: Vector2, yaw: float, up: float, tilt: float) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = tilt
	for i in 8:
		g._pos = p
		g._prev_pos = p
		g._yaw = yaw
		g._prev_yaw = yaw   # (the view blends from it: with the world held still it never caught up)
		g._v = 0.0
		await process_frame
	await _snap(name)

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.35,0,-4")
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var R = g._rails
	print("tracks %d, platforms %d, stations %s, lines %d" % [R.tracks.size(), R.platforms.size(),
			R.stations.map(func(s): return s[2] if s[2] != "" else s[1]), R.lines.size()])
	for ln: Array in R.lines:
		var p: PackedVector2Array = ln[0]
		print("  line %.0f m from %s to %s" % [(ln[1] as PackedFloat32Array)[-1], p[0].round(), p[p.size() - 1].round()])
	var over := 0
	var n := 0
	for t: Array in R.tracks:
		var pts: PackedVector2Array = t[0]
		var feet: PackedFloat32Array = t[4]
		for j in range(pts.size()):
			n += 1
			var on: Dictionary = g._nearest_seg(pts[j], 20.0, true)
			if not on.is_empty() and float(on["edge"]) < feet[j]:
				over += 1
	print("bed points %d, over a road's asphalt %d" % [n, over])
	if R.lines.is_empty() or R.stations.is_empty():
		quit()
		return
	# a train at the station: the line point nearest it
	var st: Array = R.stations[int(OS.get_environment("STATION")) if OS.get_environment("STATION") != "" else 1 % R.stations.size()]
	var sp: Vector2 = st[0]
	R.tick(0.0)   # (the trains are made on the first tick)
	var best := INF
	var at_s := 0.0
	var path: PackedVector2Array = R.lines[0][0]
	var cum: PackedFloat32Array = R.lines[0][1]
	for j in range(path.size()):
		if path[j].distance_to(sp) < best:
			best = path[j].distance_to(sp)
			at_s = cum[j]
	var tr: Dictionary = R.trains[0]
	tr["wait"] = 0.0
	tr["dir"] = 1
	tr["s"] = at_s + R.COACHES * (R.COACH_L + R.COACH_GAP) * 0.5
	(tr["node"] as Node3D).visible = true
	print("train at %.0f m along line 0, by %s" % [at_s, st[2]])
	await create_timer(1.0).timeout
	g._car.visible = false
	var stop: Vector2 = R._along(0, at_s)[0]
	var dir: Vector2 = R._along(0, at_s)[1]
	var side := Vector2(-dir.y, dir.x)
	for i in range(R.trains.size()):
		R.trains[i]["wait"] = 999.0 if i > 0 else 0.0   # (only the one)
	g.set_physics_process(false)   # (the world holds still: the train stands at the platform)
	R.tick(0.0)
	# the views: the train at the platform, the station from above, along the line from the motorway
	for sd: float in [1.0, -1.0]:   # (one side or the other is a carriageway, the other the platform)
		var eye := stop + side * 9.0 * sd - dir * 45.0
		await _view("train_at_station_%s" % ("l" if sd > 0 else "r"), eye, (stop + dir * 10.0 - eye).angle(), 3.0, -3.0)
	await _view("station_above", stop + side * 70.0 - dir * 60.0, (stop - (stop + side * 70.0 - dir * 60.0)).angle(), 45.0, -30.0)
	for s2: Array in R.stations:
		if s2 != st:
			var q: Vector2 = s2[0]
			await _view("station_above_%s" % String(s2[2]).replace(" ", "_"), q + Vector2(-90, 90), (q - (q + Vector2(-90, 90))).angle(), 55.0, -30.0)
	var lp: Vector2 = R._along(0, 600.0)[0]
	var ld: Vector2 = R._along(0, 600.0)[1]
	var ls := Vector2(-ld.y, ld.x)
	await _view("along_line", lp + ls * 4.0, ld.angle(), 1.6, -6.0)
	await _view("track_down", lp + ls * 7.0 - ld * 6.0, (lp - (lp + ls * 7.0 - ld * 6.0)).angle(), 7.0, -40.0)
	quit()
