extends GameMode
## getaway -- a top-down neon city at night. You drive: answer a ringing payphone, then
## race the hot case across town before the clock runs out. Every delivery adds a wanted
## star and one more police car on your tail; a cop that touches you is a bust, and three
## busts end the run. See GAME.md.
##
## The city is a grid of 32px tiles: every sixth row and column pair is a two-lane road,
## and the 4x4 tiles between are a block (a building or a park). Cars are circles pushed
## out of block rectangles -- no physics nodes. Cops follow a breadth-first flow field over
## the drivable tiles, rebuilt from the player's tile a few times a second. Traffic rides
## its lane tile to tile and turns at junctions. Roofs are redrawn every frame shifted away
## from the screen centre (taller = further), which is what makes the buildings stand up.

const TILE := 32.0
const PERIOD := 6                ## tiles from one road to the next
const CELL := 192.0              ## PERIOD * TILE
const ROAD := 64.0               ## two lanes
const BLOCKS_X := 7
const BLOCKS_Y := 5
const COLS := BLOCKS_X * PERIOD + 2
const ROWS := BLOCKS_Y * PERIOD + 2
const SIDEWALK := 7.0
const CAR_R := 9.0
const PLAYER_TOP := 240.0
const PLAYER_ACCEL := 340.0
const GRIP := 10.0
const COP_TOP := 150.0
const COP_DELAY := 3.0           ## seconds of calm before the first siren
const START_LIVES := 3
const MAX_STARS := 5
const INVULN := 2.5
const RETREAT := 3.0             ## after a bust the cops drive away this long
const TRAFFIC := 16
const PEDS := 30
const PARALLAX := 0.1
const BUST_TIME := 0.9           ## seconds of a cop touching you (half that if you are stopped)
const SFX_SCALE := 0.28          ## the shell default is loud; in memory only, see CLAUDE.md
const MUSIC_SCALE := 0.45
const MUSIC := "on_the_offensive"
const ROOF_ROLES := ["accent", "friend", "warn", "prize"]
const CAR_ROLES := ["friend", "ink", "warn", "prize"]
const PED_ROLES := ["ink", "friend", "warn", "accent", "prize"]
const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

## Every car on the map. A Blob, so it reskins with the palette, but drawn as a car.
## The node's rotation is its heading; it is drawn pointing along +x.
class Car extends Blob:
	var vel := Vector2.ZERO
	var heading := 0.0
	var spin := 0.0              ## visual-only twist after a knock (traffic)
	var siren := false
	var lights_on := false
	var stun := 0.0
	var stuck := 0.0
	var crash_cd := 0.0
	# traffic: drives from `from` to the centre of tile `to`, prog 0..1
	var to := Vector2i.ZERO
	var dir := Vector2i.RIGHT
	var from := Vector2.ZERO
	var prog := 0.0
	var speed := 70.0
	var wait := 0.0
	var knocked := 0.0
	# rear wheel positions last frame, for skid marks (INF = not skidding)
	var skid_l := Vector2.INF
	var skid_r := Vector2.INF

	func _draw() -> void:
		var c := Palette.col(role)
		var hl := 12.0
		var hw := 6.5
		var beam := Palette.col("warn")
		draw_colored_polygon(PackedVector2Array([Vector2(hl, -hw + 1), Vector2(hl + 70, -26),
			Vector2(hl + 70, 26), Vector2(hl, hw - 1)]), Color(beam.r, beam.g, beam.b, 0.05))
		draw_colored_polygon(PackedVector2Array([Vector2(hl, -hw + 2), Vector2(hl + 36, -12),
			Vector2(hl + 36, 12), Vector2(hl, hw - 2)]), Color(beam.r, beam.g, beam.b, 0.06))
		draw_rect(Rect2(-hl + 2, -hw + 3, hl * 2, hw * 2), Color(0, 0, 0, 0.45))
		if glow:
			draw_rect(Rect2(-hl - 4, -hw - 4, hl * 2 + 8, hw * 2 + 8), Color(c.r, c.g, c.b, 0.10))
			draw_rect(Rect2(-hl - 2, -hw - 2, hl * 2 + 4, hw * 2 + 4), Color(c.r, c.g, c.b, 0.16))
		draw_rect(Rect2(-hl, -hw, hl * 2, hw * 2), c.darkened(0.35))
		draw_rect(Rect2(-hl + 1, -hw + 1, hl * 2 - 2, hw * 2 - 2), c)
		var glass := Color(0.03, 0.03, 0.08, 0.9)
		draw_rect(Rect2(3.0, -hw + 1.5, 4.5, hw * 2 - 3), glass)
		draw_rect(Rect2(-6.0, -hw + 1.5, 9.0, hw * 2 - 3), c.lightened(0.28))
		draw_rect(Rect2(-9.5, -hw + 2, 3.5, hw * 2 - 4), glass)
		var head := Color(1, 1, 0.85)
		draw_rect(Rect2(hl - 2, -hw + 0.5, 2, 2.5), head)
		draw_rect(Rect2(hl - 2, hw - 3, 2, 2.5), head)
		var tail := Palette.col("hazard")
		draw_rect(Rect2(-hl, -hw + 0.5, 1.5, 2.5), tail)
		draw_rect(Rect2(-hl, hw - 3, 1.5, 2.5), tail)
		if siren:
			var a := Palette.col("hazard")
			var b := Palette.col("player")
			var lit := a if lights_on else b
			draw_circle(Vector2(-1.5, 0), 18.0, Color(lit.r, lit.g, lit.b, 0.16))
			draw_circle(Vector2(-1.5, 0), 9.0, Color(lit.r, lit.g, lit.b, 0.22))
			draw_rect(Rect2(-3.5, -hw + 1, 4, hw - 1), a if lights_on else a.darkened(0.6))
			draw_rect(Rect2(-3.5, 0, 4, hw - 1), b.darkened(0.6) if lights_on else b)

var _blocks: Array = []          ## by * BLOCKS_X + bx -> {interior, solid, kind, parts, trees}
var _drive_map := PackedByteArray()   ## 1 = a car may be on this tile (road or park)
var _flow := PackedInt32Array()  ## steps to the player's tile, -1 = unreachable
var _flow_t := 0.0
var _player: Car
var _cops: Array = []
var _traffic: Array = []
var _peds: Array = []
var _marker: Blob
var _cam: Camera2D
var _ground: Node2D
var _skid_node: Node2D
var _fx_node: Node2D
var _roofs: Node2D
var _top: Node2D
var _hud: Node2D
var _job_label: Label
var _banner: Label
var _banner_tw: Tween
var _skids: Array = []           ## [a, b, life]
var _fx: Array = []              ## particles: {p, v, life, max, r, role, kind}
var _stars := 1
var _job := "phone"              ## phone | drop
var _job_t := 0.0
var _deliveries := 0
var _invuln := 0.0
var _bust := 0.0                 ## 0..1, fills while a cop is on you
var _t := 0.0
var _siren_t := 0.0
var _puff_t := 0.0
var _cop_near := false
var _stick_on := false
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _started := false
var _sfx_was := 0.8
var _music_was := 0.7
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	title = "getaway"
	play_area = Rect2(0, 0, COLS * TILE, ROWS * TILE)
	super()

