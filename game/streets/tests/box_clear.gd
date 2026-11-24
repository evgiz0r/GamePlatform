extends SceneTree
## Your car clearing a big lit junction, a traffic car coming at it on its green (traffic.gd
## `_player_in_box`; route 2, 24 Nov 2026: autodrive held behind a car in the middle of
## Givatayim's Horodetsky across HaShalom -- two divided roads, lit at three corners -- went
## on through at 30 km/h, and an SUV up HaShalom on its new green at 39 km/h did not wait).
## Your car is driven by hand (held to the line, not by autodrive) from FROM to TO, through
## lit point AT, at KMH (25); the lights are held at the step that gives the cross street
## (coming from CROSS, toward AT) its green; a traffic car is sent from CROSS (on the cross street's carriageway toward AT, ~50 m out), and
## your car, standing at FROM (in the junction, as autodrive stood behind a car there), sets
## off (2.5 m/s^2 up to KMH) when it is LEAD m from AT. Once for each of LEADS (default
## 26,34,42: the two due at the lit point at about the same moment, the way route 2 had it). Prints the nearest the two came (body circles' gap), what the
## traffic car did, and a REGRESS line.
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/box_clear.gd
## Good: gap over 0 every time, the traffic car "held by junction" or behind.
var g: Node
var T

func _initialize() -> void:
	_run()

func _vec(env: String, def: Vector2) -> Vector2:
	var s := OS.get_environment(env)
	if s == "":
		return def
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1]))

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	g._set_auto(false)
	T = g._traffic
	var from := _vec("FROM", Vector2(-524.0, 763.0))
	var to := _vec("TO", Vector2(-560.0, 756.5))
	var at := _vec("AT", Vector2(-545.3, 758.7))
	var cross := _vec("CROSS", Vector2(-565.2, 714.4))
	var kmh := float(OS.get_environment("KMH")) if OS.get_environment("KMH") != "" else 25.0
	var leads: Array = []
	for s in (OS.get_environment("LEADS") if OS.get_environment("LEADS") != "" else "26,34,42").split(","):
		leads.append(float(s))
	# the lit point at AT, and the step of the cycle that gives the cross street its green
	var n := -1
	for k: int in g._sig_set.keys():
		if n < 0 or (g._nodes[k] as Vector2).distance_to(at) < (g._nodes[n] as Vector2).distance_to(at):
			n = k
	var cdir := (at - cross).normalized()
	var grp: int = g._light_group(n, cdir)
	var phase := -1
	for i in range(g.SIGNAL_CYCLE.size()):
		if String(g.SIGNAL_CYCLE[i][grp]) in ["g", "gf"]:
			phase = i
			break
	print("lit point %d at %s, the cross street's group %d, green at step %d" % [n, g._nodes[n], grp, phase])
	var dir := (to - from).normalized()
	var vmax := kmh / 3.6
	var worst := INF
	var bad := 0
	var runs := 0
	for lead: float in leads:
		for c in T.cars:
			c.alive = false
		var pos := from
		var v := 0.0
		var going := false
		g._pos = pos
		g._yaw = dir.angle()
		g._v = 0.0
		for k in range(5):
			await physics_frame
		T.send(cross, cdir)
		var sent = null
		for c in T.cars:
			if c.alive and (c.pos as Vector2).distance_to(cross) < 15.0:
				sent = c
		if sent == null:
			print("BOX CLEAR: the car was not sent")
			continue
		runs += 1
		if runs == 1:
			print("  sent: %s at %s, through the lit point: %s" % [sent.kind, sent.pos, str(Array(sent.node).has(n))])
		var near := INF
		var t := 0.0
		var cmax := 0.0
		var v_go := 0.0
		while t < 16.0 and (pos - from).dot(dir) < (to - from).length() and sent.alive:
			await physics_frame
			var dt := 1.0 / Engine.physics_ticks_per_second
			t += dt
			g._sig_phase = phase
			g._sig_t = 0.0
			if not going and (sent.pos as Vector2).distance_to(at) <= lead:
				going = true
				v_go = sent.v
			if going:
				v = minf(v + 2.5 * dt, vmax)
			pos += dir * v * dt
			g._pos = pos
			g._yaw = dir.angle()
			g._v = v
			g._v_lat = 0.0
			g._y = float(g._h(pos))
			cmax = maxf(cmax, sent.v)
			var sf := Vector2(sin(sent.yaw), cos(sent.yaw))
			var gap := INF
			for a2: float in [g.CAR_OFF, -g.CAR_OFF]:
				for b2: float in [-1.25, 0.0, 1.25]:
					gap = minf(gap, (pos + dir * a2).distance_to(sent.pos + sf * b2) - g.CAR_R - 0.95)
			if going:
				near = minf(near, gap)
		var what := "gone" if not sent.alive else "%s at %.1f km/h (top %.0f), held by %s, %.1f m from the lit point" % [
			sent.kind, sent.v * 3.6, cmax * 3.6, sent.why, (sent.pos as Vector2).distance_to(at)]
		print("BOX CLEAR your car off when the traffic car was %.0f m out at %.0f km/h: closest %.2f m; the traffic car now %s" % [lead, v_go * 3.6, near, what])
		worst = minf(worst, near)
		if near <= 0.0:
			bad += 1
	print("REGRESS box_clear: %s -- your car clearing a big lit junction at %.0f km/h, a car coming at it on its green %d times: met %d, closest %.2f m (good 0 met; the bug: an SUV at 39 km/h into autodrive, route 2)" % [
		"PASS" if bad == 0 and runs > 0 else "FAIL", kmh, runs, bad, worst])
	quit(0)
