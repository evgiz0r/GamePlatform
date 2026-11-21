extends SceneTree
## Tel Aviv's own map laid over the city (tools/osm_city.py's TOWN_LAYERS): its lamp posts
## where they stand, its building sites (hoardings, cranes: sites.gd) and its licensed
## businesses as shop fronts where OSM has no place. Counts headless; shots when drawn: a
## street of the town's lamp posts, a building site and its crane, a street of shops.
##
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/town_layers.gd
##   FULL=1 RES=1280x720 OUT=/tmp/tl game/streets/tests/run.sh town_layers 7
##
## Good (level 7): ~15,000 mapped lamp posts in the file and most of them standing (a few
## hundred dropped where nothing off the asphalt is near), none on the asphalt; made-up
## lamps only outside the map's cover (Givatayim's and Ramat Gan's corners of the box);
## ~500 sites with hoardings, a few dozen cranes; ~2,300 more shop fronts. Level 1 the same
## in its Tel Aviv strip. Ends in one REGRESS line.
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
	var k := 1.0 / float(g._city_data.get("scale", 10))
	var mapped: int = (g._city_data.get("lamps", []) as Array).size() / 2
	var biz := 0
	var biz_at: Array = []
	for p: Array in g._city_data.get("pois", []):
		if p.size() >= 6:
			biz += 1
			if biz_at.size() < 4000:
				biz_at.append(Vector2(p[0], p[1]) * k)
	var site_rings: Array = []
	for st: Dictionary in g._city_data.get("sites", []):
		var flat: Array = st["r"]
		var c := Vector2.ZERO
		for i in range(0, flat.size() - 1, 2):
			c += Vector2(flat[i], flat[i + 1]) * k
		site_rings.append([c / (flat.size() / 2), int(st.get("new", 0)), int(st.get("hi", 0))])
	while not g._tiles_todo.is_empty():
		await create_timer(0.5).timeout
	# the lamp posts standing: posts of 0.15 m (the lamps') on the asphalt
	var on_road := 0
	var lamps := 0
	for i in range(g._posts.size()):
		if absf(float(g._post_r[i]) - 0.15) < 0.001 or absf(float(g._post_r[i]) - 0.18) < 0.001:
			lamps += 1
			if not g._off_road(g._posts[i], 0.0):
				on_road += 1
	var tally: Dictionary = g._dressing
	print("lamp posts: %d in the town's map; %d lamp posts standing (0.15/0.18 m posts: lamps, and a few others), %d on the asphalt" % [mapped, lamps, on_road])
	print("tally lamps: ", tally.get("lamps", "?"))
	print("sites: ", g._works.count, " (", site_rings.size(), " in the file)")
	print("businesses added as places: %d" % biz)
	var pois_built: int = g._pois.size()
	print("places built (signs): %d" % pois_built)
	var ok: bool = mapped > 0 and on_road == 0 and int(g._works.count.get("panels", 0)) > 0 and biz > 0
	if g._city_id == "tel_aviv":
		ok = ok and int(g._works.count.get("cranes", 0)) >= 10 and mapped > 12000
	print("REGRESS town_layers: %s (lamps mapped %d, on the asphalt %d want 0; hoarding panels %d want 1+; cranes %d; businesses %d)" % [
		"PASS" if ok else "FAIL", mapped, on_road, int(g._works.count.get("panels", 0)), int(g._works.count.get("cranes", 0)), biz])
	if DisplayServer.get_name() == "headless":
		quit()
		return
	g._car.visible = false
	# Rothschild's lamp posts, down the boulevard
	var roth := Vector2(-1560, 980)
	for r: Dictionary in g._roads:
		if String(r["name"]) == "שדרות רוטשילד":
			var pts: PackedVector2Array = r["pts"]
			roth = pts[pts.size() / 2]
			break
	await _view("lamps_rothschild", roth + Vector2(8, -8), roth + Vector2(-30, 30), 1.7, 2.0)
	# a crane: the first tall new building's site, from 60 m off and up the street
	for sr: Array in site_rings:
		if int(sr[1]) == 1 and int(sr[2]) == 1:
			var c: Vector2 = sr[0]
			# (from the street: the nearest road to the site for the hoarding, a road 70-110 m
			# off for the crane over the roofs -- a point beside the site was inside a block)
			var near: Dictionary = g._nearest_seg(c, 60.0, true, true)
			if near.is_empty():
				continue
			var far := Vector2.INF
			for kk in range(12):
				var ang := kk * TAU / 12.0
				var h: Dictionary = g._nearest_seg(c + Vector2(cos(ang), sin(ang)) * 90.0, 25.0, true, true)
				if not h.is_empty():
					far = h["q"]
					break
			if far.is_finite():
				await _view("crane", far, c, 1.7, 24.0)
			var q: Vector2 = near["q"]
			await _view("hoarding", q + (q - c).normalized() * 3.0, c, 1.7, 4.0)
			break
	# a street of shops: where the businesses added are thickest
	var cells := {}
	for p: Vector2 in biz_at:
		var key := Vector2i((p / 60.0).floor())
		cells[key] = int(cells.get(key, 0)) + 1
	var best := Vector2i.ZERO
	for key: Vector2i in cells:
		if int(cells[key]) > int(cells.get(best, 0)):
			best = key
	var mid := (Vector2(best) + Vector2(0.5, 0.5)) * 60.0
	var hit: Dictionary = g._nearest_seg(mid, 40.0, true, true)
	if not hit.is_empty():
		var q: Vector2 = hit["q"]
		var pts: PackedVector2Array = g._roads[hit["road"]]["pts"]
		var t: Vector2 = (pts[int(hit["seg"]) + 1] - pts[int(hit["seg"])]).normalized()
		await _view("shops", q - t * 25.0, q + t * 10.0 + Vector2(-t.y, t.x) * 6.0, 1.7, 0.0)
	quit()
