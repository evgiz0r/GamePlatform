extends SceneTree
## Racer on a real drive, in live traffic (the user, 22 Nov, from Givatayim's start on
## Katznelson to Rambam, 1.3 km: "the racer is really passive ... there was only a bus and it
## didnt want to pass ... waiting in traffic"). Level LEVEL (1) as it starts, racer on, to the
## street TO (default Rambam), one line a second: where, how fast, what held it, the car in
## front. Then how long it took, the time it stood (under 1 m/s) and why.
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/racer_drive.gd
## PASS: there within SECS (150), standing under a quarter of the time, no crash.
var g: Node

func _initialize() -> void:
	_run()

func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(_env("LEVEL", "1"))
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_quality(0)
	var to := _env("TO", "רמב\"ם")
	var want := float(_env("DIST", "1300"))
	var best := Vector2.INF
	var bd := INF
	for r: Dictionary in g._roads:
		if not String(r["name"]).contains(to) or not r["drive"]:
			continue
		for p: Vector2 in r["pts"]:
			var d := absf(p.distance_to(g._pos) - want)
			if d < bd:
				bd = d
				best = p
	if best == Vector2.INF:
		print("RACER_DRIVE: FAIL (no street %s)" % to)
		quit(1)
		return
	print("RACER_DRIVE to %s at %s, %.0f m as the crow flies" % [to, best, best.distance_to(g._pos)])
	g._set_racer(true)
	g._ap_style = "racer"
	g._set_dest(best, to)
	var secs := float(_env("SECS", "150"))
	g._race_by_why = ""
	var t := 0.0
	var stood := 0.0
	var why := {}
	var crashes := 0
	var next := 0.0
	var probe = root.get_node("Probe")
	var e0: int = probe._events.size()
	var e_seen := e0
	while t < secs:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		if absf(float(g._v)) < 1.0:
			stood += dt
			why[g._ap_why] = float(why.get(g._ap_why, 0.0)) + dt
		while e_seen < probe._events.size():
			var ev: Dictionary = probe._events[e_seen]
			e_seen += 1
			var k := String(ev["kind"])
			if k.begins_with("racer_") or k.begins_with("pass_") or k == "crash":
				print("    event %5.1f s  %s %s" % [t, k, JSON.stringify(ev["data"])])
		if t >= next:
			next += 1.0
			var hit: Dictionary = g._nearest_seg(g._pos, 12.0, true)
			var rn := String(g._roads[int(hit["road"])]["name"]) if not hit.is_empty() else "?"
			var lk := ""
			if int(g._ap_lead_i) >= 0:
				var c = g._traffic.cars[int(g._ap_lead_i)]
				lk = "%s v=%.1f" % [c.kind, float(c.v)]
			print("  %5.1f s  %5.1f km/h  %-10s lead %5.1f m %-14s  %s  to go %.0f m" % [t, float(g._v) * 3.6,
				g._ap_why, float(g._ap_lead), lk, rn, g._pos.distance_to(best)])
			if lk != "" and (absf(float(g._v)) < 1.0 or OS.get_environment("VERBOSE") != ""):
				print("           by: %s | queue: %s" % [g._race_by_why, g._race_q_why])
		if g._pos.distance_to(best) < 25.0 or not g._dest_on:
			break
	var there: bool = g._pos.distance_to(best) < 40.0 or not g._dest_on
	for i in range(e0, probe._events.size()):
		if String(probe._events[i]["kind"]) == "crash":
			crashes += 1
			print("  crash: %s" % JSON.stringify(probe._events[i]["data"]))
	print("RACER_DRIVE %s in %.0f s, stood %.0f s (%.0f%%), why: %s, crashes %d" % ["there" if there else "NOT there",
		t, stood, 100.0 * stood / maxf(t, 1.0), JSON.stringify(why), crashes])
	print("RACER_DRIVE: %s" % ("PASS" if there and stood < t * 0.25 and crashes == 0 else "FAIL"))
	quit(0)
