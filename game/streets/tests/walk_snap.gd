extends SceneTree
## Walk snap: a filmed walk's GPS route moved onto the back half of the pavements it was
## walked on, by the game's own roads (its widths are not OSM's: they are fitted to the
## buildings), for a replay that keeps to the pavement where a phone's GPS (good to ~4 m)
## wanders into the road.
##   ROUTE  {"points": [[t, x, z]...]}  (tools/gpx_route.py route)
##   SIDES  [[from, to, "left"|"right", "street name"], ...]  seconds of the route: on that
##          side of the way walked, along the named street (Hebrew, as the city file has it);
##          points outside every span (a crossing) are left where they are
## Writes $OUT/walk.json ({"points": ...}, rounded) and prints, per point, how far it moved
## and whether it stands on any road's asphalt, and each crossing's kerb-to-kerb ends.
##   ROUTE=... SIDES=... game/streets/tests/run.sh walk_snap 1
var g: Node
## how far past the road's edge: the back half of the pavement, as the game's own walkers keep
## (the parked cars stand on the front half and the street trees at the kerb: at 1.6 m a
## filmed walk ran through their bumpers and trunks)
const BACK := 2.0

func _initialize() -> void:
	_run()

## the middle of the pavement on `side` of the named street nearest p, facing yaw
func _on_pavement(p: Vector2, yaw: float, side: String, street: String) -> Vector2:
	var best := INF
	var at := p
	for r: Dictionary in g._roads:
		if String(r.get("name", "")) != street:
			continue
		var pts: PackedVector2Array = r["pts"]
		for i in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := q.distance_to(p)
			if d >= best:
				continue
			best = d
			var along: Vector2 = (pts[i + 1] - pts[i]).normalized()
			var n := Vector2(-along.y, along.x)
			if n.dot(Vector2(sin(yaw), -cos(yaw))) < 0.0:   # the walker's left
				n = -n
			if side == "right":
				n = -n
			at = q + n * (float(r["w"]) * 0.5 + BACK)
	return at

func _run() -> void:
	var pts: Array = (JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("ROUTE"))) as Dictionary)["points"]
	var sides: Array = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SIDES")))
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var out: Array = []
	var on_road := 0
	for i in range(pts.size()):
		var t := float(pts[i][0])
		var p := Vector2(pts[i][1], pts[i][2])
		var a := Vector2(pts[maxi(i - 2, 0)][1], pts[maxi(i - 2, 0)][2])
		var b := Vector2(pts[mini(i + 2, pts.size() - 1)][1], pts[mini(i + 2, pts.size() - 1)][2])
		var yaw: float = (b - a).angle() if a.distance_to(b) > 0.5 else (float(out[out.size() - 1][3]) if not out.is_empty() else 0.0)
		var q := p
		var how := "as is"
		for s: Array in sides:
			if t >= float(s[0]) and t <= float(s[1]):
				q = _on_pavement(p, yaw, String(s[2]), String(s[3]))
				how = "%s of %s" % [s[2], s[3]]
		var asphalt: bool = not g._off_road(q, 0.0)
		if asphalt:
			on_road += 1
		print("%6.1f s  moved %4.1f m  %-24s %s" % [t, q.distance_to(p), how, "ON THE ROAD" if asphalt else ""])
		out.append([t, q.x, q.y, yaw])
	var walk: Array = []
	for o: Array in out:
		walk.append([snappedf(o[0], 0.01), snappedf(o[1], 0.01), snappedf(o[2], 0.01)])
	var f := FileAccess.open(OS.get_environment("OUT") + "/walk.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"points": walk}))
	f.close()
	# each stretch outside the spans: where it leaves one kerb and reaches the other
	var i := 0
	while i < out.size():
		if g._off_road(Vector2(out[i][1], out[i][2]), 0.0):
			i += 1
			continue
		var j := i
		while j < out.size() and not g._off_road(Vector2(out[j][1], out[j][2]), 0.0):
			j += 1
		var k0 := maxi(i - 1, 0)
		var k1 := mini(j, out.size() - 1)
		print("crossing: %.1f-%.1f s, kerb %s -> kerb %s" % [out[k0][0], out[k1][0],
			Vector2(out[k0][1], out[k0][2]).snappedf(0.01), Vector2(out[k1][1], out[k1][2]).snappedf(0.01)])
		i = j
	print("%d of %d points on a road's asphalt" % [on_road, out.size()])
	quit(0)