func start(_config: Dictionary) -> void:
	_started = true
	_sfx_was = float(SaveData.data.get("volume_sfx", 0.8))
	SaveData.data["volume_sfx"] = _sfx_was * SFX_SCALE
	_music_was = float(SaveData.data.get("volume_music", 0.7))
	SaveData.data["volume_music"] = _music_was * MUSIC_SCALE

	# The same city every run, so its streets can be learned. Everything else is random.
	_rng.seed = 1997
	_build_city()
	_rng.randomize()

	_ground = _layer(-10, _draw_ground)
	_skid_node = _layer(-9, _draw_skids)
	_fx_node = _layer(4, _draw_fx)
	_roofs = _layer(10, _draw_roofs)
	_top = _layer(20, _draw_top)
	Bus.palette_changed.connect(_ground.queue_redraw)

	_player = _make_car("player")
	_player.position = Vector2(18 * TILE + TILE, 12 * TILE + TILE)   # a central junction
	_player.heading = -PI * 0.5
	_player.rotation = _player.heading
	Probe.track(_player, "@")

	_cam = Camera2D.new()
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(play_area.size.x)
	_cam.limit_bottom = int(play_area.size.y)
	_cam.position = _player.position
	add_child(_cam)
	_cam.make_current()

	_marker = Blob.new()
	_marker.role = "prize"
	_marker.shape = "diamond"
	_marker.radius = 7.0
	_marker.z_index = 15
	add_child(_marker)
	Probe.track(_marker, "*")

	for i in TRAFFIC:
		_spawn_traffic()
	for i in PEDS:
		_spawn_ped()
	_build_hud()

	set_lives(START_LIVES)
	_stars = 1
	_new_phone()
	_rebuild_flow()
	_show_banner("answer the phone", "prize")
	Audio.play("voice_go")

func _exit_tree() -> void:
	if not _started:
		return
	SaveData.data["volume_sfx"] = _sfx_was
	SaveData.data["volume_music"] = _music_was
	Audio.stop_music()

func _layer(z: int, painter: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.draw.connect(painter)
	add_child(n)
	return n

func _make_car(role: String) -> Car:
	var c := Car.new()
	c.role = role
	c.z_index = 2
	add_child(c)
	return c

## ---- the city ----------------------------------------------------------------

func _build_city() -> void:
	_blocks.clear()
	for by in BLOCKS_Y:
		for bx in BLOCKS_X:
			var interior := Rect2(bx * CELL + ROAD, by * CELL + ROAD, CELL - ROAD, CELL - ROAD)
			var park := _rng.randf() < 0.2
			var b := {
				"interior": interior,
				"solid": interior.grow(-SIDEWALK),
				"kind": "park" if park else "building",
				"parts": [],
				"trees": [],
			}
			if park:
				var trees: Array = []
				for k in _rng.randi_range(6, 9):
					trees.append({
						"p": interior.position + Vector2(_rng.randf_range(16, 112), _rng.randf_range(16, 112)),
						"r": _rng.randf_range(8.0, 14.0),
					})
				b["trees"] = trees
			else:
				b["parts"] = _make_parts(b["solid"])
			_blocks.append(b)

	_drive_map.resize(COLS * ROWS)
	for y in ROWS:
		for x in COLS:
			var t := Vector2i(x, y)
			var ok := _is_road(t)
			if not ok:
				var b := _block(floori(x / float(PERIOD)), floori(y / float(PERIOD)))
				ok = not b.is_empty() and b["kind"] == "park"
			_drive_map[y * COLS + x] = 1 if ok else 0

## One block split into one, two or four buildings of different heights.
func _make_parts(s: Rect2) -> Array:
	var rects: Array = []
	var gap := 4.0
	match _rng.randi() % 4:
		0:
			rects.append(s)
		1:
			var w := s.size.x * _rng.randf_range(0.35, 0.65)
			rects.append(Rect2(s.position, Vector2(w - gap * 0.5, s.size.y)))
			rects.append(Rect2(s.position + Vector2(w + gap * 0.5, 0), Vector2(s.size.x - w - gap * 0.5, s.size.y)))
		2:
			var h := s.size.y * _rng.randf_range(0.35, 0.65)
			rects.append(Rect2(s.position, Vector2(s.size.x, h - gap * 0.5)))
			rects.append(Rect2(s.position + Vector2(0, h + gap * 0.5), Vector2(s.size.x, s.size.y - h - gap * 0.5)))
		_:
			var w := s.size.x * _rng.randf_range(0.4, 0.6)
			var h := s.size.y * _rng.randf_range(0.4, 0.6)
			var g := gap * 0.5
			rects.append(Rect2(s.position, Vector2(w - g, h - g)))
			rects.append(Rect2(s.position + Vector2(w + g, 0), Vector2(s.size.x - w - g, h - g)))
			rects.append(Rect2(s.position + Vector2(0, h + g), Vector2(w - g, s.size.y - h - g)))
			rects.append(Rect2(s.position + Vector2(w + g, h + g), Vector2(s.size.x - w - g, s.size.y - h - g)))
	var out: Array = []
	for r in rects:
		var ac: Array = []
		for k in _rng.randi_range(1, 3):
			ac.append({"p": Vector2(_rng.randf_range(0.2, 0.8), _rng.randf_range(0.2, 0.8)),
				"s": _rng.randf_range(4.0, 8.0)})
		out.append({
			"rect": r,
			"h": _rng.randf_range(0.35, 1.0),
			"role": ROOF_ROLES[_rng.randi() % ROOF_ROLES.size()],
			"ac": ac,
			"sign": (_rng.randi() % 4) if _rng.randf() < 0.45 else -1,
		})
	return out

func _block(bx: int, by: int) -> Dictionary:
	if bx < 0 or by < 0 or bx >= BLOCKS_X or by >= BLOCKS_Y:
		return {}
	return _blocks[by * BLOCKS_X + bx]

func _in_grid(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < COLS and t.y < ROWS

func _is_road(t: Vector2i) -> bool:
	return _in_grid(t) and (t.x % PERIOD < 2 or t.y % PERIOD < 2)

func _drivable(t: Vector2i) -> bool:
	return _in_grid(t) and _drive_map[t.y * COLS + t.x] == 1

func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(p.x / TILE), 0, COLS - 1), clampi(floori(p.y / TILE), 0, ROWS - 1))

