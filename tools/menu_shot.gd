extends SceneTree
## Screenshot of the main menu. Run through tools/menu_shot.sh, not directly.
func _init() -> void:
	await create_timer(2.0).timeout
	var img := root.get_viewport().get_texture().get_image()
	var path := "res://shots/menu.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(path)
	print("[shot] ", ProjectSettings.globalize_path(path))
	quit()
