extends SceneTree
## Shop looks: every place the city's details file gives a look ("shops": an awning, an
## umbrella, a bar's stools, crates of produce, a sign board), seen from the middle of the
## street facing it, at chest height. Prints where each one's front went (its wall, or a free-
## standing sign) and whether its tables or stools and crates are there; saves
## shop_<i>.png. The shops added or moved by hand are matched by their spot, the others by
## name.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.35,0,-3")
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._car.visible = false
	if g._details == null:
		print("FAIL no details file for this city")
		quit(1)
		return
	# (the city file itself is let go of once the city is built: the places are in g._pois,
	# [spot, role, its name's sign])
	var i := 0
	for sh: Dictionary in g._details.data.get("shops", []):
		var found := []
		for pe: Array in g._pois:
			var pat: Vector2 = pe[0]
			var sign: Label3D = pe[2]
			var name := String(sh.get("name", ""))
			if (name != "" and sign.text == name) or (sh.has("at") and pat.distance_to(g._details._v2(sh["at"])) < 2.0) \
					or (sh.has("near") and not sh.has("at") and pat.distance_to(g._details._v2(sh["near"])) < 10.0):
				found = pe
				break
		if found.is_empty():
			print("MISSING %s" % sh)
			continue
		var at: Vector2 = found[0]
		var spot: Array = g._facade_spot(at)
		var front: Vector2 = spot[0]
		var n: Vector2 = spot[1]
		var tables := 0
		for t: Vector2 in g._table_spots:
			if t.distance_to(front) < 6.0:
				tables += 1
		print("%s: front at %s facing %s, on a wall %s, tables %d, look %s" % [(found[2] as Label3D).text, front.snappedf(0.1),
			n.snappedf(0.01), spot[2], tables, sh])
		# stand across the street: out from the front past the road's far kerb
		var road: Dictionary = g._nearest_seg(front + n * 3.0, 30.0, true, true)
		var across := front + n * 14.0
		if not road.is_empty():
			var r: Dictionary = g._roads[road["road"]]
			var q: Vector2 = road["q"]
			across = q + (q - front).normalized() * 1.0   # (in the road: from the far pavement the parked cars hid it)
		var yaw := (front - across).angle()
		for f in 12:
			g._pos = across
			g._prev_pos = across
			g._yaw = yaw
			g._v = 0.0
			await process_frame
		await _snap("shop_%d" % i)
		i += 1
	print("%d shops with a look" % i)
	quit(0)
