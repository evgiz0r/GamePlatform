extends SceneTree
## The "go to…" list: open it, shoot it (jump to chosen, as the game starts), choose
## "drive to", shoot it again, then pick a street and check what happened (jumped: the car
## is there; driving: a destination is set). Shots in OUT.   tests/run.sh picker 4
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.3).timeout
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
	g._open_picker()
	await create_timer(0.5).timeout
	print("opened: jump %s, title '%s'" % [g._pick_jump, g._pick_title.text])
	await _snap("1_jump_chosen")
	g._pick_tap(g._pick_drive_btn.get_global_rect().get_center())
	await create_timer(0.3).timeout
	print("after 'drive to': jump %s, title '%s'" % [g._pick_jump, g._pick_title.text])
	await _snap("2_drive_chosen")
	g._pick_tap(g._pick_jump_btn.get_global_rect().get_center())
	await create_timer(0.3).timeout
	var from: Vector2 = g._pos
	var far := ""
	var at := Vector2.ZERO
	for r: Dictionary in g._roads:
		if r["drive"] and String(r["name"]) != "" and (r["pts"] as PackedVector2Array)[0].distance_to(from) > 150.0:
			far = r["name"]
			at = (r["pts"] as PackedVector2Array)[0]
			break
	g._go_to(far, at)
	await create_timer(1.0).timeout
	print("jumped to '%s': car %.0f m from it (was %.0f), picker closed %s" % [far, g._pos.distance_to(at), from.distance_to(at), g._picker == null])
	quit(0)
