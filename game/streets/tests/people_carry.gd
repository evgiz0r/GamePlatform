extends SceneTree
## What people carry (streets.gd "what people carry"): five people in a row beside the car,
## each with one thing -- a shopping bag, a handbag, a backpack, a box (the carrying walk),
## nothing -- walking on the spot, and three builds side by side. Shots pc_<i>_side / _front /
## _back.png in $OUT, each person up close.
## Good: the bags hang from the hand beside the leg, not through it; the backpack sits on
## the back, not inside it or floating off it; the box rests on the forearms, hands under it.
## On people.gd's figures the sixth is a child and the last on the phone.
##   OUT=... game/streets/tests/run.sh people_carry 4
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
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
	for w: Dictionary in g._walkers:   # the street's own walkers out of the way
		(w["actor"] as Node3D).position.y -= 500.0
	var p: Vector2 = g._pos
	var y: float = g._h(p) + 0.02
	var fw := Vector3(cos(g._yaw), 0, sin(g._yaw))
	var rt := fw.cross(Vector3.UP)
	var base := Vector3(p.x, y, p.y) + fw * 7.0   # on the road ahead (the pavement has trees and bins in the way)
	var kinds := ["bag", "handbag", "backpack", "box", ""]
	var made := []
	for i in range(kinds.size() + 2):
		var a = load("res://shell/actor3d.gd").new()
		g.world.add_child(a)
		a.set_character(g.PEOPLE[i % g.PEOPLE.size()], 1.72)
		g._humanize(a, 4000 + i * 7)
		g._people_lod(a)
		var what: String = kinds[i] if i < kinds.size() else ""
		g._carry(a, what, 500 + i)
		if i == 6 and g._people_maker().on():
			g._ppl.phone(a)   # (the last, in the clear: on the phone)
		if i == 5 and g._people_maker().on():   # (the sixth: a child)
			a.height = 1.2
			a.set_meta("child", true)
			g._humanize(a, 77)
			g._people_lod(a)
		a.position = base + rt * (float(i) * 2.5 - 7.5)
		a.play("Walk_Carry" if what == "box" else "Walk", true, 0.0001)
		a.face(fw)   # all facing along the row, spaced out along it: from the side, side by side in profile
		made.append(a)
		var sz: Vector3 = a.model.scale
		print("%d %s %s: build %.2f x %.2f" % [i, g.PEOPLE[i % g.PEOPLE.size()], what if what != "" else "-", sz.x / sz.y, sz.z / sz.y])
	await create_timer(0.6).timeout
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	# each up close, from its right side, from in front at an angle and from behind
	for i in range(made.size()):
		var a: Node3D = made[i]
		var c: Vector3 = a.global_position + Vector3(0, 0.95, 0)
		g.look_from(c + rt * 2.4 + Vector3(0, 0.15, 0), c)
		g._sky_follow()
		await _snap("pc_%d_side" % i)
		g.look_from(c + fw * 1.7 + rt * 1.6 + Vector3(0, 0.2, 0), c)
		g._sky_follow()
		await _snap("pc_%d_front" % i)
		g.look_from(c - fw * 1.9 - rt * 1.4 + Vector3(0, 0.3, 0), c)
		g._sky_follow()
		await _snap("pc_%d_back" % i)
	quit(0)
