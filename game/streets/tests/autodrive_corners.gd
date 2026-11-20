extends SceneTree
## Autodrive leaving the asphalt: 150 s of autodrive; every stretch with the car's middle
## more than 0.8 m off any road's asphalt (cut a corner onto the pavement or the grass), with
## what it was doing -- speed, how far from a junction, how sharp the plan turns there -- and
## how long it then stood against something. Good: none, or a few short ones at slow speed.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
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
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	g._set_auto(true)
	var t := 0.0
	var off := 0.0
	var off_total := 0.0
	var events := 0
	var still := 0.0
	var longest_still := 0.0
	var shots := 0
	var odo0: float = g._odo
	while t < 150.0:
		await physics_frame
		t += Engine.time_scale / Engine.physics_ticks_per_second
		var on: Dictionary = g._nearest_seg(g._pos, 30.0, true, true)
		var edge: float = float(on["edge"]) if not on.is_empty() else 99.0
		if edge > 0.8:
			if off == 0.0:
				events += 1
				# what the plan does here: its turn over the next 15 m, the nearest junction
				var turn := 0.0
				if g._ap_pts.size() > 3:
					var a: Vector2 = g._ap_pts[0]
					var b: Vector2 = g._ap_pts[mini(2, g._ap_pts.size() - 1)]
					var c: Vector2 = g._ap_point_ahead(15.0)
					turn = rad_to_deg((b - a).angle_to(c - b))
				var jd := INF
				for code: int in g._near(g._seg_hash, g._pos, 30.0, g.SEG_CELL):
					var r: Dictionary = g._roads[code / 4096]
					var ids: PackedInt32Array = r["ids"]
					for k in [code % 4096, code % 4096 + 1]:
						if g._node_ways(ids[k]) >= 3:
							jd = minf(jd, g._nodes[ids[k]].distance_to(g._pos))
				print("  off the road at %.0f s: %.1f m off, %.1f m/s, junction %.0f m away, plan turns %.0f deg, plan %.1f m from the car, backing %s" % [
					t, edge, g._v, jd, turn, g._ap_off_route(), g._ap_back > 0.0])
				if shots < 2 and OS.get_environment("OUT") != "":
					shots += 1
					await _snap("offroad_%d" % shots)
			off += Engine.time_scale / Engine.physics_ticks_per_second
			off_total += Engine.time_scale / Engine.physics_ticks_per_second
		else:
			off = 0.0
		if absf(g._v) < 0.3 and g._ap_light_v() > 0.5:
			still += Engine.time_scale / Engine.physics_ticks_per_second
			longest_still = maxf(longest_still, still)
		else:
			still = 0.0
	print("150 s: %.0f m driven, off the asphalt %d times, %.1f s in all; longest standstill (not at a light) %.0f s" % [g._odo - odo0, events, off_total, longest_still])
	quit(0)
