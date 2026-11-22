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
	# does everything fit? every button and label on the screen inside it (a start screen's
	# third group once ran off a phone's edge, and only a screenshot showed it)
	var screen_rect := root.get_viewport().get_visible_rect()
	var over: Array = []
	for c in flow.find_children("*", "Control", true, false):
		var ctl := c as Control
		if ctl.is_visible_in_tree() and (ctl is Button or ctl is Label) and not screen_rect.encloses(ctl.get_global_rect().grow(-1.0)):
			over.append("%s '%s'" % [ctl.get_class(), ctl.get("text")])
	print("[fits] " + ("ok" if over.is_empty() else "OFF THE SCREEN: " + ", ".join(over)))
	quit()
