extends SceneTree
## Every signalled junction checked against what a driver and a walker would expect:
##  - crossing ways in that share a group (both green at once)
##  - ways in that read their light from a node well short of the junction (cars stop where
##    no pole stands)
##  - the points of one junction drawn as several (a divided road) grouped differently
##  - a lit point next to an unlit one in the same knot (one half of a divided road stops,
##    the other never does)
##  - ways in that cars obey but no pole was put up for
##  - walk lights whose road has green one way while the green man shows
## then N seconds (DRIVE, default 120) of autodrive and traffic, counting cars that come into
## a lit junction on red, and cars standing inside one.
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
	await create_timer(1.0).timeout
	if OS.get_environment("DYNAMIC_ONLY") != "":
		await _drive()
		quit(0)
		return
	var verbose := OS.get_environment("VERBOSE") != ""
	var W := preload("res://game/streets/tests/world_checks.gd")
	for line: String in (W.light_counts(g, verbose)["lines"] as Array):
		print(line)
	if OS.get_environment("STATIC_ONLY") != "":
		quit(0)
		return
	# ---- driving: what a player would see at the lights
	await _drive()
	quit(0)

## N seconds of autodrive and traffic (DRIVE, default 120; AT=x,z[,dx,dz] puts the car there
## first). Counted per junction with lights (a site; on the old code, each lit point):
##  - cars coming in from outside it on red (traffic, and autodrive)
##  - moments two cars on crossing ways move inside it together (per 2 s)
##  - cars that waited 6 s at its edge and crept in (giving way gone wrong)
## Works on the code before sites too (DYNAMIC_ONLY=1 skips the checks above), for a before/after.
func _drive() -> void:
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	if OS.get_environment("AT") != "":
		var xy := OS.get_environment("AT").split(",")
		var at := Vector2(float(xy[0]), float(xy[1]))
		g._land_on_road(at, 40.0, Vector2(float(xy[2]), float(xy[3])) if xy.size() >= 4 else Vector2.RIGHT)
		await create_timer(1.0).timeout
	g._set_auto(true)
	var verbose := OS.get_environment("VERBOSE") != ""
	var has_sites := "_site_of" in g
	var T = g._traffic
	var secs := int(OS.get_environment("DRIVE")) if OS.get_environment("DRIVE") != "" else 120
	var inside := {}      # mover -> the site it is in (or last came into), -1 none
	var back := {}        # mover -> where it was ~1 s ago
	var entries := {"g": 0, "y": 0, "r": 0}
	var me := {"g": 0, "y": 0, "r": 0}
	var conflicts := 0
	var counted := {}
	var counted_pt := {}
	var creeps := {}
	var line_was := {}    # mover -> the site the game says it is in (sites only)
	var over := {"g": 0, "y": 0, "r": 0}
	var me_over := {"g": 0, "y": 0, "r": 0}
	for f in range(60 * secs):
		await physics_frame
		if f % 600 == 0 and verbose:
			print("  t=%d s: car at %s %.1f m/s, odo %.0f m, held by %s" % [f / 60, g._pos.round(), g._v, g._odo, g._ap_why])
		var movers: Array = []
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if c.alive:
				movers.append([i, c.pos, Vector2(sin(c.yaw), cos(c.yaw)), c.v, c.len])
		movers.append([-1, g._pos, g._fwd(), absf(g._v), g.CAR_LEN])
		var in_site := {}   # site -> [[way, mover], ...] moving inside it
		var in_point := {}  # the same by lit point (what the old code called a junction)
		for m: Array in movers:
			var id: int = m[0]
			var p: Vector2 = m[1]
			if f % 60 == 0 or not back.has(id) or (back[id] as Vector2).distance_to(p) > 20.0:
				back[id] = p
			var came: Vector2 = p - (back[id] as Vector2)
			if came.length() < 2.0:
				came = m[2]
			came = came.normalized()
			var nose: Vector2 = p + (m[2] as Vector2) * float(m[4]) * 0.5
			var now := -1
			var at_n := -1
			for n: int in g._near(g._sig_hash, p, 30.0, g.SEG_CELL):
				var site: int = g._site_of.get(n, n) if has_sites else n
				if nose.distance_to(g._nodes[n]) < g._node_r[n] + 1.2 and (id < 0 or T._node_index(T.cars[id], n) >= 0):
					now = site
					at_n = n
					if float(m[3]) > 2.0:
						if not in_site.has(site):
							in_site[site] = []
						(in_site[site] as Array).append([m[2], id])
						if not in_point.has(n):
							in_point[n] = []
						(in_point[n] as Array).append([m[2], id])
			var was: int = inside.get(id, -1)
			if now >= 0 and now != was:
				inside[id] = now
				if float(m[3]) > 1.0:
					var st: String = g._light_at(at_n, came)
					if st != "":
						if id < 0:
							me[st] += 1
						else:
							entries[st] += 1
						if st == "r" and verbose:
							print("  t=%.1f %s into %d (%s) on red at %.1f m/s" % [f / 60.0, "autodrive" if id < 0 else "car %d (%s)" % [id, T.cars[id].kind], at_n, g._nodes[at_n].round(), m[3]])
			elif now < 0 and was >= 0:
				# out of the site's points' circles: out, once well away from all of them
				var far := true
				for n: int in g._near(g._sig_hash, p, 40.0, g.SEG_CELL):
					if (g._site_of.get(n, n) if has_sites else n) == was and p.distance_to(g._nodes[n]) < 40.0:
						far = false
				if far:
					inside[id] = -1
		# over a stop line, as the game sees it: the light then
		if has_sites:
			for i in range(-1, T.cars.size()):
				var now_s: int = g._light_site if i < 0 else (T.cars[i].last_site if T.cars[i].alive else -1)
				if now_s >= 0 and now_s != line_was.get(i, -1):
					var st := ""
					if i < 0:
						var bn := -1
						for n: int in g._near(g._sig_hash, g._pos, 40.0, g.SEG_CELL):
							if g._site_of[n] == now_s and (bn < 0 or g._nodes[n].distance_to(g._pos) < g._nodes[bn].distance_to(g._pos)):
								bn = n
						if bn >= 0:
							st = g._light_at(bn, g._came_dir())
					else:
						var c = T.cars[i]
						for j in range(maxi(c.k - 2, 0), mini(c.k + 30, c.pts.size())):
							if c.node[j] >= 0 and g._site_of.get(c.node[j], -1) == now_s:
								st = g._light_at(c.node[j], T._came(c, j))
								break
					if st != "":
						if i < 0:
							me_over[st] += 1
						else:
							over[st] += 1
						if st == "r" and verbose:
							print("  t=%.1f %s over the stop line of site %d on red" % [f / 60.0, "autodrive" if i < 0 else "car %d" % i, now_s])
				line_was[i] = now_s
		for site: int in in_site:
			var ms: Array = in_site[site]
			for a in range(ms.size()):
				for b in range(a + 1, ms.size()):
					if absf((ms[a][0] as Vector2).dot(ms[b][0])) < 0.5:
						var key := "%d:%d" % [site, f / 120]
						if not counted.has(key):
							counted[key] = true
							conflicts += 1
							if verbose:
								var why: Array = []
								for id: int in [ms[a][1], ms[b][1]]:
									if id < 0:
										why.append("autodrive (%s)" % g._ap_why)
									else:
										var cc = T.cars[id]
										why.append("car %d %s light %s wait %.1f ignore %.1f in-site %s" % [id, cc.kind, g._light_at(g._sites[site]["nodes"][0], Vector2(sin(cc.yaw), cos(cc.yaw))) if has_sites else "?", cc.jwait, cc.ignore, (cc.last_site == site) if has_sites else "?"])
								print("  t=%.1f crossing ways moving inside site %d together: %s" % [f / 60.0, site, " / ".join(why)])
		for n: int in in_point:
			var ms: Array = in_point[n]
			for a in range(ms.size()):
				for b in range(a + 1, ms.size()):
					if absf((ms[a][0] as Vector2).dot(ms[b][0])) < 0.5:
						var key := "%d:%d" % [n, f / 120]
						if not counted_pt.has(key):
							counted_pt[key] = true
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if c.alive and c.jwait > 6.0:
				for n: int in g._near(g._sig_hash, c.pos, 25.0, g.SEG_CELL):
					var key := "%d:%d" % [i, g._site_of.get(n, n) if has_sites else n]
					if not creeps.has(key):
						creeps[key] = true
						if verbose:
							print("  t=%.1f car %d crept into the junction at %d after waiting 6 s" % [f / 60.0, i, n])
					break
	print("%d s, car %.0f m: traffic came into a junction with lights on green %d, amber %d, red %d; autodrive on green %d, amber %d, red %d (the game counted %d red)" % [secs, g._odo, entries["g"], entries["y"], entries["r"], me["g"], me["y"], me["r"], g._reds])
	print("crossing ways moving in one junction together: %d (by point: %d); cars that waited 6 s at a lit junction and crept in: %d" % [conflicts, counted_pt.size(), creeps.size()])
	if has_sites:
		print("over the stop line (the game's own count): traffic on green %d, amber %d, red %d; autodrive on green %d, amber %d, red %d" % [over["g"], over["y"], over["r"], me_over["g"], me_over["y"], me_over["r"]])
