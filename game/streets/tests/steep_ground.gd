extends SceneTree
## Ground too steep to drive up is a wall (STEEP in streets.gd): in the made-up test town
## (level 4), whose valley is ringed by mountains, the car is put at the town's edge facing
## straight out, eight ways round, and driven at it flat out for 25 s. Prints how far past
## the edge it got and what stopped it. Good: 30-70 m past the edge, stopped by "steep
## ground" (or a tree); the one exception is a start that lands on the mountain road,
## which climbs to the lookout terrace (about 130 m past the edge) and ends there.
var g: Node
const DIRS := [0.0, 0.7, 1.57, 2.4, 3.3, 4.0, 4.71, 5.5]

class Gas:
	func pressed(a: String) -> bool:
		return a == "move_up"

func _initialize() -> void:
	_run()

func _beyond(p: Vector2) -> float:   # metres past the town's limits (tools/fake_city.py: 720 x 560, power 4)
	var r := p.length()
	return r - r / pow(pow(absf(p.x / 720.0), 4) + pow(absf(p.y / 560.0), 4), 0.25)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	print("steep ground in this city: ", g._steep)
	root.get_node("PInput").bot = Gas.new()
	for a: float in DIRS:
		if g._auto:
			g._set_auto(false)
		var u := Vector2(cos(a), sin(a))
		var p := u * (_beyond(u * 1000.0) * -1.0 + 1000.0 + 10.0)
		for k in range(30):   # on open ground, clear of buildings
			if g._push_out(p, 2.0, true) == Vector2.ZERO:
				break
			p += u * 2.0
		g._pos = p
		g._yaw = a
		g._v = 0.0
		g._snap_pose()
		var best := -INF
		var t := 0.0
		while t < 25.0:
			await physics_frame
			t += 1.0 / 60.0
			best = maxf(best, _beyond(g._pos))
		print("way %.2f: %.0f m past the edge, %.0f m up, last hit %s" % [a, best, g._h(g._pos), g._last_hit])
	quit()
