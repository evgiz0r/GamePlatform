extends SceneTree
## Views of streets by name, in any town: for each name in STREETS (';'-separated, matched
## against a road's name or its English name, a part of it is enough) the eye stands at the
## middle of the longest stretch so named, looking along it -- at a walker's height and from
## 30 m up looking down it -- and prints where that was. The quick look at a place that is
## new to a city (a re-bake with a bigger box) without working out coordinates first.
##
##   OUT=/tmp/v STREETS="Allenby;HaCarmel;Rothschild" game/streets/tests/run.sh street_views 7
##   NIGHT=1 adds each view at night; AT=x,z;x,z... adds views from those points, looking
##   north (z-), or LOOK=x,z;... at those points
##
## (run.sh has the whole town built first.) Prints, headless too: each name's stretch, its
## kind and lanes, and the shot names.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _view(name: String, p: Vector2, at: Vector2, up: float, tilt: float) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = tilt
	var yaw := (at - p).angle()
	for i in 12:
		g._pos = p
		g._prev_pos = p
		g._yaw = yaw
		g._prev_yaw = yaw
		g._v = 0.0
		await process_frame
	await _snap(name)

func _pts(s: String) -> Array:
	var out: Array = []
	for part in s.split(";", false):
		var xy := part.split(",")
		if xy.size() == 2:
			out.append(Vector2(float(xy[0]), float(xy[1])))
	return out

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
	print("city: %s, bounds %s" % [g._city_name, g._bounds])
	var views: Array = []   # [name, eye, looking at, up, tilt]
	for want: String in OS.get_environment("STREETS").split(";", false):
		var key := want.strip_edges().to_lower()
		var best := -1
		var best_len := 0.0
		for ri in range(g._roads.size()):
			var r: Dictionary = g._roads[ri]
			if not (String(r["name"]).to_lower().contains(key) or String(r.get("en", "")).to_lower().contains(key)):
				continue
			var pts: PackedVector2Array = r["pts"]
			var l := 0.0
			for j in range(pts.size() - 1):
				l += pts[j].distance_to(pts[j + 1])
			if l > best_len:
				best_len = l
				best = ri
		if best < 0:
			print("%s: no road so named" % want)
			continue
		var r: Dictionary = g._roads[best]
		var pts: PackedVector2Array = r["pts"]
		# its middle, by length, and the way along it there
		var half := best_len * 0.5
		var mid := pts[0]
		var dir := Vector2.RIGHT
		for j in range(pts.size() - 1):
			var seg := pts[j].distance_to(pts[j + 1])
			if seg >= half and seg > 0.01:
				dir = (pts[j + 1] - pts[j]) / seg
				mid = pts[j] + dir * half
				break
			half -= seg
		var slug := want.strip_edges().to_lower().replace(" ", "_")
		print("%s: %s (%s, %s, %.0f m wide, %d lanes a way), %.0f m long, the middle at %s heading %s" % [want,
			r["name"], r.get("en", ""), r["k"], float(r["w"]), g._lanes_each_way(r), best_len,
			Vector2i(mid), Vector2(dir.x, dir.y).snapped(Vector2(0.01, 0.01))])
		# (walking height a little to the right of the middle line, so the eye is not in a car)
		views.append([slug, mid - dir * 4.0 + Vector2(-dir.y, dir.x) * float(r["w"]) * 0.3, mid + dir * 60.0, 1.7, 2.0])
		views.append([slug + "_above", mid - dir * 60.0, mid + dir * 40.0, 30.0, -18.0])
	for p: Vector2 in _pts(OS.get_environment("AT")):
		views.append(["at_%d_%d" % [int(p.x), int(p.y)], p, p + Vector2(0, -60), 1.7, 2.0])
	for p: Vector2 in _pts(OS.get_environment("LOOK")):
		views.append(["look_%d_%d" % [int(p.x), int(p.y)], p + Vector2(60, 60), p, 35.0, -22.0])
	if DisplayServer.get_name() == "headless":
		quit()
		return
	g._car.visible = false
	for night: bool in ([false, true] if OS.get_environment("NIGHT") != "" else [false]):
		if night:
			g._set_night(true)
			await create_timer(0.5).timeout
		for v: Array in views:
			await _view(String(v[0]) + ("_night" if night else ""), v[1], v[2], float(v[3]), float(v[4]))
	quit()
