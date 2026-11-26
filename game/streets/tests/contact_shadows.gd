extends SceneTree
## The contact shadows (the game's AO_SHADER layer): the ground darker at the foot of a
## building's walls and under a parked car. Stands a person's height off the ground near
## AT="x,z" (the start when not given) and shoots the same view with the layer and without:
## the nearest building's wall from the street, the nearest block on columns (the parking
## under it in the shade), and the nearest parked car from the pavement. Prints how much of each picture got darker and by how much; screenshots
## ao_<what>_on.png / _off.png in $OUT.
var g: Node

func _initialize() -> void:
	_run()

func _shot() -> Image:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()

func _layer(on: bool) -> int:
	var n := 0
	for mi: MeshInstance3D in g.world.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and mi.mesh.get_surface_count() > 0 and mi.mesh.surface_get_material(0) == g._ao_kit._ao_mat:
			mi.visible = on
			n += 1
	return n

func _ab(name: String, eye: Vector3, tgt: Vector3) -> void:
	g.look_from(eye, tgt)
	g._sky_follow()
	_layer(true)
	var on: Image = await _shot()
	_layer(false)
	var off: Image = await _shot()
	_layer(true)
	on.save_png(OS.get_environment("OUT") + "/ao_%s_on.png" % name)
	off.save_png(OS.get_environment("OUT") + "/ao_%s_off.png" % name)
	var darker := 0
	var most := 0.0
	var n := 0
	for y in range(0, on.get_height(), 4):
		for x in range(0, on.get_width(), 4):
			var d := off.get_pixel(x, y).get_luminance() - on.get_pixel(x, y).get_luminance()
			n += 1
			if d > 0.02:
				darker += 1
			most = maxf(most, d)
	print("%s: %.1f%% of the picture darker, at most by %.2f" % [name, 100.0 * darker / n, most])

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var at: Vector2 = g._pos
	var env := OS.get_environment("AT").split(",", false)
	if env.size() == 2:
		at = Vector2(float(env[0]), float(env[1]))
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	print("layer meshes: ", _layer(true))
	# the nearest building on the ground, from the street: the foot of its wall nearest a road
	var best := -1
	var bd := INF
	for bi in range(g._bld_kind.size()):
		if g._bld_kind[bi] != 0 or g._bld_solid[bi] == 0:
			continue
		var c: Vector2 = (g._bld_box[bi] as Rect2).get_center()
		if c.distance_to(at) < bd:
			bd = c.distance_to(at)
			best = bi
	if best >= 0:
		var ring: PackedVector2Array = g._blds[best]
		var c: Vector2 = (g._bld_box[best] as Rect2).get_center()
		var hit: Dictionary = g._nearest_seg(c, 60.0, true)
		var road: Vector2 = hit["q"] if not hit.is_empty() else c + Vector2(20, 0)
		var q := ring[0]
		for i in range(ring.size()):
			var p := Geometry2D.get_closest_point_to_segment(road, ring[i], ring[(i + 1) % ring.size()])
			if p.distance_to(road) < q.distance_to(road):
				q = p
		var out := (road - q).normalized()
		var e2 := q + out * 6.0 + out.orthogonal() * 2.5
		print("building %d m from the point" % int(bd))
		await _ab("wall", Vector3(e2.x, g._h(e2) + 0.14 + 1.55, e2.y), Vector3(q.x, g._h(q) + 0.4, q.y))
	# the nearest block on columns, from the street
	var cbest := -1
	var cbd := INF
	for bi in range(g._bld_kind.size()):
		if g._bld_kind[bi] == 1:
			var c: Vector2 = (g._bld_box[bi] as Rect2).get_center()
			if c.distance_to(at) < cbd:
				cbd = c.distance_to(at)
				cbest = bi
	if cbest >= 0:
		var box: Rect2 = g._bld_box[cbest]
		var c := box.get_center()
		var hit: Dictionary = g._nearest_seg(c, 60.0, true)
		var dir: Vector2 = ((hit["q"] as Vector2) - c).normalized() if not hit.is_empty() else Vector2(1, 0)
		var e2 := c + dir * (box.size.length() * 0.5 + 5.0)
		print("block on columns %d m from the point" % int(cbd))
		await _ab("columns", Vector3(e2.x, g._h(e2) + 1.6, e2.y), Vector3(c.x, g._h(c) + 1.0, c.y))
	# the nearest parked car, from 5 m off its side
	var cb := -1
	var cd := INF
	for i in range(g._ao_kit._ao_cars.size()):
		var d: float = (g._ao_kit._ao_cars[i][0] as Vector2).distance_to(at)
		if d < cd:
			cd = d
			cb = i
	if cb >= 0:
		var c: Vector2 = g._ao_kit._ao_cars[cb][0]
		var f: Vector2 = g._ao_kit._ao_cars[cb][1]
		var e2 := c + f.orthogonal() * 5.0 + f * 3.0
		print("parked car %d m from the point" % int(cd))
		await _ab("car", Vector3(e2.x, g._h(e2) + 0.14 + 1.55, e2.y), Vector3(c.x, g._h(c) + 0.3, c.y))
	quit(0)
