extends SceneTree
## Screenshot of the main menu. Run through tools/menu_shot.sh, not directly.
## With `-- --screen=other` it screenshots the "other" shelf instead of the front page.
func _init() -> void:
	var screen := "menu"
	for raw in OS.get_cmdline_user_args():
		var kv := (raw as String).trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and kv[0] == "screen":
			screen = kv[1]
	await create_timer(1.0).timeout
	if screen == "other":
		root.get_node("Flow")._show_other()
	await create_timer(1.0).timeout
	var img := root.get_viewport().get_texture().get_image()
	var path := "res://shots/%s.png" % screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(path)
	print("[shot] ", ProjectSettings.globalize_path(path))
	quit()
