extends SceneTree
## The city as built, checked for the traps that cost bug reports, before anyone drives it.
## Seconds once the city is up; run it for every city after a change to how a city is laid
## out (roads, kerbs, walls, furniture, buildings, lights) and after merging one.
##
##   game/streets/tests/run.sh city_check 1          (1-4; 0 runs all four, one after another)
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --path . -s res://game/streets/tests/city_check.gd
##
## Each count is measured on the thing's body, not its middle (a wall checked at its middle
## once left its end on the road, a hedge's end too). Should be 0:
##   walls on the road     -- a fence, hedge, garden wall or shelter back more than 0.3 m into
##                            a street's asphalt anywhere along it (sampled every metre)
##   posts on the road     -- a tree, pole, bollard, hydrant, column... 0.3 m into a street's
##                            asphalt (parked cars, which are posts to the car, left out)
##   buildings on the road -- a solid building's outline 0.3 m into a street's asphalt
##                            (Givatayim keeps 3 over a road on purpose: passages)
##   lit points alone      -- a point with traffic lights that belongs to no junction
## Traps, not bugs -- where to stage a scene test, since each has bitten before:
##   stub roads            -- a drivable road under 5 m long at a junction (one 1.5 m long
##                            turned autodrive's lane round, into the oncoming lane)
##   split junctions       -- lit points under 25 m apart counted as two junctions (one
##                            junction's points each deciding alone gave green both ways)
##   on service roads      -- walls and posts on car-park lanes and driveways (barriers and
##                            pumps belong there; a bollard row may not)
var g: Node
const PARKED_R := 0.85   ## a parked car is two posts of this radius (streets.gd)

func _initialize() -> void:
	_run()

func _load(lvl: int) -> void:
	g = null
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd") \
					and not n.is_queued_for_deletion():
				g = n
	await create_timer(0.5).timeout

func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	await create_timer(0.3).timeout
	var bad := 0
	for l: int in ([1, 2, 3, 4] if lvl == 0 else [lvl]):
		await _load(l)
		bad += _check()
	print("CITY CHECK: %d found (0 is good)" % bad)
	quit(0)

## how far a body of half-thickness `half` at q runs into the nearest drivable road's asphalt
## (> 0: in it), and that road
func _into(q: Vector2, half: float) -> Array:
	var hit: Dictionary = g._nearest_seg(q, 20.0, true, false)
	if hit.is_empty():
		return [-INF, -1]
	# past the last point of a dead end the distance is to that point, a half circle the
	# asphalt does not fill (it stops square): not on the road
	var rd: Dictionary = g._roads[int(hit["road"])]
	var pts: PackedVector2Array = rd["pts"]
	var ids: PackedInt32Array = rd["ids"]
	for e: int in [0, pts.size() - 1]:
		# (drivable ways only: a street that ends where a footpath goes on is a dead end for a
		# car, and the railings across the path's mouth stand past it, rightly)
		var drive_ways := 0
		for w: Vector2i in g._node_roads[ids[e]]:
			if (g._roads[w.x] as Dictionary)["drive"]:
				drive_ways += 1
		if (hit["q"] as Vector2).distance_to(pts[e]) < 0.01 and drive_ways <= 1:
			var dir := (pts[1] - pts[0]) if e == 0 else (pts[e] - pts[e - 1])
			if (q - pts[e]).dot(dir * (-1.0 if e == 0 else 1.0)) > 0.0:
				return [-INF, -1]
	return [half - float(hit["edge"]), int(hit["road"])]

func _service(ri: int) -> bool:
	return ri >= 0 and String((g._roads[ri] as Dictionary)["k"]) == "service"

func _name(ri: int) -> String:
	var en := String((g._roads[ri] as Dictionary).get("en", ""))
	return en if en != "" else String((g._roads[ri] as Dictionary)["k"])

