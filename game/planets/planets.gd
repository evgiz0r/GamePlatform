extends GameMode
## planets -- Scorched Earth, but the ground is round and gravity is everywhere. Tanks sit
## on planets on a map bigger than the screen; you tap to aim, press FIRE, and the shell
## bends around every planet on the way while the camera follows it. Every impact is a
## blast: it hurts any tank in range and bites a crater out of the planet, and a tank whose
## ground is gone falls to the new ground. Last tank standing wins the level. See GAME.md.
##
## Turn based, any number of tanks: tank 0 is yours (or the AI's, in AI-vs-AI), the rest
## are AIs. One shell in the air at a time.
##
## A planet is a radial heightmap: HM_N samples of "how far the rock reaches" around the
## centre. Gravity comes from the planet's original size (mass does not leave with the
## chunks), collision and standing use the live surface. Moons are planets with no gravity
## that circle a parent; they are always last in the list so the home planets keep their
## indices when a moon is destroyed.

const SURFACE_G := 450.0            ## gravity at a planet's surface, px/s^2; falls off as 1/r^2
const STEP := 1.0 / 120.0           ## shell physics step; the solver uses the same one
## The camera is zoomed out to 2/3, so the 640x360 viewport shows a 960x540 window (VIEW)
## onto a map one and a half screens wide and tall for two tanks, growing with the tank
## count. Drag to pan; the camera never shows anything beyond the map's edge, follows a
## shell that leaves the view, and comes back to your tank when your turn starts.
const BASE_WORLD := Vector2(1440, 810)
const ZOOM := 2.0 / 3.0
const VIEW := Vector2(960, 540)
const CAM_LERP := 7.0               ## how quickly the camera glides to where it is going
const FOLLOW_MARGIN := 60.0         ## a shell this close to the view's edge pulls the camera along
const FIRE_BTN := Rect2(522, 298, 108, 52)   ## screen px, bottom right, thumb sized
const SPEED_BTN := Rect2(574, 262, 56, 28)   ## 1x / 2x, above FIRE
## Two scroll wheels beside FIRE: drag left or right along one and the value scrolls,
## half a unit per screen px, with a ruler moving under a fixed pointer.
const ANGLE_SCROLL := Rect2(352, 302, 156, 18)
const POWER_SCROLL := Rect2(352, 332, 156, 18)
const SCROLL_STEP := 0.5            ## degrees (or percent) per screen px of drag
## The menu, in screen px.
const MENU_REGULAR := Rect2(200, 128, 240, 40)
const MENU_CUSTOM := Rect2(200, 178, 240, 40)
const MENU_MINUS := Rect2(200, 224, 40, 30)
const MENU_PLUS := Rect2(400, 224, 40, 30)
const MENU_AI := Rect2(200, 264, 240, 30)
const MENU_SPEED := Rect2(200, 300, 240, 30)
const MIN_PLAYERS := 2
const MAX_PLAYERS := 6
## Some big planets get a small moon circling close by: no gravity of its own, but rock
## that a blast can chew up and, with a couple of hits, wipe out entirely. Not too many.
const MOON_CHANCE := 0.5
const MOON_MAX := 3
const MOON_SPEED := 0.16            ## radians per second, give or take
const MAX_FLIGHT := 8.0             ## a shell's fuse: it explodes wherever it is when this runs out
const SPACE_MARGIN := 700.0         ## how far off the map a shell may wander before it is lost
const OFFSCREEN_MAX := 3.0          ## and how long it may stay out there, in total
## Gravity is 1/r^2 near a planet but only 1/r beyond SOFT_R x its radius: far out it pulls
## much harder than a real planet would, so a long shot turns round instead of drifting.
const SOFT_R := 1.5
## Escape speed off the biggest planet is about 300 px/s (sqrt(2 g R)); the range sits
## around it on purpose, because the shots that bend and come back are the ones near it.
const SPEED_MIN := 70.0
const SPEED_MAX := 400.0
const AIM_LEN_MIN := 20.0           ## aim distance that means "minimum power" (world px)
const AIM_LEN_MAX := 150.0          ## aim distance that means "full power"
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
const SHOT_CLOCK := 15.0            ## seconds you get per shot before the turn passes
const THINK_TIME := 0.8             ## an AI's pause before it fires
const LEVEL_PAUSE := 1.6
const PREVIEW_STEPS := 60           ## half a second of predicted flight shown while aiming
const TRAIL_MAX := 90
const STARS_PER_SCREEN := 140
## The shell default (0.8) is loud for a game that explodes every few seconds. In memory
## only -- the saved settings file is never written. See CLAUDE.md.
const SFX_SCALE := 0.35
## Solver grid: coarse sweep, then a refine around the best cell.
const SOLVE_ANGLES := 30
const SOLVE_POWERS := [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0]
const QUICK_ANGLES := 20            ## the cheaper sweep used to check a fresh layout
const QUICK_POWERS := [0.2, 0.4, 0.6, 0.8, 1.0]
const SOLVE_MAX_STEPS := 720        ## six seconds of flight; longer shots exist but are too twitchy to aim for
const FLIGHT_W := 6.0               ## solver: a second of flight costs this many pixels of miss
const PLANET_ROLES := ["accent", "prize", "friend", "warn"]
const AI_ROLES := ["hazard", "prize", "friend", "accent", "warn"]   ## warn last: it is close to your yellow
const HOME_APART := 720.0           ## two home planets are never closer than this ...
const HOME_APART_MANY := 520.0      ## ... or this, once there are more than two

var _planets: Array = []            ## {pos, r, role, seed, hm, moon, parent, orbit_r, orbit_a, orbit_w, marker}
var _ppos := PackedVector2Array()   ## planet centers, mirrored from _planets for the hot loops
var _prad := PackedFloat32Array()   ## original radii (bounding checks)
var _pgrav := PackedFloat32Array()  ## radius that gravity is computed from; 0 for a moon
var _phm: Array = []                ## live heightmaps, one PackedFloat32Array per planet
var _tanks: Array = []              ## Blob, meta: idx, ai, hp, err, aim, planet, angle, alt, vy
var _reticle: Blob = null
var _hint: Node2D = null            ## the solved aim point, tracked for the bots only under PLANETS_AUTOAIM
var _shells: Array = []             ## Blob, meta: vel, trail, path, life, out, from, shooter
var _last_trail := PackedVector2Array()  ## your previous shot, kept on screen to aim the next one
var _bits: Array = []               ## debris Blob, meta: vel
var _stars := PackedVector2Array()
var _star_phase := PackedFloat32Array()

