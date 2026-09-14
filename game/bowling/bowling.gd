extends GameMode3D
## bowling -- a hundred pins on one wide neon lane, ten throws, nobody to beat but your own
## best. Tap where the ball should land: it flies there, lands, rolls on and ploughs into
## the rack. A farther spot is a harder throw; a spot past a wall is a bank shot, because
## the lane has bumpers, not gutters. Real rigid bodies: the ball rolls, the pins tumble,
## scatter and take each other out. Keys and pad: left/right slide the ball along the foul
## line, up/down move the landing spot, A throws -- which is also how the bots play.
## Two games to pick from at the start: the hundred-pin block on a whole lane, or "random
## ground": the lane past the approach is a random patchwork of floor tiles with holes in
## it, twenty pins scattered over the tiles, and a ball that misses the floor is gone.
## The camera looks down the lane from behind and above, so all of it is on screen to tap.

const LANE_W := 6.4                  ## wide: ten pins abreast with room to bank off the walls
const LANE_LEN := 18.0               ## foul line at z=0, the pit starts at z=-LANE_LEN
const APPROACH := 3.0                ## lane surface behind the foul line where the ball waits
const WALL_H := 0.5                  ## the glowing bumper you see; the one that stops the ball is taller
const BALL_R := 0.27
const BALL_MASS := 9.0                 ## a wrecking ball next to the pins
const BALL_START_Z := 1.2
const PIN_H := 0.9
const PIN_R := 0.13                  ## collision cylinder; the drawn pin bulges past it
const PIN_MASS := 0.35                 ## light, so a hundred of them do not stop the ball and a hit one flies
const PIN_COLS := 10                 ## the rack: PIN_COLS x PIN_ROWS in staggered rows
const PIN_ROWS := 10
const PIN_DX := 0.64                 ## between neighbours in a row (a ball cannot squeeze through)
const PIN_DZ := 0.6                  ## between rows
const RACK_FRONT_Z := -12.6          ## the nearest row
const PIT_Z := -LANE_LEN - 1.2       ## anything past here (or under the floor) is gone
const LAUNCH_DEG := 16.0             ## the ball leaves the hand at this angle, always: flat, toward the pins
const SPEED_MIN := 10.0              ## slowest throw -- still rolls all the way to the rack
const SPEED_MAX := 30.0              ## fastest; the speed is solved from where you tapped
const DIST_MIN := 2.0                ## a landing spot closer than this is a tap on the ball, not a throw
const DIST_MAX := 17.0               ## the far end of the rack; keys cannot ask for more
const KEY_DIST_START := 13.0         ## where the keyboard landing spot starts (the front of the rack)
const KEY_DIST_SPEED := 6.0          ## up/down move it this fast, units per second
const SLIDE_SPEED := 3.0             ## foul-line slide on the keys, units per second
const GRAVITY_SCALE := 2.5           ## Earth gravity at this scale looks like the moon
const SETTLE := 0.7                  ## everything quiet this long -> count the pins
const ROLL_TIMEOUT := 7.0            ## a wobbling pin does not get to hold the game up
const RESET_DELAY := 1.0             ## seconds to admire the wreckage before the sweep
const THROWS := 10
const CLEAR_BONUS := 0.5             ## for knocking down every last pin: this times the rack size (then a fresh rack)
const GROUND_PINS := 20              ## random ground: pins scattered over the tiles
const TILE := 1.6                    ## floor tile size; the patchwork is TILE_COLS x TILE_ROWS of them
const TILE_COLS := 4
const TILE_ROWS := 8
const TILE_FRONT_Z := -5.0           ## the approach lane ends here; the tiles start
const TILES_KEPT := 19               ## of 32: enough floor to play on, enough holes to fall in
const BTN_BLOCK := Rect2(110, 150, 200, 64)    ## the rack-choice screen
const BTN_SHAPES := Rect2(330, 150, 200, 64)
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const PHYSICS_HZ := 120              ## a fast ball through thin pins needs it; restored on exit

