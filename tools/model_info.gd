extends SceneTree
## Prints what a 3D asset actually contains, so nobody has to guess scale or clip names:
##   tools/model_info.sh res://assets/models/car/sedan.glb
## Output: bounding box (size, centre), mesh count, node names, animation clips.
## Needs the asset imported first (tools/*.sh do that when .godot/ is missing).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: model_info.sh <res://path.glb> [more paths]")
		quit(1)
		return
	for path in args:
		_describe(path)
	quit(0)

func _describe(path: String) -> void:
	print("== " + path)
	if not ResourceLoader.exists(path):
		print("   not found (is it imported? run: $GODOT --headless --path . --import)")
		return
	var scn: PackedScene = load(path)
	if scn == null:
		print("   failed to load")
		return
	var root: Node3D = scn.instantiate()
	var box := _aabb(root, Transform3D.IDENTITY, AABB(), true)
	print("   size   %s" % str(box.size.snapped(Vector3.ONE * 0.001)))
	print("   centre %s   bottom y=%.3f" % [str(box.get_center().snapped(Vector3.ONE * 0.001)), box.position.y])
	var names: Array = []
	_walk(root, func(n: Node): if n is MeshInstance3D: names.append(n.name))
	print("   meshes %d: %s" % [names.size(), ", ".join(names.slice(0, 12)) + (" ..." if names.size() > 12 else "")])
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		print("   clips  %s" % ", ".join(ap.get_animation_list()))
	root.free()

var _first := true
func _aabb(n: Node, xf: Transform3D, acc: AABB, first: bool) -> AABB:
	if n is Node3D:
		xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var b: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
		acc = b if first else acc.merge(b)
		first = false
	for c in n.get_children():
		var r := _aabb(c, xf, acc, first)
		if r.size != Vector3.ZERO or not first:
			acc = r
			first = false
	return acc

func _walk(n: Node, f: Callable) -> void:
	f.call(n)
	for c in n.get_children():
		_walk(c, f)
