extends GameMode3D
## bowling -- a neon lane that gets wilder every level. Tap where the ball should land: it
## flies there, lands, rolls on and ploughs into the pins. A farther spot is a harder
## throw; a spot past a wall is a bank shot, because the lane has bumpers, not gutters.
## Each level is a layout -- a rack shape plus whatever is in the way (posts, angled walls,
## sliding blocks, spinning bars, holes in the lane, ramps, a raised deck, magnetised
## boards that bend the ball) -- and a pin target in a fixed number of throws. Miss the
## target and the run is over. Real rigid bodies: the ball rolls, the pins tumble.
## Keys and pad: left/right slide the ball along the foul line, up/down move the landing
## spot, A throws -- which is also how the bots play.

const LANE_W := 6.4                  ## wide: ten pins abreast with room to bank off the walls
const LANE_LEN := 18.0               ## foul line at z=0, the pit starts at z=-LANE_LEN
const APPROACH := 3.0                ## lane surface behind the foul line where the ball waits
const WALL_H := 0.5                  ## the glowing bumper you see; the one that stops the ball is taller
const BALL_R := 0.27
const BALL_MASS := 9.0                 ## a wrecking ball next to the pins
const BALL_START_Z := 1.2
const PIN_H := 0.9
const PIN_R := 0.13                  ## collision cylinder; the drawn pin bulges past it
const PIN_MASS := 0.35                 ## light, so the rack does not stop the ball and a hit pin flies
const PIN_DX := 0.64                 ## between neighbours in a row (a ball cannot squeeze through)
const PIN_DZ := 0.6                  ## between rows
const MAX_PINS := 48                 ## instanced-mesh capacity; no layout holds more
const PIT_Z := -LANE_LEN - 1.2       ## anything past here (or under the floor) is gone
const LAUNCH_DEG := 16.0             ## the ball leaves the hand at this angle, always: flat, toward the pins
const SPEED_MIN := 10.0              ## slowest throw -- still rolls all the way to the rack
const SPEED_MAX := 30.0              ## fastest; the speed is solved from where you tapped
const DIST_MIN := 2.0                ## a landing spot closer than this is a tap on the ball, not a throw
const DIST_MAX := 17.5               ## the back of the deepest rack; keys cannot ask for more
const KEY_DIST_START := 13.0         ## where the keyboard landing spot starts (the front of the rack)
const KEY_DIST_SPEED := 6.0          ## up/down move it this fast, units per second
const SLIDE_SPEED := 3.0             ## foul-line slide on the keys, units per second
const GRAVITY_SCALE := 2.5           ## Earth gravity at this scale looks like the moon
const SETTLE := 0.7                  ## everything quiet this long -> count the pins
const ROLL_TIMEOUT := 7.0            ## a wobbling pin (or a spinner) does not get to hold the game up
const RESET_DELAY := 1.0             ## seconds to admire the wreckage before the sweep
const CLEAR_DELAY := 2.4             ## level cleared: celebrate, then the next layout
const FAIL_DELAY := 2.2              ## out of throws: let it sink in, then game over
const BANNER_TIME := 2.0             ## the level name hangs on screen this long
const LEVEL_BONUS := 25              ## x level number, for clearing it
const THROW_BONUS := 15              ## per throw left over when the target falls
const STRIKE_BONUS := 20             ## every pin of a full layout in one throw
const BIG_HIT := 12                  ## pins in one throw that earn the big reaction ...
const GOOD_HIT := 6                  ## ... and the small one
const SFX_SCALE := 0.28              ## the shell default is loud; in memory only, see CLAUDE.md
const PHYSICS_HZ := 120              ## a fast ball through thin pins needs it; restored on exit

