extends GameMode3D
## drive_by -- you are in a car, looking out of the side window. The street rolls past at
## the car's speed (which changes: traffic, open road), buildings with goblins perched on
## their windowsills and roofs. Tap a goblin to shoot it. Every goblin that slides out of
## view alive costs a life. People on the sidewalk are NOT targets. See GAME.md.
##
## A rail shooter on GameMode3D: the camera never moves, the world scrolls past it.
## Everything on the street is in _scroll (moves at car speed) or _far (parallax).

const FACADE_Z := -13.0              ## front face of the buildings
const WALK_Z := -11.0                ## sidewalk, where people stroll
const CREATURE_Z := FACADE_Z + 0.55  ## goblins stand just in front of the facades
const SPAWN_X := 21.0                ## off screen to the right ...
const GONE_X := -17.0                ## ... and gone on the left
const STRIP_END := 32.0              ## how far ahead the street is built
const BASE_SPEED := 5.0              ## car speed at the start, units per second ...
const MAX_SPEED := 11.0              ## ... and after SPEED_RAMP seconds
const SPEED_RAMP := 100.0
const CREATURE_EVERY := 2.0          ## seconds between goblins at the start ...
const CREATURE_EVERY_MIN := 0.75     ## ... and after CREATURE_RAMP seconds
const CREATURE_RAMP := 90.0
const PEOPLE_EVERY := 2.6
const AIM_ASSIST := 70.0             ## a tap this close (screen px) to a goblin hits it -- thumbs are wide
const CROSS_ASSIST := 130.0          ## the crosshair (keys / pad / bots) snaps harder: it only aims sideways well
const PERSON_HIT := 30.0
const CROSS_SPEED := 300.0           ## crosshair speed on the keys / stick, px per second
const COMBO_WINDOW := 1.3            ## a kill this soon after the last one chains
const GOBLIN_H := 1.7
const PERSON_H := 1.8
const START_LIVES := 3
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const SHOPS := ["building-a", "building-b", "building-c", "building-d", "building-e", "building-f", "building-g", "building-h"]
const TOWERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c"]
const GOBLINS := ["Goblin_Male", "Goblin_Female"]
const PEOPLE := ["Casual_Male", "Casual_Female", "Casual2_Male", "Casual2_Female", "Casual3_Female"]

var _speed := BASE_SPEED
var _traffic := 0.0                  ## seconds left of a slow-down
var _next_traffic := 9.0
var _scroll: Array = []              ## Node3D moving at car speed; freed past GONE_X (buildings by their width)
var _far: Array = []                 ## {node, k} parallax layers: k = fraction of car speed
var _creatures: Array = []           ## Actor3D, meta: alive
var _people: Array = []              ## Actor3D, meta: dir, speed
var _strip_x := -19.0                ## where the next building goes
var _cross: Blob                     ## crosshair; the bots' "@"
var _gun: Polygon2D
var _flash: Blob
var _tracer: Line2D
var _creature_t := 1.5
var _people_t := 0.5
var _combo := 0
var _combo_t := 0.0
var _t := 0.0
var _sfx_was := 0.8

func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)

