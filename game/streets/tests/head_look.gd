extends SceneTree
## The driver looking left and right: autodrive handed the car 45 m before a junction on a
## side street, once in the seat view and once in the chase view. Prints the head's angle
## through the approach (degrees, + left) and saves shots at the look left, the look right
## and ahead ($OUT/head_seat_*.png, head_chase_*.png). Then the switch: driving yourself
## with "look" off, stood at a junction, the head must stay ahead; with it on, it scans.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

## a side street 45 m before a junction of 3+ ways, facing it: [where, facing]
func _approach(skip: int) -> Array:
	var found := 0
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if r["k"] != "residential" or r["pv"] or int(r["o"]) != 0:
			continue
		var ids: PackedInt32Array = r["ids"]
		var pts: PackedVector2Array = r["pts"]
		var last := pts.size() - 1
		if g._node_ways(ids[last]) < 3 or g._node_ways(ids[0]) < 3:
			continue
		var L := 0.0
		for k in range(last):
			L += pts[k].distance_to(pts[k + 1])
		if L < 70.0 or pts[last].distance_to(g._pos) > 900.0:
			continue
		# 45 m back from the end along the street
		var back := 45.0
		var k := last
		var p := pts[last]
		while back > 0.0 and k > 0:
			var seg := p.distance_to(pts[k - 1])
			if seg >= back:
				p = p + (pts[k - 1] - p) * (back / seg)
				break
			back -= seg
			p = pts[k - 1]
			k -= 1
		found += 1
		if found > skip:
			return [p, (pts[last] - p).normalized()]
	return []

func _watch(tag: String) -> void:
	var t := 0.0
	var dt := 1.0 / 60.0
	var shots := {"left": false, "right": false}
	var line := ""
	while t < 14.0:
		await physics_frame
		t += dt
		var h: float = g._head_yaw
		if int(t * 60.0) % 30 == 0:
			line += "%+.0f " % rad_to_deg(h)
		if h > 0.85 and not shots["left"]:
			shots["left"] = true
			await _snap("head_%s_left" % tag)
		if h < -0.85 and not shots["right"]:
			shots["right"] = true
			await _snap("head_%s_right" % tag)
	print("  %s: head every 0.5 s (deg, + left): %s" % [tag, line])
	print("  %s: looked left %s, right %s" % [tag, shots["left"], shots["right"]])

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	for i in range(2):
		var a := _approach(i * 3)
		if a.is_empty():
			print("no side street found")
			break
		var tag := "seat" if i == 0 else "chase"
		g._set_cockpit(i == 0)
		g._set_auto(false)
		g._land_on_road(a[0], 10.0, a[1])
		await physics_frame
		await _snap("head_%s_start" % tag)
		g._set_auto(true)
		print("%s view, from %s toward a junction 45 m on:" % [tag, Vector2i(a[0])])
		await _watch(tag)
	# driving yourself, stood 12 m before a junction: with "look" off, nothing; on, a scan
	var b := _approach(7)
	if not b.is_empty():
		g._set_cockpit(false)
		g._set_auto(false)
		for on: bool in [false, true]:
			g._look_on = on
			g._head_at = Vector2.INF
			g._land_on_road((b[0] as Vector2) + (b[1] as Vector2) * 33.0, 10.0, b[1])
			var most := 0.0
			for _f in range(240):
				await physics_frame
				g._v = 0.0
				most = maxf(most, absf(g._head_yaw))
			print("  driving yourself, look %s, stood before a junction: head turned at most %.0f deg" % ["on" if on else "off", rad_to_deg(most)])
	quit(0)
