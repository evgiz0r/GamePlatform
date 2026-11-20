extends RefCounted
## Other cars: a couple of dozen driving the real streets round the player, in their lane,
## keeping their distance, slowing for corners and stopping at red lights.
##
## Each car follows a path of lane points planned on the road graph the way autodrive plans
## the player's: a road to its end, then a pick of the ways on (mostly straight on, main
## roads rather than side streets, never against a one-way). They are not physics: they
## move along the path at their own speed, and the player's car bumps into them as it
## would a parked one. All of them are one multimesh, drawn between physics ticks like the
## player's car, so a few dozen cost about what one does.

const COUNT := 22
const NEAR := 240.0          ## further than this from the player a car is taken away...
const SPAWN_MIN := 120.0     ## ...and put back on a street this far off,
const SPAWN_MAX := 215.0     ##    out of sight when it can be
const ACCEL := 2.0           ## m/s^2
const BRAKE := 3.0           ## what a driver plans to brake at
const BRAKE_HARD := 7.5      ## what it will do when it has to
const GAP := 2.2             ## bumper to bumper when stopped (m)
const HEADWAY := 1.2         ## seconds behind the car in front, moving
const LEN := 4.4
## how long each kind is, bumper to bumper (m)
const LENS := {"sedan": 4.6, "hatch": 4.0, "suv": 4.7, "van": 5.0, "taxi": 4.6, "bus": 11.8, "moto": 1.9, "truck": 6.8}
## the player's car against each kind: circles along its length [offsets], radius
const BODY := {"bus": [[-4.6, -2.3, 0.0, 2.3, 4.6], 1.25], "moto": [[0.0], 0.55], "truck": [[-2.3, 0.0, 2.3], 1.15]}
const BUS_ROADS := {"primary": true, "secondary": true, "tertiary": true, "trunk": true}
const LANE_MOVE := 1.4       ## sideways speed changing lanes (m/s): about 2.5 s a lane
const DWELL := 7.0           ## seconds a bus stands at a stop
const LANE_W := 1.5          ## a car on my path: its middle within this of my lane line
const PLAYER_W := 2.0        ## the player's car counts as in my way from further over: it
                             ## need not be on a lane line, and half in the lane is in it
const CURVE_LAT := 2.6       ## sideways pull a driver takes a corner at (m/s^2)
const LIGHT_SKIP := 45.0     ## lights this close after one already passed are the far side of the same junction
## how much traffic each kind of road gets, and how keen a driver is to turn into it
const KIND_W := {"motorway": 1.0, "trunk": 1.0, "primary": 1.0, "secondary": 1.0, "tertiary": 0.85,
	"motorway_link": 0.6, "trunk_link": 0.6, "primary_link": 0.6, "secondary_link": 0.6,
	"tertiary_link": 0.5, "unclassified": 0.45, "residential": 0.3, "living_street": 0.08}

class Car:
	var pts := PackedVector2Array()   ## the lane ahead (and a little behind)
	var cum := PackedFloat32Array()   ## distance along it to each point
	var node := PackedInt32Array()    ## the graph node at each point
	var rd := PackedInt32Array()      ## the road each point is on (at a junction: the one coming in)
	var jwait := 0.0                  ## seconds waiting at a junction's edge
	var vmax := PackedFloat32Array()  ## the speed allowed at each point (limit, corners)
	var end := Vector3i(-1, 0, 0)     ## the last leg planned: road, last index, direction
	var k := 0                        ## the segment it is on
	var s := 0.0                      ## how far along pts
	var v := 0.0
	var pos := Vector2.ZERO
	var yaw := 0.0                    ## atan2(dir.x, dir.y): the multimesh's way of turning
	var pitch := 0.0
	var prev_pos := Vector2.ZERO
	var prev_yaw := 0.0
	var pace := 1.0                   ## this driver's share of the limit
	## the driver: how hard they pull away, the gap they leave standing and the seconds
	## behind they keep moving, how long they take to notice the way ahead clear (a light
	## gone green, the car in front moving off), and their drift in the lane. All the same,
	## every car pulled away together on the same tick at the same rate, like a train.
	var accel := 2.0
	var gap := 2.2
	var headway := 1.2
	var react := 0.6
	var react_t := 0.0
	var acc := 0.0                    ## its acceleration now (smoothed: no instant pull-away)
	var lead_v := 0.0                 ## the speed of the car in front, along my way
	var still := 0.0                  ## seconds standing
	var drift := 0.0                  ## phase of its wander in the lane
	var dip := 0.0                    ## the body: nose down braking, up pulling away (visual)
	var roll := 0.0                   ## the body: leaning out of a turn (visual)
	var paint := Color.WHITE
	var kind := "sedan"
	var braking := 0.0                ## brake lights, 0..1
	var wait := 0.0                   ## seconds held up by another car
	var blocker := -2                 ## who holds it up: a car's index, -1 the player
	var why := ""                     ## what holds its speed down (limit, curve, light, car...)
	var ignore := 0.0                 ## seconds it ignores crossing cars (a standoff broken)
	var squeeze := 0.0                ## seconds it edges past the player (a narrow street's standoff)
	var hit := 0.0                    ## seconds it sits stunned after the player hit it
	var retry := 0.0                  ## seconds before trying again to find it a road
	var want := -1.0                  ## the speed it last decided on (-1: decide now)
	var passenger := false            ## someone beside the driver (seen through the glass)
	var last_light := -1000.0         ## s at the last light it drove through
	var sign_done := -1               ## the stop sign it has stopped at already
	var sign_wait := 0.0
	var holding := false              ## stopping for a stop sign: not taking the junction yet
	var alive := false
	var len := 4.6
	## lanes: the path is the lane line a single-lane road would have; on a road with more
	## lanes each way a car sits `shift` metres to the left of it (right: negative), in lane
	## `lane_i` counted from the right
	var lane_i := 0
	var shift := 0.0
	var shift_to := 0.0
	var shift_rate := 0.0
	var lane_t := 0.0                 ## seconds before it will think of changing lanes again
	var split := false                ## a scooter filtering between the lanes past a queue
	var free_t := 0.0
	var dwell := 0.0                  ## a bus: seconds stood at the stop
	var served := {}                  ## a bus: the stops it has stopped at
	var blink := 0                    ## indicating: -1 left, 1 right
	var ring_n := 0                   ## pieces of roundabout driven since it came onto one
	var pull_out := 0.0               ## a bus leaving a stop: seconds it signals out

var g: Node                           ## the game: its road graph, lights, ground, player
var cars: Array = []
var rng := RandomNumberGenerator.new()
var hit_index := -1                   ## the car the player last bumped
var _clock := 0.0
var _degree := {}                     ## node -> how many ways out of it (3+: a junction)
const TAKE_AHEAD := 22.0              ## who goes first at a junction is settled this far before it
var _mm: MultiMesh
var _mms := {}                        ## car shape -> its multimesh
var _beams: MultiMeshInstance3D       ## their beams on the road, at night
var _blinkers: MultiMesh              ## the indicators that are lit, front and back: one draw
## each kind's half width and half length, for where its indicators are
const CORNERS := {"sedan": Vector2(0.9, 2.25), "hatch": Vector2(0.86, 1.95), "suv": Vector2(0.96, 2.32),
	"van": Vector2(0.98, 2.45), "taxi": Vector2(0.9, 2.25), "bus": Vector2(1.25, 5.85), "moto": Vector2(0.3, 0.8),
	"truck": Vector2(1.1, 3.35)}
var _night := false
var _roads: Array
var _node_roads: Array
var _node_r: PackedFloat32Array