func _ready() -> void:
	title = "drive by"
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	set_lives(START_LIVES)
	cam.fov = 58.0
	_aim_camera(0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50.0
	sun.rotation_degrees = Vector3(-42, 24, 0)
	_build_street()
	_build_car()
	for i in 3:
		_spawn_person()
	Probe.event("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

func _aim_camera(bob: float) -> void:
	look_from(Vector3(0, 1.55 + bob, 0), Vector3(0, 4.2 + bob, FACADE_Z))

## ---- the street ------------------------------------------------------------------

func _build_street() -> void:
	# road under the car, kerb, sidewalk in front of the buildings
	_plane(Vector2(140, 14), Vector3(0, 0, -4.0), "bg", 0.0)
	_plane(Vector2(140, 3.2), Vector3(0, 0.02, FACADE_Z + 1.6), "bg_alt", 0.2)
	var kerb := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(140, 0.12, 0.15)
	km.material = mat("accent", 0.8)
	kerb.mesh = km
	kerb.position = Vector3(0, 0.06, FACADE_Z + 3.2)
	world.add_child(kerb)
	# lane markings scroll too, so the road reads as moving even with nothing else in view
	for i in 16:
		var dash := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(2.0, 0.02, 0.14)
		dm.material = mat("ink", 0.4)
		dash.mesh = dm
		dash.position = Vector3(-19.0 + i * 3.5, 0.02, -7.0)
		dash.set_meta("w", 3.5)
		dash.set_meta("dash", true)
		world.add_child(dash)
		_scroll.append(dash)

	# the near row of buildings, built ahead until STRIP_END; recycled as it passes
	while _strip_x < STRIP_END:
		_add_building()

	# a far skyline and clouds, moving slower (parallax), wrapping around
	var fx := -36.0
	while fx < 44.0:
		var b := model(TOWERS[randi() % TOWERS.size()] if randf() < 0.5 else SHOPS[randi() % SHOPS.size()], randf_range(9.0, 17.0))
		b.position = Vector3(fx, 0, -30.0)
		world.add_child(b)
		var w: float = (b.get_meta("aabb") as AABB).size.x
		_far.append({"node": b, "k": 0.3, "w": w, "wrap": 80.0})
		fx += w + randf_range(0.2, 1.5)
	for i in 7:
		var c := Node3D.new()
		for j in 3:
			var puff := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = randf_range(1.2, 2.2)
			sm.height = sm.radius * 1.4
			sm.material = mat("ink", 0.25, 1.0)
			puff.mesh = sm
			puff.position = Vector3(j * 1.6 - 1.6, randf_range(-0.2, 0.3), 0)
			c.add_child(puff)
		c.position = Vector3(-36.0 + i * 11.0, randf_range(14.0, 21.0), randf_range(-42.0, -36.0))
		world.add_child(c)
		_far.append({"node": c, "k": 0.1, "w": 4.0, "wrap": 80.0})

func _plane(size: Vector2, at: Vector3, role: String, emission: float) -> void:
	var p := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.material = mat(role, emission, 1.0)
	p.mesh = pm
	p.position = at
	world.add_child(p)

func _add_building() -> void:
	var tower := randf() < 0.25
	var name: String = TOWERS[randi() % TOWERS.size()] if tower else SHOPS[randi() % SHOPS.size()]
	var b := model(name, randf_range(9.0, 12.0) if tower else randf_range(4.5, 7.5))
	var box: AABB = b.get_meta("aabb")
	b.position = Vector3(_strip_x + box.size.x * 0.5, 0, FACADE_Z - box.size.z * 0.5)
	b.set_meta("w", box.size.x)
	b.set_meta("h", box.size.y)
	world.add_child(b)
	_scroll.append(b)
	_strip_x += box.size.x + 0.3
	# something on the sidewalk between buildings now and then: a tree or a street light
	var roll := randf()
	if roll < 0.45:
		var tree := model("tree-large" if randf() < 0.5 else "tree-small", randf_range(2.4, 3.6))
		tree.position = Vector3(_strip_x - 0.15, 0, WALK_Z - 0.9)
		tree.rotation.y = randf() * TAU
		tree.set_meta("w", 1.0)
		world.add_child(tree)
		_scroll.append(tree)
	elif roll < 0.7:
		var lamp := model("light-square", 4.2)
		lamp.position = Vector3(_strip_x - 0.15, 0, FACADE_Z + 3.0)
		lamp.set_meta("w", 0.5)
		world.add_child(lamp)
		_scroll.append(lamp)

## The building whose facade spans world x, or null.
func _building_at(x: float) -> Node3D:
	for n: Node3D in _scroll:
		if not n.has_meta("h"):
			continue
		var w: float = n.get_meta("w")
		if absf(n.position.x - x) <= w * 0.5 - 0.4:
			return n
	return null

## ---- car interior (2D, drawn over the view) ---------------------------------------

func _build_car() -> void:
	var dark := Palette.col("bg").darkened(0.35)
	var trim := Palette.col("bg_alt")
	# window pillars, roof line and the door sill / dashboard
	for pts in [
			PackedVector2Array([Vector2(0, 0), Vector2(46, 0), Vector2(22, 360), Vector2(0, 360)]),
			PackedVector2Array([Vector2(640, 0), Vector2(594, 0), Vector2(618, 360), Vector2(640, 360)]),
			PackedVector2Array([Vector2(0, 0), Vector2(640, 0), Vector2(640, 22), Vector2(0, 22)]),
			PackedVector2Array([Vector2(0, 360), Vector2(0, 318), Vector2(200, 306), Vector2(440, 306), Vector2(640, 318), Vector2(640, 360)])]:
		var p := Polygon2D.new()
		p.polygon = pts
		p.color = dark
		add_child(p)
	var sill := Polygon2D.new()
	sill.polygon = PackedVector2Array([Vector2(0, 318), Vector2(200, 306), Vector2(440, 306), Vector2(640, 318), Vector2(640, 322), Vector2(440, 310), Vector2(200, 310), Vector2(0, 322)])
	sill.color = trim
	add_child(sill)
	# the gun, bottom right, pointing out of the window
	_gun = Polygon2D.new()
	_gun.polygon = PackedVector2Array([Vector2(520, 360), Vector2(556, 360), Vector2(470, 262), Vector2(452, 276)])
	_gun.color = trim.darkened(0.2)
	add_child(_gun)
	_flash = Blob.new()
	_flash.role = "warn"
	_flash.radius = 13.0
	_flash.shape = "diamond"
	_flash.position = Vector2(461, 269)
	_flash.visible = false
	add_child(_flash)
	_tracer = Line2D.new()
	_tracer.width = 2.5
	_tracer.default_color = Palette.col("warn")
	_tracer.visible = false
	add_child(_tracer)
	# crosshair: where the keys / stick aim and where the bots aim. Taps aim by themselves.
	_cross = Blob.new()
	_cross.role = "player"
	_cross.radius = 7.0
	_cross.shape = "diamond"
	_cross.glow = true
	_cross.position = Vector2(340, 170)
	_cross.modulate.a = 0.75
	add_child(_cross)
	Probe.track(_cross, "@")

	var hint := Label.new()
	hint.text = "tap the goblins   ·   arrows aim, A shoots   ·   not the people"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Palette.col("ink"))
	hint.modulate.a = 0.7
	hint.position = Vector2(10, 338)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

## ---- goblins and people ------------------------------------------------------------

func _spawn_creature() -> void:
	var b := _building_at(SPAWN_X)
	if b == null:
		return
	var h: float = b.get_meta("h")
	var g := Actor3D.new()
	world.add_child(g)
	g.set_character(GOBLINS[randi() % GOBLINS.size()], GOBLIN_H, "hazard")
	# a windowsill somewhere up the facade, or the roof
	var y := h if randf() < 0.3 else randf_range(1.2, maxf(1.3, minf(h - 1.0, 6.5)))
	g.position = Vector3(SPAWN_X, y, CREATURE_Z if y < h else FACADE_Z - 0.6)
	g.face(Vector3(0, 0, 1))
	g.play("Idle" if randf() < 0.6 else "Punch", true, randf_range(0.9, 1.3))
	g.set_meta("alive", true)
	g.set_meta("w", 0.6)
	_creatures.append(g)
	_scroll.append(g)
	track3d(g, "x", true)
	Probe.event("creature_spawn")

func _spawn_person() -> void:
	var p := Actor3D.new()
	world.add_child(p)
	p.set_character(PEOPLE[randi() % PEOPLE.size()], PERSON_H, "friend")
	var dir := 1.0 if randf() < 0.5 else -1.0
	var speed := randf_range(1.0, 1.9)
	p.position = Vector3(SPAWN_X if _t > 0.5 else randf_range(-8.0, 8.0), 0, WALK_Z + randf_range(-0.4, 0.4))
	p.set_meta("dir", dir)
	p.set_meta("speed", speed)
	p.set_meta("w", 0.6)
	p.face(Vector3(dir, 0, 0))
	p.play("Walk", true, speed / 1.7)
	_people.append(p)
	Probe.event("person_spawn")

## ---- shooting -------------------------------------------------------------------------

func _shoot(at: Vector2, assist: float = AIM_ASSIST) -> void:
	if finished:
		return
	_cross.position = at
	Audio.play("hit", 0.15)
	_flash.visible = true
	_tracer.points = PackedVector2Array([_flash.position, at])
	_tracer.visible = true
	_tracer.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_tracer, "modulate:a", 0.0, 0.14)
	tw.tween_callback(func(): _tracer.visible = false; _flash.visible = false)
	shake3d(1.2)
	Probe.event("shot")

	# nearest live goblin within the aim-assist circle (or its own on-screen size)
	var best: Actor3D = null
	var best_d := INF
	for g: Actor3D in _creatures:
		if not g.get_meta("alive"):
			continue
		var sp := to_screen(g.global_position + Vector3(0, GOBLIN_H * 0.5, 0))
		var px := absf(to_screen(g.global_position + Vector3(0, GOBLIN_H, 0)).y - to_screen(g.global_position).y)
		var d := at.distance_to(sp)
		if d < maxf(assist, px * 0.8) and d < best_d:
			best_d = d
			best = g
	if best != null:
		_kill(best)
		return
	for p: Actor3D in _people:
		var sp := to_screen(p.global_position + Vector3(0, PERSON_H * 0.5, 0))
		if at.distance_to(sp) < PERSON_HIT:
			_oops(p)
			return
	_combo = 0
	Probe.event("miss")

