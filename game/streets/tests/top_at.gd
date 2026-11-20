extends SceneTree
## Shots from above of places by their map point, for matching a user's screenshot to the
## data: AT="x,z;x,z;..." (metres, as the other tests print them), UP metres above the ground
## (default 90), and a shot from a car's height looking at each from the south-west
## (LOW=0 to skip). CAR="x,z,dx,dz;..." also puts the car down there (off the road too),
## facing (dx, dz), and shoots it from the chase camera -- where a user's car stood. Nothing
## measured.   AT="-2370,2290" CAR="-2344,2304,-0.86,-0.5" tests/run.sh top_at 3
var g: Node
func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	var up := float(OS.get_environment("UP")) if OS.get_environment("UP") != "" else 90.0
	var spots: Array = []
	for s: String in OS.get_environment("AT").split(";", false):
		var xz := s.split(",")
		spots.append(Vector2(float(xz[0]), float(xz[1])))
	var cars := OS.get_environment("CAR").split(";", false)
	for i in range(cars.size()):
		var v := cars[i].split(",")
		g._pos = Vector2(float(v[0]), float(v[1]))
		g._yaw = Vector2(float(v[2]), float(v[3])).angle()
		g._v = 0.0
		await create_timer(2.5).timeout
		await _snap("car_%d" % i)
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)
	for i in range(spots.size()):
		var p: Vector2 = spots[i]
		var y: float = g._h(p)
		g.look_from(Vector3(p.x, y + up, p.y + up * 0.35), Vector3(p.x, y, p.y))   # (straight down, the look's basis breaks)
		await _snap("top_%d" % i)
		if OS.get_environment("LOW") != "0":
			var from := p + Vector2(-1, 1).normalized() * 30.0
			g.look_from(Vector3(from.x, g._h(from) + 3.0, from.y), Vector3(p.x, y, p.y))
			await _snap("low_%d" % i)
	quit(0)
