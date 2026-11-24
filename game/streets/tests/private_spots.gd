extends RefCounted
## The places the tests keep away from (privacy, see DEV.md): read from
## game/streets/tests/.private_places.json, which is git-ignored and never committed (the
## same file tests/pick_routes.py reads; its format is there). [point, metres round it]:
## a corner keeps 800 m clear, a street 150 m either side of its line. Without the file,
## nothing is kept away from.
##   var avoid: Array = load("res://game/streets/tests/private_spots.gd").spots(g)
##   if load("res://game/streets/tests/private_spots.gd").near(avoid, p): ...

static func spots(g: Node) -> Array:
	var path := "res://game/streets/tests/.private_places.json"
	var priv = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var corners: Dictionary = (priv as Dictionary).get("corners", {}) if priv is Dictionary else {}
	var streets: Dictionary = (priv as Dictionary).get("streets", {}) if priv is Dictionary else {}
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
