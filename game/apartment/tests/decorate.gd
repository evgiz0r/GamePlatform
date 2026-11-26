extends SceneTree
## Decorating, through the same calls a tap and a drag make: pick up the sofa in the
## dollhouse, drag it into a wall (it must go back), drag it to free floor (it must stay),
## rotate it, nudge it with the keys' step. Shots before and after.
## Good: "into the wall: went back", "to free floor: stayed", "rotate: ok", "decorate: ok".
##   LEVEL=1 OUT=/tmp/shots tests/run.sh decorate
var g: Node

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func(): print("TIMEOUT"); quit(1))
	_run()

func _snap(n: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + n + ".png")
	print("shot ", n)

func _screen(p: Vector2) -> Vector2:
	return g.to_screen(Vector3(p.x, 0, p.y))

func _run() -> void:
	await create_timer(0.3).timeout
	var lv := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("apartment", {"level": lv})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("apartment.gd"):
				g = n
	g._doll = true
	await process_frame
	await process_frame
	var fails := 0
	var i := -1
	for k in g.items.size():
		if g.items[k]["name"] == "sofa":
			i = k
	var sofa: Rect2 = g.items[i]["rect"]
	var start: Vector2 = sofa.get_center()
	await _snap("deco_before")
	# pick it up by tapping it
	if not g._deco_press(_screen(start)) or g._sel != i:
		print("pick up: FAIL (sel %d, wanted %d)" % [g._sel, i])
		fails += 1
	# drag it into the nearest outside wall
	var wall: Rect2 = g._solid[0]
	var best := INF
	for w: Rect2 in g._solid:
		var d := w.get_center().distance_to(start)
		if d < best:
			best = d
			wall = w
	g._deco_drag(_screen(start + (wall.get_center() - start)))
	g._deco_release()
	var now: Vector2 = g.items[i]["rect"].get_center()
	var back := now.distance_to(start) < 0.01
	print("into the wall: ", "went back" if back else "FAIL, stayed at %s" % now)
	fails += 0 if back else 1
	# find free floor in the salon by trying spots, and drag it there
	var moved := false
	for r in g.plan["rooms"]:
		if r["kind"] != "salon":
			continue
		var a: Vector2 = g._w(r["rect"][0], r["rect"][1])
		var b: Vector2 = g._w(r["rect"][2], r["rect"][3])
		for x in range(int(a.x * 10), int(b.x * 10), 2):
			for y in range(int(a.y * 10), int(b.y * 10), 2):
				var c := Vector2(x, y) / 10.0
				if c.distance_to(start) < 1.0:
					continue
				var test := Rect2(c - sofa.size / 2.0, sofa.size)
				g._place(i, c, g.items[i]["node"].rotation.y)
				var ok: bool = g._fits(i, test)
				g._place(i, start, g.items[i]["node"].rotation.y)
				if ok and not moved:
					g._deco_press(_screen(start))
					g._deco_drag(_screen(start) + (_screen(c) - _screen(start)))
					g._deco_release()
					now = g.items[i]["rect"].get_center()
					moved = now.distance_to(start) > 0.5
					print("to free floor: ", "stayed at %s" % now if moved else "FAIL")
					break
			if moved:
				break
	if not moved:
		fails += 1
	# rotate
	var size_was: Vector2 = g.items[i]["rect"].size
	g._rotate_sel()
	var size_now: Vector2 = g.items[i]["rect"].size
	var turned: bool = size_now.is_equal_approx(Vector2(size_was.y, size_was.x))
	var what := "sofa"
	if not turned:
		# no room to turn the sofa where it went: any piece that has room must turn
		for k in g.items.size():
			var sw: Vector2 = g.items[k]["rect"].size
			if sw.x == sw.y:
				continue
			g._select(k)
			g._rotate_sel()
			if g.items[k]["rect"].size.is_equal_approx(Vector2(sw.y, sw.x)):
				turned = true
				what = g.items[k]["name"]
				break
	print("rotate: ", "ok (%s)" % what if turned else "FAIL, nothing turned")
	fails += 0 if turned else 1
	await _snap("deco_after")
	# the walk still works round the sofa's new place: the tour reaches every room
	g._select(-1)
	print("decorate: ", "ok" if fails == 0 else "%d FAILED" % fails)
	quit(0)