func _kill(g: Actor3D) -> void:
	g.set_meta("alive", false)
	_combo = _combo + 1 if _combo_t > 0.0 else 1
	_combo_t = COMBO_WINDOW
	var pts := 10 * _combo
	add_score(pts)
	Probe.event("kill", {"combo": _combo})
	if _combo > 1:
		Probe.event("combo")
	var sp := to_screen(g.global_position + Vector3(0, GOBLIN_H + 0.4, 0))
	Juice.text(self, sp, "+%d" % pts + ("  x%d!" % _combo if _combo > 1 else ""),
		Palette.col("warn" if _combo > 1 else "ink"))
	Audio.play("explode" if _combo > 1 else "impact_punch")
	hit3d(2.5)
	_debris(g.global_position + Vector3(0, GOBLIN_H * 0.6, 0), "hazard", 6)
	if not g.play("Death", false, 1.5):
		g.scale = Vector3(1.3, 0.1, 1.3)
	var tw := g.create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(g, "position:y", g.position.y - 2.5, 0.6)
	tw.tween_callback(func(): _creatures.erase(g); _scroll.erase(g); g.queue_free())

func _oops(p: Actor3D) -> void:
	add_score(-5)
	Probe.event("oops")
	Juice.text(self, to_screen(p.global_position + Vector3(0, PERSON_H + 0.3, 0)), "oops! -5", Palette.col("hazard"))
	Audio.play("hurt")
	p.play("RecieveHit", false, 1.2)
	get_tree().create_timer(0.7).timeout.connect(func():
		if is_instance_valid(p):
			p.play("Walk", true, p.get_meta("speed") / 1.7))