## One entry per level: the menu builds its level grid from this. Each is a layout.
##   need / throws -- knock down `need` pins within `throws` throws, or the run is over
##   racks  -- pin formations: shape block|triangle|diamond|ring|scatter, centred on x, front row at z
##   things -- what is in the way:
##     post    {x, z, r}            a glowing pillar the ball caroms off
##     wall    {x, z, len, deg}     a bouncy rail; deg 0 runs down the lane, others angle it
##     mover   {x, z, w, amp, speed} a block sliding side to side
##     spinner {x, z, len, speed}   a bar turning on the spot (negative speed turns the other way)
##     hole    {x0, x1, z0, z1}     no lane here: a ball (or a pin) that drops in is gone
##     ramp    {x, w, z0, z1, h}    rises from the lane at z0 to height h at z1; alone it is a kicker
##     deck    {z0, z1, h}          a raised floor across the lane; reach it by ramp or by lofting it
##   drift  -- magnetised boards: the rolling ball is pushed sideways this hard (+ = right)
const LEVELS := [
	{"name": "warm-up", "tip": "find the gaps", "need": 14, "throws": 5,
		"racks": [{"shape": "block", "cols": 5, "rows": 4, "z": -12.6}]},
	{"name": "the triangle", "tip": "every pin, four throws", "need": 15, "throws": 4,
		"racks": [{"shape": "triangle", "rows": 5, "z": -12.0}]},
	{"name": "posts", "tip": "thread it, or bank it", "need": 13, "throws": 5,
		"racks": [{"shape": "block", "cols": 5, "rows": 3, "z": -13.0}],
		"things": [{"kind": "post", "x": -1.5, "z": -7.0, "r": 0.35}, {"kind": "post", "x": 1.5, "z": -7.0, "r": 0.35},
			{"kind": "post", "x": 0.0, "z": -9.6, "r": 0.4}]},
	{"name": "the funnel", "tip": "the walls send it to the middle", "need": 14, "throws": 5,
		"racks": [{"shape": "diamond", "rows": 7, "z": -12.0}],
		"things": [{"kind": "wall", "x": -2.1, "z": -8.0, "len": 3.2, "deg": -28.0},
			{"kind": "wall", "x": 2.1, "z": -8.0, "len": 3.2, "deg": 28.0}]},
	{"name": "magnet lane", "tip": "the boards drag the ball right", "need": 14, "throws": 5, "drift": 5.0,
		"racks": [{"shape": "triangle", "rows": 4, "z": -12.4, "x": -1.5}, {"shape": "block", "cols": 3, "rows": 2, "z": -13.4, "x": 1.8}]},
	{"name": "split", "tip": "two lanes, two racks", "need": 17, "throws": 5,
		"racks": [{"shape": "triangle", "rows": 4, "z": -12.4, "x": -1.6}, {"shape": "triangle", "rows": 4, "z": -12.4, "x": 1.6}],
		"things": [{"kind": "wall", "x": 0.0, "z": -11.0, "len": 12.0, "deg": 0.0}]},
	{"name": "the chasm", "tip": "land beyond the gap", "need": 14, "throws": 4,
		"racks": [{"shape": "block", "cols": 5, "rows": 4, "z": -12.6}],
		"things": [{"kind": "hole", "x0": -3.2, "x1": 3.2, "z0": -5.0, "z1": -9.0}]},
	{"name": "sweepers", "tip": "time it", "need": 15, "throws": 5,
		"racks": [{"shape": "diamond", "rows": 7, "z": -12.2}],
		"things": [{"kind": "mover", "x": 0.0, "z": -6.5, "w": 1.8, "amp": 2.1, "speed": 1.5},
			{"kind": "mover", "x": 0.0, "z": -9.5, "w": 1.6, "amp": 2.1, "speed": -2.2}]},
	{"name": "the deck", "tip": "take the ramp, or loft it up", "need": 13, "throws": 5,
		"racks": [{"shape": "block", "cols": 5, "rows": 3, "z": -12.8}],
		"things": [{"kind": "deck", "z0": -11.0, "z1": -LANE_LEN, "h": 0.4},
			{"kind": "ramp", "x": 0.0, "w": 2.0, "z0": -7.5, "z1": -11.0, "h": 0.4},
			{"kind": "post", "x": -2.0, "z": -6.0, "r": 0.35}, {"kind": "post", "x": 2.0, "z": -6.0, "r": 0.35}]},
	{"name": "spinners", "tip": "the bars swat you away", "need": 15, "throws": 5,
		"racks": [{"shape": "scatter", "n": 20, "z": -12.2, "depth": 3.6, "w": 5.4}],
		"things": [{"kind": "spinner", "x": -1.5, "z": -9.0, "len": 2.4, "speed": 2.0},
			{"kind": "spinner", "x": 1.5, "z": -9.0, "len": 2.4, "speed": -2.0},
			{"kind": "post", "x": 0.0, "z": -6.0, "r": 0.35}]},
	{"name": "islands", "tip": "mind the holes", "need": 14, "throws": 5, "drift": -3.0,
		"racks": [{"shape": "diamond", "rows": 7, "z": -12.6}],
		"things": [{"kind": "hole", "x0": -3.2, "x1": -0.7, "z0": -3.5, "z1": -7.5},
			{"kind": "hole", "x0": 0.7, "x1": 3.2, "z0": -6.0, "z1": -10.0},
			{"kind": "hole", "x0": -1.3, "x1": 1.3, "z0": -10.2, "z1": -11.2}]},
	{"name": "chaos", "tip": "everything at once -- good luck", "need": 22, "throws": 6, "drift": 3.0,
		"racks": [{"shape": "scatter", "n": 28, "z": -12.4, "depth": 4.4, "w": 5.6}],
		"things": [{"kind": "ramp", "x": 0.0, "w": 2.2, "z0": -3.6, "z1": -5.0, "h": 0.55},
			{"kind": "hole", "x0": -3.2, "x1": 3.2, "z0": -5.6, "z1": -7.6},
			{"kind": "mover", "x": 0.0, "z": -9.0, "w": 1.6, "amp": 2.2, "speed": 2.4},
			{"kind": "spinner", "x": -1.7, "z": -10.8, "len": 1.8, "speed": 3.0},
			{"kind": "spinner", "x": 1.7, "z": -10.8, "len": 1.8, "speed": -3.0}]},
]

