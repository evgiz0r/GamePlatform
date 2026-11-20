extends SceneTree
## Which kinds of drawables are in range of the camera (before frustum culling): node counts
## per kind, to see where the draw calls come from.
var g: Node
func _initialize() -> void:
	_run()
func _run() -> void:
	await create_timer(0.5).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var cam: Camera3D = g.cam
	var groups := {}
	var all := 0
	for gi: GeometryInstance3D in g.world.find_children("*", "GeometryInstance3D", true, false):
		all += 1
		if not gi.is_visible_in_tree():
			continue
		var box := gi.global_transform * gi.get_aabb()
		var d := cam.global_position.distance_to(box.get_center())
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end:
			continue
		var out := false
		for pl: Plane in cam.get_frustum():
			var e := box.size * 0.5
			if pl.distance_to(box.get_center()) > absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z:
				out = true
		if out:
			continue
		var key := gi.get_class()
		if gi is MultiMeshInstance3D:
			key = "mm " + str((gi as MultiMeshInstance3D).multimesh.mesh.get_aabb().size.snapped(Vector3.ONE * 0.1))
		elif gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.get_parent() is Skeleton3D:
				key = "person part"
			else:
				var m = mi.mesh.surface_get_material(0) if mi.mesh != null and mi.mesh.get_surface_count() > 0 else null
				key = "mesh %s %s" % [(m.shader.code.substr(0, 0) + "shader" if m is ShaderMaterial else str((m as StandardMaterial3D).albedo_color.to_html(false)) if m is StandardMaterial3D else "?"), str(mi.get_aabb().size.y).pad_decimals(0)]
		var surf := 1
		if gi is MultiMeshInstance3D:
			surf = (gi as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
		elif gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			surf = (gi as MeshInstance3D).mesh.get_surface_count()
		groups[key] = groups.get(key, 0) + surf
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a] > groups[b])
	var tot := 0
	for k in keys:
		tot += groups[k]
	print("%d geometry nodes, %d draws in view" % [all, tot])
	for k in keys.slice(0, 200):
		print("  %4d  %s" % [groups[k], k])
	quit(0)
