extends SceneTree
## Where a deck (a bridge, an embankment, a cutting) meets the roads on the ground: every
## end of a drivable deck at a node a ground road also has. For each: the deck's height at
## its end against the ground road's there, and shots -- from a driver's height 18 m back
## along the ground road looking at the join, and from above at an angle.
##   LEVEL=2 SHOTS=12 game/streets/tests/run.sh deck_joins 2
## Run with DECKS_RECORD=1 for the check of what is drawn (below). SHOTS = how many joins to shoot (the rest only measured); AT="x,z" only the joins within
## 60 m of there. Prints each join: where, the deck's kind, its height over the ground at its
## last few points (a deck that ends above the ground leaves a step).
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var d = g._decks
	var at := Vector2.INF
	if OS.get_environment("AT") != "":
		var v := OS.get_environment("AT").split(",")
		at = Vector2(float(v[0]), float(v[1]))
	var joins: Array = []   # [deck road, end, node point, along (out of the deck), ground road]
	for ri: int in d.decks:
		var r: Dictionary = g._roads[ri]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var ids: PackedInt32Array = r["ids"]
		for end: int in [0, 1]:
			var j := 0 if end == 0 else pts.size() - 1
			var n := ids[j]
			var ground_r := -1
			for e: Vector2i in g._node_roads[n]:
				var o: Dictionary = g._roads[e.x]
				if e.x != ri and o["drive"] and not o.has("ys"):
					ground_r = e.x
			if ground_r < 0:
				continue
			if at != Vector2.INF and pts[j].distance_to(at) > 60.0:
				continue
			var inn := pts[1] if end == 0 else pts[pts.size() - 2]
			joins.append([ri, end, pts[j], (pts[j] - inn).normalized(), ground_r])
	print("deck_joins: ", joins.size(), " joins of a drivable deck with a ground road; points leveled with an overlapping road: %d (of them a divided road's lower half raised: %d; most moved %.2f m)" % [d.leveled, d.halves_raised, d.leveled_max])
	_check_drawn(d)
	_check_ends(d)
	_check_seams(d)
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 10
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var k := 0
	for jn: Array in joins:
		var ri: int = jn[0]
		var r: Dictionary = g._roads[ri]
		var p: Vector2 = jn[2]
		var out: Vector2 = jn[3]
		var ys: PackedFloat32Array = r["ys"]
		var gs: PackedFloat32Array = r["gs"]
		var lifts := []
		var n := ys.size()
		for q in range(4):
			var j: int = q if jn[1] == 0 else n - 1 - q
			if j >= 0 and j < n:
				lifts.append(snappedf(ys[j] - gs[j], 0.01))
		var gr: Dictionary = g._roads[jn[4]]
		print("join %d: (%d, %d) %s %s '%s' -> %s '%s'; lift from the end in: %s" % [k, p.x, p.y, r["deck"], r["k"], r.get("name", ""), gr["k"], gr.get("name", ""), str(lifts)])
		if k < shots:
			# from the ground side, looking back at the deck
			var from := p + out * 18.0
			g.look_from(Vector3(from.x, g._h(from) + 2.2, from.y), Vector3(p.x, g._h(p) + 0.5, p.y))
			await _snap("join_%02d_ground" % k)
			var from2 := p - out * 22.0
			g.look_from(Vector3(from2.x, d.deck_y(ri, from2) + 2.2, from2.y), Vector3(p.x, g._h(p) + 0.3, p.y))
			await _snap("join_%02d_deck" % k)
			var side := Vector2(-out.y, out.x)
			var up := p + side * 25.0 + out * 6.0
			g.look_from(Vector3(up.x, g._h(p) + 22.0, up.y), Vector3(p.x, g._h(p), p.y))
			await _snap("join_%02d_above" % k)
		k += 1
	quit(0)

