extends SceneTree
## A weak machine's levels draw less of the town (QUALITY's reach and haze columns, "a weak
## machine's levels" in streets.gd): the same view at quality 2 and quality 0, side by side,
## to see that the thicker haze hides where the town now ends; the draws at each; and the
## ranges after the view from above (which lifts them) has landed again -- each thing back at
## this level's range, not the lifted one or its own full one.
##   game/streets/tests/run.sh reach_look 4        (about 3 minutes; shots reach_q2.png, reach_q0.png)
## Good: quality 0 a quarter fewer draws than 2 (the test town's start: 614 -> ~463), the town's
## edge lost in haze in reach_q0.png, CHECK ... PASS.
var g: Node
var fails := 0

func _initialize() -> void:
	_run()

func check(what: String, ok: bool) -> void:
	print("CHECK %s: %s" % [what, "PASS" if ok else "FAIL"])
	if not ok:
		fails += 1

func _draws() -> int:
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)

func _shot(name: String) -> void:
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/streets-tests/reach_look"
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")

## every gathered thing's range is its own times the level's reach (or its own, under REACH_FROM)
func _ranges_right() -> int:
	var wrong := 0
	for gi: GeometryInstance3D in g._reach_list:
		if not is_instance_valid(gi):
			continue
		var e0: float = gi.get_meta("r_end")
		var want: float = e0 * g._reach if e0 >= g.REACH_FROM else e0
		if absf(gi.visibility_range_end - want) > 0.01:
			wrong += 1
	return wrong

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g.set_physics_process(false)   # (held still: the two shots the same view)
	g._set_quality(2)
	var d2 := await _draws()
	await _shot("reach_q2")
	g._set_quality(0)
	var d0 := await _draws()
	await _shot("reach_q0")
	print("REACH: quality 2 %d draws, quality 0 %d draws (%+d, %.0f%%); %d things gathered, haze x%.2f" % [
		d2, d0, d0 - d2, 100.0 * (d0 - d2) / maxf(d2, 1.0), g._reach_list.size(), g._fog_k])
	check("quality 0 draws at least 15% less than quality 2", d0 <= d2 * 0.85)
	check("every gathered range at quality 0's reach", _ranges_right() == 0)
	# up and back down: the view from above lifts the long ranges, landing must give back this level's
	g.set_physics_process(true)
	g._zoom_set(0.6)
	await create_timer(4.0).timeout
	g._zoom_set(0.0)
	await create_timer(5.0).timeout
	var wrong := _ranges_right()
	print("after the view from above: %d ranges not at this level's" % wrong)
	check("the ranges are this level's again after the view from above", wrong == 0 and g._zoom_ranges_n < 0)
	g._set_quality(2)
	check("back at quality 2, every range its own again", _ranges_right() == 0)
	print("REACH LOOK: %s" % ("PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
