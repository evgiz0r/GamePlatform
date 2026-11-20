extends SceneTree
## Shots from the car on one street where it meets roundabouts (or any junction with
## RINGS_ONLY=0): STREET=<part of its name>, the car put down 25 m before each, facing it, and
## left a moment for the chase camera. Prints the green areas (parks, lawns) within 40 m of
## each and how much of them lies under the street's own width. For checking a user's
## screenshot of a place by its street.   STREET=מנחם tests/run.sh street_at 3
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var want := OS.get_environment("STREET")
	var rings_only := OS.get_environment("RINGS_ONLY") != "0"
	var spots: Array = []   # [junction point, way in]
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or not (String(r["name"]).contains(want) or String(r["en"]).contains(want)):
			continue
		var ids: PackedInt32Array = r["ids"]
		var pts: PackedVector2Array = r["pts"]
		for k in [0, ids.size() - 1]:
			var n: int = ids[k]
			var ring := false
			for e: Vector2i in g._node_roads[n]:
				if (g._roads[e.x] as Dictionary).get("ring", false):
					ring = true
			if rings_only and not ring:
				continue
			var j: int = k - 1 if k > 0 else 1
			var din: Vector2 = (pts[k] - pts[j]).normalized()
			if spots.any(func(s): return (s[0] as Vector2).distance_to(pts[k]) < 30.0):
				continue
			spots.append([pts[k], din])
	print("%d places on '%s'" % [spots.size(), want])
	var most := int(OS.get_environment("MAX")) if OS.get_environment("MAX") != "" else 6
	for i in range(mini(most, spots.size())):
		var c: Vector2 = spots[i][0]
		var din: Vector2 = spots[i][1]
		var near: Array = []
		for kind: String in ["park", "grass"]:
			for ring: PackedVector2Array in g._area_rings.get(kind, []):
				var box: Rect2 = g._bld_box_of(ring)
				if box.grow(40.0).has_point(c):
					near.append("%s %.0f m2" % [kind, absf(g._area_signed(ring))])
		print("  %d at %s, way in %s; green near: %s" % [i, c.round(), din.snapped(Vector2(0.01, 0.01)), ", ".join(near)])
		g._land_on_road(c - din * 25.0, 12.0, din)
		await create_timer(2.5).timeout
		await _snap("place_%d" % i)
	quit(0)