var _ball: RigidBody3D
var _marker: Node3D                  ## the landing spot on the lane while you aim
var _guide: MeshInstance3D           ## the line from the ball to it
var _target := Vector3.ZERO          ## where the ball will land (world, on the lane)
var _key_dist := KEY_DIST_START      ## landing distance chosen on the keys
var _pins: Array = []                ## RigidBody3D, meta: swept (float, -1 = standing)
var _pin_mm: Array = []              ## [MultiMeshInstance3D, Vector3 offset] per drawn part
var _standing := 0                   ## pins up at the start of this throw
var _throws: Array = []              ## pins knocked per throw, this level
var _level := 1
var _down := 0                       ## pins knocked down this level, toward its "need"
var _total := 0                      ## pins in this level's layout
var _layout: Node3D                  ## everything the level builds; freed when it ends
var _into: Node3D                    ## where _box() puts what it makes
var _movers: Array = []              ## AnimatableBody3D, meta: kind + its numbers
var _holes: Array = []               ## Rect2 in (x, z) for the current layout
var _decks: Array = []               ## [z0, z1, h] raised floors
var _drift := 0.0
var _focus_z := -13.5                ## middle of the pins: where the camera looks after a throw
var _state := "aim"                  ## aim | rolling | reset | clear | fail | over
var _t := 0.0
var _pt := 0.0                       ## physics time: drives movers and spinners
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
var _banner: Label
var _banner_sub: Label
var _sfx_was := 0.8
var _hz_was := 60

## Set at construction: the shell sizes its backdrop off play_area before _ready runs.
func _init() -> void:
	play_area = Rect2(0, 0, 640, 360)
	world_area = Rect2(-LANE_W * 0.5 - 0.3, -LANE_LEN - 3.2, LANE_W + 0.6, APPROACH + LANE_LEN + 3.2)

func _ready() -> void:
	title = "bowling"
	super()

func start(config: Dictionary) -> void:
	_sfx_was = SaveData.data.get("volume_sfx", 0.8)
	SaveData.data["volume_sfx"] = SFX_SCALE
	_hz_was = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = PHYSICS_HZ
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.rotation_degrees = Vector3(-58, 24, 0)
	cam.fov = 50.0
	_cam_pos = _rest_cam_pos()
	_cam_target = _rest_cam_target()
	look_from(_cam_pos, _cam_target)
	_into = world
	_build_alley()
	_build_ball()
	_build_pin_meshes()
	_build_ui()
	Probe.event("start")
	_begin_level(clampi(int(config.get("level", 1)), 1, LEVELS.size()))

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
		_into.add_child(mi)
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
	_into.add_child(body)
	return body

