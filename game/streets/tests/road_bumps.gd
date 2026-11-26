extends SceneTree
## How smooth the roads run along their length, and how level their junctions sit. A user
## (25 Nov 2026): "many roads seem broken, even in some of the test rides, the road is not
## flat and causes weird driving, and some intersections are weird". The ground is a height
## grid (a point every 8-46 m, from a surface model that sees rooftops); a road laid on it
## climbs in facets, its slope changing at every triangle's edge, and a junction's arms can
## meet at different heights. Along every drivable road on the ground (not a deck), every
## 2 m, the surface's height; counted:
##   kink  -- the slope over the next 6 m differs from the slope over the last 6 m by over
##            KINK (6%): a crest or a dip a car pitches over (a speed bump is about 10%)
## and at every junction of three or more drivable arms on the ground: the spread of the
## surface's height off a plane through the junction's disc (its radius + 3 m) -- "twisted"
## over TILT (0.15 m): its arms meet at different heights, a slope alone is fine. Prints the shares, the worst places (one per 40 m), and with OUT a shot of
## the worst few from behind a car's roof.
##   LEVEL=1 STREETS_BUILD_ALL=0 OUT=/tmp/bumps $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/road_bumps.gd
## (shots need a renderer: run it through tools/godot_bg.sh without --headless)
## REGRESS line: the kink share of road under KINK_OK and twisted junctions under TWIST_OK
## (Givatayim 25 Nov: 32% before, 22% after -- the 12 m grid's limit; a guard, not the goal).
var g: Node
const KINK := 0.06
const KINK_OK := 1.2   ## % of road: Givatayim 2.36 before the network levelling (25 Nov), 1.04 after
const TWIST_OK := 25.0
const TILT := 0.15   ## m: a junction's surface this far off flat (off a plane through it)

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "1")})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var total := 0.0
	var kinks := 0.0
	var worst: Array = []   # [how much, where, road name, dir, what]
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r.has("ys"):
			continue
		var pts: PackedVector2Array = r["pts"]
		var rids: PackedInt32Array = r["ids"]
		if Array(rids).any(func(q): return g._outside.has(q)):
			continue   # (past the map's edge: not drawn, not driven)
		var prof := PackedFloat32Array()
		var at := PackedVector2Array()
		var dirs := PackedVector2Array()
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.3:
				continue
			var d := (b - a) / L
			var s := 0.0
			while s < L:
				var c := a + d * s
				prof.append(float(g._h(c)))
				at.append(c)
				dirs.append(d)
				s += 2.0
		if prof.size() < 2:
			continue
		for i in range(prof.size()):
			total += 2.0
			if i >= 3 and i + 3 < prof.size():
				var k := absf((prof[i + 3] - prof[i]) / 6.0 - (prof[i] - prof[i - 3]) / 6.0)
				if k > KINK:
					kinks += 2.0
					worst.append([k, at[i], String(r["name"]), dirs[i], "kink"])
	# junctions: how level each one's disc sits
	var juncs := 0
	var tilted := 0
	var jworst: Array = []
	var arms := {}
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r.has("ys"):
			continue
		var ids: PackedInt32Array = r["ids"]
		for k in range(ids.size()):
			arms[ids[k]] = int(arms.get(ids[k], 0)) + (1 if k == 0 or k == ids.size() - 1 else 2)
	for ni: int in arms.keys():
		if int(arms[ni]) < 3 or g._outside.has(ni):
			continue
		juncs += 1
		var c: Vector2 = g._nodes[ni]
		var rad: float = float(g._node_r[ni]) + 3.0 if ni < g._node_r.size() else 8.0
		# (off a plane through it, not its slope: a junction on a 6% street is fine, one
		# whose arms come in at different heights is twisted)
		var ps: Array = []
		for q in range(12):
			for f: float in [0.0, 0.5, 1.0]:
				var p := c + Vector2.RIGHT.rotated(TAU * q / 12.0) * rad * f
				ps.append(Vector3(p.x - c.x, float(g._h(p)), p.y - c.y))
		# least squares y = a x + b z + e
		var sxx := 0.0; var szz := 0.0; var sxz := 0.0; var sx := 0.0; var sz := 0.0
		var sy := 0.0; var sxy := 0.0; var szy := 0.0
		for v: Vector3 in ps:
			sxx += v.x * v.x; szz += v.z * v.z; sxz += v.x * v.z; sx += v.x; sz += v.z
			sy += v.y; sxy += v.x * v.y; szy += v.z * v.y
		var n := float(ps.size())
		var m := Basis(Vector3(sxx, sxz, sx), Vector3(sxz, szz, sz), Vector3(sx, sz, n)).transposed()
		var sol := m.inverse() * Vector3(sxy, szy, sy)
		var dev := 0.0
		for v: Vector3 in ps:
			dev = maxf(dev, absf(v.y - (sol.x * v.x + sol.y * v.z + sol.z)))
		var tilt := dev
		if tilt > TILT:
			tilted += 1
			jworst.append([tilt, c, ni])
	worst.sort_custom(func(x, y): return x[0] > y[0])
	jworst.sort_custom(func(x, y): return x[0] > y[0])
	var kp := 100.0 * kinks / maxf(total, 1.0)
	var jp := 100.0 * tilted / maxf(float(juncs), 1.0)
	print("roads %.1f km: kinks (slope changing over %.0f%% in 6 m) %.0f m = %.2f%%" % [total / 1000.0, KINK * 100.0, kinks, kp])
	var seen: Array = []
	for w: Array in worst:
		if seen.any(func(q): return (q as Vector2).distance_to(w[1]) < 40.0):
			continue
		seen.append(w[1])
		print("  %s %.0f%% at %s on '%s'" % [w[4], float(w[0]) * 100.0, (w[1] as Vector2).round(), w[2]])
		if seen.size() >= 12:
			break
	print("junctions %d: twisted over %.2f m off a plane: %d = %.1f%%" % [juncs, TILT, tilted, jp])
	for w: Array in jworst.slice(0, 8):
		print("  junction %.2f m off flat at %s" % [float(w[0]), (w[1] as Vector2).round()])
	# SPOTS="x,z;x,z": shots there instead of at the worst (the same places before and after a fix)
	if OS.get_environment("SPOTS") != "":
		worst = []
		for sp: String in OS.get_environment("SPOTS").split(";"):
			var xz := sp.split(",")
			var p := Vector2(float(xz[0]), float(xz[1]))
			var hit: Dictionary = g._nearest_seg(p, 30.0, true)
			if hit.is_empty():
				continue
			var rr: Dictionary = g._roads[int(hit["road"])]
			var rp: PackedVector2Array = rr["pts"]
			var sj := int(hit["seg"]) if hit.has("seg") else 0
			worst.append([1.0, p, "", (rp[sj + 1] - rp[sj]).normalized(), "spot"])
	if OS.get_environment("OUT") != "" and not worst.is_empty():
		var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 3
		var done: Array = []
		for w: Array in worst:
			if done.size() >= shots:
				break
			if done.any(func(q): return (q as Vector2).distance_to(w[1]) < 40.0):
				continue
			done.append(w[1])
			var c: Vector2 = w[1]
			var d: Vector2 = w[3]
			g._land_on_road(c - d * 22.0, 15.0, d)
			await create_timer(2.0).timeout
			await _snap("bump_%d" % done.size())
	print("REGRESS road_bumps: %s -- roads smooth along their length: %.2f%% kinked over %.0f%% in 6 m (good under %.1f%%), %.1f%% of %d junctions twisted over %.2f m (good under %.0f%%)" % [
		"PASS" if kp < KINK_OK and jp < TWIST_OK else "FAIL", kp, KINK * 100.0, KINK_OK, jp, juncs, TILT, TWIST_OK])
	quit(0)
