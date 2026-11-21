extends SceneTree
## Where two pavings lie over one spot (they flicker): world_checks' pavings_overlap, by 25 m
## square, the worst N (default 12) with the paving codes that meet there (the colour's red
## channel of each: a road's own paving, a corner's...). SHOTS=1 also shoots the worst
## three from 25 m up (pave_<i>.png). city_check gives the total against the town's limit.
##   N=12 SHOTS=1 OUT=dir game/streets/tests/run.sh pavings_where 3
var g: Node
func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	var W := preload("res://game/streets/tests/world_checks.gd")
	var res: Array = W.pavings_overlap(g)
	print("two pavings at once: %.1f m2 (%s)" % [float(res[0]), res[1]])
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 12
	var top: Array = W.last_places.slice(0, n)
	for row: Array in top:
		print("  %6.1f m2 near %s  %s" % [float(row[0]), (row[1] as Vector2).round(), row[2]])
	if OS.get_environment("SHOTS") != "":
		g.set_physics_process(false)
		process_frame.disconnect(g._frame)
		for i in range(mini(3, top.size())):
			var c: Vector2 = top[i][1]
			var y: float = g._h(c)
			g.look_from(Vector3(c.x, y + 25.0, c.y + 25.0 * 0.35), Vector3(c.x, y, c.y))
			for k in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/pave_%d.png" % i)
	quit(0)
