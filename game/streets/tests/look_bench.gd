extends SceneTree
## The look bench: a tiny made-up street (cities/look_bench.json, tests/make_look_bench.py)
## that loads in seconds, for trying looks (STREETS_TRY, see streets.gd `_try`) and judging
## them side by side. Not in the game: only this test points it at the bench. Shots in $OUT,
## bench_<STREETS_TRY or "now">_<view>.png:
##   street   down the street from the pavement's edge, eye height
##   facade   a block with balconies, from across the street
##   balcony  closer under its balconies
##   people   along the pavement: walkers, parked cars, the cafe
##   car      a parked car close up
##   STREETS_TRY=ae FULL=1 RES=1280x720 OUT=<dir> game/streets/tests/run.sh look_bench 4
## (LEVEL 4's look -- "med" -- and no town details of its own; NIGHT=1 for the night.)
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var tag := OS.get_environment("STREETS_TRY") if OS.get_environment("STREETS_TRY") != "" else "now"
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("OUT") + "/bench_%s_%s.png" % [tag, name])
	_white_check(img, name)
	_grey_check(img, name)

func _look(eye: Vector3, at: Vector3) -> void:
	g.look_from(eye, at)
	g._sky_follow()

func _run() -> void:
	OS.set_environment("STREETS_CITY_FILE", "res://game/streets/cities/look_bench.json")
	var t0 := Time.get_ticks_msec()
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	print("the bench loaded in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if OS.get_environment("NIGHT") == "1":
		g._set_night(true)
	# on foot at the junction, so people come round and the car is out of the way
	g._get_out()
	g._pos = Vector2(-4.0, 9.0)
	await create_timer(6.0).timeout   # (walkers and traffic come round)
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	_look(Vector3(-16.0, 2.0, 3.2), Vector3(40.0, 3.0, -3.0))   # (from the kerb's edge: on the pavement, people filled the frame)
	await _snap("street")
	if OS.get_environment("OVERVIEW") == "1":   # (from high over the south-west corner: the whole bench)
		_look(Vector3(-70.0, 45.0, 70.0), Vector3(0.0, 0.0, -10.0))
		await _snap("overview")
	# the block with balconies nearest the junction (any street), seen from its street side
	var kinds := {}
	for i in range(g._bld_box.size()):
		kinds[int(g._bld_kind[i])] = int(kinds.get(int(g._bld_kind[i]), 0)) + 1
	print("blocks by kind (0 plain, 1 on columns, 2 pitched roof, 3 balconies): ", kinds, "; balconies built ", g._dressing.get("balconies", 0), ", closed in ", g._dressing.get("closed_balconies", 0))
	var bi := -1
	var bd := INF
	for want: int in [3, 0]:
		for i in range(g._bld_box.size()):
			var c: Vector2 = (g._bld_box[i] as Rect2).get_center()
			if int(g._bld_kind[i]) == want and c.length() < bd:
				bd = c.length()
				bi = i
		if bi >= 0:
			break
	var box: Rect2 = g._bld_box[bi]
	var bc := box.get_center()
	# its street side: toward the main street (z 0) or the side street (x 0), whichever is nearer
	var out := Vector2(0.0, -signf(bc.y)) if absf(bc.y) < absf(bc.x) else Vector2(-signf(bc.x), 0.0)
	var face_at := bc + out * (box.size.y * 0.5 if out.x == 0.0 else box.size.x * 0.5)
	var along := Vector2(-out.y, out.x)
	print("facade: building %d at %s, kind %d, %.0f m tall" % [bi, bc, g._bld_kind[bi], g._bld_top[bi]])
	if OS.get_environment("TRACE") != "":   # (the street side the game puts its balconies on)
		var ring: PackedVector2Array = g._blds[bi]
		var area := 0.0
		for k in range(ring.size()):
			area += ring[k].x * ring[(k + 1) % ring.size()].y - ring[(k + 1) % ring.size()].x * ring[k].y
		print("  its ring %s, area sign %d, street edge %s (camera out %s)" % [ring, signi(int(area)), g._street_edge(ring, 1.0 if area > 0.0 else -1.0), out])
	# from the middle of the street it faces (further out stood in the garden opposite, behind
	# its railing), and from its own kerb, looking up under the balconies
	var mid := Vector2(face_at.x, 0.0) if out.x == 0.0 else Vector2(0.0, face_at.y)
	var e1 := mid - along * 4.0
	_look(Vector3(e1.x, 1.7, e1.y), Vector3(face_at.x, 6.5, face_at.y))
	await _snap("facade")
	var e2 := face_at + out * 7.0 + along * 3.0
	var t2 := face_at - along * 1.5
	_look(Vector3(e2.x, 1.6, e2.y), Vector3(t2.x, 5.0, t2.y))
	await _snap("balcony")
	_look(Vector3(-30.0, 1.6, 8.6), Vector3(10.0, 1.0, 8.0))
	await _snap("people")
	# a parked car close up: the nearest pair of parked car posts to the junction
	var best := Vector2.INF
	for i in range(g._posts.size() - 1):
		if is_equal_approx(g._post_r[i], 0.85) and is_equal_approx(g._post_r[i + 1], 0.85) and absf(g._posts[i].distance_to(g._posts[i + 1]) - 2.8) < 0.02:
			var m: Vector2 = (g._posts[i] + g._posts[i + 1]) * 0.5
			if m.length() < best.length():
				best = m
	if best != Vector2.INF:
		_look(Vector3(best.x + 3.5, 1.4, best.y + 3.0 * signf(best.y if best.y != 0.0 else 1.0)), Vector3(best.x, 0.7, best.y))
		await _snap("car")
	print("shots in ", OS.get_environment("OUT"), "; the whole run %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
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
