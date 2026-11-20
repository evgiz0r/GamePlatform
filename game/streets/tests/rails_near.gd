extends SceneTree
## The pedestrian railing panels (furniture's 1.2 m "rail" kit, by the zebras on main roads)
## placed within R metres of AT: each one's middle, the way it runs, and whether its ends are
## off the asphalt by the game's own reckoning. Panels across Tel Aviv's Kaplan in a user's
## screenshot stood only when the city was built as the game builds it (the start first, the
## rest while driving), so run it both ways:
##   AT=-290,170 STREETS_BUILD_ALL=0 tests/run.sh rails_near 7     (waits for the whole build)
##   AT=-290,170 tests/run.sh rails_near 7
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
	var xz := OS.get_environment("AT").split(",")
	var at := Vector2(float(xz[0]), float(xz[1]))
	var rad := float(OS.get_environment("R")) if OS.get_environment("R") != "" else 40.0
	var kit: Mesh = g._furn._kits.get("rail")
	var n := 0
	var bad := 0
	for mmi: MultiMeshInstance3D in g.world.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := mmi.multimesh
		if mm == null or mm.mesh != kit:
			continue
		for i in range(mm.instance_count):
			var t := mmi.global_transform * mm.get_instance_transform(i)
			var m := Vector2(t.origin.x, t.origin.z)
			if m.distance_to(at) > rad:
				continue
			n += 1
			var along := Vector2(t.basis.x.x, t.basis.x.z).normalized()
			var ends_off: bool = g._off_road(m - along * 0.6, 0.0) and g._off_road(m + along * 0.6, 0.0)
			if not ends_off:
				bad += 1
			print("  panel at %s running %s, ends off the road: %s" % [m.snapped(Vector2(0.1, 0.1)), along.snapped(Vector2(0.01, 0.01)), ends_off])
	print("railing panels within %.0f m of %s: %d, with an end on the road: %d" % [rad, at, n, bad])
	quit(0)
