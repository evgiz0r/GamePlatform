extends SceneTree
## The front gardens split out of loading (streets.gd _build_gardens_later): the plots within
## GARDENS_NOW of the start laid while loading, the rest of the start's squares' plots first
## thing once driving. Prints the gardens' share of loading, how long the rest took to come
## after, and what the start's squares hold once it has -- the garden walls' collision
## pieces and the board fences' points in them. Run it twice, headless:
##   STREETS_BUILD_ALL=0 ... -s res://game/streets/tests/gardens_later.gd
##   STREETS_BUILD_ALL=0 STREETS_GARDENS_SPLIT=0 ... (all while loading, as before)
## Good: the same counts both ways; the gardens' part of loading a fraction of the other's.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	# the start's squares as they were measured: all within NEAR_FIRST before the car (since a
	# city level builds only what its first view sees first, their count would depend on when
	# the background build got to them)
	OS.set_environment("STREETS_NEAR_FIRST", "1")
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.1).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var later: int = g._gardens_later.size()
	print("loading: kerbs %s ms, of it the front gardens %s ms; squares with gardens for later: %d" % [
		g._stage_ms.get("kerbs", -1), g._stage_ms.get("kerbs: front gardens (walls, gates, paths, fences, hedges)", -1), later])
	var t0 := Time.get_ticks_msec()
	while not g._gardens_later.is_empty():
		await create_timer(0.05).timeout
	if later > 0:
		print("the rest of the gardens came %d ms after (frames of the background build)" % (Time.get_ticks_msec() - t0))
	var near: Array = []
	for t: Vector2i in g._tiles_done:
		if g._tile_dist(t, g._gardens_from) < g.NEAR_FIRST:
			near.append(g._tile_rect(t))
	var walls := 0
	for i in range(g._wall_r.size()):
		var m: Vector2 = (g._walls[i * 2] + g._walls[i * 2 + 1]) * 0.5
		for r: Rect2 in near:
			if r.has_point(m):
				walls += 1
				break
	var planks := 0
	for p: Vector2 in g._plank_at:
		for r: Rect2 in near:
			if r.has_point(p):
				planks += 1
				break
	print("the start's %d squares: %d wall pieces, %d board fence points" % [near.size(), walls, planks])
	quit(0)
