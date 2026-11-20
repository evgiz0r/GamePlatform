extends SceneTree
## A traffic car that wants to go and does not: autodrive drives (traffic about) for SECS game
## seconds, every car's state is kept tick by tick, and when a car has stood STUCK_S seconds
## while its last decision wanted it moving (want > 0.5 m/s), its last two seconds are
## printed -- what it wanted and why, its moment to react, the car in front, a hit, where it
## is on its path -- so the reason shows itself. Five cases at most, then the count.
##
##   LEVEL=4 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/traffic_stuck.gd
##
## Found by the exam's "held by nothing" check (November 2026): in the test town a scooter
## wanting 8 m/s stood 28 s, in view, 15 m from the player.
var g: Node
var T

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	g._set_auto(true)
	T = g._traffic
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 150.0
	var stuck_s := float(OS.get_environment("STUCK_S")) if OS.get_environment("STUCK_S") != "" else 6.0
	var hist := {}       # car -> Array of samples, the last ~2.5 s
	var stood := {}      # car -> seconds standing while wanting to go
	var done := {}       # car -> true once printed (until it moves again)
	var last := {}       # car -> where it was (a jump: put down elsewhere, a new car)
	var cases := 0
	var t := 0.0
	while t < secs:
		await physics_frame
		var dt: float = Engine.time_scale / Engine.physics_ticks_per_second
		t += dt
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive:
				hist.erase(i)
				stood.erase(i)
				done.erase(i)
				continue
			if last.has(i) and (last[i] as Vector2).distance_to(c.pos) > 15.0:
				hist.erase(i)
				stood.erase(i)
				done.erase(i)
			last[i] = c.pos
			var h: Array = hist.get(i, [])
			h.append([snappedf(t, 0.01), snappedf(c.v, 0.01), snappedf(c.want, 0.01), c.why, snappedf(c.react_t, 0.01),
				snappedf(c.react, 0.01), snappedf(c.lead_v, 0.01), c.blocker, snappedf(c.hit, 0.01), snappedf(c.acc, 0.01),
				snappedf(c.cum[c.cum.size() - 1] - c.s, 0.1), c.holding, snappedf(c.jwait, 0.1)])
			if h.size() > 150:
				h.remove_at(0)
			hist[i] = h
			if c.v < 0.3 and c.want > 0.5:
				stood[i] = float(stood.get(i, 0.0)) + dt
			elif c.v >= 0.3:
				stood.erase(i)
				done.erase(i)
			if float(stood.get(i, 0.0)) >= stuck_s and not done.has(i):
				done[i] = true
				cases += 1
				if cases <= 5:
					print("STUCK car %d (%s) at %s, %.0f m from the player, %s; stood %.1f s wanting to go. Last 2 s:" % [
						i, c.kind, Vector2i(c.pos), c.pos.distance_to(g._pos), "in view" if T._in_view(c.pos) else "out of view", stood[i]])
					print("    t      v    want  why          react_t/react  lead_v  blocker  hit   acc   left on path  holding  jwait")
					for k in range(0, h.size(), 12):
						var e: Array = h[k]
						print("    %-6s %-5s %-5s %-12s %5s / %-5s  %-6s  %-7s  %-4s  %-5s %-12s  %-7s  %s" % e)
	print("TRAFFIC STUCK: %d cars stood %.0f s+ wanting to go, in %.0f s" % [cases, stuck_s, secs])
	quit(0)