var _state := "menu"                ## menu | aim | flying | think | levelup
var _mode := "regular"              ## regular | custom
var _n_players := 3                 ## tanks in a custom game
var _human_ai := false              ## the AI plays your tank too: nobody has to touch anything
var _speed := 1                     ## 1 or 2: how fast the shot animation runs (never the aiming)
var _turn := 0                      ## whose shot it is, an index into _tanks
var _aim := Vector2(90, -40)        ## your aim: world-space vector from your tank to the aim point
var _cam: Camera2D = null
var _cam_target := Vector2.ZERO
var _pressed := false               ## pointer held down since a press on the map
var _panning := false               ## ... and it has moved far enough to be a drag, not a tap
var _press_scr := Vector2.ZERO      ## where the press landed, in screen px
var _press_cam := Vector2.ZERO      ## where the camera was heading when it did
var _scroll := ""                   ## "angle" or "power" while a scroll wheel is being dragged
var _scroll_x := 0.0                ## last pointer x on that wheel, screen px
var _clock := SHOT_CLOCK
var _pause := 0.0
var _flight_shooter := 0
var _hit_this_flight := false
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
	play_area = Rect2(Vector2.ZERO, BASE_WORLD)

func _ready() -> void:
	title = "planets"
	super()

func start(_config: Dictionary) -> void:
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_autoaim = OS.get_environment("PLANETS_AUTOAIM") == "1"
	_n_players = clampi(int(SaveData.data.get("planets_players", 3)), MIN_PLAYERS, MAX_PLAYERS)
	_human_ai = bool(SaveData.data.get("planets_ai", false))
	_speed = 2 if int(SaveData.data.get("planets_speed", 1)) == 2 else 1

	_cam = Camera2D.new()
	_cam.position = center()
	_cam.zoom = Vector2(ZOOM, ZOOM)
	add_child(_cam)
	_cam.make_current()
	_cam_target = _cam.position

	# no lives: the tanks carry hit points, drawn along the top. An empty lives display is honest.
	set_lives(0)
	_make_stars()

	_reticle = Blob.new()
	_reticle.role = "player"
	_reticle.radius = 6.0
	add_child(_reticle)
	_reticle.visible = false
	Probe.track(_reticle, "@")

	if _autoaim:
		_hint = Node2D.new()
		add_child(_hint)
		Probe.track(_hint, "*")

	_state = "menu"
	# the bots cannot read a menu; a playtest goes straight into the regular game, unless
	# the env asks for another setup (PLANETS_MODE=custom PLANETS_PLAYERS=4 PLANETS_AI=1) or
	# for the menu itself (PLANETS_MENU=1, to screenshot it)
	if Probe.enabled and OS.get_environment("PLANETS_MENU") != "1":
		if OS.get_environment("PLANETS_PLAYERS") != "":
			_n_players = clampi(int(OS.get_environment("PLANETS_PLAYERS")), MIN_PLAYERS, MAX_PLAYERS)
		if OS.get_environment("PLANETS_AI") == "1":
			_human_ai = true
		_begin("custom" if OS.get_environment("PLANETS_MODE") == "custom" else "regular")

func _exit_tree() -> void:
	SaveData.data["volume_sfx"] = _sfx_was

func _make_stars() -> void:
	_stars.clear()
	_star_phase.clear()
	var n := int(STARS_PER_SCREEN * (play_area.size.x * play_area.size.y) / (VIEW.x * VIEW.y))
	for i in n:
		_stars.append(Vector2(randf_range(0, play_area.size.x), randf_range(0, play_area.size.y)))
		_star_phase.append(randf() * TAU)

## ---- menu -------------------------------------------------------------------

func _begin(mode: String) -> void:
	_mode = mode
	_level = 0
	score = 0
	Bus.score_changed.emit(score)
	Probe.event("begin", {"mode": mode, "players": _player_count(), "ai_vs_ai": _human_ai})
	_next_level()

func _player_count() -> int:
	return _n_players if _mode == "custom" else 2

func _save_settings() -> void:
	SaveData.set_value("planets_players", _n_players)
	SaveData.set_value("planets_ai", _human_ai)
	SaveData.set_value("planets_speed", _speed)

## ---- levels ---------------------------------------------------------------

func _next_level() -> void:
	_level += 1
	_shots_this_level = 0
	_last_trail = PackedVector2Array()
	_hint_aim = Vector2.ZERO
	for s in _shells:
		if is_instance_valid(s):
			s.queue_free()
	_shells.clear()
	# freed now, not queued: the level snapshot is taken this same frame
	for t in _tanks:
		if is_instance_valid(t):
			t.free()
	_tanks.clear()

	var n := _player_count()
	_set_world_size(n)
	var layout := _build_layout(_level, n)
	for i in n:
		_spawn_tank(i, layout["homes"][i], layout["angles"][i], i > 0 or _human_ai)
	for pl in _planets:
		var marker := Node2D.new()
		marker.position = pl["pos"]
		add_child(marker)
		pl["marker"] = marker
		Probe.track(marker, "O")

	# start aiming roughly at the nearest enemy so the first tap only has to adjust
	var me: Blob = _tanks[0]
	var foe := _nearest_foe(0)
	var toward: Vector2 = (_tanks[foe].position - me.position).normalized() if foe >= 0 else Vector2.RIGHT
	_aim = _clamp_aim(toward * 90.0)
	for t in _tanks:
		var f := _nearest_foe(t.get_meta("idx"))
		var dir: Vector2 = (_tanks[f].position - t.position).normalized() if f >= 0 else Vector2.UP
		t.set_meta("aim", _clamp_aim(dir * 60.0))
	_update_reticle()
	_update_hint()
	var info := {"level": _level, "planets": _planets.size(), "tanks": n}
	if Probe.enabled:
		# how close the best shot from your tank gets (0 means a clean hit exists) and
		# what one solve costs, since every AI runs it every turn
		var t0 := Time.get_ticks_msec()
		info["miss_me"] = snappedf(_solve(me.position, _tanks[foe].position, false)["miss"], 0.1)
		info["solve_ms"] = Time.get_ticks_msec() - t0
	Probe.event("level_start", info)
	if _level > 1 and _level % 3 == 0:
		Probe.capture("level %d" % _level)
	_turn = _tanks.size() - 1
	_next_turn()
	if _level > 1:
		_prompt = "level %d" % _level

## A bigger map for more tanks: the same room per tank as two get on the base map.
func _set_world_size(n: int) -> void:
	var k := sqrt(float(n) / 2.0)
	play_area = Rect2(Vector2.ZERO, (BASE_WORLD * k).round())
	Probe.world_rect = play_area
	_make_stars()
	# the shell's backdrop grid was sized when the scene was instantiated; resize it too
	var parent := get_parent()
	if parent != null:
		for c in parent.get_children():
			if c is Backdrop:
				c.area = play_area
				c.queue_redraw()

