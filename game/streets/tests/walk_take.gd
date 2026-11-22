extends SceneTree
## On foot (streets.gd _walk, _get_in): out of the car, 4 s holding forward (the jog), 3 s
## holding forward and the run button (the sprint) -- the speeds reached -- then a car in the
## traffic sent past, stopped beside you, and "drive": do you take it (the banner, the car
## where it stood, it gone from the traffic)?
##   LEVEL=1 STREETS_BUILD_ALL=0 $GODOT --path . -s res://game/streets/tests/walk_take.gd
## PASS: jog 4 m/s or more, sprint 8 or more; the traffic car taken.
var g: Node

class Hold:
	var keys := {}
	func pressed(action: String) -> bool:
		return keys.has(action)

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for nd in root.find_children("*", "Node2D", true, false):
			if nd.get_script() != null and String(nd.get_script().resource_path).ends_with("streets.gd"):
				g = nd
	await create_timer(1.0).timeout
	g._set_quality(0)
	var pin = root.get_node("PInput")
	var hold := Hold.new()
	pin.bot = hold
	g._set_auto(false)
	await create_timer(0.5).timeout
	g._toggle_walk()   # out
	await create_timer(1.0).timeout
	var top := 0.0
	hold.keys = {"move_up": true}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await physics_frame
		top = maxf(top, g._v)
	var jog := top
	hold.keys = {"move_up": true, "action_a": true}
	top = 0.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000:
		await physics_frame
		top = maxf(top, g._v)
	var sprint := top
	hold.keys = {}
	await create_timer(1.0).timeout
	# a car beside you, held there
	var fwd: Vector2 = g._fwd()
	var took := false
	var sent: bool = g._traffic.send((g._pos as Vector2) + Vector2(fwd.y, -fwd.x) * 3.0, fwd, {"kind": "sedan"})
	var car = null
	if sent:
		var bd := INF
		for c in g._traffic.cars:
			if c.alive and (c.pos as Vector2).distance_to(g._pos) < bd:
				bd = (c.pos as Vector2).distance_to(g._pos)
				car = c
		car.hit = 1000.0
		car.v = 0.0
		g._pos = (car.pos as Vector2) + Vector2(sin(car.yaw), cos(car.yaw)).orthogonal() * 2.0
		await physics_frame
		var at: Vector2 = car.pos
		g._toggle_walk()   # in: the nearest car
		await create_timer(0.5).timeout
		took = not g._walking and not car.alive and (g._pos as Vector2).distance_to(at) < 1.0
	pin.bot = null
	print("WALK_TAKE jog %.1f m/s, sprint %.1f m/s, a car sent beside you: %s, taken: %s" % [jog, sprint, sent, took])
	print("WALK_TAKE: %s" % ("PASS" if jog >= 4.0 and sprint >= 8.0 and took else "FAIL"))
	quit(0)
