extends SceneTree
## Street fronts: what stands along a residential pavement -- the motorbikes and scooters
## parked up on it, the wooden board fences on the garden walls -- seen from someone walking
## past. Finds the N (default 3) of each nearest the start, stands the camera on the pavement
## 5 m short of it at chest height looking along the street, and saves moto_<i>.png and
## planks_<i>.png. Prints how many of each the city has.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	g.view.get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the camera where people walk (the back half of the pavement) `back` metres short of `at`
## along the street, looking at it
func _look_at(at: Vector2, back: float) -> void:
	var hit: Dictionary = g._nearest_seg(at, 20.0, true, true)
	var from := at
	if not hit.is_empty():
		var r: Dictionary = g._roads[hit["road"]]
		var pts: PackedVector2Array = r["pts"]
		var along: Vector2 = (pts[hit["seg"] + 1] - pts[hit["seg"]]).normalized()
		var out: Vector2 = (at - Vector2(hit["q"])).normalized()
		from = Vector2(hit["q"]) + out * (float(r["w"]) * 0.5 + 2.0) - along * back
	var yaw := (at - from).angle()
	for i in 12:
		g._pos = from
		g._prev_pos = from
		g._yaw = yaw
		g._v = 0.0
		await process_frame

func _nearest(list: PackedVector2Array, p: Vector2, n: int) -> Array:
	var all: Array = []
	for q: Vector2 in list:
		all.append(q)
	all.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_to(p) < b.distance_to(p))
	var out: Array = []
	for q: Vector2 in all:
		if out.size() >= n:
			break
		var apart := true
		for o: Vector2 in out:
			if o.distance_to(q) < 40.0:   # different stretches, not three of one row
				apart = false
		if apart:
			out.append(q)
	return out

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.35,0,-6")
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._car.visible = false
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 3
	var start: Vector2 = g._pos
	print("motorbikes parked on pavements: %d, wooden fence pieces on garden walls: %d" % [g._moto_at.size(), g._plank_at.size()])
	var i := 0
	for p: Vector2 in _nearest(g._moto_at, start, n):
		await _look_at(p, 5.0)
		await _snap("moto_%d" % i)
		i += 1
	i = 0
	for p: Vector2 in _nearest(g._plank_at, start, n):
		await _look_at(p, 6.0)
		await _snap("planks_%d" % i)
		i += 1
	quit(0)
