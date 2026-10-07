extends SceneTree
## Screenshot of the main menu. Run through tools/menu_shot.sh, not directly.
## With `-- --screen=other` it screenshots the "other" shelf instead of the front page,
## and with `-- --screen=levels:<game>` that game's start screen
## (new game or pick a level).
func _init() -> void:
	var screen := "menu"
	for raw in OS.get_cmdline_user_args():
		var kv := (raw as String).trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and kv[0] == "screen":
			screen = kv[1]
	await create_timer(1.0).timeout
	var flow := root.get_node("Flow")
	if screen == "other":
		flow._show_other()
	elif screen.begins_with("levels:"):
		for g in flow.list_games():
			if g["id"] == screen.trim_prefix("levels:"):
				flow._show_levels(g)
		screen = screen.replace(":", "_")
	await create_timer(1.0).timeout
	var img := root.get_viewport().get_texture().get_image()
	var path := "res://shots/%s.png" % screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(path)
	print("[shot] ", ProjectSettings.globalize_path(path))
	quit()
