extends SceneTree
## Pictures of one flat: the dollhouse from above, then eye-level views from the entrance,
## the salon and a bedroom; then the guided tour run for a while, printing which rooms it
## reached. Good: every room's name in "tour reached", no "stuck".
##   LEVEL=1 OUT=/tmp/shots tests/run.sh views
var g: Node

func _initialize() -> void:
	create_timer(400.0).timeout.connect(func(): print("TIMEOUT"); quit(1))
	_run()

func _snap(n: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + n + ".png")
	print("shot ", n)

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
	await _snap("doll")
	g._doll = false
	await _snap("entrance")
	for kind in ["salon", "parents", "mamad", "kitchen"]:
		for r in g.plan["rooms"]:
			if r["kind"] == kind:
				g._pos = g._w(r["label"][0], r["label"][1])
				# look the way with the most room
				var best := 0.0
				var by := 0.0
				for k in 16:
					var y := k * TAU / 16
					var d := Vector2(-sin(y), -cos(y))
					var free := 0.0
					while free < 8.0:
						var p: Vector2 = g._pos + d * free
						var hit := false
						for s in g._solid:
							if s.has_point(p):
								hit = true
						if hit:
							break
						free += 0.1
					if free > best:
						best = free
						by = y
				g._yaw = by
				# step back to the wall behind for a wider view
				var back := Vector2(sin(by), cos(by))
				for i in 30:
					var p2: Vector2 = g._pos + back * 0.1
					var hit2 := false
					for s in g._solid:
						if s.grow(0.3).has_point(p2):
							hit2 = true
					if hit2:
						break
					g._pos = p2
				await _snap(kind)
				break
	# from the balcony rail, out over the street
	for r in g.plan["rooms"]:
		if r["kind"] == "mirpeset":
			var rc: Array = r["rect"]
			g._pos = g._w((rc[0] + rc[2]) / 2.0, rc[3] - 0.55)
			g._yaw = PI
			g._pitch = -0.3
			await _snap("balcony")
			g._pitch = -0.08
	# the tour
	var s: Array = g.plan["start"]
	g._pos = g._w(s[0], s[1])
	g._yaw = PI
	g._start_tour()
	var seen := {}
	var last := Vector2.INF
	var still := 0.0
	var t := 0.0
	while not g._tour.is_empty() and t < 400.0:
		await physics_frame
		t += 1.0 / 60.0
		seen[g._room_now] = true
		if last.is_finite() and g._pos.distance_to(last) < 0.0005 and not g._tour.is_empty() and not (g._tour[0] is Dictionary):
			still += 1.0 / 60.0
			if still > 6.0:
				print("stuck at ", g._pos, " in ", g._room_now, " heading for ", g._tour[0])
				break
		else:
			still = 0.0
		last = g._pos
	var missed := []
	for r in g.plan["rooms"]:
		if not seen.has(r["name"]) and r["name"] not in missed:
			missed.append(r["name"])
	print("tour missed: ", missed, "   (good: [])")
	print("tour reached: ", seen.keys(), " in %.0f s, %d waypoints left" % [t, g._tour.size()])
	quit(0)
