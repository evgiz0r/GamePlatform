extends SceneTree
## Streets over open holes: every drivable road on the ground, sampled every 2 m along its
## middle and both edges of its asphalt, asking what a car there stands on
## (`_decks.surf(p, ground)`). Over a cutting the ground is cut away and `surf` gives the
## cutting's road -- so a street at grade that crosses one is a hole a car falls through
## (a car on Kaplan dropped into the Lova Eliav tunnel's cutting under its outer lanes and
## hit the tunnel's wall). And whether a deck's wall stands there, solid at street level
## (`_decks.push`: a cutting's wall where it starts at a street's kerb stopped a car on the
## street). Prints each street with points over a hole or in a wall, and where.
##
##   LEVEL=7 $GODOT --headless --path . -s res://game/streets/tests/street_holes.gd
##
## Good: 0 points over a hole, 0 in a wall.
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 7
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var samples := 0
	var holes := 0
	var walled := 0
	var where := {}   # street -> [count, first point, depth]
	var walls := {}   # street -> [count, first point]
	for r: Dictionary in g._roads:
		if not r["drive"] or r.has("ys"):
			continue
		var pts: PackedVector2Array = r["pts"]
		var hw := float(r["w"]) * 0.5 - 0.5
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.01:
				continue
			var d := (b - a) / L
			var side := Vector2(-d.y, d.x)
			var s := 0.0
			while s <= L:
				for off: float in [-hw, 0.0, hw]:
					var p := a + d * s + side * off
					var ground: float = g._h(p)
					var under: float = g._decks.surf(p, ground)
					samples += 1
					if g._decks.push(p, 0.3, ground + 0.3) != Vector2.ZERO:
						walled += 1
						var wn := String(r["en"] if r["en"] != "" else r["name"]) + " (" + _wall_kind(p, ground + 0.3) + ")"
						if not walls.has(wn):
							walls[wn] = [0, p]
						walls[wn][0] = int(walls[wn][0]) + 1
					if under < ground - 0.5:
						holes += 1
						var nm := String(r["en"] if r["en"] != "" else r["name"])
						if not where.has(nm):
							where[nm] = [0, p, ground - under]
						where[nm][0] = int(where[nm][0]) + 1
				s += 2.0
	for nm: String in where:
		print("  %s: %d points over a hole, first at (%.0f, %.0f), %.1f m down" % [nm, where[nm][0], where[nm][1].x, where[nm][1].y, where[nm][2]])
	for nm: String in walls:
		print("  %s: %d points in a deck's wall, first at (%.0f, %.0f)" % [nm, walls[nm][0], walls[nm][1].x, walls[nm][1].y])
	print("street_holes: %d points over a hole, %d in a deck's wall, of %d sampled on the streets" % [holes, walled, samples])
	quit()

## what kind of deck wall stands at p for a body at y: a parapet, a bank's foot, a pier...
func _wall_kind(p: Vector2, y: float) -> String:
	for i: int in g._near(g._decks._wall_hash, p, 1.0, g._decks.CELL):
		var w: Array = g._decks._walls[i]
		var q := Geometry2D.get_closest_point_to_segment(p, w[0], w[1])
		if q.distance_to(p) < float(w[6]) + 0.3:
			return String(w[7])
	return "?"
