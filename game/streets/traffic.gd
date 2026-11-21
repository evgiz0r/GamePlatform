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
const LENS := {"sedan": 4.6, "hatch": 4.0, "mini": 3.6, "wagon": 4.65, "mpv": 4.4, "suv": 4.7, "van": 5.0, "taxi": 4.6, "bus": 11.8, "moto": 1.9, "truck": 6.8}
## the player's car against each kind: circles along its length [offsets], radius
const BODY := {"bus": [[-4.6, -2.3, 0.0, 2.3, 4.6], 1.25], "moto": [[0.0], 0.55], "truck": [[-2.3, 0.0, 2.3], 1.15]}
const BUS_ROADS := {"primary": true, "secondary": true, "tertiary": true, "trunk": true}
const LANE_MOVE := 1.4       ## sideways speed changing lanes (m/s): about 2.5 s a lane
const SIDE_PER_V := 0.35     ## sideways at most this share of the speed (about 19 degrees)
const REALIGN := 0.3        ## following a road change's new lane line: sideways at this share of the speed
const NARROW_LOOK := 90.0   ## how far ahead a car looks for its way narrowing to fewer lanes
const BUS_TURN_IN := 40.0    ## a car turning right off a road with a bus lane moves into it this close to the turn
const DWELL := 7.0           ## seconds a bus stands at a stop
## A van or truck now and then stops in the street for a delivery, hazards on, half in its
## lane (there is no room at the kerb: the parked cars); cars behind go round it over the
## centre line when nothing is coming, autodrive too (_ap_pass_bus). And now and then a car
## parked ahead of the player pulls out as they come.
const DBL_SHARE := 0.1       ## of the vans and trucks, the share that stop somewhere on the way
                             ## (0.45 was too many standing in the street: "very rare in Israel", a user)
const DBL_ROADS := {"residential": true, "tertiary": true, "unclassified": true, "secondary": true, "living_street": true}
const KERB_EVERY := Vector2(35.0, 75.0)   ## seconds between cars set to pull out ahead of the player
const KERB_BOARD := 0.6      ## of those, the share with someone getting in beside the driver first
const LANE_W := 1.5          ## a car on my path: its middle within this of my lane line
const PLAYER_W := 2.0        ## the player's car counts as in my way from further over: it
                             ## need not be on a lane line, and half in the lane is in it
const CURVE_LAT := 2.6       ## sideways pull a driver takes a corner at (m/s^2)
const SITE_KEEP := 120.0     ## metres after which the junction last driven into is forgotten (a car can come back)
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
	var y := 0.0                      ## the height of the surface under it: the ground, or a bridge or a tunnel's road
	var lift := 0.0                   ## y above the ground under it: about 0 on the street, a deck's height on a bridge (see _level)
	var prev_y := 0.0
	var rear := Vector2.INF           ## where its rear axle is (trailing the front: see _place)
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
	var ignore_car := -1              ## ...and this one car, at any angle (a ring of cars each waiting for the next)
	var squeeze := 0.0                ## seconds it edges past the player (a narrow street's standoff)
	var hit := 0.0                    ## seconds it sits stunned after the player hit it
	var retry := 0.0                  ## seconds before trying again to find it a road
	var want := -1.0                  ## the speed it last decided on (-1: decide now)
	var passenger := false            ## someone beside the driver (seen through the glass)
	var last_light := -1000.0         ## s where it last came into a junction with lights...
	var last_site := -1               ## ...and which (its other points are not stopped at again)
	var amber_go := -1                ## the lit point it went on for, too late to stop on amber
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
	var film_through := false         ## a filmed walk's car that drives on past it at a zebra (send)
	var split := false                ## a scooter filtering between the lanes past a queue
	var bus_ok := false               ## may drive in a bus lane: a bus, and half the taxis
	var shift_rd := -1                ## the road its shift_to is a lane of
	var realign := false              ## moving over because the road changed, not changing lanes
	var free_t := 0.0
	var dwell := 0.0                  ## a bus: seconds stood at the stop
	var served := {}                  ## a bus: the stops it has stopped at
	var blink := 0                    ## indicating: -1 left, 1 right
	var ring_n := 0                   ## pieces of roundabout driven since it came onto one
	var pull_out := 0.0               ## a bus leaving a stop: seconds it signals out
	## the street's own goings-on (_double_park, _kerb_tick):
	var dbl_s := -1.0                 ## a van or truck making a delivery: where (s along its path) it stops in the street
	var dbl := 0.0                    ## ... and the seconds it stands there, hazards on
	var dbl_edge := INF               ## ... and how far left of its lane line what stands at the kerb along the way in reaches (INF: not measured yet)
	var dbl_edge_s := -1.0            ## (the stop it was measured for)
	var kerb := false                 ## parked at the kerb ahead of the player, to pull out as they come
	var kerb_t := 0.0                 ## seconds parked
	var hold_t := 0.0                 ## seconds still to wait, signalling, before pulling out
	var pass_i := -1                  ## the double-parked car it is going round, over the centre line
	var door := 0.0                   ## a kerb car: its front passenger's door, 0 shut .. 1 open
	var board_t := -1.0               ## ... seconds its passenger has been getting in (-1: not yet)
	var stood := false                ## ... stood at the kerb: a parked car's dust and permit, driven off
	var rev_t := 0.0                  ## ... seconds it still backs up, its reversing lights on, before pulling out
	var steer := 0.0                  ## the front wheels' angle, radians (+ left: visual)
	var cover_on := 0                 ## its front wheels on a manhole cover now (bits)
	var steer_to := 0.0               ## ... the lane its front runs on, against its heading

