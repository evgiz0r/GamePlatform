extends SceneTree
## People appearing in view: over 90 s of autodrive, every person (walkers, people at the
## crossings, at cafe tables) who shows up or jumps more than 2 m in one frame within the
## distance people are drawn at and in front of the car. And people at crossings by traffic
## lights stepping out while the road's cars had green. Good: 0 and 0.
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
	await create_timer(1.0).timeout
	g._set_auto(true)
	var was := {}
	var pops := {}
	var against_light := 0
	var crossed := 0
	var states := {}
	for f in range(60 * 90):
		await physics_frame
		var actors: Array = []
		for w: Dictionary in g._walkers:
			actors.append(["walker", w["actor"]])
		for c: Dictionary in g._chatters:
			actors.append(["at a table", c["actor"]])
		for c: Dictionary in g._crossers:
			actors.append(["crossing", c["actor"]])
		for e: Array in actors:
			var a: Node3D = e[1]
			var key := a.get_instance_id()
			var p := Vector2(a.position.x, a.position.z)
			var seen: bool = a.visible and not g._unseen(p)
			if seen and was.has(key):
				var prev: Array = was[key]
				if not prev[0] or (prev[1] as Vector2).distance_to(p) > 2.0:
					pops[e[0]] = int(pops.get(e[0], 0)) + 1
			was[key] = [a.visible, p]   # (shown before, or not: coming into range is not a pop)
		for i in range(g._crossers.size()):
			var cr: Dictionary = g._crossers[i]
			var st: String = cr["state"]
			if st == "cross" and states.get(i, "") == "wait":
				crossed += 1
				var n: int = cr.get("sig", -1)
				if n >= 0:
					if g._light_at(n, cr["sig_dir"]) != "r":
						against_light += 1
			states[i] = st
	print("people popping up or jumping in view over 90 s: %s" % (str(pops) if not pops.is_empty() else "none"))
	print("crossings started: %d; stepped out while the road had green or amber: %d" % [crossed, against_light])
	quit(0)
