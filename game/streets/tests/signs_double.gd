extends SceneTree
## Stop and give-way poles standing two to a way in: every pair of poles within 3 m of each
## other whose plates face the same way, with the junction points they were stood for and
## the sign records behind them (a user's screenshot: two give-way triangles side by side).
##   tests/run.sh signs_double 1
var g: Node
func _initialize() -> void:
	_run()

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
	var at: Array = g.sign_at
	var pairs := 0
	var same_node := 0
	var shown := 0
	for i in range(at.size()):
		for j in range(i + 1, at.size()):
			var a: Array = at[i]
			var b: Array = at[j]
			if (a[0] as Vector2).distance_to(b[0]) > 3.0 or (a[1] as Vector2).dot(b[1]) < 0.7:
				continue
			pairs += 1
			if a[3] == b[3]:
				same_node += 1
			if shown < 15:
				shown += 1
				var recs := [a[4], b[4]]
				var ranks := []
				for e: Vector2i in g._node_roads[a[3]]:
					ranks.append("%s %s" % [g._roads[e.x]["k"], g._roads[e.x]["name"]])
				print("  %s %s at %s (node %d, %d ways) and %s %s at %s (node %d), %.1f m apart; records: %s" % [a[2], (a[1] as Vector2).snapped(Vector2(0.01, 0.01)),
					(a[0] as Vector2).round(), a[3], g._node_ways(a[3]), b[2], (b[1] as Vector2).snapped(Vector2(0.01, 0.01)), (b[0] as Vector2).round(), b[3],
					(a[0] as Vector2).distance_to(b[0]), recs])
				print("      roads at the first: %s" % [ranks])
	print("sign poles: %d; two facing the same way within 3 m: %d (at the same junction point: %d)" % [at.size(), pairs, same_node])
	quit(0)