func _check() -> int:
	var out := {}            ## kind -> [[how far, where, what], ...]
	var add := func(kind: String, d: float, at: Vector2, what: String) -> void:
		if not out.has(kind):
			out[kind] = []
		(out[kind] as Array).append([d, at, what])
	# -- walls: every metre along them, and their ends
	for i in range(g._wall_r.size()):
		var a: Vector2 = g._walls[i * 2]
		var b: Vector2 = g._walls[i * 2 + 1]
		var half: float = g._wall_r[i]
		if half > 0.45:
			continue   # medians: walls in the road on purpose
		var steps := maxi(1, int(ceil(a.distance_to(b))))
		var worst := [-INF, -1, a]
		for s in range(steps + 1):
			var q := a.lerp(b, float(s) / steps)
			var r: Array = _into(q, half)
			if float(r[0]) > float(worst[0]):
				worst = [r[0], r[1], q]
		if float(worst[0]) > 0.3:
			var kind := "fence" if half <= 0.07 else ("shelter back" if half <= 0.1 else ("garden wall" if half <= 0.2 else "hedge"))
			add.call("walls on service roads" if _service(worst[1]) else "walls on the road", worst[0], worst[2],
				"%s (wall %d), %.1f m into %s" % [kind, i, float(worst[0]), _name(worst[1])])
	# -- posts
	for i in range(g._posts.size()):
		var r: float = g._post_r[i]
		if is_equal_approx(r, PARKED_R):
			continue
		var q: Vector2 = g._posts[i]
		var hit: Array = _into(q, r)
		if float(hit[0]) > 0.3:
			add.call("posts on service roads" if _service(hit[1]) else "posts on the road", hit[0], q,
				"post %d (%.2f m across), %.1f m into %s" % [i, r * 2.0, float(hit[0]), _name(hit[1])])
	# -- buildings: their outline's corners and every metre of their sides
	for bi in range(g._blds.size()):
		if g._bld_solid[bi] == 0:
			continue   # raised on columns: you drive under it
		var ring: PackedVector2Array = g._blds[bi]
		var worst := [-INF, -1, Vector2.ZERO]
		for k in range(ring.size()):
			var a2: Vector2 = ring[k]
			var b2: Vector2 = ring[(k + 1) % ring.size()]
			var steps := maxi(1, int(ceil(a2.distance_to(b2))))
			for s in range(steps):
				var q := a2.lerp(b2, float(s) / steps)
				var r: Array = _into(q, 0.0)
				if float(r[0]) > float(worst[0]) and not _service(r[1]):
					worst = [r[0], r[1], q]
		if float(worst[0]) > 0.3:
			add.call("buildings on the road", worst[0], worst[2], "building %d, %.1f m into %s" % [bi, float(worst[0]), _name(worst[1])])
	# -- lights
	for n: int in g._sig_set.keys():
		if not g._site_of.has(n):
			add.call("lit points alone", 0.0, g._nodes[n], "node %d" % n)
		for m: int in g._near(g._sig_hash, g._nodes[n], 25.0, g.SEG_CELL):
			if m > n and g._nodes[m].distance_to(g._nodes[n]) < 25.0 and g._site_of.get(m, -1) != g._site_of.get(n, -2):
				add.call("split junctions", g._nodes[m].distance_to(g._nodes[n]), g._nodes[n],
					"nodes %d and %d, %.0f m apart, junctions %d and %d" % [n, m, g._nodes[m].distance_to(g._nodes[n]),
					g._site_of.get(n, -1), g._site_of.get(m, -1)])
	# -- stub roads at junctions
	for ri in range(g._roads.size()):
		var rd: Dictionary = g._roads[ri]
		if not rd["drive"] or rd.has("y"):
			continue
		var pts: PackedVector2Array = rd["pts"]
		var l := 0.0
		for k in range(pts.size() - 1):
			l += pts[k].distance_to(pts[k + 1])
		var ids: PackedInt32Array = rd["ids"]
		if l < 5.0 and (g._node_ways(ids[0]) >= 3 or g._node_ways(ids[ids.size() - 1]) >= 3):
			add.call("stub roads", l, pts[0], "%s, %.1f m (road %d)" % [_name(ri), l, ri])
	var failing := ["walls on the road", "posts on the road", "buildings on the road", "lit points alone"]
	var traps := ["stub roads", "split junctions", "walls on service roads", "posts on service roads"]
	var found := 0
	print("CITY CHECK %s (%d roads, %d buildings, %d walls, %d posts, %d lit points):" % [g._city_name,
		g._roads.size(), g._blds.size(), g._wall_r.size(), g._posts.size(), g._sig_set.size()])
	for kind: String in failing + traps:
		var list: Array = out.get(kind, [])
		list.sort_custom(func(x, y): return x[0] > y[0])
		if kind in failing:
			found += list.size()
		print("  %-24s %5d%s" % [kind, list.size(), "" if kind in failing else "   (traps: where to stage a test)"])
		for e: Array in list.slice(0, 6):
			print("      at %-14s %s" % [str(Vector2i(e[1])), e[2]])
	return found
