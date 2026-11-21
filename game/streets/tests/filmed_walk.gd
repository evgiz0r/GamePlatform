extends SceneTree
## The filmed walk (the place with a "walk" in LEVELS: level 5): it loads, walks on its own
## and stops where its film did. At each of AT (seconds into the walk, default the
## landmarks below) it jumps there, lets the eye settle and saves a shot, printing where it
## is and the nearest wall -- the shots are what to put beside the film's frames at the
## same seconds. RECORD=1 instead plays the whole walk from the start and saves every frame,
## named by the walk's own clock (run with --fixed-fps 10 for a frame per 0.1 s): the game's
## half of a side-by-side video (DEV.md, "The filmed walk"). SCAN=1 walks the whole route a
## quarter second at a time and prints every stretch of it inside a building or a post;
## POSTS_NEAR="x,z,r;x,z,r" lists the posts round each spot (to route the walk between them), the
## nearest road's edge, and everything drawn by instance there (what the scan cannot see);
## TRAFFIC_LOG=from,to the cars round the walk every quarter second (AT jumps the walk's clock,
## so a scripted car's timing shows only here or in a recording).
## CAMERA_LOG=1 prints the camera every 0.1 s of the walk at its own pace (tests/film_motion.py
## charts it against the film).
var g: Node
const LANDMARKS := "8,28,40,55,70,84,94"   # the zebra, the forecourt, the passage, its end, the little street, Sheinkin, Ha-Meri

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 5})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var out := OS.get_environment("OUT")
	if g._film.is_empty():
		print("FAIL no walk: is this the walk's level?")
		quit(1)
		return
	var last: float = g._film[g._film.size() - 1].z
	print("walk of %.0f s, %d points, from %s to %s, on foot %s, hud shown %s" % [last, g._film.size(),
		Vector2i(g._film_at(0.0)), Vector2i(g._film_at(last)), g._walking, g._hud.visible])
	if OS.get_environment("POSTS_NEAR") != "":
		# POSTS_NEAR="x,z,r;x,z,r": every post (anything round and solid) within r of x,z, to
		# route a walk between them; and where the kerb is
		for spot: String in OS.get_environment("POSTS_NEAR").split(";", false):
			var q := spot.split_floats(",")
			var c := Vector2(q[0], q[1])
			print("-- near %s (kept clear by the details file: %s, of %d spots)" % [c, g._kept_clear(c), g._keep_clear.size()])
			for i in range(g._posts.size()):
				if g._posts[i].distance_to(c) <= q[2]:
					print("post %d at %s r %.2f" % [i, Vector2(snappedf(g._posts[i].x, 0.1), snappedf(g._posts[i].y, 0.1)), g._post_r[i]])
			# the nearest road's centre line and how far its edge is (a walk keeps to the
			# pavement: edge 0.3 to KERB_W + PAVE_W)
			var hit: Dictionary = g._nearest_seg(c, 8.0, true, true)
			if not hit.is_empty():
				var q2: Vector2 = hit["q"]
				print("road %d: its centre line nearest at %s, %.2f m from the edge (negative: in the road), road side %s"
					% [hit["road"], Vector2(snappedf(q2.x, 0.1), snappedf(q2.y, 0.1)), hit["edge"], (q2 - c).normalized()])
			# and everything drawn by the instance there, solid or not (a bike in its rack, a
			# chair, a tree's crown hanging low): which group, where, its size and how low it
			# comes -- a post marks only part of some of these, and the scan sees only posts
			for n: Node in root.find_children("*", "MultiMeshInstance3D", true, false):
				var mmi := n as MultiMeshInstance3D
				if mmi.multimesh == null or mmi.multimesh.mesh == null or not mmi.is_visible_in_tree():
					continue
				var mm := mmi.multimesh
				var ab := mm.mesh.get_aabb()
				var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
				for i in range(count):
					var xf := mmi.global_transform * mm.get_instance_transform(i)
					var p := xf.origin
					if Vector2(p.x, p.z).distance_to(c) > q[2]:
						continue
					var box := xf * ab
					print("drawn %s/%s at %s, %.1f x %.1f m, %.1f to %.1f m up, %.2f m off" % [mmi.get_parent().name, mmi.name,
						Vector2(snappedf(p.x, 0.1), snappedf(p.z, 0.1)), box.size.x, box.size.z,
						box.position.y - g._h(Vector2(p.x, p.z)), box.end.y - g._h(Vector2(p.x, p.z)), Vector2(p.x, p.z).distance_to(c)])
		quit()
		return
	if OS.get_environment("SCAN") == "1":
		# the whole route, every quarter second: each stretch inside a building or a post
		# (anything solid: a bollard, a parked bike) -- a replayed walk goes through walls
		# without a sound, and from inside a building its walls are not drawn
		var was := ""
		var from := 0.0
		var where := Vector2.ZERO
		var t := 0.0
		while t <= last + 0.25:
			var p: Vector2 = g._film_at(t)
			var what := ""
			if g._push_out(p, 0.25, false, false) != Vector2.ZERO:
				what = String(g._last_hit)
			elif g._push_out(p, 0.25, true, false) != Vector2.ZERO:
				what = String(g._last_hit)
			if what.begins_with("post "):   # where it stands, to know which way to walk round it
				var q: Vector2 = g._posts[int(what.get_slice(" ", 1))]
				what += " at %s" % Vector2(snappedf(q.x, 0.1), snappedf(q.y, 0.1))
			if what != was:
				if was != "":
					print("INSIDE %s from %.2f to %.2f s, walking at %s" % [was, from, t, where])
				was = what
				from = t
				where = Vector2(snappedf(p.x, 0.1), snappedf(p.y, 0.1))
			t += 0.25
		if was != "":
			print("INSIDE %s from %.2f to the end" % [was, from])
		print("scan done")
		quit()
		return
	if OS.get_environment("TRAFFIC_LOG") != "":
		# TRAFFIC_LOG=from,to: the walk at its own pace from the start (scripted cars are sent
		# by its clock, which AT jumps), and every quarter second from `from` to `to` each car
		# within 40 m: where it is from the walker, its speed and what holds it down (traffic.gd's
		# `why`), lane, kind, whether it drives on
		# past the walk's zebras ("through")
		var span := OS.get_environment("TRAFFIC_LOG").split_floats(",")
		var next := span[0]
		while g._film_t <= span[1]:
			await physics_frame
			if g._film_t < next:
				continue
			next += 0.25
			var line := "%6.2f s:" % g._film_t
			for c in g._traffic.cars:
				if not c.alive or c.pos.distance_to(g._pos) > 40.0:
					continue
				var rel: Vector2 = c.pos - g._pos
				line += "  [%s %s %.1f m/s (%s) lane %d%s at %.0f m]" % [c.kind, Vector2i(rel), c.v, c.why, c.lane_i,
					" through" if c.film_through else "", rel.length()]
			print(line)
		quit()
		return
	if OS.get_environment("CAMERA_LOG") == "1":
		# the replay's camera at the walk's own pace, every 0.1 s of it: which way the camera
		# faces (degrees round the map's x/z, + turning right), how far up it looks, where the
		# walker stands, the body's facing and the head's turn -- the game's half of
		# tests/film_motion.py's chart (run with --fixed-fps 10 and a small RES: minutes)
		var next := 0.0
		while g._film_t <= last + 0.2:
			await physics_frame
			if g._film_t < next:
				continue
			next += 0.1
			var fwd: Vector3 = -g.cam.global_transform.basis.z
			print("CAM %.2f %.2f %.2f %.3f %.3f %.1f %.1f" % [g._film_t, rad_to_deg(atan2(fwd.z, fwd.x)),
				rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0))), g._pos.x, g._pos.y, rad_to_deg(g._yaw), rad_to_deg(g._film_look)])
		quit()
		return
	if OS.get_environment("RECORD") == "1":
		while g._film_t <= last + 0.5:
			await RenderingServer.frame_post_draw
			var t: float = g._film_t
			root.get_viewport().get_texture().get_image().save_jpg(out + "/f%05d.jpg" % int(round(t * 10.0)), 0.88)
		print("recorded to ", out)
		quit()
		return
	var at := OS.get_environment("AT") if OS.get_environment("AT") != "" else LANDMARKS
	for s: String in at.split(","):
		var t := float(s)
		g._film_t = t - 1.5   # a moment before, for the head to turn the way it walks
		for i in range(20):
			await physics_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out + "/t%03d.png" % int(t))
		# what is nearest: anything solid within a step means the walk goes through it
		var hit: Vector2 = g._push_out(g._pos, 0.3, true, false)
		print("t=%3d s at %s  facing %3d deg  %s" % [int(t), Vector2i(g._pos), int(rad_to_deg(g._yaw)),
			"clear" if hit == Vector2.ZERO else "INSIDE %s (%.2f m)" % [g._last_hit, hit.length()]])
	g._film_t = last + 1.0
	for i in range(30):
		await physics_frame
	print("at the end: done %s, standing at %s, speed %.2f" % [g._film_done, Vector2i(g._pos), g._v])
	quit()
