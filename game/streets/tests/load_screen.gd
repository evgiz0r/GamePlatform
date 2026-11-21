extends SceneTree
## The loading screen as a player sees it: a still every 0.7 s while the city builds
## (load_<n>.png), to check its text reads over whatever is behind it (a user: "make a better
## font that we can see during load" -- pale letters on Tel Aviv's pale ground).
##   RES=1280x720 tests/run.sh load_screen 7
var g: Node
func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	var n := 0
	while n < 40:
		await create_timer(0.7).timeout
		for c in root.find_children("*", "Node2D", true, false):
			if c.get_script() != null and String(c.get_script().resource_path).ends_with("streets.gd"):
				g = c
		if g != null and g._loaded:
			break
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/load_%02d.png" % n)
		n += 1
	print("%d stills while loading" % n)
	quit(0)