func setup(game: Node) -> void:
	g = game
	_roads = g._roads
	_node_roads = g._node_roads
	_node_r = g._node_r
	rng.seed = hash(g._city_name) + 23
	# a multimesh per car shape (one surface each, the car shader: paint and brake in custom
	# data); a car's slot in the others stays hidden
	var b: Rect2 = g._bounds
	var box := AABB(Vector3(b.position.x - 500.0, -200.0, b.position.y - 500.0),
		Vector3(b.size.x + 1000.0, 600.0, b.size.y + 1000.0))   # no box to recompute every frame
	for kind: String in ["sedan", "hatch", "suv", "van", "taxi", "bus", "moto", "truck"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true   # white: the car shader's part colours are vertex colours, see _chunked
		mm.use_custom_data = true
		mm.mesh = g._parked_mesh(kind)
		mm.instance_count = COUNT
		mm.custom_aabb = box
		for i in range(COUNT):
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
			mm.set_instance_color(i, Color.WHITE)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		g.world.add_child(mi)
		_mms[kind] = mm
	_mm = _mms["sedan"]
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.mesh = g._beam_mesh()
	bm.instance_count = COUNT
	bm.custom_aabb = _mm.custom_aabb
	_beams = MultiMeshInstance3D.new()
	_beams.multimesh = bm
	_beams.material_override = g._glow_mat("lamplight", 0.4)
	_beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beams.visible = false
	g.world.add_child(_beams)
	_blinkers = MultiMesh.new()
	_blinkers.transform_format = MultiMesh.TRANSFORM_3D
	var lamp := BoxMesh.new()
	lamp.size = Vector3(0.13, 0.1, 0.1)
	lamp.material = g.mat("warn", 2.6)
	_blinkers.mesh = lamp
	_blinkers.instance_count = COUNT * 2
	_blinkers.custom_aabb = box
	for k in range(COUNT * 2):
		_blinkers.set_instance_transform(k, Transform3D(Basis(), Vector3(0, -500, 0)))
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = _blinkers
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.world.add_child(bmi)
	# a soft patch under each car, for when the real shadows are off (g._set_blobs)
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.mesh = g.blob_mesh()
	sm.instance_count = COUNT
	sm.custom_aabb = box
	for k in range(COUNT):
		sm.set_instance_transform(k, Transform3D(Basis(), Vector3(0, -500, 0)))
	_blobs = MultiMeshInstance3D.new()
	_blobs.multimesh = sm
	_blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blobs.visible = g._blobs_on
	g.world.add_child(_blobs)
	var palette: Array = g._car_paints()
	var med := String(g._place.get("look", "")) == "med"
	# the city's buses: Givatayim's in the blue and the green of its two companies, Bedford's white
	var bus_paints: Array = [Palette.col("player").lerp(Palette.col("bg"), 0.25), Palette.col("friend").lerp(Palette.col("bg"), 0.3)] \
			if med else [Palette.col("ink").lerp(Palette.col("bg_alt"), 0.1)]
	for i in range(COUNT):
		var c := Car.new()
		c.pace = rng.randf_range(0.82, 1.06)
		cars.append(c)
		c.paint = palette[rng.randi() % palette.size()]
		# a couple of buses, a few scooters and taxis, the rest cars
		var roll := rng.randf()
		if i % 9 == 4:
			c.kind = "bus"
			c.paint = bus_paints[i % bus_paints.size()]
			c.pace = rng.randf_range(0.8, 0.9)
		elif roll < 0.15:
			c.kind = "moto"
			c.pace = rng.randf_range(0.95, 1.12)
		elif roll < (0.27 if med else 0.2):
			c.kind = "taxi"
		elif roll < (0.32 if med else 0.25):
			c.kind = "truck"
		else:
			c.kind = g.CAR_MIX[rng.randi() % g.CAR_MIX.size()]
		c.len = float(LENS.get(c.kind, 4.6))
		c.passenger = rng.randf() < 0.35
		_driver(c)
		c.alive = _spawn(c, true)
		_hide_or_show(i)
	retint()

## this car's driver: brisk or easy, close or careful, quick or slow to notice
func _driver(c: Car) -> void:
	var brisk := rng.randf()   # one dial for the driver, a little noise on each
	c.accel = lerpf(1.5, 2.8, brisk) * rng.randf_range(0.9, 1.1)
	c.gap = lerpf(3.0, 1.6, brisk) * rng.randf_range(0.9, 1.1)
	c.headway = lerpf(1.8, 0.9, brisk) * rng.randf_range(0.9, 1.1)
	c.react = lerpf(1.1, 0.35, brisk) * rng.randf_range(0.8, 1.2)
	c.drift = rng.randf() * TAU
	match c.kind:
		"bus", "truck":
			c.accel = rng.randf_range(0.9, 1.3)
			c.gap = maxf(c.gap, 2.6)
		"moto":
			c.accel = rng.randf_range(2.6, 3.6)
			c.react = rng.randf_range(0.3, 0.6)

var _blobs: MultiMeshInstance3D

func show_blobs(on: bool) -> void:
	if _blobs != null:
		_blobs.visible = on

func retint() -> void:
	pass   # the car shader is the game's, retinted with it

func set_night(on: bool) -> void:
	_night = on
	_beams.visible = on
	if not on:
		return
	for i in range(cars.size()):   # nothing drawn yet for cars that are not alive
		_beams.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))

func alive_count() -> int:
	var n := 0
	for c: Car in cars:
		if c.alive:
			n += 1
	return n

## ---- every physics tick ------------------------------------------------------------------

var _tick_n := 0

func tick(dt: float) -> void:
	_clock += dt
	_tick_n += 1
	var me: Vector2 = g._pos
	# One car a tick is put back near the player: driving off leaves several behind at once,
	# and finding each a new road in the same tick (up to 24 tries apiece) was a stutter every
	# few seconds. One that found nowhere this time looks again a moment later.
	var spawned := false
	for i in range(cars.size()):
		var c: Car = cars[i]
		c.prev_pos = c.pos
		c.prev_yaw = c.yaw
		if not c.alive or c.pos.distance_to(me) > NEAR or (c.wait > 25.0 and (not _in_view(c.pos) or c.blocker == -1)):
			c.retry -= dt
			if spawned or c.retry > 0.0:
				continue
			spawned = true
			var t0 := Time.get_ticks_usec()
			c.alive = _spawn(c, false)
			_us("traffic: respawn", t0)
			if not c.alive:
				c.retry = 0.1
			_hide_or_show(i)
			continue
		var t1 := Time.get_ticks_usec()
		while c.cum[c.cum.size() - 1] - c.s < 140.0:
			if not _next(c):
				break
		_trim(c)
		var t2 := Time.get_ticks_usec()
		_us("traffic: route", t1, t2)
		# What the car wants -- the limit, the corners, lights, signs, who goes first at a
		# junction, the car in front -- is decided 20 times a second, a third of the cars each
		# tick (with three ticks' time, so its waits still count right); its speed still
		# follows every tick. A driver reacts slower than that anyway, and deciding it every
		# tick for every car was most of traffic's time.
		# (and one far off, out of sight, every sixth tick: nobody sees it think)
		var every := 3 if c.pos.distance_squared_to(me) < 120.0 * 120.0 or _in_view(c.pos) else 6
		if c.want < 0.0 or (i + _tick_n) % every == 0:
			c.want = _target(c, i, dt * (1.0 if c.want < 0.0 else float(every)))
		var vt := c.want
		_us("traffic: follow", t2)
		var ds := clampf(c.shift_to - c.shift, -LANE_MOVE * dt, LANE_MOVE * dt)
		c.shift += ds
		c.shift_rate = ds / maxf(dt, 0.001)
		_signal(c, dt)
		if c.hit > 0.0:
			c.hit -= dt
			vt = 0.0
		var was := c.v
		if vt > c.v + 0.05:
			# the way ahead clear: from standing, a moment to notice; then pulling away, gently
			# at first (the push builds over half a second or so) and easing off as it nears
			# the speed it wants
			if c.v < 0.3 and c.react_t < c.react:
				# (behind a car, the moment to notice starts when that car is really off, not
				# when it has rolled a few millimetres: else a whole queue went in the same
				# second, like a train)
				if not (c.why == "car" and c.lead_v < 1.0):
					c.react_t += dt
				c.acc = 0.0
			else:
				var want_a := c.accel * clampf(1.0 - pow(c.v / maxf(vt, 1.0), 4.0), 0.2, 1.0)
				c.acc = move_toward(c.acc, want_a, 4.0 * dt)
				c.v = minf(c.v + c.acc * dt, vt)
		else:
			# slowing: as before, down to what it wants at once if it must (its plans brake at
			# BRAKE; this is the margin) -- only the pull-away is softened
			c.v = move_toward(c.v, vt, BRAKE_HARD * dt)
			c.acc = (c.v - was) / maxf(dt, 0.001)
			if vt < 0.3:
				c.react_t = 0.0
		# the body: nose down braking, a little up pulling away; leaning out of a turn
		var turn := angle_difference(c.prev_yaw, c.yaw) / maxf(dt, 0.001)
		c.dip = lerpf(c.dip, clampf(-c.acc * 0.011, -0.03, 0.06), minf(1.0, dt * 6.0))
		c.roll = lerpf(c.roll, clampf(turn * c.v * 0.012, -0.06, 0.06), minf(1.0, dt * 5.0))
		c.braking = clampf(c.braking + (dt * 8.0 if c.v < was - 0.01 or c.v < 0.2 else -dt * 4.0), 0.0, 1.0)
		c.still = c.still + dt if c.v < 0.3 else 0.0
		var before := c.s
		c.s = minf(c.s + c.v * dt, c.cum[c.cum.size() - 1])
		_passed_lights(c, before)
		if c.s >= c.cum[c.cum.size() - 1] - 0.01:
			c.alive = false   # the end of a road with nowhere on: gone, back elsewhere next tick
			continue
		_place(c)

