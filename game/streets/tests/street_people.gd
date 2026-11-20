extends SceneTree
## More kinds of people (streets.gd "more kinds of people"): after a while on autodrive from
## the start, who is about -- walkers with a dog, with a pushchair, people on the park
## benches, people waiting at the bus stops -- and a look at the nearest of each from a few
## metres (shots sp_*.png in $OUT), frozen. Good: a dog on a lead a step ahead of its walker,
## a pushchair in front of the hands, a sitter on the seat (not in the air, not in the bench),
## a waiter at the stop facing the road.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _look_at_person(name: String, a: Node3D, back: float, h: float, side: float) -> void:
	var fw: Vector3 = a.global_transform.basis.z   # (the figures face +Z)
	var rt := fw.cross(Vector3.UP)
	var p := a.global_position
	g.look_from(p + fw * back + rt * side + Vector3(0, h, 0), p + fw * 0.5 + Vector3(0, 0.7, 0))
	g._sky_follow()
	await _snap(name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._set_auto(true)
	await create_timer(float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 12.0).timeout
	var counts := {"dog": 0, "pram": 0}
	var first := {}
	for w: Dictionary in g._walkers:
		for k: String in ["dog", "pram"]:
			if w.has(k) and (w["actor"] as Node3D).visible:
				counts[k] += 1
				var a: Node3D = w["actor"]
				if not first.has(k) or a.global_position.distance_to(g.cam.global_position) < (first[k] as Node3D).global_position.distance_to(g.cam.global_position):
					first[k] = a
	var sat := 0
	for c: Dictionary in g._sitters:
		if (c["actor"] as Node3D).visible:
			sat += 1
			if not first.has("sit"):
				first["sit"] = c["actor"]
	var waiting := 0
	for c: Dictionary in g._waiters:
		if (c["actor"] as Node3D).visible:
			waiting += 1
			if not first.has("wait"):
				first["wait"] = c["actor"]
	print("walkers with a dog %d, with a pushchair %d (out now); sitting on benches %d, waiting at stops %d; benches known %d" % [
		counts["dog"], counts["pram"], sat, waiting, g._bench_spots.size()])
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	for k: String in ["dog", "pram", "sit", "wait"]:
		if first.has(k):
			var a: Node3D = first[k]
			print("%s: %d m from the camera" % [k, int(a.global_position.distance_to(g.cam.global_position))])
			await _look_at_person("sp_" + k, a, 1.0, 1.4, 3.0)   # (from the side: what is ahead of them shows)
	quit(0)
