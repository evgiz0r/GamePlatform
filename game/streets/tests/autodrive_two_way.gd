extends SceneTree
## Autodrive for 90 s: how long it spends left of the middle of a two-way street (in the
## oncoming lane) away from junctions, how often it hits traffic or buildings, how far it got.
var g: Node
var crashes := {}
func _initialize() -> void:
	_run()
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
	g._set_auto(true)
	var t := 0.0
	var wrong := 0.0
	var near_mid := 0.0
	var two_way := 0.0
	var odo0: float = g._odo
	var last_hit := ""
	var hits := {}
	var stuck := 0.0
	var max_stuck := 0.0
	var dt := 1.0 / 60.0
	while t < 90.0:
		await physics_frame
		t += dt
		if g._cross_showing() and not g._cross["chosen"]:
			pass
		var h = g._last_hit
		if h != "" and h != last_hit and g._crash_cool > 0.0:
			var kind: String = h.split(" ")[0]
			hits[kind] = int(hits.get(kind, 0)) + 1
		last_hit = h
		if absf(g._v) < 0.5:
			stuck += dt
			max_stuck = maxf(max_stuck, stuck)
		else:
			stuck = 0.0
		var hit: Dictionary = g._nearest_seg(g._pos, 20.0, true, true)
		if hit.is_empty():
			continue
		var r: Dictionary = g._roads[hit["road"]]
		if int(r["o"]) != 0 or absf(g._v) < 2.0:
			continue
		# away from junctions
		var near_j := false
		for n2: int in [(r["ids"] as PackedInt32Array)[hit["seg"]], (r["ids"] as PackedInt32Array)[int(hit["seg"]) + 1]]:
			if g._node_ways(n2) >= 3 and g._nodes[n2].distance_to(g._pos) < g._node_r[n2] + 8.0:
				near_j = true
		if near_j:
			continue
		var pts: PackedVector2Array = r["pts"]
		var sj: int = hit["seg"]
		var d: Vector2 = (pts[sj + 1] - pts[sj]).normalized()
		if d.dot(g._fwd()) < 0.0:
			d = -d
		var right := Vector2(-d.y, d.x)
		var off: float = (g._pos - (hit["q"] as Vector2)).dot(right)
		two_way += dt
		if off < -0.3:
			wrong += dt
		elif off < 0.9:
			near_mid += dt
	print("90 s: %.0f m driven; on two-way streets %.0f s: left of the middle %.1f s, within 0.9 m right of it %.1f s; hits %s; longest standstill %.0f s" % [g._odo - odo0, two_way, wrong, near_mid, str(hits), max_stuck])
	quit(0)
