extends RefCounted
## Racer mode: "thief or racer mode, where the autodrive doesn't care about traffic". The
## "racer" button (or key R) puts autodrive on with the rules off: through red lights and
## stop signs, never giving way, at the speed the car can
## take the bends rather than the limit, round any slower car (over the centre line when
## nothing is coming). It still stops for people on a zebra and brakes for a person in its
## lane -- a driver who does not care about traffic, not one who runs people down. The town goes on as before: traffic always
## lets the player go (it stands on its brakes), and now a car that has to brake hard for
## you, or finds you coming at it in its lane, sounds its horn where it is.
##
## streets.gd's _autodrive asks `on` to leave out the lights, signs and giving way,
## and to raise the limit and the corners; _ap_pass_bus asks `can_pass` to go round moving
## cars too. Here: the horns, and the count of what it got away with.

const LIMIT_K := 1.8          ## the road's limit times this...
const TOP := 110.0 / 3.6      ## ...up to this (m/s)
const CORNER_K := 1.3         ## bends taken this much faster (sideways pull x1.7: tyres near their grip)...
const CORNER_FROM := 7.0      ## ...those the plan takes at this or more (m/s); tight turns as usual
const PASS_SLOWER := 2.0      ## a car this much slower than it wants to go (m/s) is gone round
const HOOT_BRAKE := -3.0      ## a car braking harder than this (m/s^2) with the player its blocker hoots
const HOOT_NEAR := 45.0       ## only cars this close hoot (m)
const HOOT_COOL := 6.0        ## seconds before the same car hoots again
const HOOTS_AT_ONCE := 3

var g: Node
var on := false
var reds := 0                 ## red lights run since it was switched on (the HUD shows it)
var hoots := 0
var passes := 0               ## cars gone round (either side), and queues gone round on the pavement
var mounts := 0
var _cool := {}               ## car instance id -> seconds until it may hoot again
var _horns: Array = []        ## AudioStreamPlayer3D pool
var _horn_left: Array = []    ## seconds left of each one's hoot
var _reds_was := 0
var _scan_t := 0.0

func _init(game: Node) -> void:
	g = game

func set_on(v: bool) -> void:
	on = v
	if on:
		reds = 0
		_reds_was = g._reds

## the limit it drives to, from the road's
func limit(lim: float) -> float:
	return minf(lim * LIMIT_K, TOP) if lim > 0.0 else lim

## a car ahead it would go round rather than follow
func can_pass(car_v: float, want_v: float) -> bool:
	return on and car_v < want_v - PASS_SLOWER

func tick(dt: float) -> void:
	for i in range(_horns.size()):
		if float(_horn_left[i]) > 0.0:
			_horn_left[i] = float(_horn_left[i]) - dt
			if float(_horn_left[i]) <= 0.0:
				(_horns[i] as AudioStreamPlayer3D).stop()
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - dt
		if float(_cool[k]) <= 0.0:
			_cool.erase(k)
	if not on or g._traffic == null:
		return
	if g._reds > _reds_was:
		reds += g._reds - _reds_was
		_reds_was = g._reds
		Probe.event("racer_red", {"reds": reds})
		_hoot_nearest(30.0)   # (someone across always has something to say about it)
	_scan_t -= dt
	if _scan_t > 0.0:
		return
	_scan_t = 0.2
	var me: Vector2 = g._pos
	var fwd: Vector2 = g._fwd()
	for c in g._traffic.cars:
		if not c.alive or _cool.has(c.get_instance_id()):
			continue
		var rel: Vector2 = me - c.pos
		var d := rel.length()
		if d > HOOT_NEAR:
			continue
		var cdir := Vector2(sin(c.yaw), cos(c.yaw))
		# stood on its brakes for you
		var braking: bool = c.blocker == -1 and c.acc < HOOT_BRAKE and c.v > 1.0
		# you, coming at it in its own lane: ahead of it, facing it, close to its line
		var head_on: bool = d < 30.0 and rel.dot(cdir) > 0.0 and fwd.dot(cdir) < -0.7 \
				and absf(rel.dot(Vector2(cdir.y, -cdir.x))) < 1.6 and g._v > 4.0
		if braking or head_on:
			_hoot(c, 0.9 if head_on else 0.5)

func _hoot_nearest(reach: float) -> void:
	var best = null
	var bd := reach
	for c in g._traffic.cars:
		if c.alive and not _cool.has(c.get_instance_id()):
			var d: float = (c.pos as Vector2).distance_to(g._pos)
			if d < bd:
				bd = d
				best = c
	if best != null:
		_hoot(best, 0.7)

func _hoot(c, secs: float) -> void:
	_cool[c.get_instance_id()] = HOOT_COOL
	var i := _free_horn()
	if i < 0:
		return
	var h: AudioStreamPlayer3D = _horns[i]
	var y: float = g._h(c.pos) + 1.0
	h.position = Vector3(c.pos.x, y, c.pos.y)
	# each car its own horn: a little higher or lower, and a long blast or two short ones
	var seed := absi(c.get_instance_id()) % 7
	h.pitch_scale = 0.82 + 0.06 * seed
	h.volume_db = linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8)))) - 2.0
	_horn_left[i] = secs
	hoots += 1
	if not Audio.muted():
		h.play()
	Probe.event("hoot", {"kind": c.kind, "hoots": hoots})

func _free_horn() -> int:
	if _horns.is_empty():
		if g._snd_horn == null:
			return -1
		for i in range(HOOTS_AT_ONCE):
			var h := AudioStreamPlayer3D.new()
			h.stream = g._snd_horn.stream
			h.unit_size = 12.0
			h.max_distance = 160.0
			g.world.add_child(h)
			_horns.append(h)
			_horn_left.append(0.0)
	for i in range(_horns.size()):
		if float(_horn_left[i]) <= 0.0:
			return i
	return -1
