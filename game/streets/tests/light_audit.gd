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

func _arms(j: int) -> Array:
	var out: Array = []   # [way in, road, name, one-way ok]
	var c: Vector2 = g._nodes[j]
	for e: Vector2i in g._node_roads[j]:
		var r: Dictionary = g._roads[e.x]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		for d2: int in [-1, 1]:
			var from := e.y + d2
			if from < 0 or from >= pts.size():
				continue
			var ok: bool = r["o"] == 0 or r["o"] == -d2
			out.append([(c - pts[from]).normalized(), e.x, String(r["name"]), ok])
	return out

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
	# ---- groups at each lit junction
	var conflicts := 0
	var conflict_j := {}
	var single := 0
	for j: int in g._lit:
		var arms := _arms(j)
		var seen := {}
		var groups := {}
		for a: Array in arms:
			groups[g._light_group(j, a[0])] = true
		if groups.size() < 2:
			single += 1
		for x in range(arms.size()):
			for y in range(x + 1, arms.size()):
				var A: Array = arms[x]
				var B: Array = arms[y]
				if not A[3] or not B[3]:
					continue
				var da: Vector2 = A[0]
				var db: Vector2 = B[0]
				if absf(da.dot(db)) < 0.6 and g._light_group(j, da) == g._light_group(j, db):
					conflicts += 1
					conflict_j[j] = true
					if verbose:
						print("  same group, crossing: node %d at %s  '%s' %s / '%s' %s  angle %d" % [j, g._nodes[j].round(), A[2], da.snapped(Vector2(0.01, 0.01)), B[2], db.snapped(Vector2(0.01, 0.01)), int(rad_to_deg(da.angle_to(db)))])
	print("lit junctions %d; crossing ways in sharing a group: %d (at %d junctions); junctions with one group only: %d" % [g._lit.size(), conflicts, conflict_j.size(), single])
	# ---- stop points that are not a junction's (a light mapped a few metres out)
	var short := 0
	for n: int in g._sig_set:
		if g._node_ways(n) < 3:
			var near_j := false
			for o: int in g._sig_set:
				if o != n and g._node_ways(o) >= 3 and g._nodes[o].distance_to(g._nodes[n]) < 40.0:
					near_j = true
			if near_j:
				short += 1
				if verbose:
					print("  stop point %d %s is not a junction, and a lit junction is within 40 m" % [n, g._nodes[n].round()])
	var multi := 0
	var most := 0
	for st: Dictionary in g._sites:
		if (st["nodes"] as Array).size() > 1:
			multi += 1
		most = maxi(most, (st["nodes"] as Array).size())
	if verbose:
		for st: Dictionary in g._sites:
			var ns: Array = st["nodes"]
			if ns.size() >= 4:
				var names := {}
				var span := 0.0
				for n: int in ns:
					span = maxf(span, g._nodes[n].distance_to(st["c"]))
					for e: Vector2i in g._node_roads[n]:
						names[String((g._roads[e.x] as Dictionary)["name"])] = true
				print("  site of %d points at %s, %.0f m across: %s" % [ns.size(), (st["c"] as Vector2).round(), span * 2.0, ", ".join(names.keys())])
	print("sites %d (of several points: %d, the most %d); stop points short of a junction (where no pole stands): %d" % [g._sites.size(), multi, most, short])
	# ---- knots: a junction's points within 35 m of each other along a road
	var unlit_twins := 0
	var split_groups := 0
	for j: int in g._lit:
		for e: Vector2i in g._node_roads[j]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"]:
				continue
			var ids: PackedInt32Array = r["ids"]
			var pts: PackedVector2Array = r["pts"]
			for step: int in [-1, 1]:
				var k := e.y
				var d := 0.0
				while k + step >= 0 and k + step < ids.size():
					d += pts[k].distance_to(pts[k + step])
					k += step
					if d > 35.0:
						break
					var o: int = ids[k]
					if g._node_ways(o) < 3:
						continue
					if not g._lit.has(o) and not g._sig_set.has(o) and g._other_half(j, o, e.x):
						unlit_twins += 1
						if verbose:
							print("  lit %d %s and the unlit other half of its road %d %.0f m along '%s'" % [j, g._nodes[j].round(), o, d, r["name"]])
					elif g._lit.has(o) and o > j:
						# travelling j -> o along this road: same light both?
						var dir := (pts[k] - pts[k - step]).normalized()
						var gj: int = g._light_group(j, (pts[e.y] - pts[e.y - step]).normalized() if e.y - step >= 0 and e.y - step < pts.size() else dir)
						var go: int = g._light_group(o, dir)
						if gj != go:
							split_groups += 1
							if verbose:
								print("  knot %d -> %d along '%s' (%.0f m): group %d then %d" % [j, o, r["name"], d, gj, go])
					break
	print("knots: lit junction with the other half of its divided road unlit: %d; a road through two lit points of one knot in different groups: %d" % [unlit_twins, split_groups])
	# ---- ways in with no pole: built poles face -dir from their spot
	var no_pole := 0
	var on_zebra := 0
	for j: int in g._lit:
		for a: Array in g._sig_line.get(j, []):
			if a[3]:
				continue   # from inside the site: no light on purpose
			var din: Vector2 = a[0]
			# where a stopped car's front is, against the zebras on that way in
			var front: Vector2 = g._nodes[j] - din * (float(a[1]) + 1.0)
			for ni: int in g._crossing_nodes:
				var zp: Vector2 = g._nodes[ni]
				if zp.distance_to(front) < 12.0:
					var along := (front - zp).dot(din)
					if absf((front - zp).dot(Vector2(-din.y, din.x))) < 3.0 and along > -1.5 and along < 1.5 + g.CAR_LEN:
						on_zebra += 1
						if verbose:
							print("  node %d %s: a car stopped at the line has its front on the zebra %d" % [j, g._nodes[j].round(), ni])
			var found := false
			for sp: Array in g._light_spots:
				var hd: Vector3 = sp[0]
				var p := Vector2(hd.x, hd.z)
				if p.distance_to(g._nodes[j]) < 30.0 and (sp[1] as Vector2).dot(-din) > 0.95:
					found = true
					break
			if not found:
				no_pole += 1
				if verbose:
					var r: Dictionary = g._roads[int(a[2])]
					print("  node %d %s: no light for the way in %s along '%s' (%s, w %.1f, one-way %d)" % [j, g._nodes[j].round(), din.snapped(Vector2(0.01, 0.01)), r["name"], r["k"], r["w"], r["o"]])
	print("ways in to a lit junction with no light facing them: %d; stop lines that leave a waiting car's front on a zebra: %d" % [no_pole, on_zebra])
	# ---- walk lights: the road under the zebra, both ways, against the walk light's group
	var walk_bad := 0
	var walk_n := 0
	for ni: int in g._crossing_nodes:
		var z: Array = g._zebra_geom(ni)
		if z.is_empty():
			continue
		var j: int = g._zebra_light(ni)
		if j < 0:
			continue
		walk_n += 1
		var gw: int = g._light_group(j, z[3])
		var gb: int = g._light_group(j, -(z[3] as Vector2))
		if gw != gb:
			walk_bad += 1
			if verbose:
				print("  zebra %d %s: its road is group %d one way and %d the other" % [ni, (z[0] as Vector2).round(), gw, gb])
	print("zebras with walk lights: %d; of them on a road with green one way while the green man shows: %d" % [walk_n, walk_bad])
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
	var creeps := {}
	var line_was := {}    # mover -> the site the game says it is in (sites only)
	var over := {"g": 0, "y": 0, "r": 0}
	var me_over := {"g": 0, "y": 0, "r": 0}
	for f in range(60 * secs):
		await physics_frame
		if f % 600 == 0 and verbose:
			print("  t=%d s: car at %s %.1f m/s, odo %.0f m" % [f / 60, g._pos.round(), g._v, g._odo])
		var movers: Array = []
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if c.alive:
				movers.append([i, c.pos, Vector2(sin(c.yaw), cos(c.yaw)), c.v, c.len])
		movers.append([-1, g._pos, g._fwd(), absf(g._v), g.CAR_LEN])
		var in_site := {}   # site -> [[way, mover], ...] moving inside it
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
								print("  t=%.1f crossing ways moving inside site %d together: %s and %s" % [f / 60.0, site, ms[a][1], ms[b][1]])
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
	print("crossing ways moving in one junction together: %d; cars that waited 6 s at a lit junction and crept in: %d" % [conflicts, creeps.size()])
	if has_sites:
		print("over the stop line (the game's own count): traffic on green %d, amber %d, red %d; autodrive on green %d, amber %d, red %d" % [over["g"], over["y"], over["r"], me_over["g"], me_over["y"], me_over["r"]])
