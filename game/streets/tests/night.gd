extends SceneTree
## The night up close: from the car's seat with the headlights on, from a walker's eye height
## by the nearest street lamps (their pools and halos), and in front of the nearest lit shop.
## Shots night_<view>.png in $OUT.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.6).timeout
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
	g._set_night(true)
	await create_timer(0.5).timeout
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	var p: Vector2 = g._pos
	var f: Vector2 = g._fwd()
	g.look_from(Vector3(p.x - f.x * 7, g._h(p) + 2.6, p.y - f.y * 7), Vector3(p.x + f.x * 30, g._h(p + f * 30), p.y + f.y * 30))
	g._sky_follow()
	await _snap("night_car")
	# the nearest lamps' pools, from a walker's height 12 m off
	var lamps: Array = g._pool_at.duplicate()
	lamps.sort_custom(func(a, b): return Vector2(a.x, a.y).distance_to(p) < Vector2(b.x, b.y).distance_to(p))
	for i in range(mini(2, lamps.size())):
		var q := Vector2(lamps[i].x, lamps[i].y)
		var from := q + (p - q).normalized().rotated(0.6) * 12.0
		g.look_from(Vector3(from.x, g._h(from) + 1.7, from.y), Vector3(q.x, g._h(q) + 1.5, q.y))
		g._sky_follow()
		await _snap("night_lamp_%d" % i)
	# the nearest lit shop, from across the pavement
	var shops: Array = g._shop_lights.duplicate()
	shops.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(p) < (b[0] as Vector2).distance_to(p))
	if not shops.is_empty():
		var s: Array = shops[0]
		var at: Vector2 = s[0]
		var n: Vector2 = s[1]
		var from := at + n * 7.0 + n.orthogonal() * 3.0
		g.look_from(Vector3(from.x, g._h(from) + 1.7, from.y), Vector3(at.x, g._h(at) + 0.8, at.y))
		g._sky_follow()
		await _snap("night_shop")
	print("lamps %d, lit shops %d" % [g._pool_at.size(), g._shop_lights.size()])
	quit(0)
