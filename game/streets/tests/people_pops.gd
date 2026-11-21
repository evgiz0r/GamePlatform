extends SceneTree
## Object permanence: over SECS (default 90) of autodrive, what in view does what nothing real
## does. A user: "i dont want any popping of any objects, it looks fake, even more than
## collision stuff. need some more object permanence". Counted only for what the driver can
## see (drawn, in front or near, not behind a building from the eye: the game's _spawn_ok):
##   people popping   -- someone showing up, or jumping more than 2 m in one frame
##   people sliding   -- someone moving sideways faster than 1 m/s (0.2 s smoothed): a person
##                       steps aside, they do not glide. Split by whether your car was within
##                       8 m: everyone on the pavement used to slide a metre aside as
##                       autodrive drove past on the road ("they jump to the side")
##   people on a street -- someone on a street's asphalt with no zebra within 5 m ("people
##                       crossing the road in random locations, bothers the traffic"):
##                       times it began
##   cars popping     -- a traffic car showing up within 60 m in front, or moving further in a
##                       frame than its speed (1.5x + 0.3 m)
## And crossings at lights started while the road had green or amber. All good at 0 but the
## sliding with your car far (people stepping round each other and the posts: a baseline).
## Ends in a REGRESS line (validate.sh REGRESS=1).
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/people_pops.gd
var g: Node
func _initialize() -> void:
	_run()

## on a street's asphalt (a kerbed road's lanes or a junction's disc), not a driveway's: worked
## out here, not by the game's own _on_street, so the test also runs on the code before it
func _on_street(p: Vector2) -> bool:
	var hit: Dictionary = g._nearest_seg(p, 14.0, true)
	if not hit.is_empty() and float(hit["edge"]) < 0.0 and g._kerbed(g._roads[int(hit["road"])]):
		return true
	return g._in_junction(p, 0.0)
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	g._set_auto(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var was := {}
	var pops := {}
	var slide_near := 0
	var slide_far := 0
	var sliding := {}
	var on_street := 0
	var was_on := {}
	var car_pops := 0
	var car_was := {}
	var against_light := 0
	var crossed := 0
	var states := {}
	var firsts: Array = []
	for f in range(int(secs / dt)):
		await physics_frame
		var actors: Array = []
		for w: Dictionary in g._walkers:
			actors.append(["walker", w["actor"], w])
		for c: Dictionary in g._chatters:
			actors.append(["at a table", c["actor"], null])
		for c: Dictionary in g._crossers:
			actors.append(["crossing", c["actor"], null])
		for e: Array in actors:
			var a: Node3D = e[1]
			var key := a.get_instance_id()
			var p := Vector2(a.position.x, a.position.z)
			var seen: bool = a.visible and not g._spawn_ok(p)   # (out of range, behind you, or behind a building from the eye: not seen)
			if seen and was.has(key):
				var prev: Array = was[key]
				if not prev[0] or (prev[1] as Vector2).distance_to(p) > 2.0:
					pops[e[0]] = int(pops.get(e[0], 0)) + 1
					if firsts.size() < 8:
						firsts.append("%s popped at %s, %.0f m from your car (%s)" % [e[0], p.round(), p.distance_to(g._pos),
							"was hidden" if not prev[0] else "jumped %.1f m from %s" % [(prev[1] as Vector2).distance_to(p), (prev[1] as Vector2).round()]])
				elif e[2] != null and (e[2] as Dictionary).has("yaw"):
					# sideways, against the way they face, smoothed over ~0.2 s
					var yaw: float = (e[2] as Dictionary)["yaw"]
					var side := Vector2(-sin(yaw), cos(yaw))
					var lat := (p - (prev[1] as Vector2)).dot(side) / dt
					var sm: float = lerpf(float(prev[2]), lat, 1.0 - exp(-dt / 0.2))
					var near: bool = p.distance_to(g._pos) < 8.0
					if absf(sm) > 1.0 and not sliding.get(key, false):
						sliding[key] = true
						if near:
							slide_near += 1
							if firsts.size() < 8:
								firsts.append("walker slid sideways %.1f m/s at %s, your car %.1f m off at %.1f m/s" % [absf(sm), p.round(), p.distance_to(g._pos), g._v])
						else:
							slide_far += 1
					elif absf(sm) < 0.5:
						sliding[key] = false
					was[key] = [a.visible, p, sm]
					continue
			if seen and e[0] == "walker":
				var on: bool = _on_street(p)
				if on:
					for ni: int in g._crossing_nodes:
						if (g._nodes[ni] as Vector2).distance_to(p) < 5.0:
							on = false
							break
				if on and not was_on.get(key, false):
					on_street += 1
					if firsts.size() < 8:
						firsts.append("walker on a street's asphalt at %s, no zebra near" % p.round())
				was_on[key] = on
			was[key] = [a.visible, p, 0.0]   # (shown before, or not: coming into range is not a pop)
		# traffic: popping in front, or moving further than it drives
		for i in range(g._traffic.cars.size()):
			var c = g._traffic.cars[i]
			var cp: Vector2 = c.pos
			var seen_c: bool = c.alive and not g._unseen(cp) and cp.distance_to(g._pos) < 60.0
			if seen_c and car_was.has(i):
				var pr: Array = car_was[i]
				if not pr[0] or (pr[1] as Vector2).distance_to(cp) > absf(c.v) * dt * 1.5 + 0.3:
					car_pops += 1
					if firsts.size() < 8:
						firsts.append("a %s popped at %s (%s)" % [c.kind, cp.round(), "showed up" if not pr[0] else "jumped %.1f m" % (pr[1] as Vector2).distance_to(cp)])
			car_was[i] = [c.alive, cp]
		for i in range(g._crossers.size()):
			var cr: Dictionary = g._crossers[i]
			var st: String = cr["state"]
			if st == "cross" and states.get(i, "") == "wait":
				crossed += 1
				var n: int = cr.get("sig", -1)
				if n >= 0:
					if g._light_at(n, cr["sig_dir"]) != "r":
						against_light += 1
			states[i] = st
	print("people popping up or jumping in view over %.0f s: %s" % [secs, str(pops) if not pops.is_empty() else "none"])
	print("people sliding sideways over 1 m/s in view: %d with your car within 8 m, %d with it further (stepping round each other and posts)" % [slide_near, slide_far])
	print("people on a street's asphalt away from a zebra (times it began): %d" % on_street)
	print("traffic cars popping up or jumping in view: %d" % car_pops)
	print("crossings started: %d; stepped out while the road had green or amber: %d" % [crossed, against_light])
	for s: String in firsts:
		print("  " + s)
	var n_pops := 0
	for k: String in pops:
		n_pops += int(pops[k])
	var bad := n_pops + slide_near + on_street + car_pops + against_light
	print("REGRESS people_pops: %s -- in view over %.0f s: people popping %d, sliding aside by your car %d, on a street away from a zebra %d, cars popping %d, crossing against the light %d (good 0 each; the bugs: everyone on the pavement slid a metre aside as autodrive passed, people stepped over side streets' mouths)" % [
		"PASS" if bad == 0 else "FAIL", secs, n_pops, slide_near, on_street, car_pops, against_light])
	quit(0)