## What every level shares: bumpers, the pit, the masking unit, the floor of the world.
## The lane surface itself belongs to the level, because some levels cut holes in it.
func _build_alley() -> void:
	var length := LANE_LEN + APPROACH
	var mid_z := (APPROACH - LANE_LEN) * 0.5
	# bumpers: a glowing rail you see, and a tall invisible wall so a flying ball cannot
	# clear it. Both bounce, so a bank shot comes back with most of its speed.
	for side: float in [-1.0, 1.0]:
		var rx := side * (LANE_W * 0.5 + 0.1)
		_box(Vector3(0.2, WALL_H, length), Vector3(rx, WALL_H * 0.5 - 0.05, mid_z), mat("accent", 0.85), true, 0.7)
		_box(Vector3(0.2, 6.0, length), Vector3(rx, WALL_H + 3.0, mid_z), null, true, 0.7)
		# the neighbouring lanes, dim, so this is an alley and not a plank in space
		_box(Vector3(LANE_W, 0.3, length), Vector3(side * (LANE_W + 0.9), -0.25, mid_z), mat("bg_alt", 0.05, 0.4))
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
	# a wide dark floor under everything so the world has a ground (and holes a bottom)
	_box(Vector3(70, 0.2, 70), Vector3(0, -1.9, -8), mat("bg", 0.0, 1.0), true)

## ---- a level's layout ----------------------------------------------------------------

func _lv() -> Dictionary:
	return LEVELS[clampi(_level - 1, 0, LEVELS.size() - 1)]

func _is_last() -> bool:
	return _level == LEVELS.size()

func _begin_level(n: int) -> void:
	_level = n
	# "play again" after a game over restarts here, not wherever the run began
	Flow.current_config["level"] = n
	var lv := _lv()
	if _layout != null:
		_layout.queue_free()
	for p in _pins:
		if is_instance_valid(p):
			p.queue_free()
	_pins.clear()
	_movers.clear()
	_holes.clear()
	_decks.clear()
	_layout = Node3D.new()
	world.add_child(_layout)
	_into = _layout
	_drift = float(lv.get("drift", 0.0))
	for th: Dictionary in lv.get("things", []):
		match String(th.kind):
			"hole": _holes.append(Rect2(th.x0, th.z1, th.x1 - th.x0, th.z0 - th.z1))
			"deck": _decks.append([float(th.z0), float(th.z1), float(th.h)])
	_build_lane()
	for th: Dictionary in lv.get("things", []):
		_build_thing(th)
	if _drift != 0.0:
		_build_drift_marks()
	_into = world
	var spots: Array = []
	for r: Dictionary in lv.racks:
		spots.append_array(_rack_spots(r))
	var zsum := 0.0
	for sp: Vector2 in spots:
		_pins.append(_make_pin(Vector3(sp.x, _floor_y(sp.y), sp.y)))
		zsum += sp.y
	_focus_z = zsum / maxf(1.0, spots.size())
	_total = _pins.size()
	_standing = _total
	_down = 0
	_throws.clear()
	set_lives(int(lv.throws))   # the shell's lives row doubles as throws left
	_sync_pin_meshes()
	_reset_ball()
	_state = "aim"
	_show_banner("LEVEL %d  ·  %s" % [n, String(lv.name)],
		"knock down %d pins in %d throws  --  %s" % [int(lv.need), int(lv.throws), String(lv.tip)])
	Audio.play("voice_final_round" if _is_last() else "voice_level")
	if _is_last():
		shake3d(5.0)
	_refresh_strip()
	Probe.event("level_start", {"level": n, "name": lv.name, "pins": _total, "need": lv.need, "throws": lv.throws})

func _in_hole(x: float, z: float) -> bool:
	for h: Rect2 in _holes:
		if h.has_point(Vector2(x, z)):
			return true
	return false

func _floor_y(z: float) -> float:
	for d: Array in _decks:
		if z <= d[0] and z >= d[1]:
			return d[2]
	return 0.0