var _ball: RigidBody3D
var _marker: Node3D                  ## the landing spot on the lane while you aim
var _guide: MeshInstance3D           ## the line from the ball to it
var _target := Vector3.ZERO          ## where the ball will land (world, on the lane)
var _key_dist := KEY_DIST_START      ## landing distance chosen on the keys
var _pins: Array = []                ## RigidBody3D, meta: swept (float, -1 = standing)
var _pin_mm: Array = []              ## [MultiMeshInstance3D, Vector3 offset] per drawn part
var _standing := 0                   ## pins up at the start of this throw
var _throws: Array = []              ## pins knocked per throw, the whole game
var _racks := 0                      ## racks cleared
var _mode := ""                      ## block | ground, chosen on the first screen
var _floor: Array = []               ## the lane surface (and board lines) of the current mode
var _rack_size := 0                  ## pins in a fresh rack of the current mode
var _menu: Node2D                    ## the rack-choice screen
var _menu_pick := 0                  ## 0 = block, 1 = ground (keys move it, A picks)
var _state := "menu"                 ## menu | aim | rolling | reset | over
var _t := 0.0
var _roll_t := 0.0
var _quiet_t := 0.0
var _aim_x := 0.0
var _airborne := false
var _sfx_t := 0.0                    ## throttle for pin clatter
var _cam_pos := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _drag := false
var _strip: Label
var _hint: Label
var _sfx_was := 0.8
var _hz_was := 60

## Set at construction: the shell sizes its backdrop off play_area before _ready runs.
func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-LANE_W * 0.5 - 0.3, -LANE_LEN - 3.2, LANE_W + 0.6, APPROACH + LANE_LEN + 3.2)

func _ready() -> void:
	title = "bowling"
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	_hz_was = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = PHYSICS_HZ
	set_lives(0)   # nothing can hurt you here; the game is ten throws long, that is all
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.rotation_degrees = Vector3(-58, 24, 0)
	cam.fov = 50.0
	_cam_pos = _rest_cam_pos()
	_cam_target = _rest_cam_target()
	look_from(_cam_pos, _cam_target)
	_build_lane()
	_build_ball()
	_build_pin_meshes()
	_build_ui()
	_strip.visible = false
	_hint.visible = false
	_build_menu()
	Probe.event("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was
	Engine.physics_ticks_per_second = _hz_was

## ---- the alley ---------------------------------------------------------------------

func _box(size: Vector3, at: Vector3, m: Material, solid: bool = false, bounce: float = 0.0) -> Node3D:
	var mi: MeshInstance3D = null
	if m != null:
		mi = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = m
		mi.mesh = bm
	if not solid:
		mi.position = at
		world.add_child(mi)
		return mi
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	if mi != null:
		body.add_child(mi)
	if bounce > 0.0:
		var pm := PhysicsMaterial.new()
		pm.bounce = bounce
		pm.friction = 0.2
		body.physics_material_override = pm
	body.position = at
	world.add_child(body)
	return body

func _build_lane() -> void:
	var length := LANE_LEN + APPROACH
	var mid_z := (APPROACH - LANE_LEN) * 0.5
	# the lane surface itself is per mode: _build_floor()
	# bumpers: a glowing rail you see, and a tall invisible wall so a flying ball cannot
	# clear it. Both bounce, so a bank shot comes back with most of its speed.
	for side: float in [-1.0, 1.0]:
		var rx := side * (LANE_W * 0.5 + 0.1)
		_box(Vector3(0.2, WALL_H, length), Vector3(rx, WALL_H * 0.5 - 0.05, mid_z), mat("accent", 0.85), true, 0.7)
		_box(Vector3(0.2, 6.0, length), Vector3(rx, WALL_H + 3.0, mid_z), null, true, 0.7)
		# the neighbouring lanes, dim, so this is an alley and not a plank in space
		_box(Vector3(LANE_W, 0.3, length), Vector3(side * (LANE_W + 0.9), -0.25, mid_z), mat("bg_alt", 0.05, 0.4))
	# foul line and the seven aiming arrows
	_box(Vector3(LANE_W, 0.012, 0.06), Vector3(0, 0.006, 0.0), mat("hazard", 0.9))
	for i in range(-3, 4):
		var ax := i * (LANE_W / 8.0)
		var az := -2.4 - (3 - absi(i)) * 0.4
		_box(Vector3(0.09, 0.012, 0.42), Vector3(ax, 0.006, az), mat("accent", 0.9))
	# the pit: a floor well below the deck so knocked pins tumble out of sight, walled in
	_box(Vector3(LANE_W + 0.8, 0.2, 3.0), Vector3(0, -1.6, -LANE_LEN - 1.5), mat("bg", 0.0), true)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.2, 2.2, 3.0), Vector3(side * (LANE_W * 0.5 + 0.1), -0.6, -LANE_LEN - 1.5), mat("bg_alt", 0.05, 0.4), true)
	# back wall and the masking unit above the pins: a glowing bar and a row of bulbs
	_box(Vector3(LANE_W + 0.8, 5.0, 0.3), Vector3(0, 0.9, -LANE_LEN - 3.0), mat("bg_alt", 0.12), true)
	_box(Vector3(LANE_W + 0.8, 0.9, 0.25), Vector3(0, 2.75, -LANE_LEN - 2.4), mat("bg_alt", 0.3))
	_box(Vector3(LANE_W + 0.8, 0.06, 0.06), Vector3(0, 2.3, -LANE_LEN - 2.28), mat("prize", 0.9))
	_box(Vector3(LANE_W + 0.8, 0.06, 0.06), Vector3(0, 3.2, -LANE_LEN - 2.28), mat("prize", 0.9))
	for i in 15:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		sm.material = mat("accent" if i % 2 == 0 else "warn", 1.0)
		bulb.mesh = sm
		bulb.position = Vector3(-3.5 + i * 0.5, 2.75, -LANE_LEN - 2.25)
		world.add_child(bulb)
	# a wide dark floor under everything: the world has a ground, and whatever falls
	# through a hole in the random one lands on it in plain view
	_box(Vector3(70, 0.2, 70), Vector3(0, -1.9, -8), mat("bg", 0.0, 1.0), true)

