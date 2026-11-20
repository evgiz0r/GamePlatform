extends SceneTree
## What a simulated second costs, and where it goes: autodrive drives for SECS game seconds
## (traffic and people about, quality 0) and this prints the wall time per game second and,
## every 10 s, the game's own profiler's average frame part by part (`_prof_avg`). Run it at
## two speeds to see what going faster buys:
##
##   LEVEL=4 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/sim_cost.gd
##   STREETS_SIM_SPEED=3 LEVEL=4 ...     (the same game time in a third of the ticks)
##
## November 2026, the test town: 158-171 ms a game second at 1x, 106 at 2x, 55 at 3x (traffic
## is half of each tick). Not --time-scale: the shell puts the time scale back to 1 when the
## game starts, so that flag measured 1x three times over.
var g: Node

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
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 40.0
	var t := 0.0
	var ticks := 0
	var next_print := 10.0
	var w0 := Time.get_ticks_msec()
	while t < secs:
		await physics_frame
		t += Engine.time_scale / Engine.physics_ticks_per_second
		ticks += 1
		if t >= next_print:
			next_print += 10.0
			print("  %3.0f s: %s" % [t, g._prof_avg])
	var wall := float(Time.get_ticks_msec() - w0)
	print("SIM COST %s at time scale %.1f: %.0f game s in %.1f s wall, %d ticks: %.0f ms a game second, %.1f ms a tick" % [
		g._city_name, Engine.time_scale, t, wall / 1000.0, ticks, wall / t, wall / ticks])
	quit(0)
