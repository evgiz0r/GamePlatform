extends SceneTree
## People's feet against the surface drawn under them: for each walker within 60 m (after the
## walkers have spread, WAIT s), a ray straight down from knee height against the meshes drawn
## there (the pavement's, the kerbs', the road's: MeshInstance3D only), and how far the drawn
## surface is above (+) or below the person's feet. The user: "their legs are somewhat bit
## inside the ground". Prints each and the spread; headless.
##   STREETS_BUILD_ALL=0 LEVEL=1 $GODOT --headless --path . -s res://game/streets/tests/feet_ground.gd
var g: Node
var _faces := {}   # mesh instance id -> its triangles in world space

func _initialize() -> void:
	_run()

func _tris(mi: MeshInstance3D) -> PackedVector3Array:
	var id := mi.get_instance_id()
	if not _faces.has(id):
		var f := mi.mesh.get_faces()
		var xf := mi.global_transform
		for i in range(f.size()):
			f[i] = xf * f[i]
		_faces[id] = f
	return _faces[id]

## the highest drawn surface under p between y_lo and y_hi, or NAN
func _surface(p: Vector2, y_lo: float, y_hi: float) -> float:
	var best := NAN
	var from := Vector3(p.x, y_hi, p.y)
	for mi: MeshInstance3D in g.world.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.get_parent() is Node3D and (mi.get_parent() as Node3D).get_script() != null and String((mi.get_parent() as Node3D).get_script().resource_path).ends_with("actor3d.gd"):
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if p.x < ab.position.x or p.x > ab.end.x or p.y < ab.position.z or p.y > ab.end.z or ab.position.y > y_hi or ab.end.y < y_lo:
			continue
		if mi.get_aabb().size.length() > 900.0:
			pass
		var f := _tris(mi)
		for i in range(0, f.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, f[i], f[i + 1], f[i + 2])
			if hit != null and (hit as Vector3).y >= y_lo and (is_nan(best) or (hit as Vector3).y > best):
				best = (hit as Vector3).y
	return best

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var wait := float(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 6.0
	await create_timer(wait).timeout
	g.set_physics_process(false)
	var diffs: Array = []
	for w: Dictionary in g._walkers:
		var a: Node3D = w["actor"]
		var p := Vector2(a.position.x, a.position.z)
		if not a.visible or p.distance_to(g._pos) > 60.0:
			continue
		var s := _surface(p, a.position.y - 0.6, a.position.y + 0.5)
		if is_nan(s):
			print("  walker %d at %s: nothing drawn under it" % [g._walkers.find(w), Vector2i(p)])
			continue
		var d: float = s - a.position.y
		diffs.append(d)
		var lw: Dictionary = g._walkers[int(w["with"])] if w.has("with") else w
		var hit: Dictionary = g._nearest_seg(p, 5.0, true, true)
		print("  walker %d at %s: the surface %+.3f m from its feet%s  [crossing %s, edge %.2f, corner fill %s, walk_y %+.3f, pave %+.3f over the ground]" % [g._walkers.find(w), Vector2i(p), d,
			"  (in it)" if d > 0.03 else "", float(lw.get("s", 0.0)) < float(lw.get("cross", 0.0)), float(hit.get("edge", INF)),
			g._in_corner_fill(p, 0.0), float(g._walk_y(p)) - float(g._h(p)), s - float(g._h(p))])
	diffs.sort()
	if not diffs.is_empty():
		print("surface over the feet: min %+.3f, median %+.3f, max %+.3f (of %d)" % [diffs[0], diffs[diffs.size() / 2], diffs[diffs.size() - 1], diffs.size()])
	quit()
