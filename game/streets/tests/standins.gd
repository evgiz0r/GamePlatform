extends SceneTree
## The city from above before it is built (standins.gd): the view goes up over the town as
## soon as the car is shown, while the squares round it are all that is built, and shots are
## taken as the rest goes up. Prints how many squares got a stand-in and how long making them
## all took, and checks that no built square still has one (it would lie over the real
## streets) and that every square still to build has one.
##   LEVEL=3 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/standins.gd
## (STREETS_BUILD_ALL=0 is the point: with the whole city built first there is nothing to stand in for.)
## PASS: stand-ins made, none left on a built square, none missing on an unbuilt one, at
## every shot. Shots: $OUT/standins_NN.png.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.1).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	g._zoom_set(1.0)
	# look over a part of town still to build, ZOOM_AWAY m from the car (default 1200)
	var away := float(OS.get_environment("ZOOM_AWAY")) if OS.get_environment("ZOOM_AWAY") != "" else 1200.0
	var far := Vector2.ZERO
	for t: Vector2i in g._tiles_todo:
		var c: Vector2 = g._tile_rect(t).get_center()
		if absf(c.distance_to(g._pos) - away) < absf(far.distance_to(g._pos) - away) and not (g._tile_blds.get(t, []) as Array).is_empty():
			far = c
	g._zoom_off = far - g._pos
	var out := OS.get_environment("OUT")
	var bad := 0
	var shots := 0
	for i in range(8):
		await create_timer(2.5 if i < 4 else 6.0).timeout
		var si = g._standins
		var made: int = si.made if si != null else 0
		var left: int = si._by_tile.size() if si != null else 0
		var on_built := 0
		var missing := 0
		if si != null:
			for t: Vector2i in si._by_tile:
				if g._tiles_done.has(t) and t != g._tile:   # (the one being built keeps it to its end)
					on_built += 1
					print("  on a built square: %s, still in the to-do list: %s" % [t, g._tiles_todo.has(t)])
			if si.ms > 0:   # (all made: every square still to build has one, unless it is empty)
				for t: Vector2i in g._tiles_todo:
					if not si._by_tile.has(t) and not (g._tile_blds.get(t, []) as Array).is_empty():
						missing += 1   # (one with roads only within 15 m of its edge has nothing in it to draw)
						print("  missing: %s, built %s" % [t, g._tiles_done.has(t)])
		bad += on_built + missing
		var vis: bool = si != null and si.root != null and si.root.visible
		print("STANDINS shot %d: squares built %d, to build %d; stand-ins made %d, left %d, on built squares %d, missing %d, shown %s, made in %d ms" % [
			i, g._tiles_done.size(), g._tiles_todo.size(), made, left, on_built, missing, vis, si.ms if si != null else -1])
		if out != "":
			root.get_viewport().get_texture().get_image().save_png(out + "/standins_%02d.png" % i)
			shots += 1
	var ok: bool = bad == 0 and g._standins != null and g._standins.made > 0
	print("STANDINS: %s (%d wrong)" % ["PASS" if ok else "FAIL", bad])
	quit(0)
