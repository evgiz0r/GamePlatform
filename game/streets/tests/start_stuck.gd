extends SceneTree
## The first minute or two of a level as the player starts it, autodrive on: does the car get
## stuck? Evgeni, 24 Nov 2026, the Tel Aviv ambulance run: "the ambulance autodrive just got
## stuck in these poles for a minute" -- on Kaplan's pavement among the railings, just after
## the start (the town still building round it). Loads LEVEL as the game does (set
## STREETS_BUILD_ALL=0 to build round the start first, as a player sees it), switches autodrive
## on at once, and for SECS (default 90) prints every 2 s where the car is, its speed, what held
## it (_ap_why), whether it is on a road's asphalt, and every hit; then a summary of standing
## time and seconds off the asphalt. LEVEL 25 is the Tel Aviv ambulance run.
##   LEVEL=25 STREETS_BUILD_ALL=0 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/start_stuck.gd
## Good: off the asphalt 0 s, no standing 10 s+ but at lights.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 25})
	while g == null or not g._loaded:
		await create_timer(0.1).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	print("start at (%.1f, %.1f) on %s, heading (%.2f, %.2f), on asphalt %s" % [g._pos.x, g._pos.y, g._on_name, g._fwd().x, g._fwd().y, str(_on_asphalt())])
	if not g._auto:
		g._set_auto(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	var t := 0.0
	var next := 0.0
	var off := 0.0
	var stand := 0.0
	var worst_stand := 0.0
	var last_hit: String = g._last_hit
	while t < secs:
		await physics_frame
		var dt: float = Engine.time_scale / Engine.physics_ticks_per_second
		t += dt
		var on := _on_asphalt()
		if not on:
			off += dt
		if absf(g._v) < 0.3:
			stand += dt
			worst_stand = maxf(worst_stand, stand)
		else:
			stand = 0.0
		var h: String = g._last_hit
		if h != last_hit and h != "" and g._crash_cool > 0.35:
			print("HIT t %.1f %s at (%.1f, %.1f) %.0f km/h" % [t, h, g._pos.x, g._pos.y, absf(g._v) * 3.6])
		last_hit = h
		if OS.get_environment("TRACE") != "" and t < float(OS.get_environment("TRACE")) and fmod(t, 0.5) < dt:
			var pl: Array = []
			for q in (g._ap_pts as PackedVector2Array).slice(0, 8):
				pl.append("(%.0f,%.0f)" % [q.x, q.y])
			print("    trace t %.1f (%.1f, %.1f) v %.1f dest %s kt %s plan %s" % [t, g._pos.x, g._pos.y, g._v, str(g._dest_on), str(not g._ap_kt.is_empty()), " ".join(pl)])
		if t >= next:
			next += 2.0
			print("  t %4.0f (%.1f, %.1f) %s %3.0f km/h held by %-8s %s%s" % [t, g._pos.x, g._pos.y, g._on_name, g._v * 3.6, g._ap_why,
				"" if on else "OFF THE ASPHALT ", ("turning round " if not g._ap_kt.is_empty() else "")])
	print("START STUCK: %.0f s off the asphalt, longest standing %.0f s, %.0f m driven in %.0f s; knocked or through %d things, railing panels down %d" % [
		off, worst_stand, g._odo, secs, g._knocked_n, (g._rails_down as Array).size() if "_rails_down" in g else -1])
	if OS.get_environment("OUT") != "" and "_rails_down" in g and not (g._rails_down as Array).is_empty():
		# a look back at the first broken panel, from 8 m off and 3 m up
		var gp: Vector4 = (g._rails_down[0] as Dictionary)["gone"]
		var mid := Vector2((gp.x + gp.z) * 0.5, (gp.y + gp.w) * 0.5)
		g._set_auto(false)
		g._v = 0.0
		g._pos = mid + Vector2(-8.0, 6.0)
		for k in range(30):
			await process_frame
		var cam: Camera3D = root.get_viewport().get_camera_3d()
		cam.global_position = Vector3(mid.x - 7.0, float(g._h(mid)) + 3.0, mid.y + 5.0)
		cam.look_at(Vector3(mid.x, float(g._h(mid)) + 0.4, mid.y))
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/rail_down.png")
	quit(0)

## the car's middle within a drivable road's asphalt (its width), by the nearest segment
func _on_asphalt() -> bool:
	var hit: Dictionary = g._nearest_seg(g._pos, 12.0, true, true, g._y)
	if hit.is_empty():
		return false
	var r: Dictionary = g._roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var cp := Geometry2D.get_closest_point_to_segment(g._pos, pts[sj], pts[sj + 1])
	return cp.distance_to(g._pos) <= float(r["w"]) * 0.5 + 0.3
