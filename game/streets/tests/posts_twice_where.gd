extends SceneTree
## Where a solid thing is put up twice on one spot (city_check's "posts twice": same radius,
## under 0.3 m apart): counted by who put each of the pair up (the three callers above
## _add_post), the worst kinds first, with a place for each. Needs POSTS_FROM=1, which has
## _add_post keep its caller (get_stack: a debug build, as the editor's binary is).
##   POSTS_FROM=1 LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/posts_twice_where.gd
var g: Node
func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	await create_timer(1.0).timeout
	var from: Array = g._post_from
	var kinds := {}   # "who A | who B" -> [n, first place, radius]
	var n := 0
	for i in range(g._posts.size()):
		var r: float = g._post_r[i]
		if is_equal_approx(r, 0.85):
			continue   # a parked car's
		var p: Vector2 = g._posts[i]
		for j: int in g._near(g._post_hash, p, 0.3, g.BLD_CELL):
			if j <= i or not is_equal_approx(float(g._post_r[j]), r):
				continue
			if (g._posts[j] as Vector2).distance_to(p) < 0.3:
				n += 1
				var a: String = from[i] if i < from.size() else "?"
				var b: String = from[j] if j < from.size() else "?"
				var k := "%.2f m  %s|  %s" % [r * 2.0, a, b]
				if not kinds.has(k):
					kinds[k] = [0, p.round(), (g._posts[j] as Vector2).distance_to(p)]
				kinds[k][0] += 1
				break
	print("posts twice: %d" % n)
	var keys := kinds.keys()
	keys.sort_custom(func(x, y): return kinds[x][0] > kinds[y][0])
	for k in keys:
		print("  %4d  %s  at %s, %.2f m apart" % [kinds[k][0], k, kinds[k][1], kinds[k][2]])
	quit(0)
