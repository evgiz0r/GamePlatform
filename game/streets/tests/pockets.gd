extends SceneTree
## Pockets (see the game's _find_pockets): streets inside the map's edge with no way back to
## the town's main network but against a one-way ("traps"), or no way to them from it ("cut
## off"). Prints how many points and how many km of public street each takes, and checks the
## two ways round them: a "go to" an address in a cut-off pocket finds a way (to the nearest
## street that has one), and a route set down in a trap starts outside it; and that traffic
## is not put down inside one. Writes
## $OUT/pockets_<city>.json (the points, for tests/pockets_map.py to draw).
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --headless --path . -s res://game/streets/tests/pockets.gd
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(0.5).timeout
	var t0 := Time.get_ticks_usec()
	g._find_pockets()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	# public street metres in each
	var km := {"trap": 0.0, "cut_off": 0.0, "all": 0.0}
	for r: Dictionary in g._roads:
		if not r["drive"] or r["pv"] or r["k"] == "service":
			continue
		var ids: PackedInt32Array = r["ids"]
		var pts: PackedVector2Array = r["pts"]
		for j in range(ids.size() - 1):
			var L := pts[j].distance_to(pts[j + 1])
			km["all"] += L
			if g._trap.has(ids[j]) and g._trap.has(ids[j + 1]):   # (wholly in one)
				km["trap"] += L
			if g._cut_off.has(ids[j]) and g._cut_off.has(ids[j + 1]):
				km["cut_off"] += L
	print("pockets in %s (found in %.0f ms): traps %d points, %.1f km of public street; cut off %d points, %.1f km; of %.1f km" % [
		g._city_id, ms, g._trap.size(), km["trap"] / 1000.0, g._cut_off.size(), km["cut_off"] / 1000.0, km["all"] / 1000.0])
	if OS.get_environment("OUT") != "":
		var out := {"city": g._city_id, "trap": [], "cut_off": []}
		for n: int in g._trap:
			out["trap"].append([snappedf(g._nodes[n].x, 0.1), snappedf(g._nodes[n].y, 0.1)])
		for n: int in g._cut_off:
			out["cut_off"].append([snappedf(g._nodes[n].x, 0.1), snappedf(g._nodes[n].y, 0.1)])
		FileAccess.open(OS.get_environment("OUT") + "/pockets_%s.json" % g._city_id, FileAccess.WRITE).store_string(JSON.stringify(out))
	# "go to" addresses in cut-off pockets: is a way found now?
	var tried := 0
	var found := 0
	for st: String in g._addr:
		for a: Array in g._addr[st]:
			var at: Vector2 = a[1]
			var hit: Dictionary = g._nearest_seg(at, 150.0, true, true)
			if hit.is_empty() or not g._pocketed(hit, g._cut_off):
				continue
			tried += 1
			g._dest_name = "%s %s" % [st, a[0]]
			if g._route_to(at):
				found += 1
			elif OS.get_environment("VERBOSE") != "":
				var alt: Dictionary = g._nearest_seg_out(at, 400.0, g._cut_off)
				var gi: PackedInt32Array = g._roads[hit["road"]]["ids"]
				var me: Dictionary = g._nearest_seg(g._pos, 40.0, true, true)
				var mi: PackedInt32Array = g._roads[me["road"]]["ids"]
				var ai: PackedInt32Array = g._roads[alt["road"]]["ids"] if not alt.is_empty() else PackedInt32Array([-1, -1])
				var aj: int = alt.get("seg", 0)
				print("  no way: goal seg ends cut off %s/%s; nearest clear seg %s (%.0f m off, one-way %d, ends %d %d trap %s/%s); start seg ends trap %s/%s; a* start->alt ends %d / %d points" % [
					g._cut_off.has(gi[hit["seg"]]), g._cut_off.has(gi[hit["seg"] + 1]), "none" if alt.is_empty() else str(alt["q"]),
					(alt["q"] as Vector2).distance_to(at) if not alt.is_empty() else -1.0, int(g._roads[alt["road"]]["o"]) if not alt.is_empty() else 9,
					ai[aj], ai[aj + 1], g._trap.has(ai[aj]), g._trap.has(ai[aj + 1]), g._trap.has(mi[me["seg"]]), g._trap.has(mi[me["seg"] + 1]),
					g._astar.get_id_path(mi[me["seg"] + 1], ai[aj]).size() if ai[aj] >= 0 else -1, g._astar.get_id_path(mi[me["seg"] + 1], ai[aj + 1]).size() if ai[aj] >= 0 else -1])
			break
		if tried >= 8:
			break
	print("go to an address in a cut-off pocket: a way found %d of %d" % [found, tried])
	# a route set down in a trap: does it start outside?
	var moved := 0
	var traps := 0
	for st: String in g._addr:
		for a: Array in g._addr[st]:
			var hit: Dictionary = g._nearest_seg(a[1], 60.0, true, true)
			if hit.is_empty() or not g._pocketed(hit, g._trap):
				continue
			traps += 1
			g._route = {"id": 0, "from": "%s %s" % [st, a[0]], "from_at": [a[1].x, a[1].y], "to": "the middle",
				"to_at": [g._bounds.get_center().x, g._bounds.get_center().y]}
			g._route_begin()
			var on: Dictionary = g._nearest_seg(g._pos, 10.0, true, true)
			if not on.is_empty() and not g._pocketed(on, g._trap):
				moved += 1
			break
		if traps >= 5:
			break
	g._route = {}
	g._set_auto(false)
	print("a route from an address in a trap: started outside it %d of %d" % [moved, traps])
	# traffic put down round a player standing in or by a pocket: none of it inside one (it
	# never got out: a trap's one-ways, a cut-off pocket's barrier)
	var put := 0
	var inside := 0
	var tries := 0
	for marks: Dictionary in [g._trap, g._cut_off]:
		for n: int in marks:
			if tries >= 8:
				break
			if tries > 0 and (g._nodes[n] as Vector2).distance_to(g._pos) < 300.0:
				continue
			tries += 1
			g._pos = g._nodes[n]
			for c in g._traffic.cars:
				c.alive = g._traffic._spawn(c, true)
				if not c.alive:
					continue
				put += 1
				var on: Dictionary = g._nearest_seg(c.pos, 6.0, true, true)
				if not on.is_empty() and (g._pocketed(on, g._trap) or g._pocketed(on, g._cut_off)):
					inside += 1
	print("traffic put down round %d places in or by a pocket: %d cars, %d inside a pocket" % [tries, put, inside])
	print("POCKETS: %s" % ("PASS" if found == tried and moved == traps and inside == 0 else "FAIL"))
	quit(0)