## Returns {homes: [planet index per tank], angles: [surface angle per tank]}. Every level is
## random: home planets well apart, at least four planets of assorted sizes, moons on some
## of the big ones, and the layout checked with the AI's own solver so that every tank has
## someone it can hit.
func _build_layout(level: int, n: int) -> Dictionary:
	var extra := 3 + mini(4, (level - 1) / 2)
	var best: Dictionary = {}
	var best_miss := INF
	for attempt in 8:
		_clear_planets()
		var ok := true
		for i in n:
			if not _place_home(i, n, randf_range(60.0, 110.0)):
				ok = false
		for i in extra:
			if not _place_random(_random_radius()):
				ok = false
		if not ok:
			continue
		_add_moons()
		var homes: Array = []
		var angles: Array = []
		var spots: Array = []
		for i in n:
			homes.append(i)
			var others: Array = []
			for j in n:
				if j != i:
					others.append(_planets[j]["pos"])
			var a := _surface_angle(i, _closest_of(_planets[i]["pos"], others))
			angles.append(a)
			spots.append(_tank_pos(i, a))
		# every tank must be able to reach its nearest neighbour
		var miss := 0.0
		for i in n:
			var others: Array = spots.duplicate()
			others.remove_at(i)
			miss = maxf(miss, _solve(spots[i], _closest_of(spots[i], others), true)["miss"])
		if miss < best_miss:
			best_miss = miss
			best = {"homes": homes, "angles": angles, "planets": _planets.duplicate(true)}
		# a near miss is a hit now that every impact is a blast
		if miss < BLAST_R * 0.7:
			break
	_planets = best["planets"]
	_sync_planets()
	return best

func _closest_of(from: Vector2, points: Array) -> Vector2:
	var best := from
	var best_d := INF
	for p in points:
		var d: float = from.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best

## Small moons are common, giants rare -- a mix reads better than a row of look-alikes.
func _random_radius() -> float:
	var roll := randf()
	if roll < 0.4:
		return randf_range(18.0, 34.0)
	if roll < 0.75:
		return randf_range(34.0, 60.0)
	return randf_range(60.0, 95.0)

## Home planet i of n. With two, one sits in the left third and one in the right, far
## apart, so the duel crosses most of the map; with more they go anywhere, still spaced.
func _place_home(i: int, n: int, r: float) -> bool:
	var apart := HOME_APART if n == 2 else HOME_APART_MANY
	var x0 := play_area.position.x + r + 30.0
	var x1 := play_area.end.x - r - 30.0
	if n == 2:
		var third := play_area.size.x / 3.0
		if i == 0:
			x1 = play_area.position.x + third
		else:
			x0 = play_area.end.x - third
	for attempt in 60:
		var p := Vector2(randf_range(x0, x1), randf_range(play_area.position.y + r + 40.0, play_area.end.y - r - 40.0))
		var clear := true
		for pl in _planets:
			if p.distance_to(pl["pos"]) < apart:
				clear = false
				break
		if clear:
			_add_planet(p, r)
			return true
	return false

func _place_random(r: float) -> bool:
	var inner := play_area.grow(-(r + 30.0))
	for i in 40:
		var p := Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
		var clear := true
		for pl in _planets:
			if p.distance_to(pl["pos"]) < r + pl["r"] + 64.0:
				clear = false
				break
		if clear:
			_add_planet(p, r)
			return true
	return false

## Moons come last in the list, after every planet, so the home planets keep their low
## indices (the tanks refer to them by index) even when a moon is destroyed and removed.
## Each one circles its parent slowly on a ring that stays clear of everything else.
func _add_moons() -> void:
	var n := 0
	var count := _planets.size()
	for i in count:
		var pl: Dictionary = _planets[i]
		if n >= MOON_MAX or pl["r"] < 55.0 or randf() > MOON_CHANCE:
			continue
		for attempt in 12:
			var mr := randf_range(10.0, 16.0)
			var orbit: float = pl["r"] + mr + randf_range(34.0, 52.0)
			var ring_ok := play_area.grow(-(mr + 10.0)).has_point(pl["pos"] - Vector2(orbit, orbit)) \
				and play_area.grow(-(mr + 10.0)).has_point(pl["pos"] + Vector2(orbit, orbit))
			if not ring_ok:
				continue
			var clear := true
			for j in _planets.size():
				if j == i:
					continue
				# the whole ring must miss the other planet, not just the starting spot
				var gap: float = absf(pl["pos"].distance_to(_planets[j]["pos"]) - orbit)
				if gap < _planets[j]["r"] + mr + 16.0:
					clear = false
					break
			if clear:
				var a := randf() * TAU
				_add_planet(pl["pos"] + Vector2.from_angle(a) * orbit, mr, true)
				var moon: Dictionary = _planets[_planets.size() - 1]
				moon["parent"] = i
				moon["orbit_r"] = orbit
				moon["orbit_a"] = a
				moon["orbit_w"] = MOON_SPEED * randf_range(0.7, 1.3) * (1.0 if randf() < 0.5 else -1.0)
				n += 1
				break

func _update_moons(delta: float) -> void:
	var moved := false
	for pl in _planets:
		if not pl["moon"]:
			continue
		var parent: int = pl["parent"]
		if parent < 0 or parent >= _planets.size():
			continue
		pl["orbit_a"] += pl["orbit_w"] * delta
		pl["pos"] = _planets[parent]["pos"] + Vector2.from_angle(pl["orbit_a"]) * pl["orbit_r"]
		if pl.has("marker") and is_instance_valid(pl["marker"]):
			pl["marker"].position = pl["pos"]
		moved = true
	if moved:
		_sync_planets()

func _clear_planets() -> void:
	for pl in _planets:
		if pl.has("marker") and is_instance_valid(pl["marker"]):
			pl["marker"].free()
	_planets.clear()
	_sync_planets()

func _add_planet(pos: Vector2, r: float, moon: bool = false) -> void:
	var role: String = "ink" if (moon or r < 35.0) else PLANET_ROLES[_planets.size() % PLANET_ROLES.size()]
	var hm := PackedFloat32Array()
	hm.resize(HM_N)
	hm.fill(r)
	_planets.append({"pos": pos, "r": r, "role": role, "seed": randf() * TAU, "hm": hm, "moon": moon,
		"parent": -1, "orbit_r": 0.0, "orbit_a": 0.0, "orbit_w": 0.0})
	_sync_planets()

