extends SceneTree
## Tel Aviv's (level 7) beach, the Carmel market and the towers added with them: the counts
## (beach.gd: beaches, umbrellas, chairs, lifeguard towers; landmarks.gd: market stalls placed
## of those planned, the landmarks found), then views -- the beach from above and from the sand
## among the umbrellas with people in the chairs, a lifeguard's tower, the market down its
## walkway and from above, the Shalom Meir tower and the Opera tower.
##
##   OUT=/tmp/sea game/streets/tests/run.sh seaside 7
##   LEVEL=7 STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/seaside.gd   the counts
##
## Good: 8-10 beaches with a few hundred umbrellas, chairs about twice that, a tower every
## ~230 m of shore; stalls placed on most of the ~280 places planned (not where a building or
## a post stands); the two towers found (Shalom Meir 130 m, the Opera tower's top 82 m). In the
## shots: warm sand, rows of coloured umbrellas with white chairs facing the sea and people in
## some, a white and blue hut on stilts, stalls down both sides of the market with a walkway
## between, the Shalom Meir tower's antenna.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the eye at p, `up` over the ground, facing `at`, tilted; first turned away a moment, so
## the people placed out of sight (the bathers in their chairs) are in place when it turns
func _view(name: String, p: Vector2, at: Vector2, up: float, tilt: float, settle := false) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = tilt
	var yaw := (at - p).angle()
	if settle:
		for i in 200:   # (a people tick is every 1.5 s)
			g._pos = p
			g._prev_pos = p
			g._yaw = yaw + PI
			g._prev_yaw = yaw + PI
			g._v = 0.0
			await process_frame
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
	while not g._tiles_todo.is_empty():   # (every square built: the counts are the whole town's)
		await create_timer(0.5).timeout
	print("beach: ", g._beach.count, ", chairs as seats ", g._beach_spots.size())
	print("market and landmarks: ", g._marks.count)
	for f: Array in g._marks.found:
		print("  %s: building %d, %.0f m, at %s" % [f[0], f[1], f[2], f[3]])
	if DisplayServer.get_name() == "headless" or g._city_id != "tel_aviv":
		quit()
		return
	g._car.visible = false
	var shore := Vector2(-2468, 0)
	await _view("beach_above", shore + Vector2(70, 50), shore, 32.0, -24.0)
	# on the sand among the umbrellas, the chair nearest that point ahead
	var best: Array = []
	for sp: Array in g._beach_spots:
		if best.is_empty() or (sp[0] as Vector2).distance_to(shore) < (best[0] as Vector2).distance_to(shore):
			best = sp
	if not best.is_empty():
		var c: Vector2 = best[0]
		var face: Vector2 = best[1]
		var side := Vector2(-face.y, face.x)
		await _view("beach_chairs", c - face * 9.0 + side * 6.0, c + face * 6.0, 1.7, -4.0, true)
		await _view("beach_to_sea", c - face * 4.0, c + face * 40.0, 1.7, 0.0, true)
	for it_list: Array in g._beach._tile_items.values():
		var done := false
		for it: Array in it_list:
			if String(it[0]) == "tower" and g._bounds.grow(-150.0).has_point(it[1]):
				var tp: Vector2 = it[1]
				var dir: Vector2 = it[2]
				await _view("lifeguard", tp - dir * 16.0 + Vector2(-dir.y, dir.x) * 8.0, tp, 2.0, 6.0)
				done = true
				break
		if done:
			break
	# the market: down HaCarmel's walkway, and from above
	var mid := Vector2(-2078, 701)
	var along := Vector2(-0.77, 0.63)
	await _view("market", mid - along * 20.0, mid + along * 30.0, 1.7, 0.0, true)
	await _view("market_above", mid - along * 45.0 + Vector2(-along.y, along.x) * 18.0, mid + along * 10.0, 22.0, -26.0)
	for f: Array in g._marks.found:
		var at := Vector2(f[3])
		if String(f[0]) == "מגדל שלום מאיר":
			# (from beside its roof: from the street a nearer tower stands in the way)
			await _view("shalom_meir", at + Vector2(45, -30), at, 150.0, 8.0)
		elif String(f[0]) == "מגדל האופרה":
			await _view("opera_tower", at + Vector2(-150, 120), at, 12.0, 12.0)
	quit()