func _center(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)

## Which way traffic flows on a road tile (right-hand traffic). Junction tiles have two.
func _lane_dirs(t: Vector2i) -> Array:
	var out: Array = []
	if not _is_road(t):
		return out
	match t.y % PERIOD:
		0: out.append(Vector2i(-1, 0))
		1: out.append(Vector2i(1, 0))
	match t.x % PERIOD:
		0: out.append(Vector2i(0, 1))
		1: out.append(Vector2i(0, -1))
	return out

func _on_grass(p: Vector2) -> bool:
	var b := _block(floori((p.x - ROAD) / CELL), floori((p.y - ROAD) / CELL))
	return not b.is_empty() and b["kind"] == "park" and (b["interior"] as Rect2).has_point(p)

func _in_building(p: Vector2, m: float) -> bool:
	for bx in range(floori((p.x - ROAD - m) / CELL), floori((p.x - ROAD + m) / CELL) + 1):
		for by in range(floori((p.y - ROAD - m) / CELL), floori((p.y - ROAD + m) / CELL) + 1):
			var b := _block(bx, by)
			if b.is_empty() or b["kind"] != "building":
				continue
			if (b["solid"] as Rect2).grow(m).has_point(p):
				return true
	return false

func _clear(a: Vector2, b: Vector2, m: float) -> bool:
	var d := b - a
	var steps := int(d.length() / 10.0) + 1
	for i in range(1, steps + 1):
		if _in_building(a + d * (float(i) / float(steps)), m):
			return false
	return true

## ---- the frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished or _player == null:
		return
	var dt := minf(delta, 0.05)
	_t += dt
	Audio.music(MUSIC)

	_update_player(dt)
	_update_cops(dt)
	_update_traffic(dt)
	_update_peds(dt)
	if finished:
		return
	_update_job(dt)
	_update_fx(dt)
	_update_camera(dt)

	_siren_t += dt
	if _siren_t > 0.13:
		_siren_t = 0.0
		for c in _cops:
			c.lights_on = not c.lights_on
			c.queue_redraw()

	_marker.scale = Vector2.ONE * (1.0 + 0.18 * sin(_t * 7.0))
	_skid_node.queue_redraw()
	_fx_node.queue_redraw()
	_roofs.queue_redraw()
	_top.queue_redraw()
	_hud.queue_redraw()

## Shared by the player and the cops: steer towards a world direction (not "left/right"),
## so the arrow keys, a thumb-stick and the bots all mean the same thing. The car turns
## at a limited rate and its sideways speed bleeds off by `grip`, which is the drift.
func _drive(c: Car, want: Vector2, top: float, accel: float, grip: float, corner: float,
		turn_mul: float, dt: float) -> void:
	var mag := minf(1.0, want.length())
	var spd := c.vel.dot(Vector2.from_angle(c.heading))
	if mag > 0.15:
		var diff := wrapf(want.angle() - c.heading, -PI, PI)
		var k := clampf(absf(spd) / maxf(top, 1.0), 0.0, 1.0)
		var rate := lerpf(5.0, 3.1, k) * turn_mul * clampf(0.4 + absf(spd) / 50.0, 0.4, 1.0)
		c.heading += clampf(diff, -rate * dt, rate * dt)
	var fwd := Vector2.from_angle(c.heading)
	var right := fwd.orthogonal()
	spd = c.vel.dot(fwd)
	var lat := c.vel.dot(right)
	if mag > 0.15:
		var off := absf(wrapf(want.angle() - c.heading, -PI, PI))
		if off > 2.0:
			spd = move_toward(spd, 25.0, accel * 1.6 * dt)
		else:
			var goal := top * mag * clampf(1.0 - corner * off, 0.3, 1.0)
			spd = move_toward(spd, goal, (accel if spd < goal else accel * 1.2) * dt)
	else:
		spd = move_toward(spd, 0.0, 170.0 * dt)
	lat *= exp(-grip * dt)
	c.vel = fwd * spd + right * lat
	c.rotation = c.heading + c.spin

func _update_player(dt: float) -> void:
	var p := _player
	var want := PInput.dir()
	if _stick_on and _stick_vec != Vector2.ZERO:
		want = _stick_vec
	var hb := PInput.pressed("action_a")
	var top := PLAYER_TOP * (0.68 if _on_grass(p.position) else 1.0)
	_drive(p, want, top, PLAYER_ACCEL, 2.0 if hb else GRIP, 0.25, 1.45 if hb else 1.0, dt)
	if hb:
		var fwd := Vector2.from_angle(p.heading)
		p.vel -= fwd * minf(p.vel.dot(fwd), 140.0 * dt)
	p.position += p.vel * dt

	var impact := _hit_walls(p, dt)
	for t in _traffic:
		var car: Car = t
		var hit := _bump(p, car, 0.0)
		if hit > 110.0 and car.knocked <= 0.0:
			car.knocked = 1.2
			car.spin = _rng.randf_range(-1.4, 1.4)
			Audio.play("impact_plate", 0.15, -4.0)
		impact = maxf(impact, hit)
	p.crash_cd -= dt
	if impact > 85.0 and p.crash_cd <= 0.0:
		p.crash_cd = 0.25
		Juice.shake(clampf(impact / 35.0, 2.0, 8.0))
		if impact > 200.0:
			Juice.hitstop(0.05)
		Audio.play("impact_metal", 0.15, clampf(-14.0 + impact / 20.0, -14.0, 0.0))
		_sparks(p.position + p.vel.normalized() * -2.0 + Vector2.from_angle(p.heading) * 10.0, 8)
		Probe.count("crash")

	_skid(p, hb)
	_puff_t -= dt
	if want.length() > 0.15 and _puff_t <= 0.0 and p.vel.length() < top * 0.85:
		_puff_t = 0.07
		var back := p.position - Vector2.from_angle(p.heading) * 13.0
		_fx.append({"p": back, "v": -Vector2.from_angle(p.heading) * 30.0, "life": 0.5, "max": 0.5,
			"r": 3.0, "role": "ink", "kind": "smoke"})

	if _invuln > 0.0:
		_invuln -= dt
		p.modulate.a = 0.35 if int(_invuln * 10.0) % 2 == 0 else 1.0
		if _invuln <= 0.0:
			p.modulate.a = 1.0

