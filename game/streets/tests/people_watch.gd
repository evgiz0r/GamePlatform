extends SceneTree
## People on a pavement as someone standing among them sees them: you on foot at AT (x,z,
## default Sirkin by its shops, walk 2's 40 s) facing FACE (dx,dz, default along it), the game
## running as played for WAIT s to let people come, then SECS s watched. Every tick, each
## walker within 35 m: how often one turns back (its way along its line reversed), how much
## of the time it is stepped off its line (weaving round things and people), how often two
## people stand closer than 0.45 m, and how often anyone is inside something solid (a post,
## a wall, a building, a parked car) -- 12 cm in or more. Saves a frame every 0.5 s
## (watch_NNN.png in $OUT) when OUT is set, from 6 m up behind you, looking along FACE (the game's own
## camera overridden each frame; people are placed by it, so out of its sight).
##   FULL=1 STREETS_BUILD_ALL=0 RES=960x540 OUT=<dir> game/streets/tests/run.sh people_watch 1
## (headless without OUT: the numbers only.)
var g: Node

func _initialize() -> void:
	_run()

func _env_v2(name: String, d: Vector2) -> Vector2:
	var s := OS.get_environment(name)
	if s == "":
		return d
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var at := _env_v2("AT", Vector2(486.27, -698.66))
	var face := _env_v2("FACE", Vector2(0.05, -1.0)).normalized()
	g._get_out()
	g._pos = at
	g._yaw = face.angle()
	# (from 6 m up and 6 m back, looking along the pavement: from the eyes, a tree by the
	# walk's line filled the frame)
	var eye := Vector3(at.x - face.x * 6.0, float(g._h(at)) + 6.0, at.y - face.y * 6.0)
	var look := Vector3(at.x + face.x * 14.0, float(g._h(at)), at.y + face.y * 14.0)
	process_frame.connect(func() -> void: g.look_from(eye, look))   # (after the game's own camera)
	var wait := float(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 25.0
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 40.0
	var out := OS.get_environment("OUT")
	var t := 0.0
	while t < wait:   # (people placed round the new spot, out of sight, walking in)
		g._pos = at
		await physics_frame
		t += 1.0 / 60.0
	var seen := {}           # walker id -> true (came within 35 m)
	var turned := 0          # turn-backs within 35 m
	var last_dir := {}
	var off_line := 0.0      # walker-seconds stepped more than 0.3 m off the line
	var near_t := 0.0        # walker-seconds within 35 m
	var close_t := 0.0       # pair-seconds closer than 0.45 m
	var inside_t := 0.0      # person-seconds 12 cm or more into something solid
	var inside_what := {}
	var shot := 0
	var next_shot := 0.0
	t = 0.0
	var dt := 1.0 / 60.0
	while t < secs:
		g._pos = at
		g._yaw = face.angle()
		await physics_frame
		t += dt
		var ps: Array = []
		for w: Dictionary in g._walkers:
			var a: Node3D = w["actor"]
			if not a.visible:
				continue
			var p := Vector2(a.position.x, a.position.z)
			if p.distance_to(at) > 35.0:
				continue
			var id := a.get_instance_id()
			seen[id] = true
			near_t += dt
			if last_dir.has(id) and float(last_dir[id]) != float(w["dir"]) and w.get("line") == last_dir.get(str(id) + "l"):
				turned += 1
			last_dir[id] = float(w["dir"])
			last_dir[str(id) + "l"] = w.get("line")
			if absf(float(w.get("lat", 0.0))) > 0.3:
				off_line += dt
			ps.append(p)
		for list: Array in [g._chatters, g._sitters, g._waiters, g._keepers]:
			for c: Dictionary in list:
				var ca: Node3D = c["actor"]
				if ca.visible and Vector2(ca.position.x, ca.position.z).distance_to(at) < 35.0:
					ps.append(Vector2(ca.position.x, ca.position.z))
		for i in range(ps.size()):
			for j in range(i + 1, ps.size()):
				if (ps[i] as Vector2).distance_to(ps[j]) < 0.45:
					close_t += dt
		for w: Dictionary in g._walkers:
			var a: Node3D = w["actor"]
			var p := Vector2(a.position.x, a.position.z)
			if not a.visible or p.distance_to(at) > 35.0:
				continue
			var push: Vector2 = g._push_out(p, 0.12, true, false)
			var cpush: Vector2 = g._car_box_push(p, 0.12)
			if push.length() > 0.0 or cpush.length() > 0.0:
				if OS.get_environment("TRACE") != "" and fmod(t, 1.0) < dt:
					var why := ""
					for pi: int in g._near(g._post_hash, p, 3.0, g.BLD_CELL):
						var dd: float = (g._posts[pi] as Vector2).distance_to(p)
						if dd < float(g._post_r[pi]) + 0.12:
							why += " post %d r%.2f at %.2f" % [pi, g._post_r[pi], dd]
					var pv: Vector2 = g._push_out(p, 0.12, true, false)
					print("  %.1f s  inside: walker %d%s lat %.2f lane %.2f hold %s at %s, %.2f m from you; push %.2f by %s%s" % [t, g._walkers.find(w), " (with %d)" % int(w["with"]) if w.has("with") else "", float(w.get("lat", 0.0)), float(w.get("lane", 0.0)), w.get("hold_me", false), p, p.distance_to(at), pv.length(), g._last_hit, why])
				inside_t += dt
				var k := "a parked car" if cpush.length() > 0.0 else ("a post" if g._push_out(p, 0.12, false, false) == Vector2.ZERO else "a wall or building")
				inside_what[k] = float(inside_what.get(k, 0.0)) + dt
		if out != "" and t >= next_shot:
			next_shot += 0.5
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png(out + "/watch_%03d.png" % shot)
			shot += 1
	print("watched %.0f s at (%.1f, %.1f): %d walkers came within 35 m, %.0f walker-seconds near" % [secs, at.x, at.y, seen.size(), near_t])
	print("  turned back in view: %d" % turned)
	print("  stepped off their line (> 0.3 m): %.0f%% of the time" % (100.0 * off_line / maxf(near_t, 0.001)))
	print("  two people closer than 0.45 m: %.1f pair-seconds" % close_t)
	print("  inside something solid (12 cm+): %.1f person-seconds %s" % [inside_t, inside_what])
	quit()
