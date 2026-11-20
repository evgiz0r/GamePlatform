extends SceneTree
## Where a frame's cost goes, in numbers that do not depend on this machine's (software)
## renderer: for a few views -- the car at the start, driving a main road, from above -- at
## the browser's starting quality (2) and the top (3): the draw calls, triangles and objects
## of the view and of the shadow pass (Viewport.get_render_info), the kinds of drawables in
## them, and the script's own average frame (the game's profiler, `_prof_avg`) over a few
## seconds of autodrive. Then the scene's totals: nodes, mesh instances, multimeshes and
## their instances, distinct shader kinds (each one the browser compiles while loading).
##   tests/run.sh perf_dive 7            (STREETS_BUILD_ALL=1, the default: everything built first)
##   STREETS_BUILD_ALL=0 tests/run.sh perf_dive 7   (as the game builds: the totals after the rest is done)
var g: Node
func _initialize() -> void:
	_run()

var _names := {}   # a distinctive line of each of the game's shaders -> the constant's name

func _info(what: int) -> int:
	return RenderingServer.get_rendering_info(what)

func _sample(label: String) -> void:
	# a few frames to settle, then the numbers of the last
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	# (the whole frame: the view, the shadow map and the HUD together)
	print("%-26s %5d draws %9d triangles %5d objects" % [label,
		_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), _info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])

## the drawables in view (range and frustum) by kind, the biggest few by triangles
func _kinds(label: String) -> void:
	var cam: Camera3D = g.cam
	var by := {}   # kind -> [count, triangles]
	for gi: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if not gi.is_visible_in_tree():
			continue
		var box := gi.global_transform * gi.get_aabb()
		var d := cam.global_position.distance_to(box.get_center())
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + box.size.length() * 0.5:
			continue
		var out := false
		for pl: Plane in cam.get_frustum():
			var e := box.size * 0.5
			if pl.distance_to(box.get_center()) > absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z:
				out = true
		if out:
			continue
		var key := gi.get_class()
		var tris := 0
		if gi is MultiMeshInstance3D:
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null:
				continue
			var n := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			key = "multimesh " + _mat_name(mm.mesh.surface_get_material(0) if mm.mesh.get_surface_count() > 0 else null, gi)
			tris = _tris(mm.mesh) * n
		elif gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh == null:
				continue
			key = ("person part" if mi.get_parent() is Skeleton3D else "mesh ") + _mat_name(mi.mesh.surface_get_material(0) if mi.mesh.get_surface_count() > 0 else null, gi)
			tris = _tris(mi.mesh)
		if not by.has(key):
			by[key] = [0, 0]
		by[key][0] += 1
		by[key][1] += tris
	var rows: Array = []
	for k: String in by:
		rows.append([k, by[k][0], by[k][1]])
	rows.sort_custom(func(a, b): return a[2] > b[2])
	var words: Array = []
	for r: Array in rows.slice(0, 10):
		words.append("%s x%d %dk" % [r[0], r[1], r[2] / 1000])
	print("  in view (%s): %s" % [label, ", ".join(words)])

func _mat_name(m: Material, gi: GeometryInstance3D) -> String:
	if gi.material_override != null:
		m = gi.material_override
	if m == null:
		return "?"
	for pair: Array in [[g._tone_material, "TONE (batched)"], [g._roof_mat, "ROOF"], [g._wall_mat, "WALL"], [g._kerb_mat, "KERB"],
			[g._ground_shader_mat, "GROUND"], [g._car_shader_mat, "CAR"]]:
		if pair[0] != null and m == pair[0]:
			return pair[1]
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		var code := (m as ShaderMaterial).shader.code
		for key: String in _names:
			if code.contains(key):
				return _names[key]
		return "shader#%d" % (hash(code) % 1000)
	if m is StandardMaterial3D:
		return "std " + (m as StandardMaterial3D).albedo_color.to_html(false)
	return m.get_class()

