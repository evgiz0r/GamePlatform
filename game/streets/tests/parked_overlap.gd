extends SceneTree
## Parked cars inside things: every car parked at the kerb (_parked_at, _parked_face) against
## the posts that are not parked cars (trees, lamps, signs, bins, bollards -- anything round
## you can hit) and the walls, over its whole length: the car as its five 0.85 m circles
## (_add_car_posts), a thing counted when it reaches more than 0.25 m into one. Grouped by
## kind of thing (who put it up, with POSTS_FROM=1), worst places first. A user (22 Nov,
## Ashdod, the chase camera): "some parking cars spawn inside trees or other objects".
##   LEVEL=3 STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/parked_overlap.gd
## Good: none.
var g: Node
func _initialize() -> void:
	_run()
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	var priv = load("res://game/streets/tests/private_spots.gd")
	var avoid: Array = priv.spots(g)
	var cars: int = (g._parked_at as PackedVector2Array).size()
	var by := {}
	var where: Array = []
	var bad := 0
	for ci in range(cars):
		var p: Vector2 = g._parked_at[ci]
		var f: Vector2 = g._parked_face[ci]
		var worst := 0.0
		var what := ""
		for k: float in [-1.4, -0.7, 0.0, 0.7, 1.4]:
			var q := p + f * k
			for i: int in g._near(g._post_hash, q, 2.0, g.BLD_CELL):
				var r: float = g._post_r[i]
				if absf(r - 0.85) < 0.001:
					continue   # (a parked car's own circles, or the next car's)
				var into: float = 0.85 + r - (g._posts[i] as Vector2).distance_to(q)
				if into > worst:
					worst = into
					what = "post r %.2f %s" % [r, String(g._post_from[i]).split(" ")[0] if i < (g._post_from as Array).size() else ""]
			var push: Vector2 = g._push_out(q, 0.85, false)
			if push.length() > worst:
				worst = push.length()
				what = "wall or building"
		if worst > 0.25:
			bad += 1
			var key := what.split(" ")[0] + " " + (what.split(" ")[3] if what.split(" ").size() > 3 else "")
			by[key] = int(by.get(key, 0)) + 1
			if not priv.near(avoid, p):
				where.append([worst, p.round(), what])
	print("PARKED INSIDE THINGS: %d of %d parked cars, by what: %s" % [bad, cars, by])
	where.sort_custom(func(a, b): return a[0] > b[0])
	for w: Array in where.slice(0, 12):
		print("  %.2f m into %s at %s" % [w[0], w[2], w[1]])
	quit()
