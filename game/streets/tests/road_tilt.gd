extends SceneTree
## How much the roads lean sideways: along every drivable road, every few metres, the ground
## (or the deck) under its left and right edges, as a slope across it. A road is built level
## across (or a little cambered, 2-3%); over 8% a parked car sits askew and a driven one slides.
## Prints the share of road over 4% / 8% / 15% and the worst stretches, with a shot of the
## worst from the driver's height (OUT). Default the test town (the hills are there).
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "4")})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var total := 0.0
	var over := [0.0, 0.0, 0.0]
	var worst: Array = []   # [slope, where, road name, dir]
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.5:
				continue
			var d := (b - a) / L
			var side := Vector2(-d.y, d.x)
			var s := 0.0
			while s < L:
				var c := a + d * s
				var y0: float = g._h(c)
				var yl: float = g._decks.surf(c + side * hw, y0 + 1.0) if r.has("ys") else g._h(c + side * hw)
				var yr: float = g._decks.surf(c - side * hw, y0 + 1.0) if r.has("ys") else g._h(c - side * hw)
				var slope := absf(yl - yr) / (2.0 * hw)
				total += 3.0
				for k in range(3):
					if slope > [0.04, 0.08, 0.15][k]:
						over[k] += 3.0
				if slope > 0.08:
					worst.append([slope, c, String(r["name"]), d])
				s += 3.0
	worst.sort_custom(func(x, y): return x[0] > y[0])
	print("roads %.1f km: leaning over 4%%: %.0f m, over 8%%: %.0f m, over 15%%: %.0f m" % [total / 1000.0, over[0], over[1], over[2]])
	var seen: Array = []
	for w: Array in worst:
		if seen.any(func(q): return (q as Vector2).distance_to(w[1]) < 40.0):
			continue
		seen.append(w[1])
		print("  %.0f%% at %s on '%s'" % [float(w[0]) * 100.0, (w[1] as Vector2).round(), w[2]])
		if seen.size() >= 12:
			break
	if OS.get_environment("OUT") != "" and not seen.is_empty():
		var w: Array = worst[0]
		var c: Vector2 = w[1]
		var d: Vector2 = w[3]
		g._land_on_road(c - d * 25.0, 15.0, d)
		await create_timer(2.0).timeout
		await _snap("worst_from_car")
	quit(0)
