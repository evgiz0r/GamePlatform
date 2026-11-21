extends SceneTree
## Where a divided road's median ends at a junction: the paving there is pieced together --
## each half paves its own half of the median, cut back at its own junction point; the
## crossing's slabs, the islands, the corners' kerbs -- and a user found it "messy a lot of
## times. the geometry doesn't align and it looks weird" (Tel Aviv, a median with railings
## by a zebra). Lists every median end (the half, its median's width, a zebra near or not)
## and shoots N of them (default 8; zebras first, then a spread), each from a driver's height
## coming up the half (end_<i>.png) and from above (end_<i>_top.png). AT=x,z shoots only the
## ends within 40 m of that point.
##   N=8 RES=1280x720 tests/run.sh median_ends 7
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	for i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

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
	await create_timer(1.0).timeout
	var n_shots := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 8
	var at := Vector2.INF
	if OS.get_environment("AT") != "":
		var xz := OS.get_environment("AT").split(",")
		at = Vector2(float(xz[0]), float(xz[1]))
	var zebras: Array = []
	for ni: int in g._crossing_nodes:
		zebras.append(g._nodes[ni])
	# every end of a half's kerbed run at a junction: [where, the way into the junction, road, median, zebra near]
	var ends: Array = []
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r.has("median") or float(r["median"]) < 0.25:
			continue
		for run: PackedVector2Array in g._street_runs(r, g.KERB_CUT, true):
			for k in [0, 1]:
				var e: Vector2 = run[0] if k == 0 else run[run.size() - 1]
				var e2: Vector2 = run[1] if k == 0 else run[run.size() - 2]
				var d := (e - e2).normalized()
				# a junction there (the run was cut short of one), not the road's open end
				var pts: PackedVector2Array = r["pts"]
				var ids: PackedInt32Array = r["ids"]
				var near_j := false
				for i in range(ids.size()):
					if pts[i].distance_to(e) < 25.0 and g._kerb_arms(ids[i]) >= 3:
						near_j = true
				if not near_j:
					continue
				var zeb := false
				for z: Vector2 in zebras:
					if z.distance_to(e) < 18.0:
						zeb = true
				if at != Vector2.INF and e.distance_to(at) > 40.0:
					continue
				ends.append([e, d, ri, float(r["median"]), zeb])
	var with_zebra := ends.filter(func(x): return x[4])
	print("median ends at junctions: %d (%d with a zebra within 18 m)" % [ends.size(), with_zebra.size()])
	seed(3)
	with_zebra.shuffle()
	var rest := ends.filter(func(x): return not x[4])
	rest.shuffle()
	var pick: Array = (with_zebra + rest).slice(0, n_shots)
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	for i in range(pick.size()):
		var e: Vector2 = pick[i][0]
		var d: Vector2 = pick[i][1]
		var r: Dictionary = g._roads[int(pick[i][2])]
		var o := float(r["o"])
		# the median is on the left of the traffic: stand in the half's lanes, right of it
		var travel := d if (d.dot((r["pts"] as PackedVector2Array)[1] - (r["pts"] as PackedVector2Array)[0]) * o) > 0.0 else -d
		var right := Vector2(-travel.y, travel.x)
		var hw := float(r["w"]) * 0.5
		var eye := e - travel * 16.0 + right * (hw * 0.7)
		var look := e + travel * 6.0 - right * 1.0
		var y: float = g._h(e)
		print("end %d: %s on '%s' (%s), median %.1f m, half %.1f m wide, zebra %s" % [i, e.round(), r["name"], r["k"],
			float(pick[i][3]), float(r["w"]), pick[i][4]])
		g.look_from(Vector3(eye.x, g._h(eye) + 2.1, eye.y), Vector3(look.x, y + 0.3, look.y))
		await _snap("end_%d" % i)
		g.look_from(Vector3(e.x, y + 28.0, e.y + 28.0 * 0.35), Vector3(e.x, y, e.y))
		await _snap("end_%d_top" % i)
	quit(0)
