extends SceneTree
## A town's traffic signs and road paint as a driver sees them, one shot of each kind, for
## checking them against that country's real signs (Israel, the Netherlands, France and
## Monaco under the Vienna Convention; Canada under its MUTCD): stop and give-way with their
## lines, the speed limit, the street signs (no entry, one way, turn only, keep right,
## roundabout, crossing, parking, name plates) and the words painted near schools.
## Prints the country, the counts of each kind and the centre-line colours in use.
##   tests/run.sh country_signs 14      (Delft; 2 Bedford, 34 Annecy, 41 Monaco, 1 Givatayim)
## Shots: <kind>.png, SHOTS of each (default 1), from 12 m in front of the sign, 1.5 m up.
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## looks at `at` (a plate's middle, m above the ground) from `back` m out along `face` (the
## way the sign's face looks), a little to the right of it, as a driver coming up to it
func _shoot(name: String, at: Vector2, face: Vector2, back := 12.0, up := 2.0) -> void:
	var from := at + face * back + Vector2(face.y, -face.x) * -1.5
	g.look_from(Vector3(from.x, g._h(from) + 1.5, from.y), Vector3(at.x, g._h(at) + up * 0.6, at.y))
	await _snap(name)

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
	await create_timer(1.0).timeout
	var country: String = g._country() if g.has_method("_country") else "(before: by look only) " + String(g._place.get("look", ""))
	print("country: ", country)
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 1
	g.set_physics_process(false)
	if process_frame.is_connected(g._frame):
		process_frame.disconnect(g._frame)
	var done := {}
	var counts := {}
	# stop and give-way, from a driver's seat up the way in (their lines and words in view)
	var keys: Array = g._signs.keys()
	keys.sort()
	for n: int in keys:
		for r: Array in g._signs[n]:
			var kind: String = r[0]
			counts[kind] = int(counts.get(kind, 0)) + 1
			if int(done.get(kind, 0)) >= shots:
				continue
			done[kind] = int(done.get(kind, 0)) + 1
			var c: Vector2 = g._nodes[n]
			var way_in: Vector2 = r[1]
			var from := c - way_in * (float(r[2]) + 14.0) + Vector2(-way_in.y, way_in.x) * 1.6
			g.look_from(Vector3(from.x, g._h(from) + 1.5, from.y), Vector3(c.x - way_in.x * float(r[2]), g._h(c) + 0.6, c.y - way_in.y * float(r[2])))
			await _snap("%s_%d" % [kind, done[kind]])
	# the street signs: each plate's spot and the way its face looks
	var by_kind := {}
	for pid: int in g._signs_at:
		var sa: Array = g._signs_at[pid]
		var kind: String = sa[0]
		counts[kind] = int(counts.get(kind, 0)) + 1
		if not by_kind.has(kind):
			by_kind[kind] = []
		(by_kind[kind] as Array).append(sa)
	for kind: String in by_kind:
		var list: Array = by_kind[kind]
		list.sort_custom(func(a, b): return (a[1] as Transform3D).origin.x < (b[1] as Transform3D).origin.x)
		for k in range(mini(shots, list.size())):
			var xf: Transform3D = list[k * maxi(1, list.size() / maxi(shots, 1))][1]
			var f3 := (xf.basis * Vector3.BACK).normalized()
			await _shoot("%s_%d" % [kind, k + 1], Vector2(xf.origin.x, xf.origin.z), Vector2(f3.x, f3.z).normalized(), 7.0 if kind != "street" else 6.0, xf.origin.y - g._h(Vector2(xf.origin.x, xf.origin.z)))
	# the speed limits
	var sp := 0
	for lm: Array in g._landmarks:
		if String(lm[1]) != "speed":
			continue
		sp += 1
		if sp <= shots:
			var dir: Vector2 = lm[2]
			await _shoot("speed_%d" % sp, lm[0], -dir, 12.0, 2.35)
	counts["speed"] = sp
	# words painted on the road (stop, give way, school), read from behind them
	var words := {}
	for lb in g.world.get_children():
		if lb is Label3D and absf((lb as Label3D).transform.basis.y.y) < 0.1:
			var t := (lb as Label3D).text
			words[t] = int(words.get(t, 0)) + 1
			if int(words[t]) == 1 and t not in ["STOP", "עצור"]:
				var at := Vector2(lb.position.x, lb.position.z)
				var d := Vector2(lb.transform.basis.y.x, lb.transform.basis.y.z).normalized()
				g.look_from(Vector3(at.x - d.x * 16.0, g._h(at) + 1.5, at.y - d.y * 16.0), Vector3(at.x + d.x * 4.0, g._h(at), at.y + d.y * 4.0))
				await _snap("word_" + str(words.size()))
	print("painted words: ", words)
	print("counts: ", counts)
	quit(0)
