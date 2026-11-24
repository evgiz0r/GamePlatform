extends SceneTree
## Waving and pointing (people.gd Gesture): two people 6 m ahead of the car, facing it; one
## waves, one points. Prints, a second in (the pose full on), where each one's right hand is
## in their own body's frame (metres: x to their left, y up from the feet, z ahead of them) and
## the head's height; then the same after the gesture ends. Shots ge_<i>_front, ge_<i>_side.
## Good: the wave's hand above the head's height less 0.1, out to the right (x < -0.2); the
## point's at shoulder height (1.25-1.5) and well ahead (z > 0.3, the shoulder being back of the feet); both hands back by the
## end (y under 1.0).
##   OUT=... game/streets/tests/run.sh people_gesture 4
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _ge(a: Node3D) -> Object:
	for m in a.model.find_children("*", "SkeletonModifier3D", true, false):
		if "hand_at" in m:
			return m
	return null

## the hand (or the elbow) as the gesture left it, in the person's own frame
func _hand(a: Node3D, elbow := false) -> Vector3:
	var ge = _ge(a)
	return a.global_transform.affine_inverse() * (ge.elbow_at if elbow else ge.hand_at)

func _head(a: Node3D) -> Vector3:
	var sk: Skeleton3D = a.model.find_children("*", "Skeleton3D", true, false)[0]
	return a.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if not g._people_maker().on():
		print("old figures: nothing to test")
		quit(0)
		return
	for list: Array in [g._walkers, g._chatters, g._waiters, g._keepers, g._sitters]:
		for w: Dictionary in list:
			(w["actor"] as Node3D).position.y -= 500.0
	var p: Vector2 = g._pos
	var y: float = g._h(p) + 0.02
	var fw := Vector3(cos(g._yaw), 0, sin(g._yaw))
	var rt := fw.cross(Vector3.UP)
	var base := Vector3(p.x, y, p.y) + fw * 6.0
	var made := []
	var kinds := ["wave", "point"]
	for i in range(2):
		var a = load("res://shell/actor3d.gd").new()
		g.world.add_child(a)
		g._set_character(a, g.PEOPLE[i % g.PEOPLE.size()], 1.72)
		g._humanize(a, 7000 + i * 13)
		g._people_lod(a)
		a.position = base + rt * (float(i) * 1.6 - 0.8)
		a.play("Idle", true)
		a.face(-fw)
		made.append(a)
	await create_timer(0.5).timeout
	process_frame.disconnect(g._frame)
	g.set_physics_process(false)
	for i in range(2):
		print("%s started: %s" % [kinds[i], g._ppl.gesture(made[i], kinds[i])])
	await create_timer(1.1).timeout
	var ok := 0
	for i in range(2):
		var a: Node3D = made[i]
		var h := _hand(a)
		var hd := _head(a)
		print("%s: hand (%.2f, %.2f, %.2f), head at %.2f" % [kinds[i], h.x, h.y, h.z, hd.y])
		if kinds[i] == "wave" and h.y > hd.y - 0.1 and h.x < -0.2:
			ok += 1
		if kinds[i] == "point" and h.y > 1.25 and h.y < 1.5 and h.z > 0.3:
			ok += 1
	for i in range(2):
		var c: Vector3 = (made[i] as Node3D).global_position + Vector3(0, 1.3, 0)
		g.look_from(c - fw * 2.6 + Vector3(0, 0.1, 0), c)
		g._sky_follow()
		await _snap("ge_%d_front" % i)
		g.look_from(c + rt * 2.6 - fw * 0.4, c)
		g._sky_follow()
		await _snap("ge_%d_side" % i)
	await create_timer(2.2).timeout
	var back := 0
	for i in range(2):
		var h := _hand(made[i])
		print("%s after: hand (%.2f, %.2f, %.2f)" % [kinds[i], h.x, h.y, h.z])
		if h.y < 1.0:
			back += 1
	print("PASS %d/2 posed, %d/2 back" % [ok, back])
	quit(0)
