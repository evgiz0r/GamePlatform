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
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("OUT") + "/" + name + ".png")
	_white_check(img, name)
	_grey_check(img, name)

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

## Nothing sunlit burns out: the share of the shot that is pure white (every channel 252+),
## every 4th pixel. The renderer clips at 1 before any tone curve, so a white wall too bright
## for the light goes flat 255 (a view up at the start's blocks was 19% before roll_white).
## Over 5% is a fail: a few % is the sky's sun-side and the odd glint.
func _white_check(img: Image, name: String) -> void:
	var n := 0
	var hot := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			n += 1
			if c.r >= 0.988 and c.g >= 0.988 and c.b >= 0.988:
				hot += 1
	var share := float(hot) / maxf(1.0, float(n))
	print("%s %s: pure white %.1f%%" % ["FAIL" if share > 0.05 else "ok  ", name, share * 100.0])

## The family "what is grey in life reads grey on screen", for a tint over the whole scene
## (the palette's lavender in the light or the greys): the truly grey pixels of the shot --
## channels within 0.04 of each other (at 0.12 it measured the sand plaster), neither dark nor
## burnt out -- averaged, red and blue each over green. FAIL past 0.07 off. One thing's tint
## (a mauve car) is too small a share of the frame to move it: that needs a look at the thing.
## Bench, 22 Nov: red/green 1.04-1.07, blue/green ~1.015 (the film's greys ~1.03 and 0.98).
func _grey_check(img: Image, name: String) -> void:
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			var hi := maxf(c.r, maxf(c.g, c.b))
			var lo := minf(c.r, minf(c.g, c.b))
			if hi - lo < 0.04 and hi > 0.15 and hi < 0.95:
				sr += c.r
				sg += c.g
				sb += c.b
				n += 1
	if n < 50 or sg <= 0.0:
		print("ok   %s: greys -- too few to judge" % name)
		return
	var rg := sr / sg
	var bg := sb / sg
	var off := absf(rg - 1.0) > 0.07 or absf(bg - 1.0) > 0.07
	print("%s %s: greys red/green %.3f blue/green %.3f (%d px)" % ["FAIL" if off else "ok  ", name, rg, bg, n])