func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	print(g._load_text())
	# the game's shaders by name: each constant's longest line, looked for in a material's code
	for sc: Script in [g.get_script(), g._furn.get_script()]:
		var consts := sc.get_script_constant_map()
		for k: String in consts:
			if typeof(consts[k]) == TYPE_STRING and String(consts[k]).contains("shader_type"):
				var longest := ""
				for line: String in String(consts[k]).split("\n"):
					if line.strip_edges().length() > longest.length() and not line.strip_edges().begins_with("//"):
						longest = line.strip_edges()
				_names[longest] = k
	var start: Vector2 = g._pos
	# a main road's spot: the longest primary or secondary road's middle
	var main := start
	var best := 0.0
	for r: Dictionary in g._roads:
		if r["drive"] and r["k"] in ["primary", "secondary", "trunk"]:
			var pts: PackedVector2Array = r["pts"]
			var L := 0.0
			for j in range(pts.size() - 1):
				L += pts[j].distance_to(pts[j + 1])
			if L > best:
				best = L
				main = pts[pts.size() / 2]
	for q: int in [2, 3]:
		g._set_quality(q)
		g._land_on_road(start, 20.0, Vector2.ZERO)
		await create_timer(1.5).timeout
		await _sample("start, quality %d" % q)
		if q == 2:
			_kinds("start, q2")
		g._land_on_road(main, 20.0, Vector2.ZERO)
		await create_timer(1.5).timeout
		await _sample("main road, quality %d" % q)
	g._set_quality(2)
	g._zoom_set(g.ZOOM_UP)
	await create_timer(3.0).timeout
	await _sample("from above, quality 2")
	_kinds("from above")
	g._zoom_set(0.0)
	await create_timer(2.0).timeout
	# the script's own frame while driving (the profiler's 2 s average, after a while)
	g._set_auto(true)
	for i in range(3):
		await create_timer(4.0).timeout
	print("script while driving: %s" % g._prof_avg)
	# the scene's totals, once the rest of the city is built (STREETS_BUILD_ALL=0: as in the
	# game, the start's squares behind the loading text and the rest while driving -- only
	# those are indexed, see _index_into)
	var waited := 0.0
	while g._bg_build and waited < 900.0:
		await create_timer(1.0).timeout
		waited += 1.0
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var meshes := 0
	var mms := 0
	var inst := 0
	var keys := {}
	for gi: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		keys[g._shader_key(gi)] = true
		if gi is MultiMeshInstance3D:
			mms += 1
			var mm := (gi as MultiMeshInstance3D).multimesh
			if mm != null:
				inst += mm.instance_count
		elif gi is MeshInstance3D:
			meshes += 1
	print("scene: %d nodes, %d mesh instances, %d multimeshes (%d instances), %d shader kinds (codes x plain/instanced x shadow: the warm-up's steps)" % [nodes, meshes, mms, inst, keys.size()])
	# the static meshes' vertices by material (each a vertex of a triangle soup unless indexed):
	# where the buffers' memory goes
	var verts := {}   # name -> [meshes, vertices, indexed meshes]
	var all_v := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.mesh is ArrayMesh:
			continue
		var am := mi.mesh as ArrayMesh
		for si in range(am.get_surface_count()):
			var name := _mat_name(am.surface_get_material(si), mi)
			if not verts.has(name):
				verts[name] = [0, 0, 0]
			var n := am.surface_get_array_len(si)
			verts[name][0] += 1
			verts[name][1] += n
			if am.surface_get_array_index_len(si) > 0:
				verts[name][2] += 1
			all_v += n
	var rows: Array = []
	for k: String in verts:
		rows.append([k, verts[k][0], verts[k][1], verts[k][2]])
	rows.sort_custom(func(a, b): return a[2] > b[2])
	print("static meshes: %.2f M vertices in all" % (all_v / 1.0e6))
	var bv: Array = []
	for k: String in g._dressing:
		if k.begins_with("batched vertices: "):
			bv.append([int(g._dressing[k]), k.substr(18)])
	bv.sort_custom(func(a, b): return a[0] > b[0])
	print("  batched, by tone: " + ", ".join(bv.slice(0, 14).map(func(x): return "%s %.2f M" % [x[1], x[0] / 1.0e6])))
	# and by who added them (debug builds: the function and line, the kit's vertices)
	var bm: Array = []
	for k: String in g._dressing:
		if k.begins_with("batched by: "):
			bm.append([int(g._dressing[k]), k.substr(12)])
	bm.sort_custom(func(x, y): return x[0] > y[0])
	print("  batched, by who: " + ", ".join(bm.slice(0, 16).map(func(x): return "%s %.2f M" % [x[1], x[0] / 1.0e6])))
	for r: Array in rows.slice(0, 12):
		print("  %-28s %5d surfaces %6.2f M vertices (%d indexed)" % [r[0], r[1], float(r[2]) / 1.0e6, r[3]])
	print("video memory %.0f MB, textures %.0f MB, buffers %.0f MB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])
	quit(0)
