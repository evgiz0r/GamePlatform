extends SceneTree
## Every piece of writing a town shows -- 3D labels (shop names, street plates, road words,
## station and shelter signs), the HUD's labels and buttons, the name plates waiting to be put
## up, a taxi's roof sign -- checked for Hebrew letters. Hebrew belongs only in the Israeli
## towns (_hebrew(): _country() "il" and no "lang": "en"); anywhere else one Hebrew letter is a FAIL.
##   tests/run.sh hebrew_scan 14      (Delft; 2 Bedford, 33 Leiden, 34 Annecy, 39 showroom, 41 Monaco)
## Prints: country, how many texts it read, how many had Hebrew, up to 12 of them, then
## "hebrew_scan: ok" or "hebrew_scan: FAIL".
var g: Node

func _initialize() -> void:
	_run()

static func _has_hebrew(s: String) -> bool:
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if c >= 0x0590 and c <= 0x05FF:
			return true
	return false

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while g._bg_build:
		await create_timer(0.5).timeout
	await create_timer(float(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 3.0).timeout
	var country: String = g._country()
	var texts: Array = []
	for n in root.find_children("*", "Label3D", true, false):
		texts.append(["label3d", (n as Label3D).text])
	for n in root.find_children("*", "Label", true, false):
		texts.append(["label", (n as Label).text])
	for n in root.find_children("*", "Button", true, false):
		texts.append(["button", (n as Button).text])
	for s: Array in g._name_signs:
		texts.append(["name plate", String(s[1])])
	# SHOT=1: a picture of the shop sign nearest the start (or the one reading SIGN), and of
	# the whole screen with the HUD as it is now
	if OS.get_environment("SHOT") != "":
		var want := OS.get_environment("SIGN")
		var best: Label3D = null
		var best_d := INF
		var car := Vector3(g._pos.x, 0.0, g._pos.y)
		for n in root.find_children("*", "Label3D", true, false):
			var lb := n as Label3D
			if lb.text.strip_edges() == "" or lb.text.is_valid_float():
				continue
			var d := lb.global_position.distance_to(car) if want == "" else (0.0 if lb.text.contains(want) else INF)
			if d < best_d:
				best_d = d
				best = lb
		await _snap("hud")
		if best != null:
			var at := best.global_position
			var face := best.global_transform.basis.z.normalized()
			g.set_physics_process(false)
			if process_frame.is_connected(g._frame):
				process_frame.disconnect(g._frame)
			g.look_from(at + face * 7.0 + Vector3(0, -0.6, 0), at)
			await _snap("sign")
	var bad: Array = []
	for t: Array in texts:
		if _has_hebrew(String(t[1])):
			bad.append(t)
	print("country: ", country, " · texts read: ", texts.size(), " · with Hebrew: ", bad.size())
	for i in range(mini(12, bad.size())):
		print("  ", bad[i][0], ": ", String(bad[i][1]).replace("\n", " / "))
	var he: bool = g._hebrew() if g.has_method("_hebrew") else country == "il"
	if not he and not bad.is_empty():
		print("hebrew_scan: FAIL")
	else:
		print("hebrew_scan: ok")
	quit()