func _escaped(g: Actor3D) -> void:
	g.set_meta("alive", false)
	_creatures.erase(g)
	_scroll.erase(g)
	g.queue_free()
	Probe.event("escaped")
	Juice.text(self, Vector2(60, 150), "one got away!", Palette.col("hazard"))
	shake3d(2.5)
	lose_life()

func _debris(at: Vector3, role: String, n: int) -> void:
	for i in n:
		var d := RigidBody3D.new()
		d.mass = 0.2
		var s := randf_range(0.12, 0.26)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * s
		bm.material = mat(role, 0.9)
		mi.mesh = bm
		d.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * s
		cs.shape = bs
		d.add_child(cs)
		world.add_child(d)
		d.global_position = at + Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3))
		d.linear_velocity = Vector3(randf_range(-3, 3), randf_range(3, 7), randf_range(1, 5))
		d.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		get_tree().create_timer(1.2).timeout.connect(d.queue_free)

## ---- per frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	_combo_t -= delta
	if _combo_t <= 0.0:
		_combo = 0

	# the car: a slow ramp, a gentle wave, and now and then traffic that halves it
	_next_traffic -= delta
	if _next_traffic <= 0.0:
		_traffic = randf_range(2.0, 4.0)
		_next_traffic = randf_range(9.0, 16.0)
	_traffic -= delta
	var target := lerpf(BASE_SPEED, MAX_SPEED, clampf(_t / SPEED_RAMP, 0.0, 1.0))
	target *= 1.0 + 0.3 * sin(_t * 0.35)
	if _traffic > 0.0:
		target *= 0.45
	_speed = lerpf(_speed, target, 1.0 - exp(-delta * 1.2))
	_aim_camera(sin(_t * 9.0) * 0.012 * (_speed / MAX_SPEED))

	# scroll the street; recycle what has passed; build the road ahead
	var dx := _speed * delta
	for n: Node3D in _scroll.duplicate():
		n.position.x -= dx
		var w: float = n.get_meta("w") if n.has_meta("w") else 1.0
		if n.position.x + w * 0.5 < GONE_X:
			if n.has_meta("dash"):
				n.position.x += 16 * 3.5
				continue
			if n is Actor3D:
				if n.get_meta("alive"):
					_escaped(n)
				continue   # a dead goblin is cleaned up by its own death tween
			_scroll.erase(n)
			n.queue_free()
	_strip_x -= dx
	while _strip_x < STRIP_END:
		_add_building()
	for f in _far:
		var n: Node3D = f["node"]
		n.position.x -= dx * f["k"]
		if n.position.x + f["w"] * 0.5 < -40.0:
			n.position.x += f["wrap"]

	# people stroll along the sidewalk at their own pace on top of the scroll
	for p: Actor3D in _people.duplicate():
		p.position.x += (p.get_meta("dir") * p.get_meta("speed") - _speed) * delta
		if p.position.x < GONE_X - 2.0 or p.position.x > SPAWN_X + 6.0:
			_people.erase(p)
			p.queue_free()

	_creature_t -= delta
	if _creature_t <= 0.0:
		_creature_t = lerpf(CREATURE_EVERY, CREATURE_EVERY_MIN, clampf(_t / CREATURE_RAMP, 0.0, 1.0))
		_spawn_creature()
	_people_t -= delta
	if _people_t <= 0.0 and _people.size() < 6:
		_people_t = PEOPLE_EVERY
		_spawn_person()

	# keys / stick / bots aim the crosshair; A fires
	var d := PInput.dir()
	if d != Vector2.ZERO:
		_cross.position = (_cross.position + d * CROSS_SPEED * delta).clamp(Vector2(30, 30), Vector2(610, 300))
	if PInput.just_pressed("action_a"):
		_shoot(_cross.position, CROSS_ASSIST)

func _input(e: InputEvent) -> void:
	if finished:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if Flow.pointer_over_hud():
			return
		_shoot(e.position)
