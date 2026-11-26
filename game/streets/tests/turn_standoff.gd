extends SceneTree
## Autodrive turning into a side street while a car comes out of it: does either get through?
## Route 9 in Bedford (26 Nov 2026) stood 230 s at Hammonds Plains Road / Giles Drive: turning
## left into Giles, autodrive waited for a sedan nosing out of it, and the sedan waited for
## autodrive -- then the next car out did the same. The user: "always stuck there".
## Autodrive is put FROM_M before the junction on the main road, sent DEST along the side
## street; one traffic car is sent along the side street towards the junction, a different
## head start each case. Per case: seconds to get DEST_OK m into the side street, the longest
## both stood face to face, hits.
##   LEVEL=2 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/turn_standoff.gd
## (TS_FROM, TS_JUNC, TS_DEST, TS_OUT as "x,z" override the Bedford spot.)
## PASS: every case in under 30 s with no hit.
var g: Node
var T

func _initialize() -> void:
	_run()

func _v2(name: String, dflt: Vector2) -> Vector2:
	var s := OS.get_environment(name)
	if s == "":
		return dflt
	var xz := s.split(",")
	return Vector2(float(xz[0]), float(xz[1]))

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
	T = g._traffic
	var junc := _v2("TS_JUNC", Vector2(-2613.5, -692.2))
	var from := _v2("TS_FROM", Vector2(-2560.0, -686.0))
	var dest := _v2("TS_DEST", Vector2(-2652.0, -739.0))
	var out := _v2("TS_OUT", Vector2(-2636.0, -720.0))   # where the side street's car starts
	var side := (out - junc).normalized()
	var bad := 0
	var n := 0
	for head: float in [0.0, 6.0, 12.0, 18.0, 26.0]:
		n += 1
		for c in T.cars:
			c.alive = false
			c.retry = 1000.0
		g._set_auto(false)
		if not g._land_on_road(from, 10.0, (junc - from).normalized()):
			print("TURN STANDOFF: could not land at ", from)
			quit(1)
			return
		await physics_frame
		g._set_dest(dest, "turn test")
		g._set_auto(true)
		var dt := Engine.time_scale / Engine.physics_ticks_per_second
		var t := 0.0
		var sent = null
		var hits := 0
		var last_hit: String = g._last_hit
		var face := 0.0
		var face_max := 0.0
		var in_at := -1.0
		var why := {}
		while t < 60.0:
			await physics_frame
			t += dt
			var my_d: float = (g._pos as Vector2).distance_to(junc)
			if sent == null and my_d < 20.0 + head:
				if not T.send(junc + side * (8.0 + head * 0.8), -side):
					print("TURN STANDOFF: could not send a car")
					break
				for c in T.cars:
					if c.alive:
						sent = c
			if g._last_hit != last_hit and String(g._last_hit).begins_with("car"):
				hits += 1
				last_hit = g._last_hit
			if sent != null and sent.alive and absf(g._v) < 0.3 and sent.v < 0.3 and (sent.pos as Vector2).distance_to(g._pos) < 15.0:
				face += dt
				face_max = maxf(face_max, face)
				why[String(g._ap_why) + " / " + String(sent.why)] = true
			else:
				face = 0.0
			if (g._pos as Vector2 - junc).dot(side) > 18.0 and absf(((g._pos as Vector2) - junc).cross(side)) < 8.0:
				in_at = t
				break
		var ok := in_at >= 0.0 and in_at < 30.0 and hits == 0
		if not ok:
			bad += 1
		print("TURN STANDOFF case %d (side car %.0f m head start): %s in %.1f s, stood face to face %.1f s at most (%s), %d hits, at (%.0f, %.0f)" % [
			n, head, "through" if in_at >= 0.0 else "NOT through", in_at if in_at >= 0.0 else t, face_max, ", ".join(why.keys()), hits, g._pos.x, g._pos.y])
	print("REGRESS turn_standoff: %s -- autodrive turning into a side street a car comes out of: %d of %d cases stuck or hit (the bug: route 9, Bedford's Giles Drive, 230 s face to face)" % ["PASS" if bad == 0 else "FAIL", bad, n])
	quit(0)
