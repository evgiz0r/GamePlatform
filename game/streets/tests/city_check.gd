extends SceneTree
## The city as built, checked for the traps that cost bug reports, before anyone drives it.
## Seconds once the city is up; run it for every city after a change to how a city is laid
## out (roads, kerbs, walls, furniture, buildings, lights) and after merging one.
##
##   game/streets/tests/run.sh city_check 1          (1-4; 0 runs all four, one after another)
##   SHOTS=1 OUT=dir game/streets/tests/run.sh city_check 1    and a picture of the worst two
##       of each kind that should be 0, from 30 m up (city_<kind>_<n>.png), the place ringed
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
## and the user's reports since these checks began, each fixed with a test that staged it
## (world_checks.gd says which), so none comes back unseen. Should be 0: signs doubled, a
## junction offering one street twice, a traffic island on the road, a median's wall over
## another road. Under the city's limit (LIMITS): roads leaning over 6% side to side, two
## pavings laid over one spot (they flicker).
##   LEVEL=0 runs Givatayim, Bedford, Ashdod, the test town and Tel Aviv, one after another.
## Traps, not bugs -- where to stage a scene test, since each has bitten before:
##   stub roads            -- a drivable road under 5 m long at a junction (one 1.5 m long
##                            turned autodrive's lane round, into the oncoming lane)
##   split junctions       -- lit points under 25 m apart counted as two junctions (one
##                            junction's points each deciding alone gave green both ways)
##   on service roads      -- walls and posts on car-park lanes and driveways (barriers and
##                            pumps belong there; a bollard row may not)
##   buildings on private lanes -- a private road (pv) through or into a building: a passage
##                            or a garage's mouth (HaKirya's lanes in Tel Aviv). The game does
##                            not cut buildings back from private lanes (_kerbed); no traffic
##                            or route uses them, but the player can drive in
var g: Node
var _found := {}
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
	for l: int in ([1, 2, 3, 4, 7] if lvl == 0 else [lvl]):
		await _load(l)
		bad += await _check(l)
		if OS.get_environment("SHOTS") != "" and OS.get_environment("OUT") != "":
			await _shots()
	print("CITY CHECK: %d found (0 is good)" % bad)
	quit(0)

## how far a body of half-thickness `half` at q runs into the nearest drivable road's asphalt
## (> 0: in it), and that road
func _into(q: Vector2, half: float) -> Array:
	var hit: Dictionary = g._nearest_seg(q, 20.0, true, false)
	if hit.is_empty():
		return [-INF, -1]
	# a rounded corner's asphalt is road too (the straight strips alone missed 159 posts on
	# Givatayim's corners, which another session found): how far the body is in past the
	# corner's kerb line, measured as on a straight road
	var corner := _corner_depth(q, half)
	if corner > -INF:
		var straight := half - float(hit["edge"])
		return [maxf(straight, corner), int(hit["road"])]
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

## how far a body of half-width `half` at q runs into a rounded corner's asphalt past its
## curved kerb line (the fill's outline from its second point to its last but one), or -INF
## when q is on no corner's fill
func _corner_depth(q: Vector2, half: float) -> float:
	if not ("_fill_hash" in g):
		return -INF
	var best := -INF
	for key: int in g._near(g._fill_hash, q, half + 1.0, g.BLD_CELL):
		var poly: PackedVector2Array = g._corner_fill[key]
		var d := INF
		for k in range(1, poly.size() - 1):
			d = minf(d, Geometry2D.get_closest_point_to_segment(q, poly[k], poly[k + 1]).distance_to(q))
		if Geometry2D.is_point_in_polygon(q, poly):
			best = maxf(best, half + d)
	return best

## what a post is, as far as the game's lists tell (a signal pole stands on a light spot)
func _post_kind(q: Vector2, r: float) -> String:
	for ls: Array in g._light_spots:
		var v: Vector3 = ls[0]
		if Vector2(v.x, v.z).distance_to(q) < 0.3:
			return "signal pole"
	if "_moto_at" in g:
		for m: Vector2 in g._moto_at:
			if m.distance_to(q) < 0.1:
				return "parked motorbike"
	if is_equal_approx(r, 0.3):
		return "tree, bin, gatepost or A-board"   # (all 0.3 m: a bin on Katznelson read as a tree)
	if is_equal_approx(r, 0.15):
		return "lamp, cat or pole"
	return "post"

## a lit point in words: how many ways meet there (2: a crossing mid-street, not a junction)
## and the roads through it
func _node_desc(n: int) -> String:
	var names := []
	for e: Vector2i in g._node_roads[n]:
		var r: Dictionary = g._roads[e.x]
		if r["drive"]:
			names.append("%s%s" % [_name(e.x), " (one-way)" if int(r["o"]) != 0 else ""])
	return "%d ways: %s" % [g._node_ways(n), ", ".join(names)]

func _service(ri: int) -> bool:
	return ri >= 0 and String((g._roads[ri] as Dictionary)["k"]) == "service"

func _name(ri: int) -> String:
	var en := String((g._roads[ri] as Dictionary).get("en", ""))
	return en if en != "" else String((g._roads[ri] as Dictionary)["k"])

## The limits for the checks of the user's reports that never read 0 (world_checks.gd), per
## level, from the measures after each fix with room for small changes: over one, the fixed
## bug is coming back. Tilt: the share of road leaning over 6% side to side (Givatayim's
## ground model holds roofs, its open problem). Pavings: m2 of two different pavings at one
## height over one spot (Tel Aviv read 30 after the fix).
const LIMITS := {
	1: {"tilt": 8.0, "pavings": 60.0},
	2: {"tilt": 3.0, "pavings": 60.0},
	3: {"tilt": 3.0, "pavings": 60.0},
	4: {"tilt": 3.0, "pavings": 60.0},
	7: {"tilt": 3.0, "pavings": 60.0},
}

