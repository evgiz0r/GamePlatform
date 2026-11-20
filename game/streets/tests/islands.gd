extends SceneTree
## Traffic islands (_find_islands): lawns and paved patches with road nearly all round them,
## raised a kerb's height and cut back off the asphalt. Prints how many and how much ground,
## then samples every piece on a 1 m grid for any point on a road's asphalt or a junction's
## disc -- a raised island on the road would be a step in the lanes. Good: 0. Shots (OUT) of
## the SHOTS biggest from the nearest road, 18 m off, facing it.   tests/run.sh islands 3
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var area := 0.0
	var on_road := 0
	var samples := 0
	var worst: Array = []
	for piece: PackedVector2Array in g._islands:
		var a := absf(g._area_signed(piece))
		area += a
		var box: Rect2 = g._bld_box_of(piece)
		var x := box.position.x + 0.5
		while x < box.end.x:
			var z := box.position.y + 0.5
			while z < box.end.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, piece):
					samples += 1
					var hit: Dictionary = g._nearest_seg(p, 14.0, true)
					if (not hit.is_empty() and float(hit["edge"]) < -0.05) or g._in_junction(p, -0.05):
						on_road += 1
						if worst.size() < 8:
							worst.append(p)
				z += 1.0
			x += 1.0
	print("islands: %d pieces, %.0f m2; 1 m samples on a road's asphalt or a junction's disc: %d of %d" % [g._islands.size(), area, on_road, samples])
	for p: Vector2 in worst:
		print("  on the road at %s" % p.round())
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 4
	if OS.get_environment("OUT") == "" or shots <= 0:
		quit(0)
		return
	var order: Array = range(g._islands.size())
	order.sort_custom(func(i, j): return absf(g._area_signed(g._islands[i])) > absf(g._area_signed(g._islands[j])))
	var done: Array = []
	for i: int in order:
		var piece: PackedVector2Array = g._islands[i]
		var c := Vector2.ZERO
		for q in piece:
			c += q
		c /= piece.size()
		if done.any(func(d): return (d as Vector2).distance_to(c) < 80.0):
			continue
		var hit: Dictionary = g._nearest_seg(c, 60.0, true, true)
		if hit.is_empty():
			continue
		var q: Vector2 = hit["q"]
		var dir := (c - q).normalized()
		g._land_on_road(q - dir * 6.0, 10.0, dir)   # (on the road nearest it, then turned to face it)
		g._yaw = (c - g._pos).angle()
		g._v = 0.0
		await create_timer(2.5).timeout
		await _snap("island_%d" % done.size())
		print("  island %d: %.0f m2 at %s" % [done.size(), absf(g._area_signed(piece)), c.round()])
		done.append(c)
		if done.size() >= shots:
			break
	quit(0)