## The lane surface, cut into a grid along every hole edge so the holes are real holes:
## a ball (or a pin) that rolls into one drops to the floor of the world and is gone.
func _build_lane() -> void:
	var xs: Array = [-LANE_W * 0.5, LANE_W * 0.5]
	var zs: Array = [APPROACH, -LANE_LEN]
	for h: Rect2 in _holes:
		xs.append_array([h.position.x, h.end.x])
		zs.append_array([h.position.y, h.end.y])
	xs.sort()
	zs.sort()
	var boards: Array = []
	for i in range(1, 8):
		boards.append(-LANE_W * 0.5 + i * LANE_W / 8.0)
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			if x1 - x0 < 0.01 or z1 - z0 < 0.01 or _in_hole((x0 + x1) * 0.5, (z0 + z1) * 0.5):
				continue
			var mid := Vector3((x0 + x1) * 0.5, -0.2, (z0 + z1) * 0.5)
			_box(Vector3(x1 - x0, 0.4, z1 - z0), mid, mat("bg_alt", 0.18, 0.22), true, 0.15)
			for bx: float in boards:
				if bx > x0 + 0.02 and bx < x1 - 0.02:
					_box(Vector3(0.02, 0.011, z1 - z0), Vector3(bx, 0.0055, mid.z), mat("ink", 0.02, 0.6))
	# glowing lips round every hole, so you can see them from the foul line
	for h: Rect2 in _holes:
		var c := h.get_center()
		_box(Vector3(h.size.x, 0.03, 0.08), Vector3(c.x, 0.015, h.position.y), mat("hazard", 0.9))
		_box(Vector3(h.size.x, 0.03, 0.08), Vector3(c.x, 0.015, h.end.y), mat("hazard", 0.9))
		_box(Vector3(0.08, 0.03, h.size.y), Vector3(h.position.x, 0.015, c.y), mat("hazard", 0.9))
		_box(Vector3(0.08, 0.03, h.size.y), Vector3(h.end.x, 0.015, c.y), mat("hazard", 0.9))
	# foul line and the seven aiming arrows
	_box(Vector3(LANE_W, 0.012, 0.06), Vector3(0, 0.006, 0.0), mat("hazard", 0.9))
	for i in range(-3, 4):
		var ax := i * (LANE_W / 8.0)
		var az := -2.4 - (3 - absi(i)) * 0.4
		if not _in_hole(ax, az):
			_box(Vector3(0.09, 0.012, 0.42), Vector3(ax, 0.006, az), mat("accent", 0.9))

func _obstacle(body: StaticBody3D, bounce: float) -> void:
	var pm := PhysicsMaterial.new()
	pm.bounce = bounce
	pm.friction = 0.2
	body.physics_material_override = pm
	body.set_meta("obstacle", true)

func _build_thing(th: Dictionary) -> void:
	match String(th.kind):
		"post":
			var body := StaticBody3D.new()
			var r: float = th.r
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = 1.2
			cs.shape = cyl
			cs.position.y = 0.6
			body.add_child(cs)
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = 1.2
			cm.material = mat("hazard", 0.75)
			mi.mesh = cm
			mi.position.y = 0.6
			body.add_child(mi)
			var cap := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = r * 0.9
			tm.outer_radius = r * 1.25
			tm.material = mat("warn", 1.0)
			cap.mesh = tm
			cap.position.y = 1.2
			body.add_child(cap)
			_obstacle(body, 0.8)
			_layout.add_child(body)
			body.position = Vector3(th.x, 0, th.z)
		"wall":
			var body: StaticBody3D = _box(Vector3(0.22, 0.6, th.len), Vector3.ZERO, mat("accent", 0.8), true)
			body.position = Vector3(th.x, 0.3, th.z)
			body.rotation.y = deg_to_rad(th.deg)
			_obstacle(body, 0.75)
		"mover":
			var body := _moving_block(Vector3(th.w, 0.55, 0.4), "warn")
			body.set_meta("kind", "mover")
			body.set_meta("base", Vector3(th.x, 0.275, th.z))
			body.set_meta("amp", float(th.amp))
			body.set_meta("speed", float(th.speed))
			body.position = body.get_meta("base")
			track3d(body, "x")
		"spinner":
			var body := _moving_block(Vector3(th.len, 0.45, 0.24), "hazard")
			body.set_meta("kind", "spinner")
			body.set_meta("speed", float(th.speed))
			body.set_meta("base", Vector3(th.x, 0.225, th.z))
			body.position = body.get_meta("base")
			var hub := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.2
			cm.bottom_radius = 0.2
			cm.height = 0.7
			cm.material = mat("warn", 1.0)
			hub.mesh = cm
			hub.position.y = 0.1
			body.add_child(hub)
			track3d(body, "x")
		"ramp":
			_ramp(float(th.x), float(th.w), float(th.z0), float(th.z1), float(th.h))
		"deck":
			var z0: float = th.z0
			var z1: float = th.z1
			var h: float = th.h
			_box(Vector3(LANE_W, h, z0 - z1), Vector3(0, h * 0.5, (z0 + z1) * 0.5), mat("bg_alt", 0.25, 0.25), true, 0.15)
			_box(Vector3(LANE_W, 0.05, 0.06), Vector3(0, h + 0.02, z0), mat("friend", 1.0))
			_box(Vector3(LANE_W, h, 0.02), Vector3(0, h * 0.5, z0 + 0.005), mat("friend", 0.35))

