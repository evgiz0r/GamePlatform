extends RefCounted
## The places the tests keep away from (privacy, see DEV.md), as tests/pick_routes.py lists
## them (AVOID_CORNERS, AVOID_STREETS -- one list, read from there): [point, metres round it].
## A corner keeps 800 m clear, a street 150 m either side of its line.
##   var avoid: Array = load("res://game/streets/tests/private_spots.gd").spots(g)
##   if load("res://game/streets/tests/private_spots.gd").near(avoid, p): ...

static func spots(g: Node) -> Array:
	var src := FileAccess.get_file_as_string("res://game/streets/tests/pick_routes.py")
	var corners := {}
	var streets := {}
	for line: String in src.split("\n"):
		for key: String in ["AVOID_CORNERS", "AVOID_STREETS"]:
			if line.begins_with(key + " ="):
				var lit := line.substr(line.find("=") + 1).split("#")[0].replace("(", "[").replace(")", "]")
				var v = JSON.parse_string(lit)
				if v is Dictionary:
					if key == "AVOID_CORNERS":
						corners = v
					else:
						streets = v
	var out: Array = []
	for pair: Array in corners.get(g._city_id, []):
		var a := {}
		for r: Dictionary in g._roads:
			if String(r.get("en", "")) == pair[0]:
				for n: int in r["ids"]:
					a[n] = true
		for r: Dictionary in g._roads:
			if String(r.get("en", "")) == pair[1]:
				for n: int in r["ids"]:
					if a.has(n):
						out.append([g._nodes[n], 800.0])
	for name: String in streets.get(g._city_id, []):
		for r: Dictionary in g._roads:
			if String(r.get("name", "")).contains(name):
				for p: Vector2 in r["pts"]:
					out.append([p, 150.0])
	return out

static func near(spots_: Array, p: Vector2) -> bool:
	for s: Array in spots_:
		if (s[0] as Vector2).distance_to(p) < float(s[1]):
			return true
	return false
