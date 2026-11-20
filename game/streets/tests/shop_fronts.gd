extends SceneTree
## The shop windows up close (SHOP_SHADER: a lit room behind the glass, worked out from where
## you look) and what stands in front of them (A-frame boards, crates), from the pavement 4 m
## out and 30 degrees aside, the nearest lit shops to the start; then the same at night.
## Also how many shopkeepers stand in doorways now. Shots shopf_*.png in $OUT.
##   FULL=1 STREETS_BUILD_ALL=0 RES=1280x720 OUT=<dir> game/streets/tests/run.sh shop_fronts 1
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
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
	await create_timer(4.0).timeout   # (the people put out: shopkeepers among them)
	var kept := 0
	for c: Dictionary in g._keepers:
		if (c["actor"] as Node3D).visible:
			kept += 1
	print("shop doorways known %d, shopkeepers standing in them %d" % [g._shop_spots.size(), kept])
	var start: Vector2 = g._pos
	var shops: Array = g._shop_lights.duplicate()
	shops.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(start) < (b[0] as Vector2).distance_to(start))
	print("lit shop windows %d" % shops.size())
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	for pass_i in range(2):
		if pass_i == 1:
			g._set_night(true)
			await create_timer(1.0).timeout
		for k in range(mini(3, shops.size())):
			var at: Vector2 = shops[k][0]
			var n: Vector2 = shops[k][1]
			var side := Vector2(-n.y, n.x)
			var eye := at + n * 4.0 + side * 2.3
			var y: float = g._h(at)
			g.look_from(Vector3(eye.x, y + 1.6, eye.y), Vector3(at.x, y + 1.3, at.y))
			g._sky_follow()
			await _snap("shopf_%d%s" % [k, "_night" if pass_i == 1 else ""])
	quit()
