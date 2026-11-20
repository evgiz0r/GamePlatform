extends SceneTree
## Autodrive started on a divided road of two lanes or more: 120 s. Time on such roads and
## how far from the right lane's middle; how often its body overlapped a traffic car's
## (a bonk); hits by kind.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL"))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	# onto the nearest one-way road of two lanes or more, in its right lane
	var best := INF
	var at := Vector2.ZERO
	var dir := Vector2.ZERO
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or int(r["o"]) == 0 or g._lanes_each_way(r) < 2 or r.get("ring", false) or r["k"] == "service":
			continue
		var pts: PackedVector2Array = r["pts"]
		if pts.size() < 3:
			continue
		var m := pts.size() / 2
		var d: float = pts[m].distance_to(g._pos)
		if d < best:
			best = d
			dir = (pts[m + 1] - pts[m]).normalized() * float(r["o"])
			at = pts[m] + Vector2(-dir.y, dir.x) * float(g._lane_off(r))
	g._pos = at
	g._yaw = dir.angle()
	g._v = 0.0
	await create_timer(1.0).timeout
	g._set_auto(true)
	var T = g._traffic
	var t := 0.0
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var multi := 0.0
	var off_sum := 0.0
	var bonks := 0
	var touching := {}
	var hits := {}
	var last_hit := ""
	var odo0: float = g._odo
	var shot := false
	var passes := 0
	var passed_was: int = g._ap_passed
	while t < 120.0:
		await physics_frame
		t += dt
		if g._ap_passed != passed_was:
			passed_was = g._ap_passed
			passes += 1
		var h = g._last_hit
		if h != "" and h != last_hit and g._crash_cool > 0.0:
			var kind: String = h.split(" ")[0]
			hits[kind] = int(hits.get(kind, 0)) + 1
			var on: Dictionary = g._nearest_seg(g._pos, 30.0, true, true)
			var rr: Dictionary = g._roads[on["road"]] if not on.is_empty() else {}
			var lane_at := -1
			for j in range(g._ap_pts.size()):
				if g._ap_pts[j].distance_to(g._pos) < 8.0:
					lane_at = j
					break
			print("  hit %s at %.0f s, %.1f m/s, on %s (%s, o %s, w %.1f, lanes %d, lane %.1f), edge %.1f, plan point near: %s, cross %s, steer %.2f, backing %s" % [h, t, g._v,
				rr.get("en", "?"), rr.get("k", "?"), rr.get("o", "?"), float(rr.get("w", 0)), g._lanes_each_way(rr) if not rr.is_empty() else 0,
				g._lane_off(rr) if not rr.is_empty() else 0.0, float(on.get("edge", 99)), lane_at, not g._cross.is_empty(), g._steer, g._ap_back > 0.0])
			if OS.get_environment("OUT") != "" and int(hits[kind]) <= 2:
				await _snap("hit_%d_%s_%d" % [lvl, kind, int(hits[kind])])
		last_hit = h
		var fwd: Vector2 = g._fwd()
		var right := Vector2(-fwd.y, fwd.x)
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive:
				touching.erase(i)
				continue
			var rel: Vector2 = c.pos - g._pos
			var lon := absf(rel.dot(fwd))
			var lat := absf(rel.dot(right))
			var half_w: float = 0.55 if c.kind == "moto" else (1.25 if c.kind == "bus" else 0.9)
			var over := lat < 0.9 + half_w - 0.1 and lon < 2.3 + float(c.len) * 0.5 - 0.2
			if over and not touching.has(i):
				bonks += 1
				print("  bonk at %.0f s: %s %.1f m across, %.1f along, me %.1f m/s, it %.1f m/s, backing %s, its blocker %d" % [t, c.kind, lat, lon, g._v, c.v, g._ap_back > 0.0, c.blocker])
				if not shot and OS.get_environment("OUT") != "":
					shot = true
					await _snap("bonk_%d" % lvl)
			if over:
				touching[i] = true
			else:
				touching.erase(i)
		var hit: Dictionary = g._nearest_seg(g._pos, 15.0, true, true)
		if hit.is_empty() or absf(g._v) < 2.0:
			continue
		var r: Dictionary = g._roads[hit["road"]]
		if int(r["o"]) == 0 or g._lanes_each_way(r) < 2:
			continue
		var pts: PackedVector2Array = r["pts"]
		var sj: int = hit["seg"]
		var d: Vector2 = (pts[sj + 1] - pts[sj]).normalized() * float(r["o"])
		var lat_me: float = (g._pos - (hit["q"] as Vector2)).dot(Vector2(-d.y, d.x))
		multi += dt
		off_sum += absf(lat_me - float(g._lane_off(r))) * dt
	print("buses passed at their stops: %d" % passes)
	print("120 s from %.0f m away: %.0f m driven; on multi-lane one-ways %.0f s, %.2f m from the right lane's middle on average; bonks %d; hits %s" % [best, g._odo - odo0, multi, off_sum / maxf(multi, 0.01), bonks, str(hits)])
	quit(0)
