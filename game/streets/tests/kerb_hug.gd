extends SceneTree
## Autodrive along the kerb: Evgeni, 23 Nov 2026, Bedford's Union Street at 32 km/h with its
## right wheels on the kerb's edge -- "sometimes gets stuck like this on the side". Drives
## TRIPS trips (default 3) by "go to" from FROM to TO (x,z; default the length of Union Street),
## and every tick on a straight stretch (no junction within 20 m) takes the gap from the car's
## right side to the asphalt's right edge, and where its plan's line sits. Prints each stretch
## of 1 s+ under HUG m (default 0.3): where, how long, the road's width, where the car sits
## from the road's middle against where its lane is (_lane_off), the plan's line there, and
## what autodrive said (_ap_why, the plan point moves _ap_cleared) -- so the reason shows.
##   LEVEL=2 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/kerb_hug.gd
## Good: no stretch, the car's right side ~1 m from the edge on an 8 m street.
var g: Node

func _initialize() -> void:
	_run()

func _vec(env: String, def: Vector2) -> Vector2:
	var s := OS.get_environment(env)
	if s == "":
		return def
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

## [gap right side to edge, offset of p from the road's middle (+ right), road, its lane] or []
func _gap(p: Vector2, fwd: Vector2) -> Array:
	var hit: Dictionary = g._nearest_seg(p, 12.0, true, false)
	if hit.is_empty():
		return []
	var r: Dictionary = g._roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var ids: PackedInt32Array = r["ids"]
	for n: int in [ids[sj], ids[sj + 1]]:
		if n >= 0 and g._node_ways(n) >= 3 and g._nodes[n].distance_to(p) < 20.0:
			return []
	var d: Vector2 = (pts[sj + 1] - pts[sj]).normalized()
	if d.dot(fwd) < 0.0:
		d = -d
	if absf(d.dot(fwd)) < 0.95:
		return []
	var right := Vector2(-d.y, d.x)
	var off := (p - (hit["q"] as Vector2)).dot(right)
	return [float(r["w"]) * 0.5 - (off + 0.92), off, r, float(g._lane_off(r)) if int(r["o"]) == 0 else 0.0, right, hit["q"]]

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 2})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	var from := _vec("FROM", Vector2(450.0, -1150.0))
	var to := _vec("TO", Vector2(830.0, -1945.0))
	var trips := int(OS.get_environment("TRIPS")) if OS.get_environment("TRIPS") != "" else 3
	var hug := float(OS.get_environment("HUG")) if OS.get_environment("HUG") != "" else 0.3
	var t := 0.0
	var gaps: Array = []
	var stretches := 0
	for trip in range(trips):
		var a := from if trip % 2 == 0 else to
		var b := to if trip % 2 == 0 else from
		g._land_on_road(a, 60.0, Vector2.ZERO)
		await physics_frame
		g._set_dest(b, "there")
		g._set_auto(true)
		var t0 := t
		var run := 0.0
		var first: Array = []
		while t - t0 < 240.0 and g._dest_on:
			await physics_frame
			t += Engine.time_scale / Engine.physics_ticks_per_second
			if OS.get_environment("VERBOSE") != "" and fmod(t - t0, 10.0) < 0.017:
				print("  t %.0f at (%.0f, %.0f) on %s %.0f km/h, held by %s" % [t - t0, g._pos.x, g._pos.y, g._on_name, absf(g._v) * 3.6, g._ap_why])
			if absf(g._v) < 3.0:
				run = 0.0
				continue
			var e := _gap(g._pos, g._fwd())
			if e.is_empty():
				run = 0.0
				continue
			gaps.append(e[0])
			if float(e[0]) < hug:
				if run == 0.0:
					# the plan's line here: its nearest point, from the road's middle
					var pl := 99.0
					var pts: PackedVector2Array = g._ap_pts
					for j in range(pts.size() - 1):
						var cp := Geometry2D.get_closest_point_to_segment(g._pos, pts[j], pts[j + 1])
						if cp.distance_to(g._pos) < 6.0:
							pl = (cp - (e[5] as Vector2)).dot(e[4])
							break
					first = [t - t0, g._pos, e, pl, g._ap_why, g._ap_cleared, g._on_name, absf(g._v) * 3.6]
				run += Engine.time_scale / Engine.physics_ticks_per_second
				if absf(run - 1.0) < 0.01:
					stretches += 1
					var r: Dictionary = first[2][2]
					print("HUG trip %d t %.0f at (%.0f, %.0f) on %s %.0f km/h: right side %.2f m from the edge, the car %.2f m right of the middle (its lane %.2f, the plan's line %.2f), road %.1f m %s o=%d, held by %s, plan points moved so far %d" % [
						trip, first[0], (first[1] as Vector2).x, (first[1] as Vector2).y, first[6], first[7], first[2][0], first[2][1], first[2][3], first[3],
						float(r["w"]), r["k"], int(r["o"]), first[4], first[5]])
			else:
				run = 0.0
		print("trip %d: %.0f s, arrived %s" % [trip, t - t0, str(not g._dest_on)])
	gaps.sort()
	var under := 0
	for x: float in gaps:
		if x < hug:
			under += 1
	print("KERB HUG: %d stretches of 1 s+ under %.1f m; gap median %.2f m, %.0f%% of straight driving under %.1f m" % [
		stretches, hug, gaps[gaps.size() / 2] if not gaps.is_empty() else -1.0, 100.0 * under / maxf(gaps.size(), 1), hug])
	quit(0)
