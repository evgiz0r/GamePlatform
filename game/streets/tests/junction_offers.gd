extends SceneTree
## The choices autodrive offers at junctions, city-wide (LEVEL): for every way into every
## junction where it would ask (two or more proper streets on), the ways out it lists --
## how many offers, how many with no name (a slip road offered as a way of its own: "it gave
## four options, one of them weird"), how many two of the same street within 40 degrees,
## and the busiest offers with their names. No driving: seconds after the city is built.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(0.5).timeout
	var asks := 0
	var unnamed := 0
	var twins := 0
	var sizes := {}
	var worst: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"] or r.get("ring", false):
			continue
		var pts: PackedVector2Array = r["pts"]
		for end: Array in [[pts.size() - 1, 1], [0, -1]]:
			var ei: int = end[0]
			var dir: int = end[1]
			if int(r["o"]) != 0 and int(r["o"]) != dir:
				continue
			var found: Array = g._ap_ways(ri, ei, dir)
			var main: Array = (found[0] as Array).filter(func(x): return not x["service"])
			if main.size() < 2:
				continue
			var prev := pts[ei - dir] if (ei - dir >= 0 and ei - dir < pts.size()) else pts[ei]
			var came := (pts[ei] - prev).normalized()
			var exits: Array = g._cluster_exits(main, came, 0, {})
			if exits.size() < 2:
				continue
			asks += 1
			sizes[exits.size()] = int(sizes.get(exits.size(), 0)) + 1
			var names: Array = []
			var bad := false
			for x: Dictionary in exits:
				if String(x["name"]) == "":
					unnamed += 1
					bad = true
				names.append("%s %+d" % [x["en"] if String(x["en"]) != "" else (x["name"] if String(x["name"]) != "" else "(no name)"), int(rad_to_deg(x["turn"]))])
			for a in range(exits.size()):
				for b in range(a + 1, exits.size()):
					if String(exits[a]["name"]) != "" and exits[a]["name"] == exits[b]["name"] \
							and absf(angle_difference(exits[a]["turn"], exits[b]["turn"])) < 0.7:
						twins += 1
						bad = true
			if bad or exits.size() >= 4:
				worst.append([exits.size() + (10 if bad else 0), "%s at %s: %s" % [r["en"], Vector2i(pts[ei]), ", ".join(names)]])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("JUNCTION OFFERS: %d places it asks; offers per ask %s; with no name %d; twins (same street, within 40 deg) %d" % [asks, str(sizes), unnamed, twins])
	for w: Array in worst.slice(0, 12):
		print("  ", w[1])
	quit(0)
