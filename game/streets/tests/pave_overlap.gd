extends SceneTree
## Pavement laid twice over the same ground: two pieces of the kerbs' mesh (pavement, or a
## kerb's top) at the same height over the same spot. Each is patterned along its own street,
## so where they overlap the phone's depth buffer picks one or the other pixel by pixel and
## the corner flickers between brick and slabs. Prints the overlapping area (pavement on
## pavement, kerb top on pavement), how many places, the worst, and shoots the worst from
## eye height (OUT, SHOTS). Good: next to none.   tests/run.sh pave_overlap 7
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

const CELL := 3.0

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	# every up-facing triangle drawn with the kerbs' material: [a, b, c (2D), y, pavement?]
	var tris: Array = []
	for mi: MeshInstance3D in g.world.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh as ArrayMesh
		if m == null:
			continue
		for s in range(m.get_surface_count()):
			if m.surface_get_material(s) != g._kerb_mat:
				continue
			var arr := m.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := idx.size() if not idx.is_empty() else v.size()
			var xf := mi.global_transform
			for i in range(0, n, 3):
				var i0 := idx[i] if not idx.is_empty() else i
				var i1 := idx[i + 1] if not idx.is_empty() else i + 1
				var i2 := idx[i + 2] if not idx.is_empty() else i + 2
				if nrm[i0].y < 0.9:
					continue   # a kerb's face
				var a := xf * v[i0]
				var b := xf * v[i1]
				var c := xf * v[i2]
				var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
				if absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) < 0.002:
					continue
				tris.append([tri, (a.y + b.y + c.y) / 3.0, col[i0].b > 0.5, col[i0].r])
	print("kerb-mesh triangles facing up: %d" % tris.size())
	var cells := {}
	for t in range(tris.size()):
		var tri: PackedVector2Array = tris[t][0]
		var box := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
		for cx in range(floori(box.position.x / CELL), floori(box.end.x / CELL) + 1):
			for cz in range(floori(box.position.y / CELL), floori(box.end.y / CELL) + 1):
				var k := Vector2i(cx, cz)
				if not cells.has(k):
					cells[k] = []
				cells[k].append(t)
	var area := [0.0, 0.0, 0.0]   # pavement on pavement, kerb top on pavement (or kerb on kerb), of the first: two patterns
	var places: Array = []   # [where, m2]
	for k: Vector2i in cells:
		var list: Array = cells[k]
		for x in range(list.size()):
			for y in range(x + 1, list.size()):
				var ta: int = list[x]
				var tb: int = list[y]
				if absf(float(tris[ta][1]) - float(tris[tb][1])) > 0.04:
					continue
				var A: PackedVector2Array = tris[ta][0]
				var B: PackedVector2Array = tris[tb][0]
				var boxa := Rect2(A[0], Vector2.ZERO).expand(A[1]).expand(A[2])
				var boxb := Rect2(B[0], Vector2.ZERO).expand(B[1]).expand(B[2])
				if not boxa.intersects(boxb):   # (grown in, a sliver's box came out negative)
					continue
				# (a pair shares several cells: count it in the one its boxes' overlap starts in)
				var both := boxa.intersection(boxb)
				if Vector2i(floori(both.position.x / CELL), floori(both.position.y / CELL)) != k:
					continue
				var over := 0.0
				var mid := Vector2.ZERO
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(A, B):
					var s := 0.0
					for i in range(piece.size()):
						s += piece[i].cross(piece[(i + 1) % piece.size()])
					over += absf(s) * 0.5
					mid = piece[0]
				if over < 0.02:
					continue
				var both_pave: bool = tris[ta][2] and tris[tb][2]
				area[0 if both_pave else 1] += over
				if both_pave and absf(float(tris[ta][3]) - float(tris[tb][3])) > 0.01:
					area[2] += over   # two different pavings: the flicker is brick against slabs
				var merged := false
				for pl: Array in places:
					if (pl[0] as Vector2).distance_to(mid) < 25.0:
						pl[1] += over
						merged = true
						break
				if not merged:
					places.append([mid, over])
	places.sort_custom(func(p, q): return p[1] > q[1])
	print("overlapping: pavement on pavement %.0f m2 (two different pavings %.0f m2), kerb top on pavement %.0f m2, in %d places (over 1 m2: %d)" % [area[0], area[2], area[1],
		places.size(), places.filter(func(p): return p[1] > 1.0).size()])
	for pl: Array in places.slice(0, 15):
		print("  %.1f m2 at %s" % [pl[1], (pl[0] as Vector2).round()])
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 3
	if OS.get_environment("OUT") == "" or shots <= 0:
		quit(0)
		return
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	for i in range(mini(shots, places.size())):
		var p: Vector2 = places[i][0]
		var y: float = g._h(p)
		var from := p + Vector2(-1, 1).normalized() * 12.0
		g.look_from(Vector3(from.x, g._h(from) + 2.2, from.y), Vector3(p.x, y, p.y))
		await _snap("overlap_%d" % i)
		g.look_from(Vector3(p.x, y + 22.0, p.y + 8.0), Vector3(p.x, y, p.y))   # (straight down, the look's basis breaks)
		await _snap("overlap_%d_top" % i)
	quit(0)
