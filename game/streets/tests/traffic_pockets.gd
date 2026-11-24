extends SceneTree
## Cars turning round in a cul-de-sac estate: a few streets that all only end, off a main
## street (g._pocket_ahead). Evgeni, 23 Nov 2026, Bedford's Meadowview Drive: "many cars just
## driving there turning around, causing traffic" -- traffic went into dead ends that had a
## driveway or a side street on the way (its old test stopped at the first point with three
## ways), turned round at the end and met the cars coming in; autodrive roaming had no test.
## Puts the player at AT (default Meadowview Drive, (760, -2040)), then for SECS game seconds
## (default 150) counts every traffic car within NEAR m (250) that turns round (its heading
## reversed within 4 s), and the car-seconds traffic spends standing there; with AUTO=1 the
## player roams on autodrive from AT instead of standing, and its own turn-rounds and seconds
## inside an estate count too. Also lists the estate streets within NEAR m.
##   LEVEL=2 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/traffic_pockets.gd
## Good: no more than a turn-round a minute near the player (a car that came from the end of
## a street), autodrive's own: none in a roam that starts outside an estate.
var g: Node
var T

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _xz(s: String) -> Vector2:
	var a := s.split(",")
	return Vector2(float(a[0]), float(a[1]))

## is the street segment nearest p in an estate (one of its two ways leads in, the other out)
func _in_pocket(p: Vector2) -> bool:
	if not g.has_method("_pocket_ahead"):
		return false   # (a build from before it: the counts still hold)
	var hit: Dictionary = g._nearest_seg(p, 12.0, true, true)
	if hit.is_empty():
		return false
	var ri: int = hit["road"]
	var sj: int = hit["seg"]
	var r: Dictionary = g._roads[ri]
	if r["k"] == "service" or r["pv"]:
		return false
	return g._pocket_ahead(ri, sj + 1, 1) or g._pocket_ahead(ri, sj, -1)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(_env("LEVEL", "2"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	T = g._traffic
	var at := _xz(_env("AT", "760,-2040"))
	var near := float(_env("NEAR", "250"))
	var secs := float(_env("SECS", "150"))
	var auto := _env("AUTO", "") != ""
	# the estates near: each street segment in one, by name
	var names := {}
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"] or r["k"] == "service" or not g.has_method("_pocket_ahead"):
			continue
		var p: PackedVector2Array = r["pts"]
		for sj in range(p.size() - 1):
			var m := (p[sj] + p[sj + 1]) * 0.5
			if m.distance_to(at) < near and (g._pocket_ahead(ri, sj + 1, 1) or g._pocket_ahead(ri, sj, -1)):
				names[r["name"] if r["name"] != "" else "(no name)"] = true
	print("estate streets within %.0f m: %s" % [near, ", ".join(names.keys())])
	g._land_on_road(at, 60.0, Vector2.ZERO)
	await physics_frame
	g._set_auto(auto)
	if not auto:
		g._v = 0.0
	var back := {}       # car -> [[t, heading], ...] over the last 4 s
	var cool := {}       # car -> t of its last counted turn-round
	var last := {}       # car -> where it was (a jump: a new car)
	var turns := 0
	var stood := 0.0
	var in_pocket_s := 0.0
	var my_turns := 0
	var my_back: Array = []
	var my_cool := -99.0
	var t := 0.0
	while t < secs:
		await physics_frame
		var dt: float = Engine.time_scale / Engine.physics_ticks_per_second
		t += dt
		var centre: Vector2 = g._pos if auto else at
		for i in range(T.cars.size()):
			var c = T.cars[i]
			if not c.alive or c.pos.distance_to(centre) > near:
				back.erase(i)
				continue
			if last.has(i) and (last[i] as Vector2).distance_to(c.pos) > 15.0:
				back.erase(i)
			last[i] = c.pos
			var hd := Vector2(sin(c.yaw), cos(c.yaw))
			var h: Array = back.get(i, [])
			h.append([t, hd])
			while float(h[0][0]) < t - 4.0:
				h.pop_front()
			back[i] = h
			if (h[0][1] as Vector2).dot(hd) < -0.8 and t - float(cool.get(i, -99.0)) > 8.0:
				cool[i] = t
				turns += 1
				if turns <= 12:
					print("TURN t %.0f car %d (%s) at (%.0f, %.0f) on %s%s" % [t, i, c.kind, c.pos.x, c.pos.y,
						g._street_name(c.pos) if g.has_method("_street_name") else "", "  (in an estate)" if _in_pocket(c.pos) else ""])
			if c.v < 0.3 and c.want > 0.5:
				stood += dt
		if auto:
			var f: Vector2 = g._fwd()
			my_back.append([t, f])
			while float(my_back[0][0]) < t - 4.0:
				my_back.pop_front()
			if (my_back[0][1] as Vector2).dot(f) < -0.8 and t - my_cool > 8.0:
				my_cool = t
				my_turns += 1
				print("AUTODRIVE TURN t %.0f at (%.0f, %.0f) on %s" % [t, g._pos.x, g._pos.y, g._on_name])
			if _in_pocket(g._pos):
				in_pocket_s += dt
	var line := "TRAFFIC POCKETS: %d traffic turn-rounds within %.0f m in %.0f s (%.1f a minute), %.0f car-seconds standing wanting to go" % [
		turns, near, secs, turns * 60.0 / secs, stood]
	if auto:
		line += "; autodrive turned round %d times, %.0f s of %.0f in an estate, %.0f m driven" % [my_turns, in_pocket_s, secs, g._odo]
	print(line)
	# (before the fix: 9.2 a minute here; after: 0.4-1.6)
	var per_min := turns * 60.0 / secs
	print("REGRESS traffic_pockets: %s -- traffic turning round within %.0f m of a cul-de-sac estate %.1f a minute (good under 4.5, it reads 0.4-2.5; the bug: 9.2)" % [
		"PASS" if per_min < 4.5 else "FAIL", near, per_min])
	quit(0)
