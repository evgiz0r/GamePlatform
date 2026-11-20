extends SceneTree
## Why a route of the set cannot be planned: for each route in this LEVEL's city, the roads
## nearest its two ends (public and drivable), and whether the road graph joins them --
## the size of the part of the graph each end is in. Headless, seconds after the city loads.
var g: Node

func _initialize() -> void:
	_run()

## how many graph points can be reached from `start` (following the one-ways)
func _reach(start: int) -> int:
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var p: int = todo.pop_back()
		for q: int in g._astar.get_point_connections(p):
			if not seen.has(q):
				seen[q] = true
				todo.append(q)
	return seen.size()

func _run() -> void:
	var lvl := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": lvl})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	var all: Dictionary = JSON.parse_string(FileAccess.open("res://game/streets/routes.json", FileAccess.READ).get_as_text())
	for r: Dictionary in all["routes"]:
		if int(r["level"]) != lvl:
			continue
		var from := Vector2(float(r["from_at"][0]), float(r["from_at"][1]))
		var to := Vector2(float(r["to_at"][0]), float(r["to_at"][1]))
		var s: Dictionary = g._nearest_seg(from, 40.0, true, true)
		var e: Dictionary = g._nearest_seg(to, 150.0, true, true)
		var line := "route %d: " % int(r["id"])
		if s.is_empty() or e.is_empty():
			print(line + "no public road near the %s" % ("start" if s.is_empty() else "end"))
			continue
		var rs: Dictionary = g._roads[s["road"]]
		var re: Dictionary = g._roads[e["road"]]
		var a: int = (rs["ids"] as PackedInt32Array)[int(s["seg"])]
		var b: int = (re["ids"] as PackedInt32Array)[int(e["seg"])]
		print(line + "start on %s (%s, %.0f m off), end on %s (%s, %.0f m off); reach from the start %d points, from the end %d; a way %s" % [
			rs["en"], rs["k"], float(s["edge"]), re["en"], re["k"], float(e["edge"]), _reach(a), _reach(b),
			"found" if g._astar.has_point(a) and g._astar.has_point(b) and not g._astar.get_id_path(a, b).is_empty() else "NOT found"])
	quit(0)