## The lane surface for the mode: the whole lane as one polished slab, or the approach
## slab and then a random patchwork of tiles with holes, grown from the approach so it
## is always reachable. Board lines only where there is a whole lane to draw them on.
func _build_floor() -> Array:
	for n in _floor:
		if is_instance_valid(n):
			n.queue_free()
	_floor.clear()
	var cells: Array = []
	if _mode == "ground":
		var length := APPROACH - TILE_FRONT_Z
		var mid_z := (APPROACH + TILE_FRONT_Z) * 0.5
		_floor.append(_box(Vector3(LANE_W, 0.4, length), Vector3(0, -0.2, mid_z), mat("bg_alt", 0.18, 0.22), true, 0.15))
		for i in range(1, 8):
			_floor.append(_box(Vector3(0.02, 0.011, length), Vector3(-LANE_W * 0.5 + i * LANE_W / 8.0, 0.0055, mid_z), mat("ink", 0.02, 0.6)))
		cells = _random_ground()
		for c: Vector2i in cells:
			var at := _tile_centre(c)
			_floor.append(_box(Vector3(TILE, 0.4, TILE), Vector3(at.x, -0.2, at.z), mat("bg_alt", 0.18, 0.22), true, 0.15))
			# a thin glowing lip on every tile edge that faces a hole, so the holes read
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := c + d
				var open: bool = not cells.has(n) and n.x >= 0 and n.x < TILE_COLS and n.y >= 0 and n.y < TILE_ROWS
				if open:
					var lip_size := Vector3(TILE, 0.03, 0.06) if d.x == 0 else Vector3(0.06, 0.03, TILE)
					var lip_at := Vector3(at.x + d.x * (TILE * 0.5 - 0.03), 0.01, at.z - d.y * (TILE * 0.5 - 0.03))
					_floor.append(_box(lip_size, lip_at, mat("warn", 0.8)))
	else:
		var length := LANE_LEN + APPROACH
		var mid_z := (APPROACH - LANE_LEN) * 0.5
		_floor.append(_box(Vector3(LANE_W, 0.4, length), Vector3(0, -0.2, mid_z), mat("bg_alt", 0.18, 0.22), true, 0.15))
		for i in range(1, 8):
			_floor.append(_box(Vector3(0.02, 0.011, length), Vector3(-LANE_W * 0.5 + i * LANE_W / 8.0, 0.0055, mid_z), mat("ink", 0.02, 0.6)))
	return cells

func _tile_centre(c: Vector2i) -> Vector3:
	return Vector3((c.x - (TILE_COLS - 1) * 0.5) * TILE, 0.0, TILE_FRONT_Z - (c.y + 0.5) * TILE)

## TILES_KEPT cells of the TILE_COLS x TILE_ROWS grid (row 0 touches the approach),
## grown from two or three random front-row cells by adding random neighbours. The
## growth wanders and leaves holes behind; sometimes a whole side is missing.
func _random_ground() -> Array:
	var cells: Array = []
	var front: Array = range(TILE_COLS)
	front.shuffle()
	for i in randi_range(2, 3):
		cells.append(Vector2i(front[i], 0))
	var guard := 0
	while cells.size() < TILES_KEPT and guard < 5000:
		guard += 1
		var from: Vector2i = cells[randi() % cells.size()]
		var n: Vector2i = from + [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, 1), Vector2i(0, -1)][randi() % 5]
		if n.x < 0 or n.y < 0 or n.x >= TILE_COLS or n.y >= TILE_ROWS or cells.has(n):
			continue
		cells.append(n)
	return cells

