extends SceneTree
## Around a roundabout (RING="x,z", else the one nearest the start): the car on autodrive
## from 60 m off (OFFX, OFFZ); traffic round it.
## The longest any car stays on a ring, the autodrive's, crossing collisions and stalls
## within 40 m of it.
var g: Node
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
	var ring := Vector2.INF
	if OS.get_environment("RING") != "":
		var f := OS.get_environment("RING").split(",")
		ring = Vector2(float(f[0]), float(f[1]))
	else:   # the roundabout nearest the start
		var best := INF
		for r: Dictionary in g._roads:
			if r.get("ring", false):
				var c := Vector2.ZERO
				for q: Vector2 in r["pts"]:
					c += q
				c /= float((r["pts"] as PackedVector2Array).size())
				if c.distance_to(g._pos) < best:
					best = c.distance_to(g._pos)
					ring = c
	print("roundabout at ", Vector2i(ring))
	var off := Vector2(float(OS.get_environment("OFFX")), float(OS.get_environment("OFFZ")))
	if off == Vector2.ZERO:
		off = Vector2(60, 0)
	g._land_on_road(ring + off, 60.0, ring)
	g._set_auto(true)
	var T = g._traffic
	var on_ring := {}
	var max_ring := 0.0
	var me_ring := 0.0
	var me_max := 0.0
	var hits := 0
	var stall := {}
	var stalls := 0
	var seen := {}
	var t := 0.0
	var dt := 1.0 / 60.0
	var near_time := 0.0
	while t < 75.0:
		await physics_frame
		t += dt
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive:
				continue
			var rr: Dictionary = g._roads[c.rd[mini(c.k, c.rd.size() - 1)]]
			if rr.get("ring", false):
				on_ring[i] = float(on_ring.get(i, 0.0)) + dt
				max_ring = maxf(max_ring, on_ring[i])
			else:
				on_ring[i] = 0.0
			if c.pos.distance_to(ring) < 40.0:
				near_time += dt
				if c.v < 0.3:
					stall[i] = float(stall.get(i, 0.0)) + dt
					if absf(stall[i] - 12.0) < dt * 0.6:
						stalls += 1
				else:
					stall[i] = 0.0
				for k in range(i + 1, T.cars.size()):
					var o = T.cars[k]
					if o.alive and o.pos.distance_to(c.pos) < 2.4 and absf(angle_difference(o.yaw, c.yaw)) > 0.6:
						var key := "%d-%d" % [i, k]
						if not seen.has(key) or t - float(seen[key]) > 3.0:
							hits += 1
						seen[key] = t
		var hit: Dictionary = g._nearest_seg(g._pos, 6.0, true, true)
		if not hit.is_empty() and (g._roads[hit["road"]] as Dictionary).get("ring", false):
			me_ring += dt
			me_max = maxf(me_max, me_ring)
		else:
			me_ring = 0.0
	print("75 s near the ring: traffic there %.0f car-s; longest on a ring %.1f s; autodrive's longest on it %.1f s; crossing touches %d; stalls over 12 s %d; autodrive now %.0f m away" % [near_time, max_ring, me_max, hits, stalls, g._pos.distance_to(ring)])
	quit(0)
