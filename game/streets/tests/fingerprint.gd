extends SceneTree
## A refactor's safety net: the whole city built (run.sh builds every square), then a hash of
## everything it drew -- every mesh's vertices, colours and UVs, every multimesh's transforms,
## every node's place -- and of a minute of autodrive (the car's path, the traffic's places).
## Run it before a change that should change nothing and after: the lines must match.
##   HASH_SECS=60 game/streets/tests/run.sh fingerprint 4
## Needs a window (run.sh's xvfb): headless, the dummy renderer keeps no mesh data.
## Counts and hashes per kind are printed too, so a mismatch says where it is.
var g: Node

func _initialize() -> void:
	_run()

func _find() -> void:
	for n in root.find_children("*", "Node2D", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
			g = n

func _run() -> void:
	seed(12345)
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		_find()
	await create_timer(1.0).timeout
	_hash_world("built")
	var secs := float(OS.get_environment("HASH_SECS")) if OS.get_environment("HASH_SECS") != "" else 30.0
	g._set_auto(true)
	var path := PackedFloat64Array()
	var ticks := int(secs * Engine.physics_ticks_per_second)
	for i in ticks:
		await physics_frame
		if i % 30 == 0:
			path.append(snappedf(g._pos.x, 0.01))
			path.append(snappedf(g._pos.y, 0.01))
	print("FP drive path ", path.size() / 2, " points hash ", hash(path), " end ", g._pos.snapped(Vector2(0.1, 0.1)))
	_hash_world("after drive")
	quit(0)

func _hash_world(label: String) -> void:
	# one line per thing drawn, sorted, so the order squares were built in does not matter:
	# FPMESH <hash of its vertices, colours, UVs, indices> -- the town's geometry, which must not
	# change; FPMM <instances> <hash of its mesh> <hash of the instances' buffer> -- a multimesh
	# (people and cars move, so a few of these differ between any two runs: compare to a run of
	# the code before, see fp_compare.py); FPNODE <class> <transform> for still things
	var lines := PackedStringArray()
	var info := PackedStringArray()
	for n: Node in g.find_children("*", "", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
			var mi := n as MeshInstance3D
			lines.append("FPMESH %d %s" % [_mesh_hash(mi.mesh), mi.visible])
			info.append("FPMESH %d | %s | %s | %s" % [_mesh_hash(mi.mesh), _what(mi), mi.mesh.get_aabb(), _mats(mi.mesh)])
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			var mm := (n as MultiMeshInstance3D).multimesh
			lines.append("FPMM %d %d %d" % [mm.instance_count, _mesh_hash(mm.mesh) if mm.mesh is ArrayMesh else 0, hash(mm.buffer) if mm.instance_count > 0 else 0])
		elif n is Node3D:
			lines.append("FPNODE %s %d" % [n.get_class(), hash((n as Node3D).transform)])
		else:
			lines.append("FPOTHER %s" % n.get_class())
	lines.sort()
	var f := FileAccess.open(OS.get_environment("OUT") + "/fp_%s.txt" % label.replace(" ", "_"), FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	info.sort()
	f = FileAccess.open(OS.get_environment("OUT") + "/fpinfo_%s.txt" % label.replace(" ", "_"), FileAccess.WRITE)
	f.store_string("\n".join(info))
	f.close()
	print("FP %s %d things, hash of all %d" % [label, lines.size(), hash(lines)])

func _mesh_hash(m: ArrayMesh) -> int:
	var h := m.get_surface_count()
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		h = hash([h, a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_COLOR], a[Mesh.ARRAY_TEX_UV], a[Mesh.ARRAY_INDEX]])
	return h

## where a node hangs, without the engine's made-up names (@MeshInstance3D@123)
func _what(n: Node) -> String:
	var out := PackedStringArray()
	var at := n
	while at != null and at != g:
		out.append(at.get_class() if String(at.name).begins_with("@") else String(at.name))
		at = at.get_parent()
	out.reverse()
	return "/".join(out)

func _mats(m: ArrayMesh) -> String:
	var out := PackedStringArray()
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		var v := m.surface_get_array_len(s)
		out.append("%d:%s" % [v, (mat.shader.code.substr(0, 60).replace("\n", " ") if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null else str(mat.get_class()) if mat != null else "-")])
	return ", ".join(out)