func _sync_planets() -> void:
	_ppos.clear()
	_prad.clear()
	_pgrav.clear()
	_phm.clear()
	for pl in _planets:
		_ppos.append(pl["pos"])
		_prad.append(pl["r"])
		_pgrav.append(0.0 if pl["moon"] else pl["r"])
		_phm.append(pl["hm"])

## A surface angle on planet `on` that faces `toward`, jittered, and that keeps the tank on
## the map and out of any moon's way.
func _surface_angle(on: int, toward: Vector2) -> float:
	var base: float = (toward - _planets[on]["pos"]).angle()
	for i in 12:
		var a := base + randf_range(-1.1, 1.1)
		var spot := _tank_pos(on, a)
		if play_area.grow(-30.0).has_point(spot) and _spot_clear(spot):
			return a
	return base

func _spot_clear(p: Vector2) -> bool:
	for pl in _planets:
		if pl["moon"] and p.distance_to(pl["pos"]) < pl["r"] + TANK_R + 12.0:
			return false
	return true

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
			var t_near := maxf(m - root, 0.0 if pl["moon"] else MIN_ROCK)
			if t_near < hm[k]:
				hm[k] = t_near
				removed = true
		if removed:
			pl["hm"] = hm
			any = true
	if any:
		_drop_dead_moons()
		_sync_planets()
	return any

## A moon with no rock left is gone, with a puff of what it was made of.
func _drop_dead_moons() -> void:
	var keep: Array = []
	for pl in _planets:
		var biggest := 0.0
		for v in pl["hm"]:
			biggest = maxf(biggest, v)
		if pl["moon"] and biggest < 3.0:
			Probe.event("moon_destroyed")
			_boom(pl["pos"], "ink", 10, 90.0)
			if pl.has("marker") and is_instance_valid(pl["marker"]):
				pl["marker"].free()
			continue
		keep.append(pl)
	_planets = keep

func _tank_pos(planet: int, angle: float) -> Vector2:
	return _planets[planet]["pos"] + Vector2.from_angle(angle) * (_surface(planet, angle) + TANK_R)

func _spawn_tank(idx: int, planet: int, angle: float, ai: bool) -> Blob:
	var b := Blob.new()
	b.role = "player" if idx == 0 else AI_ROLES[(idx - 1) % AI_ROLES.size()]
	b.radius = TANK_R * 0.8
	add_child(b)
	b.position = _tank_pos(planet, angle)
	b.set_meta("idx", idx)
	b.set_meta("ai", ai)
	b.set_meta("planet", planet)
	b.set_meta("angle", angle)
	b.set_meta("alt", _surface(planet, angle) + TANK_R)   # distance from the planet centre
	b.set_meta("vy", 0.0)
	b.set_meta("hp", MAX_HP)
	# an AI opens wide of the mark and closes in with every miss; later levels open tighter
	b.set_meta("err", maxf(0.8, 1.5 - 0.06 * float(_level - 1)))
	b.set_meta("aim", Vector2(60, -40))
	_tanks.append(b)
	Probe.track(b, "T" if idx == 0 else ("x" if _autoaim else "*"))
	return b

func _alive(i: int) -> bool:
	return i >= 0 and i < _tanks.size() and is_instance_valid(_tanks[i]) and _tanks[i].get_meta("hp") > 0

func _alive_count() -> int:
	var n := 0
	for i in _tanks.size():
		if _alive(i):
			n += 1
	return n

func _nearest_foe(i: int) -> int:
	var best := -1
	var best_d := INF
	for j in _tanks.size():
		if j == i or not _alive(j):
			continue
		var d: float = _tanks[i].position.distance_to(_tanks[j].position)
		if d < best_d:
			best_d = d
			best = j
	return best

func _is_human_turn() -> bool:
	return _turn == 0 and not _human_ai

## A tank stands on the live surface under it. When that ground is carved away it falls,
## straight down toward the centre, and thuds onto whatever is left.
func _update_tanks(delta: float) -> void:
	for t in _tanks:
		if not is_instance_valid(t) or t.get_meta("hp") <= 0:
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
				Probe.event("tank_landed", {"tank": t.get_meta("idx")})
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

## ---- camera ---------------------------------------------------------------

## Keep a camera centre inside the map, so the view never shows past its edge.
func _clamp_cam(p: Vector2) -> Vector2:
	var half := VIEW * 0.5
	return Vector2(clampf(p.x, play_area.position.x + half.x, play_area.end.x - half.x),
		clampf(p.y, play_area.position.y + half.y, play_area.end.y - half.y))

## The part of the map on screen right now (shake ignored).
func _view_rect() -> Rect2:
	return Rect2(_cam.position - VIEW * 0.5, VIEW)

## Screen px (640x360 space) to world, for HUD drawn in _draw while the camera roams.
func _scr(v: Vector2) -> Vector2:
	return _cam.position + _cam.offset - VIEW * 0.5 + v / ZOOM

func _update_camera(delta: float) -> void:
	if _state == "flying":
		var inner := _view_rect().grow(-FOLLOW_MARGIN)
		for sh in _shells:
			if is_instance_valid(sh) and not inner.has_point(sh.position):
				_cam_target = _clamp_cam(sh.position)
	_cam.position = _cam.position.lerp(_cam_target, 1.0 - exp(-CAM_LERP * delta))

## ---- physics --------------------------------------------------------------

func _accel(p: Vector2) -> Vector2:
	var a := Vector2.ZERO
	for i in _ppos.size():
		var r := _pgrav[i]
		if r <= 0.0:
			continue
		var d := _ppos[i] - p
		var r2 := maxf(d.length_squared(), 100.0)
		var dist := sqrt(r2)
		var soft := r * SOFT_R
		var mag := SURFACE_G * r * r / (r2 if dist <= soft else soft * dist)
		a += d * (mag / dist)
	return a

func _aim_velocity(aim: Vector2) -> Vector2:
	var power := clampf((aim.length() - AIM_LEN_MIN) / (AIM_LEN_MAX - AIM_LEN_MIN), 0.0, 1.0)
	return aim.normalized() * lerpf(SPEED_MIN, SPEED_MAX, power)

## The aim as Scorched Earth would say it: degrees anticlockwise from "right" (so 90 is
## straight up on screen) and power 0-100.
func _aim_angle() -> float:
	return fposmod(-rad_to_deg(_aim.angle()), 360.0)

func _aim_power() -> float:
	return clampf((_aim.length() - AIM_LEN_MIN) / (AIM_LEN_MAX - AIM_LEN_MIN), 0.0, 1.0) * 100.0

func _set_aim(angle_deg: float, power: float) -> void:
	var len := lerpf(AIM_LEN_MIN, AIM_LEN_MAX, clampf(power, 0.0, 100.0) / 100.0)
	_aim = Vector2.from_angle(-deg_to_rad(angle_deg)) * len
	_update_reticle()

