extends SceneTree
## A thin bright line straight across the screen, flickering, on the filmed walk's passage
## (a user's screenshot, walk level 5 around film 36-56 s: "flickering line in the middle of
## the screen sometimes"). Plays the walk from FROM to UNTIL seconds (default 34-60) and saves
## a frame every STEP seconds (default 0.25) as l<tenths>.png, printing the eye's height over
## the ground and the camera's pitch (anything flat at the eye's height, seen edge-on, is a
## line at the horizon: ~30% down the screen in the walk's view, pitched 15 deg down).
## Then tests/horizon_line.py finds the frames with a one-pixel line in them.
## The cause was the sky dome: Godot's hemisphere closes with a flat disc at its middle's
## height, and the dome stands on the eye, so the disc is a plane through the eye -- which a
## software renderer never draws and a phone's GPU did now and then, a pixel high, in the
## horizon's grey. To see it here, DROP=0.002 stands the dome 2 mm below the eye (the GPU's
## rounding, made bigger) and HEMI=1 puts the old hemisphere back: a band across every frame
## (before); with the whole sphere there is no disc to draw, none.
##   RES=1650x896 OUT=/tmp/line game/streets/tests/run.sh horizon_line 5
##   DROP=0.002 HEMI=1 FROM=40 UNTIL=42 STEP=0.5 ... (the old dome: a line in every frame)
var g: Node
func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 5})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	var out := OS.get_environment("OUT")
	if g._film.is_empty():
		print("FAIL no walk: is this the walk's level?")
		quit(1)
		return
	g.sky_drop = float(OS.get_environment("DROP")) if OS.get_environment("DROP") != "" else 0.0
	if OS.get_environment("HEMI") == "1":   # the dome as it was: a hemisphere, its flat bottom on the eye
		var hm := SphereMesh.new()
		hm.radius = 1900.0
		hm.height = 1900.0
		hm.is_hemisphere = true
		hm.radial_segments = 32
		hm.rings = 10
		hm.material = g._sky_mat
		g._sky_dome.mesh = hm
	var from := float(OS.get_environment("FROM")) if OS.get_environment("FROM") != "" else 34.0
	var until := float(OS.get_environment("UNTIL")) if OS.get_environment("UNTIL") != "" else 60.0
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 0.25
	g._film_t = from - 1.5
	for i in range(30):
		await physics_frame
	while g._film_t < from:
		await physics_frame
	var next := from
	while g._film_t <= until:
		await RenderingServer.frame_post_draw
		if g._film_t < next:
			continue
		next += step
		var t: float = g._film_t
		root.get_viewport().get_texture().get_image().save_png(out + "/l%04d.png" % int(round(t * 10.0)))
		var eye: Vector3 = g.cam.global_position
		print("t=%.2f eye %.3f m over the ground at %s (cam y %.3f, pitch %.1f deg)" % [t, eye.y - g._h(Vector2(eye.x, eye.z)),
			Vector2i(Vector2(eye.x, eye.z)), eye.y, rad_to_deg(g.cam.global_rotation.x)])
	quit()
