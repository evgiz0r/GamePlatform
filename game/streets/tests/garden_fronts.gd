extends SceneTree
## The garden fronts and the pavement's things near a point (AT="x,z", else the start): how
## many gates, yard cars, rendered walls, pavement covers' streets, earth tree pits and
## recycling bins the squares round it got, then a look from a walker's eye height at the
## nearest gate and its path, the nearest yard with its car, the nearest recycling bins,
## zone-30 and parking signs, delivery bikes, bikes on bollards and dropped, a cabinet (its
## tags), the pavement from above, the nearest passages between blocks (shots gf_*.png in $OUT).
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _look(name: String, at: Vector2, from_dir: Vector2, back: float, h: float, aim_h := 0.5) -> void:
	var e := at + from_dir.normalized() * back
	g.look_from(Vector3(e.x, g._h(e) + h, e.y), Vector3(at.x, g._h(at) + aim_h, at.y))
	g._sky_follow()
	await _snap(name)

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
	var at: Vector2 = g._pos
	var env := OS.get_environment("AT").split(",", false)
	if env.size() == 2:
		at = Vector2(float(env[0]), float(env[1]))
	var gates: Array = []
	for k in g._gate_cache:
		gates.append_array(g._gate_cache[k])
	var yards := gates.filter(func(x): return x[5])
	print("gates %d (yards %d), yard cars %s, spilling %s, tree pits %s, paper bins %d, cages %d, glass %d" % [gates.size(),
		yards.size(), g._dressing.get("yard_cars", 0), g._dressing.get("spilling_over", 0), g._dressing.get("tree_pits", 0),
		(g._furn.where.get("recycle_paper", []) as Array).size(), (g._furn.where.get("recycle_cages", []) as Array).size(),
		(g._furn.where.get("recycle_glass", []) as Array).size()])
	var by_near := func(a, b): return (a[2] as Vector2).distance_to(at) < (b[2] as Vector2).distance_to(at)
	gates.sort_custom(by_near)
	yards.sort_custom(by_near)
	for i in range(mini(2, gates.size())):
		var gt: Array = gates[i]
		var dp: Vector2 = gt[2]
		var nj: Vector2 = gt[3]
		var depth: float = gt[4]
		var gate_pt := dp - nj * (depth + 0.3)
		# from the pavement, a few metres along, looking through the gate to the door
		await _look("gf_gate_%d" % i, gate_pt + nj * 0.5, -nj + nj.orthogonal() * 0.6, 6.0, 1.6, 1.2)
	if not yards.is_empty():
		var gt: Array = yards[0]
		var dp: Vector2 = gt[2]
		var nj: Vector2 = gt[3]
		await _look("gf_yard", dp - nj * 3.0, -nj + nj.orthogonal() * 0.4, 9.0, 1.7, 0.8)
	for kind: String in ["recycle_paper", "bollards", "signs_zone30", "signs_parking", "delivery_bikes", "bikes_on_bollards", "bikes_dropped", "cabinets"]:
		var list: Array = (g._furn.where.get(kind, []) as Array).duplicate()
		if list.is_empty():
			continue
		list.sort_custom(func(a, b): return Vector2(a.origin.x, a.origin.z).distance_to(at) < Vector2(b.origin.x, b.origin.z).distance_to(at))
		var t: Transform3D = list[0]
		var fwd := Vector2(t.basis.z.x, t.basis.z.z).normalized()
		var tall := kind.begins_with("signs")
		print("%s: %d, nearest %d m" % [kind, list.size(), int(Vector2(t.origin.x, t.origin.z).distance_to(at))])
		await _look("gf_" + kind, Vector2(t.origin.x, t.origin.z), fwd + fwd.orthogonal() * 0.35, 5.0 if tall else 3.2,
			1.7, 2.2 if tall else 0.6)
	# looking down at the pavement along the start street: covers, pits
	var f: Vector2 = g._fwd()
	var side := Vector2(-f.y, f.x)
	var walk := at + side * 6.0
	g.look_from(Vector3(walk.x, g._h(walk) + 1.7, walk.y), Vector3(walk.x + f.x * 7, g._h(walk), walk.y + f.y * 7))
	g._sky_follow()
	await _snap("gf_pavement")
	# and from above, 40 m of both pavements: the covers in them, the tree pits
	for sd: float in [1.0, -1.0]:
		var over := at + side * 5.5 * sd
		g.look_from(Vector3(over.x - f.x * 4, g._h(over) + 9.0, over.y - f.y * 4), Vector3(over.x + f.x * 16, g._h(over), over.y + f.y * 16))
		g._sky_follow()
		await _snap("gf_pavement_above_%d" % int(sd))
	# the nearest passage between blocks, from a walker a few metres into it
	var ps: Array = g.passages.duplicate()
	ps.sort_custom(func(a, b): return (a[0] as Vector2).distance_to(at) < (b[0] as Vector2).distance_to(at))
	print("passages walled: %d, nearest %d m" % [ps.size(), int((ps[0][0] as Vector2).distance_to(at)) if ps.size() > 0 else -1])
	for i in range(mini(2, ps.size())):
		var m: Vector2 = ps[i][0]
		var d: Vector2 = ps[i][1]
		await _look("gf_passage_%d" % i, m, -d, 7.0, 1.6, 1.0)
	print("tree pits %s, grates %s" % [g._dressing.get("tree_pits", 0), g._dressing.get("tree_grates", 0)])
	quit(0)
