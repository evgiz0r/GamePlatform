extends SceneTree
## The test town's "deep water" on a road (found 23 Nov 2026 by the exam, "autodrive: hit deep"
## at 50 km/h): autodrive from (-548, 410) towards (-470, 457) is stopped dead at (-524, 430) by
## _deep_push -- at 60 and at 30 ticks a second alike, so not the tick rate. Prints every hit
## and, near the spot, the car's height, the ground's and the push. Good: no 'deep water' line.
##   $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/deep_water_road.gd
var g: Node
func _initialize() -> void:
	_run()
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var w := 0
	while g._bg_build:
		await create_timer(0.5).timeout
		w += 1
		if w % 10 == 0:
			print("  waiting: bg %s catch %s bstep '%s' hz %d frames %d" % [g._bg_build, g._catch_up, g._bstep, Engine.physics_ticks_per_second, Engine.get_physics_frames()])
	g._set_quality(0)
	for run in range(3):
		g._set_auto(false)
		g._pos = Vector2(-548.0, 410.0)
		g._yaw = 1.09
		g._v = 0.0
		g._snap_pose()
		await physics_frame
		g._set_dest(Vector2(-470.0, 457.0), "test")
		g._set_auto(true)
		var t := 0.0
		var last := ""
		while t < 14.0:
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			if g._last_hit != last:
				last = g._last_hit
				print("  run %d t %.2f hit '%s' at %s v %.1f y %.2f ground %.2f" % [run, t, last, g._pos, g._v, g._y, g._h(g._pos)])
			if g._pos.distance_to(Vector2(-523, 430)) < 6.0 and int(t * 10) % 3 == 0:
				print("    near: %s v %.1f y %.2f ground %.2f deep %s" % [g._pos, g._v, g._y, g._h(g._pos), g._deep_push(g._pos, 1.0, g._y)])
		print("run %d done at %s, hz %d" % [run, g._pos, Engine.physics_ticks_per_second])
	quit()
