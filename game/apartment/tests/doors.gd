extends SceneTree
## Every door of every flat: how wide is the opening you can actually walk through, once
## the 3D walls are built (walls) and the furniture is in (with furniture)? Prints the
## narrowest per flat and every door under 70 cm. Good: "doors: ok" (nothing under 0.69 m).
## Headless is fine:  $GODOT --headless --path . -s res://game/apartment/tests/doors.gd
const MIN := 0.69   ## 70 cm, less what the 2 mm measuring steps can lose

func _initialize() -> void:
	create_timer(300.0).timeout.connect(func(): print("TIMEOUT"); quit(1))
	_run()

func _game(lv: int) -> Node:
	root.get_node("Flow").start_game("apartment", {"level": lv})
	for k in 200:
		await create_timer(0.1).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("apartment.gd") \
					and n._loaded and n.plan.get("seed", -1) == lv:
				return n
	return null

## The free span through the middle of a door, along its line, among `rects`.
func _span(g: Node, d: Dictionary, rects: Array) -> float:
	var m := (float(d["a"]) + float(d["b"])) / 2.0
	var line: float = d["line"]
	var pt := func(u: float) -> Vector2:
		return g._w(u, line) if d["o"] == "h" else g._w(line, u)
	var blocked := func(p: Vector2) -> bool:
		for r: Rect2 in rects:
			if r.has_point(p):
				return true
		return false
	if blocked.call(pt.call(m)):
		return 0.0
	var lo := m
	while lo > m - 2.0 and not blocked.call(pt.call(lo - 0.002)):
		lo -= 0.002
	var hi := m
	while hi < m + 2.0 and not blocked.call(pt.call(hi + 0.002)):
		hi += 0.002
	return hi - lo

func _run() -> void:
	await create_timer(0.3).timeout
	var bad := 0
	for lv in range(1, 9):
		var g := await _game(lv)
		if g == null:
			print("flat %d did not load" % lv)
			bad += 1
			continue
		var narrow := INF
		var narrow_f := INF
		for d in g.plan["doors"]:
			var w: float = _span(g, d, g._solid)
			var wf: float = _span(g, d, g._blocks())
			narrow = minf(narrow, w)
			narrow_f = minf(narrow_f, wf)
			if w < MIN or wf < MIN:
				bad += 1
				print("  flat %d: %s door into %s: %.2f m (walls), %.2f m (with furniture)" % [lv, d["style"], d["into"], w, wf])
		print("flat %d: narrowest door %.2f m, with furniture %.2f m" % [lv, narrow, narrow_f])
	print("doors: ok" if bad == 0 else "doors: %d too narrow" % bad)
	quit(0)
