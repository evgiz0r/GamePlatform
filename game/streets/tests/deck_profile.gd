extends SceneTree
## The heights decks.gd works out for the lifted roads near a spot, with and without the
## rounding at their joints (_round_joints): along each deck within REACH m of AT, metre by
## metre from its start, the road's height, the ground's and the change of grade between
## points (a crest a car takes off from is a big negative one). No game, no rendering:
## the city's file and Decks.infer() alone, in seconds.
##
##   CITY=ashdod AT=-1060,-640 $GODOT --headless --path . -s res://game/streets/tests/deck_profile.gd
##
## Good: no grade change sharper than about -4% per 6 m with rounding on, at speeds the
## autodrive takes (a bridge's top, a ramp's top, a cutting's lip).
func _initialize() -> void:
	var D = load("res://game/streets/decks.gd")
	var S = load("res://game/streets/streets.gd")
	var city := OS.get_environment("CITY") if OS.get_environment("CITY") != "" else "tel_aviv"
	var at_s := OS.get_environment("AT").split(",")
	var at := Vector2(float(at_s[0]), float(at_s[1]))
	var reach := float(OS.get_environment("REACH")) if OS.get_environment("REACH") != "" else 80.0
	for on: bool in [false, true]:
		D.round_joints = on
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://game/streets/cities/%s.json" % city))
		var info: Dictionary = D.infer(data, S.DRIVE)
		print("\n=== rounding %s: crests %s, cutting tops %s" % ["on" if on else "off", info.get("crests_rounded"), info.get("cutting_tops_eased")])
		var k := 1.0 / float(data.get("scale", 10))
		var nd: Array = data["nodes"]
		var hg: Dictionary = data["height"]
		for r: Dictionary in data["roads"]:
			if not r.has("y"):
				continue
			var ns: Array = r["n"]
			var ys: Array = r["y"]
			var pts: Array = []
			var near := false
			for j in range(ns.size()):
				var p := Vector2(float(nd[int(ns[j]) * 2]), float(nd[int(ns[j]) * 2 + 1])) * k
				pts.append(p)
				near = near or p.distance_to(at) < reach
			if not near:
				continue
			var kind := "br" if r.has("br") else ("tu" if r.has("tu") else ("cu" if r.has("cu") else "em"))
			print("-- %s %s from %s to %s" % [kind, r.get("name", ""), Vector2i(pts[0]), Vector2i(pts[-1])])
			var d := 0.0
			var line := ""
			var prev_g := NAN
			for j in range(ns.size()):
				if j > 0:
					d += (pts[j] as Vector2).distance_to(pts[j - 1])
				var y := float(ys[j]) * k
				var gr := NAN
				if j > 0 and (pts[j] as Vector2).distance_to(pts[j - 1]) > 0.5:
					gr = (y - float(ys[j - 1]) * k) / (pts[j] as Vector2).distance_to(pts[j - 1])
				var dg := gr - prev_g if not is_nan(prev_g) and not is_nan(gr) else 0.0
				line += "  %4.0f m %6.2f (gnd %6.2f) %s%s\n" % [d, y, D._hgt(hg, pts[j], k), ("%+5.1f%%" % (gr * 100.0)) if not is_nan(gr) else "      ",
					("  dg %+5.1f%%" % (dg * 100.0)) if absf(dg) > 0.03 else ""]
				if not is_nan(gr):
					prev_g = gr
			print(line)
	quit()
