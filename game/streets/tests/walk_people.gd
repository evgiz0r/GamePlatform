extends SceneTree
## The people round a filmed walk, as the walker sees them (the user, on walk 2's replay:
## "people are popping randomly and moving aimlessly on my path, and no collision between
## them and the parked cars"). Plays the walk of LEVEL (default 6, Sheinkin and Sirkin) from
## its start to its end and, every tick, looks at everyone in the street:
##   pop       someone in the camera's view within 75 m (not behind a building) who was not
##             there the tick before (just made visible, or moved more than 1.5 m in a tick)
##   turned    a walker turning back on the spot in view within 40 m (the end of its stretch)
##   swerve    a walker within 8 m stepping more than 0.5 m off its line, and how far
##   close     someone within 0.58 m of the walker (two bodies in one place: walked through;
##             0.6 is the floor they are held at)
##   in car    someone (or a dog, a pushchair) more than 0.15 m into a parked car's body (4.4 x
##             1.8 m, its corners rounded; the car found as its end posts, 2.8 m apart)
## UNTIL=s stops there. SEED=n another day's people (who goes where hangs on frame times as well as the seed).
## FROM=s starts the walk s seconds in (walk 2's Sirkin is from about 45 s; a whole walk takes
## 15 minutes of wall time here, mostly the street's own tick). Run headless at a fixed tick
## (no screenshots):
##   STREETS_BUILD_ALL=0 LEVEL=6 FROM=45 $GODOT --headless --fixed-fps 10 --path . -s res://game/streets/tests/walk_people.gd
var g: Node
var last := {}        ## actor id -> [visible, position]

