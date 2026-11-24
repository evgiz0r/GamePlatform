extends SceneTree
## Kerb pieces lying on a street's asphalt: the tops of the kerbs' mesh (as world_checks'
## pavings_overlap reads it) whose middle is more than DEEP m (default 0.6) inside a street's
## asphalt, away from its islands (a median, a link island, a roundabout's middle: their
## kerbs stand on purpose). Grouped by 10 m square, worst first, with the street, so a stray
## piece -- a corner laid one by one where the probes missed the asphalt by a little, left
## standing near a roundabout's zebra in Ashdod -- can be found and looked at.
##   LEVEL=3 STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/kerbs_on_road.gd
## By default only those within 8 m of a zebra (where the reported piece was: everywhere,
## Ashdod reads 781 squares, nearly all islands and medians mapped as their own roads);
## ALL=1 every one. Places on the tests' private list are counted, not printed.
## Good: none, or only pieces that are islands the check does not know.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	var deep := float(OS.get_environment("DEEP")) if OS.get_environment("DEEP") != "" else 0.6
	var spots := {}   # 10 m square -> [count, a point, street, depth]
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var hidden := 0
	var all := OS.get_environment("ALL") != ""
	var zebras: Array = []
	for ni: int in g._crossing_nodes:
		zebras.append(g._nodes[ni])
	var tops := 0
	for mi: MeshInstance3D in g.world.find_children("*", "MeshInstance3D", true, false):
		var m := mi.mesh as ArrayMesh
		if m == null:
			continue
		for s in range(m.get_surface_count()):
			if m.surface_get_material(s) != g._kerb_mat:
				continue
			var arr := m.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := idx.size() if not idx.is_empty() else v.size()
			var xf := mi.global_transform
			for i in range(0, n, 3):
				var i0 := idx[i] if not idx.is_empty() else i
				if nrm[i0].y < 0.9 or col[i0].b > 0.5:
					continue   # pavement, or a kerb's face: a kerb's top only
				var a := xf * v[i0]
				var b := xf * v[(idx[i + 1] if not idx.is_empty() else i + 1)]
				var c := xf * v[(idx[i + 2] if not idx.is_empty() else i + 2)]
				var mid := Vector2(a.x + b.x + c.x, a.z + b.z + c.z) / 3.0
				tops += 1
				var hit: Dictionary = g._nearest_seg(mid, 20.0, true, false)
				if hit.is_empty() or float(hit["edge"]) > -deep:
					continue
				var r: Dictionary = g._roads[int(hit["road"])]
				if not g._kerbed(r) or r.has("ys"):
					continue
				if g._in_junction(mid, 0.0):
					continue   # (a roundabout's middle, a junction's islands)
				if not all:
					var by_zebra := false
					for z: Vector2 in zebras:
						if z.distance_squared_to(mid) < 64.0:
							by_zebra = true
							break
					if not by_zebra:
						continue
				if priv.near(avoid, mid):
					hidden += 1
					continue
				var k := Vector2i(floori(mid.x / 10.0), floori(mid.y / 10.0))
				if not spots.has(k):
					spots[k] = [0, mid, String(r.get("en", "")) if String(r.get("en", "")) != "" else String(r["name"]), 0.0]
				spots[k][0] += 1
				spots[k][3] = maxf(float(spots[k][3]), -float(hit["edge"]))
	var keys := spots.keys()
	keys.sort_custom(func(x, y): return spots[x][0] > spots[y][0])
	print("kerbs on the road%s: %d squares with kerb tops over %.1f m into a street's asphalt (of %d kerb-top triangles; %d at private places, not shown)" % [
		"" if all else " by a zebra", keys.size(), deep, tops, hidden])
	for k in keys.slice(0, int(OS.get_environment("N")) if OS.get_environment("N") != "" else 15):
		print("  %4d at %s on '%s', up to %.1f m in" % [spots[k][0], (spots[k][1] as Vector2).round(), spots[k][2], spots[k][3]])
	quit(0)