var g: Node                           ## the game: its road graph, lights, ground, player
var cars: Array = []
var rng := RandomNumberGenerator.new()
var hit_index := -1                   ## the car the player last bumped
var _me_lift := 0.0                   ## the player's height above the ground under it, this tick (see _level)
var _clock := 0.0
var _degree := {}                     ## node -> how many ways out of it (3+: a junction)
const TAKE_AHEAD := 22.0              ## who goes first at a junction is settled this far before it
var _mm: MultiMesh
var _mms := {}                        ## car shape -> its multimesh
var _beams: MultiMeshInstance3D       ## their beams on the road, at night
var _door: MultiMeshInstance3D        ## the kerb car's open door (one at a time)
var _door_i := -1                     ## ... whose
## each kind's half width and half length, for where its indicators are
const CORNERS := {"sedan": Vector2(0.9, 2.25), "hatch": Vector2(0.86, 1.95), "mini": Vector2(0.8, 1.8),
	"wagon": Vector2(0.9, 2.3), "mpv": Vector2(0.92, 2.18), "suv": Vector2(0.96, 2.32),
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
	for kind: String in ["sedan", "hatch", "mini", "wagon", "mpv", "suv", "van", "taxi", "bus", "moto", "truck"]:
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
	# (the indicators are in every vehicle's own lamps, in the car shader: the boxes they were
	# -- one more draw -- went)
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
	# a kerb car's open door: the car shader's, painted the car's colour (custom data)
	var dm := MultiMesh.new()
	dm.transform_format = MultiMesh.TRANSFORM_3D
	dm.use_colors = true
	dm.use_custom_data = true
	dm.mesh = g._door_mesh("sedan")
	dm.instance_count = COUNT   # (the door at its car's own slot: the shader's dust and fading are the car's)
	dm.custom_aabb = box
	for k in range(COUNT):
		dm.set_instance_transform(k, Transform3D(Basis(), Vector3(0, -500, 0)))
		dm.set_instance_color(k, Color.WHITE)
	_door = MultiMeshInstance3D.new()
	_door.multimesh = dm
	_door.visible = false
	g.world.add_child(_door)
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
	# (0.3-0.9 s: with 0.35-1.1 a queue's start-up wave ran ~1.2 s a car against the ~1 s
	# measured at real signals, and queues crossed the line a quarter slower -- queue_start)
	c.react = lerpf(0.9, 0.3, brisk) * rng.randf_range(0.8, 1.2)
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
	_kerb_tick(dt)
	var me: Vector2 = g._pos
	_me_lift = float(g._y) - float(g._h(me))
	# One car a tick is put back near the player: driving off leaves several behind at once,
	# and finding each a new road in the same tick (up to 24 tries apiece) was a stutter every
	# few seconds. One that found nowhere this time looks again a moment later.
	var spawned := false
	for i in range(cars.size()):
		var c: Car = cars[i]
		c.prev_pos = c.pos
		c.prev_yaw = c.yaw
		c.prev_y = c.y
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
		# moving over because the road changed (onto a narrower one, a slip road's lane) and
		# someone is where it is moving to: it eases off and lets them by rather than sliding
		# into their side -- realign never looked (two cars on HaGdud HaIvri moved over into
		# each other, the exam's overlaps)
		if c.realign and absf(c.shift_to - c.shift) > 0.5 and c.v > 1.0 and not _side_clear(c, i, c.shift_to):
			vt = minf(vt, c.v * 0.8)
		var lat := maxf(LANE_MOVE, c.v * REALIGN) if c.realign else LANE_MOVE
		# Sideways only as it rolls, like a car steering: its back trails the front (_place),
		# so a shift while it stood moved the front alone and swung the body round -- cars
		# waiting at Kaplan's light stood 60 degrees across the next lane, on its cars
		# (pulling out from close behind a delivery van it goes round: steeper, as people turn
		# out at a crawl -- at 19 degrees, from 2 m behind it, it met the van's corner first)
		var side_k := 0.8 if c.pass_i >= 0 and c.v < 3.0 else SIDE_PER_V
		lat = minf(lat, c.v * side_k * 4.6 / maxf(c.len, 4.6))   # (a 12 m bus angled as much swung its ends into the next lane)
		var ds := clampf(c.shift_to - c.shift, -lat * dt, lat * dt)
		if c.realign and absf(c.shift_to - c.shift - ds) < 0.05:
			c.realign = false
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
				# (behind a car, the moment to notice starts when that car is off (0.5 m/s),
				# not when it has rolled a few millimetres -- but only when it is close: one
				# that stopped short of a standing car, with metres still to close, never
				# rolled up (tests/traffic_stuck.gd: three in four minutes, one 6 m short).
				# 3.5 m/s is about 2 m of room at the braking it plans with.)
				# (0.3 m/s: seen to be moving -- at 0.5 the follower waited ~0.45 s more for the
				# car in front's gentle first push to show; nearer 0 the queue went like a train)
				if not (c.why == "car" and c.lead_v < 0.3 and vt < 3.5):
					c.react_t += dt
				# and waiting to react it stands: it crept on at 0.26 m/s for as long as it
				# waited, neither pulling away nor stopped
				c.v = move_toward(c.v, 0.0, BRAKE * dt)
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
		c.steer = move_toward(c.steer, c.steer_to, 1.4 * dt)   # (a driver turns the wheel, not snaps it)
		# a front wheel over a manhole cover, near you: the nose bobs
		if c.v > 2.0 and c.pos.distance_squared_to(g._pos) < 2500.0:
			var fw := Vector2(sin(c.yaw), cos(c.yaw))
			var sd := Vector2(-fw.y, fw.x) * 0.78
			var on := 0
			for k in range(2):
				if float(g.cover_under(c.pos + fw * c.len * 0.3 + (sd if k == 0 else -sd))) > 0.0:
					on |= 1 << k
			if on & ~c.cover_on:
				c.dip -= 0.012
			c.cover_on = on

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
	if c.kerb or c.hold_t > 0.0:
		return _kerb_wait(c, dt)
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
			if not _level(c, float(g._y), _me_lift):
				continue   # (overhead on a bridge, or under it)
			q = g._pos
			ov = maxf(float(g._v), 0.0)
			oyaw = atan2(cos(float(g._yaw)), sin(float(g._yaw)))   # the player's heading, as this file turns

		else:
			if j == i:
				continue
			var o: Car = cars[j]
			if not o.alive or not _level(c, o.y, o.lift):
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
		if j == c.pass_i and c.shift > 1.3:
			continue   # out past its side, going round it
		var wide := PLAYER_W if j == cars.size() else LANE_W
		if j < cars.size() and absf(angle_difference(oyaw, c.yaw)) < 0.6:
			var oc: Car = cars[j]
			var me_w: Vector2 = CORNERS.get(c.kind, CORNERS["sedan"])
			var its: Vector2 = CORNERS.get(oc.kind, CORNERS["sedan"])
			if absf(oc.shift_to - oc.shift) > 0.3:
				# one changing lanes stands across two: its body, not its middle, says whose way
				# it is in -- a bus stopped by a light halfway over, angled, its back end out, was
				# 2.7 m to the side of the van behind in the next lane, which drove into it
				wide = maxf(wide, me_w.x + its.x + absf(sin(angle_difference(oyaw, c.yaw))) * its.y)
			elif oc.kind in ["bus", "truck"] and absf(angle_difference(oyaw, c.yaw)) < 0.5:
				# a bus or truck going my way is on my path when the bodies would touch side by
				# side, not by its middle within 1.5 m: cars drove through a 2.2 m truck's flank in
				# the next lane. Only those: counting every car by its body stopped queues in the
				# junction for what they could pass (queue_start 1.07x -> 1.25-1.62x)
				wide = maxf(wide, me_w.x + its.x + 0.1)
		if c.split:
			wide = 0.6   # filtering: only what is right in front of the wheel
		if c.ignore > 0.0 and j == c.ignore_car:
			wide = 0.6   # breaking a ring: past the one it waited for, unless it is square in front
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
	# a delivery van stood in the street ahead: round it, over the centre line, when nothing comes
	if who >= 0 and who != c.pass_i and best < 35.0 and _parked_double(cars[who]) and c.kind != "bus":
		var rr: Dictionary = _roads[c.rd[mini(c.k + 1, c.rd.size() - 1)]]
		if _lanes_dir(rr) <= 1 and int(rr["o"]) == 0 and not _near_junction(c, best + 12.0) \
				and _oncoming_clear(c, i, best + 45.0, _pass_shift(rr), _pass_secs(c, best + (cars[who] as Car).len + c.len + 1.5), best + (cars[who] as Car).len + c.len + 1.5):
			c.pass_i = who
			Probe.event("go_round", {"kind": c.kind})
	c.ignore = maxf(0.0, c.ignore - dt)
	if c.squeeze > 0.0:
		c.squeeze -= dt
		vt = _held(c, vt, 2.5, "squeezing past")
	c.lead_v = lead_v if best < INF else 99.0
	_steer_lanes(c, i, dt, best, lead_v)
	vt = _held(c, vt, _bus_stop(c, dt), "bus stop")
	vt = _held(c, vt, _double_park(c, dt), "delivery")
	if best < INF:
		# (the seconds behind at its own speed while it is the slower: a queue pulling away
		# kept its gap for the speed the car in front had reached, so each waited till that
		# one was well off -- the third car of a queue moved 9 s after the green)
		var free := best - (c.len + best_len) * 0.5 - c.gap
		var room := free - minf(lead_v, c.v) * c.headway
		var follow := sqrt(maxf(0.0, lead_v * lead_v + 2.0 * BRAKE * maxf(room, 0.0)))
		# (inside its seconds behind: a little under that car's pace to open the gap again,
		# not a stop -- `0.0` there braked it 7.5 m/s^2 to a standstill behind a car going
		# its own speed, and the player's car behind it, its sudden stops charted)
		if room <= 0.0:
			follow = maxf(lead_v + room * 0.5, 0.0) if free > 0.0 else 0.0
		if who >= 0 and who == c.pass_i:
			# going round the van it stands behind: creep on, pulling out. It moves sideways
			# only as it rolls, and the van counts as in its way until it is out past its side:
			# standing there, waiting to be out before it rolled, it never went (van_pass).
			var bump := best - (c.len + best_len) * 0.5
			follow = maxf(follow, minf(1.2, sqrt(2.0 * BRAKE * maxf(bump - 0.6, 0.0))))
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
				# cars each waiting for the next round a ring (two in a junction, or side by side
				# after a merge, or three): the lowest number goes, past the one that holds it at
				# any angle. Ignoring only crossing cars, two nearly side by side in Ashdod each
				# held the other for good (the exam's "held by nothing ... a loop")
				if c.wait > 2.5 and who >= 0:
					var ring: Array = [i]
					var k := who
					while k >= 0 and k < cars.size() and ring.size() < 6 and not ring.has(k):
						var ok: Car = cars[k]
						if not ok.alive or ok.wait <= 2.5:
							break
						ring.append(k)
						k = ok.blocker
					if k == i and ring.size() >= 2 and i == ring.min():
						c.ignore = 3.0
						c.ignore_car = who
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

## the first traffic light ahead that counts -- of a junction it is not in already (see the
## game's _lights_setup: one junction can be several points): stop at its line on red, and on
## amber when there is room to; through on green
func _light_ahead(c: Car) -> float:
	for j in range(c.k + 1, c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > 80.0:
			break
		var n := c.node[j]
		if not g._sig_set.has(n):
			continue
		var dir := _came(c, j)
		var way: Array = g._way_in(n, dir)
		if way.is_empty() or way[3]:
			continue   # not a way into it from outside (inside a junction of several points)
		if c.amber_go == n:
			return INF   # it went on amber, too close to stop: through, red or not (see below)
		# over the line and rolling, or in the junction: committed, through. Over the line but
		# standing -- stopped there for people on the crossing -- is not: it waited for the
		# people, then drove on through the red
		# (rolling: moving at all -- 2 m/s left a scooter filtering over the line at walking
		# pace on amber "not committed": it stopped on the crossing, 7 m past the line)
		var rolling_in := c.v > 0.5 or dist - c.len * 0.5 < _node_r[n]
		if _in_site(c, n) and rolling_in:
			continue   # in it already
		var state: String = g._light_at(n, dir)
		# the front at the stop line, not the middle: a bus's middle there left its front 4 m
		# into the junction, across the other road
		var stop: float = dist - (float(way[1]) + 1.0 + c.len * 0.5)
		if state == "g" or (stop < -1.5 and rolling_in):
			return INF
		# too late to stop on amber: through. Judged at a firmer braking than the stop below
		# is planned at -- the same, and a car that could stop kept its speed (the plan asked
		# for no braking yet) until it could not, often late in the amber, and crossed on red
		if state == "y" and c.v * c.v > 2.0 * (BRAKE + 1.0) * maxf(stop, 0.1):
			# and that stands: going on, it braked as hard as it could the moment the light
			# turned red and stopped in the junction, a truck 4.5 m past the line (the exam)
			c.amber_go = n
			return INF
		return sqrt(2.0 * BRAKE * maxf(stop - 0.3, 0.0))
	return INF

## the way a car ARRIVES at its point j (a few metres back): the node sits mid-curve on a
## turn, and the direction there read the cross street's light as often as its own
func _came(c: Car, j: int) -> Vector2:
	var k := j - 1
	while k > 0 and c.cum[j] - c.cum[k] < 6.0:
		k -= 1
	return c.pts[j] - c.pts[maxi(k, 0)]

## has this car come into the junction with lights that node n is a point of?
func _in_site(c: Car, n: int) -> bool:
	return c.last_site >= 0 and g._site_of.get(n, -2) == c.last_site and c.s - c.last_light < SITE_KEEP

## Is car o (coming to node n at its point k) going to stand at its red there? Then a car
## with the green need not wait for it. Not if it is in that junction already, or over the line.
func _held_at_red(o: Car, k: int, n: int) -> bool:
	if not g._sig_set.has(n):
		return false
	var dir := _came(o, k)
	var way: Array = g._way_in(n, dir)
	if way.is_empty() or way[3]:
		return false
	var dist := o.cum[k] - o.s
	var rolling_in := o.v > 2.0 or dist - o.len * 0.5 < _node_r[n]
	if (_in_site(o, n) and rolling_in) or g._light_at(n, dir) != "r":
		return false
	return dist - (float(way[1]) + 1.0 + o.len * 0.5) > -1.0 or not rolling_in

## The next junction on my way, and who goes first. A car already in it goes. Then the
## bigger road: a roundabout's ring above all (on it you go, coming in you give way), then
## main roads over side streets. Between equals, whoever gets there first; turning across,
## give way to one going straight. The player always has the right of way. A car kept
## waiting long enough creeps through (the car in front still holds it back), so a jam
## cannot lock for good. (The first version was first come, first served, and a car kept
## the junction while it sat in a queue: whole crossroads and roundabouts locked up.)
## how far back from junction point n, along the way car c comes in to its point j, its
## front must stand for both front corners to be 0.5 m clear of every road crossing there:
## (w/2 + 0.5 + half width * |cos|) / sin of the angle between them; the road it is on and
## its straight-on continuation (within ~20 degrees) are not crossing
func _clear_back(c: Car, j: int, n: int) -> float:
	var in_dir := _came(c, j)
	if in_dir.length_squared() < 0.0001:
		return 0.0
	in_dir = in_dir.normalized()
	var hw: float = (CORNERS.get(c.kind, Vector2(0.9, 2.3)) as Vector2).x
	var need := 0.0
	for e: Vector2i in _node_roads[n]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var u := pts[mini(e.y + 1, pts.size() - 1)] - pts[maxi(e.y - 1, 0)]
		if u.length_squared() < 0.0001:
			continue
		u = u.normalized()
		var sn := absf(in_dir.cross(u))
		if sn < 0.35:
			continue
		need = maxf(need, (float(r["w"]) * 0.5 + 0.5 + hw * absf(in_dir.dot(u))) / sn)
	return minf(need, _node_r[n] * 2.5 + 2.0)

func _junction_ahead(c: Car, i: int, dt: float) -> float:
	for j in range(c.k + 1, c.pts.size() - 1):
		var dist := c.cum[j] - c.s
		if dist > TAKE_AHEAD + c.v * 1.5:
			break
		var n := c.node[j]
		if n < 0 or _ways_out(n) < 3:
			continue
		# (its front at the junction's edge -- and, at a skewed junction, as far back as keeps
		# both front corners 0.5 m off each crossing road's asphalt: the same distance along a
		# slanted way in left a corner in the lane, and the cars going by drove through it)
		# (not at lights: there the lights decide, and held further back a queue's next car
		# waited for anything in the junction -- the car ahead of it too: queue_start 1.07x
		# -> 1.48x)
		var lit_near: bool = not (g._near(g._sig_hash, g._nodes[n], 40.0, g.SEG_CELL) as Array).is_empty()   # (a junction's unlit points too)
		var back := _node_r[n] + 1.0 if lit_near else maxf(_node_r[n] + 1.0, _clear_back(c, j, n))
		var edge := dist - (back + c.len * 0.5)
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
		# (not while autodrive stands giving way at this junction: it waits for me, I go)
		if _level(c, float(g._y), _me_lift) and not g._ap_giving.has(n) and not (rel.dot(fwd) < 0.0 and absf(rel.dot(Vector2(-fwd.y, fwd.x))) < 2.5):
			var pd := me_at.distance_to(node_at)
			var pv := maxf(float(g._v), 0.0)
			var pfwd := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
			if pd < _node_r[n] + 3.0:
				return _hold(c, dt, stop)
			# (autodrive gives way by itself now: a car too close to stop comfortably for it goes
			# on, and autodrive waits; one that stood on its brakes for autodrive was the worse)
			var can_stop: bool = not g._auto or c.v * c.v <= 2.0 * BRAKE * maxf(edge - 0.3, 0.0) + 2.0
			if pd < _node_r[n] + 30.0 and pv > 1.5 and pfwd.dot(node_at - me_at) > 0.0 \
					and pd / pv < my_eta + 1.5 and can_stop:
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
			if _held_at_red(o, ok, n):
				continue   # it will stand at its red: my green is mine (it held cars on a green
				           # back for a car waiting at the red across, seconds at a time)
			var o_eta := od / maxf(o.v, 2.0)
			if o_eta > 5.0:
				continue
			if g._sig_set.has(n):
				# lights: they say who goes. One held at its red is not coming (a car with its
				# green gave way to one on the main road that was about to stop at its red, sat
				# out its green and was caught by the next red: a queue on a side street let
				# one car through a green); one with its green too goes first only when I turn
				# across it
				if _in_site(o, n):
					# already in the junction (a point of it further on), clearing it: its light
					# there reads the street across, but it is not stopping for it
					if o_eta < my_eta + 1.5:
						return _hold(c, dt, stop)
					continue
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
		# (the front at the painted line, not the middle -- as at a light: with the middle there
		# a car's nose stood 2 m into the junction, in the crossing street's lane, and the next
		# car along it drove into it; a bus's stood at the junction's middle)
		var line := dist - float(rule[1]) - c.len * 0.5
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

## a car's front over a stop line: it is in that junction (all its points)
func _passed_lights(c: Car, before: float) -> void:
	for j in range(c.k + 1, c.pts.size()):
		if c.cum[j] - c.s > 30.0:
			break
		var n := c.node[j]
		if n < 0 or not g._sig_set.has(n):
			continue
		var line: float = c.cum[j] - g._light_line(n, _came(c, j)) - c.len * 0.5   # (where its middle is with the front at the line)
		if line > c.s:
			break
		if line > before - 0.01 or (_in_site(c, n) and c.cum[j] > before):
			c.last_site = g._site_of.get(n, -1)
			c.last_light = c.s

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
		if mid.distance_squared_to(c.pos) > 4900.0 or (c.film_through and z.size() >= 4):
			continue   # (a filmed walk's car that drove on: past the walk's own zebras only)
		for j in range(c.k, c.pts.size() - 1):
			var base := c.cum[j] - c.s
			if base > 70.0:
				break
			var cp := Geometry2D.get_closest_point_to_segment(mid, c.pts[j], c.pts[j + 1])
			if cp.distance_to(mid) < float(z[1]):
				if g._zebra_clear(z, cp):
					break   # (the person is on the other half of a divided road, or not there yet)
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
	if _parked_double(c):
		c.blink = 2   # hazards
		return
	if c.kerb or c.rev_t > 0.0:
		c.blink = 0
		return
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

## ---- the street's goings-on -----------------------------------------------------------------

## standing in the street making its delivery (hazards on)
func _parked_double(o: Car) -> bool:
	return o.alive and o.dbl_s >= 0.0 and o.dbl_s - o.s < 2.0 and o.v < 0.5

## over the centre line: the other way's lane, from this one's line
func _pass_shift(r: Dictionary) -> float:
	return clampf(2.0 * _lane(r), 2.3, 3.4)

var pass_by_time := true   ## false for a test: a pass judged by distance alone, as before (tests/van_pass.gd PASS_OLD=1)

## seconds for car c to drive `d` metres from its speed now, pulling away as it does
func _pass_secs(c: Car, d: float) -> float:
	if not pass_by_time:
		return 0.0
	var a := maxf(c.accel, 1.0)
	# (and a margin: round a van it eases out and back, slower than it could)
	return (sqrt(c.v * c.v + 2.0 * a * maxf(d, 0.0)) - c.v) / a * 1.25 + 1.5

## nothing coming the other way (nor anyone already over there) for `reach` metres ahead --
## and, given `secs` (how long the pass of `d` metres will take), nothing that would get to
## the pass's far end in that time at its speed now.
## (By distance alone, 35 + 45 m, a car went round a delivery van with the player 60-80 m
## off at 50 km/h -- there in under 6 s, the pass taking 7 or 8 -- and stood head-on in the
## player's lane, held by them: autodrive braked 8.8 m/s^2 from 48 km/h and touched it.)
func _oncoming_clear(c: Car, i: int, reach: float, over: float, secs := 0.0, d := 0.0) -> bool:
	for j in range(cars.size() + 1):
		var q: Vector2
		if j == cars.size():
			if not _level(c, float(g._y), _me_lift):
				continue
			q = g._pos
		else:
			var o: Car = cars[j]
			if j == i or not o.alive or not _level(c, o.y, o.lift) or _parked_double(o):
				continue
			q = o.pos
		# (it must not reach the far end of the pass, `d` on, before the pass is done)
		var qv: float = maxf(float(g._v), 0.0) if j == cars.size() else (cars[j] as Car).v
		var far := maxf(reach, d + qv * secs + 10.0)
		if q.distance_squared_to(c.pos) > (far + 10.0) * (far + 10.0):
			continue
		var pr := _proj(c, q, 8.0, far)
		if pr.x != INF and absf(pr.y - over) < 2.0:
			return false
	return true

## A van or truck's delivery: it pulls in toward the kerb as far as there is room, stops,
## stands DBL seconds with its hazards on, signals and goes. Where it stops is put off a little
## while that is a junction, a crossing or a road it would not stop in. The speed it may do
## now, or INF.
func _double_park(c: Car, dt: float) -> float:
	if c.dbl_s < 0.0:
		return INF
	var to := c.dbl_s - c.s
	if to > 70.0:
		return INF
	if c.v > 0.5 and to > 3.0:   # still coming to it: is it somewhere to stop?
		var ok := true
		for jj in range(c.k, c.pts.size()):
			var at := c.cum[jj] - c.s
			if at > to + 20.0:
				break
			if absf(at - to) < 20.0 and c.node[jj] >= 0 and _ways_out(c.node[jj]) >= 3:
				ok = false   # (by a junction)
			if absf(at - to) < 6.0 and not DBL_ROADS.has(String(_roads[c.rd[jj]]["k"])):
				ok = false
		for z: Array in g._zebras_on:
			if (z[0] as Vector2).distance_to(_at(c, c.dbl_s)) < 15.0:
				ok = false
		if not ok:
			c.dbl_s += 25.0
			if c.dbl_s - c.s > 260.0:
				c.dbl_s = -1.0   # (nowhere suitable: no delivery this time)
			return INF
	if to < 35.0:   # in toward the kerb, as far as there is room
		var r: Dictionary = _roads[c.rd[mini(c.k + 1, c.rd.size() - 1)]]
		var cw: float = (CORNERS.get(c.kind, Vector2(0.95, 2.4)) as Vector2).x
		var room := clampf(float(r["w"]) * 0.5 - _lane(r) - cw - 0.3, 0.0, 1.0)
		# and no further than keeps its side 0.3 m off what stands at the kerb, on the way in
		# and where it stops: parked cars stand a third in the road, and a truck pulled in by
		# the asphalt's room alone stood 0.3 m into one's side (the exam's "traffic body into a
		# post" -- a parked car is two posts to the car)
		if c.dbl_edge_s != c.dbl_s:
			c.dbl_edge_s = c.dbl_s
			c.dbl_edge = _kerb_edge(c, to + c.len * 0.5)
		if c.dbl_edge > -INF:
			room = clampf(minf(room, c.shift_to - cw - 0.3 - c.dbl_edge), 0.0, 1.0)
		c.shift_to -= room
	if to < 1.2:
		if c.v < 0.4:
			c.dbl -= dt
			if c.dbl <= 0.0:
				c.dbl_s = -1.0
				c.pull_out = 3.0
				return INF
		return 0.0
	return sqrt(2.0 * BRAKE * maxf(to - 0.6, 0.0))

## how far left of car c's lane line (right: negative) the nearest thing standing to its
## right reaches, over its path from its back now to `ahead` metres on: the inner edge of the
## parked cars, posts and trees along the kerb it would pull in toward; -INF if none
func _kerb_edge(c: Car, ahead: float) -> float:
	var edge := -INF
	var seen := {}
	var step := 0.0
	while step <= ahead + 0.1:
		var at := _at(c, c.s - c.len * 0.5 + step)
		for pi: int in g._near(g._post_hash, at, 5.0, g.BLD_CELL):
			if seen.has(pi):
				continue
			seen[pi] = true
			var pr := _proj(c, g._posts[pi], c.len * 0.5 + 1.0, ahead + 1.0)
			if pr.x == INF or pr.y > c.shift_to:
				continue   # (off its path, or left of its middle)
			edge = maxf(edge, pr.y + float(g._post_r[pi]))
		step += 4.0
	return edge

## Now and then a car parked at the kerb ahead of the player, 90-150 m on along their street
## (where the street's parked cars are, in a gap between them), that pulls out as they come:
## it signals, waits a moment, and goes -- in front of them, as people do.
var _kerb_t := 20.0

func _kerb_tick(dt: float) -> void:
	_kerb_t -= dt
	if _kerb_t > 0.0:
		return
	_kerb_t = rng.randf_range(KERB_EVERY.x, KERB_EVERY.y)
	if g._walking or absf(float(g._v)) < 4.0 or String(g._place.get("look", "")) != "med":
		return
	var pick: Car = null
	var far := -1.0
	for c: Car in cars:
		if c.kerb or c.hold_t > 0.0:
			return   # (one at a time)
		if c.kind == "bus" or c.kind == "moto" or c.kind == "truck" or c.dbl_s >= 0.0:
			continue
		var d: float = INF if not c.alive else c.pos.distance_to(g._pos)
		if d > far and (not c.alive or not _in_view(c.pos)):
			far = d
			pick = c
	if pick == null:
		return
	var hit: Dictionary = g._nearest_seg(g._pos, 8.0, true, true)
	if hit.is_empty():
		return
	var ri: int = hit["road"]
	var r: Dictionary = _roads[ri]
	if not DBL_ROADS.has(String(r["k"])) or _lanes_dir(r) > 1:
		return
	var p: PackedVector2Array = r["pts"]
	var sj: int = hit["seg"]
	var fwd := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
	var dir := 1 if (p[sj + 1] - p[sj]).dot(fwd) >= 0.0 else -1
	if int(r["o"]) != 0 and dir != int(r["o"]):
		return
	var lane := _lane(r)
	var cw: float = (CORNERS.get(pick.kind, Vector2(0.9, 2.25)) as Vector2).x
	var kshift := -(float(r["w"]) * 0.5 - lane - cw - 0.25)   # (its side 0.25 m off the kerb)
	if kshift > -0.8:
		return   # (no room at this kerb to stand clear of the lane)
	for d: float in [130.0, 115.0, 100.0, 145.0, 90.0]:
		var spot := _along_road(p, sj, hit["q"], dir, d)
		if spot.is_empty():
			continue
		var at: Vector2 = spot[0]
		var seg: int = spot[1]
		var along: Vector2 = (p[seg + 1] - p[seg]).normalized() * dir
		var right := Vector2(-along.y, along.x)
		var kp := at + right * (lane - kshift)
		# a gap among the street's parked cars: parked cars near (so people park here), none in it
		var parking := false
		for pi: int in g._near(g._post_hash, kp, 12.0, g.BLD_CELL):
			if is_equal_approx(float(g._post_r[pi]), 0.85):
				parking = true
		if not parking:
			continue
		var free := true
		for k: float in [-2.0, 0.0, 2.0]:
			if g._push_out(kp + along * k, cw + 0.05, true, false) != Vector2.ZERO:
				free = false
		for o: Car in cars:
			if o != pick and o.alive and o.pos.distance_to(kp) < 9.0:
				free = false
		if not free:
			continue
		if not _start_on(pick, ri, seg, at, dir):
			return
		pick.alive = true
		pick.kerb = true
		pick.kerb_t = 0.0
		pick.v = 0.0
		pick.shift = kshift
		pick.shift_to = kshift
		pick.rear = Vector2.INF
		pick.stood = true
		pick.passenger = false
		_place(pick)
		pick.prev_pos = pick.pos
		pick.prev_yaw = pick.yaw
		pick.prev_y = pick.y
		pick.steer = 0.0
		# now and then someone about to get in beside the driver: the door open over the
		# pavement, them standing at it (where the door and they have room)
		if rng.randf() < KERB_BOARD:
			var stand := _board_spot(pick, 0.0)
			var tip := _board_tip(pick)
			if g._push_out(stand, 0.3, true, false) == Vector2.ZERO and g._push_out(tip, 0.12, true, false) == Vector2.ZERO \
					and not g._wall_between(pick.pos, stand) and g.boarder_at(stand, Vector2(cos(pick.yaw), -sin(pick.yaw)), false):
				pick.door = 1.0
				pick.board_t = -1.0
		_hide_or_show(cars.find(pick))
		Probe.event("kerb_car", {"ahead": int(d), "boarding": pick.door > 0.0})
		return

## the point `d` metres on along road points p from q (on segment sj) going `dir`: [point,
## its segment], or [] when the road ends first
func _along_road(p: PackedVector2Array, sj: int, q: Vector2, dir: int, d: float) -> Array:
	var cur := q
	var k := sj + (1 if dir > 0 else 0)
	var left := d
	while k >= 0 and k < p.size():
		var L := cur.distance_to(p[k])
		if L >= left:
			var at := cur.lerp(p[k], left / maxf(L, 0.001))
			return [at, k - 1 if dir > 0 else k]
		left -= L
		cur = p[k]
		k += dir
	return []

## parked at the kerb: still, until the player is coming up behind (18-45 m) or a while has
## gone; then a moment signalling, and out
func _kerb_wait(c: Car, dt: float) -> float:
	c.why = "parked"
	if c.hold_t > 0.0:
		if c.rev_t > 0.0:   # backing up a little first, its reversing lights on
			c.rev_t -= dt
			c.s = maxf(c.s - 0.3 * dt, 0.0)
			c.why = "backing out"
			if c.rev_t <= 0.0:
				c.pull_out = 3.0
			return 0.0
		c.hold_t -= dt
		if c.hold_t <= 0.0:
			Probe.event("pull_out", {"kind": c.kind})
			return c.vmax[mini(c.k + 1, c.vmax.size() - 1)]
		return 0.0
	c.kerb_t += dt
	var rel: Vector2 = g._pos - c.pos
	var behind := -rel.dot(Vector2(sin(c.yaw), cos(c.yaw)))
	if c.door > 0.0:
		# someone at the open door: they get in as the player comes (or after a while), the
		# door shuts, and only then does it think of going
		if c.board_t < 0.0 and ((behind > 0.0 and behind < 95.0 and absf(float(g._v)) > 2.0) or c.kerb_t > 40.0):
			c.board_t = 0.0
		if c.board_t < 0.0:
			g.boarder_keep()
		if c.board_t >= 0.0:
			c.board_t += dt
			if c.board_t < BOARD_IN:
				g.boarder_at(_board_spot(c, c.board_t / BOARD_IN), Vector2(cos(c.yaw), -sin(c.yaw)), true)
			else:
				if not c.passenger:
					c.passenger = true   # (in: the shader seats them)
					g.boarder_gone()
					Probe.event("boarded", {})
				c.door = maxf(0.0, c.door - dt / 0.7)
		return 0.0
	if (behind > 18.0 and behind < 62.0 and absf(float(g._v)) > 2.0) or c.kerb_t > 50.0:
		c.kerb = false
		c.hold_t = 1.3
		# a parked car backs up a little to get out (if there is room behind it), then signals
		var back := Vector2(sin(c.yaw), cos(c.yaw)) * -2.75
		var cw: float = (CORNERS.get(c.kind, Vector2(0.9, 2.25)) as Vector2).x
		if g._push_out(c.pos + back, cw - 0.1, true, false) == Vector2.ZERO:
			c.rev_t = 0.9
		else:
			c.pull_out = 3.0   # (signalling out: _signal)
	return 0.0

## getting in: the time it takes them from the pavement into the seat
const BOARD_IN := 1.1

## where someone getting into the kerb car's passenger seat stands: by its right side, at the
## doorway's middle -- t 0 on the pavement, 1 at the seat (half inside the body: then gone)
func _board_spot(c: Car, t: float) -> Vector2:
	var dc: Vector2 = g._door_at(c.kind)
	var fwd := Vector2(sin(c.yaw), cos(c.yaw))
	var right := Vector2(-cos(c.yaw), sin(c.yaw))   # (its -X)
	return c.pos + fwd * (dc.y - 0.55) + right * lerpf(dc.x + 0.5, dc.x - 0.15, smoothstep(0.0, 1.0, t))

## the open door's back edge, for room
func _board_tip(c: Car) -> Vector2:
	var dc: Vector2 = g._door_at(c.kind)
	var fwd := Vector2(sin(c.yaw), cos(c.yaw))
	var right := Vector2(-cos(c.yaw), sin(c.yaw))
	return c.pos + fwd * (dc.y - 1.0 * cos(1.0)) + right * (dc.x + 1.0 * sin(1.0))

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
		# off onto a slip road: a turn to its side, however shallow the fork (counted straight
		# at under 34 degrees, a car left Sderot Herzl's three lanes for its slip from the
		# middle one, across the bus in the kerb lane -- the exam's overlaps there)
		if absf(a) < 0.6 and absf(a) > 0.08 and _onto_link(c, j):
			return [1 if a > 0.0 else -1, dist]
		return [0 if absf(a) < 0.6 else (1 if a > 0.0 else -1), dist]
	return [0, INF]

## at point j of its path, does the car leave its road for a slip road (a "_link")?
func _onto_link(c: Car, j: int) -> bool:
	var into := -1
	for q in range(j + 1, mini(j + 4, c.rd.size())):
		if c.rd[q] >= 0 and c.rd[q] != c.rd[j]:
			into = c.rd[q]
			break
	if into < 0 or c.rd[j] < 0:
		return false
	return String((_roads[into] as Dictionary)["k"]).ends_with("_link") and not String((_roads[c.rd[j]] as Dictionary)["k"]).ends_with("_link")

func _near_junction(c: Car, ahead: float) -> bool:
	for j in range(maxi(c.k - 2, 0), c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > ahead:
			return false
		if dist > -8.0 and c.node[j] >= 0 and _ways_out(c.node[j]) >= 3:
			return true
	return false

## nobody beside it in the lane `shift` left of its line: from level with it to half a
## length ahead (those further ahead are followed as usual; braking for them while moving
## over, it slowed to a standstill and the move over stopped with it)
func _side_clear(c: Car, i: int, shift: float) -> bool:
	for j in range(cars.size()):
		if j == i or not (cars[j] as Car).alive:
			continue
		var o: Car = cars[j]
		if o.pos.distance_squared_to(c.pos) > 400.0 or not _level(c, o.y, o.lift):
			continue
		var pr := _proj(c, o.pos, 16.0, 24.0)
		if pr.x != INF and pr.x > -1.0 and pr.x < (o.len + c.len) * 0.5 and absf(pr.y - shift) < 2.0:   # (one level or ahead: it lets them go; one behind lets it)
			return false
	return true

## nobody (nor the player) beside or close behind or ahead in the lane `shift` left of my line
func _lane_clear(c: Car, i: int, shift: float) -> bool:
	for j in range(cars.size() + 1):
		var q: Vector2
		if j == cars.size():
			if not _level(c, float(g._y), _me_lift):
				continue
			q = g._pos
		else:
			if j == i or not (cars[j] as Car).alive or not _level(c, (cars[j] as Car).y, (cars[j] as Car).lift):
				continue
			q = (cars[j] as Car).pos
		if q.distance_squared_to(c.pos) > 900.0:
			continue
		var pr := _proj(c, q, 16.0, 24.0)
		if pr.x != INF and pr.x > -14.0 and pr.x < 22.0:
			if absf(pr.y - shift) < 2.3:
				return false
			# nor one moving into that lane itself: two cars either side of it each saw it
			# empty, moved in at once and drove on through each other side by side (the
			# exam's "bodies overlapping"). Where it is going: its shift still to come.
			if j < cars.size():
				var o: Car = cars[j]
				if Vector2(sin(o.yaw), cos(o.yaw)).dot(Vector2(sin(c.yaw), cos(c.yaw))) > 0.5 \
						and absf(pr.y + (o.shift_to - o.shift) - shift) < 2.3:
					return false
	return true

## In the kerb lane: as far toward the middle as keeps this vehicle's side 0.3 m inside the
## asphalt (its lane line is where a car's is: on a 5 m street a car's side was 0.1 m from the
## edge and a bus's 0.25 m over it, brushing the kerbside trees and poles -- the exam's
## "traffic body into a post"). A bus on a narrow street rides a little over the middle, as
## real ones do.
func _kerb_room(c: Car, r: Dictionary) -> float:
	var hw: float = (CORNERS.get(c.kind, Vector2(0.9, 2.3)) as Vector2).x
	return maxf(0.0, g._lane_off(r) + hw + 0.3 - float(r["w"]) * 0.5)

## Which lane: on a road with more than one each way, into the right one for the turn
## ahead (right lane for a right turn, left for a left), out to overtake a slow car in
## front when the lane beside is free, back to the right now and then. A bus keeps to the
## right lane. A scooter stuck behind a queue rides the line between two lanes past it.
func _steer_lanes(c: Car, i: int, dt: float, best: float, lead_v: float) -> void:
	c.lane_t = maxf(0.0, c.lane_t - dt)
	var r: Dictionary = _roads[c.rd[mini(c.k + 1, c.rd.size() - 1)]]
	var n := _lanes_dir(r)
	if c.pass_i >= 0:   # going round a delivery van: out until past it, then back
		var o: Car = cars[c.pass_i]
		var pr := _proj(c, o.pos, 40.0, 60.0)
		if not o.alive or pr.x == INF or pr.x < -(o.len + c.len) * 0.5 - 1.5:
			c.pass_i = -1
		elif pass_by_time and absf(c.shift) < 0.4 and c.v > 0.5 and not _oncoming_clear(c, i, pr.x + 20.0, _pass_shift(r),
				_pass_secs(c, pr.x + (o.len + c.len) * 0.5 + 1.5), pr.x + (o.len + c.len) * 0.5 + 1.5):
			# something coming that will be here before it is past, and it has barely begun to
			# move over: back in behind the van, and wait. (Only then: once further out, or
			# standing, it could not get back -- a car moves sideways only as it rolls -- and
			# stood with its nose in the other lane, face to face with autodrive, till taken away.)
			c.pass_i = -1
		else:
			c.shift_to = _pass_shift(r)
			return
	if n <= 1:
		c.lane_i = 0
		c.split = false
		var to1 := _kerb_room(c, r)   # (each vehicle's side 0.3 m on the asphalt: a bus's 1.25 m half width on a narrow street's lane line had it over the kerb into the poles)
		var rid1: int = c.rd[mini(c.k + 1, c.rd.size() - 1)]
		if rid1 != c.shift_rd:   # (onto a one-lane road: its middle, followed as below)
			if c.shift_rd >= 0 and absf(to1 - c.shift_to) > 0.3:
				c.realign = true
			c.shift_rd = rid1
		c.shift_to = to1
		return
	# Onto the next road: the lane of it the car is in, where it is, not the same number. Two
	# roads drawn on the node they share lie on one middle line, so the second lane of a
	# four-lane link is the first of the two-lane slip it runs on into (its numbers kept,
	# the link's second lane's cars all crossed over into the slip's other lane and stood on
	# each other there, at Begin x Kaplan).
	var rid0: int = c.rd[mini(c.k + 1, c.rd.size() - 1)]
	if rid0 != c.shift_rd and c.shift_rd >= 0 and c.shift_rd < _roads.size():
		var phys: float = _lane(_roads[c.shift_rd]) - c.shift   # right of the middle line, now
		var near_d := INF
		for idx in range(n):
			var dd := absf(_lane(r) - _lane_shift(r, idx) - phys)
			if dd < near_d:
				near_d = dd
				c.lane_i = idx
	var want := c.lane_i
	var turn: Array = _turn_ahead(c)
	var vnow: float = c.vmax[mini(c.k + 1, c.vmax.size() - 1)]
	# a bus lane: the buses' (and half the taxis'); the rest keep out of it but for the last
	# stretch before a right turn off it
	var bus_i := -1
	var way := 1
	if g._has_bus_lane(r):
		way = _way_on(c, r)
		for idx in range(n):
			if g._bus_lane(r, idx, way):
				bus_i = idx
				break
	if c.kind == "bus":
		want = bus_i if bus_i >= 0 else 0
	elif int(turn[0]) != 0 and float(turn[1]) < 110.0:
		want = 0 if int(turn[0]) > 0 else n - 1
	elif best < 40.0 and lead_v < vnow * 0.75 and c.lane_i < n - 1 and c.lane_t <= 0.0 and c.kind != "moto":
		want = c.lane_i + 1   # out to pass
	elif c.lane_i > 0 and c.lane_t <= 0.0 and rng.randf() < dt * 0.1:
		want = c.lane_i - 1   # keep right
	elif c.bus_ok and bus_i >= 0 and c.lane_t <= 0.0:
		want = bus_i
	want = clampi(want, 0, n - 1)
	# the way narrows ahead (a four-lane link into a two-lane slip): over to the lanes that
	# go on, in good time and with a look (clamped at the fork, cars from three lanes slid
	# into one at once, on top of each other -- Begin's slip off Kaplan)
	var n_on := n
	var narrow := -1
	var look := minf(NARROW_LOOK, float(turn[1]) if int(turn[0]) != 0 else INF)   # (up to a turn: the turn picks the lane)
	for j in range(c.k + 1, c.pts.size()):
		if c.cum[j] - c.s > look:
			break
		if c.rd[j] >= 0 and _lanes_dir(_roads[c.rd[j]]) < n_on:
			n_on = _lanes_dir(_roads[c.rd[j]])
			narrow = c.rd[j]
	if narrow >= 0:
		# the lanes that go on are the ones lying within the narrower road (on the same
		# middle line): the nearest of those to where the car would be
		var rn: Dictionary = _roads[narrow]
		var half := (float(rn["w"]) if int(rn["o"]) != 0 else float(rn["w"]) * 0.5) * 0.5
		var mid_n := 0.0 if int(rn["o"]) != 0 else float(rn["w"]) * 0.25   # (a two-way road's lanes this way: its right half)
		var best_w := want
		var best_d := INF
		for idx in range(n):
			var centre := _lane(r) - _lane_shift(r, idx)
			if absf(centre - mid_n) > half - 0.8:
				continue   # (ends: its lane does not go on)
			if absi(idx - want) < best_d:
				best_d = absi(idx - want)
				best_w = idx
		want = best_w if best_d < INF else mini(want, n_on - 1)
	if bus_i >= 0 and not c.bus_ok and not (int(turn[0]) > 0 and float(turn[1]) < BUS_TURN_IN):
		want = _off_bus_lanes(r, want, way, n)
		if g._bus_lane(r, c.lane_i, way):
			want = _off_bus_lanes(r, c.lane_i, way, n)   # (in one: out of it, the near way)
	c.lane_i = clampi(c.lane_i, 0, n - 1)
	if want != c.lane_i and c.lane_t <= 0.0 and not _near_junction(c, 14.0):
		var step := c.lane_i + (1 if want > c.lane_i else -1)
		if _lane_clear(c, i, _lane_shift(r, step)):
			c.lane_i = step
			c.lane_t = 3.0
			c.realign = false
	# Onto a road whose lanes lie elsewhere (the same lane of a narrower road, both drawn
	# on the node they share: a 12.8 m link into a 6.4 m slip) the car follows the road over
	# as it drives, not at a lane change's pace: at 1.4 m/s its side ran off the slip's edge
	# into the poles there for 25 m.
	var to := _lane_shift(r, c.lane_i)
	var rid: int = c.rd[mini(c.k + 1, c.rd.size() - 1)]
	if rid != c.shift_rd:
		if c.shift_rd >= 0 and absf(to - c.shift_to) > 0.3:
			c.realign = true
		c.shift_rd = rid
	c.shift_to = to
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

## the lane nearest `idx` going `way` along road r that is not a bus lane (leftward first:
## bus lanes are mostly on the right)
func _off_bus_lanes(r: Dictionary, idx: int, way: int, n: int) -> int:
	for d in range(n):
		for cand: int in [idx + d, idx - d]:
			if cand >= 0 and cand < n and not g._bus_lane(r, cand, way):
				return cand
	return idx

## which way car c runs along road r: 1 its points' way, -1 against
func _way_on(c: Car, r: Dictionary) -> int:
	if int(r["o"]) != 0:
		return signi(int(r["o"]))
	var p: PackedVector2Array = r["pts"]
	var fwd := Vector2(sin(c.yaw), cos(c.yaw))
	var best := INF
	var d := Vector2.ZERO
	for j in range(p.size() - 1):
		var dist := Geometry2D.get_closest_point_to_segment(c.pos, p[j], p[j + 1]).distance_squared_to(c.pos)
		if dist < best:
			best = dist
			d = p[j + 1] - p[j]
	return 1 if d.dot(fwd) >= 0.0 else -1

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
				# in toward the kerb -- as far as there is room: its side 0.3 m short of the
				# asphalt's edge. A whole 0.9 m on a 6 m street put a bus's side 0.9 m over
				# the kerb, into the stop's pole and the street trees (the exam's checks)
				var room := 0.9
				if j < c.rd.size() and c.rd[j] >= 0:
					var r: Dictionary = _roads[c.rd[j]]
					room = clampf(float(r["w"]) * 0.5 - g._lane_off(r) - CORNERS["bus"].x - 0.3, 0.0, 0.9)
				c.shift_to -= room
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
func lead_on(path: PackedVector2Array, from: Vector2, look: float, ignore_crossing: bool, y := NAN, skip := -1) -> Array:
	var best := INF
	var bv := 0.0
	var bhalf := 0.0
	var who := -1
	if path.size() < 2:
		return [best, bv, bhalf, who]
	var start := Geometry2D.get_closest_point_to_segment(from, path[0], path[1])
	var skipped: Car = cars[skip] if skip >= 0 and skip < cars.size() else null   # (one crossing that will be gone: see autodrive)
	for c: Car in cars:
		if not c.alive or c == skipped or c.pos.distance_squared_to(from) > (look + c.len * 0.5 + 6.0) * (look + c.len * 0.5 + 6.0):
			continue
		if not is_nan(y) and absf(c.y - y) > LEVEL + 0.08 * c.pos.distance_to(from):
			continue   # (on a bridge overhead, in a tunnel underneath -- not just down a hill:
			           # 60 m ahead on a 6% street a car is 3.6 m lower, and was not seen)
		var cdir := Vector2(sin(c.yaw), cos(c.yaw))
		var offs: Array = (BODY[c.kind][0] as Array).duplicate() if BODY.has(c.kind) else [-c.len * 0.33, 0.0, c.len * 0.33]
		# and its nose and tail: one waiting crossways at a junction's edge stuck its nose
		# into autodrive's turn, its middle well clear of the lane, and autodrive hit the nose
		offs.append(c.len * 0.5 - 0.3)
		offs.append(-c.len * 0.5 + 0.3)
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
		if g._pocketed(hit, g._trap) or g._pocketed(hit, g._cut_off) or g._pocketed(hit, g._outside):
			continue   # (in a pocket at the map's edge: a car put down there never got out -- see _find_pockets)
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
		if _by_junction(r, sj, at, 12.0):
			continue   # (put down in a junction's mouth at k 0, "held by junction", it stood there
			           # and the main road's traffic drove into it -- the exam, Ashdod's Inbar and Odem)
		var dir := 1 if rng.randf() < 0.5 else -1
		if r["o"] != 0:
			dir = int(r["o"])
		if _start_on(c, ri, sj, at, dir):
			return true
	return false

## within `d` m of a junction (a point of three ways or more) at either end of segment sj
func _by_junction(r: Dictionary, sj: int, at: Vector2, d: float) -> bool:
	var p: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	for k: int in [sj, sj + 1]:
		if k < ids.size() and ids[k] >= 0 and _ways_out(ids[k]) >= 3 and p[k].distance_to(at) < d:
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
	c.bus_ok = c.kind == "bus" or (c.kind == "taxi" and rng.randf() < 0.5)
	if g._has_bus_lane(r):   # (put down in a bus lane only if it may use one)
		for idx in range(n):
			if g._bus_lane(r, idx, dir) and (c.kind == "bus" or (c.bus_ok and rng.randf() < 0.5)):
				c.lane_i = idx
				break
		if not c.bus_ok:
			c.lane_i = _off_bus_lanes(r, c.lane_i, dir, n)
	c.shift = _lane_shift(r, c.lane_i)
	c.shift_to = c.shift
	c.shift_rate = 0.0
	c.shift_rd = ri
	c.realign = false
	c.split = false
	c.amber_go = -1
	c.served = {}
	c.dwell = 0.0
	c.dbl_s = -1.0
	c.dbl = 0.0
	c.kerb = false
	c.hold_t = 0.0
	c.pass_i = -1
	c.door = 0.0
	c.board_t = -1.0
	c.stood = false
	c.rev_t = 0.0
	c.steer = 0.0
	if (c.kind == "van" or c.kind == "truck") and String(g._place.get("look", "")) == "med" and rng.randf() < DBL_SHARE:
		c.dbl_s = rng.randf_range(60.0, 170.0)   # (a delivery somewhere ahead)
		c.dbl = rng.randf_range(25.0, 50.0)
	c.pts = PackedVector2Array([at + Vector2(-along.y, along.x) * lane])
	c.cum = PackedFloat32Array([0.0])
	c.node = PackedInt32Array([-1])
	c.rd = PackedInt32Array([ri])
	c.vmax = PackedFloat32Array([float(r["speed"]) * c.pace])
	c.k = 0
	c.s = 0.0
	c.film_through = false
	c.last_light = -1000.0
	c.last_site = -1
	c.y = g._decks.deck_y(ri, at) if r.has("ys") else float(g._h(at))
	c.lift = c.y - float(g._h(at))
	_leg(c, ri, sj + 1 if dir > 0 else sj, dir)
	while c.cum[c.cum.size() - 1] < 140.0:
		if not _next(c):
			break
	if c.cum[c.cum.size() - 1] < 20.0:
		return false   # (a dead end straight ahead: somewhere else)
	c.v = c.vmax[0] * 0.7
	c.want = -1.0
	# (a car is a pooled object: what it was doing in its last life goes too -- its
	# acceleration above all, eased towards the new want: a filmed walk's car sent in the
	# middle of its last life's hard stop braked from 9 to 3 m/s over its first 2 s)
	c.acc = 0.0
	c.braking = 0.0
	c.react_t = 0.0
	c.still = 0.0
	c.blocker = -2
	c.holding = false
	c.sign_done = -1
	c.sign_wait = 0.0
	c.wait = 0.0
	c.hit = 0.0
	c.ignore = 0.0
	c.squeeze = 0.0
	c.rear = Vector2.INF   # (placed afresh: its back on the lane behind it)
	_place(c)
	c.prev_pos = c.pos
	c.prev_yaw = c.yaw
	c.prev_y = c.y
	return true

## A car put on the road nearest `at` (within 25 m), heading the way `heading` points (a
## one-way street's own way whatever it says), at its road's pace: for a scripted moment, a
## filmed walk's cars. It is the car furthest from the player, out of sight as a rule.
## False when there is no road there. `opts`: "lane" "kerb" or "median" (the right-hand lane,
## or the one by the middle of the road, where it has two or more a way), "through" true (it
## drives on past the walk at a zebra, as one did in a film while the cars in the other lane
## waited), "kind" (one of that body if there is one), "paint" (white, silver, grey, black,
## blue, red: _car_paints' order, as details.gd's parked cars take it).
func send(at: Vector2, heading: Vector2, opts: Dictionary = {}) -> bool:
	var far: Car = null
	var fd := -1.0
	for pass_kind: bool in [true, false]:
		if far != null or (pass_kind and not opts.has("kind")):
			continue
		for c: Car in cars:
			if c.kind == "bus" or (pass_kind and c.kind != String(opts["kind"])):
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
	if far.alive and opts.has("lane"):
		var n := _lanes_dir(r)
		far.lane_i = 0 if String(opts["lane"]) == "kerb" else n - 1
		far.shift = _lane_shift(r, far.lane_i)
		far.shift_to = far.shift
		far.lane_t = 30.0   # (and keeps to it past the walk)
	far.film_through = bool(opts.get("through", false))
	if opts.has("paint"):
		var pal: Array = g._car_paints()
		var pi := int({"white": 0, "silver": 4, "grey": 7, "black": 9, "blue": 11, "red": 12}.get(String(opts["paint"]), -1))
		if pi >= 0:
			far.paint = pal[pi]
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
	if g._sig_set.has(node):
		# at a light the turn starts at the stop line, not behind it: a car waiting for the
		# green stands straight in its lane (at Begin x Kaplan the curve began 20 m out and
		# cars waiting to turn left stood angled across the next lane, overlapping its cars).
		# Only coming in from outside the junction: its inner points' "lines" are a few
		# metres off, and turns there tightened into the next point's red.
		var fit := -2.0
		var way_in: Array = []
		for way: Array in g._sig_line.get(node, []):
			if (way[0] as Vector2).dot(in_dir) > fit:
				fit = (way[0] as Vector2).dot(in_dir)
				way_in = way
		if fit > 0.7 and not bool(way_in[3]):
			back = minf(back, maxf(float(way_in[1]) - 0.5, 3.0))
	var ahead := minf(_node_r[node] + 1.0, cn.distance_to(p[from]) * 0.8)
	var E := cn - in_dir * back + rin * lane_in
	var X := cn + out_dir * ahead + rout * lane
	var K = Geometry2D.line_intersects_line(E, in_dir, X, -out_dir)
	var k2: Vector2 = K if K != null and (K as Vector2).distance_to(cn) < back + ahead + 4.0 else (E + X) * 0.5
	# The back trails a wheelbase behind the front (_place) and runs inside it round a turn,
	# by about wb^2 / 2R: a driver swings the front out by as much. On the tight
	# arc alone the back cut over the corner's kerb and whatever stood on it -- every car
	# turning at some corners went over the post there (the exam's checks, Givatayim).
	# Moving the curve's middle point by d moves the arc's middle by d/2.
	var wb := clampf(c.len * 0.6, 1.3, 7.0)
	var chord := (E + X) * 0.5
	var outward := k2 - chord
	var mid0 := (E + k2 * 2.0 + X) * 0.25
	var ab := E.distance_to(mid0)
	var bc := mid0.distance_to(X)
	var ca := X.distance_to(E)
	var area2 := absf((mid0 - E).cross(X - E))
	if outward.length() > 0.05 and area2 > 0.01:
		var R := ab * bc * ca / (2.0 * area2)
		# (wb^2 / 2R, the same for R well over wb, and still an answer on the tight turns
		# where a bus's 7 m wheelbase is more than the radius: those cut in most)
		k2 += outward.normalized() * minf(wb * wb / (2.0 * R), 1.5) * 2.0
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
			# nor into a pocket whose only ways out run off the map (see the game's _find_pockets)
			if g._trap.has((r2["ids"] as PackedInt32Array)[nxt]) and not g._trap.has(node):
				score -= 6.0
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
	# A vehicle steers by its front wheels and its back follows: the front axle runs on its
	# lane (shifted into the lane it is in, with its little drift), the rear axle trails it
	# a wheelbase behind, pulled along, never sliding sideways. The body was pointed along the
	# lane 2.2 m either side of its middle, the same for a car and a 12 m bus, so at every
	# corner it pivoted on its middle: a bus's back swung out across the lane, a car's nose
	# snapped round at each kink in its line -- "they jump around".
	var wb := clampf(c.len * 0.6, 1.3, 7.0)
	var wander := sin(_clock * 0.31 + c.drift) * 0.1 * clampf(c.v / 8.0, 0.0, 1.0)
	var off := c.shift + wander
	# (the front on the lane rounded over 4 m: the lane line has corners in it -- a bend in
	# the map's road -- and a front run exactly round each flicked the heading at 2.5 rad/s)
	var fa := _at(c, c.s + wb * 0.5 - 2.0)
	var fb := _at(c, c.s + wb * 0.5 + 2.0)
	var f0 := (fa + fb) * 0.5
	var td := fb - fa
	var ty := atan2(td.x, td.y) if td.length_squared() > 0.0001 else c.yaw
	var front := f0 + Vector2(cos(ty), -sin(ty)) * off   # (its lane: left of the line)
	if c.rear == Vector2.INF or c.rear.distance_to(front) > wb * 1.6:
		# placed afresh (a new start, sent elsewhere): its back on the lane behind
		var r0 := _at(c, c.s - wb * 0.5)
		var rd := f0 - r0
		var ry := atan2(rd.x, rd.y) if rd.length_squared() > 0.0001 else ty
		c.rear = r0 + Vector2(cos(ry), -sin(ry)) * off
	else:
		c.rear = front + (c.rear - front).normalized() * wb
	var d := front - c.rear
	c.pos = (front + c.rear) * 0.5
	c.y = g._decks.surf(c.pos, c.y)
	c.lift = c.y - float(g._h(c.pos))
	if d.length_squared() > 0.01:
		c.yaw = atan2(d.x, d.y)
		# the front wheels point along the lane the front runs on; the body trails them
		c.steer_to = clampf(angle_difference(c.yaw, ty), -0.5, 0.5)
		if g._hnx > 0:
			c.pitch = atan2(float(g._decks.surf(front, c.y)) - float(g._decks.surf(c.rear, c.y)), d.length())

func _in_view(p: Vector2) -> bool:
	var look := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
	var to: Vector2 = p - g._pos
	return to.length() < 200.0 and to.normalized().dot(look) > 0.3

## ---- every drawn frame --------------------------------------------------------------------

func draw(f: float) -> void:
	var door_on := false
	for i in range(cars.size()):
		var c: Car = cars[i]
		if not c.alive:
			continue
		var p := c.prev_pos.lerp(c.pos, f)
		var yaw := lerp_angle(c.prev_yaw, c.yaw, f)
		# (the slope it is on, the nose dipping or lifting, the lean in a turn)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -c.pitch + c.dip) * Basis(Vector3.BACK, c.roll)
		var xf := Transform3D(basis, Vector3(p.x, lerpf(c.prev_y, c.y, f) + float(g.road_top()), p.y))
		var mm: MultiMesh = _mms[c.kind]
		mm.set_instance_transform(i, xf)
		var lit := c.blink != 0 and fmod(_clock + float(i) * 0.13, 0.7) < 0.36
		mm.set_instance_custom_data(i, _custom(c, lit))
		if c.door > 0.0:   # the kerb car's open door, on its hinge at the front of the doorway
			door_on = true
			if _door.multimesh.mesh != g._door_mesh(c.kind):
				_door.multimesh.mesh = g._door_mesh(c.kind)
			_door.multimesh.set_instance_custom_data(i, Color(c.paint, 32.0))
			var dc: Vector2 = g._door_at(c.kind)
			_door.multimesh.set_instance_transform(i, xf * Transform3D(Basis(Vector3.UP, c.door * 1.0), Vector3(-dc.x, 0.0, dc.y)))
			_door_i = i
		elif i == _door_i:
			_door.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
			_door_i = -1
		if _night:
			_beams.multimesh.set_instance_transform(i, xf)
		if _blobs.visible:
			var cs: Vector2 = CORNERS.get(c.kind, Vector2(0.9, 2.25))
			_blobs.multimesh.set_instance_transform(i, xf * Transform3D(Basis.from_scale(Vector3(cs.x * 2.0 + 0.8, 1.0, cs.y * 2.0 + 1.0)), Vector3(0, 0.02, 0)))
	_door.visible = door_on

## a car's instance data for the car shader (CAR_SHADER's notes): its paint, each channel
## carrying a small whole number -- r the indicators lit (1 its left, 2 its right, 3 both), g
## and b the front wheels' steer in 64 steps -- and in alpha the brake light, 2 for each person
## aboard, 8 reversing, 16 the passenger's door open, 32 stood at the kerb
func _custom(c: Car, lit: bool) -> Color:
	var bl := 0
	if lit:
		bl = 3 if c.blink == 2 else (1 if c.blink < 0 else 2)
	var sq := clampi(int(round(c.steer / 0.016)) + 32, 1, 63)
	var flags := (1 if c.rev_t > 0.0 else 0) + (2 if c.door > 0.0 else 0) + (4 if c.stood else 0)
	return Color(c.paint.r + 2.0 * bl, c.paint.g + 2.0 * float(sq / 8), c.paint.b + 2.0 * float(sq % 8),
		minf(c.braking, 0.95) + (4.0 if c.passenger else 2.0) + 8.0 * flags)

func _hide_or_show(i: int) -> void:
	var c: Car = cars[i]
	if not c.alive:
		(_mms[c.kind] as MultiMesh).set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
		if _beams != null:
			_beams.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))
		if _blobs != null:
			_blobs.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))

## ---- the player's car against them --------------------------------------------------------

## how far to move a circle at `p` (radius r) to be clear of every car: each is two
## circles along its length, like a parked car
func push(p: Vector2, r: float, y := NAN) -> Vector2:
	var out := Vector2.ZERO
	for i in range(cars.size()):
		var c: Car = cars[i]
		if not c.alive or c.pos.distance_squared_to(p) > (100.0 if c.kind == "bus" else 64.0):
			continue
		if not is_nan(y) and absf(c.y - y) > LEVEL:
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

## two things this much apart in height are on different levels (a bridge and the street under
## it, a tunnel and the hill over it) and do not meet -- unless each is as high above the ground
## under it as the other (`lift`): both on the street, a hill between them. By height alone a
## car coming down a slope to a junction was 3-4 m above the player standing in it 50 m on,
## and passed over it as if on a bridge.
const LEVEL := 2.5

func _level(c: Car, y: float, lift: float) -> bool:
	return absf(c.y - y) <= LEVEL or absf(c.lift - lift) <= LEVEL

func bumped(i: int) -> void:
	if i >= 0 and i < cars.size():
		var c: Car = cars[i]
		c.hit = 2.5
		c.v = minf(c.v, 1.0)
