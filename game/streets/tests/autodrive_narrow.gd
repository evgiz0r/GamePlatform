extends SceneTree
## Autodrive through the narrow streets around David Kalai (Givatayim): each second it stands,
## what holds it. Then the narrowest two-way streets near the start, the same.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
func _why() -> String:
	var fwd: Vector2 = g._fwd()
	var parts: Array = []
	var lead: Array = g._traffic.lead_on(g._ap_pts, g._pos, 30.0, g._ap_wait > 3.0)
	if float(lead[0]) < 30.0:
		parts.append("lead %.1f m (v %.1f)" % [float(lead[0]), float(lead[1])])
	var nose: Vector2 = g._pos + fwd * (g.CAR_OFF + 0.5)
	if g._push_out(nose, 1.15, true, false) != Vector2.ZERO:
		parts.append("nose blocked by %s" % g._last_hit)
	if g._ap_back > 0.0:
		parts.append("backing")
	if g._ap_turn > 0.0:
		parts.append("turning round")
	if not g._cross.is_empty():
		parts.append("crossing choice")
	if g._ap_light_v() < 1.0:
		parts.append("light")
	if g._ap_zebra_v() < 1.0 or g._ap_people_v() < 1.0:
		parts.append("people")
	for c in g._traffic.cars:
		if c.alive and c.pos.distance_to(g._pos) < 9.0:
			parts.append("%s %.1f m away, facing %s, v %.1f, wait %.1f, blocker %d" % [c.kind, c.pos.distance_to(g._pos),
				"me" if Vector2(sin(c.yaw), cos(c.yaw)).dot(fwd) < -0.5 else "my way" if Vector2(sin(c.yaw), cos(c.yaw)).dot(fwd) > 0.5 else "across", c.v, c.wait, c.blocker])
	return ", ".join(parts)
func _drive(label: String, secs: float) -> void:
	g._set_auto(true)
	var t := 0.0
	var still := 0.0
	var longest := 0.0
	var reported := 0
	var shot := false
	while t < secs:
		await physics_frame
		t += Engine.time_scale / Engine.physics_ticks_per_second
		if absf(g._v) < 0.4:
			still += Engine.time_scale / Engine.physics_ticks_per_second
			longest = maxf(longest, still)
			if int(still) > reported:
				reported = int(still)
				if reported <= 4 or reported % 5 == 0:
					var on: Dictionary = g._nearest_seg(g._pos, 20.0, true, true)
					var r: Dictionary = g._roads[on["road"]] if not on.is_empty() else {}
					print("  %s %.0f s, still %d s on %s (o %s, w %.1f): %s" % [label, t, reported, r.get("en", "?"), r.get("o", "?"), float(r.get("w", 0)), _why()])
				if reported == 8 and not shot and OS.get_environment("OUT") != "":
					shot = true
					await _snap("narrow_%s" % label)
		else:
			still = 0.0
			reported = 0
	print("%s: longest standstill %.0f s, drove %.0f m" % [label, longest, g._odo])
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 1})
	while g == null or not g._loaded:   # (however long the city takes to build)
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)   # (what this measures doesn't depend on it, and it runs ~3x faster)
	var spots: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if r["drive"] and String(r["en"]) == "David Kalai":
			spots.append(ri)
			print("David Kalai piece: o %d, w %.1f, l %d, lane %.2f, points %d" % [r["o"], r["w"], r["l"], g._lane_off(r), (r["pts"] as PackedVector2Array).size()])
	var narrow: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if r["drive"] and not r["pv"] and r["k"] in ["residential", "living_street", "unclassified"] and float(r["w"]) <= 6.0 \
				and (r["pts"] as PackedVector2Array).size() >= 2 and (r["pts"] as PackedVector2Array)[0].distance_to(g._pos) < 700.0:
			narrow.append(ri)
	narrow.shuffle()
	spots.append_array(narrow.slice(0, 4))
	for i in range(spots.size()):
		var r: Dictionary = g._roads[spots[i]]
		var pts: PackedVector2Array = r["pts"]
		var dir := 1 if int(r["o"]) >= 0 else -1
		var a: Vector2 = pts[0] if dir > 0 else pts[pts.size() - 1]
		var b: Vector2 = pts[1] if dir > 0 else pts[pts.size() - 2]
		var d := (b - a).normalized()
		g._set_auto(false)
		g._pos = a + d * 6.0 + Vector2(-d.y, d.x) * float(g._lane_off(r))
		g._yaw = d.angle()
		g._v = 0.0
		g._snap_pose()
		await physics_frame
		await _drive("%s_%d" % [String(r["en"]).replace(" ", ""), i], 50.0)
	quit(0)