## What decks.gd drew standing up (DECKS_RECORD=1: parapets, walls, guardrails, railings):
## any of it on another drivable road's carriageway at its own level (a rail across a slip
## road's mouth, a wall across a street at a ramp's foot), and runs shorter than LONE m
## standing alone (a parapet's scrap between two gaps). Both print where.
const LONE := 4.0
func _check_drawn(d) -> void:
	var seen := {}
	var on_lanes := 0
	var where: Array = []
	var runs := {}   # "road side" -> {index: length}
	for w: Array in d.drawn:
		var key := "%d %d %d %s" % [w[5], int(w[6]), w[7], w[4]]
		if seen.has(key):
			continue   # (a deck in several squares is drawn by each)
		seen[key] = true
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var rk := "%d %d %s" % [w[5], int(w[6]), w[4]]
		if not runs.has(rk):
			runs[rk] = {}
		runs[rk][int(w[7])] = a.distance_to(b)
		var n := maxi(1, ceili(a.distance_to(b) / 0.5))
		var hit := false
		for k in range(n + 1):
			var t := float(k) / n
			var p := a.lerp(b, t)
			var foot: float = lerpf(float(w[2]), float(w[3]), t) - (d.GUARD_H if w[4] == "guardrail" else d.PARAPET)
			for code: int in g._near(g._seg_hash, p, 8.0, g.SEG_CELL):
				var rj: int = code / 4096
				var r: Dictionary = g._roads[rj]
				if rj == int(w[5]) or not r["drive"]:
					continue
				var pts: PackedVector2Array = r["pts"]
				var sj: int = code % 4096
				if Geometry2D.get_closest_point_to_segment(p, pts[sj], pts[sj + 1]).distance_to(p) > float(r["w"]) * 0.5 - 0.3:
					continue
				var y: float = d.seg_y(rj, sj, p) if r.has("ys") else g._h(p)
				if absf(y - foot) < 0.8:
					hit = true
					break
			if hit:
				break
		if hit:
			on_lanes += 1
			if where.size() < 15:
				where.append("%s of road %d '%s' at (%d, %d)" % [w[4], w[5], g._roads[int(w[5])].get("name", ""), a.x, a.y])
	print("deck_joins: %d pieces drawn standing, %d on another road's lanes at its level" % [seen.size(), on_lanes])
	for s: String in where:
		print("  on lanes: ", s)
	var lone := 0
	var lone_at: Array = []
	for rk: String in runs:
		var idx: Array = (runs[rk] as Dictionary).keys()
		idx.sort()
		var start := 0
		while start < idx.size():
			var end := start
			var length: float = runs[rk][idx[start]]
			while end + 1 < idx.size() and int(idx[end + 1]) == int(idx[end]) + 1:
				end += 1
				length += float(runs[rk][idx[end]])
			if length < LONE:
				lone += 1
				if lone_at.size() < 15:
					var ri := int(rk.split(" ")[0])
					var pts: PackedVector2Array = d._dense(g._roads[ri]["pts"], 4.0 if g._roads[ri]["drive"] else 1.0)
					var q: Vector2 = pts[mini(int(idx[start]), pts.size() - 1)]
					lone_at.append("%s %.1f m, road %d '%s' near (%d, %d)" % [rk, length, ri, g._roads[ri].get("name", ""), q.x, q.y])
			start = end + 1
	print("deck_joins: %d runs shorter than %.0f m standing alone" % [lone, LONE])
	for s: String in lone_at:
		print("  lone: ", s)

