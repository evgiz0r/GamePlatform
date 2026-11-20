extends SceneTree
## On foot: out of the car, walk and turn, the view from the eyes, a car stopping for you
## on the road, back in.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 1})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var car0: Vector2 = g._pos
	g._toggle_walk()
	print("walking ", g._walking, " stepped out ", snappedf(g._pos.distance_to(car0), 0.1), " m from the car")
	Input.action_press("move_up")
	await create_timer(4.0).timeout
	print("walked ", snappedf(g._pos.distance_to(car0), 0.1), " m, speed ", snappedf(g._v, 0.01), " anim ", g._me_anim)
	await _snap("w_walk")
	Input.action_press("move_right")
	await create_timer(0.6).timeout
	Input.action_release("move_right")
	Input.action_press("action_a")
	await create_timer(2.0).timeout
	print("running ", snappedf(g._v, 0.01), " anim ", g._me_anim)
	Input.action_release("action_a")
	Input.action_release("move_up")
	await create_timer(0.6).timeout
	g._set_cockpit(true)
	await create_timer(0.3).timeout
	await _snap("w_eyes")
	g._set_cockpit(false)
	# stand in the lane ahead of a car coming, and see whether it stops
	var T = g._traffic
	var stopped_for_me := -1.0
	for c in T.cars:
		if c.alive and c.v > 4.0 and c.kind != "bus":
			var ahead: Vector2 = T._at(c, c.s + 28.0)
			g._pos = ahead
			g._prev_pos = ahead
			var t := 0.0
			var mind := INF
			var minv := INF
			var gap0: float = T._path_gap(c, ahead, 120.0, 2.0)
			while t < 7.0:
				await physics_frame
				t += Engine.time_scale / Engine.physics_ticks_per_second
				var d: float = c.pos.distance_to(g._pos)
				if d < mind:
					mind = d
					minv = c.v
			print("gap on its lane at first %.1f; closest %.1f m at %.1f m/s; me moved %.1f m" % [gap0, mind, minv, ahead.distance_to(g._pos)])
			stopped_for_me = c.v
			print("a %s coming at me: now %.1f m/s, %.1f m away" % [c.kind, c.v, c.pos.distance_to(g._pos)])
			break
	g._pos = g._car_at + Vector2(1.5, 0)
	g._toggle_walk()
	print("back in: walking ", g._walking, " at the car ", g._pos == g._car_at)
	quit(0)
