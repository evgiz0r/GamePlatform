extends SceneTree
## Traffic cars off the road: does any traffic car's middle stray beyond every drivable road's
## edge? (A day in Givatayim's preview, 24 Nov 2026: a white car on a grass median beside a
## bus, on Ze'ev Jabotinsky.) The player's car has this check in scenario.gd (off_fast); this is
## the same rule for everyone else. Loads LEVEL (1, Givatayim), lets traffic run SECS (120) s
## with your car parked out of the way, and every 0.5 s looks at each moving traffic car: its
## middle more than OFF_M (0.4) past the nearest drivable road's edge (at its own height) counts.
## Prints each car's worst stretch (where, which road it was on, how far out, how long) and a
## REGRESS line.
##   LEVEL=1 SECS=120 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/traffic_on_road.gd
## Good: 0 cars off.
var g: Node
const OFF_M := 0.4

func _initialize() -> void:
	_run()

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
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 120.0
	var T = g._traffic
	var t := 0.0
	var next := 0.0
	var worst := {}   # car index -> [out m, pos, road name, samples, kind]
	var looks := 0
	while t < secs:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		g._v = 0.0
		if t < next:
			continue
		next = t + 0.5
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive or c.v < 1.0:
				continue
			looks += 1
			var hit: Dictionary = g._nearest_seg(c.pos, 15.0, true, false, c.y)
			var out := 99.0 if hit.is_empty() else float(hit["edge"])
			if out > OFF_M:
				var nm := ""
				if c.rd.size() > 0:
					nm = String(g._roads[c.rd[mini(c.k, c.rd.size() - 1)]].get("name", ""))
				if not worst.has(i):
					worst[i] = [out, c.pos, nm, 0, c.kind]
				worst[i][3] += 1
				if out > float(worst[i][0]):
					worst[i][0] = out
					worst[i][1] = c.pos
					worst[i][2] = nm
	for i: int in worst.keys():
		var w: Array = worst[i]
		print("OFF ROAD car %d (%s) on %s: %.1f m past the edge at (%.1f, %.1f), %.1f s of it" % [i, w[4], w[2], w[0], w[1].x, w[1].y, w[3] * 0.5])
	print("REGRESS traffic_on_road: %s -- traffic cars' middles on a drivable road, %d looks over %.0f s: %d cars off by over %.1f m (the bug: a car on Jabotinsky's grass median, A day in Givatayim)" % [
		"PASS" if worst.is_empty() else "FAIL", looks, secs, worst.size(), OFF_M])
	quit(0)
