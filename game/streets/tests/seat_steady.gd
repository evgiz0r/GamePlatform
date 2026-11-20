extends SceneTree
## How steady the view from the driver's seat is: autodrive from the start for SECS seconds
## in the seat view, and the camera's heading against the car's every frame -- how far it
## looks off ahead (most, and on average), how fast it turns (on average, and the share of
## the time faster than 1 rad/s), and how often it swings back the other way. The look-round
## once whipped the seat view left and right with every small steering correction ("so
## chaotic, it jumps around, he looks at random locations"). Shots every 10 s ($OUT).
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

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
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 90.0
	g._set_cockpit(true)
	g._set_auto(true)
	var t := 0.0
	var last_rel := 0.0
	var last_dir := 0.0
	var most := 0.0
	var sum_abs := 0.0
	var sum_rate := 0.0
	var fast := 0.0
	var flips := 0
	var n := 0
	var next_shot := 10.0
	var phys: int = Engine.get_physics_frames()
	while t < secs:
		await process_frame
		# (game time since the last drawn frame: this machine draws a few frames a second, and
		# counting each as 1/60 s made the view's turning speed look ten times what it was; a
		# tick is time_scale / ticks a second of game time, the simulation sped up or not)
		var now: int = Engine.get_physics_frames()
		var dt := maxf(float(now - phys), 1.0) * Engine.time_scale / Engine.physics_ticks_per_second
		phys = now
		t += dt
		var cam: Camera3D = g.cam
		var f := -cam.global_transform.basis.z
		var view := atan2(f.z, f.x)
		var rel := angle_difference(float(g._view_yaw), view)   # + one way, - the other
		var rate := (rel - last_rel) / dt
		if n > 0:
			most = maxf(most, absf(rel))
			sum_abs += absf(rel)
			sum_rate += absf(rate)
			if absf(rate) > 1.0:
				fast += dt
			var dir := signf(rate) if absf(rate) > 0.3 else 0.0
			if dir != 0.0 and last_dir != 0.0 and dir != last_dir:
				flips += 1
			if dir != 0.0:
				last_dir = dir
		last_rel = rel
		n += 1
		if t >= next_shot:
			next_shot += 10.0
			await _snap("seat_%02d" % int(t))
	var mins := secs / 60.0
	print("SEAT VIEW over %.0f s: looks off ahead at most %.0f deg, %.1f deg on average; turns %.2f rad/s on average, faster than 1 rad/s %.1f%% of the time; swings back %.0f times a minute" % [
		secs, rad_to_deg(most), rad_to_deg(sum_abs / maxf(n - 1, 1)), sum_rate / maxf(n - 1, 1), 100.0 * fast / secs, flips / mins])
	quit(0)
