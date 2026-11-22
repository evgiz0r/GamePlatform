extends SceneTree
## What the loading screen says, and when: every new text under the loading bar (the spinner's
## dots dropped), with the seconds since the start. The squares round the start name the
## stage they are on, "kerbs and pavements (5 of 13)" (TILE_STAGES).
##   LEVEL=7 $GODOT --headless --path . -s res://game/streets/tests/load_text.gd
var g: Node
func _initialize() -> void:
	_run()
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	var t0 := Time.get_ticks_msec()
	var last := ""
	while g == null or not g._loaded:
		await process_frame
		if g == null:
			for n in root.find_children("*", "Node2D", true, false):
				if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
					g = n
			continue
		if g._loading == null:
			continue
		var t: String = g._loading.text.replace("\n", "  |  ").rstrip(" ·")
		if t != last:
			print("%5.1f s  %s" % [(Time.get_ticks_msec() - t0) / 1000.0, t])
			last = t
	print("%5.1f s  loaded" % [(Time.get_ticks_msec() - t0) / 1000.0])
	quit()