## Pushes a car out of every building it overlaps and off the city edge; returns how hard
## it hit (speed into the wall). Hitting a face square-on nudges the car along it towards
## the nearer corner, so steering straight into a wall slides round it instead of sticking.
func _hit_walls(c: Car, dt: float) -> float:
	var r := CAR_R
	var p := c.position
	var impact := 0.0
	for bx in range(floori((p.x - ROAD - r) / CELL), floori((p.x - ROAD + r) / CELL) + 1):
		for by in range(floori((p.y - ROAD - r) / CELL), floori((p.y - ROAD + r) / CELL) + 1):
			var b := _block(bx, by)
			if b.is_empty() or b["kind"] != "building":
				continue
			var rect: Rect2 = b["solid"]
			if not rect.grow(r).has_point(p):
				continue
			var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
			var d := p - q
			var dl := d.length()
			var n := Vector2.ZERO
			if dl > 0.001:
				if dl >= r:
					continue
				n = d / dl
				p = q + n * r
			else:
				var gl := p.x - rect.position.x
				var gr := rect.end.x - p.x
				var gt := p.y - rect.position.y
				var gb := rect.end.y - p.y
				var m := minf(minf(gl, gr), minf(gt, gb))
				if m == gl:
					n = Vector2.LEFT
					p.x = rect.position.x - r
				elif m == gr:
					n = Vector2.RIGHT
					p.x = rect.end.x + r
				elif m == gt:
					n = Vector2.UP
					p.y = rect.position.y - r
				else:
					n = Vector2.DOWN
					p.y = rect.end.y + r
			var vn := c.vel.dot(n)
			if vn < 0.0:
				c.vel -= n * vn * 1.3
				c.vel *= 0.94
				impact = maxf(impact, -vn)
				# slide towards the nearer end of the face
				var along := n.orthogonal()
				var mid := rect.get_center()
				var side := signf((p - mid).dot(along))
				if side == 0.0:
					side = 1.0
				c.vel += along * side * 260.0 * dt
	var size := play_area.size
	if p.x < r:
		p.x = r
		impact = maxf(impact, -c.vel.x)
		c.vel.x = absf(c.vel.x) * 0.3
	elif p.x > size.x - r:
		p.x = size.x - r
		impact = maxf(impact, c.vel.x)
		c.vel.x = -absf(c.vel.x) * 0.3
	if p.y < r:
		p.y = r
		impact = maxf(impact, -c.vel.y)
		c.vel.y = absf(c.vel.y) * 0.3
	elif p.y > size.y - r:
		p.y = size.y - r
		impact = maxf(impact, c.vel.y)
		c.vel.y = -absf(c.vel.y) * 0.3
	c.position = p
	return impact

## Two cars overlapping: separate them. `share` is how much of the shove `b` takes
## (0 for traffic, which stays on its lane). Returns the closing speed.
func _bump(a: Car, b: Car, share: float) -> float:
	var d := a.position - b.position
	var dl := d.length()
	var r := CAR_R * 2.0
	if dl >= r or dl < 0.001:
		return 0.0
	var n := d / dl
	var pen := r - dl
	a.position += n * pen * (1.0 - share)
	b.position -= n * pen * share
	var rel := (a.vel - b.vel).dot(n)
	if rel >= 0.0:
		return 0.0
	a.vel -= n * rel * (1.0 - share) * 1.3
	b.vel += n * rel * share * 1.3
	return -rel

func _skid(c: Car, hb: bool) -> void:
	var fwd := Vector2.from_angle(c.heading)
	var right := fwd.orthogonal()
	var lat := absf(c.vel.dot(right))
	var sliding := lat > 60.0 or (hb and c.vel.length() > 70.0)
	if not sliding:
		c.skid_l = Vector2.INF
		return
	var rear := c.position - fwd * 8.0
	var l := rear + right * 5.0
	var r := rear - right * 5.0
	if c.skid_l != Vector2.INF:
		_skids.append([c.skid_l, l, 1.0])
		_skids.append([c.skid_r, r, 1.0])
		if _skids.size() > 600:
			_skids = _skids.slice(_skids.size() - 600)
	c.skid_l = l
	c.skid_r = r
	if _rng.randf() < 0.3:
		_fx.append({"p": rear, "v": Vector2(_rng.randf_range(-15, 15), _rng.randf_range(-15, 15)),
			"life": 0.7, "max": 0.7, "r": 4.0, "role": "ink", "kind": "smoke"})

## ---- the police ----------------------------------------------------------------

func _update_cops(dt: float) -> void:
	_flow_t -= dt
	if _flow_t <= 0.0:
		_flow_t = 0.25
		_rebuild_flow()
	if _t > COP_DELAY and _cops.size() < _stars:
		_spawn_cop()

	var top := minf(COP_TOP + 13.0 * _stars + minf(25.0, _t * 0.15), PLAYER_TOP * 0.94)
	_cop_near = false
	for x in _cops:
		var c: Car = x
		if c.stun > 0.0:
			# just made a bust: back off and give you a head start
			c.stun -= dt
			var away := (c.position - _player.position).normalized()
			_drive(c, away, top * 0.85, 300.0, 11.0, 0.55, 1.0, dt)
		else:
			var goal := _cop_goal(c)
			_drive(c, (goal - c.position).normalized(), top, 300.0, 11.0, 0.55, 1.0, dt)
		c.position += c.vel * dt
		var hit := _hit_walls(c, dt)
		if hit > 160.0 and c.position.distance_to(_player.position) < 400.0:
			_sparks(c.position + Vector2.from_angle(c.heading) * 10.0, 5)
		for t in _traffic:
			_bump(c, t, 0.0)
		_skid(c, false)
		# wedged against something for a while: back off and swing round
		if c.stun <= 0.0 and c.vel.length() < 20.0:
			c.stuck += dt
			if c.stuck > 1.2:
				c.stuck = 0.0
				c.vel = -Vector2.from_angle(c.heading) * 110.0
				c.heading += _rng.randf_range(-1.2, 1.2)
		else:
			c.stuck = 0.0
		if c.position.distance_to(_player.position) < 260.0:
			_cop_near = true

	for i in _cops.size():
		for j in range(i + 1, _cops.size()):
			_bump(_cops[i], _cops[j], 0.5)
	# a cop on you fills the bust meter; get away before it is full
	var touching := false
	for x in _cops:
		var c: Car = x
		if c.stun <= 0.0 and c.position.distance_to(_player.position) < CAR_R * 2.0 + 5.0:
			touching = true
		_bump(_player, c, 0.5)
	if touching and _invuln <= 0.0:
		var slow := _player.vel.length() < 50.0
		_bust += dt / BUST_TIME * (2.0 if slow else 1.0)
		if _bust >= 1.0:
			_busted()
	else:
		_bust = maxf(0.0, _bust - dt * 0.8)

