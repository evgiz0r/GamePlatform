extends SceneTree
## Where the cars sit across the road, driving straight: autodrive from the start for SECS
## seconds (LEVEL), and every traffic car about it. On straight stretches (no junction within
## 20 m), each car's gap from its right side to the asphalt's right edge, by kind of road
## (two-way or one-way, lanes, width) -- median, and how often under 0.3 m (hugging the
## kerb). The worst places with the road's name, a shot of the first. Also every time
## autodrive turned round on the spot, and where. ("They drive straight but stand very much
## on the right of the street.")
var g: Node
var T

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

## [gap to the right edge (m), road, its width] for a body at p heading `fwd`, half width hw;
## [] near a junction or off any road
func _gap(p: Vector2, fwd: Vector2, hw: float) -> Array:
	var hit: Dictionary = g._nearest_seg(p, 12.0, true, false)
	if hit.is_empty():
		return []
	var r: Dictionary = g._roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var ids: PackedInt32Array = r["ids"]
	for n: int in [ids[sj], ids[sj + 1]]:
		if g._node_ways(n) >= 3 and g._nodes[n].distance_to(p) < 20.0:
			return []
	var d: Vector2 = (pts[sj + 1] - pts[sj]).normalized()
	if d.dot(fwd) < 0.0:
		d = -d
	if absf(d.dot(fwd)) < 0.95:
		return []   # (not along it: turning, or across it)
	var right := Vector2(-d.y, d.x)
	var off := (p - (hit["q"] as Vector2)).dot(right)   # + right of the road's middle
	return [float(r["w"]) * 0.5 - off - hw, r, float(r["w"])]

func _key(r: Dictionary) -> String:
	if int(r["o"]) != 0:
		return "one-way, %d lane(s)" % g._lanes_each_way(r)
	return "two-way, %d lane(s) a way" % g._lanes_each_way(r)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	T = g._traffic
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	g._set_auto(true)
	var gaps := {}        # "who: road kind" -> Array of gaps
	var worst: Array = [] # [gap, who, road name, width, kind, where]
	var spins: Array = []
	var was_turning := false
	var shot := false
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < secs:
		await physics_frame
		t += dt
		if g._ap_turn > 0.0 and not was_turning:
			spins.append("%.0f s at %s on %s" % [t, Vector2i(g._pos), g._on_name])
		was_turning = g._ap_turn > 0.0
		if int(t * 60.0) % 6 != 0:
			continue
		var list: Array = []
		if absf(g._v) > 3.0:
			list.append(["autodrive", g._pos, g._fwd(), 0.9])
		for c in T.cars:
			if c.alive and c.v > 3.0:
				list.append([c.kind if c.kind in ["bus", "moto", "truck"] else "car", c.pos, Vector2(sin(c.yaw), cos(c.yaw)), 0.9 if c.kind != "bus" else 1.25])
		for e: Array in list:
			var gp := _gap(e[1], e[2], e[3])
			if gp.is_empty():
				continue
			var who: String = "autodrive" if e[0] == "autodrive" else "traffic " + String(e[0])
			var key := "%s: %s" % [who, _key(gp[1])]
			var arr: Array = gaps.get(key, [])
			arr.append(gp[0])
			gaps[key] = arr
			if float(gp[0]) < 0.3:
				worst.append([gp[0], who, (gp[1] as Dictionary)["en"], gp[2], _key(gp[1]), Vector2i(e[1])])
				if who == "autodrive" and not shot:
					shot = true
					await _snap("lane_hugging")
	print("LANE POSITION over %.0f s (gap from the right side to the asphalt's right edge, driving straight):" % secs)
	var keys := gaps.keys()
	keys.sort()
	for k in keys:
		var arr: Array = gaps[k]
		arr.sort()
		var under := 0
		for v in arr:
			if float(v) < 0.3:
				under += 1
		print("  %-44s %4d samples: median %.2f m, under 0.3 m %3.0f%%" % [k, arr.size(), float(arr[arr.size() / 2]), 100.0 * under / arr.size()])
	worst.sort_custom(func(a, b): return a[0] < b[0])
	print("hugging the right edge, the closest:")
	var seen := {}
	for w: Array in worst:
		var tag := "%s %s" % [w[1], w[2]]
		if seen.has(tag):
			continue
		seen[tag] = true
		print("  %.2f m  %-16s on %s (%.1f m wide, %s) at %s" % [w[0], w[1], w[2] if String(w[2]) != "" else "a road", w[3], w[4], w[5]])
		if seen.size() >= 10:
			break
	print("autodrive turned round on the spot %d time(s): %s" % [spins.size(), str(spins)])
	quit(0)
