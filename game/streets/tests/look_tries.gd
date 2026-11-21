extends SceneTree
## The same two pictures for each look being tried (STREETS_TRY, see streets.gd `_try`): the
## start's view behind the car, as the game shows it (Givatayim's start, Katznelson), and a
## closer look up at the blocks on its right. Shots try_<STREETS_TRY or "now">_{start,close}.png
## in $OUT (and _under: nearer, looking up at that block's balconies); put them side by side to see which gets more real.
##   STREETS_TRY=aecr FULL=1 STREETS_BUILD_ALL=0 RES=1280x720 OUT=<dir> game/streets/tests/run.sh look_tries 1
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(4.0).timeout   # (the squares round the start built, the camera settled)
	var tag := OS.get_environment("STREETS_TRY") if OS.get_environment("STREETS_TRY") != "" else "now"
	await _snap("try_%s_start" % tag)
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var fw: Vector2 = g._fwd()
	var right := Vector2(-fw.y, fw.x)
	var p: Vector2 = g._pos
	var eye := p + right * 1.5 - fw * 2.0
	var at := p + fw * 14.0 + right * 9.0
	g.look_from(Vector3(eye.x, g._h(eye) + 1.7, eye.y), Vector3(at.x, g._h(at) + 6.0, at.y))
	g._sky_follow()
	await _snap("try_%s_close" % tag)
	# nearer, under the balconies of the block on the right: the creases, lip, coping, railings
	eye = p + fw * 9.0 + right * 3.0
	at = p + fw * 15.0 + right * 10.0
	g.look_from(Vector3(eye.x, g._h(eye) + 1.7, eye.y), Vector3(at.x, g._h(at) + 7.0, at.y))
	g._sky_follow()
	await _snap("try_%s_under" % tag)
	print("shots in ", OS.get_environment("OUT"))
	quit()
