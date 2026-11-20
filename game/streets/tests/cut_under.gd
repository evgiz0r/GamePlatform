extends SceneTree
## Cuttings (open trenches, `cu`) whose middle line passes under a street at grade: each one
## is a trench through the street, its railings across the lanes -- what a user saw across
## Tel Aviv's Kaplan ("weird borders"), where a 19 m piece of the Lova Eliav tunnel, too
## short alone for a tunnel, was put on the ground between two tunnel pieces and dug as a
## cutting. Counted only where it is a metre deep or more (where its railing stands), not where
## it comes up to the street it ends at. Expect 0; also prints the tunnels and cuttings near AT
## (x,z; optional).
##   tests/run.sh cut_under 7
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
	var at := Vector2.INF
	if OS.get_environment("AT") != "":
		var xz := OS.get_environment("AT").split(",")
		at = Vector2(float(xz[0]), float(xz[1]))
	var cuts := 0
	var under := 0
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		var kind := String(r.get("deck", ""))
		if kind not in ["cu", "tu"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		if at != Vector2.INF:
			for p in pts:
				if p.distance_to(at) < 40.0:
					print("  near: %s '%s' (%s) %s" % [kind, r["name"], r["k"], Array(pts).map(func(q): return q.round())])
					break
		if kind != "cu":
			continue
		cuts += 1
		var hit := Vector2.INF
		for j in range(pts.size() - 1):
			var L := pts[j].distance_to(pts[j + 1])
			var s := 0.0
			while s <= L and hit == Vector2.INF:
				var p := pts[j].lerp(pts[j + 1], s / maxf(L, 0.001))
				# (deep enough for its railing -- a metre -- not its end coming up to the street it joins)
				if g._decks._street_over(p) and g._h(p) - g._decks.deck_y(ri, p) > 1.0:
					hit = p
				s += 1.0
		if hit != Vector2.INF:
			under += 1
			print("  cutting '%s' (%s) runs under a street at %s" % [r["name"], r["k"], hit.round()])
	print("cuttings: %d, under a street at grade: %d" % [cuts, under])
	quit(0)
