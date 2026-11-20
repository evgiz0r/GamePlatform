extends SceneTree
## The stop and give-way signs worked out where OSM has none (`_infer_signs`): how many of
## each, how many junctions have rules, how many ways in got no pole (no room off the road),
## and shots from a driver's seat 14 m back from the line to the first few of each kind
## (stop_*.png, give_*.png; SHOTS of each, default 2). With a stop, traffic and autodrive
## come to a full stop at the line; with a give-way, down to walking pace.
##   tests/run.sh signs_inferred 1
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
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
	await create_timer(1.0).timeout
	print("signs inferred: %d stop, %d give way (mapped in OSM and kept: the rest)" % [int(g._dressing.get("signs inferred: stop", 0)),
		int(g._dressing.get("signs inferred: give way", 0))])
	var rules := 0
	var kinds := {"stop": 0, "give_way": 0}
	for n: int in g._signs:
		for r: Array in g._signs[n]:
			rules += 1
			kinds[r[0]] = int(kinds.get(r[0], 0)) + 1
	print("junctions with a sign: %d, ways in with one: %d (stop %d, give way %d); poles stood: %d" % [g._signs.size(), rules,
		kinds["stop"], kinds["give_way"], int(g._dressing.get("signs", 0))])
	# shots: a few junctions of each kind, from a driver's seat up the way in
	var shots := int(OS.get_environment("SHOTS")) if OS.get_environment("SHOTS") != "" else 2
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	var done := {"stop": 0, "give_way": 0}
	var keys: Array = g._signs.keys()
	keys.sort()
	for n: int in keys:
		for r: Array in g._signs[n]:
			var kind: String = r[0]
			if done[kind] >= shots:
				continue
			var c: Vector2 = g._nodes[n]
			var way_in: Vector2 = r[1]
			var from := c - way_in * (float(r[2]) + 14.0) + Vector2(-way_in.y, way_in.x) * 1.6
			done[kind] += 1
			print("  %s at %s, way in %s, line %.1f m before" % [kind, c.round(), way_in, float(r[2])])
			g.look_from(Vector3(from.x, g._h(from) + 1.5, from.y), Vector3(c.x - way_in.x * float(r[2]), g._h(c) + 0.6, c.y - way_in.y * float(r[2])))
			await _snap("%s_%d" % ["stop" if kind == "stop" else "give", done[kind]])
	quit(0)
