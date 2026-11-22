extends SceneTree
## Where city_check's "islands on the road" are: every raised island (streets.gd _islands)
## with square metres of it on asphalt -- a road's lanes (_nearest_seg edge < -0.05) or a
## junction's disc -- worst first, with the road under it (kind, name, width), whether the
## island is a mapped area or a made-up slip-road one, and its size. Same sampling as
## world_checks.islands_on_road (a point a square metre).
##   LEVEL=14 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/islands_where.gd
## First found (22 Nov 2026): 0 in the Israeli towns, Bedford and the test town; Delft 39,
## Leiden 87 -- see DEV.md, "Open problems".
var g: Node
const W := preload("res://game/streets/tests/world_checks.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 14
	await create_timer(0.3).timeout   # (the shell's fade needs the tree up first)
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd") \
					and not n.is_queued_for_deletion():
				g = n
	await create_timer(0.5).timeout
	var rows: Array = []
	var total := 0
	for ii in range(g._islands.size()):
		var piece: PackedVector2Array = g._islands[ii]
		var box: Rect2 = g._bld_box_of(piece)
		var n := 0
		var roads := {}
		var junction := 0
		var x := box.position.x + 0.5
		while x < box.end.x:
			var z := box.position.y + 0.5
			while z < box.end.y:
				var p := Vector2(x, z)
				if Geometry2D.is_point_in_polygon(p, piece):
					var hit: Dictionary = g._nearest_seg(p, 14.0, true)
					if not hit.is_empty() and float(hit["edge"]) < -0.05 and not W.high_deck(g, hit):
						n += 1
						var r: Dictionary = g._roads[int(hit["road"])]
						var key := "%s '%s' w %.1f%s" % [r["k"], r["name"], float(r["w"]), " (one-way)" if int(r.get("o", 0)) != 0 else ""]
						roads[key] = int(roads.get(key, 0)) + 1
					elif g._in_junction(p, -0.05):
						n += 1
						junction += 1
				z += 1.0
			x += 1.0
		if n > 0:
			total += n
			var made: bool = g._link_islands.has(piece)
			rows.append([n, box.get_center().round(), "made-up slip-road island" if made else "mapped area",
				roundi(g._area(piece)), roads, junction])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("ISLANDS ON THE ROAD, level %d: %d m2 in %d islands (of %d)" % [lvl, total, rows.size(), g._islands.size()])
	for r in rows.slice(0, 25):
		print("  %3d m2 at %s  %s, %d m2;  on: %s%s" % [r[0], r[1], r[2], r[3], r[4],
			("  junction disc %d" % r[5]) if r[5] > 0 else ""])
	quit()
