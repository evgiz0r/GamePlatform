extends SceneTree
## Do the people in the street keep clear of things and of each other? Autodrive for $SECS
## seconds (default 40) and, ten times a second, count the walkers more than 10 cm into a
## post (a tree, a lamp, a sign, a bin, a bench...) or a wall, and the walkers closer than
## shoulder to shoulder to anyone. Run headless (fast):
##   $GODOT --headless --path . -s res://game/streets/tests/people_clear.gd
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_auto(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 40.0
	var samples := 0
	var in_posts := 0
	var close_pairs := 0
	var walking := 0
	var hits := {}
	var deep := 0.0
	var t := 0.0
	while t < secs:
		await create_timer(0.1).timeout
		t += 0.1
		var at: Array = []
		for w: Dictionary in g._walkers:
			var a: Node3D = w["actor"]
			if not a.visible or (w["line"] as PackedVector2Array).size() < 2:
				continue
			var p := Vector2(a.position.x, a.position.z)
			at.append(p)
			walking += 1
			var pu: Vector2 = g._push_out(p, 0.2, true, false)
			if pu.length() > 0.1:   # (in it, not brushing it: a garden wall's face at 8 cm is a brush)
				in_posts += 1
				var kind := String(g._last_hit).split(" ")[0]
				hits[kind] = int(hits.get(kind, 0)) + 1
				deep = maxf(deep, pu.length())
		var walkers := at.size()
		for c: Dictionary in g._chatters:
			var a: Node3D = c["actor"]
			if a.visible:
				at.append(Vector2(a.position.x, a.position.z))
		for i in range(walkers):   # (a walker and anyone: people chatting stand close on purpose)
			for j in range(i + 1, at.size()):
				if (at[i] as Vector2).distance_to(at[j]) < 0.45:
					close_pairs += 1
		samples += 1
	print("%d samples, %d walker-samples: in a post or wall %d (%.1f%%), people closer than 0.45 m %d" % [samples,
		walking, in_posts, 100.0 * in_posts / maxf(walking, 1), close_pairs])
	print("  in what: %s, at most %.2f m in" % [hits, deep])
	quit(0)