## Deck ends that stop in the air (no other deck carries on there, and the deck is more than
## 0.3 m off the ground: a ledge to drive off, a hole under it), and two decks meeting at a
## bend (each ribbon ends square across its own way: the outside of the bend needs filling
## -- decks.gd's joint disc). Prints where.
func _check_ends(d) -> void:
	var hanging := 0
	var bends := 0
	var lines: Array = []
	for ri: int in d.decks:
		var r: Dictionary = g._roads[ri]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var ids: PackedInt32Array = r["ids"]
		var ys: PackedFloat32Array = r["ys"]
		var gs: PackedFloat32Array = r["gs"]
		for end: int in [0, 1]:
			var j := 0 if end == 0 else pts.size() - 1
			var others: Array = []
			var loop := false
			for e: Vector2i in g._node_roads[ids[j]]:
				if e.x != ri:
					others.append(e.x)
				elif e.y != j:
					loop = true   # (a roundabout: its end is its own start)
			if loop:
				continue
			var joint := false
			for o: int in others:
				joint = joint or (g._roads[o] as Dictionary).has("ys")
			if not joint and absf(ys[j] - gs[j]) > 0.3:
				hanging += 1
				if lines.size() < 20:
					lines.append("  in the air: road %d '%s' (%s) end at (%d, %d), %.1f m off the ground, %d other roads there" % [ri, r.get("name", ""), r["deck"], pts[j].x, pts[j].y, ys[j] - gs[j], others.size()])
			if others.size() == 1 and joint and end == 0:
				var o: Dictionary = g._roads[others[0]]
				var op: PackedVector2Array = o["pts"]
				var oi: PackedInt32Array = o["ids"]
				var q := op[1] if oi[0] == ids[j] else op[op.size() - 2]
				var bend := 180.0 - rad_to_deg(absf((pts[1] - pts[0]).angle_to(q - pts[0])))
				if bend > 4.0:
					bends += 1
	print("deck_joins: %d drivable deck ends in the air, %d joints between two decks at a bend over 4 degrees" % [hanging, bends])
	for l: String in lines:
		print(l)

## Seams: a drivable deck's asphalt edge lying on another road's carriageway (a deck's or the
## ground's) at a height 0.15-1.2 m off it -- a step you see from the car, or a slot under
## it (a divided road's two halves, lifted by different amounts, overlap at the median).
## Every 2 m along both edges; prints the worst places.
func _check_seams(d) -> void:
	var n := 0
	var total := 0
	var worst: Array = []
	var kinds := {}
	for ri: int in d.decks:
		var r: Dictionary = g._roads[ri]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = d._dense(r["pts"], 2.0)
		for sd: float in [-1.0, 1.0]:
			var line: PackedVector2Array = g._offset_line(pts, float(r["w"]) * 0.5 * sd)
			for i in range(line.size()):
				var p := line[i]
				var y: float = d.deck_y(ri, pts[i])
				total += 1
				var dy := 0.0
				var kind := ""
				for code: int in g._near(g._seg_hash, p, 8.0, g.SEG_CELL):
					var rj: int = code / 4096
					var o: Dictionary = g._roads[rj]
					if rj == ri or not o["drive"]:
						continue
					var op: PackedVector2Array = o["pts"]
					var sj: int = code % 4096
					if Geometry2D.get_closest_point_to_segment(p, op[sj], op[sj + 1]).distance_to(p) > float(o["w"]) * 0.5 - 0.2:
						continue
					var oy: float = d.seg_y(rj, sj, p) if o.has("ys") else g._h(p)
					var dd := absf(y - oy)
					if dd > 0.15 and dd < 1.2:
						dy = maxf(dy, dd)
						kind = ("a street on the ground" if not o.has("ys") else ("a tunnel or cutting" if not String(o["deck"]) in ["em", "br"]
							else ("the other half" if int(o["o"]) != 0 and int(r["o"]) != 0 and d._rank(o) == d._rank(r) else "another deck")))
				if dy > 0.0:
					n += 1
					kinds[kind] = int(kinds.get(kind, 0)) + 1
					if kind == "the other half" and OS.get_environment("HALVES") != "" and int(kinds[kind]) % 60 == 1:
						print("  half seam %.2f m at (%d, %d) road %d '%s' %s, its middle at %.2f" % [dy, p.x, p.y, ri, r.get("name", ""), r["deck"], y])
					worst.append([dy, "%.2f m: road %d '%s' (%s) at (%d, %d)" % [dy, ri, r.get("name", ""), r["deck"], p.x, p.y]])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("deck_joins: %d of %d deck edge points lie on another road's lanes 0.15-1.2 m above or below it (seams), by what is under or over: %s" % [n, total, str(kinds)])
	var shown := {}
	for w: Array in worst:
		var key := String(w[1]).get_slice("at", 0)
		if shown.size() >= 12:
			break
		if not shown.has(key):
			shown[key] = true
			print("  seam ", w[1])
