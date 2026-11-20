extends SceneTree
## Up over the city, a long press on a street sends the car there: zoom out, hold the mouse on
## a spot ahead for HOLD_S, then check the destination was set to a street, the view came back
## down, the city runs again, autodrive is on with a route, and the car closes on the spot.
## Shots: the ring filling under the press, the view landing, the drive.
##   tests/run.sh go_where 1        (AT_X, AT_Y: where on the 640x360 screen to press)
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _press(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	print(g._load_text())
	if OS.get_environment("FULL") == "":
		g._set_quality(0)
	var start: Vector2 = g._pos
	g._zoom_set(g.ZOOM_UP)
	await create_timer(2.5).timeout
	var at := Vector2(float(OS.get_environment("AT_X")) if OS.get_environment("AT_X") != "" else 330.0,
			float(OS.get_environment("AT_Y")) if OS.get_environment("AT_Y") != "" else 120.0)
	var aim: Vector2 = g._screen_ground(at)
	print("zoomed: %s, paused %s; pressing at %s, the ground there %s (%.0f m from the car)" % [g._zoomed(), g._paused, at, aim.round(), aim.distance_to(start)])
	_press(at, true)
	await create_timer(g.HOLD_S * 0.6).timeout
	await _snap("1_holding")
	print("holding: ring %.2f, destination yet: %s" % [g._hold_progress(), g._dest_on])
	await create_timer(g.HOLD_S * 0.6).timeout
	_press(at, false)
	print("after the hold: destination %s '%s' at %s (%.0f m from where pressed), autodrive %s" % [g._dest_on, g._dest_name, (g._dest as Vector2).round(), (g._dest as Vector2).distance_to(aim), g._auto])
	await create_timer(1.0).timeout
	await _snap("2_landing")
	await create_timer(3.0).timeout
	print("landed: zoomed %s, paused %s, route points %d" % [g._zoomed(), g._paused, g._ap_pts.size()])
	var d0: float = g._pos.distance_to(g._dest)
	await create_timer(15.0).timeout
	await _snap("3_driving")
	print("15 s on: %.0f m to go (was %.0f), %.1f m/s, still going there %s" % [g._pos.distance_to(g._dest), d0, g._v, g._dest_on])
	# a short press is still a drag, not a destination
	g._clear_dest()
	g._zoom_set(g.ZOOM_UP)
	await create_timer(2.0).timeout
	_press(at, true)
	await create_timer(0.2).timeout
	_press(at, false)
	await create_timer(0.8).timeout
	print("a quick press: destination %s (should be false)" % g._dest_on)
	quit(0)
