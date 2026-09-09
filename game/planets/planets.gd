extends GameMode
## planets -- Scorched Earth, but the ground is round and gravity is everywhere. Two
## tanks sit on planets; you drag to aim, let go to fire, and the shell bends around
## every planet on the way. Every impact is a blast: it hurts any tank in range and
## bites a crater out of the planet, and a tank whose ground is gone falls to the new
## ground. Hit the enemy and the next level has more planets in the way. The enemy
## shoots back and learns from its misses. See GAME.md.
##
## Turn based: your shot, then the enemy's. One shell in the air at a time.
##
## A planet is a radial heightmap: HM_N samples of "how far the rock reaches" around the
## centre. Gravity comes from the planet's original size (mass does not leave with the
## chunks), collision and standing use the live surface.

const SURFACE_G := 450.0            ## gravity at a planet's surface, px/s^2; falls off as 1/r^2
const STEP := 1.0 / 120.0           ## shell physics step; the solver uses the same one
## The world is 960x540 seen through a camera zoomed out to 2/3, so it fits the 640x360
## viewport: more room round the planets, and no tank ends up right by the edge.
const WORLD := Rect2(0, 0, 960, 540)
const ZOOM := 2.0 / 3.0
const MAX_FLIGHT := 8.0             ## a shell's fuse: it explodes wherever it is when this runs out
const SPACE_MARGIN := 700.0         ## how far off screen a shell may wander before it is lost
const OFFSCREEN_MAX := 3.0          ## and how long it may stay out there, in total
## Gravity is 1/r^2 near a planet but only 1/r beyond SOFT_R x its radius: far out it pulls
## much harder than a real planet would, so a long shot turns round instead of drifting.
const SOFT_R := 1.5
## Escape speed off the biggest planet is about 290 px/s (sqrt(2 g R)); the range sits
## around it on purpose, because the shots that bend and come back are the ones near it.
const SPEED_MIN := 70.0
const SPEED_MAX := 400.0
const AIM_LEN_MIN := 20.0           ## drag length that means "minimum power" (world px)
const AIM_LEN_MAX := 150.0          ## drag length that means "full power" -- 100 px on screen, a short thumb pull
const AIM_SPEED := 300.0            ## how fast the keys move the aim point, px/s
const MUZZLE_LEN := 22.0
const TANK_R := 10.0
const HIT_R := 18.0                 ## a shell this close to a tank strikes it directly
const BLAST_R := 52.0               ## a blast this close to a tank hurts it
const DMG_DIRECT := 60              ## damage from a blast right on the tank ...
const DMG_EDGE := 12                ## ... down to this at the edge of the blast
const MAX_HP := 100
const ARM_TIME := 0.35              ## a shell younger than this cannot hurt its own shooter
const CRATER_R := 32.0              ## how much planet a blast removes
const MIN_ROCK := 8.0               ## a planet never carves below this radius
const HM_N := 144                   ## heightmap samples around a planet
const SHOT_CLOCK := 10.0            ## seconds you get per shot before the turn passes
const THINK_TIME := 0.8             ## the enemy's pause before it fires
const LEVEL_PAUSE := 1.6
const PREVIEW_STEPS := 60           ## half a second of predicted flight shown while aiming
const TRAIL_MAX := 90
const STAR_COUNT := 140
## The shell default (0.8) is loud for a game that explodes every few seconds. In memory
## only -- the saved settings file is never written. See CLAUDE.md.
const SFX_SCALE := 0.35
## Solver grid: coarse sweep, then a refine around the best cell.
const SOLVE_ANGLES := 36
const SOLVE_POWERS := [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
const SOLVE_MAX_STEPS := 1000       ## eight seconds of flight: enough for a shot that goes out and comes back
const FLIGHT_W := 6.0               ## solver: a second of flight costs this many pixels of miss
const PLANET_ROLES := ["accent", "prize", "friend", "warn"]
const HOME_APART := 460.0           ## the two home planets are never closer than this

var _planets: Array = []            ## {pos, r, role, seed, hm, marker}
var _ppos := PackedVector2Array()   ## planet centers, mirrored from _planets for the hot loops
var _prad := PackedFloat32Array()   ## original radii (gravity, bounding checks)
var _phm: Array = []                ## live heightmaps, one PackedFloat32Array per planet
var _player: Blob = null
var _enemy: Blob = null
var _reticle: Blob = null
var _hint: Node2D = null            ## the solved aim point, tracked for the bots only under PLANETS_AUTOAIM
var _shells: Array = []             ## Blob, meta: vel, trail, path, life, mine, from
var _last_trail := PackedVector2Array()  ## your previous shot, kept on screen to aim the next one
var _bits: Array = []               ## debris Blob, meta: vel
var _stars := PackedVector2Array()
var _star_phase := PackedFloat32Array()

var _state := "aim"                 ## aim | flying | think | levelup
var _aim := Vector2(90, -40)        ## world-space vector from the player tank to the aim point
var _enemy_aim := Vector2(-60, -40)
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_moved := false
var _clock := SHOT_CLOCK
var _pause := 0.0
var _flight_owner_mine := true
var _player_hit_this_flight := false
var _enemy_err := 0.8               ## how wrong the enemy's shot is; shrinks with every miss
var _shots_this_level := 0
var _level := 0
var _prompt := ""
var _t := 0.0
var _sfx_was := 0.8
var _autoaim := false
var _trace_steps := 0               ## how long the last _trace flew, for the solver's flight-time preference
var _hint_aim := Vector2.ZERO       ## the aim behind _hint, re-solved only once it stops working

## Set at construction, not in _ready: the shell sizes its backdrop grid off play_area
## right after instantiating the scene, before _ready has run.
func _init() -> void:
	play_area = WORLD

func _ready() -> void:
	title = "planets"
	play_area = WORLD
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_autoaim = OS.get_environment("PLANETS_AUTOAIM") == "1"

	var cam := Camera2D.new()
	cam.position = center()
	cam.zoom = Vector2(ZOOM, ZOOM)
	add_child(cam)
	cam.make_current()

	# no lives: the tanks carry hit points, drawn over them. An empty lives display is honest.
	set_lives(0)

	for i in STAR_COUNT:
		_stars.append(Vector2(randf_range(0, play_area.size.x), randf_range(0, play_area.size.y)))
		_star_phase.append(randf() * TAU)

	_reticle = Blob.new()
	_reticle.role = "player"
	_reticle.radius = 6.0
	add_child(_reticle)
	Probe.track(_reticle, "@")

	if _autoaim:
		_hint = Node2D.new()
		add_child(_hint)
		Probe.track(_hint, "*")

	_prompt = "drag anywhere to aim, let go to fire"
	_next_level()
	Probe.capture("start")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

## ---- levels ---------------------------------------------------------------

func _next_level() -> void:
	_level += 1
	_shots_this_level = 0
	_last_trail = PackedVector2Array()
	_hint_aim = Vector2.ZERO
	# the enemy opens wide of the mark and closes in with every miss; later levels open tighter
	_enemy_err = maxf(0.8, 1.5 - 0.06 * float(_level - 1))
	for s in _shells:
		if is_instance_valid(s):
			s.queue_free()
	_shells.clear()
	# same reason as the planet markers: gone now, so the snapshot shows one tank each
	if _player != null and is_instance_valid(_player):
		_player.free()
	if _enemy != null and is_instance_valid(_enemy):
		_enemy.free()
	_player = null
	_enemy = null

	var layout := _build_layout(_level)
	_player = _spawn_tank(layout["pp"], layout["pa"], true)
	_enemy = _spawn_tank(layout["ep"], layout["ea"], false)
	Probe.track(_player, "T")
	if not _autoaim:
		Probe.track(_enemy, "*")
	for pl in _planets:
		var marker := Node2D.new()
		marker.position = pl["pos"]
		add_child(marker)
		pl["marker"] = marker
		Probe.track(marker, "O")

	# start aiming roughly at the enemy so the first drag only has to adjust
	var toward: Vector2 = (_enemy.position - _player.position).normalized()
	_aim = _clamp_aim(toward * 90.0)
	_enemy_aim = _clamp_aim((_player.position - _enemy.position).normalized() * 60.0)
	_update_reticle()
	_update_hint()
	_state = "aim"
	_clock = SHOT_CLOCK
	if _level > 1:
		_prompt = "level %d -- your shot" % _level
	var info := {"level": _level, "planets": _planets.size()}
	if Probe.enabled:
		# how close the best shot gets from each side (0 means a clean hit exists), and
		# what one solve costs, since the enemy runs it every turn
		var t0 := Time.get_ticks_msec()
		info["miss_me"] = snappedf(_solve(_player.position, _enemy.position)["miss"], 0.1)
		info["miss_enemy"] = snappedf(_solve(_enemy.position, _player.position)["miss"], 0.1)
		info["solve_ms"] = (Time.get_ticks_msec() - t0) / 2
	Probe.event("level_start", info)
	if _level > 1 and _level % 3 == 0:
		Probe.capture("level %d" % _level)

## Returns {pp, pa, ep, ea}: planet index + surface angle for the player and the enemy.
## Level 1 is the first drawing; every level after it is random: at least four planets of
## assorted sizes, the two home planets well apart, and the layout checked with the
## enemy's own solver so a shot always exists from both sides.
func _build_layout(level: int) -> Dictionary:
	_clear_planets()
	if level == 1:
		_add_planet(Vector2(480, 275), 110.0)
		return {"pp": 0, "pa": deg_to_rad(140.0), "ep": 0, "ea": deg_to_rad(-25.0)}

	var total := 4 + mini(3, (level - 2) / 2)
	var best: Dictionary = {}
	var best_miss := INF
	for attempt in 8:
		_clear_planets()
		# the two home planets first (index 0 yours, 1 the enemy's), then the rest
		var ok := _place_home(true, randf_range(55.0, 95.0)) and _place_home(false, randf_range(55.0, 95.0))
		for i in total - 2:
			if not _place_random(_random_radius()):
				ok = false
		if not ok:
			continue
		var pa := _surface_angle(0, 1)
		var ea := _surface_angle(1, 0)
		var p_pos := _tank_pos(0, pa)
		var e_pos := _tank_pos(1, ea)
		var miss := maxf(_solve(p_pos, e_pos)["miss"], _solve(e_pos, p_pos)["miss"])
		if miss < best_miss:
			best_miss = miss
			best = {"pp": 0, "pa": pa, "ep": 1, "ea": ea, "planets": _planets.duplicate(true)}
		# a near miss is a hit now that every impact is a blast
		if miss < BLAST_R * 0.7:
			break
	if best.is_empty():
		# never happens in practice; fall back to the drawing
		return _build_layout(1)
	_planets = best["planets"]
	_sync_planets()
	return best

## Small moons are common, giants rare -- a mix reads better than a row of look-alikes.
func _random_radius() -> float:
	var roll := randf()
	if roll < 0.4:
		return randf_range(16.0, 30.0)
	if roll < 0.75:
		return randf_range(30.0, 55.0)
	return randf_range(55.0, 80.0)

## A home planet sits in the left or the right third of the world, and the two of them
## are at least HOME_APART apart, so the duel always crosses most of the screen.
func _place_home(left: bool, r: float) -> bool:
	var third := play_area.size.x / 3.0
	var x0 := play_area.position.x + r + 30.0 if left else play_area.end.x - third
	var x1 := play_area.position.x + third if left else play_area.end.x - r - 30.0
	for i in 40:
		var p := Vector2(randf_range(x0, x1), randf_range(play_area.position.y + r + 40.0, play_area.end.y - r - 40.0))
		if _planets.size() > 0 and p.distance_to(_planets[0]["pos"]) < HOME_APART:
			continue
		_add_planet(p, r)
		return true
	return false

func _clear_planets() -> void:
	for pl in _planets:
		if pl.has("marker") and is_instance_valid(pl["marker"]):
			# freed now, not queued: the level snapshot is taken this same frame, and a
			# queued marker would still show the old level's planets in it
			pl["marker"].free()
	_planets.clear()
	_sync_planets()

func _add_planet(pos: Vector2, r: float) -> void:
	var role: String = "ink" if r < 35.0 else PLANET_ROLES[_planets.size() % PLANET_ROLES.size()]
	var hm := PackedFloat32Array()
	hm.resize(HM_N)
	hm.fill(r)
	_planets.append({"pos": pos, "r": r, "role": role, "seed": randf() * TAU, "hm": hm})
	_sync_planets()

func _sync_planets() -> void:
	_ppos.clear()
	_prad.clear()
	_phm.clear()
	for pl in _planets:
		_ppos.append(pl["pos"])
		_prad.append(pl["r"])
		_phm.append(pl["hm"])

func _place_random(r: float) -> bool:
	var inner := play_area.grow(-(r + 30.0))
	for i in 40:
		var p := Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
		var clear := true
		for pl in _planets:
			if p.distance_to(pl["pos"]) < r + pl["r"] + 56.0:
				clear = false
				break
		if clear:
			_add_planet(p, r)
			return true
	return false

## A surface angle on planet `on` that faces planet `other`, jittered, and that keeps the
## tank on screen.
func _surface_angle(on: int, other: int) -> float:
	var base: float = (_planets[other]["pos"] - _planets[on]["pos"]).angle()
	for i in 12:
		var a := base + randf_range(-1.1, 1.1)
		if play_area.grow(-30.0).has_point(_tank_pos(on, a)):
			return a
	return base

## ---- the ground -------------------------------------------------------------

## How far the rock of planet i reaches in direction `ang`, off the live heightmap.
func _surface(i: int, ang: float) -> float:
	var hm: PackedFloat32Array = _phm[i]
	var f := fposmod(ang, TAU) / TAU * float(HM_N)
	var a := int(f) % HM_N
	return lerpf(hm[a], hm[(a + 1) % HM_N], f - floorf(f))

## True if p is inside the rock of any planet.
func _in_rock(p: Vector2) -> bool:
	for i in _ppos.size():
		var d := p - _ppos[i]
		var d2 := d.length_squared()
		if d2 >= _prad[i] * _prad[i]:
			continue
		var s := _surface(i, d.angle())
		if d2 < s * s:
			return true
	return false

## Bite a crater of radius cr centred at c out of every planet it reaches. Along each
## sample ray the rock now stops where the ray first enters the crater circle. Returns
## true if any rock was removed.
func _carve(c: Vector2, cr: float) -> bool:
	var any := false
	for i in _planets.size():
		var pl: Dictionary = _planets[i]
		var rel: Vector2 = c - pl["pos"]
		if rel.length() > pl["r"] + cr:
			continue
		var hm: PackedFloat32Array = pl["hm"]
		var removed := false
		for k in HM_N:
			var d := Vector2.from_angle(TAU * float(k) / float(HM_N))
			var m := d.dot(rel)
			var disc := m * m - (rel.length_squared() - cr * cr)
			if disc < 0.0:
				continue
			var root := sqrt(disc)
			var t_far := m + root
			if t_far < hm[k]:
				continue           # the crater is buried under solid rock (cannot show a cave)
			var t_near := maxf(m - root, MIN_ROCK)
			if t_near < hm[k]:
				hm[k] = t_near
				removed = true
		if removed:
			pl["hm"] = hm
			any = true
	if any:
		_sync_planets()
	return any

func _tank_pos(planet: int, angle: float) -> Vector2:
	return _planets[planet]["pos"] + Vector2.from_angle(angle) * (_surface(planet, angle) + TANK_R)

func _spawn_tank(planet: int, angle: float, mine: bool) -> Blob:
	var b := Blob.new()
	b.role = "player" if mine else "hazard"
	b.radius = TANK_R * 0.8
	add_child(b)
	b.position = _tank_pos(planet, angle)
	b.set_meta("planet", planet)
	b.set_meta("angle", angle)
	b.set_meta("alt", _surface(planet, angle) + TANK_R)   # distance from the planet centre
	b.set_meta("vy", 0.0)
	b.set_meta("hp", MAX_HP)
	return b

## A tank stands on the live surface under it. When that ground is carved away it falls,
## straight down toward the centre, and thuds onto whatever is left.
func _update_tanks(delta: float) -> void:
	for t in [_player, _enemy]:
		if t == null or not is_instance_valid(t):
			continue
		var pi: int = t.get_meta("planet")
		var ang: float = t.get_meta("angle")
		var alt: float = t.get_meta("alt")
		var vy: float = t.get_meta("vy")
		var ground := _surface(pi, ang) + TANK_R
		if alt > ground + 0.05:
			vy += SURFACE_G * delta
			alt -= vy * delta
			if alt <= ground:
				alt = ground
				Probe.event("tank_landed", {"mine": t == _player})
				Audio.play("thud")
				Juice.shake(minf(6.0, vy * 0.03))
				Juice.pop(t, 1.25, 0.2)
				vy = 0.0
		else:
			alt = ground
			vy = 0.0
		t.set_meta("alt", alt)
		t.set_meta("vy", vy)
		t.position = _ppos[pi] + Vector2.from_angle(ang) * alt

## ---- physics --------------------------------------------------------------

func _accel(p: Vector2) -> Vector2:
	var a := Vector2.ZERO
	for i in _ppos.size():
		var d := _ppos[i] - p
		var r2 := maxf(d.length_squared(), 100.0)
		var r := _prad[i]
		var dist := sqrt(r2)
		var soft := r * SOFT_R
		var mag := SURFACE_G * r * r / (r2 if dist <= soft else soft * dist)
		a += d * (mag / dist)
	return a

func _aim_velocity(aim: Vector2) -> Vector2:
	var power := clampf((aim.length() - AIM_LEN_MIN) / (AIM_LEN_MAX - AIM_LEN_MIN), 0.0, 1.0)
	return aim.normalized() * lerpf(SPEED_MIN, SPEED_MAX, power)

func _clamp_aim(v: Vector2) -> Vector2:
	if v.length() < 0.001:
		v = Vector2.RIGHT
	return v.normalized() * clampf(v.length(), AIM_LEN_MIN, AIM_LEN_MAX)

## What a live shell at p has run into: "planet", "tank" (with which), "space", or {}.
## The shooter is immune for the first moments so a shell cannot pop on its own barrel.
func _collide(p: Vector2, shooter: Vector2, life: float) -> Dictionary:
	for t in [_player, _enemy]:
		if t == null or not is_instance_valid(t):
			continue
		if life < 0.2 and t.position.distance_to(shooter) < 1.0:
			continue
		if p.distance_to(t.position) < HIT_R:
			return {"what": "tank", "tank": t}
	if _in_rock(p):
		return {"what": "planet"}
	if not in_play_area(p, SPACE_MARGIN):
		return {"what": "space"}
	return {}

## Fly a shell from `from` and report how close it gets to `target`; 0 means a hit.
## Stops where the real shell would: rock, the shooter's own tank, or deep space.
## Inlined rather than sharing _collide because the solver runs this a few hundred times
## a turn and a Dictionary per step was most of the cost.
func _trace(from: Vector2, vel: Vector2, target: Vector2, shooter: Vector2, max_steps: int) -> float:
	var p := from
	var v := vel
	var closest := from.distance_to(target)
	var bounds := play_area.grow(SPACE_MARGIN)
	var n := _ppos.size()
	var immune := int(0.2 / STEP)
	var out_max := int(OFFSCREEN_MAX / STEP)
	var out := 0
	_trace_steps = max_steps
	for step in max_steps:
		_trace_steps = step
		var a := Vector2.ZERO
		for i in n:
			var d := _ppos[i] - p
			var r2 := maxf(d.length_squared(), 100.0)
			var r := _prad[i]
			var dist := sqrt(r2)
			var soft := r * SOFT_R
			var mag := SURFACE_G * r * r / (r2 if dist <= soft else soft * dist)
			a += d * (mag / dist)
		v += a * STEP
		p += v * STEP
		var dt := p.distance_to(target)
		if dt < closest:
			closest = dt
		if dt < HIT_R:
			return 0.0
		if not play_area.has_point(p):
			out += 1
		var stopped := not bounds.has_point(p) or out > out_max
		if not stopped:
			for i in n:
				var d := p - _ppos[i]
				var d2 := d.length_squared()
				if d2 < _prad[i] * _prad[i]:
					var s := _surface(i, d.angle())
					if d2 < s * s:
						stopped = true
						break
		if not stopped and step > immune and p.distance_to(shooter) < HIT_R:
			stopped = true
		if stopped:
			break
	return closest

## Search for an aim that sends a shell from `from` to `target`. Coarse sweep, then a
## refine around the best cell. Returns {aim, miss}.
##
## Among shots that get about equally close, the quicker one wins: a long looping flight
## through the far gravity field is hypersensitive, so a shade of noise or a fresh crater
## sends it wide, while a short lob survives both. FLIGHT_W is the price of a second of
## flight, in pixels of miss.
func _solve(from: Vector2, target: Vector2) -> Dictionary:
	var best_aim := (target - from).normalized() * 90.0
	var best_miss := INF
	var best_score := INF
	for i in SOLVE_ANGLES:
		var ang := TAU * float(i) / float(SOLVE_ANGLES)
		for pw in SOLVE_POWERS:
			var aim := Vector2.from_angle(ang) * lerpf(AIM_LEN_MIN, AIM_LEN_MAX, pw)
			var miss := _trace(from + aim.normalized() * MUZZLE_LEN, _aim_velocity(aim), target, from, SOLVE_MAX_STEPS)
			var score := miss + float(_trace_steps) * STEP * FLIGHT_W
			if score < best_score:
				best_score = score
				best_miss = miss
				best_aim = aim
	var base_ang := best_aim.angle()
	var base_len := best_aim.length()
	var span := AIM_LEN_MAX - AIM_LEN_MIN
	for da in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for dl in [-0.07, 0.0, 0.07]:
			var aim := Vector2.from_angle(base_ang + deg_to_rad(da)) * clampf(base_len + dl * span, AIM_LEN_MIN, AIM_LEN_MAX)
			var miss := _trace(from + aim.normalized() * MUZZLE_LEN, _aim_velocity(aim), target, from, SOLVE_MAX_STEPS)
			var score := miss + float(_trace_steps) * STEP * FLIGHT_W
			if score < best_score:
				best_score = score
				best_miss = miss
				best_aim = aim
	return {"aim": best_aim, "miss": best_miss}

## ---- firing ---------------------------------------------------------------

func _fire(from: Blob, aim: Vector2, mine: bool) -> void:
	var muzzle: Vector2 = from.position + aim.normalized() * MUZZLE_LEN
	var s := Blob.new()
	s.role = "warn" if mine else "hazard"
	s.radius = 5.0
	add_child(s)
	s.position = muzzle
	s.set_meta("vel", _aim_velocity(aim))
	s.set_meta("trail", PackedVector2Array([muzzle]))
	s.set_meta("path", PackedVector2Array([muzzle]))
	s.set_meta("life", 0.0)
	s.set_meta("out", 0.0)
	s.set_meta("mine", mine)
	s.set_meta("from", from.position)
	_shells.append(s)
	Probe.track(s, "!" if mine else "x")
	Probe.event("fire" if mine else "enemy_fire")
	Audio.play("thud")
	Audio.play("impact_metal", 0.15, -6.0)
	Juice.pop(from, 1.3, 0.2)
	Juice.shake(3.0)
	_flight_owner_mine = mine
	_player_hit_this_flight = false
	_dragging = false
	_state = "flying"
	if mine:
		_shots_this_level += 1
		_last_trail = PackedVector2Array()
		_prompt = ""
	else:
		_prompt = "incoming!"

func _enemy_fire() -> void:
	if _enemy == null or not is_instance_valid(_enemy) or _player == null:
		return
	var sol := _solve(_enemy.position, _player.position)
	var aim: Vector2 = sol["aim"]
	# an offset with a floor, not plain noise around zero: the opening shots are meant
	# to land near you, never on you, so there is time to learn the arcs
	var ang_err := _signed(0.4, 1.0) * deg_to_rad(12.0) * _enemy_err
	var len_err := 1.0 + _signed(0.3, 1.0) * 0.15 * _enemy_err
	_enemy_aim = _clamp_aim(aim.rotated(ang_err) * len_err)
	_fire(_enemy, _enemy_aim, false)

func _signed(lo: float, hi: float) -> float:
	return randf_range(lo, hi) * (1.0 if randf() < 0.5 else -1.0)

## ---- play -----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	queue_redraw()
	_move_bits(delta)
	_update_tanks(delta)

	match _state:
		"aim":
			_clock -= delta
			if not _dragging:
				var d := PInput.dir()
				if d != Vector2.ZERO:
					_aim = _clamp_aim(_aim + d * AIM_SPEED * delta)
			if PInput.just_pressed("action_a"):
				_fire(_player, _aim, true)
			elif _clock <= 0.0:
				Probe.event("turn_timeout")
				_prompt = "too slow!"
				_dragging = false
				_state = "think"
				_pause = THINK_TIME
		"flying":
			_move_shells(delta)
			if _shells.is_empty():
				if _enemy == null:
					_state = "levelup"
					_pause = LEVEL_PAUSE
				elif _flight_owner_mine:
					_state = "think"
					_pause = THINK_TIME
					_prompt = "enemy is aiming..."
				else:
					if not _player_hit_this_flight:
						_enemy_err = maxf(0.3, _enemy_err * 0.75)
					_state = "aim"
					_clock = SHOT_CLOCK
					_prompt = "your shot"
					_update_hint()   # tanks fall and craters open: the bot's hint goes stale
		"think":
			_pause -= delta
			if _pause <= 0.0:
				_enemy_fire()
		"levelup":
			_pause -= delta
			if _pause <= 0.0:
				_next_level()
	_update_reticle()

func _update_reticle() -> void:
	if _player != null and is_instance_valid(_player):
		_reticle.position = _player.position + _aim
	_reticle.visible = _state == "aim"

func _update_hint() -> void:
	if _hint == null or _player == null or _enemy == null:
		return
	# keep the old hint while it still works: the bot needs a steady target to settle on,
	# and a fresh solve can jump to a different branch every turn
	if _hint_aim != Vector2.ZERO:
		var still := _trace(_player.position + _hint_aim.normalized() * MUZZLE_LEN,
			_aim_velocity(_hint_aim), _enemy.position, _player.position, SOLVE_MAX_STEPS)
		if still < BLAST_R * 0.4:
			_hint.position = _player.position + _hint_aim
			return
	var sol := _solve(_player.position, _enemy.position)
	_hint_aim = sol["aim"]
	_hint.position = _player.position + _hint_aim
	Probe.event("hint", {"miss": snappedf(sol["miss"], 0.1)})

func _move_shells(delta: float) -> void:
	var keep: Array = []
	for s in _shells:
		if not is_instance_valid(s):
			continue
		var p: Vector2 = s.position
		var v: Vector2 = s.get_meta("vel")
		var life: float = s.get_meta("life")
		var out: float = s.get_meta("out")
		var shooter: Vector2 = s.get_meta("from")
		var mine: bool = s.get_meta("mine")
		var hit: Dictionary = {}
		var steps := maxi(1, int(round(delta / STEP)))
		for i in steps:
			v += _accel(p) * STEP
			p += v * STEP
			life += STEP
			if not in_play_area(p):
				out += STEP
			hit = _collide(p, shooter, life)
			if not hit.is_empty():
				break
		s.position = p
		s.set_meta("vel", v)
		s.set_meta("life", life)
		s.set_meta("out", out)
		var trail: PackedVector2Array = s.get_meta("trail")
		trail.append(p)
		if trail.size() > TRAIL_MAX:
			trail = trail.slice(trail.size() - TRAIL_MAX)
		s.set_meta("trail", trail)
		var path: PackedVector2Array = s.get_meta("path")
		path.append(p)
		s.set_meta("path", path)

		if hit.is_empty() and life < MAX_FLIGHT and out < OFFSCREEN_MAX:
			keep.append(s)
			continue
		if mine:
			_last_trail = path
		s.queue_free()
		if not hit.is_empty() and hit["what"] == "space":
			Probe.event("lost_in_space")
			_prompt = "lost in space"
			continue
		if hit.is_empty():
			# the fuse ran out, in orbit or off screen: it blows up where it is
			Probe.event("fuse")
			_prompt = "fuse ran out"
		_explode(p, mine, life < ARM_TIME)
	_shells = keep

## Every impact is a blast: it bites a crater out of any planet in reach, throws chunks,
## and hurts every tank within BLAST_R -- the enemy, you, or both. A shell that lands
## before it has armed still digs, but spares whoever fired it: shooting the ground at
## your own feet should cost the turn, not a life.
func _explode(at: Vector2, mine: bool, unarmed: bool) -> void:
	Probe.event("blast")
	var carved := _carve(at, CRATER_R)
	if carved:
		Probe.event("crater")
		_boom(at, _nearest_planet_role(at), 12, 120.0)
	Audio.play("explode")
	Juice.hit(5.0)
	_boom(at, "warn", 8, 90.0)

	var hurt_enemy := _blast_damage(_enemy, at)
	var hurt_player := _blast_damage(_player, at)
	if not mine:
		# the enemy's shells start at half strength and reach full by level 6, so the
		# opening levels are about learning the arcs, not surviving them
		hurt_player = int(round(float(hurt_player) * clampf(0.5 + 0.1 * float(_level - 1), 0.5, 1.0)))
	if unarmed:
		if mine:
			hurt_player = 0
		else:
			hurt_enemy = 0
	if hurt_enemy == 0 and hurt_player == 0 and _prompt != "fuse ran out":
		_prompt = ("hit the planet" if carved else "boom") if mine else "it missed you"
	if hurt_enemy > 0:
		_damage_enemy(hurt_enemy, at, not mine)
	if hurt_player > 0:
		_damage_player(hurt_player, mine)

## Damage a blast at `at` does to `tank`: full on a direct hit, tapering to DMG_EDGE at
## the edge of the blast, nothing beyond it.
func _blast_damage(tank: Blob, at: Vector2) -> int:
	if tank == null or not is_instance_valid(tank):
		return 0
	var d := at.distance_to(tank.position)
	if d >= BLAST_R:
		return 0
	var k := clampf((d - HIT_R) / (BLAST_R - HIT_R), 0.0, 1.0)
	return int(round(lerpf(float(DMG_DIRECT), float(DMG_EDGE), k)))

func _nearest_planet_role(at: Vector2) -> String:
	var best := "accent"
	var best_d := INF
	for pl in _planets:
		var d: float = at.distance_to(pl["pos"]) - pl["r"]
		if d < best_d:
			best_d = d
			best = pl["role"]
	return best

func _damage_enemy(dmg: int, at: Vector2, suicide: bool) -> void:
	var hp: int = _enemy.get_meta("hp") - dmg
	_enemy.set_meta("hp", hp)
	Probe.event("enemy_hurt", {"dmg": dmg, "hp": hp})
	Juice.flash(_enemy)
	Juice.text(self, _enemy.position + Vector2(-10, -30), "-%d" % dmg, Palette.col("hazard"))
	if hp > 0:
		add_score(dmg)
		_prompt = "it hurt itself!" if suicide else "hit! -%d" % dmg
		return
	# its own shell coming back round on it is worth something, but not a full kill
	var points := 50 if suicide else maxi(30, 150 - 25 * (_shots_this_level - 1))
	add_score(points)
	Probe.event("hit_enemy", {"level": _level, "shots": _shots_this_level})
	Audio.play("voice_level_up" if _level % 3 == 0 else "voice_correct")
	Juice.hit(8.0)
	Juice.text(self, at + Vector2(-14, -50), "+%d" % points, Palette.col("warn"))
	_boom(_enemy.position, "hazard", 16, 140.0)
	_enemy.queue_free()
	_enemy = null
	_prompt = "it blew itself up!" if suicide else "destroyed!"

func _damage_player(dmg: int, mine: bool) -> void:
	_player_hit_this_flight = true
	var hp: int = _player.get_meta("hp") - dmg
	_player.set_meta("hp", hp)
	Probe.event("self_hit" if mine else "player_hurt", {"dmg": dmg, "hp": hp})
	Audio.play("hurt")
	Juice.hit(7.0)
	Juice.flash(_player)
	Juice.text(self, _player.position + Vector2(-10, -30), "-%d" % dmg, Palette.col("hazard"))
	_prompt = "you hurt yourself! -%d" % dmg if mine else "hit! -%d" % dmg
	if hp <= 0:
		_boom(_player.position, "player", 16, 140.0)
		_prompt = "destroyed"
		lose()

func _boom(at: Vector2, role: String, n: int, speed: float) -> void:
	for i in n:
		var d := Blob.new()
		d.role = role
		d.radius = randf_range(3.0, 5.0)
		d.shape = "diamond"
		add_child(d)
		d.position = at
		d.set_meta("vel", Vector2.from_angle(randf() * TAU) * randf_range(speed * 0.3, speed))
		_bits.append(d)

func _move_bits(delta: float) -> void:
	var keep: Array = []
	for b in _bits:
		if not is_instance_valid(b):
			continue
		var v: Vector2 = b.get_meta("vel")
		v += _accel(b.position) * delta * 0.5
		b.set_meta("vel", v)
		b.position += v * delta
		b.modulate.a = maxf(0.0, b.modulate.a - delta * 1.1)
		if b.modulate.a <= 0.02:
			b.queue_free()
			continue
		keep.append(b)
	_bits = keep

## Drag anywhere: the drag vector is the aim, its length the power. Starting the drag
## away from the tank keeps the thumb off the thing being aimed. A plain tap fires the
## current aim again. Keys drive the same aim point so the bots can play.
func _input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if Flow.pointer_over_hud() or _state != "aim":
				return
			_dragging = true
			_drag_moved = false
			_drag_from = get_global_mouse_position()
			return
		if not _dragging:
			return
		_dragging = false
		if _state == "aim":
			_fire(_player, _aim, true)
		return
	if event is InputEventMouseMotion and _dragging and _state == "aim":
		var d := get_global_mouse_position() - _drag_from
		if d.length() > 8.0:
			_drag_moved = true
		if _drag_moved:
			_aim = _clamp_aim(d)
			_update_reticle()

## ---- the screen ------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")

	for i in _stars.size():
		var tw := 0.35 + 0.35 * sin(_t * 1.7 + _star_phase[i])
		draw_circle(_stars[i], 1.0, Color(ink.r, ink.g, ink.b, tw))

	for i in _planets.size():
		_draw_planet(i)

	if _last_trail.size() > 1:
		var lc := Palette.col("warn")
		for i in range(0, _last_trail.size(), 3):
			draw_circle(_last_trail[i], 1.0, Color(lc.r, lc.g, lc.b, 0.22))

	for s in _shells:
		if not is_instance_valid(s):
			continue
		var trail: PackedVector2Array = s.get_meta("trail")
		var c := Palette.col(s.role)
		for i in trail.size():
			var k := float(i) / float(maxi(1, trail.size()))
			draw_circle(trail[i], 0.8 + k * 2.0, Color(c.r, c.g, c.b, k * 0.55))
		if not in_play_area(s.position):
			_draw_offscreen_marker(s.position, c)

	if _state == "aim" and _player != null and is_instance_valid(_player):
		_draw_preview()
		_draw_clock()
	_draw_tank(_player, _aim)
	_draw_tank(_enemy, _enemy_aim)

	_draw_hp_bars(f)
	_text(f, 480, 92, "level %d" % _level, 18, Palette.col("ink"))
	if _prompt != "":
		_text(f, 480, 520, _prompt, 19, Palette.col("accent"))

## Two long bars at the top, yours on the left and the enemy's on the right, each anchored
## at the outer edge and draining toward the middle, the way a fighting game does it.
func _draw_hp_bars(f: Font) -> void:
	var y := 70.0
	var w := 380.0
	var h := 12.0
	var lx := 40.0
	var rx := play_area.end.x - 40.0 - w
	var bg := Palette.col("bg_alt")
	var edge := Palette.col("bg")
	draw_rect(Rect2(lx - 2, y - 2, w + 4, h + 4), edge)
	draw_rect(Rect2(rx - 2, y - 2, w + 4, h + 4), edge)
	draw_rect(Rect2(lx, y, w, h), bg)
	draw_rect(Rect2(rx, y, w, h), bg)
	var php := _hp_frac(_player)
	var ehp := _hp_frac(_enemy)
	var pc := Palette.col("player") if php > 0.35 else Palette.col("warn")
	var ec := Palette.col("hazard") if ehp > 0.35 else Palette.col("warn")
	draw_rect(Rect2(lx, y, w * php, h), pc)
	draw_rect(Rect2(rx + w * (1.0 - ehp), y, w * ehp, h), ec)
	# labels at the inner ends: the outer right corner is where the shell's menu button sits
	draw_string(f, Vector2(lx, y - 5), "you", HORIZONTAL_ALIGNMENT_LEFT, w, 13, Palette.col("player"))
	draw_string(f, Vector2(rx, y - 5), "enemy", HORIZONTAL_ALIGNMENT_LEFT, w, 13, Palette.col("hazard"))

func _hp_frac(tank: Blob) -> float:
	if tank == null or not is_instance_valid(tank):
		return 0.0
	return clampf(float(tank.get_meta("hp")) / float(MAX_HP), 0.0, 1.0)

## A shell that has gone off screen is still coming back: an arrow on the edge, pointing
## at it, with a hint of how far out it is.
func _draw_offscreen_marker(p: Vector2, c: Color) -> void:
	var inner := play_area.grow(-16.0)
	var edge := p.clamp(inner.position, inner.end)
	var dir := (p - edge).normalized()
	var side := dir.orthogonal()
	var far := clampf(p.distance_to(edge) / SPACE_MARGIN, 0.0, 1.0)
	var size := 12.0 - 4.0 * far
	draw_colored_polygon(PackedVector2Array([edge + dir * size, edge - dir * size * 0.6 + side * size * 0.7,
		edge - dir * size * 0.6 - side * size * 0.7]), Color(c.r, c.g, c.b, 0.9 - 0.4 * far))

func _draw_planet(i: int) -> void:
	var pl: Dictionary = _planets[i]
	var pos: Vector2 = pl["pos"]
	var r: float = pl["r"]
	var hm: PackedFloat32Array = pl["hm"]
	var c := Palette.col(pl["role"])
	var body := Palette.col("bg_alt").lightened(0.12)
	# gravity halo: three faint rings, so the reach of each planet is readable
	for k in [1.45, 1.95, 2.55]:
		draw_arc(pos, r * k, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.11 / k), 1.0, true)
	var pts := PackedVector2Array()
	pts.resize(HM_N + 1)
	for k in HM_N:
		pts[k] = pos + Vector2.from_angle(TAU * float(k) / float(HM_N)) * hm[k]
	pts[HM_N] = pts[0]
	draw_colored_polygon(pts, body)
	draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.10))
	draw_polyline(pts, c, 2.0, true)
	# craters, placed from the planet's seed so they hold still; buried ones vanish with the rock
	var sd: float = pl["seed"]
	for k in 3:
		var a := sd + float(k) * 2.1
		var dist := r * (0.35 + 0.18 * float(k))
		var cr := r * (0.16 - 0.03 * float(k))
		if _surface(i, a) > dist + cr:
			draw_circle(pos + Vector2.from_angle(a) * dist, cr, Palette.col("bg_alt"))