## Where a cop drives next: straight at you when it can see you, otherwise a few steps
## down the flow field, as far ahead as it has a clear line to.
func _cop_goal(c: Car) -> Vector2:
	var pp := _player.position
	if c.position.distance_to(pp) < 150.0 and _clear(c.position, pp, 6.0):
		return pp + _player.vel * 0.25
	var cur := _tile_of(c.position)
	var path: Array = []
	for step in 4:
		var best := cur
		var bd := _flow_at(cur)
		if bd < 0:
			bd = 1 << 30
		for o in N8:
			var off: Vector2i = o
			var nt := cur + off
			if not _drivable(nt):
				continue
			if off.x != 0 and off.y != 0 and (not _drivable(Vector2i(cur.x + off.x, cur.y))
					or not _drivable(Vector2i(cur.x, cur.y + off.y))):
				continue
			var d := _flow_at(nt)
			if d >= 0 and d < bd:
				bd = d
				best = nt
		if best == cur:
			break
		cur = best
		path.append(cur)
	if path.is_empty():
		return pp
	for i in range(path.size() - 1, -1, -1):
		var p := _center(path[i])
		if i == 0 or _clear(c.position, p, 5.0):
			return p
	return pp

func _flow_at(t: Vector2i) -> int:
	if not _in_grid(t):
		return -1
	return _flow[t.y * COLS + t.x]

func _rebuild_flow() -> void:
	var n := COLS * ROWS
	if _flow.size() != n:
		_flow.resize(n)
	_flow.fill(-1)
	var src := _tile_of(_player.position)
	_flow[src.y * COLS + src.x] = 0
	var q: Array[Vector2i] = [src]
	var head := 0
	while head < q.size():
		var cur: Vector2i = q[head]
		head += 1
		var d := _flow[cur.y * COLS + cur.x]
		for o in N8:
			var off: Vector2i = o
			var nt := cur + off
			if not _drivable(nt):
				continue
			if off.x != 0 and off.y != 0 and (not _drivable(Vector2i(cur.x + off.x, cur.y))
					or not _drivable(Vector2i(cur.x, cur.y + off.y))):
				continue
			var i := nt.y * COLS + nt.x
			if _flow[i] != -1:
				continue
			_flow[i] = d + 1
			q.append(nt)

func _spawn_cop() -> void:
	var view := _view_rect().grow(60.0)
	for attempt in 200:
		var t := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		if not _is_road(t):
			continue
		var p := _center(t)
		if view.has_point(p) or p.distance_to(_player.position) < 380.0:
			continue
		var c := _make_car("hazard")
		c.siren = true
		c.position = p
		c.heading = (_player.position - p).angle()
		c.rotation = c.heading
		_cops.append(c)
		Probe.track(c, "x")
		Probe.event("cop_spawn", {"cops": _cops.size()})
		Audio.play("impact_bell", 0.05, -10.0)
		return

func _set_stars(n: int) -> void:
	var was := _stars
	_stars = clampi(n, 1, MAX_STARS)
	if _stars > was:
		Probe.event("wanted_up", {"stars": _stars})
	# fewer stars than cops: the one furthest away gives up
	while _cops.size() > _stars:
		var far: Car = _cops[0]
		for x in _cops:
			var c: Car = x
			if c.position.distance_to(_player.position) > far.position.distance_to(_player.position):
				far = c
		_cops.erase(far)
		far.queue_free()

func _busted() -> void:
	Probe.event("busted", {"stars": _stars, "lives": lives - 1})
	Probe.capture("busted")
	_show_banner("BUSTED", "hazard")
	Audio.play("impact_punch")
	lose_life()
	if finished:
		return
	_invuln = INVULN
	_bust = 0.0
	for x in _cops:
		var c: Car = x
		c.stun = RETREAT
	_player.vel *= 0.2
	_set_stars(_stars - 1)

## ---- traffic and people ----------------------------------------------------------

func _spawn_traffic() -> void:
	for attempt in 80:
		var t := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		var dirs := _lane_dirs(t)
		if dirs.size() != 1:
			continue
		var p := _center(t)
		if _player != null and p.distance_to(_player.position) < 200.0:
			continue
		var crowded := false
		for x in _traffic:
			if (x as Car).position.distance_to(p) < 48.0:
				crowded = true
				break
		if crowded:
			continue
		var c := _make_car(CAR_ROLES[_rng.randi() % CAR_ROLES.size()])
		c.glow = false
		c.dir = dirs[0]
		c.to = t + c.dir
		c.from = p
		c.position = p
		c.heading = Vector2(c.dir).angle()
		c.rotation = c.heading
		c.speed = _rng.randf_range(55.0, 85.0)
		_traffic.append(c)
		Probe.track(c, "o")
		return

func _next_dir(t: Vector2i, cur: Vector2i) -> Vector2i:
	var opts: Array = []
	for d in _lane_dirs(t):
		var dv: Vector2i = d
		if dv == -cur:
			continue
		if _is_road(t + dv):
			opts.append(dv)
	if opts.is_empty():
		return -cur
	if opts.has(cur) and _rng.randf() < 0.55:
		return cur
	return opts[_rng.randi() % opts.size()]

func _ahead_blocked(c: Car) -> bool:
	var f := Vector2(c.dir)
	var side := f.orthogonal()
	var others: Array = [_player]
	others.append_array(_cops)
	others.append_array(_traffic)
	for x in others:
		var o: Car = x
		if o == c:
			continue
		var d := o.position - c.position
		var ahead := d.dot(f)
		if ahead > 2.0 and ahead < 30.0 and absf(d.dot(side)) < 11.0:
			return true
	return false

func _update_traffic(dt: float) -> void:
	for x in _traffic:
		var c: Car = x
		var moving := false
		if c.knocked > 0.0:
			c.knocked -= dt
		else:
			var blocked := _ahead_blocked(c)
			c.wait = c.wait + dt if blocked else 0.0
			if not blocked or c.wait > 2.2:
				moving = true
				c.prog += c.speed * dt / TILE
				while c.prog >= 1.0:
					c.prog -= 1.0
					c.from = _center(c.to)
					c.dir = _next_dir(c.to, c.dir)
					c.to = c.to + c.dir
		c.position = c.from.lerp(_center(c.to), c.prog)
		c.heading = lerp_angle(c.heading, Vector2(c.dir).angle(), 1.0 - exp(-10.0 * dt))
		c.spin *= exp(-2.0 * dt)
		c.rotation = c.heading + c.spin
		c.vel = Vector2(c.dir) * c.speed if moving else Vector2.ZERO

func _spawn_ped() -> void:
	var b: Dictionary = _blocks[_rng.randi() % _blocks.size()]
	var path: Rect2 = (b["interior"] as Rect2).grow(-3.5)
	var n := Blob.new()
	n.role = PED_ROLES[_rng.randi() % PED_ROLES.size()]
	n.radius = 2.6
	n.glow = false
	n.z_index = 1
	add_child(n)
	var per := 2.0 * (path.size.x + path.size.y)
	_peds.append({
		"node": n, "path": path, "t": _rng.randf() * per,
		"spd": _rng.randf_range(10.0, 20.0) * (1.0 if _rng.randf() < 0.5 else -1.0),
		"off": Vector2.ZERO, "offv": Vector2.ZERO, "scare": 0.0,
	})