## a walker's place on its line, for the pops: which line, how far along, which way, where across
func _walker_state(w: Dictionary) -> String:
	var line: PackedVector2Array = w.get("line", PackedVector2Array())
	return "with %s, line %d pts from %s, s %.2f, dir %s, lat %.2f, lane %.2f, dodge %.2f, at %s" % [w.get("with", "-"),
		line.size(), Vector2i(line[0]) if line.size() > 0 else "-", float(w.get("s", 0.0)), w.get("dir", "-"),
		float(w.get("lat", 0.0)), float(w.get("lane", 0.0)), float(w.get("dodge", 0.0)), w.get("at", "-")]

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var lv := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 6
	root.get_node("Flow").start_game("streets", {"level": lv})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	if g._film.is_empty():
		print("FAIL no walk on level %d" % lv)
		print("REGRESS walk_people: FAIL -- filmed walk on level %d none (good: one to replay)" % lv)
		quit(1)
		return
	var end: float = g._film[g._film.size() - 1].z
	if OS.get_environment("SEED") != "":   # (another day's people: who goes where hangs on the frame times too)
		g._people_rng.seed = int(OS.get_environment("SEED"))
	if OS.get_environment("FROM") != "":
		g._film_t = float(OS.get_environment("FROM"))
		for i in range(20):   # (the people round the new spot put out, unseen, before counting)
			await process_frame
	# the parked cars: their end posts, 0.85 m, 2.8 m apart, one after the other (_add_car_posts)
	var cars: Array = []   # [middle, along]
	for i in range(g._posts.size() - 1):
		if is_equal_approx(g._post_r[i], 0.85) and is_equal_approx(g._post_r[i + 1], 0.85) \
				and absf(g._posts[i].distance_to(g._posts[i + 1]) - 2.8) < 0.02:
			cars.append([(g._posts[i] + g._posts[i + 1]) * 0.5, (g._posts[i] - g._posts[i + 1]).normalized()])
	var car_hash := {}
	for k in range(cars.size()):
		var c: Vector2 = cars[k][0]
		var key := Vector2i(floori(c.x / 10.0), floori(c.y / 10.0))
		if not car_hash.has(key):
			car_hash[key] = []
		car_hash[key].append(k)
	print("walk of %.0f s on level %d from %.0f s; %d parked cars known" % [end, lv, g._film_t, cars.size()])
	var counts := {"pop": 0, "turned": 0, "swerve": 0, "close": 0, "in car": 0, "dog across": 0}
	var shown := {}
	var in_car_now := {}
	var swerving := {}
	var closest := INF
	var deepest := 0.0
	var met := {}   # everyone seen within 40 m
	var until := float(OS.get_environment("UNTIL")) if OS.get_environment("UNTIL") != "" else end
	while g._film_t <= until:
		await process_frame
		var t: float = g._film_t
		var me: Vector2 = g._pos
		var cam: Camera3D = g.cam
		var bodies: Array = []   # [id, kind, where, radius]: for the parked cars
		for kind: String in ["walker", "chatter", "crosser", "sitter", "waiter"]:
			var list: Array = {"walker": g._walkers, "chatter": g._chatters, "crosser": g._crossers,
				"sitter": g._sitters, "waiter": g._waiters}[kind]
			for w: Dictionary in list:
				var a: Node3D = w["actor"]
				var id := a.get_instance_id()
				var p := Vector2(a.position.x, a.position.z)
				var d := p.distance_to(me)
				# (behind a building from the eye is not seen: people are put down and taken away
				# round corners and behind blocks -- g._spawn_ok -- where the frustum still holds them)
				var eye := Vector2(cam.global_position.x, cam.global_position.z)
				var seen: bool = a.visible and d < 75.0 and cam.is_position_in_frustum(a.position + Vector3.UP) and not g._behind_building(eye, p)
				var was: Array = last.get(id, [a.visible, p])   # (the first look: what is there already counts as there)
				if seen and (not was[0] or (was[1] as Vector2).distance_to(p) > 1.5):
					counts["pop"] += 1
					_say(shown, "pop", "%5.1f s  pop: a %s %s %.0f m away (%s)" % [t, kind,
						"appears" if not was[0] else "jumps %.1f m" % (was[1] as Vector2).distance_to(p), d, Vector2i(p)])
					if kind == "walker":   # (what it was doing the tick before and now)
						print("    before %s\n    now    %s" % [was[2] if was.size() > 2 else "-", _walker_state(w)])
				last[id] = [a.visible, p, _walker_state(w) if kind == "walker" else ""]
				if not a.visible:
					continue
				if seen and d < 40.0:
					met[id] = true
				bodies.append([id, kind, p, 0.25])
				if d < 0.58:   # (0.6 is the floor walkers are held at: a push off a post after it left 0.599)
					counts["close"] += 1
					closest = minf(closest, d)
					_say(shown, "close", "%5.1f s  close: a %s %.2f m from the walker at %s%s" % [t, kind, d, Vector2i(me),
						(" (walker %d%s, hold %s, lat %.2f, lane %.2f, dir %d)" % [g._walkers.find(w), " beside %d" % int(w["with"]) if w.has("with") else "",
						w.get("hold_me", false), float(w.get("lat", 0.0)), float(w.get("lane", 0.0)), int(w.get("dir", 0))]) if kind == "walker" else ""])
				if w.has("dog_at") and d < float(g.PEOPLE_SEEN):   # its dog on its own side of any fence or railing
					var dg := Vector3(w["dog_at"].x, 0.0, w["dog_at"].y)
					var across: bool = g._wall_between(p, Vector2(dg.x, dg.z))
					if across and not w.get("was_across", false):
						counts["dog across"] = int(counts.get("dog across", 0)) + 1
						_say(shown, "dog across", "%5.1f s  dog across: a fence or railing between a walker at %s and its dog at %s (%.1f m apart), %.0f m from the walker" % [t,
							Vector2i(p), Vector2i(dg.x, dg.z), p.distance_to(Vector2(dg.x, dg.z)), d])
					w["was_across"] = across
				if kind == "walker" and w.has("line") and (w["line"] as PackedVector2Array).size() >= 2:
					var off := absf(float(w.get("lat", 0.0))) + float(w.get("dodge", 0.0))
					if d < 8.0 and off > 0.5 and not swerving.get(id, false):
						counts["swerve"] += 1
						_say(shown, "swerve", "%5.1f s  swerve: a walker %.1f m off its line (side step %.2f, dodge %.2f), %.1f m from the walker" % [t, off,
							float(w.get("lat", 0.0)), float(w.get("dodge", 0.0)), d])
					swerving[id] = off > 0.5
					# turning back on its own stretch (a new stretch, walked on to, is not a turn)
					var line: PackedVector2Array = w["line"]
					var key := [line[0], line.size(), float(w["dir"])]
					var was_key: Array = w.get("was_key", key)
					if was_key[0] == key[0] and was_key[1] == key[1] and was_key[2] != key[2] and seen and d < 40.0:
						counts["turned"] += 1
						_say(shown, "turned", "%5.1f s  turned: a walker turns back at the end of its stretch, %.0f m away in view" % [t, d])
					w["was_key"] = key
		# the dogs and pushchairs, where shown (where the game put them: a headless run reads a
		# multimesh's copies back as nothing)
		for w: Dictionary in g._walkers:
			var wa: Node3D = w["actor"]
			if not wa.visible or Vector2(wa.position.x, wa.position.z).distance_to(me) > float(g.PEOPLE_SEEN):
				continue
			for spec: Array in [["dog_at", "dog", 0.25], ["pram_at", "pushchair", 0.3]]:
				if w.has(spec[0]):
					bodies.append([spec[1] + str(wa.get_instance_id()), spec[1], w[spec[0]], spec[2]])
		# into a parked car's body: 4.3 x 1.8 m, someone's middle closer to it than their own size
		for b: Array in bodies:
			var p: Vector2 = b[2]
			var depth := 0.0
			var how := ""
			var key := Vector2i(floori(p.x / 10.0), floori(p.y / 10.0))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for k: int in car_hash.get(key + Vector2i(dx, dz), []):
						var rel: Vector2 = p - cars[k][0]
						var al: Vector2 = cars[k][1]
						# its outline 4.4 x 1.8 m, the corners rounded 0.45 m as a car's are
						var q := Vector2(absf(rel.dot(al)) - 1.75, absf(rel.dot(al.orthogonal())) - 0.45)
						var gap := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 0.45
						if float(b[3]) - gap > depth:
							depth = float(b[3]) - gap
							how = "%.2f along, %.2f across" % [rel.dot(al), rel.dot(al.orthogonal())]
			var inside := depth > 0.15   # (a hand's width: brushing a wing mirror is not walking through)
			var d := p.distance_to(me)
			if inside and not in_car_now.get(b[0], false) and d < 75.0:
				counts["in car"] += 1
				var pushed: Vector2 = g._push_out(p, 0.25, true, false)
				_say(shown, "in car", "%5.1f s  in car: a %s %.2f m into a parked car (its middle %s of the car's), %.0f m from the walker, at %s; pushed now %.2f m by %s" % [t, b[1], depth, how, d, Vector2i(p),
					pushed.length(), g._last_hit if pushed != Vector2.ZERO else "nothing"])
			if d < 75.0:
				deepest = maxf(deepest, depth if inside else 0.0)
			in_car_now[b[0]] = inside
	print("over the walk: %s; nearest anyone came %s; deepest into a car %.2f m; people met within 40 m: %d" % [counts,
		"%.2f m" % closest if closest < INF else "-", deepest, met.size()])
	# The bug ("people are popping randomly and moving aimlessly on my path, and no collision
	# between them and the parked cars"): a cafe table's person jumped 2.3 m in view, walkers
	# stood 0.55 m into a parked car (then 0.17-0.27 m into its corners). The fix read 0 pops,
	# nobody within 0.6 m of you, nobody past a hand's width (0.15 m) into a car: each must
	# stay 0. Turning back and stepping aside read 0-1 and hang on who is out that day: shown,
	# not judged.
	var bad: int = int(counts["pop"]) + int(counts["close"]) + int(counts["in car"])
	print("REGRESS walk_people: %s -- pops %d, within 0.6 m of you %d, into a parked car %d (deepest %.2f m); turned %d, swerves %d (good 0, 0, 0; the bug: a jump of 2.3 m in view, 0.55 m into a car)" % [
		"PASS" if bad == 0 else "FAIL", counts["pop"], counts["close"], counts["in car"], deepest, counts["turned"], counts["swerve"]])
	quit()

func _say(shown: Dictionary, what: String, line: String) -> void:
	shown[what] = int(shown.get(what, 0)) + 1
	if int(shown[what]) <= 12:
		print(line)