## time spent in one part of the tick, for the game's frame profiler (sub-parts of "traffic":
## a name with a colon is not added to the frame's script total again)
func _us(part: String, t0: int, t1: int = -1) -> void:
	if t1 < 0:
		t1 = Time.get_ticks_usec()
	g._prof[part] = int(g._prof.get(part, 0)) + t1 - t0

## the speed this car wants now: the limit, the corners ahead braked down to in time, a
## red light ahead, the car in front
func _target(c: Car, i: int, dt: float) -> float:
	_seek(c)
	var vt: float = c.vmax[mini(c.k + 1, c.vmax.size() - 1)]
	c.why = "limit"
	for j in range(c.k + 1, c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > 90.0:
			break
		vt = _held(c, vt, sqrt(c.vmax[j] * c.vmax[j] + 2.0 * BRAKE * maxf(dist, 0.0)), "curve")
	var lv := _light_ahead(c)
	vt = _held(c, vt, lv, "light")
	vt = _held(c, vt, _zebra_ahead(c), "zebra")
	if lv == INF:
		vt = _held(c, vt, _sign_ahead(c, dt), "sign")
		if not c.holding:
			vt = _held(c, vt, _junction_ahead(c, i, dt), "junction")
	# the car (or the player) in front, on this lane
	# far enough to stop in, at the speed it is doing (55 m was short of that on a motorway)
	var look := clampf(12.0 + c.v * 1.2 + c.v * c.v / (2.0 * BRAKE), 18.0, 130.0)
	var best := INF
	var best_len := 4.6
	var who := -2
	var lead_v := 0.0
	var fwd := Vector2(sin(c.yaw), cos(c.yaw))
	for j in range(cars.size() + 1):
		var q: Vector2
		var ov: float
		var oyaw: float
		if j == cars.size():
			q = g._pos
			ov = maxf(float(g._v), 0.0)
			oyaw = atan2(cos(float(g._yaw)), sin(float(g._yaw)))   # the player's heading, as this file turns

		else:
			if j == i:
				continue
			var o: Car = cars[j]
			if not o.alive:
				continue
			q = o.pos
			ov = o.v
			oyaw = o.yaw
		var d2 := q.distance_squared_to(c.pos)
		if d2 > (look + 6.0) * (look + 6.0) or (q - c.pos).dot(fwd) < -2.0:
			continue
		if c.ignore > 0.0 and j < cars.size() and absf(angle_difference(oyaw, c.yaw)) > 0.8:
			continue   # breaking a standoff: go, and let the crossing car wait
		if j == cars.size() and c.squeeze > 0.0:
			continue   # edging past them, slowly
		var wide := PLAYER_W if j == cars.size() else LANE_W
		if c.split:
			wide = 0.6   # filtering: only what is right in front of the wheel
		var gap := _path_gap(c, q, look, wide)
		if gap < best:
			best = gap
			who = -1 if j == cars.size() else j
			best_len = 4.6 if j == cars.size() else (cars[j] as Car).len
			# moving with me: its speed along my way, else treat it as standing
			lead_v = ov * maxf(0.0, cos(angle_difference(oyaw, c.yaw)))
	# the player's car, left standing while they walk: in the way like any other
	if g._walking and g._car_at.distance_squared_to(c.pos) < (look + 6.0) * (look + 6.0):
		var pg := _path_gap(c, g._car_at, look, PLAYER_W)
		if pg < best:
			best = pg
			who = -1
			best_len = 4.6
			lead_v = 0.0
	c.ignore = maxf(0.0, c.ignore - dt)
	if c.squeeze > 0.0:
		c.squeeze -= dt
		vt = _held(c, vt, 2.5, "squeezing past")
	c.lead_v = lead_v if best < INF else 99.0
	_steer_lanes(c, i, dt, best, lead_v)
	vt = _held(c, vt, _bus_stop(c, dt), "bus stop")
	if best < INF:
		var room := best - (c.len + best_len) * 0.5 - c.gap - lead_v * c.headway
		var follow := sqrt(maxf(0.0, lead_v * lead_v + 2.0 * BRAKE * maxf(room, 0.0)))
		if room <= 0.0:
			follow = 0.0
		if follow < vt:
			vt = follow
			c.why = "player" if who == -1 else "car"
			if c.v < 0.3:
				c.wait += dt
				c.blocker = who
				# Face to face with the player in a narrow street, both standing (the player
				# waits for it, it waits for the player, for ever -- and autodrive with
				# them): if there is nearly room, it edges by, brushing past; if they are
				# nose to nose, it is gone once out of sight, or after a while regardless
				if who == -1 and c.wait > 3.5 and absf(float(g._v)) < 0.5:
					var pr := _proj(c, g._pos, 4.0, 30.0)
					var lat := absf(pr.y - c.shift) if pr.x != INF else 0.0
					if lat > 1.2:
						c.squeeze = 5.0
						c.wait = 0.0
					elif c.wait > 9.0 or not _in_view(c.pos):
						c.wait = 30.0   # (tick sends it elsewhere)
				# two cars each waiting for the other in a junction: the lower number goes
				if c.wait > 2.5 and who >= 0:
					var o: Car = cars[who]
					if o.blocker == i and o.wait > 2.5 and i < who:
						c.ignore = 3.0
						c.wait = 0.0
			return vt
	c.wait = 0.0
	c.blocker = -2
	return vt

## the lower of two speeds, noting what the lower one is for (the drive recorder logs it)
func _held(c: Car, cur: float, v: float, why: String) -> float:
	if v < cur:
		c.why = why
		return v
	return cur

## the first traffic light ahead that counts: stop at its line on red, and on amber when
## there is room to; through on green
func _light_ahead(c: Car) -> float:
	var counted := c.last_light
	for j in range(c.k + 1, c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > 80.0:
			break
		var n := c.node[j]
		if not g._sig_set.has(n) or c.cum[j] - counted < LIGHT_SKIP:
			continue
		counted = c.cum[j]
		# the way it ARRIVES (a few metres back): the node sits mid-curve on a turn, and the
		# direction there read the cross street's light as often as its own
		var k := j - 1
		while k > 0 and c.cum[j] - c.cum[k] < 6.0:
			k -= 1
		var dir := c.pts[j] - c.pts[maxi(k, 0)]
		var state: String = g._light_at(n, dir)
		# the front at the stop line (1.2 m out from the junction's edge), not the middle: a
		# bus's middle there left its front 4 m into the junction, across the other road
		var stop := dist - (_node_r[n] + 2.2 + c.len * 0.5)
		# its front over the line and rolling, or in the junction: committed, through. Over
		# the line but standing -- stopped there for people on the crossing -- is not: it
		# waited for the people, then drove on through the red.
		if state == "g" or stop < -1.5 and (c.v > 2.0 or dist - c.len * 0.5 < _node_r[n]):
			return INF
		if state == "y" and c.v * c.v > 2.0 * BRAKE * maxf(stop, 0.1):
			return INF   # too late to stop on amber: through
		return sqrt(2.0 * BRAKE * maxf(stop - 0.3, 0.0))
	return INF

## The next junction on my way, and who goes first. A car already in it goes. Then the
## bigger road: a roundabout's ring above all (on it you go, coming in you give way), then
## main roads over side streets. Between equals, whoever gets there first; turning across,
## give way to one going straight. The player always has the right of way. A car kept
## waiting long enough creeps through (the car in front still holds it back), so a jam
## cannot lock for good. (The first version was first come, first served, and a car kept
## the junction while it sat in a queue: whole crossroads and roundabouts locked up.)
func _junction_ahead(c: Car, i: int, dt: float) -> float:
	for j in range(c.k + 1, c.pts.size() - 1):
		var dist := c.cum[j] - c.s
		if dist > TAKE_AHEAD + c.v * 1.5:
			break
		var n := c.node[j]
		if n < 0 or _ways_out(n) < 3:
			continue
		var edge := dist - (_node_r[n] + 1.0 + c.len * 0.5)   # (its front at the junction's edge)
		if edge < -1.0:
			break   # in it already: carry on through
		var mine := _arrival(c, j, n)
		var stop := sqrt(2.0 * BRAKE * maxf(edge - 0.3, 0.0))
		var my_eta := dist / maxf(c.v, 2.0)
		# the player: stopped in it, or coming into it first -- unless right behind me
		var me_at: Vector2 = g._pos
		var node_at := _nodes_at(n)
		var rel := me_at - c.pos
		var fwd := Vector2(sin(c.yaw), cos(c.yaw))
		if not (rel.dot(fwd) < 0.0 and absf(rel.dot(Vector2(-fwd.y, fwd.x))) < 2.5):
			var pd := me_at.distance_to(node_at)
			var pv := maxf(float(g._v), 0.0)
			var pfwd := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
			if pd < _node_r[n] + 3.0:
				return _hold(c, dt, stop)
			if pd < _node_r[n] + 30.0 and pv > 1.5 and pfwd.dot(node_at - me_at) > 0.0 \
					and pd / pv < my_eta + 1.5:
				return _hold(c, dt, stop)
		for oi in range(cars.size()):
			if oi == i:
				continue
			var o: Car = cars[oi]
			if not o.alive or o.pos.distance_squared_to(node_at) > 3600.0:
				continue
			var ok := _node_index(o, n)
			if ok < 0:
				continue
			var od := o.cum[ok] - o.s
			var theirs := _arrival(o, ok, n)
			if not _crosses(mine[0], mine[1], theirs[0], theirs[1], int(mine[3]), int(theirs[3])):
				continue
			if od < _node_r[n] + 1.0:
				return _hold(c, dt, stop)   # in it now
			var o_eta := od / maxf(o.v, 2.0)
			if o_eta > 5.0:
				continue
			if g._sig_set.has(n):
				# lights: they say who goes. One held at its red is not coming (a car with its
				# green gave way to one on the main road that was about to stop at its red, sat
				# out its green and was caught by the next red: a queue on a side street let
				# one car through a green); one with its green too goes first only when I turn
				# across it
				if g._light_at(n, theirs[0]) != "g":
					continue
				var turn_across: bool = (mine[0] as Vector2).dot(mine[1]) < 0.85 and (theirs[0] as Vector2).dot(theirs[1]) >= 0.85
				if turn_across and o_eta < my_eta + 2.0:
					return _hold(c, dt, stop)
				continue
			var mr: int = mine[2]
			var orr: int = theirs[2]
			if orr > mr:
				return _hold(c, dt, stop)
			if orr < mr:
				continue
			var my_turn: bool = (mine[0] as Vector2).dot(mine[1]) < 0.85
			var o_turn: bool = (theirs[0] as Vector2).dot(theirs[1]) < 0.85
			if my_turn and not o_turn and o_eta < my_eta + 2.0:
				return _hold(c, dt, stop)
			if my_turn == o_turn and (o_eta < my_eta - 0.25 or (absf(o_eta - my_eta) <= 0.25 and oi < i)):
				return _hold(c, dt, stop)
		break
	c.jwait = 0.0
	return INF

func _hold(c: Car, dt: float, stop: float) -> float:
	if c.v < 0.5:
		c.jwait += dt
	if c.jwait > 6.0:
		return INF   # waited long enough: in, slowly (whoever is in the way still stops it)
	return stop

## where node n comes on this car's way (just behind counts too: it may be in it), or -1
func _node_index(o: Car, n: int) -> int:
	for k in range(maxi(o.k - 3, 0), mini(o.pts.size(), o.k + 24)):
		if o.node[k] == n:
			var d := o.cum[k] - o.s
			if d > -(_node_r[n] + 5.0) and d < 55.0:
				return k
	return -1

## how a car comes through node n at its point j: [way in, way out, road rank, last node]
func _arrival(c: Car, j: int, n: int) -> Array:
	var m := j - 1
	while m > 0 and c.pts[m].distance_squared_to(c.pts[j]) < 0.25:
		m -= 1
	var way_in := (c.pts[j] - c.pts[maxi(m, 0)]).normalized()
	var way_out := way_in
	for q in range(j + 1, c.pts.size()):
		if c.cum[q] - c.cum[j] > 3.0:
			way_out = (c.pts[q] - c.pts[j]).normalized()
			break
	var from := -1
	for q in range(j - 1, -1, -1):
		if c.node[q] >= 0 and c.node[q] != n:
			from = c.node[q]
			break
	var r: Dictionary = _roads[c.rd[j]]
	var rank := 10 if r.get("ring", false) else int(g.ROAD_RANK.get(r["k"], 1))
	return [way_in, way_out, rank, from]

func _nodes_at(n: int) -> Vector2:
	return g._nodes[n]

func _ways_out(n: int) -> int:
	if _degree.has(n):
		return _degree[n]
	var count := 0
	for e: Vector2i in _node_roads[n]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		var p: PackedVector2Array = r["pts"]
		if e.y > 0:
			count += 1
		if e.y < p.size() - 1:
			count += 1
	_degree[n] = count
	return count

## do two ways through a junction cross? Not when both come along the same road (the one
## behind follows), and not when they come from opposite sides and both go straight on.
## Two roads joining into one (a slip road merging) do: they want the same lane.
func _crosses(in_a: Vector2, out_a: Vector2, in_b: Vector2, out_b: Vector2, from_a := -1, from_b := -2) -> bool:
	if from_a == from_b or (from_a < 0 and in_a.dot(in_b) > 0.85):
		return false
	if in_a.dot(in_b) < -0.85 and in_a.dot(out_a) > 0.85 and in_b.dot(out_b) > 0.85:
		return false
	return true

## a stop sign on my way: a full stop at its line, a moment, then on (and the junction
## after it taken in turn); a give-way: down to walking pace at the line
func _sign_ahead(c: Car, dt: float) -> float:
	c.holding = false
	if g._signs.is_empty():
		return INF
	for j in range(c.k + 1, c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > 60.0:
			break
		var n := c.node[j]
		if not g._signs.has(n):
			continue
		var dir := c.pts[j] - c.pts[maxi(j - 1, 0)]
		if dir.length_squared() < 0.01 and j >= 2:
			dir = c.pts[j] - c.pts[j - 2]
		var rule: Array = g._sign_rule(n, dir)
		if rule.is_empty():
			continue
		var line := dist - float(rule[1])
		if line < -1.0:
			continue
		if rule[0] == "give_way":
			return sqrt(16.0 + 2.0 * BRAKE * maxf(line, 0.0))
		if c.sign_done == n:
			continue
		c.holding = true
		if line < 2.5 and c.v < 0.3:
			c.sign_wait += dt
			if c.sign_wait > 0.8:
				c.sign_done = n
				c.sign_wait = 0.0
			return 0.0
		return sqrt(2.0 * BRAKE * maxf(line - 0.3, 0.0))
	return INF

func _passed_lights(c: Car, before: float) -> void:
	for j in range(c.k, c.pts.size()):
		if c.cum[j] > c.s:
			break
		if c.cum[j] > before and g._sig_set.has(c.node[j]) and c.cum[j] - c.last_light >= LIGHT_SKIP:
			c.last_light = c.cum[j]

## how far along my lane ahead something at q is (centre to centre), or INF if it is not
## on it
func _path_gap(c: Car, q: Vector2, look: float, wide := LANE_W) -> float:
	for j in range(c.k, c.pts.size() - 1):
		var base := c.cum[j] - c.s
		if base > look:
			break
		var a := c.pts[j]
		var b := c.pts[j + 1]
		var d := b - a
		if d.length_squared() < 0.0001:
			continue
		var dn := d.normalized()
		var cp := Geometry2D.get_closest_point_to_segment(q, a, b)
		var off := q - cp
		var lon := off.dot(dn)
		var lat := off.dot(Vector2(dn.y, -dn.x))   # to the left of the lane line
		# in my lane: the one I am in, and while changing, the one I am going to
		if Vector2(lon, lat - c.shift).length() < wide or (absf(c.shift_to - c.shift) > 0.3 and Vector2(lon, lat - c.shift_to).length() < wide):
			var along := base + a.distance_to(cp)
			if along > 0.5:
				return along
	return INF

## someone on a zebra crossing on my way: stop short of it (the speed allowed now, or INF)
func _zebra_ahead(c: Car) -> float:
	var best := INF
	for z: Array in g._zebras_on:
		var mid: Vector2 = z[0]
		if mid.distance_squared_to(c.pos) > 4900.0:
			continue
		for j in range(c.k, c.pts.size() - 1):
			var base := c.cum[j] - c.s
			if base > 70.0:
				break
			var cp := Geometry2D.get_closest_point_to_segment(mid, c.pts[j], c.pts[j + 1])
			if cp.distance_to(mid) < float(z[1]):
				var stop := base + c.pts[j].distance_to(cp) - 4.0 - c.len * 0.5
				if stop > -1.5:   # (over the line already: through)
					best = minf(best, sqrt(2.0 * BRAKE * maxf(stop - 0.3, 0.0)))
				break
	return best

## where q is from this car's lane line: (metres ahead of it, metres to the left), or INF
func _proj(c: Car, q: Vector2, back: float, ahead: float) -> Vector2:
	for j in range(maxi(c.k - 4, 0), c.pts.size() - 1):
		var base := c.cum[j] - c.s
		if base > ahead:
			break
		var a := c.pts[j]
		var b := c.pts[j + 1]
		var d := b - a
		var L := d.length()
		if L < 0.01:
			continue
		var dn := d / L
		var t := (q - a).dot(dn)
		if t < -0.01 or t > L + 0.01:
			continue
		var lat := (q - a).dot(Vector2(dn.y, -dn.x))
		if absf(lat) > 9.0:
			continue
		var along := base + t
		if along < -back:
			continue
		return Vector2(along, lat)
	return Vector2(INF, INF)

## which way a driver is signalling: changing lanes (left is +shift), the turn ahead within
## 40 m, a bus pulling in to its stop or out of it
func _signal(c: Car, dt: float) -> void:
	c.pull_out = maxf(0.0, c.pull_out - dt)
	if c.kind == "bus" and c.dwell > DWELL - 1.5:
		c.pull_out = 4.0
	if c.pull_out > 0.0:
		c.blink = -1
		return
	if absf(c.shift_to - c.shift) > 0.4:
		c.blink = -1 if c.shift_to > c.shift else 1
		return
	var turn: Array = _turn_ahead(c)
	if int(turn[0]) != 0 and float(turn[1]) < 40.0:
		c.blink = int(turn[0])
		return
	if c.kind == "bus" and c.shift_to < c.shift - 0.2:
		c.blink = 1
		return
	c.blink = 0

## ---- lanes --------------------------------------------------------------------------------

## lanes each way on road r: OSM's count when it has one, else what the width holds
func _lanes_dir(r: Dictionary) -> int:
	return g._lanes_each_way(r)

## how far left of the lane line lane `idx` (from the right) of road r lies
func _lane_shift(r: Dictionary, idx: int) -> float:
	var n := _lanes_dir(r)
	if n <= 1:
		return 0.0
	var w := float(r["w"])
	var centre := 0.0   # to the right of the road's middle
	if int(r["o"]) != 0:
		centre = w * 0.5 - w / n * (idx + 0.5)
	else:
		centre = w * 0.5 - w * 0.5 / n * (idx + 0.5)
	return _lane(r) - centre

## the next junction ahead within 110 m where this car turns: [+1 right / -1 left / 0
## straight on, metres to it], or [0, INF]
func _turn_ahead(c: Car) -> Array:
	var n := c.pts.size()
	for j in range(c.k + 1, n - 1):
		var dist := c.cum[j] - c.s
		if dist > 110.0:
			break
		var node := c.node[j]
		if node < 0 or _ways_out(node) < 3:
			continue
		var din := (c.pts[j] - c.pts[maxi(j - 2, 0)]).normalized()
		var dout := (c.pts[mini(j + 2, n - 1)] - c.pts[j]).normalized()
		var a := din.angle_to(dout)
		return [0 if absf(a) < 0.6 else (1 if a > 0.0 else -1), dist]
	return [0, INF]

func _near_junction(c: Car, ahead: float) -> bool:
	for j in range(maxi(c.k - 2, 0), c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > ahead:
			return false
		if dist > -8.0 and c.node[j] >= 0 and _ways_out(c.node[j]) >= 3:
			return true
	return false

## nobody (nor the player) beside or close behind or ahead in the lane `shift` left of my line
func _lane_clear(c: Car, i: int, shift: float) -> bool:
	for j in range(cars.size() + 1):
		var q: Vector2
		if j == cars.size():
			q = g._pos
		else:
			if j == i or not (cars[j] as Car).alive:
				continue
			q = (cars[j] as Car).pos
		if q.distance_squared_to(c.pos) > 900.0:
			continue
		var pr := _proj(c, q, 16.0, 24.0)
		if pr.x != INF and pr.x > -14.0 and pr.x < 22.0 and absf(pr.y - shift) < 2.3:
			return false
	return true

## Which lane: on a road with more than one each way, into the right one for the turn
## ahead (right lane for a right turn, left for a left), out to overtake a slow car in
## front when the lane beside is free, back to the right now and then. A bus keeps to the
## right lane. A scooter stuck behind a queue rides the line between two lanes past it.
func _steer_lanes(c: Car, i: int, dt: float, best: float, lead_v: float) -> void:
	c.lane_t = maxf(0.0, c.lane_t - dt)
	var r: Dictionary = _roads[c.rd[mini(c.k + 1, c.rd.size() - 1)]]
	var n := _lanes_dir(r)
	if n <= 1:
		c.lane_i = 0
		c.split = false
		c.shift_to = 0.0
		return
	var want := c.lane_i
	var turn: Array = _turn_ahead(c)
	var vnow: float = c.vmax[mini(c.k + 1, c.vmax.size() - 1)]
	if c.kind == "bus":
		want = 0
	elif int(turn[0]) != 0 and float(turn[1]) < 110.0:
		want = 0 if int(turn[0]) > 0 else n - 1
	elif best < 40.0 and lead_v < vnow * 0.75 and c.lane_i < n - 1 and c.lane_t <= 0.0 and c.kind != "moto":
		want = c.lane_i + 1   # out to pass
	elif c.lane_i > 0 and c.lane_t <= 0.0 and rng.randf() < dt * 0.1:
		want = c.lane_i - 1   # keep right
	want = clampi(want, 0, n - 1)
	c.lane_i = clampi(c.lane_i, 0, n - 1)
	if want != c.lane_i and c.lane_t <= 0.0 and not _near_junction(c, 14.0):
		var step := c.lane_i + (1 if want > c.lane_i else -1)
		if _lane_clear(c, i, _lane_shift(r, step)):
			c.lane_i = step
			c.lane_t = 3.0
	c.shift_to = _lane_shift(r, c.lane_i)
	if c.kind == "moto":
		if best < 20.0 and lead_v < 2.0:
			c.split = true
			c.free_t = 0.0
		elif c.split:
			c.free_t += dt
			# back into the lane only where there is room in it: merging back beside a car
			# put the scooter on top of it
			if c.free_t > 3.0 and _lane_clear(c, i, c.shift_to):
				c.split = false
		if c.split:
			var lw := float(r["w"]) / n * (1.0 if int(r["o"]) != 0 else 0.5)
			c.shift_to += lw * 0.5 * (1.0 if c.lane_i < n - 1 else -1.0)

## A bus pulls in at each stop on its side of the street, stands a while, and goes on:
## the speed that stops it at the next one it has not served, or INF
func _bus_stop(c: Car, dt: float) -> float:
	if c.kind != "bus":
		return INF
	for j in range(c.k, c.pts.size() - 1):
		var base := c.cum[j] - c.s
		if base > 70.0:
			break
		var a := c.pts[j]
		var b := c.pts[j + 1]
		var L := a.distance_to(b)
		if L < 0.01:
			continue
		var d := (b - a) / L
		for id: int in g._near(g._stop_hash, a.lerp(b, 0.5), L * 0.5 + 10.0, g.SEG_CELL):
			if c.served.has(id):
				continue
			var sp: Vector2 = g._stop_spots[id]
			var t := (sp - a).dot(d)
			var side := (sp - a).dot(Vector2(-d.y, d.x))
			if t < 0.0 or t > L or side < 0.5 or side > 9.0:
				continue
			var at := base + t
			if at < 45.0:
				c.shift_to -= 0.9   # in toward the kerb
			if at < 1.6:
				if c.v < 0.4:
					c.dwell += dt
					if c.dwell > DWELL:
						c.served[id] = true
						c.dwell = 0.0
						return INF
				return 0.0
			return sqrt(2.0 * BRAKE * maxf(at - 0.6, 0.0))
	return INF

## the same for any lane (the player's autodrive): [gap centre to centre, speed of the car
## there along the lane, half its length], or [INF, 0, 0]. A car is found by points along its
## body (five along a bus), not only its middle: a bus pulled in at its stop, or slanting out
## of it, stuck its back corner into the lane while its middle was clear of it -- and the
## half length lets autodrive stop short of a bus's back, not a car's length behind its middle.
func lead_on(path: PackedVector2Array, from: Vector2, look: float, ignore_crossing: bool) -> Array:
	var best := INF
	var bv := 0.0
	var bhalf := 0.0
	var who := -1
	if path.size() < 2:
		return [best, bv, bhalf, who]
	var start := Geometry2D.get_closest_point_to_segment(from, path[0], path[1])
	for c: Car in cars:
		if not c.alive or c.pos.distance_squared_to(from) > (look + c.len * 0.5 + 6.0) * (look + c.len * 0.5 + 6.0):
			continue
		var cdir := Vector2(sin(c.yaw), cos(c.yaw))
		var offs: Array = BODY[c.kind][0] if BODY.has(c.kind) else [-c.len * 0.33, 0.0, c.len * 0.33]
		var rad: float = float(BODY[c.kind][1]) if BODY.has(c.kind) else 0.95
		var found := INF
		var same_at := 0.0
		for off: float in offs:
			var q := c.pos + cdir * off
			var base := -path[0].distance_to(start)
			for j in range(path.size() - 1):
				if base > look:
					break
				var a := path[j]
				var b := path[j + 1]
				var cp := Geometry2D.get_closest_point_to_segment(q, a, b)
				var dir := (b - a).normalized()
				var same := dir.dot(cdir)
				# one going my way is in it wherever the bodies would touch: my half width,
				# its, and a hand's breadth (by its middle alone, at 1.5 m, one in the next
				# lane on a narrow road was not, and autodrive ran in between two of them)
				var wide := LANE_W
				if same > 0.6:
					wide = maxf(LANE_W, 0.9 + rad + 0.25)
				if cp.distance_to(q) < wide:
					var along := base + a.distance_to(cp) - off * same   # (as if from its middle)
					if along > 0.5 and along < found and not (ignore_crossing and same < 0.6):
						found = along
						same_at = same
					break
				base += a.distance_to(b)
		if found < best:
			best = found
			bv = c.v * maxf(same_at, 0.0)
			bhalf = c.len * 0.5
			who = cars.find(c)
	return [best, bv, bhalf, who]

## ---- the path -----------------------------------------------------------------------------

func _spawn(c: Car, first: bool) -> bool:
	var me: Vector2 = g._pos
	var look := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
	# a few tries a tick once driving (the rest on later ticks: see tick()), more at the start
	for _try in range(24 if first else 8):
		var ang := rng.randf() * TAU
		var d := rng.randf_range(35.0 if first else SPAWN_MIN, SPAWN_MAX)
		var q := me + Vector2(cos(ang), sin(ang)) * d
		if not first and d < 185.0 and Vector2(cos(ang), sin(ang)).dot(look) > 0.0:
			continue   # in front of the camera and near enough to see it appear
		var hit: Dictionary = g._nearest_seg(q, 40.0, true, true)
		if hit.is_empty():
			continue
		var ri: int = hit["road"]
		var r: Dictionary = _roads[ri]
		if r["k"] == "service" or rng.randf() > float(KIND_W.get(r["k"], 0.25)):
			continue
		if c.kind == "bus" and not BUS_ROADS.has(r["k"]):
			continue
		var at: Vector2 = hit["q"]
		if at.distance_to(me) < 30.0:
			continue
		var crowded := false
		for o: Car in cars:
			if o != c and o.alive and o.pos.distance_to(at) < 14.0:
				crowded = true
		if crowded:
			continue
		var sj: int = hit["seg"]
		var dir := 1 if rng.randf() < 0.5 else -1
		if r["o"] != 0:
			dir = int(r["o"])
		if _start_on(c, ri, sj, at, dir):
			return true
	return false

## start car c at `at` on road ri's segment sj, driving `dir` along it, in a lane of its
## own picking, its path planned on for 140 m; false when the road runs out too soon
func _start_on(c: Car, ri: int, sj: int, at: Vector2, dir: int) -> bool:
	var r: Dictionary = _roads[ri]
	var p: PackedVector2Array = r["pts"]
	var along := (p[sj + 1] - p[sj]).normalized() * dir
	var lane := _lane(r)
	var n := _lanes_dir(r)
	c.lane_i = 0 if (c.kind == "bus" or rng.randf() < 0.5) else rng.randi_range(0, n - 1)
	c.lane_i = clampi(c.lane_i, 0, n - 1)
	c.shift = _lane_shift(r, c.lane_i)
	c.shift_to = c.shift
	c.shift_rate = 0.0
	c.split = false
	c.served = {}
	c.dwell = 0.0
	c.pts = PackedVector2Array([at + Vector2(-along.y, along.x) * lane])
	c.cum = PackedFloat32Array([0.0])
	c.node = PackedInt32Array([-1])
	c.rd = PackedInt32Array([ri])
	c.vmax = PackedFloat32Array([float(r["speed"]) * c.pace])
	c.k = 0
	c.s = 0.0
	c.last_light = -1000.0
	_leg(c, ri, sj + 1 if dir > 0 else sj, dir)
	while c.cum[c.cum.size() - 1] < 140.0:
		if not _next(c):
			break
	if c.cum[c.cum.size() - 1] < 20.0:
		return false   # (a dead end straight ahead: somewhere else)
	c.v = c.vmax[0] * 0.7
	c.want = -1.0
	c.wait = 0.0
	c.hit = 0.0
	c.ignore = 0.0
	c.squeeze = 0.0
	_place(c)
	c.prev_pos = c.pos
	c.prev_yaw = c.yaw
	return true

## A car put on the road nearest `at` (within 25 m), heading the way `heading` points (a
## one-way street's own way whatever it says), at its road's pace: for a scripted moment, a
## filmed walk's cars. It is the car furthest from the player, out of sight as a rule.
## False when there is no road there.
func send(at: Vector2, heading: Vector2) -> bool:
	var far: Car = null
	var fd := -1.0
	for c: Car in cars:
		if c.kind == "bus":
			continue   # (a bus down a side street)
		var d: float = INF if not c.alive else c.pos.distance_to(g._pos)
		if d > fd:
			fd = d
			far = c
	var hit: Dictionary = g._nearest_seg(at, 25.0, true, true)
	if far == null or hit.is_empty():
		return false
	var ri: int = hit["road"]
	var r: Dictionary = _roads[ri]
	var p: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var dir := 1 if (p[sj + 1] - p[sj]).dot(heading) >= 0.0 else -1
	if r["o"] != 0:
		dir = int(r["o"])
	far.alive = _start_on(far, ri, sj, hit["q"], dir)
	return far.alive

## the right-hand lane's offset from the middle of a road. Every two-way street gets two,
## however narrow (both ways down the middle met head on).
func _lane(r: Dictionary) -> float:
	return g._lane_off(r)

## append road `ri` from index `from` to its end in direction `dir`, in the right-hand lane
func _leg(c: Car, ri: int, from: int, dir: int) -> void:
	var r: Dictionary = _roads[ri]
	var p: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var lane := _lane(r)
	var lim := float(r["speed"]) * c.pace
	var last := p.size() - 1 if dir > 0 else 0
	if r.get("ring", false):
		last = _ring_stop(r, from, dir, last)
	_turn_into(c, ri, from, dir, lane, lim)
	var start := c.pts.size()
	var i := from
	while true:
		var prv := p[i - dir] if (i - dir >= 0 and i - dir < p.size()) else p[i]
		var nxt := p[i + dir] if (i + dir >= 0 and i + dir < p.size()) else p[i]
		var d := (nxt - prv).normalized()
		var q: Vector2 = g._clear_lane(p[i], d, lane)
		var tail := c.pts[c.pts.size() - 1]
		c.cum.append(c.cum[c.cum.size() - 1] + tail.distance_to(q))
		c.pts.append(q)
		c.node.append(ids[i])
		c.rd.append(ri)
		c.vmax.append(lim)
		if i == last:
			break
		i += dir
	c.end = Vector3i(ri, last, dir)
	_curves(c, start - 8)

## Into the next road at a junction (the player's autodrive does the same, see the game's
## _ap_turn_into): the last road ended on the junction's point and the next one's first
## point can be far down it; the straight line between ran down the wrong side of the new
## street, into the cars coming the other way. The turn now starts just short of the
## junction in its lane and comes out just past it in the right lane. The junction's node
## goes on the middle of the curve, where it was, for the lights and the giving way.
func _turn_into(c: Car, ri: int, from: int, dir: int, lane: float, lim: float) -> void:
	var r: Dictionary = _roads[ri]
	var p: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var at := from - dir
	var n := c.pts.size()
	if at < 0 or at >= p.size() or n < 2:
		return
	var node := ids[at]
	if c.node[n - 1] != node or _ways_out(node) < 3:
		return
	var cn: Vector2 = g._nodes[node]
	var before := c.pts[n - 2]
	var in_dir := (cn - before).normalized()
	var out_dir := (p[from] - cn).normalized()
	if in_dir == Vector2.ZERO or out_dir == Vector2.ZERO or absf(in_dir.angle_to(out_dir)) < 0.35:
		return
	var rin := Vector2(-in_dir.y, in_dir.x)
	var rout := Vector2(-out_dir.y, out_dir.x)
	var lane_in := (c.pts[n - 1] - cn).dot(rin)
	var back := minf(_node_r[node] + 1.0, before.distance_to(cn) * 0.8)
	var ahead := minf(_node_r[node] + 1.0, cn.distance_to(p[from]) * 0.8)
	var E := cn - in_dir * back + rin * lane_in
	var X := cn + out_dir * ahead + rout * lane
	var K = Geometry2D.line_intersects_line(E, in_dir, X, -out_dir)
	var k2: Vector2 = K if K != null and (K as Vector2).distance_to(cn) < back + ahead + 4.0 else (E + X) * 0.5
	var rd_in := c.rd[n - 1]
	var v_in := c.vmax[n - 1]
	c.pts[n - 1] = E
	c.node[n - 1] = -1
	c.cum[n - 1] = c.cum[n - 2] + before.distance_to(E)
	for t: float in [0.25, 0.5, 0.75, 1.0]:
		var q := E * (1.0 - t) * (1.0 - t) + k2 * 2.0 * (1.0 - t) * t + X * t * t
		c.cum.append(c.cum[c.cum.size() - 1] + c.pts[c.pts.size() - 1].distance_to(q))
		c.pts.append(q)
		c.node.append(node if t == 0.5 else -1)
		c.rd.append(rd_in if t <= 0.5 else ri)
		c.vmax.append(minf(v_in, lim))

## corners: the radius through the points 5 m either side of each, and the speed that keeps
## the sideways pull comfortable round it
func _curves(c: Car, from_k: int) -> void:
	for k in range(maxi(1, from_k), c.pts.size() - 1):
		var a := _at(c, c.cum[k] - 5.0)
		var b := c.pts[k]
		var d := _at(c, c.cum[k] + 5.0)
		var cr := absf((b - a).cross(d - a))
		if cr < 0.001:
			continue
		var radius := a.distance_to(b) * b.distance_to(d) * d.distance_to(a) / (2.0 * cr)
		c.vmax[k] = minf(c.vmax[k], maxf(sqrt(CURVE_LAT * radius), 2.5))

## On a roundabout a leg ends at the next way off it, so a car can leave there. (Driving
## a ring to its OSM end first sent cars nearly all the way round, and there "straight on"
## was round again: they circled, and the cars waiting to come on waited for ever.)
func _ring_stop(r: Dictionary, from: int, dir: int, last: int) -> int:
	var ids: PackedInt32Array = r["ids"]
	var k := from
	while k != last:
		if k != from and _ways_out(ids[k]) >= 3:
			return k
		k += dir
	return last

## at the end of the planned road, the next one: straight on rather than a turn, a main
## road rather than a side street, never against a one-way, back only from a dead end
func _next(c: Car) -> bool:
	if c.end.x < 0:
		return false
	var r: Dictionary = _roads[c.end.x]
	var p: PackedVector2Array = r["pts"]
	var ei := c.end.y
	var dir := c.end.z
	var node: int = (r["ids"] as PackedInt32Array)[ei]
	var prev := clampi(ei - dir, 0, p.size() - 1)
	var came := (p[ei] - p[prev]).normalized()
	var best := Vector3i(-1, 0, 0)
	var best_score := -INF
	var back := Vector3i(-1, 0, 0)
	for e: Vector2i in _node_roads[node]:
		var r2: Dictionary = _roads[e.x]
		if not r2["drive"] or r2["pv"] or r2["k"] == "service":
			continue
		var p2: PackedVector2Array = r2["pts"]
		for d2: int in [1, -1]:
			var nxt := e.y + d2
			if nxt < 0 or nxt >= p2.size():
				continue
			if r2["o"] != 0 and r2["o"] != d2:
				continue
			if e.x == c.end.x and nxt == prev:
				back = Vector3i(e.x, nxt, d2)
				continue
			var go := (p2[nxt] - p2[e.y]).normalized()
			var straight := came.dot(go)
			if straight < -0.7:
				continue
			var score := straight * 1.4 + float(KIND_W.get(r2["k"], 0.25)) * 1.2 + rng.randf() * 1.5
			# into a dead end only when there is nothing else: the cars went in through
			# traffic, turned round at the end in a queue of others doing the same, and
			# overlapped there (a dozen times a run in one cul-de-sac)
			if _dead_end(r2, nxt, d2):
				score -= 4.0
			if r.get("ring", false):
				# on a roundabout: off it at one of the next few exits, never round and round
				score += (-0.6 - 1.1 * c.ring_n) if r2.get("ring", false) else 1.0
			if c.kind == "bus":
				score += 3.0 if BUS_ROADS.has(r2["k"]) else -3.0   # buses keep to their routes
			if score > best_score:
				best_score = score
				best = Vector3i(e.x, nxt, d2)
	if best.x < 0:
		best = back
	if best.x < 0:
		return false
	c.ring_n = c.ring_n + 1 if (_roads[best.x] as Dictionary).get("ring", false) else 0
	_leg(c, best.x, best.y, best.z)
	return true

## road r from point k on, going dir: does it end in a dead end with no turning on the way?
func _dead_end(r: Dictionary, k: int, dir: int) -> bool:
	var ids: PackedInt32Array = r["ids"]
	var last := ids.size() - 1 if dir > 0 else 0
	if g._node_ways(ids[last]) > 1:
		return false
	while k != last:
		if g._node_ways(ids[k]) >= 3:
			return false
		k += dir
	return true

## drop what is well behind, so the path stays short
func _trim(c: Car) -> void:
	if c.k < 12:
		return
	var cut := 10
	var off := c.cum[cut]
	c.pts = c.pts.slice(cut)
	c.node = c.node.slice(cut)
	c.rd = c.rd.slice(cut)
	c.vmax = c.vmax.slice(cut)
	var cum := c.cum.slice(cut)
	for j in range(cum.size()):
		cum[j] -= off
	c.cum = cum
	c.s -= off
	c.last_light -= off
	c.k -= cut

## the segment the car is on, from where it was last
func _seek(c: Car) -> void:
	while c.k < c.cum.size() - 2 and c.cum[c.k + 1] < c.s:
		c.k += 1
	while c.k > 0 and c.cum[c.k] > c.s:
		c.k -= 1

func _at(c: Car, s: float) -> Vector2:
	var n := c.pts.size()
	if s <= 0.0:
		return c.pts[0]
	if s >= c.cum[n - 1]:
		return c.pts[n - 1]
	var j := clampi(c.k, 0, n - 2)
	while j < n - 2 and c.cum[j + 1] < s:
		j += 1
	while j > 0 and c.cum[j] > s:
		j -= 1
	var seg := c.cum[j + 1] - c.cum[j]
	return c.pts[j].lerp(c.pts[j + 1], (s - c.cum[j]) / maxf(seg, 0.001))

## where the body is: the chord between points 2.2 m either side on the lane, so it rounds
## the corners of the lane line instead of pivoting on them
func _place(c: Car) -> void:
	_seek(c)
	var a := _at(c, c.s - 2.2)
	var b := _at(c, c.s + 2.2)
	c.pos = (a + b) * 0.5
	var d := b - a
	if d.length_squared() > 0.01:
		c.yaw = atan2(d.x, d.y)
		if g._hnx > 0:
			c.pitch = atan2(float(g._h(b)) - float(g._h(a)), d.length())
	# a little drift in the lane while it moves (nobody holds the line to the centimetre)
	var wander := sin(_clock * 0.31 + c.drift) * 0.14 * clampf(c.v / 8.0, 0.0, 1.0)
	var off := c.shift + wander
	if off != 0.0 or c.shift_rate != 0.0:
		c.pos += Vector2(cos(c.yaw), -sin(c.yaw)) * off       # its lane: left of the line
		c.yaw += atan2(c.shift_rate, maxf(c.v, 3.0))         # nose into the lane change

func _in_view(p: Vector2) -> bool:
	var look := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
	var to: Vector2 = p - g._pos
	return to.length() < 200.0 and to.normalized().dot(look) > 0.3

## ---- every drawn frame --------------------------------------------------------------------

func draw(f: float) -> void:
	for i in range(cars.size()):
		var c: Car = cars[i]
		if not c.alive:
			continue
		var p := c.prev_pos.lerp(c.pos, f)
		var yaw := lerp_angle(c.prev_yaw, c.yaw, f)
		# (the slope it is on, the nose dipping or lifting, the lean in a turn)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -c.pitch + c.dip) * Basis(Vector3.BACK, c.roll)
		var xf := Transform3D(basis, Vector3(p.x, float(g._h(p)) + float(g.road_top()), p.y))
		var mm: MultiMesh = _mms[c.kind]
		mm.set_instance_transform(i, xf)
		# alpha: the brake light, plus 2 for a driver, 4 for a driver and a passenger (the car
		# shader draws them through the glass)
		mm.set_instance_custom_data(i, Color(c.paint, c.braking + (4.0 if c.passenger else 2.0)))
		if _night:
			_beams.multimesh.set_instance_transform(i, xf)
		if _blobs.visible:
			var cs: Vector2 = CORNERS.get(c.kind, Vector2(0.9, 2.25))
			_blobs.multimesh.set_instance_transform(i, xf * Transform3D(Basis.from_scale(Vector3(cs.x * 2.0 + 0.8, 1.0, cs.y * 2.0 + 1.0)), Vector3(0, 0.02, 0)))
		# the indicators: the car's right is its -X
		var lit := c.blink != 0 and fmod(_clock + float(i) * 0.13, 0.7) < 0.36
		if lit:
			var cn: Vector2 = CORNERS.get(c.kind, Vector2(0.9, 2.25))
			var x := -float(c.blink) * (cn.x - 0.04)
			_blinkers.set_instance_transform(i * 2, xf * Transform3D(Basis(), Vector3(x, 0.72, cn.y)))
			_blinkers.set_instance_transform(i * 2 + 1, xf * Transform3D(Basis(), Vector3(x, 0.86, -cn.y)))
		else:
			_blinkers.set_instance_transform(i * 2, Transform3D(Basis(), Vector3(0, -500, 0)))
			_blinkers.set_instance_transform(i * 2 + 1, Transform3D(Basis(), Vector3(0, -500, 0)))

func _hide_or_show(i: int) -> void:
	var c: Car = cars[i]
	if not c.alive:
		(_mms[c.kind] as MultiMesh).set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
		if _blinkers != null:
			_blinkers.set_instance_transform(i * 2, Transform3D(Basis(), Vector3(0, -500, 0)))
			_blinkers.set_instance_transform(i * 2 + 1, Transform3D(Basis(), Vector3(0, -500, 0)))
		if _beams != null:
			_beams.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
		if _blobs != null:
			_blobs.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))

## ---- the player's car against them --------------------------------------------------------

## how far to move a circle at `p` (radius r) to be clear of every car: each is two
## circles along its length, like a parked car
func push(p: Vector2, r: float) -> Vector2:
	var out := Vector2.ZERO
	for i in range(cars.size()):
		var c: Car = cars[i]
		if not c.alive or c.pos.distance_squared_to(p) > (100.0 if c.kind == "bus" else 64.0):
			continue
		var fwd := Vector2(sin(c.yaw), cos(c.yaw))
		var body: Array = BODY.get(c.kind, [[1.25, -1.25], 0.85])
		for off: float in body[0]:
			var d := (p + out) - (c.pos + fwd * off)
			var need := r + float(body[1])
			if d.length() < need:
				out += d.normalized() * (need - d.length()) if d.length() > 0.001 else Vector2(need, 0)
				hit_index = i
	return out

func bumped(i: int) -> void:
	if i >= 0 and i < cars.size():
		var c: Car = cars[i]
		c.hit = 2.5
		c.v = minf(c.v, 1.0)
