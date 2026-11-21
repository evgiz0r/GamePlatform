extends SceneTree
## Traffic that moves further in one of its ticks than it drives: autodrive round the start
## for SECS (default 120) and, every traffic tick, any car within 80 m whose middle moved more
## than its speed allows (1.5x + 0.3 m), with what it was doing. people_pops counts these as
## "cars popping"; this says which and why. STREETS_WORLD_SPLIT=0 ticks the traffic every
## physics tick (as before 21 Nov) for a side by side.
##   LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/traffic_jumps.gd
var g: Node
func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var T = g._traffic
	g._set_auto(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 120.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t := 0.0
	var was := {}
	var tick_was: int = T._tick_n
	var since := 0.0
	var jumps := 0
	var shown := 0
	var by_kind := {}
	while t < secs:
		await physics_frame
		t += dt
		since += dt
		if T._tick_n == tick_was:
			continue
		tick_was = T._tick_n
		var tdt := since
		since = 0.0
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive or c.pos.distance_to(g._pos) > 80.0:
				was.erase(i)
				continue
			if was.has(i):
				var w: Array = was[i]
				var d: float = (w[0] as Vector2).distance_to(c.pos)
				if d > absf(c.v) * tdt * 1.5 + 0.3 and d < 30.0:
					jumps += 1
					by_kind[c.kind] = int(by_kind.get(c.kind, 0)) + 1
					if shown < 25:
						shown += 1
						print("%.1f s  %s %d moved %.2f m in %.3f s at v %.1f (was %.1f): shift %.2f -> %.2f (was %.2f), split %s, realign %s, s %.1f (was %.1f), k %d (was %d), why %s, stood %s, wait %.1f" % [
							t, c.kind, i, d, tdt, c.v, w[1], c.shift, c.shift_to, w[2], c.get("split"), c.realign, c.s, w[3], c.k, w[4], c.why, c.stood, c.wait])
			was[i] = [c.pos, c.v, c.shift, c.s, c.k]
	print("TRAFFIC JUMPS over %.0f s (split %s): %d %s" % [secs, g._world_split_on, jumps, str(by_kind)])
	quit(0)
