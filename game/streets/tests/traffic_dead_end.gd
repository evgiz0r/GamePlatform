extends SceneTree
## Cars at a dead end: arriving, turning round, leaving -- do they keep to their own side and
## clear of each other? The exam (22 Nov 2026, Givatayim) had five cars in a row drive through
## motorbikes standing nose to nose 15 m short of HaDganim's dead end (-145, 269), where it goes
## on as steps; every one of them, both ways, about 1.8 m north of the street's middle.
## Stages it: the rest of traffic off, the player standing beside the street (traffic is only
## kept near the player), a car sent in toward the dead end every EVERY seconds (default 4)
## for SECS (default 60), from FROM metres back (default 90). Prints per car its side of the
## middle going in and coming out (right of its heading is +), and every pair of bodies
## overlapping 0.25 m+ (the exam's measure). PASS: no overlaps, and every car right of the
## middle both ways.
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/traffic_dead_end.gd
## END_AT="x,z" for another dead end (the end point), ROAD_DIR="x,z" a point back along it.
const Bodies = preload("res://game/streets/tests/bodies.gd")
var g: Node

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _xz(s: String) -> Vector2:
	var a := s.split(",")
	return Vector2(float(a[0]), float(a[1]))

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(_env("LEVEL", "1"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	var tr = g._traffic
	var end_at := _xz(_env("END_AT", "-145,269.3"))
	var back_at := _xz(_env("ROAD_DIR", "-279.7,283.8"))
	var u := (end_at - back_at).normalized()    # into the dead end
	var from := float(_env("FROM", "90"))
	var secs := float(_env("SECS", "60"))
	var every := float(_env("EVERY", "4"))
	# the player: standing past the dead end
	g._auto = false
	g._v = 0.0
	var side := Vector2(-u.y, u.x)
	g._pos = end_at + u * float(_env("PLAYER_PAST", "35"))   # past the end (on the steps there): out of the way, traffic kept near
	for c in tr.cars:
		c.alive = false
	var verbose := OS.get_environment("VERBOSE") != ""
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var next_send := 0.0
	var sent := 0
	var seen := {}       # car index -> {"in": [sum, n], "out": [...]}
	var pairs := {}
	var overlaps := 0
	var worst := 0.0
	while t < secs + 20.0:
		g._v = 0.0
		if t >= next_send and t < secs:
			next_send += every
			var at := end_at - u * from
			var free := true
			for o in tr.cars:
				if o.alive and o.pos.distance_to(at) < 15.0:
					free = false
			if free and tr.send(at, u):
				sent += 1
		await physics_frame
		t += dt
		var boxes := {}
		for i in range(tr.cars.size()):
			var c = tr.cars[i]
			if not c.alive or c.pos.distance_to(end_at) > from + 10.0:
				continue
			boxes[i] = Bodies.car_box(c)
			# side of the street's middle, + right of its own heading
			var fw := Vector2(sin(c.yaw), cos(c.yaw))
			var off: float = (c.pos - back_at).dot(side)   # + right of `u` (the game's lanes: (-y, x) is right)
			var going_in := fw.dot(u) > 0.0
			var right := off if going_in else -off
			var along_end: float = (end_at - c.pos).dot(u)
			if along_end > -2.0 and along_end < 60.0 and absf(off) < 6.0 and c.v > 0.5:
				var e: Dictionary = seen.get(i, {"in": [0.0, 0, INF], "out": [0.0, 0, INF], "kind": c.kind})
				var key := "in" if going_in else "out"
				var a: Array = e[key]
				e[key] = [a[0] + right, a[1] + 1, minf(a[2], right)]
				seen[i] = e
		if verbose and int((t - dt) / 2.0) != int(t / 2.0):
			var row := []
			for i: int in boxes:
				var c = tr.cars[i]
				row.append("%d %s %.0fm %+.1f v%.1f %s b%d k%d/%d" % [i, c.kind, (end_at - c.pos).dot(u), (c.pos - back_at).dot(side), c.v, c.why, c.blocker, c.k, c.pts.size()])
			print("  t %.0f: %s" % [t, " | ".join(row)])
		var now := {}
		for i: int in boxes:
			for j: int in boxes:
				if j <= i:
					continue
				var d := Bodies.box_depth(boxes[i], boxes[j])
				if d > 0.25:
					var key := "%d:%d" % [i, j]
					now[key] = true
					worst = maxf(worst, d)
					if not pairs.has(key):
						overlaps += 1
						var a = tr.cars[i]
						var b = tr.cars[j]
						print("  overlap t %.1f: %s (%s, %.1f m/s, heading %.0f, k %d of %d) & %s (%s, %.1f m/s, heading %.0f, k %d of %d), %.2f m in, %.0f m from the end" % [
							t, a.kind, a.why, a.v, rad_to_deg(a.yaw), a.k, a.pts.size(), b.kind, b.why, b.v, rad_to_deg(b.yaw), b.k, b.pts.size(), d, a.pos.distance_to(end_at)])
		pairs = now
	var wrong := 0
	for i: int in seen:
		var e: Dictionary = seen[i]
		var line := "  car %d %s:" % [i, e["kind"]]
		for key: String in ["in", "out"]:
			var a: Array = e[key]
			if a[1] > 0:
				line += "  %s %.2f m right of the middle (least %.2f)" % [key, a[0] / a[1], a[2]]
				if a[0] / a[1] < 0.3:
					wrong += 1
		print(line)
	print("DEAD END: %d sent, %d cars seen, %d on the wrong side, %d overlaps (worst %.2f m)" % [sent, seen.size(), wrong, overlaps, worst])
	print("DEAD END RESULT: %s" % ("PASS" if overlaps == 0 and wrong == 0 and sent > 0 else "FAIL"))
	quit(0)