## A box that moves by script: AnimatableBody3D, so the ball feels it as solid and moving.
func _moving_block(size: Vector3, role: String) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat(role, 0.8)
	mi.mesh = bm
	body.add_child(mi)
	_obstacle(body, 0.6)
	_layout.add_child(body)
	_movers.append(body)
	return body

## A wedge: its top face runs from (y=0, z0) up to (y=h, z1). With nothing after it, it
## is a kicker and the ball takes off.
func _ramp(x: float, w: float, z0: float, z1: float, h: float) -> void:
	var dz := z1 - z0
	var length := sqrt(dz * dz + h * h)
	var along := Vector3(0, h, dz) / length
	var up := Vector3(0, -dz, h) / length
	var t := 0.3
	var mid_top := Vector3(x, h * 0.5, (z0 + z1) * 0.5)
	var body: StaticBody3D = _box(Vector3(w, t, length), Vector3.ZERO, mat("friend", 0.55), true, 0.05)
	body.transform = Transform3D(Basis(Vector3.RIGHT, up, -along), mid_top - up * t * 0.5)
	# chevrons up the ramp so it reads as a ramp from the foul line
	for i in 3:
		var k := (i + 1) / 4.0
		var p := Vector3(x, h * k + 0.01, z0 + dz * k)
		var c: Node3D = _box(Vector3(w * 0.7, 0.02, 0.07), p, mat("prize", 1.0))
		c.rotation.x = atan2(h, -dz)

## Magnetised boards: rows of glowing chevrons pointing the way the ball will be dragged.
func _build_drift_marks() -> void:
	var sgn := signf(_drift)
	for zi in 5:
		var z := -3.0 - zi * 1.8
		for xi in 4:
			var x := -2.4 + xi * 1.6
			if _in_hole(x, z) or _floor_y(z) > 0.0:
				continue
			for arm: float in [-1.0, 1.0]:
				var b: Node3D = _box(Vector3(0.05, 0.012, 0.36), Vector3(x + sgn * 0.06, 0.008, z + arm * 0.12), mat("warn", 0.9))
				b.rotation.y = arm * sgn * deg_to_rad(50)

## Where each pin of one formation stands, as (x, z).
func _rack_spots(r: Dictionary) -> Array:
	var out: Array = []
	var cx: float = r.get("x", 0.0)
	var z0: float = r.z
	match String(r.shape):
		"block":
			var cols: int = r.cols
			for row in int(r.rows):
				var shift := 0.15 if row % 2 == 1 else -0.15
				for col in cols:
					out.append(Vector2(cx + (col - (cols - 1) * 0.5) * PIN_DX + shift, z0 - row * PIN_DZ))
		"triangle":
			for row in int(r.rows):
				for i in row + 1:
					out.append(Vector2(cx + (i - row * 0.5) * PIN_DX, z0 - row * PIN_DZ))
		"diamond":
			var rows: int = r.rows
			var mid := rows / 2
			for row in rows:
				var n := mid - absi(row - mid) + 1
				for i in n:
					out.append(Vector2(cx + (i - (n - 1) * 0.5) * PIN_DX, z0 - row * PIN_DZ))
		"ring":
			var n: int = r.n
			var rad: float = r.rad
			for i in n:
				var a := TAU * i / n
				out.append(Vector2(cx + cos(a) * rad, z0 - rad + sin(a) * rad))
		"scatter":
			# the same scatter every time this level is played: seeded by the level
			var rng := RandomNumberGenerator.new()
			rng.seed = 7919 * _level
			var w: float = r.w
			var depth: float = r.depth
			var tries := 0
			while out.size() < int(r.n) and tries < 4000:
				tries += 1
				var p := Vector2(cx + rng.randf_range(-w * 0.5, w * 0.5), z0 - rng.randf_range(0.0, depth))
				var ok := true
				for q: Vector2 in out:
					if p.distance_to(q) < 0.62:
						ok = false
						break
				if ok:
					out.append(p)
	return out

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
	_banner = _label(26, "accent", 92)
	_banner_sub = _label(13, "ink", 128)