func _clamp_aim(v: Vector2) -> Vector2:
	if v.length() < 0.001:
		v = Vector2.RIGHT
	return v.normalized() * clampf(v.length(), AIM_LEN_MIN, AIM_LEN_MAX)

## What a live shell at p has run into: "planet", "tank" (with which), "space", or {}.
## The shooter is immune for the first moments so a shell cannot pop on its own barrel.
func _collide(p: Vector2, shooter: Vector2, life: float) -> Dictionary:
	for t in _tanks:
		if not is_instance_valid(t) or t.get_meta("hp") <= 0:
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
			var r := _pgrav[i]
			if r <= 0.0:
				continue
			var d := _ppos[i] - p
			var r2 := maxf(d.length_squared(), 100.0)
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
## refine around the best cell. Returns {aim, miss}. `quick` is the cheaper grid used to
## check a fresh layout, where a few extra pixels of miss do not matter.
##
## Among shots that get about equally close, the quicker one wins: a long looping flight
## through the far gravity field is hypersensitive, so a shade of noise or a fresh crater
## sends it wide, while a short lob survives both. FLIGHT_W is the price of a second of
## flight, in pixels of miss.
func _solve(from: Vector2, target: Vector2, quick: bool) -> Dictionary:
	var best_aim := (target - from).normalized() * 90.0
	var best_miss := INF
	var best_score := INF
	var angles := QUICK_ANGLES if quick else SOLVE_ANGLES
	var powers: Array = QUICK_POWERS if quick else SOLVE_POWERS
	for i in angles:
		var ang := TAU * float(i) / float(angles)
		for pw in powers:
			var aim := Vector2.from_angle(ang) * lerpf(AIM_LEN_MIN, AIM_LEN_MAX, pw)
			var miss := _trace(from + aim.normalized() * MUZZLE_LEN, _aim_velocity(aim), target, from, SOLVE_MAX_STEPS)
			var sc := miss + float(_trace_steps) * STEP * FLIGHT_W
			if sc < best_score:
				best_score = sc
				best_miss = miss
				best_aim = aim
	var base_ang := best_aim.angle()
	var base_len := best_aim.length()
	var span := AIM_LEN_MAX - AIM_LEN_MIN
	for da in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		for dl in [-0.07, 0.0, 0.07]:
			var aim := Vector2.from_angle(base_ang + deg_to_rad(da)) * clampf(base_len + dl * span, AIM_LEN_MIN, AIM_LEN_MAX)
			var miss := _trace(from + aim.normalized() * MUZZLE_LEN, _aim_velocity(aim), target, from, SOLVE_MAX_STEPS)
			var sc := miss + float(_trace_steps) * STEP * FLIGHT_W
			if sc < best_score:
				best_score = sc
				best_miss = miss
				best_aim = aim
	return {"aim": best_aim, "miss": best_miss}

## ---- turns ----------------------------------------------------------------

## Hand the shot to the next tank still standing; with one (or none) left the level is won.
func _next_turn() -> void:
	if finished:
		return
	if _alive_count() <= 1:
		_state = "levelup"
		_pause = LEVEL_PAUSE
		if _alive(0):
			add_score(100)
			Juice.text(self, _tanks[0].position + Vector2(-20, -50), "+100", Palette.col("warn"))
		Probe.event("level_won", {"level": _level})
		return
	for i in _tanks.size():
		_turn = (_turn + 1) % _tanks.size()
		if _alive(_turn):
			break
	if _is_human_turn():
		_state = "aim"
		_clock = SHOT_CLOCK
		_prompt = "your shot"
		_cam_target = _clamp_cam(_tanks[0].position)   # back home for your turn
		_update_hint()   # tanks fall and craters open: the bot's hint goes stale
	else:
		_state = "think"
		_pause = THINK_TIME
		_prompt = ("%s is aiming..." % _tank_name(_turn))
		# with nobody at the controls, the camera goes to whoever is about to shoot
		if _human_ai:
			_cam_target = _clamp_cam(_tanks[_turn].position)

func _tank_name(i: int) -> String:
	return "you" if i == 0 else "AI %d" % i

func _ai_fire(i: int) -> void:
	var foe := _nearest_foe(i)
	if foe < 0:
		_next_turn()
		return
	var me: Blob = _tanks[i]
	var sol := _solve(me.position, _tanks[foe].position, false)
	var aim: Vector2 = sol["aim"]
	# an offset with a floor, not plain noise around zero: the opening shots are meant
	# to land near the target, never on it, so there is time to learn the arcs
	var err: float = me.get_meta("err")
	var ang_err := _signed(0.4, 1.0) * deg_to_rad(12.0) * err
	var len_err := 1.0 + _signed(0.3, 1.0) * 0.15 * err
	me.set_meta("aim", _clamp_aim(aim.rotated(ang_err) * len_err))
	_fire(i, me.get_meta("aim"))

func _signed(lo: float, hi: float) -> float:
	return randf_range(lo, hi) * (1.0 if randf() < 0.5 else -1.0)

func _fire(shooter: int, aim: Vector2) -> void:
	var from: Blob = _tanks[shooter]
	var muzzle: Vector2 = from.position + aim.normalized() * MUZZLE_LEN
	var s := Blob.new()
	s.role = "warn" if shooter == 0 else from.role
	s.radius = 5.0
	add_child(s)
	s.position = muzzle
	s.set_meta("vel", _aim_velocity(aim))
	s.set_meta("trail", PackedVector2Array([muzzle]))
	s.set_meta("path", PackedVector2Array([muzzle]))
	s.set_meta("life", 0.0)
	s.set_meta("out", 0.0)
	s.set_meta("from", from.position)
	s.set_meta("shooter", shooter)
	_shells.append(s)
	Probe.track(s, "!" if shooter == 0 else "x")
	Probe.event("fire" if shooter == 0 else "enemy_fire")
	Audio.play("thud")
	Audio.play("impact_metal", 0.15, -6.0)
	Juice.pop(from, 1.3, 0.2)
	Juice.shake(3.0)
	_flight_shooter = shooter
	_hit_this_flight = false
	_state = "flying"
	if shooter == 0:
		_shots_this_level += 1
		_last_trail = PackedVector2Array()
		_prompt = ""
	else:
		_prompt = "incoming!"

