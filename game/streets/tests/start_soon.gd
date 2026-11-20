extends SceneTree
## How soon you can drive, and how soon the city round you is all there. From the moment the
## level is started: when the car is shown (`_loaded`) and how many squares were built before
## it, then -- the car left standing -- when the squares within NEAR_FIRST of it are all built
## (`_catch_up_ms`, the "near_built" event) and how the frames ran meanwhile.
##   STREETS_BUILD_ALL=0 LEVEL=1 $GODOT --headless --path . -s res://game/streets/tests/start_soon.gd
## STREETS_NEAR_FIRST=1 for the old way (all of NEAR_FIRST before the car). With a display
## (tests/run.sh, OUT=dir) it saves the view when the car is shown and once the rest is up
## (soon_shown_<level>, soon_built_<level>).
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	var t0 := Time.get_ticks_msec()
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:
		await process_frame
		if g == null:
			for n in root.find_children("*", "Node2D", true, false):
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
					g = n
	var shown := Time.get_ticks_msec() - t0
	var first: int = g._tiles_done.size()
	var near_todo := 0
	for t: Vector2i in g._tiles_todo:
		if g._tile_dist(t, g._pos) < g.NEAR_FIRST:
			near_todo += 1
	print("%s: the car shown after %.1f s (city file %.1f s, warm-up %.1f s); %d squares built before it, %d more within %d m of it" % [
		g._city_name, shown / 1000.0, int(g._stage_ms.get("city file (parse, roads fitted, buildings cut)", 0)) / 1000.0,
		int(g._stage_ms.get("warm up (shaders compiled, 4 frames)", 0)) / 1000.0, first, near_todo, int(g.NEAR_FIRST)])
	await _snap("soon_shown_%d" % lvl)
	var ts := Time.get_ticks_msec()
	var frames := 0
	var worst := 0.0
	var slow := 0
	var hurry: bool = g._catch_up   # (false: nothing left to catch up -- the old way, a walk, a route)
	while hurry and g._catch_up_ms == 0 and Time.get_ticks_msec() - ts < 180000:
		await process_frame
		var dt: float = g.get_process_delta_time()
		frames += 1
		worst = maxf(worst, dt)
		if dt > 0.05:
			slow += 1
	var took := Time.get_ticks_msec() - ts
	print("the squares round the car built %.1f s after it was shown (the game's count: %d ms); %d frames, %.0f a second, the slowest %d ms, %d over 50 ms" % [
		took / 1000.0, g._catch_up_ms, frames, frames / maxf(took / 1000.0, 0.001), int(worst * 1000.0), slow])
	await create_timer(0.5).timeout
	await _snap("soon_built_%d" % lvl)
	quit(0)