## The Blob is the turret dome; the tracks and barrel are drawn here underneath it.
func _draw_tank(tank: Blob, aim: Vector2) -> void:
	if tank == null or not is_instance_valid(tank):
		return
	var c := Palette.col(tank.role)
	var p: Vector2 = tank.position
	var angle: float = tank.get_meta("angle")
	draw_line(p, p + aim.normalized() * MUZZLE_LEN, c, 4.0)
	draw_set_transform(p, angle + PI * 0.5, Vector2.ONE)
	draw_rect(Rect2(-15, -1, 30, 9), c)
	draw_rect(Rect2(-12, 2, 24, 4), Palette.col("bg_alt"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_preview() -> void:
	var p: Vector2 = _player.position + _aim.normalized() * MUZZLE_LEN
	var v := _aim_velocity(_aim)
	var c := Palette.col("warn")
	var life := 0.0
	for i in PREVIEW_STEPS:
		v += _accel(p) * STEP
		p += v * STEP
		life += STEP
		if not _collide(p, _player.position, life).is_empty():
			break
		if i % 5 == 4:
			var k := 1.0 - float(i) / float(PREVIEW_STEPS)
			draw_circle(p, 2.2, Color(c.r, c.g, c.b, 0.25 + 0.45 * k))
	# the aim point itself, a ring so the shell stays visible under it
	draw_arc(_player.position + _aim, 10.0, 0.0, TAU, 24, Color(c.r, c.g, c.b, 0.6), 2.0, true)

func _draw_clock() -> void:
	var frac := clampf(_clock / SHOT_CLOCK, 0.0, 1.0)
	if frac > 0.5:
		return
	var c := Palette.col("warn") if frac > 0.2 else Palette.col("hazard")
	draw_arc(_player.position, TANK_R + 10.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, c, 3.0, true)

func _text(f: Font, cx: float, y: float, msg: String, size: int, col: Color) -> void:
	draw_string(f, Vector2(cx - 300, y), msg, HORIZONTAL_ALIGNMENT_CENTER, 600, size, col)
