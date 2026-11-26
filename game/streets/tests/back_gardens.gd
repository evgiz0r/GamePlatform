extends SceneTree
## Bedford's fenced back gardens (26 Nov 2026, furniture.gd back_gardens): the user, on
## Fleetview Drive: "houses ... have some kind of closed gardens on the back". Prints how many
## houses got one and how much fence, then (drawn) looks at Fleetview Drive from above and
## from the street beside a house. NO_YARDS=1 for the picture before.
##   OUT=/tmp/bg FULL=1 RES=1280x720 game/streets/tests/run.sh back_gardens 2
## Good: most of the street's houses closed behind, no fence across a road or a neighbour's
## garden, every fence standing on the ground.
var g: Node
func _initialize() -> void:
	_run()
func _shot(p: Vector2, yaw: float, up: float, pitch: float, name: String) -> void:
	g._dev_cam[2] = up
	g._dev_cam[4] = pitch
	for i in 6:
		g._pos = p
		g._prev_pos = p
		g._yaw = yaw
		g._prev_yaw = yaw
		await process_frame
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.6,0,0")
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 2
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while not g._tiles_todo.is_empty():
		await create_timer(0.5).timeout
	g._car.visible = false
	var yards := {}
	for k in g._furn._yards:
		for poly in g._furn._yards[k]:
			yards[poly] = true
	print("back gardens: %d, fence %d m" % [int(g._dressing.get("back_gardens", 0)), int(g._dressing.get("garden_fence_m", 0))])
	# Fleetview Drive's middle, and the garden nearest it
	var pts := PackedVector2Array()
	for r: Dictionary in g._roads:
		if String(r["name"]) == "Fleetview Drive":
			pts.append_array(r["pts"])
	if pts.is_empty():
		print("REGRESS back_gardens: FAIL (no Fleetview Drive)")
		quit()
		return
	var mid: Vector2 = pts[pts.size() / 2]
	var near: PackedVector2Array
	var nd := INF
	var on_street := 0
	for poly: PackedVector2Array in yards:
		var c := (poly[0] + poly[1] + poly[2] + poly[3]) * 0.25
		var dd := c.distance_to(mid)
		if dd < nd:
			nd = dd
			near = poly
		for q in pts:
			if q.distance_to(c) < 60.0:
				on_street += 1
				break
	print("gardens within 60 m of Fleetview Drive's points: %d; nearest to its middle %.0f m off" % [on_street, nd])
	if DisplayServer.get_name() == "headless":
		print("REGRESS back_gardens: %s" % ["PASS" if yards.size() > 50 else "FAIL"])
		quit()
		return
	var tag := "before" if OS.get_environment("NO_YARDS") != "" else "after"
	# from above the street, looking over the house at its garden
	var hc := (near[0] + near[1]) * 0.5          # the house end of the garden
	var gc := (near[2] + near[3]) * 0.5          # its rear fence
	var back := (gc - hc).normalized()
	var from := hc - back * 22.0
	await _shot(from, back.angle(), 26.0, -38.0, "fleetview_above_" + tag)
	# standing in the garden by the house, looking down it to the rear fence
	var eye := hc + back * 1.5
	await _shot(eye, back.angle(), 1.6, -4.0, "fleetview_garden_" + tag)
	# from behind the gardens, looking back at the houses over the rear fences
	eye = gc + back * 9.0
	await _shot(eye, (-back).angle(), 2.2, -3.0, "fleetview_behind_" + tag)
	# straight down over the street, wide
	await _shot(mid, back.angle(), 70.0, -80.0, "fleetview_map_" + tag)
	quit()