func _label(size: int, role: String, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Palette.col(role))
	l.add_theme_color_override("font_outline_color", Palette.col("bg"))
	l.add_theme_constant_override("outline_size", 6)
	l.position = Vector2(0, y)
	l.size = Vector2(640, size + 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	add_child(l)
	return l

## A title across the middle of the screen that holds, then fades.
func _show_banner(head: String, sub: String) -> void:
	_banner.text = head
	_banner_sub.text = sub
	for l: Label in [_banner, _banner_sub]:
		var tw := l.create_tween()
		l.modulate.a = 0.0
		tw.tween_property(l, "modulate:a", 1.0, 0.25)
		tw.tween_interval(BANNER_TIME)
		tw.tween_property(l, "modulate:a", 0.0, 0.6)

## ---- pins ----------------------------------------------------------------------------

## The pins are drawn as three instanced meshes (body, head, neck band) whose transforms
## follow the physics bodies every frame: three draw calls however many pins there are.
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
		mm.instance_count = MAX_PINS
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

func _pin_up(p: RigidBody3D) -> bool:
	if not is_instance_valid(p) or float(p.get_meta("swept")) >= 0.0:
		return false
	var pos := p.global_position
	if pos.y < -0.15 or pos.z < -LANE_LEN or (pos.y < 0.05 and _in_hole(pos.x, pos.z)):
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
	_pt += delta
	for m: AnimatableBody3D in _movers:
		if not is_instance_valid(m):
			continue
		# the whole transform every tick: an AnimatableBody3D handed only a new rotation
		# snapped back to the origin
		var base: Vector3 = m.get_meta("base")
		var speed: float = m.get_meta("speed")
		if m.get_meta("kind") == "mover":
			m.transform = Transform3D(Basis(), base + Vector3(sin(_pt * speed) * float(m.get_meta("amp")), 0, 0))
		else:
			m.transform = Transform3D(Basis(Vector3.UP, _pt * speed), base)
	if _state != "rolling":
		return
	_roll_t += delta
	var bp := _ball.global_position
	# magnetised boards pull the ball sideways while it is rolling on them
	if _drift != 0.0 and not _airborne and bp.y < BALL_R + 0.1 and bp.z > -LANE_LEN:
		_ball.apply_central_force(Vector3(_drift * BALL_MASS, 0, 0))
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
		if other.has_meta("obstacle"):
			_airborne = false
			_ball.linear_damp = 0.04
			if _sfx_t <= 0.0:
				_sfx_t = 0.1
				Audio.play("impact_metal" if other is AnimatableBody3D else "impact_light", 0.15)
				shake3d(2.0)
				Probe.event("obstacle_hit")
			return
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
	var strike := up == 0 and _standing == _total
	_throws.append(knocked)
	_down = _total - up
	var lv := _lv()
	var left := int(lv.throws) - _throws.size()
	set_lives(left)
	var deck := to_screen(Vector3(0, 1.6, _focus_z))
	if strike:
		Probe.event("strike")
		Juice.text(self, deck, "STRIKE! +%d" % (knocked + STRIKE_BONUS), Palette.col("prize"))
		Audio.play("voice_congratulations")
		hit3d(7.0)
		_sparks(Vector3(0, 0.8, _focus_z), 18)
	elif knocked >= BIG_HIT:
		Probe.event("big_hit")
		Juice.text(self, deck, "+%d  !!" % knocked, Palette.col("prize"))
		Audio.play("voice_correct")
		hit3d(5.0)
		_sparks(Vector3(0, 0.8, _focus_z), 10)
	elif knocked >= GOOD_HIT:
		Juice.text(self, deck, "+%d" % knocked, Palette.col("warn"))
		Audio.play("coin")
	elif knocked > 0:
		Juice.text(self, deck, "+%d" % knocked, Palette.col("ink"))
	else:
		Juice.text(self, deck, "miss", Palette.col("hazard"))
	Probe.event("pins_down", {"n": knocked, "left": up, "down": _down, "need": lv.need})
	add_score(knocked + (STRIKE_BONUS if strike else 0))

	# fallen pins shrink away; the rest stay exactly where they are
	for p: RigidBody3D in _pins:
		if not _pin_up(p):
			p.set_meta("swept", _t + RESET_DELAY * 0.5)
	if _down >= int(lv.need):
		_level_clear(left)
	elif left <= 0:
		_level_failed()
	else:
		get_tree().create_timer(RESET_DELAY).timeout.connect(_reset)
	_refresh_strip()

func _level_clear(left: int) -> void:
	_state = "clear"
	var bonus := LEVEL_BONUS * _level + THROW_BONUS * left
	add_score(bonus)
	Probe.event("level_clear", {"level": _level, "throws_left": left, "score": score})
	Audio.play("voice_mission_completed" if _is_last() else "voice_objective_achieved")
	Audio.play("impact_bell")
	hit3d(4.0)
	_sparks(Vector3(0, 0.8, _focus_z), 22)
	var sub := "+%d" % bonus + ("  (%d throws to spare)" % left if left > 0 else "")
	_show_banner("YOU BEAT THEM ALL" if _is_last() else "LEVEL %d CLEAR" % _level, sub)
	get_tree().create_timer(CLEAR_DELAY).timeout.connect(func():
		if finished:
			return
		if _is_last():
			_state = "over"
			Probe.event("game_end", {"score": score})
			win()
		else:
			_begin_level(_level + 1))

func _level_failed() -> void:
	_state = "fail"
	Probe.event("level_failed", {"level": _level, "down": _down, "need": _lv().need})
	Audio.play("voice_mission_failed")
	shake3d(4.0)
	_show_banner("OUT OF THROWS", "%d of %d pins" % [_down, int(_lv().need)])
	get_tree().create_timer(FAIL_DELAY).timeout.connect(func():
		if not finished:
			_state = "over"
			Probe.event("game_end", {"score": score})
			lose())

func _reset() -> void:
	if finished or _state != "reset":
		return
	var kept: Array = []
	for p: RigidBody3D in _pins:
		if float(p.get_meta("swept")) >= 0.0:
			p.queue_free()
		else:
			kept.append(p)
	_pins = kept
	_standing = _pins.size()
	_sync_pin_meshes()
	_reset_ball()
	_state = "aim"
	_refresh_strip()
	if int(_lv().throws) - _throws.size() == 1:
		Audio.play("voice_final_round")

## Each throw starts lined up on the thickest bunch of standing pins: the keys (and the
## bots, which cannot plan) get a sensible first guess; a tap aims anywhere regardless.
func _line_up() -> void:
	var best: RigidBody3D = null
	var best_n := -1
	for p: RigidBody3D in _pins:
		if not _pin_up(p):
			continue
		var n := 0
		for q: RigidBody3D in _pins:
			if _pin_up(q) and p.global_position.distance_to(q.global_position) < 1.0:
				n += 1
		if n > best_n:
			best_n = n
			best = p
	if best == null:
		return
	var edge := LANE_W * 0.5 - BALL_R - 0.1
	_aim_x = clampf(best.global_position.x, -edge, edge)
	_key_dist = clampf(BALL_START_Z - best.global_position.z + 0.4, DIST_MIN, DIST_MAX)

func _reset_ball() -> void:
	_line_up()
	_ball.freeze = true
	_ball.linear_velocity = Vector3.ZERO
	_ball.angular_velocity = Vector3.ZERO
	_ball.global_transform = Transform3D(Basis(), Vector3(_aim_x, BALL_R, BALL_START_Z))

## The strip: the level, pins down toward the target, pins per throw, throws left.
func _refresh_strip() -> void:
	var lv := _lv()
	var marks: Array = []
	for i in int(lv.throws):
		if i < _throws.size():
			marks.append(str(_throws[i]))
		elif i == _throws.size() and _state == "aim":
			marks.append("[_]")
		else:
			marks.append("·")
	_strip.text = "level %d/%d  %s      %d / %d pins      %s" % [_level, LEVELS.size(), String(lv.name),
		_down, int(lv.need), "  ".join(marks)]

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

	if _state == "aim":
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
	if _state in ["rolling", "reset", "clear", "fail"]:
		var bp := _ball.global_position
		var bz := clampf(bp.z, _focus_z + 2.5, BALL_START_Z)
		var bx := clampf(bp.x, -2.0, 2.0)
		want_pos = Vector3(bx * 0.5, 6.0 + maxf(0.0, bp.y - BALL_R) * 0.5, bz + 7.5)
		want_target = Vector3(bx * 0.3, 0.0, bz - 7.0)
		if _state != "rolling":
			want_pos = Vector3(0, 5.5, _focus_z + 9.0)
			want_target = Vector3(0, 0.3, _focus_z - 1.5)
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