func _check(lvl: int) -> int:
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
				"post %d (%.2f m across, %s), %.1f m into %s" % [i, r * 2.0, _post_kind(q, r), float(hit[0]), _name(hit[1])])
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
			# (a private lane -- Tel Aviv's 14 were all HaKirya's, running under a building or into
			# its garage, 21 Nov: a trap, not a street anyone is sent down)
			var pv := int(worst[1]) >= 0 and bool((g._roads[int(worst[1])] as Dictionary)["pv"])
			add.call("buildings on private lanes" if pv else "buildings on the road", worst[0], worst[2],
				"building %d, %.1f m into %s" % [bi, float(worst[0]), _name(worst[1])])
	# -- lights
	for n: int in g._sig_set.keys():
		if not g._site_of.has(n):
			add.call("lit points alone", 0.0, g._nodes[n], "node %d" % n)
		for m: int in g._near(g._sig_hash, g._nodes[n], 25.0, g.SEG_CELL):
			if m > n and g._nodes[m].distance_to(g._nodes[n]) < 25.0 and g._site_of.get(m, -1) != g._site_of.get(n, -2):
				add.call("split junctions", g._nodes[m].distance_to(g._nodes[n]), g._nodes[n],
					"nodes %d and %d, %.0f m apart, junctions %d and %d; %s / %s" % [n, m, g._nodes[m].distance_to(g._nodes[n]),
					g._site_of.get(n, -1), g._site_of.get(m, -1), _node_desc(n), _node_desc(m)])
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
	_found = out
	var failing := ["walls on the road", "posts on the road", "buildings on the road", "lit points alone"]
	var traps := ["stub roads", "split junctions", "walls on service roads", "posts on service roads", "buildings on private lanes"]
	var found := 0
	print("CITY CHECK %s (%d roads, %d buildings, %d walls, %d posts, %d lit points):" % [g._city_name,
		g._roads.size(), g._blds.size(), g._wall_r.size(), g._posts.size(), g._sig_set.size()])
	for kind: String in failing + traps:
		var list: Array = out.get(kind, [])
		list.sort_custom(func(x, y): return x[0] > y[0])
		if kind in failing:
			found += list.size()
		print("  %-24s %5d%s" % [kind, list.size(), "" if kind in failing else "   (traps: where to stage a test)"])
		if kind.begins_with("posts") and list.size() > 6:
			var by := {}
			for e: Array in list:
				var m := String(e[2])
				var k2 := m.substr(m.find(", ") + 2, m.find(")") - m.find(", ") - 2) if m.find(", ") >= 0 else "post"
				by[k2] = int(by.get(k2, 0)) + 1
			print("      by kind: %s" % str(by))
		for e: Array in list.slice(0, 6):
			print("      at %-14s %s" % [str(Vector2i(e[1])), e[2]])
	# -- the user's reports since these checks began, each fixed and staged by a test of its own
	# (world_checks.gd names them): should read 0, or stay under the city's limit
	while g._bg_build:
		await create_timer(0.5).timeout
	var W := preload("res://game/streets/tests/world_checks.gd")
	for row: Array in [["signs doubled", W.signs_doubled(g)], ["junction offers twice", W.junction_twins(g)],
			["islands on the road", W.islands_on_road(g)], ["median over a road (m)", W.medians_over_roads(g)]]:
		var res: Array = row[1]
		var v := float(res[0])
		found += ceili(v)
		print("  %-24s %5d%s" % [row[0], ceili(v), ("      at " + String(res[1])) if v > 0.0 else ""])
	var lim: Dictionary = LIMITS.get(lvl, {})
	for row: Array in [["road leaning over 6% (%)", "tilt", W.tilt(g)], ["two pavings at once (m2)", "pavings", W.pavings_overlap(g)]]:
		var res: Array = row[2]
		var v := float(res[0])
		var cap := float(lim.get(row[1], INF))
		var over := v > cap
		if over:
			found += 1
		print("  %-24s %5.1f   (limit %s)%s  %s" % [row[0], v, "%.1f" % cap if cap < INF else "not set",
			"  OVER" if over else "", res[1]])
	return found

func _snap(name: String) -> void:
	await create_timer(0.6).timeout   # draw ranges settle after a camera move
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")   # (the 3D view alone, no HUD)
	print("shot ", name)

## the worst two of each kind that should be 0, from 30 m over the roofs round it and a
## little to the south (at a flat 30 m up one shot was the inside of a tower block), a red
## ring round the place
func _shots() -> void:
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.1, 0.1)
	mat.no_depth_test = true
	ring.material_override = mat
	g.world.add_child(ring)   # (the 3D world: under the game's own Node2D it is never drawn)
	for kind: String in ["walls on the road", "posts on the road", "buildings on the road"]:
		var list: Array = _found.get(kind, [])
		for k in range(mini(2, list.size())):
			var at: Vector2 = list[k][1]
			var y: float = g._h(at)
			ring.position = Vector3(at.x, y + 0.3, at.y)
			var up := maxf(30.0, g._roof_near(at, 25.0) + 20.0)
			g.look_from(Vector3(at.x, y + up, at.y + up * 0.4), Vector3(at.x, y, at.y))
			g._sky_follow()   # (the sky dome follows the camera in the game's frame, stopped here: a
			                  # kilometre from the start the camera was outside it, a blank picture)
			await _snap("city_%s_%s_%d" % [g._city_id, kind.replace(" ", "_"), k + 1])
	ring.queue_free()
