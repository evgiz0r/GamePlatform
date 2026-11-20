extends SceneTree
## A queue at a red light pulling away when it turns green: watches one signalled junction
## (KNOT_AT="x,z", LEVEL; default the big one on Sderot Herzl in Ashdod) for SECS seconds
## and, each time a queue standing at its red (a car held by the light, the car held up by
## it, and so on) gets the green, records every one's speed for the next 12 s. Prints a
## line per car and writes $OUT/queue_start.json for
## queue_start_chart.py: speed against time, one line per car in queue order -- a queue
## that pulls away car after car, not all at once on the same tick like a train.
##
## Judged against how real queues go (QUEUE CHECK at the end, PASS or FAIL): a driver starts
## roughly a second after the car in front moves off, and once a queue is moving its cars
## cross the stop line about 2 s apart -- the first few slower: about 3.8, 3.1, 2.7, 2.4,
## 2.2 s, then 2.0-2.1 (Greenshields' 1947 counts at signals; the Highway Capacity Manual's
## base of 1900 cars an hour a lane is 1.9 s). The bands below are wide on purpose -- this
## watches a few queues of mixed drivers -- and still catch both mistakes made tuning this
## by eye: a queue that went within 0.3 s of each other (a train), then one whose third car
## moved 9 s after the green.
const START_GAP := [0.6, 2.5]     ## s between one car moving off and the next (each)
const START_MED := [0.8, 2.0]     ## ...their median
const LINE_GAP := [1.4, 4.5]      ## s between cars crossing the stop line (each)
const LINE_MED := [1.7, 3.3]      ## ...their median
const FIRST := [1.0, 5.5]         ## s from the green to the first car's front over the line
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
	var open: Array = []      # runs still recording: [run, [car indices], start t, line point, its way]
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
					var run := {"t0": t, "cars": [], "cross": []}
					for qi in range(chain.size()):
						run["cars"].append([qi + 1, T.cars[chain[qi]].kind, []])
						run["cross"].append(-1.0)
					runs.append(run)
					# the stop line: a metre past the first car's front (it stops that short)
					var c0 = T.cars[chain[0]]
					var d0 := Vector2(sin(c0.yaw), cos(c0.yaw))
					open.append([run, chain, t, c0.pos + d0 * (c0.len * 0.5 + 1.0), d0])
		# each car's front over the line: every tick
		for o: Array in open:
			for k in range((o[1] as Array).size()):
				var c = T.cars[o[1][k]]
				if c.alive and float(o[0]["cross"][k]) < 0.0 \
						and (c.pos + Vector2(sin(c.yaw), cos(c.yaw)) * c.len * 0.5 - (o[3] as Vector2)).dot(o[4]) > 0.0:
					o[0]["cross"][k] = snappedf(t - float(o[2]), 0.01)
		# record 10 times a second
		if int(t * 60.0) % 6 == 0:
			for o: Array in open:
				var run: Dictionary = o[0]
				for k in range((o[1] as Array).size()):
					var c = T.cars[o[1][k]]
					(run["cars"][k][2] as Array).append(snappedf(c.v * 3.6, 0.1) if c.alive else -1.0)
		open = open.filter(func(o): return t - float(o[2]) < 12.0)
	var start_gaps: Array = []
	var line_gaps: Array = []
	var firsts: Array = []
	for run: Dictionary in runs:
		print("GREEN at %.0f s: %d cars in the queue" % [run["t0"], run["cars"].size()])
		var last_moved := -1.0
		var last_cross := -1.0
		for qi in range((run["cars"] as Array).size()):
			var c: Array = run["cars"][qi]
			var sp: Array = c[2]
			var moved := -1.0
			for k in range(sp.size()):
				if float(sp[k]) > 1.0:
					moved = k * 0.1
					break
			var cross: float = run["cross"][qi]
			print("  car %d (%s): moving after %s, over the line after %s, %.0f km/h after 6 s" % [c[0], c[1],
				"%.1f s" % moved if moved >= 0.0 else "--", "%.1f s" % cross if cross >= 0.0 else "--",
				float(sp[mini(60, sp.size() - 1)]) if sp.size() > 0 else 0.0])
			# (a gap only between two cars that both did it within the 12 s watched)
			if qi == 0 and cross >= 0.0:
				firsts.append(cross)
			if qi > 0 and moved >= 0.0 and last_moved >= 0.0:
				start_gaps.append(moved - last_moved)
			if qi > 0 and cross >= 0.0 and last_cross >= 0.0:
				line_gaps.append(cross - last_cross)
			last_moved = moved
			last_cross = cross
	if OS.get_environment("OUT") != "":
		var f := FileAccess.open(OS.get_environment("OUT") + "/queue_start.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"city": g._city_name, "runs": runs}))
	print("QUEUES: %d recorded" % runs.size())
	var verdict := []
	verdict.append(_band("start gaps", start_gaps, START_GAP, START_MED))
	verdict.append(_band("line gaps", line_gaps, LINE_GAP, LINE_MED))
	verdict.append(_band("first car over the line", firsts, FIRST, FIRST))
	var ok := not verdict.has(false) and not start_gaps.is_empty() and not line_gaps.is_empty()
	print("QUEUE CHECK: %s" % ("PASS" if ok else ("FAIL" if not start_gaps.is_empty() else "NO QUEUES (watch longer, or another junction)")))
	quit(0)

## one measure against its bands: each in [lo, hi], the median in [mlo, mhi]; prints it
func _band(what: String, xs: Array, each: Array, med: Array) -> bool:
	if xs.is_empty():
		print("  %-24s none measured" % what)
		return true
	var s := xs.duplicate()
	s.sort()
	var m: float = s[s.size() / 2]
	var outside := s.filter(func(x): return x < each[0] or x > each[1]).size()
	# a few out of the band are drivers being drivers; a third of them is the model
	var ok: bool = m >= med[0] and m <= med[1] and outside * 3 <= s.size()
	print("  %-24s median %.1f s (good %.1f-%.1f), %d of %d outside %.1f-%.1f s, range %.1f-%.1f: %s" % [
		what, m, med[0], med[1], outside, s.size(), each[0], each[1], s[0], s[s.size() - 1], "ok" if ok else "OFF"])
	return ok
