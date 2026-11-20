extends SceneTree
## Streets over open holes: every drivable road on the ground, sampled every 2 m along its
## middle and both edges of its asphalt, asking what a car there stands on
## (`_decks.surf(p, ground)`). Over a cutting the ground is cut away and `surf` gives the
## cutting's road -- so a street at grade that crosses one is a hole a car falls through
## (a car on Kaplan dropped into the Lova Eliav tunnel's cutting under its outer lanes and
## hit the tunnel's wall). Prints each street with points over a hole, and where.
##
##   LEVEL=7 $GODOT --headless --path . -s res://game/streets/tests/street_holes.gd
##
## Good: 0 points over a hole.
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
	var where := {}   # street -> [count, first point, depth]
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
					if under < ground - 0.5:
						holes += 1
						var nm := String(r["en"] if r["en"] != "" else r["name"])
						if not where.has(nm):
							where[nm] = [0, p, ground - under]
						where[nm][0] = int(where[nm][0]) + 1
				s += 2.0
	for nm: String in where:
		print("  %s: %d points over a hole, first at (%.0f, %.0f), %.1f m down" % [nm, where[nm][0], where[nm][1].x, where[nm][1].y, where[nm][2]])
	print("street_holes: %d points over a hole of %d sampled on the streets" % [holes, samples])
	quit()
