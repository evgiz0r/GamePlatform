extends SceneTree
## How the other cars move, as a vehicle would or not: autodrive round the start for SECS
## seconds (traffic about it), and for every traffic car every tick --
##   rear slip: how fast its rear axle moves sideways. A real car's rear wheels roll, they do
##     not slide: ~0. A body pivoting on its middle at a corner swings its back out sideways
##     (a bus by metres a second): that is the "jumping round" a player sees.
##   snaps: its heading turning faster than 1.5 rad/s while moving (a kink in its line).
## Per kind of vehicle, and the share of moving time with the rear sliding over 0.5 m/s.
## Saves the body outlines of the bus that turned most, every 0.25 s through its turn
## ($OUT/bus_turn.json), for bus_turn_chart.py.
var g: Node
var T

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
	await create_timer(1.0).timeout
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	T = g._traffic
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	g._set_auto(true)
	var dt := Engine.time_scale / Engine.physics_ticks_per_second
	var t := 0.0
	var prev := {}          # car -> [pos, yaw]
	var moving := {}        # kind -> seconds moving
	var sliding := {}       # kind -> seconds with the rear sliding > 0.5 m/s
	var worst := {}         # kind -> worst rear slip (m/s)
	var snaps := {}         # kind -> count of heading snaps
	var buses := {}         # car -> [[t, x, z, yaw, len], ...] every 0.25 s
	while t < secs:
		await physics_frame
		t += dt
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive:
				prev.erase(i)
				continue
			if prev.has(i):
				var p0: Vector2 = prev[i][0]
				var y0: float = prev[i][1]
				if p0.distance_to(c.pos) > 3.0:   # (sent elsewhere: a new start)
					prev[i] = [c.pos, c.yaw]
					continue
				var fwd := Vector2(sin(c.yaw), cos(c.yaw))
				var right := Vector2(fwd.y, -fwd.x)
				var wb := clampf(c.len * 0.6, 1.3, 7.0)
				var rate := angle_difference(y0, c.yaw) / dt
				# the rear axle's velocity: the middle's, plus the turn swinging the back round
				# it (a point a metres along the body moves a * rate sideways; d fwd/d yaw is
				# `right` in this file's way of turning)
				var vel: Vector2 = (c.pos - p0) / dt
				var rear_v := vel + right * (-wb * 0.5) * rate
				var slip := absf(rear_v.dot(right))
				var k: String = c.kind
				if c.v > 1.0:
					moving[k] = float(moving.get(k, 0.0)) + dt
					if slip > 0.5:
						sliding[k] = float(sliding.get(k, 0.0)) + dt
					worst[k] = maxf(float(worst.get(k, 0.0)), slip)
					if absf(rate) > 1.5:
						snaps[k] = int(snaps.get(k, 0)) + 1
						if int(snaps[k]) <= 3:
							print("  snap: %s at %.1f m/s turning %.1f rad/s, lane shift %.1f -> %.1f, held by %s, %.0f m from a junction" % [
								k, c.v, rate, c.shift, c.shift_to, c.why, _to_junction(c)])
				if c.kind == "bus" and int(t * 60.0) % 15 == 0:
					var arr: Array = buses.get(i, [])
					if not arr.is_empty() and Vector2(float(arr[arr.size() - 1][1]), float(arr[arr.size() - 1][2])).distance_to(c.pos) > 8.0:
						# (taken away and put back elsewhere: a new track, not a turn)
						if arr.size() > 4:
							buses["%d-%d" % [i, int(t)]] = arr
						arr = []
					arr.append([snappedf(t, 0.01), snappedf(c.pos.x, 0.01), snappedf(c.pos.y, 0.01), snappedf(c.yaw, 0.001), c.len])
					buses[i] = arr
			prev[i] = [c.pos, c.yaw]
	print("TRAFFIC MOTION over %.0f s:" % secs)
	var kinds := moving.keys()
	kinds.sort()
	for k in kinds:
		var mv: float = moving[k]
		print("  %-6s %5.0f s moving: rear sliding %4.1f%% of it, worst %.1f m/s, %d heading snaps" % [
			k, mv, 100.0 * float(sliding.get(k, 0.0)) / maxf(mv, 0.01), float(worst.get(k, 0.0)), int(snaps.get(k, 0))])
	# the bus that turned most within 10 s
	var best: Array = []
	var best_turn := 0.0
	for i in buses:
		var arr: Array = buses[i]
		for a in range(arr.size()):
			var turned := 0.0
			var b := a
			while b + 1 < arr.size() and float(arr[b + 1][0]) - float(arr[a][0]) < 10.0:
				turned += absf(angle_difference(float(arr[b][3]), float(arr[b + 1][3])))
				b += 1
			if turned > best_turn:
				best_turn = turned
				best = arr.slice(a, b + 1)
	print("  the bus that turned most: %.0f deg in %d samples" % [rad_to_deg(best_turn), best.size()])
	if OS.get_environment("OUT") != "" and not best.is_empty():
		var f := FileAccess.open(OS.get_environment("OUT") + "/bus_turn.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"city": g._city_id, "samples": best}))
	quit(0)

## metres from the car to the nearest junction point on its way
func _to_junction(c) -> float:
	var best := INF
	for j in range(c.k, mini(c.k + 12, c.pts.size())):
		var n: int = c.node[j]
		if n >= 0 and g._node_ways(n) >= 3:
			best = minf(best, g._nodes[n].distance_to(c.pos))
	return best
