extends SceneTree
## Where people's feet are against the ground they stand on: each of the kit's figures twice,
## as the kit draws it and as the street draws it (_humanize: a grown-up's proportions, the
## thighs stretched), standing (Idle) and mid-stride (Walk). Prints the lowest foot or toe
## bone's height over the person's own origin -- the street's should match the kit's, or the
## feet are in the pavement (the user: "their legs are somewhat bit inside the ground").
## Headless: STREETS_BUILD_ALL=0 LEVEL=4 $GODOT --headless --path . -s res://game/streets/tests/foot_sink.gd
var g: Node

func _initialize() -> void:
	_run()

func _low_foot(a: Node3D) -> float:
	var low := INF
	for sk: Skeleton3D in a.find_children("*", "Skeleton3D", true, false):
		for i in range(sk.get_bone_count()):
			var n := sk.get_bone_name(i).to_lower()
			if n.contains("foot") or n.contains("toe"):
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
				low = minf(low, p.y - a.global_position.y)
	return low

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(0.5).timeout
	for clip: String in ["Idle", "Walk"]:
		for who: String in g.PEOPLE:
			var row: Array = []
			for human: bool in [false, true]:
				var a = load("res://shell/actor3d.gd").new()
				g.world.add_child(a)
				a.position = Vector3(0, 100, 0)
				a.set_character(who, 1.7)
				if human:
					g._humanize(a, 7)
				a.play(clip, true, 1.0)
				for _f in range(20):
					await process_frame
				row.append(_low_foot(a))
				a.queue_free()
			print("%-6s %-16s lowest foot bone: kit %.3f m, street %.3f m -> %+.3f" % [clip, who, row[0], row[1], row[1] - row[0]])
	quit()