## ---- play -----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished:
		return
	_t += delta
	queue_redraw()
	if _state == "menu":
		if PInput.just_pressed("action_a"):
			_begin("regular")
		return
	# the speed option runs the shot faster; aiming, thinking and falling stay at 1x
	var sim := delta * (float(_speed) if _state == "flying" else 1.0)
	_update_moons(sim)
	_move_bits(sim)
	_update_tanks(sim)
	_update_camera(delta)

	match _state:
		"aim":
			_clock -= delta
			var d := PInput.dir()
			if d != Vector2.ZERO:
				_aim = _clamp_aim(_aim + d * AIM_SPEED * delta)
			if PInput.just_pressed("action_a"):
				_fire(0, _aim)
			elif _clock <= 0.0:
				Probe.event("turn_timeout")
				_prompt = "too slow!"
				_next_turn()
		"flying":
			_move_shells(sim)
			if _shells.is_empty():
				var shooter: Blob = _tanks[_flight_shooter]
				if is_instance_valid(shooter) and shooter.get_meta("ai") and not _hit_this_flight:
					shooter.set_meta("err", maxf(0.25, shooter.get_meta("err") * 0.65))
				_next_turn()
		"think":
			_pause -= delta
			if _pause <= 0.0:
				_ai_fire(_turn)
		"levelup":
			_pause -= delta
			if _pause <= 0.0:
				_next_level()
	_update_reticle()

func _update_reticle() -> void:
	if _reticle == null:
		return
	if _alive(0):
		_reticle.position = _tanks[0].position + _aim
	_reticle.visible = _state == "aim"

func _update_hint() -> void:
	if _hint == null or not _alive(0):
		return
	var foe := _nearest_foe(0)
	if foe < 0:
		return
	var me: Vector2 = _tanks[0].position
	var target: Vector2 = _tanks[foe].position
	# keep the old hint while it still works: the bot needs a steady target to settle on,
	# and a fresh solve can jump to a different branch every turn
	if _hint_aim != Vector2.ZERO:
		var still := _trace(me + _hint_aim.normalized() * MUZZLE_LEN, _aim_velocity(_hint_aim), target, me, SOLVE_MAX_STEPS)
		if still < BLAST_R * 0.4:
			_hint.position = me + _hint_aim
			return
	var sol := _solve(me, target, false)
	_hint_aim = sol["aim"]
	_hint.position = me + _hint_aim
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
		var shooter_pos: Vector2 = s.get_meta("from")
		var shooter: int = s.get_meta("shooter")
		var hit: Dictionary = {}
		var steps := maxi(1, int(round(delta / STEP)))
		for i in steps:
			v += _accel(p) * STEP
			p += v * STEP
			life += STEP
			if not in_play_area(p):
				out += STEP
			hit = _collide(p, shooter_pos, life)
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
		if shooter == 0:
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
		_explode(p, shooter, life < ARM_TIME)
	_shells = keep

## Every impact is a blast: it bites a crater out of any planet in reach, throws chunks,
## and hurts every tank within BLAST_R -- friend, foe, or the one that fired. A shell that
## lands before it has armed still digs, but spares whoever fired it: shooting the ground
## at your own feet should cost the turn, not a life.
func _explode(at: Vector2, shooter: int, unarmed: bool) -> void:
	Probe.event("blast")
	var carved := _carve(at, CRATER_R)
	if carved:
		Probe.event("crater")
		_boom(at, _nearest_planet_role(at), 12, 120.0)
	Audio.play("explode")
	Juice.hit(5.0)
	_boom(at, "warn", 8, 90.0)

	var anyone := false
	for i in _tanks.size():
		if not _alive(i):
			continue
		var dmg := _blast_damage(_tanks[i], at)
		if dmg == 0 or (unarmed and i == shooter):
			continue
		if i == 0 and shooter != 0 and not _human_ai:
			# the AIs' shells start at half strength against you and reach full by level 6,
			# so the opening levels are about learning the arcs, not surviving them
			dmg = int(round(float(dmg) * clampf(0.5 + 0.1 * float(_level - 1), 0.5, 1.0)))
		anyone = true
		_damage(i, dmg, at, shooter)
	if not anyone and _prompt != "fuse ran out":
		_prompt = ("hit the planet" if carved else "boom") if shooter == 0 else "it missed"

## Damage a blast at `at` does to `tank`: full on a direct hit, tapering to DMG_EDGE at
## the edge of the blast, nothing beyond it.
func _blast_damage(tank: Blob, at: Vector2) -> int:
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

func _damage(i: int, dmg: int, at: Vector2, by: int) -> void:
	var t: Blob = _tanks[i]
	var hp: int = t.get_meta("hp") - dmg
	t.set_meta("hp", hp)
	_hit_this_flight = _hit_this_flight or i != by
	Juice.flash(t)
	Juice.text(self, t.position + Vector2(-10, -30), "-%d" % dmg, Palette.col("hazard"))
	if i == 0:
		Probe.event("self_hit" if by == 0 else "player_hurt", {"dmg": dmg, "hp": hp})
		Audio.play("hurt")
		Juice.hit(7.0)
		_prompt = "you hurt yourself! -%d" % dmg if by == 0 else "hit! -%d" % dmg
	else:
		Probe.event("enemy_hurt", {"tank": i, "dmg": dmg, "hp": hp})
		if by == 0:
			add_score(dmg)
			_prompt = "hit! -%d" % dmg
		elif by == i:
			_prompt = "%s hurt itself!" % _tank_name(i)
	if hp <= 0:
		_destroy(i, at, by)

func _destroy(i: int, at: Vector2, by: int) -> void:
	var t: Blob = _tanks[i]
	_boom(t.position, t.role, 16, 140.0)
	t.visible = false
	Juice.hit(8.0)
	if i == 0:
		Probe.event("player_destroyed")
		_prompt = "destroyed"
		if not _human_ai:
			lose()
		return
	var points := 50 if by == i else maxi(30, 150 - 25 * (_shots_this_level - 1))
	Probe.event("hit_enemy", {"level": _level, "tank": i, "shots": _shots_this_level})
	if by == 0:
		add_score(points)
		Juice.text(self, at + Vector2(-14, -50), "+%d" % points, Palette.col("warn"))
		Audio.play("voice_level_up" if _level % 3 == 0 else "voice_correct")
	_prompt = ("%s blew itself up!" % _tank_name(i)) if by == i else ("%s destroyed!" % _tank_name(i))

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

## ---- input ------------------------------------------------------------------