func _perim(r: Rect2, t: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	t = fposmod(t, 2.0 * (w + h))
	if t < w:
		return r.position + Vector2(t, 0)
	t -= w
	if t < h:
		return r.position + Vector2(w, t)
	t -= h
	if t < w:
		return r.position + Vector2(w - t, h)
	t -= w
	return r.position + Vector2(0, h - t)

func _update_peds(dt: float) -> void:
	var cars: Array = [_player]
	cars.append_array(_cops)
	for ped in _peds:
		var n: Blob = ped["node"]
		ped["t"] = float(ped["t"]) + float(ped["spd"]) * dt
		var offv: Vector2 = ped["offv"]
		var off: Vector2 = ped["off"]
		off += offv * dt
		offv *= exp(-7.0 * dt)
		off *= exp(-0.9 * dt)
		ped["scare"] = float(ped["scare"]) - dt
		var pos := _perim(ped["path"], ped["t"]) + off
		if float(ped["scare"]) <= 0.0:
			for x in cars:
				var c: Car = x
				var d := pos - c.position
				if d.length() < 28.0 and c.vel.length() > 60.0:
					var away := d.normalized() if d.length() > 0.1 else Vector2.UP
					offv = away * 170.0
					ped["scare"] = 0.9
					if _rng.randf() < 0.3:
						Juice.text(self, pos + Vector2(-4, -20), "!", Palette.col("ink"))
					break
		ped["off"] = off
		ped["offv"] = offv
		n.position = pos

## ---- the job -------------------------------------------------------------------

func _random_curb(near: float, far: float) -> Vector2:
	for attempt in 300:
		var t := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
		if _lane_dirs(t).size() != 1:
			continue
		var p := _center(t)
		var d := p.distance_to(_player.position)
		if d >= near and d <= far:
			return p
	return _center(Vector2i(1, 3))

func _new_phone() -> void:
	_job = "phone"
	_marker.position = _random_curb(260.0, 700.0)
	_marker.role = "prize"
	_marker.queue_redraw()
	_job_label.text = "answer the ringing phone"
	Probe.event("phone_ringing")

func _new_drop() -> void:
	_job = "drop"
	_marker.position = _random_curb(450.0, 5000.0)
	_marker.role = "warn"
	_marker.queue_redraw()
	_job_t = 10.0 + _marker.position.distance_to(_player.position) / 55.0

func _update_job(dt: float) -> void:
	if _job == "drop":
		_job_t -= dt
		if _job_t <= 0.0:
			_show_banner("too slow", "hazard")
			Audio.play("voice_mission_failed")
			Probe.event("job_failed")
			_new_phone()
			return
		_job_label.text = "deliver the hot case   %d" % ceili(_job_t)
	if _player.position.distance_to(_marker.position) > 24.0:
		return
	var at := _marker.position
	Juice.pop(_marker, 1.8)
	if _job == "phone":
		add_score(50)
		Juice.text(self, at + Vector2(-16, -26), "+$50", Palette.col("prize"))
		Audio.play("pickup")
		Probe.event("job_taken")
		_new_drop()
		_show_banner("deliver it", "warn")
	else:
		var pay := 200 + ceili(_job_t) * 10
		add_score(pay)
		_deliveries += 1
		Juice.text(self, at + Vector2(-20, -26), "+$%d" % pay, Palette.col("prize"))
		Juice.shake(4.0)
		Audio.play("coin")
		Audio.play("voice_mission_completed")
		Probe.event("delivered", {"pay": pay, "deliveries": _deliveries})
		_set_stars(_stars + 1)
		_show_banner("paid $%d" % pay, "prize")
		_burst(at, "prize", 18)
		_new_phone()

## ---- effects and camera ---------------------------------------------------------

func _sparks(at: Vector2, n: int) -> void:
	for i in n:
		_fx.append({"p": at, "v": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(80, 220),
			"life": 0.3, "max": 0.3, "r": 1.5, "role": "warn", "kind": "spark"})

func _burst(at: Vector2, role: String, n: int) -> void:
	for i in n:
		_fx.append({"p": at, "v": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(40, 160),
			"life": 0.7, "max": 0.7, "r": 2.5, "role": role, "kind": "spark"})

func _update_fx(dt: float) -> void:
	var keep: Array = []
	for f in _fx:
		f["life"] = float(f["life"]) - dt
		if float(f["life"]) <= 0.0:
			continue
		f["p"] = (f["p"] as Vector2) + (f["v"] as Vector2) * dt
		f["v"] = (f["v"] as Vector2) * exp(-3.0 * dt)
		keep.append(f)
	if keep.size() > 300:
		keep = keep.slice(keep.size() - 300)
	_fx = keep
	var live: Array = []
	for s in _skids:
		s[2] = float(s[2]) - dt / 9.0
		if float(s[2]) > 0.0:
			live.append(s)
	_skids = live

func _update_camera(dt: float) -> void:
	var spd := _player.vel.length()
	var aim := _player.position + _player.vel * 0.4
	_cam.position = _cam.position.lerp(aim, 1.0 - exp(-5.0 * dt))
	var z := lerpf(1.05, 0.82, clampf(spd / PLAYER_TOP, 0.0, 1.0))
	var zz := lerpf(_cam.zoom.x, z, 1.0 - exp(-1.2 * dt))
	_cam.zoom = Vector2(zz, zz)

func _view_rect() -> Rect2:
	if _cam == null:
		return Rect2(_player.position - Vector2(320, 180), Vector2(640, 360))
	var size := Vector2(640, 360) / _cam.zoom
	return Rect2(_cam.get_screen_center_position() - size * 0.5, size)

## ---- touch: a floating thumb-stick wherever the thumb lands ------------------------
## The car is never under the finger: put a thumb down anywhere and drag the way you
## want to go. The base follows the thumb if it wanders too far.

func _input(event: InputEvent) -> void:
	if finished:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			if Flow.pointer_over_hud():
				return
			_stick_on = true
			_stick_origin = get_viewport().get_mouse_position()
			_stick_vec = Vector2.ZERO
		else:
			_stick_on = false
			_stick_vec = Vector2.ZERO
	elif event is InputEventMouseMotion and _stick_on:
		var at := get_viewport().get_mouse_position()
		var d := at - _stick_origin
		if d.length() > 56.0:
			_stick_origin = at - d.normalized() * 56.0
			d = at - _stick_origin
		_stick_vec = Vector2.ZERO if d.length() < 8.0 else d.normalized() * minf(1.0, d.length() / 40.0)

## ---- HUD -----------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5   # under the shell's own HUD and pause screen
	add_child(layer)
	_hud = Node2D.new()
	_hud.draw.connect(_draw_hud)
	layer.add_child(_hud)
	_job_label = UIKit.label("", 12, "ink")
	_job_label.position = Vector2(170, 30)
	_job_label.size = Vector2(300, 18)
	layer.add_child(_job_label)
	_banner = UIKit.label("", 40, "hazard")
	_banner.position = Vector2(70, 130)
	_banner.size = Vector2(500, 60)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.modulate.a = 0.0
	layer.add_child(_banner)

func _show_banner(msg: String, role: String) -> void:
	if _banner_tw != null and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner.text = msg
	_banner.add_theme_color_override("font_color", Palette.col(role))
	_banner.modulate.a = 1.0
	_banner.scale = Vector2.ONE * 1.5
	_banner_tw = _banner.create_tween()
	_banner_tw.tween_property(_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tw.tween_interval(0.8)
	_banner_tw.tween_property(_banner, "modulate:a", 0.0, 0.4)

func _draw_hud() -> void:
	var flash := _cop_near and int(_t * 8.0) % 2 == 0
	for i in MAX_STARS:
		var p := Vector2(320.0 + (i - 2) * 22.0, 18.0)
		var c := Palette.col("warn")
		if i < _stars:
			if _cop_near:
				c = Palette.col("hazard") if flash else Palette.col("player")
			_hud.draw_circle(p, 12.0, Color(c.r, c.g, c.b, 0.12))
			_hud.draw_colored_polygon(_star_pts(p, 8.5), c)
		else:
			var pts := _star_pts(p, 8.5)
			pts.append(pts[0])
			_hud.draw_polyline(pts, Color(c.r, c.g, c.b, 0.25), 1.2)
	if _stick_on:
		var ink := Palette.col("ink")
		var pl := Palette.col("player")
		_hud.draw_arc(_stick_origin, 40.0, 0.0, TAU, 40, Color(ink.r, ink.g, ink.b, 0.25), 2.0)
		_hud.draw_circle(_stick_origin + _stick_vec * 40.0, 14.0, Color(pl.r, pl.g, pl.b, 0.35))

func _star_pts(p: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	return pts

## ---- drawing the city ----------------------------------------------------------

func _draw_ground() -> void:
	var g := _ground
	var bg := Palette.col("bg")
	var alt := Palette.col("bg_alt")
	var ink := Palette.col("ink")
	var warn := Palette.col("warn")
	var road := bg.lerp(alt, 0.6)
	var walk := alt.lerp(ink, 0.10)
	g.draw_rect(play_area, road)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 77
	for i in 160:   # asphalt patches
		var p := Vector2(r2.randf() * play_area.size.x, r2.randf() * play_area.size.y)
		var c := road.darkened(0.12) if i % 2 == 0 else road.lightened(0.03)
		g.draw_rect(Rect2(p, Vector2(r2.randf_range(6, 22), r2.randf_range(4, 14))), c)

	var stripe := Color(ink.r, ink.g, ink.b, 0.16)
	var dash := Color(warn.r, warn.g, warn.b, 0.5)
	for j in BLOCKS_Y + 1:
		var y := j * CELL + ROAD * 0.5
		for i in BLOCKS_X:
			_dashes(Vector2(i * CELL + ROAD + 16, y), Vector2((i + 1) * CELL - 16, y), dash)
	for i in BLOCKS_X + 1:
		var x := i * CELL + ROAD * 0.5
		for j in BLOCKS_Y:
			_dashes(Vector2(x, j * CELL + ROAD + 16), Vector2(x, (j + 1) * CELL - 16), dash)
	for i in BLOCKS_X + 1:
		for j in BLOCKS_Y + 1:
			var ix := Rect2(i * CELL, j * CELL, ROAD, ROAD)
			for s in 7:
				var o := 5.0 + s * 8.0
				if i < BLOCKS_X:
					g.draw_rect(Rect2(ix.end.x + 3, ix.position.y + o, 9, 4), stripe)
				if i > 0:
					g.draw_rect(Rect2(ix.position.x - 12, ix.position.y + o, 9, 4), stripe)
				if j < BLOCKS_Y:
					g.draw_rect(Rect2(ix.position.x + o, ix.end.y + 3, 4, 9), stripe)
				if j > 0:
					g.draw_rect(Rect2(ix.position.x + o, ix.position.y - 12, 4, 9), stripe)

	var friend := Palette.col("friend")
	for b in _blocks:
		var r: Rect2 = b["interior"]
		g.draw_rect(r, walk)
		g.draw_rect(r, walk.lightened(0.18), false, 1.0)
		if b["kind"] == "park":
			var grass := alt.lerp(friend, 0.16)
			g.draw_rect(r.grow(-5), grass)
			var mid := r.get_center()
			g.draw_line(Vector2(r.position.x + 5, mid.y), Vector2(r.end.x - 5, mid.y), walk, 6.0)
			g.draw_line(Vector2(mid.x, r.position.y + 5), Vector2(mid.x, r.end.y - 5), walk, 6.0)
			g.draw_circle(mid, 15.0, walk)
			g.draw_circle(mid, 10.0, Palette.col("player").darkened(0.55))
			g.draw_circle(mid, 4.0, Palette.col("player").darkened(0.2))
		else:
			g.draw_rect(b["solid"], bg.darkened(0.3))
		# street lamps on two corners of every block
		for cp in [r.position, r.end]:
			var lp: Vector2 = cp + (r.get_center() - cp).normalized() * 4.0
			for k in 4:
				g.draw_circle(lp, 30.0 - k * 7.0, Color(warn.r, warn.g, warn.b, 0.022))
			g.draw_circle(lp, 2.0, warn.lightened(0.4))

func _dashes(a: Vector2, b: Vector2, c: Color) -> void:
	var d := b - a
	var l := d.length()
	var u := d / l
	var s := 0.0
	while s < l:
		_ground.draw_line(a + u * s, a + u * minf(s + 10.0, l), c, 2.0)
		s += 18.0

func _draw_skids() -> void:
	var bg := Palette.col("bg").darkened(0.5)
	for s in _skids:
		_skid_node.draw_line(s[0], s[1], Color(bg.r, bg.g, bg.b, 0.55 * float(s[2])), 2.5)

func _draw_fx() -> void:
	for f in _fx:
		var k := float(f["life"]) / float(f["max"])
		var c := Palette.col(f["role"])
		var p: Vector2 = f["p"]
		if f["kind"] == "spark":
			_fx_node.draw_line(p, p - (f["v"] as Vector2) * 0.03, Color(c.r, c.g, c.b, k), f["r"])
		else:
			_fx_node.draw_circle(p, float(f["r"]) * (2.0 - k), Color(c.r, c.g, c.b, 0.14 * k))

## Roofs are drawn shifted away from the screen centre, more for taller buildings, and
## joined to their footprint by four wall quads; that is the whole 3D trick.
func _draw_roofs() -> void:
	var cc := _cam.get_screen_center_position()
	var view := _view_rect().grow(80.0)
	var friend := Palette.col("friend")
	for b in _blocks:
		var ir: Rect2 = b["interior"]
		if not view.intersects(ir):
			continue
		if b["kind"] == "park":
			for tr in b["trees"]:
				var tp: Vector2 = tr["p"]
				var rr: float = tr["r"]
				var lift := tp + (tp - cc) * 0.3 * PARALLAX
				_roofs.draw_circle(tp + Vector2(2, 3), rr, Color(0, 0, 0, 0.3))
				_roofs.draw_circle(lift, rr, friend.darkened(0.6))
				_roofs.draw_circle(lift - Vector2(rr, rr) * 0.2, rr * 0.6, friend.darkened(0.4))
			continue
		var idx := 0
		for part in b["parts"]:
			_draw_building(part, cc, idx)
			idx += 1

func _draw_building(part: Dictionary, cc: Vector2, idx: int) -> void:
	var base: Rect2 = part["rect"]
	var h: float = part["h"]
	var pc := base.get_center()
	var off := (pc - cc) * h * PARALLAX
	var s := 1.0 + h * 0.06
	var roof_r := Rect2(pc + off - base.size * s * 0.5, base.size * s)
	var bq := [base.position, Vector2(base.end.x, base.position.y), base.end, Vector2(base.position.x, base.end.y)]
	var rq := [roof_r.position, Vector2(roof_r.end.x, roof_r.position.y), roof_r.end, Vector2(roof_r.position.x, roof_r.end.y)]
	var normals := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var shade := [0.05, 0.3, 0.5, 0.18]
	var rc := Palette.col(part["role"])
	var alt := Palette.col("bg_alt")
	var warn := Palette.col("warn")
	var roof := alt.lerp(rc, 0.16 + 0.12 * h)
	var wall := roof.darkened(0.25)
	for i in 4:
		var j := (i + 1) % 4
		_roofs.draw_colored_polygon(PackedVector2Array([bq[i], bq[j], rq[j], rq[i]]), wall.darkened(shade[i]))
		# lit windows on the walls that face the camera
		var depth := -off.dot(normals[i])
		if depth > 5.0:
			var a: Vector2 = bq[i]
			var bb: Vector2 = bq[j]
			var length := a.distance_to(bb)
			var n := int(length / 9.0)
			var rows := [0.5] if depth < 12.0 else [0.33, 0.66]
			for k in n:
				var t := (k + 0.5) / float(n)
				var lo: Vector2 = a.lerp(bb, t)
				var hi: Vector2 = (rq[i] as Vector2).lerp(rq[j], t)
				for f in rows:
					if (k * 7 + i * 13 + idx * 5 + int(base.position.x) + int(f * 10.0)) % 5 < 2:
						_roofs.draw_rect(Rect2(lo.lerp(hi, f) - Vector2(1.2, 1.2), Vector2(2.4, 2.4)),
							Color(warn.r, warn.g, warn.b, 0.75))
	_roofs.draw_rect(roof_r, roof)
	_roofs.draw_rect(roof_r.grow(-2.5), roof.lightened(0.12), false, 1.5)
	_roofs.draw_rect(roof_r, Color(rc.r, rc.g, rc.b, 0.55), false, 1.0)
	for a in part["ac"]:
		var sz: float = float(a["s"]) * s
		var p: Vector2 = roof_r.position + (a["p"] as Vector2) * roof_r.size
		_roofs.draw_rect(Rect2(p + Vector2(1.5, 1.5) - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(0, 0, 0, 0.3))
		_roofs.draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), roof.lightened(0.22))
	var side: int = part["sign"]
	if side >= 0:
		var sr: Rect2
		var w := roof_r.size
		match side:
			0: sr = Rect2(roof_r.position + Vector2(w.x * 0.2, 4), Vector2(w.x * 0.6, 3))
			1: sr = Rect2(roof_r.position + Vector2(w.x - 7, w.y * 0.2), Vector2(3, w.y * 0.6))
			2: sr = Rect2(roof_r.position + Vector2(w.x * 0.2, w.y - 7), Vector2(w.x * 0.6, 3))
			_: sr = Rect2(roof_r.position + Vector2(4, w.y * 0.2), Vector2(3, w.y * 0.6))
		var flick := 1.0
		if idx % 3 == 1 and sin(_t * 13.0 + pc.x) > 0.85:
			flick = 0.35
		_roofs.draw_rect(sr.grow(5.0), Color(rc.r, rc.g, rc.b, 0.10 * flick))
		_roofs.draw_rect(sr.grow(2.0), Color(rc.r, rc.g, rc.b, 0.28 * flick))
		_roofs.draw_rect(sr, rc.lightened(0.35 * flick))

## The arrow round your car pointing at the job, the ring on the job itself, and the
## bust meter closing round your car while a cop is on you.
func _draw_top() -> void:
	if _bust > 0.02:
		var hz := Palette.col("hazard")
		var pp := _player.position
		_top.draw_circle(pp, 24.0, Color(hz.r, hz.g, hz.b, 0.10 + 0.15 * _bust))
		_top.draw_arc(pp, 22.0, -PI * 0.5, -PI * 0.5 + TAU * _bust, 40, hz, 3.0)
	var c := Palette.col(_marker.role)
	var mp := _marker.position
	var pulse := 20.0 + 4.0 * sin(_t * 6.0)
	_top.draw_circle(mp, pulse + 10.0, Color(c.r, c.g, c.b, 0.08))
	_top.draw_arc(mp, pulse, 0.0, TAU, 32, Color(c.r, c.g, c.b, 0.7), 2.0)
	var to := mp - _player.position
	if to.length() < 70.0:
		return
	var dn := to.normalized()
	var sd := dn.orthogonal()
	var base := _player.position + dn * (32.0 + 3.0 * sin(_t * 8.0))
	var pts := PackedVector2Array([base + dn * 10.0, base - dn * 4.0 + sd * 8.0, base - dn * 1.0, base - dn * 4.0 - sd * 8.0])
	var glow := PackedVector2Array()
	for p in pts:
		glow.append(base + (p - base) * 1.6)
	_top.draw_colored_polygon(glow, Color(c.r, c.g, c.b, 0.2))
	_top.draw_colored_polygon(pts, c)