func _build_ball() -> void:
	_ball = RigidBody3D.new()
	_ball.mass = BALL_MASS
	_ball.gravity_scale = GRAVITY_SCALE
	_ball.continuous_cd = true
	_ball.linear_damp = 0.04
	_ball.angular_damp = 0.05
	_ball.contact_monitor = true
	_ball.max_contacts_reported = 4
	_ball.can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	pm.bounce = 0.05
	_ball.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = BALL_R
	cs.shape = ss
	_ball.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.material = mat("player", 0.45, 0.12)
	mi.mesh = sm
	_ball.add_child(mi)
	# three finger holes: the only way a rolling sphere shows that it is rolling
	for off in [Vector3(-0.09, 0.0, 0.06), Vector3(0.09, 0.0, 0.06), Vector3(0.0, 0.0, -0.1)]:
		var hole := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.05
		hm.height = 0.1
		hm.material = mat("bg", 0.0, 0.9)
		hole.mesh = hm
		hole.position = (Vector3(0, BALL_R, 0) + off).normalized() * BALL_R
		_ball.add_child(hole)
	_ball.freeze = true
	world.add_child(_ball)
	_ball.global_position = Vector3(_aim_x, BALL_R, BALL_START_Z)
	_ball.body_entered.connect(_on_ball_hit)
	track3d(_ball, "@")

	# the landing spot: a glowing ring on the lane, and a thin line from the ball to it
	_marker = Node3D.new()
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.42
	tm.material = mat("player", 0.9)
	ring.mesh = tm
	ring.position = Vector3(0, 0.02, 0)
	_marker.add_child(ring)
	var dot := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.08
	dm.height = 0.16
	dm.material = mat("player", 1.0)
	dot.mesh = dm
	dot.position = Vector3(0, 0.05, 0)
	_marker.add_child(dot)
	_marker.visible = false
	world.add_child(_marker)
	_guide = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.04, 0.01, 1.0)
	gm.material = mat("player", 0.5)
	_guide.mesh = gm
	_guide.visible = false
	world.add_child(_guide)

func _build_ui() -> void:
	var back := ColorRect.new()
	var c := Palette.col("bg")
	c.a = 0.62
	back.color = c
	back.position = Vector2(0, 308)
	back.size = Vector2(640, 52)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_strip = Label.new()
	_strip.add_theme_font_size_override("font_size", 13)
	_strip.add_theme_color_override("font_color", Palette.col("ink"))
	_strip.position = Vector2(0, 314)
	_strip.size = Vector2(640, 20)
	_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_hint = Label.new()
	_hint.text = "tap where the ball should land: further is harder, past a wall is a bank shot  ·  arrows aim, A throws"
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Palette.col("ink"))
	_hint.modulate.a = 0.6
	_hint.position = Vector2(0, 338)
	_hint.size = Vector2(640, 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

## ---- the rack-choice screen -----------------------------------------------------------------

## Two buttons over the empty lane. ColorRect + Label with the mouse ignored and a
## Rect2 test in _input, not real Buttons: _input runs before the GUI would.
func _build_menu() -> void:
	_menu = Node2D.new()
	add_child(_menu)
	var title := Label.new()
	title.text = "bowling"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Palette.col("player"))
	title.position = Vector2(0, 62)
	title.size = Vector2(640, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(title)
	var sub := Label.new()
	sub.text = "pick a rack"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Palette.col("accent"))
	sub.position = Vector2(0, 112)
	sub.size = Vector2(640, 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(sub)
	for i in 2:
		var r: Rect2 = BTN_BLOCK if i == 0 else BTN_SHAPES
		var edge := ColorRect.new()
		edge.name = "edge%d" % i
		edge.position = r.position - Vector2(3, 3)
		edge.size = r.size + Vector2(6, 6)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.add_child(edge)
		var box := ColorRect.new()
		box.color = Palette.col("player" if i == 0 else "prize")
		box.position = r.position
		box.size = r.size
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.add_child(box)
		var l := Label.new()
		l.text = "100 pins" if i == 0 else "random ground"
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Palette.col("bg"))
		l.position = r.position
		l.size = r.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.add_child(l)
		var blurb := Label.new()
		blurb.text = "a wall of a hundred, ten throws" if i == 0 else "the floor is a random shape with holes,\ntwenty pins on it. clear it, get another"
		blurb.add_theme_font_size_override("font_size", 11)
		blurb.add_theme_color_override("font_color", Palette.col("ink"))
		blurb.modulate.a = 0.75
		blurb.position = Vector2(r.position.x, r.end.y + 6)
		blurb.size = Vector2(r.size.x, 34)
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu.add_child(blurb)
	_menu_highlight()