## Tap anywhere on the map and the aim point goes there. Drag and the map pans. Fire is a
## separate control: the big button bottom right, a tap on your own tank, or space. The
## wheels beside FIRE scroll the angle and the power. The keys nudge the same aim point so
## the bots can play. In the menu, taps pick options.
func _input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var scr := get_viewport().get_mouse_position()
		if mb.pressed:
			if Flow.pointer_over_hud():
				return
			if _state == "menu":
				_menu_press(scr)
				return
			if SPEED_BTN.has_point(scr):
				_speed = 3 - _speed
				_save_settings()
				Audio.play("click")
				return
			if _is_human_turn() and _state == "aim":
				if FIRE_BTN.has_point(scr):
					_fire(0, _aim)
					return
				if ANGLE_SCROLL.grow(6.0).has_point(scr):
					_scroll = "angle"
					_scroll_x = scr.x
					return
				if POWER_SCROLL.grow(6.0).has_point(scr):
					_scroll = "power"
					_scroll_x = scr.x
					return
			_pressed = true
			_panning = false
			_press_scr = scr
			_press_cam = _cam_target
			return
		_scroll = ""
		if not _pressed:
			return
		_pressed = false
		if _panning or _state != "aim" or not _is_human_turn():
			return
		# a tap: on your tank it fires, anywhere else it puts the aim point there
		var world := get_global_mouse_position()
		if world.distance_to(_tanks[0].position) < TANK_R * 2.4:
			_fire(0, _aim)
		else:
			_aim = _clamp_aim(world - _tanks[0].position)
			_update_reticle()
		return
	if event is InputEventMouseMotion and _scroll != "":
		var x := get_viewport().get_mouse_position().x
		var dx := (x - _scroll_x) * SCROLL_STEP
		_scroll_x = x
		if _state == "aim":
			if _scroll == "angle":
				_set_aim(_aim_angle() + dx, _aim_power())
			else:
				_set_aim(_aim_angle(), _aim_power() + dx)
		return
	if event is InputEventMouseMotion and _pressed:
		var scr := get_viewport().get_mouse_position()
		var d := scr - _press_scr
		if not _panning and d.length() > 12.0:
			_panning = true
		if _panning and _state != "flying":
			_cam_target = _clamp_cam(_press_cam - d / ZOOM)

func _menu_press(scr: Vector2) -> void:
	if MENU_REGULAR.has_point(scr):
		Audio.play("select")
		_begin("regular")
	elif MENU_CUSTOM.has_point(scr):
		Audio.play("select")
		_begin("custom")
	elif MENU_MINUS.has_point(scr):
		_n_players = maxi(MIN_PLAYERS, _n_players - 1)
		Audio.play("click")
		_save_settings()
	elif MENU_PLUS.has_point(scr):
		_n_players = mini(MAX_PLAYERS, _n_players + 1)
		Audio.play("click")
		_save_settings()
	elif MENU_AI.has_point(scr):
		_human_ai = not _human_ai
		Audio.play("click")
		_save_settings()
	elif MENU_SPEED.has_point(scr):
		_speed = 3 - _speed
		Audio.play("click")
		_save_settings()

## ---- the screen ------------------------------------------------------------

func _draw() -> void:
	var f: Font = ThemeDB.fallback_font
	var ink := Palette.col("ink")

	for i in _stars.size():
		var tw := 0.35 + 0.35 * sin(_t * 1.7 + _star_phase[i])
		draw_circle(_stars[i], 1.0, Color(ink.r, ink.g, ink.b, tw))

	if _state == "menu":
		_draw_menu(f)
		return

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
		if not _view_rect().has_point(s.position):
			_draw_offscreen_marker(s.position, c)

	if _state == "aim" and _alive(0):
		_draw_preview()
		_draw_clock()
	for t in _tanks:
		_draw_tank(t, _aim if t.get_meta("idx") == 0 else t.get_meta("aim"))

	_draw_hp_bars(f)
	_draw_speed_button(f)
	if not _human_ai:
		_draw_fire_button(f)
		_draw_scroll(f, ANGLE_SCROLL, "angle", _aim_angle(), 10.0, 30.0, "%d°" % int(round(_aim_angle())))
		_draw_scroll(f, POWER_SCROLL, "power", _aim_power(), 5.0, 25.0, "%d%%" % int(round(_aim_power())))
	# between the two bars, or under the row of them when there are more
	_text(f, _scr(Vector2(320, 58 if _tanks.size() <= 2 else 74)), "level %d" % _level, 18, Palette.col("ink"))
	if _prompt != "":
		draw_string(f, _scr(Vector2(20, 346)), _prompt, HORIZONTAL_ALIGNMENT_LEFT, 320.0 / ZOOM, 19, Palette.col("accent"))

func _draw_menu(f: Font) -> void:
	_text(f, _scr(Vector2(320, 92)), "planets", 44, Palette.col("player"))
	_text(f, _scr(Vector2(320, 114)), "scorched earth, but the ground is round", 16, Palette.col("accent"))
	_draw_button(f, MENU_REGULAR, "regular game", true, "player")
	_draw_button(f, MENU_CUSTOM, "custom game", true, "prize")
	_draw_button(f, MENU_MINUS, "-", true, "bg_alt")
	_draw_button(f, MENU_PLUS, "+", true, "bg_alt")
	_text(f, _scr(Vector2(320, 246)), "%d tanks" % _n_players, 17, Palette.col("ink"))
	_draw_button(f, MENU_AI, "AI plays your tank too: %s" % ("on" if _human_ai else "off"), true,
		"warn" if _human_ai else "bg_alt")
	_draw_button(f, MENU_SPEED, "shot speed: %dx" % _speed, true, "warn" if _speed == 2 else "bg_alt")
	_text(f, _scr(Vector2(320, 350)), "custom: you and %d AIs on a bigger map. AI on: sit back and watch."
		% (_n_players - 1), 12, Palette.col("ink").darkened(0.3))

## A screen-space button drawn in world coordinates via _scr.
func _draw_button(f: Font, r: Rect2, label: String, live: bool, role: String) -> void:
	var box := Rect2(_scr(r.position), r.size / ZOOM)
	var c := Palette.col(role)
	draw_rect(box.grow(3.0), Palette.col("bg"))
	draw_rect(box, c)
	draw_rect(box, Palette.col("ink") if live else Palette.col("bg_alt").lightened(0.2), false, 2.0)
	var dark := role == "bg_alt"
	draw_string(f, box.position + Vector2(0, box.size.y * 0.68), label, HORIZONTAL_ALIGNMENT_CENTER, box.size.x,
		int(r.size.y * 0.55 / ZOOM) if r.size.y < 36 else 24, Palette.col("ink") if dark else Palette.col("bg"))

