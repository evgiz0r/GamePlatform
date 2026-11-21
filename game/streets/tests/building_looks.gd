extends SceneTree
## The blocks' fronts as the street sees them (WALL_SHADER, _med_plaster): from across the
## street, eye height, the nearest blocks of three storeys and more round the start -- their
## plaster by age (the 1950s-70s ones sand, the older cream, the new white or stone), the
## balconies' bands, the balconies closed in, shutters and grime. Prints the plaster count
## over the whole town (how many blocks of each, from the city file's years and colours) and
## each shot block's height and distance; shots bld_*.png in $OUT.
##   FULL=1 STREETS_BUILD_ALL=0 RES=1280x720 OUT=<dir> game/streets/tests/run.sh building_looks 1
## (N=6 blocks by default; CITY=<file name> for the count when not Givatayim.)
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	var want := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6
	var start: Vector2 = g._pos
	# the town's plaster mix, from the city file as the game reads it
	var counts := {}
	var city := OS.get_environment("CITY") if OS.get_environment("CITY") != "" else "givatayim"
	var blds: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://game/streets/cities/%s.json" % city)) as Dictionary).get("buildings", [])
	for bd: Dictionary in blds:
		var ring: Array = bd.get("p", [])
		if ring.size() < 2:
			continue
		var hsh: int = g._hash_i(Vector2(float(ring[0]), float(ring[1])) * 0.1)
		var ts: Vector2 = g._med_plaster(bd, hsh, 0)
		var kind := "stone" if ts.y >= 0.79 else ("sand" if ts.y >= 0.4 and int(ts.x) == 0 else ("cream" if ts.y >= 0.1 and int(ts.x) == 0 else ("white" if int(ts.x) == 0 else "tint %d" % int(ts.x))))
		counts[kind] = int(counts.get(kind, 0)) + 1
	print("the town's plaster (from the city file): ", counts)
	# the nearest blocks: from 22 m out along the line from the block's middle to the start
	var near: Array = []
	for i in range(g._bld_box.size()):
		var box: Rect2 = g._bld_box[i]
		var c := box.get_center()
		var d := c.distance_to(start)
		if d > 25.0 and d < 220.0 and float(g._bld_top[i]) >= 9.0 and box.size.x > 8.0 and box.size.y > 8.0:
			near.append([d, i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var shot := 0
	for e: Array in near:
		if shot >= want:
			break
		var i: int = e[1]
		var box: Rect2 = g._bld_box[i]
		var c := box.get_center()
		var out := (start - c).normalized()
		var eye := c + out * (maxf(box.size.x, box.size.y) * 0.5 + 18.0)
		if g._push_out(eye, 0.4, false) != Vector2.ZERO or g._wall_between(eye, c + out * (maxf(box.size.x, box.size.y) * 0.45)):
			continue
		var y: float = g._h(eye)
		g.look_from(Vector3(eye.x, y + 1.6, eye.y), Vector3(c.x, y + minf(float(g._bld_top[i]) * 0.5, 9.0), c.y))
		g._sky_follow()
		await _snap("bld_%d" % shot)
		print("bld_%d: building %d, %.0f m tall, %.0f m from the start" % [shot, i, float(g._bld_top[i]), e[0]])
		shot += 1
	print("shots in ", OS.get_environment("OUT"))
	quit()