func _menu_highlight() -> void:
	for i in 2:
		var edge: ColorRect = _menu.get_node("edge%d" % i)
		edge.color = Palette.col("ink") if i == _menu_pick else Palette.col("bg")

func _choose(mode: String) -> void:
	if _state != "menu":
		return
	_mode = mode
	Audio.play("select")
	_menu.queue_free()
	_menu = null
	if _mode != "ground":
		_build_floor()
	_rack()
	_strip.visible = true
	_hint.visible = true
	_state = "aim"
	_refresh_strip()
	Probe.event("begin", {"mode": mode})

## ---- pins ----------------------------------------------------------------------------

## A hundred pins are drawn as three instanced meshes (body, head, neck band) whose
## transforms follow the physics bodies every frame: three draw calls instead of three
## hundred nodes, which is the difference between a phone coping and not.
func _build_pin_meshes() -> void:
	var body := CylinderMesh.new()
	body.top_radius = 0.07
	body.bottom_radius = 0.125
	body.height = 0.72
	var head := SphereMesh.new()
	head.radius = 0.1
	head.height = 0.2
	var band := CylinderMesh.new()
	band.top_radius = 0.1
	band.bottom_radius = 0.105
	band.height = 0.05
	for part in [[body, Vector3(0, 0.36, 0), mat("ink", 0.22, 0.35)],
			[head, Vector3(0, 0.8, 0), mat("ink", 0.22, 0.35)],
			[band, Vector3(0, 0.58, 0), mat("hazard", 0.6)]]:
		var mesh: Mesh = part[0]
		mesh.material = part[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = PIN_COLS * PIN_ROWS
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		world.add_child(mmi)
		_pin_mm.append([mmi, part[1]])

func _sync_pin_meshes() -> void:
	var n := _pins.size()
	for e in _pin_mm:
		var mm: MultiMesh = (e[0] as MultiMeshInstance3D).multimesh
		var off: Vector3 = e[1]
		mm.visible_instance_count = n
		for i in n:
			var p: RigidBody3D = _pins[i]
			var s := 1.0
			var swept: float = p.get_meta("swept")
			if swept >= 0.0:
				s = maxf(0.01, 1.0 - (_t - swept) / 0.3)
			var xf := p.global_transform * Transform3D(Basis().scaled(Vector3.ONE * s), off * s)
			mm.set_instance_transform(i, xf)

func _make_pin(at: Vector3) -> RigidBody3D:
	var p := RigidBody3D.new()
	p.mass = PIN_MASS
	p.gravity_scale = GRAVITY_SCALE
	p.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	p.center_of_mass = Vector3(0, 0.34, 0)   # a real pin is bottom-heavy
	p.contact_monitor = true
	p.max_contacts_reported = 2
	p.angular_damp = 0.1
	p.linear_damp = 0.05
	var pm := PhysicsMaterial.new()
	pm.friction = 0.3
	pm.bounce = 0.35
	p.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = PIN_R
	cyl.height = PIN_H
	cs.shape = cyl
	cs.position = Vector3(0, PIN_H * 0.5, 0)
	p.add_child(cs)
	p.set_meta("swept", -1.0)
	world.add_child(p)
	p.global_position = at
	p.body_entered.connect(_on_pin_hit)
	track3d(p, "*")
	return p

## A fresh rack for the current mode, the nearest row at RACK_FRONT_Z.
func _rack() -> void:
	for p in _pins:
		if is_instance_valid(p):
			p.queue_free()
	_pins.clear()
	if _mode == "ground":
		# a new floor every rack, and the pins on four slots per tile, twenty of them at
		# random, never on the front row (that is where the ball arrives)
		var cells := _build_floor()
		var slots: Array = []
		for c: Vector2i in cells:
			if c.y == 0:
				continue
			var at := _tile_centre(c)
			for off in [Vector3(-0.4, 0, -0.4), Vector3(0.4, 0, -0.4), Vector3(-0.4, 0, 0.4), Vector3(0.4, 0, 0.4)]:
				slots.append(at + off)
		slots.shuffle()
		for i in mini(GROUND_PINS, slots.size()):
			_pins.append(_make_pin(slots[i]))
		Probe.event("ground", {"tiles": cells.size(), "pins": _pins.size()})
	else:
		for row in PIN_ROWS:
			var shift := 0.15 if row % 2 == 1 else -0.15
			for col in PIN_COLS:
				var x := (col - (PIN_COLS - 1) * 0.5) * PIN_DX + shift
				_pins.append(_make_pin(Vector3(x, 0, RACK_FRONT_Z - row * PIN_DZ)))
	_rack_size = _pins.size()
	_standing = _pins.size()
	_sync_pin_meshes()

func _pin_up(p: RigidBody3D) -> bool:
	if not is_instance_valid(p) or float(p.get_meta("swept")) >= 0.0:
		return false
	var pos := p.global_position
	if pos.y < -0.15 or pos.z < -LANE_LEN:
		return false
	return p.global_transform.basis.y.y > 0.85   # leaning more than ~32 degrees is down

## ---- the throw ---------------------------------------------------------------------------

## Throw so the ball lands on `target` (a point on the lane): a fixed launch angle, and the
## speed solved from the distance, so a farther spot is a harder throw. Past DIST_MAX the
## speed just caps and the ball lands short of the spot, still going that way.
func _throw_at(target: Vector3) -> void:
	if _state != "aim" or finished:
		return
	var from := _ball.global_position
	var to := target - from
	to.y = 0.0
	var dist := to.length()
	if dist < DIST_MIN:
		return
	var flat := to / dist
	var up := deg_to_rad(LAUNCH_DEG)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity") * GRAVITY_SCALE
	# 1.05: the first contact with the lane eats a little of the launch; measured, not derived
	var speed := clampf(sqrt(minf(dist, DIST_MAX) * 1.05 * g / sin(2.0 * up)), SPEED_MIN, SPEED_MAX)
	var dir := Vector3(flat.x * cos(up), sin(up), flat.z * cos(up))
	_state = "rolling"
	_roll_t = 0.0
	_quiet_t = 0.0
	_airborne = true
	_marker.visible = false
	_guide.visible = false
	_ball.freeze = false
	_ball.linear_damp = 0.0   # no drag in the air, so it lands where the marker was
	_ball.linear_velocity = dir * speed
	_ball.angular_velocity = Vector3.UP.cross(flat) * (speed * cos(up) / BALL_R)   # rolling, not sliding, once it lands
	Audio.play("jump", 0.1)
	Probe.event("throw", {"dist": snappedf(dist, 0.1), "speed": snappedf(speed, 0.1), "x": snappedf(target.x, 0.1)})

## The landing spot the keys (and the bots) ask for: straight ahead, _key_dist away.
func _key_target() -> Vector3:
	return _ball.global_position + Vector3(0, 0, -_key_dist)

func _physics_process(delta: float) -> void:
	if _state != "rolling":
		return
	_roll_t += delta
	var bp := _ball.global_position
	# done when the ball is gone (or stuck) and the pins have stopped moving
	var ball_done: bool = bp.z < PIT_Z or bp.y < -1.0 or (_roll_t > 2.0 and _ball.linear_velocity.length() < 0.4)
	var pins_quiet := true
	for p: RigidBody3D in _pins:
		if p.global_position.y > -1.0 and p.global_position.z > PIT_Z:
			if p.linear_velocity.length() > 0.5 or p.angular_velocity.length() > 1.2:
				pins_quiet = false
				break
	_quiet_t = _quiet_t + delta if (ball_done and pins_quiet) else 0.0
	if _quiet_t >= SETTLE or _roll_t >= ROLL_TIMEOUT:
		_tally()

func _on_ball_hit(other: Node) -> void:
	if _state != "rolling":
		return
	if other is StaticBody3D:
		if _airborne:
			_airborne = false
			_ball.linear_damp = 0.04
			Audio.play("thud")
			hit3d(3.0)
			Probe.event("land", {"z": snappedf(_ball.global_position.z, 0.1)})
		elif _ball.linear_velocity.length() > 3.0 and absf(_ball.global_position.x) > LANE_W * 0.5 - BALL_R - 0.15:
			Audio.play("impact_light", 0.15)
			shake3d(1.5)
			Probe.event("bank")
		return
	if other is RigidBody3D:
		if _sfx_t <= 0.0:
			_sfx_t = 0.08
			Audio.play("impact_wood", 0.2)
		hit3d(2.5)

func _on_pin_hit(other: Node) -> void:
	if _state != "rolling" or not (other is RigidBody3D) or _sfx_t > 0.0:
		return
	_sfx_t = 0.06
	Audio.play("impact_wood", 0.25, -4.0)
	shake3d(1.2)

## ---- counting and the sweep -----------------------------------------------------------------

func _tally() -> void:
	_state = "reset"
	var up := 0
	for p: RigidBody3D in _pins:
		if _pin_up(p):
			up += 1
	var knocked := _standing - up
	_throws.append(knocked)
	var cleared := up == 0
	var deck := to_screen(Vector3(0, 1.6, RACK_FRONT_Z - 2.5))
	if cleared:
		Probe.event("rack_cleared")
		Juice.text(self, deck, "CLEARED! +%d" % (knocked + _clear_bonus()), Palette.col("prize"))
		Audio.play("voice_congratulations")
		hit3d(7.0)
		_sparks(Vector3(0, 0.8, RACK_FRONT_Z - 2.5), 18)
		_racks += 1
	elif knocked >= 25:
		Probe.event("big_hit")
		Juice.text(self, deck, "+%d  !!" % knocked, Palette.col("prize"))
		Audio.play("voice_correct")
		hit3d(5.0)
		_sparks(Vector3(0, 0.8, RACK_FRONT_Z - 2.5), 10)
	elif knocked >= 10:
		Juice.text(self, deck, "+%d" % knocked, Palette.col("warn"))
		Audio.play("coin")
	elif knocked > 0:
		Juice.text(self, deck, "+%d" % knocked, Palette.col("ink"))
	else:
		Juice.text(self, deck, "miss", Palette.col("hazard"))
	Probe.event("pins_down", {"n": knocked, "left": up})
	add_score(knocked + (_clear_bonus() if cleared else 0))
	_refresh_strip()

	# fallen pins shrink away; the rest stay exactly where they are
	for p: RigidBody3D in _pins:
		if not _pin_up(p):
			p.set_meta("swept", _t + RESET_DELAY * 0.5)
	get_tree().create_timer(RESET_DELAY).timeout.connect(_reset.bind(_throws.size() >= THROWS, cleared))

func _clear_bonus() -> int:
	return int(round(_rack_size * CLEAR_BONUS))

func _reset(game_over: bool, cleared: bool) -> void:
	if finished:
		return
	var kept: Array = []
	for p: RigidBody3D in _pins:
		if float(p.get_meta("swept")) >= 0.0:
			p.queue_free()
		else:
			kept.append(p)
	_pins = kept
	if game_over:
		_state = "over"
		_refresh_strip()
		Probe.event("game_end", {"score": score})
		get_tree().create_timer(0.8).timeout.connect(win)
		return
	if cleared:
		_rack()
	_standing = _pins.size()
	_sync_pin_meshes()
	_ball.freeze = true
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_transform = Transform3D(Basis(), Vector3(_aim_x, BALL_R, BALL_START_Z))
	_state = "aim"
	if _throws.size() == THROWS - 1:
		Audio.play("voice_final_round")

## The strip: pins per throw so far, the current throw bracketed, and pins left up.
func _refresh_strip() -> void:
	var marks: Array = []
	for i in THROWS:
		if i < _throws.size():
			marks.append(str(_throws[i]))
		elif i == _throws.size() and _state != "over":
			marks.append("[_]")
		else:
			marks.append("·")
	var up := 0
	for p: RigidBody3D in _pins:
		if _pin_up(p):
			up += 1
	_strip.text = "   ".join(marks) + "      %d pins up" % up

func _sparks(at: Vector3, n: int) -> void:
	for i in n:
		var d := RigidBody3D.new()
		d.mass = 0.1
		d.gravity_scale = GRAVITY_SCALE
		var s := randf_range(0.06, 0.14)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * s
		bm.material = mat("prize" if i % 2 == 0 else "accent", 1.0)
		mi.mesh = bm
		d.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3.ONE * s
		cs.shape = bs
		d.add_child(cs)
		world.add_child(d)
		d.global_position = at + Vector3(randf_range(-2.0, 2.0), 0.2, randf_range(-1.5, 1.5))
		d.linear_velocity = Vector3(randf_range(-3, 3), randf_range(4, 9), randf_range(-3, 1))
		d.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		get_tree().create_timer(1.2).timeout.connect(d.queue_free)

## ---- per frame -----------------------------------------------------------------------------

## Behind and above the ball, looking down the lane at about 35 degrees: the whole lane
## is on screen to tap, and the pins at the far end are still pins.
func _rest_cam_pos() -> Vector3:
	return Vector3(_aim_x * 0.3, 11.0, BALL_START_Z + 9.0)

func _rest_cam_target() -> Vector3:
	return Vector3(_aim_x * 0.15, 0.0, -6.0)

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	_sfx_t -= delta

	if _state == "menu":
		if PInput.just_pressed("move_left") or PInput.just_pressed("move_right"):
			_menu_pick = 1 - _menu_pick
			_menu_highlight()
			Audio.play("click")
		if PInput.just_pressed("action_a"):
			_choose("block" if _menu_pick == 0 else "ground")
	elif _state == "aim":
		var d := PInput.dir()
		if d.x != 0.0:
			_aim_x = clampf(_aim_x + d.x * SLIDE_SPEED * delta, -(LANE_W * 0.5 - BALL_R - 0.1), LANE_W * 0.5 - BALL_R - 0.1)
			_ball.global_transform = Transform3D(Basis(), Vector3(_aim_x, BALL_R, BALL_START_Z))
		if d.y != 0.0:
			_key_dist = clampf(_key_dist - d.y * KEY_DIST_SPEED * delta, DIST_MIN, DIST_MAX)
		if not _drag:
			_target = _key_target()
			_marker.visible = d != Vector2.ZERO
		if PInput.just_pressed("action_a"):
			_throw_at(_key_target())
		_show_aim()

	_sync_pin_meshes()

	# the camera rides down the lane behind the ball and glides home for the next throw
	var want_pos := _rest_cam_pos()
	var want_target := _rest_cam_target()
	if _state == "rolling" or _state == "reset":
		var bp := _ball.global_position
		var bz := clampf(bp.z, RACK_FRONT_Z + 1.5, BALL_START_Z)
		var bx := clampf(bp.x, -2.0, 2.0)
		want_pos = Vector3(bx * 0.5, 6.0 + maxf(0.0, bp.y - BALL_R) * 0.5, bz + 7.5)
		want_target = Vector3(bx * 0.3, 0.0, bz - 7.0)
		if _state == "reset":
			want_pos = Vector3(0, 5.5, RACK_FRONT_Z + 8.0)
			want_target = Vector3(0, 0.3, RACK_FRONT_Z - 2.5)
	var k := 1.0 - exp(-delta * (5.0 if _state == "rolling" else 3.0))
	_cam_pos = _cam_pos.lerp(want_pos, k)
	_cam_target = _cam_target.lerp(want_target, k)
	look_from(_cam_pos, _cam_target)

## ---- aiming with the pointer ---------------------------------------------------------------

## The marker sits on the landing spot; the line runs from the ball to it. Hidden unless
## the player is holding the pointer down or nudging the keys.
func _show_aim() -> void:
	if not _marker.visible:
		_guide.visible = false
		return
	_marker.position = Vector3(_target.x, 0.0, _target.z)
	var from := _ball.global_position
	from.y = 0.012
	var to := Vector3(_target.x, 0.012, _target.z)
	var v := to - from
	var n := v.length()
	_guide.visible = n > 0.1
	if _guide.visible:
		_guide.position = (from + to) * 0.5
		_guide.scale = Vector3(1, 1, n)
		_guide.rotation.y = atan2(-v.x, -v.z)

## Press anywhere on the lane ahead of the ball and the marker shows where it will land;
## drag to move it; release to throw. A release behind the ball, or over the HUD, cancels.
func _input(e: InputEvent) -> void:
	if finished:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _state == "menu":
			if Flow.pointer_over_hud():
				return
			if BTN_BLOCK.has_point(e.position):
				_choose("block")
			elif BTN_SHAPES.has_point(e.position):
				_choose("ground")
			return
		if e.pressed:
			if Flow.pointer_over_hud() or _state != "aim":
				_drag = false
				return
			_drag = true
			_aim_pointer(e.position)
		elif _drag:
			_drag = false
			_aim_pointer(e.position)
			if _marker.visible:
				_throw_at(_target)
			_marker.visible = false
	elif e is InputEventMouseMotion and _drag:
		_aim_pointer(e.position)

func _aim_pointer(screen: Vector2) -> void:
	var g := ground_point(screen)
	if not g.is_finite() or _state != "aim":
		_marker.visible = false
		return
	var ahead := _ball.global_position.z - g.z
	_marker.visible = ahead >= DIST_MIN
	if _marker.visible:
		_target = Vector3(g.x, 0.0, g.z)