## A shell that has gone off screen is still coming back: an arrow on the edge, pointing
## at it, with a hint of how far out it is.
func _draw_offscreen_marker(p: Vector2, c: Color) -> void:
	var inner := _view_rect().grow(-24.0)
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
	# gravity halo: three faint rings, so the reach of each planet is readable (moons have none)
	if not pl["moon"]:
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
	for k in (1 if pl["moon"] else 3):
		var a := sd + float(k) * 2.1
		var dist := r * (0.35 + 0.18 * float(k))
		var cr := r * (0.16 - 0.03 * float(k))
		if _surface(i, a) > dist + cr:
			draw_circle(pos + Vector2.from_angle(a) * dist, cr, Palette.col("bg_alt"))

## The Blob is the turret dome; the tracks and barrel are drawn here underneath it.
func _draw_tank(tank: Blob, aim: Vector2) -> void:
	if tank == null or not is_instance_valid(tank) or tank.get_meta("hp") <= 0:
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
	var me: Vector2 = _tanks[0].position
	var p: Vector2 = me + _aim.normalized() * MUZZLE_LEN
	var v := _aim_velocity(_aim)
	var c := Palette.col("warn")
	var life := 0.0
	for i in PREVIEW_STEPS:
		v += _accel(p) * STEP
		p += v * STEP
		life += STEP
		if not _collide(p, me, life).is_empty():
			break
		if i % 5 == 4:
			var k := 1.0 - float(i) / float(PREVIEW_STEPS)
			draw_circle(p, 2.2, Color(c.r, c.g, c.b, 0.25 + 0.45 * k))
	# the aim point itself, a ring so the shell stays visible under it
	draw_arc(me + _aim, 10.0, 0.0, TAU, 24, Color(c.r, c.g, c.b, 0.6), 2.0, true)

func _draw_clock() -> void:
	var frac := clampf(_clock / SHOT_CLOCK, 0.0, 1.0)
	if frac > 0.5:
		return
	var c := Palette.col("warn") if frac > 0.2 else Palette.col("hazard")
	draw_arc(_tanks[0].position, TANK_R + 10.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 32, c, 3.0, true)

func _draw_fire_button(f: Font) -> void:
	var live := _state == "aim"
	var c := Palette.col("warn") if live else Palette.col("bg_alt")
	var r := Rect2(_scr(FIRE_BTN.position), FIRE_BTN.size / ZOOM)
	draw_rect(r.grow(3.0), Palette.col("bg"))
	draw_rect(r, c)
	draw_rect(r, Palette.col("ink") if live else Palette.col("bg_alt").lightened(0.2), false, 2.0)
	draw_string(f, r.position + Vector2(0, r.size.y * 0.66), "FIRE", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 27,
		Palette.col("bg") if live else Palette.col("ink").darkened(0.5))

func _draw_speed_button(f: Font) -> void:
	_draw_button(f, SPEED_BTN, "%dx" % _speed, true, "warn" if _speed == 2 else "bg_alt")

## A scroll wheel: a ruler that slides under a fixed pointer as the value changes. Minor
## ticks every `minor`, taller ones every `major`. Reads as a dial, drags like a wheel.
func _draw_scroll(f: Font, r: Rect2, label: String, value: float, minor: float, major: float, text: String) -> void:
	var live := _state == "aim"
	var box := Rect2(_scr(r.position), r.size / ZOOM)
	draw_rect(box.grow(2.0), Palette.col("bg"))
	draw_rect(box, Palette.col("bg_alt"))
	var ink := Palette.col("ink") if live else Palette.col("ink").darkened(0.55)
	var cx := r.position.x + r.size.x * 0.5
	var half := r.size.x * 0.5 * SCROLL_STEP          # how much value fits either side of the pointer
	var first := floorf((value - half) / minor) * minor
	var v := first
	while v <= value + half:
		var x := cx + (v - value) / SCROLL_STEP
		if x >= r.position.x + 2.0 and x <= r.end.x - 2.0:
			var is_major := fmod(absf(v), major) < 0.01
			var h := (r.size.y * 0.7) if is_major else (r.size.y * 0.35)
			draw_line(_scr(Vector2(x, r.end.y - 1.0)), _scr(Vector2(x, r.end.y - 1.0 - h)), Color(ink.r, ink.g, ink.b, 0.55), 1.5)
		v += minor
	var pc := Palette.col("warn") if live else Palette.col("bg_alt").lightened(0.3)
	draw_line(_scr(Vector2(cx, r.position.y - 3.0)), _scr(Vector2(cx, r.end.y + 1.0)), pc, 3.0)
	draw_string(f, _scr(Vector2(r.position.x, r.position.y - 4.0)), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x / ZOOM, 16, ink)
	draw_string(f, _scr(Vector2(r.position.x, r.position.y - 4.0)), text, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x / ZOOM, 16, pc)

## HP along the top. Two tanks: fighting-game style, yours left, theirs right, draining
## toward the middle. More: a row of shorter bars, one per tank, in each tank's colour.
func _draw_hp_bars(f: Font) -> void:
	var y := 46.0
	var h := 9.0
	var n := _tanks.size()
	if n <= 2:
		var w := 248.0
		var lx := 28.0
		var rx := 640.0 - 28.0 - w
		_draw_bar(f, Rect2(lx, y, w, h), 0, false)
		if n == 2:
			_draw_bar(f, Rect2(rx, y, w, h), 1, true)
		return
	var gap := 8.0
	var w := (584.0 - gap * float(n - 1)) / float(n)
	for i in n:
		_draw_bar(f, Rect2(28.0 + float(i) * (w + gap), y, w, h), i, false)

func _draw_bar(f: Font, r: Rect2, i: int, from_right: bool) -> void:
	var t: Blob = _tanks[i]
	var frac := clampf(float(t.get_meta("hp")) / float(MAX_HP), 0.0, 1.0)
	var c := Palette.col(t.role) if frac > 0.35 else Palette.col("warn")
	draw_rect(Rect2(_scr(r.position - Vector2(2, 2)), (r.size + Vector2(4, 4)) / ZOOM), Palette.col("bg"))
	draw_rect(Rect2(_scr(r.position), r.size / ZOOM), Palette.col("bg_alt"))
	var x := r.position.x + (r.size.x * (1.0 - frac) if from_right else 0.0)
	draw_rect(Rect2(_scr(Vector2(x, r.position.y)), Vector2(r.size.x * frac, r.size.y) / ZOOM), c)
	var label := _tank_name(i) + (" (AI)" if i == 0 and _human_ai else "")
	draw_string(f, _scr(Vector2(r.position.x, r.position.y - 4.0)), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x / ZOOM,
		18 if _tanks.size() <= 2 else 14, Palette.col(t.role))

func _text(f: Font, at: Vector2, msg: String, size: int, col: Color) -> void:
	draw_string(f, at - Vector2(300, 0), msg, HORIZONTAL_ALIGNMENT_CENTER, 600, size, col)
