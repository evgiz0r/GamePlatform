extends SceneTree
## Cars' lights and moving parts up close (CAR_SHADER's lamps, traffic.gd's _custom): one
## traffic car staged 14 m ahead of the start and shot by day and by night --
##   front: its running lights, its left indicator lit, its front wheels turned left
##   back:  braking, reversing, its right indicator lit, the third brake light
##   door:  stood at the kerb, its passenger's door open, someone at it (from behind, the
##          pavement side)
##   steer: its front wheels turned, from the side
##   taxi:  a taxi's roof sign, front three quarters
## (shots lights_*.png in $OUT; the game frozen, the car's state set by hand).
##   FULL=1 STREETS_BUILD_ALL=0 RES=1280x720 OUT=<dir> game/streets/tests/run.sh car_lights 1
var g: Node
var t   ## the traffic (a RefCounted, not a node)

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

## car i put at p facing yaw, as kind, its state set (blink -1 left, 1 right, 2 both)
func _stage(c, i: int, kind: String, p: Vector2, yaw: float) -> void:
	(t._mms[c.kind] as MultiMesh).set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
	c.kind = kind
	c.alive = true
	c.pos = p
	c.prev_pos = p
	c.yaw = yaw
	c.prev_yaw = yaw
	c.pitch = 0.0
	c.dip = 0.0
	c.roll = 0.0
	c.y = float(g._h(p))
	c.prev_y = c.y
	c.blink = 0
	c.braking = 0.0
	c.rev_t = 0.0
	c.door = 0.0
	c.steer = 0.0
	c.stood = false
	c.passenger = false
	c.paint = g._car_paints()[4]   # (silver)

## the traffic clock set so car i's indicator is in the lit half of its flash
func _lit(i: int) -> void:
	t._clock = fposmod(0.1 - float(i) * 0.13, 0.7) + 7.0

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	t = g._traffic
	g.set_physics_process(false)
	process_frame.disconnect(g._frame)   # (frozen: its own camera would move ours back)
	var fw: Vector2 = g._fwd()
	var side := Vector2(-fw.y, fw.x)
	var at: Vector2 = g._pos + fw * 14.0
	var yaw := atan2(fw.x, fw.y)
	var i := 0
	var c = t.cars[i]
	var right := Vector2(-cos(yaw), sin(yaw))   # (the car's -X)
	var fwd := Vector2(sin(yaw), cos(yaw))
	for night: bool in [false, true]:
		g._set_night(night)
		var tag := "night" if night else "day"
		# front: facing the camera, indicating left, its wheels turned left
		_stage(c, i, "sedan", at, yaw + PI)
		c.blink = -1
		c.steer = 0.4
		_lit(i)
		t.draw(1.0)
		var front: Vector2 = at - fw * 5.5 + side * 1.6
		g.look_from(Vector3(front.x, c.y + 1.2, front.y), Vector3(at.x, c.y + 0.6, at.y))
		g._sky_follow()
		await _snap("lights_front_" + tag)
		# back: braking, reversing, indicating right
		_stage(c, i, "hatch", at, yaw)
		c.blink = 1
		c.braking = 1.0
		c.rev_t = 1.0
		_lit(i)
		t.draw(1.0)
		var back: Vector2 = at - fw * 5.0 - side * 1.2
		g.look_from(Vector3(back.x, c.y + 1.2, back.y), Vector3(at.x, c.y + 0.7, at.y))
		g._sky_follow()
		await _snap("lights_back_" + tag)
	g._set_night(false)
	# the door: someone at the open passenger door, seen from behind on the pavement side
	_stage(c, i, "sedan", at, yaw)
	c.stood = true
	c.door = 1.0
	var dc: Vector2 = g._door_at("sedan")
	var stand: Vector2 = at + fwd * (dc.y - 0.55) + right * (dc.x + 0.5)
	g.boarder_at(stand, Vector2(cos(yaw), -sin(yaw)), false)
	t.draw(1.0)
	var eye: Vector2 = at - fwd * 6.0 + right * 3.0
	g.look_from(Vector3(eye.x, c.y + 1.6, eye.y), Vector3(at.x, c.y + 0.8, at.y))
	g._sky_follow()
	await _snap("lights_door")
	g.boarder_gone()
	# the front wheels turned: from the side, low, a car's length off
	_stage(c, i, "hatch", at, yaw)
	c.steer = 0.4
	t.draw(1.0)
	eye = at + fwd * 2.2 + right * 3.2
	g.look_from(Vector3(eye.x, c.y + 0.9, eye.y), Vector3(at.x + fwd.x * 1.2, c.y + 0.4, at.y + fwd.y * 1.2))
	g._sky_follow()
	await _snap("lights_steer")
	# a taxi, front three quarters; then at night
	_stage(c, i, "taxi", at, yaw + PI)
	t.draw(1.0)
	var tx: Vector2 = at - fw * 4.0 - side * 3.0
	g.look_from(Vector3(tx.x, c.y + 2.0, tx.y), Vector3(at.x, c.y + 1.2, at.y))
	g._sky_follow()
	await _snap("lights_taxi")
	g._set_night(true)
	t.draw(1.0)
	await _snap("lights_taxi_night")
	print("shots in ", OS.get_environment("OUT"))
	quit()
