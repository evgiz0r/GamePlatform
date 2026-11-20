extends SceneTree
## A queue at a red light pulling away when it turns green: watches one signalled junction
## (KNOT_AT="x,z", LEVEL; default the big one on Sderot Herzl in Ashdod) for SECS seconds
## and, each time a queue standing at its red (a car held by the light, the car held up by
## it, and so on) gets the green, records every one's speed for the next 12 s. Prints a
## line per car and writes $OUT/queue_start.json for
## queue_start_chart.py: speed against time, one line per car in queue order -- a queue
## that pulls away car after car, not all at once on the same tick like a train.
var g: Node
var T

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 3})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	T = g._traffic
	var xz := (OS.get_environment("KNOT_AT") if OS.get_environment("KNOT_AT") != "" else "-1820,2354").split(",")
	var at := Vector2(float(xz[0]), float(xz[1]))
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 150.0
	for ang in range(0, 360, 30):
		var q := at + Vector2.from_angle(deg_to_rad(ang)) * 110.0
		if g._land_on_road(q, 30.0, Vector2.ZERO) and g._pos.distance_to(at) > 80.0:
			break
	g._set_auto(false)
	var t := 0.0
	var dt := 1.0 / 60.0
	var last_phase: int = g._sig_phase
	var runs: Array = []      # each: {"t0", "cars": [[queue position, kind, [speeds every 0.1 s]]]}
	var open: Array = []      # runs still recording: [run, [car indices], start t]
	while t < secs:
		await physics_frame
		t += dt
		g._v = 0.0
		if g._sig_phase != last_phase:
			last_phase = g._sig_phase
			var step: Array = g.SIGNAL_CYCLE[g._sig_phase]
			if "g" in step:
				# real queues: a car standing at the red (held by the light), then the car
				# held up by it, and the one held up by that... (cars standing at the fronts
				# of different lanes of the same junction all go together, rightly: they are
				# not a queue -- the first version took them for one)
				var fronts: Array = []
				for i in range(T.cars.size()):
					var c = T.cars[i]
					if c.alive and c.v < 0.3 and c.why == "light" and c.pos.distance_to(at) < 70.0 \
							and T._light_ahead(c) == INF:   # (its own light the one gone green)
						fronts.append(i)
				for f: int in fronts:
					var chain: Array = [f]
					var grew := true
					while grew and chain.size() < 8:
						grew = false
						for i in range(T.cars.size()):
							var c = T.cars[i]
							if c.alive and c.v < 0.3 and c.blocker == chain[chain.size() - 1] and not chain.has(i):
								chain.append(i)
								grew = true
								break
					if chain.size() < 2:
						continue
					var run := {"t0": t, "cars": []}
					for qi in range(chain.size()):
						run["cars"].append([qi + 1, T.cars[chain[qi]].kind, []])
					runs.append(run)
					open.append([run, chain, t])
		# record 10 times a second
		if int(t * 60.0) % 6 == 0:
			for o: Array in open:
				var run: Dictionary = o[0]
				for k in range((o[1] as Array).size()):
					var c = T.cars[o[1][k]]
					(run["cars"][k][2] as Array).append(snappedf(c.v * 3.6, 0.1) if c.alive else -1.0)
		open = open.filter(func(o): return t - float(o[2]) < 12.0)
	for run: Dictionary in runs:
		print("GREEN at %.0f s: %d cars in the queue" % [run["t0"], run["cars"].size()])
		for c: Array in run["cars"]:
			var sp: Array = c[2]
			var moved := -1.0
			for k in range(sp.size()):
				if float(sp[k]) > 1.0:
					moved = k * 0.1
					break
			print("  car %d (%s): moving after %s, %.0f km/h after 6 s" % [c[0], c[1],
				"%.1f s" % moved if moved >= 0.0 else "--", float(sp[mini(60, sp.size() - 1)]) if sp.size() > 0 else 0.0])
	if OS.get_environment("OUT") != "":
		var f := FileAccess.open(OS.get_environment("OUT") + "/queue_start.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"city": g._city_name, "runs": runs}))
	print("QUEUES: %d recorded" % runs.size())
	quit(0)
