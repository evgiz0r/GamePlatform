extends RefCounted
## Models made with Blender (tools/blender_model.sh -> assets/models/made/), stamped into a
## square's batches: a model's triangles go into the same buffers as the boxes around them --
## no node, no draw of its own. Each surface keeps its material's ROLE (tools/blender/kit.py's
## names: "paint", "paint2", "paint3", "metal", "wood", "rubber", "dark"...), which the caller
## turns into a colour (`stamp`) or into one of its buffers by palette role (`stamp_into`).

const DIR := "res://assets/models/made/"

var g: Node
var _tris := {}               ## model -> [[role, PackedVector3Array verts, PackedVector3Array normals], ...]
var stamped := {}             ## for tests: model -> how many put down

func _init(game: Node) -> void:
	g = game

## a model's triangles by surface (loaded once)
func tris(name: String) -> Array:
	if _tris.has(name):
		return _tris[name]
	var out: Array = []
	var ps := load(DIR + name + ".glb") as PackedScene
	if ps == null:
		push_warning("models: no %s%s.glb (tools/blender_model.sh makes it)" % [DIR, name])
		_tris[name] = out
		return out
	var root := ps.instantiate()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var p := mi.get_parent()
		while p != null and p != root and p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var mesh: Mesh = mi.mesh
		for si in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var m := mesh.surface_get_material(si)
			var role := String(m.resource_name) if m != null else ""
			var tv := PackedVector3Array()
			var tn := PackedVector3Array()
			var count := idx.size() if not idx.is_empty() else v.size()
			for k in range(count):
				var i := idx[k] if not idx.is_empty() else k
				tv.append(xf * v[i])
				tn.append((xf.basis * nn[i]).normalized() if i < nn.size() else Vector3.UP)
			out.append([role, tv, tn])
	root.free()
	_tris[name] = out
	return out

## the whole model as one mesh of one surface (positions and normals; the caller's material
## colours it all): for a multimesh of many, as the parks' benches are
var _meshes := {}
func mesh(name: String) -> ArrayMesh:
	if _meshes.has(name):
		return _meshes[name]
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	for surf: Array in tris(name):
		v.append_array(surf[1])
		n.append_array(surf[2])
	var am: ArrayMesh = null
	if not v.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		am = ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[name] = am
	return am

## into one buffer, each surface in the colour `colour.call(role)` gives
func stamp(b, name: String, at: Transform3D, colour: Callable) -> void:
	for surf: Array in tris(name):
		_put(b, surf, at, colour.call(String(surf[0])))
	stamped[name] = int(stamped.get(name, 0)) + 1

## into several buffers, each surface into `bufs[roles[role]]` in white (the buffer's own
## material colours it: a palette role); a role not in `roles` goes to `roles["*"]`
func stamp_into(bufs: Dictionary, roles: Dictionary, name: String, at: Transform3D) -> void:
	for surf: Array in tris(name):
		var key: String = roles.get(String(surf[0]), roles.get("*", ""))
		if bufs.has(key):
			_put(bufs[key], surf, at, Color.WHITE)
	stamped[name] = int(stamped.get(name, 0)) + 1

func _put(b, surf: Array, at: Transform3D, col: Color) -> void:
	var tv: PackedVector3Array = surf[1]
	var tn: PackedVector3Array = surf[2]
	for k in range(0, tv.size() - 2, 3):
		var nrm := (at.basis * (tn[k] + tn[k + 1] + tn[k + 2])).normalized()
		b.tri(at * tv[k], at * tv[k + 1], at * tv[k + 2], nrm, col)
