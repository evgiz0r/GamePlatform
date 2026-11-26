extends RefCounted
## The sounds of driving (moved out of streets.gd; `g` is the game).
## Loops made by sounds/make_sounds.py (it says why each is what it is), played at a pitch
## and a volume set here every frame: the engine at the revs a simple automatic gearbox gives
## (the loop is the engine at 1200 rpm), louder and brighter under load; the tyres' roar and
## the wind with the speed; the nearest car going by as its tyres' whoosh, its pitch falling as
## it passes; the city far off, always. A looping clip with its pitch changed is cheap and
## smooth in a browser, where pushing generated audio every frame stutters whenever a frame
## is late. (The engine used to be made here at load: a buzz of sharp pulses almost all
## below 200 Hz, the only sound there was, and a laptop's speaker turned it into a rough
## flutter that players switched off.)

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game


const SND_DIR := "res://game/streets/sounds/"
const IDLE_RPM := 800.0
const GEAR_RPM := [420.0, 240.0, 165.0, 122.0, 96.0]   ## rpm per m/s, first to fifth
const SND_LOOPS := ["engine", "engine_load", "road", "wind", "road", "city"]
var _engine: Array = []              ## players: SND_LOOPS, the second "road" the car going by
var _rpm := IDLE_RPM
var _gear_n := 1
var _load := 0.0
var _by_id := 0                      ## the car going by, and how fast it closes on you
var _by_d := INF
var _by_closing := 0.0

func _build_engine() -> void:
	for name: String in SND_LOOPS:
		var p := AudioStreamPlayer.new()
		p.stream = load(SND_DIR + name + ".wav")
		p.volume_db = -80.0
		g.add_child(p)
		_engine.append(p)

func _engine_tick(dt: float) -> void:
	if _engine.is_empty():
		return
	var off := Audio.muted() or g.finished or g._paused
	_street_snd_tick(dt, off)
	if g._rails != null:
		g._rails.sound(off)
	for i in range(_engine.size()):
		var p: AudioStreamPlayer = _engine[i]
		if off and p.playing:
			p.stop()
		elif not off and not p.playing:
			p.play(1.5 if i == 4 else 0.0)   # (the car going by: its own stretch of road)
	if off:
		return
	# the gearbox: up a gear sooner on a light foot, later with it down; down below 1250
	var v := 0.0 if g._walking else absf(g._v)   # on foot: the car idles where it was left
	if g._gear > 0:
		var up_at := 2000.0 + 1700.0 * g._throttle_in
		if v * float(GEAR_RPM[_gear_n - 1]) > up_at and _gear_n < GEAR_RPM.size():
			_gear_n += 1
		elif v * float(GEAR_RPM[_gear_n - 1]) < 1250.0 and _gear_n > 1:
			_gear_n -= 1
	else:
		_gear_n = 1
	var want := maxf(IDLE_RPM, v * float(GEAR_RPM[_gear_n - 1]))
	if v < 1.5:   # pulling away: the clutch lets the revs rise with the pedal
		want = maxf(want, IDLE_RPM + 1500.0 * g._throttle_in)
	_rpm = lerpf(_rpm, want, 1.0 - exp(-dt * 7.0))
	_load = lerpf(_load, g._throttle_in, 1.0 - exp(-dt * 6.0))
	var base := linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8))))
	var pitch := clampf(_rpm / 1200.0, 0.3, 4.0)
	var rev := clampf((_rpm - IDLE_RPM) / 3500.0, 0.0, 1.0)
	var eng: AudioStreamPlayer = _engine[0]
	var load: AudioStreamPlayer = _engine[1]
	var road: AudioStreamPlayer = _engine[2]
	var wind: AudioStreamPlayer = _engine[3]
	var by: AudioStreamPlayer = _engine[4]
	var city: AudioStreamPlayer = _engine[5]
	eng.pitch_scale = pitch
	load.pitch_scale = pitch
	eng.volume_db = base - 17.0 + 7.0 * rev
	load.volume_db = base - 38.0 + 26.0 * sqrt(_load)
	# the tyres' roar and the wind: what speed sounds like (+8 dB a doubling, and brighter;
	# the wind only at speed, +12 dB a doubling)
	var sp := clampf(v / 14.0, 0.02, 3.0)
	road.pitch_scale = 0.8 + 0.3 * clampf(v / 20.0, 0.0, 1.5)
	road.volume_db = base - 8.0 + 26.0 * log(sp) / log(10.0) if v > 0.2 else -80.0
	wind.volume_db = base - 23.0 + 40.0 * log(maxf(sp, 0.05)) / log(10.0) if v > 2.0 else -80.0
	if g._wet_k > 0.01 and v > 0.5:   # on a wet road the tyres hiss: brighter, and the spray's shh
		road.pitch_scale *= 1.0 + 0.25 * g._wet_k
		road.volume_db += 2.0 * g._wet_k
		wind.volume_db = maxf(wind.volume_db, base - 15.0 + 20.0 * log(sp * g._wet_k) / log(10.0))
	city.volume_db = base - (16.0 if g._walking else 19.0)
	if g._walking:   # idling behind you, quieter the further you walk
		eng.volume_db -= 4.0 + g._pos.distance_to(g._car_at) * 0.9
		load.volume_db = -80.0
	# the nearest car going by: its tyres, louder as it nears, the pitch falling as it passes
	# (how fast it closes on you, from its distance a frame ago)
	var near := INF
	var nv := 0.0
	var nid := 0
	if g._traffic != null:
		for c in g._traffic.cars:
			if c.alive and c.v > 1.0:
				var d: float = c.pos.distance_to(g._pos)
				if d < near:
					near = d
					nv = c.v
					nid = c.get_instance_id() if c is Object else hash(c)
	if nid == _by_id and dt > 0.0 and near < INF and _by_d < INF:
		_by_closing = lerpf(_by_closing, (_by_d - near) / dt, 1.0 - exp(-dt * 8.0))
	elif nid != _by_id:
		_by_closing = 0.0
	_by_id = nid
	_by_d = near
	if near < 60.0:
		by.pitch_scale = clampf((0.85 + nv / 40.0) / (1.0 - clampf(_by_closing, -60.0, 60.0) / 343.0), 0.5, 2.5)
		by.volume_db = base - 7.0 - 24.0 * log(maxf(near, 3.0) / 3.0) / log(10.0)
	else:
		by.volume_db = -80.0

## ---- the sounds of the street ----------------------------------------------------------------
## What a walk down a Givatayim street sounds like besides the traffic, made by
## sounds/make_sounds.py: birds in the trees by day, crickets in the gardens at night,
## people talking at the cafe, shop or school you are passing, a dog barking a street or two
## away now and then. Worked out twice a second from where you are -- how many trees round
## you (a 40 m grid of the trees, counted as they are planted), the nearest place people talk -- and
## the hour; each eases to its level. In the car they are quieter (the glass, the engine),
## the more so the faster; on foot they are what you hear. The voices and the dog are where
## they come from (3D players: they pan as you turn); the birds and crickets are all round.
const SND_CELL := 40.0
const TALKY := ["restaurant", "cafe", "fast_food", "bar", "pub", "ice_cream", "school", "kindergarten", "community_centre"]
var _amb: Array = []                 ## the birds' and the crickets' loops
var _voices: AudioStreamPlayer3D     ## at the nearest cafe, shop or school
var _dog: AudioStreamPlayer3D        ## a street or two away, now and then
var _snd_trees := {}                 ## 40 m cell -> trees in it (counted as each square plants them)
var _snd_talky := {}                 ## 40 m cell -> places people talk at
var _amb_t := 0.0
var _amb_db := [-80.0, -80.0, -80.0] ## where the birds, crickets and voices are easing to (dB)
var _dog_t := 30.0
var _amb_rng := RandomNumberGenerator.new()

func _build_street_sounds() -> void:
	for name: String in ["birds", "crickets"]:
		var p := AudioStreamPlayer.new()
		p.stream = load(SND_DIR + name + ".wav")
		p.volume_db = -80.0
		g.add_child(p)
		_amb.append(p)
	_voices = AudioStreamPlayer3D.new()
	_voices.stream = load(SND_DIR + "voices.wav")
	_voices.volume_db = -80.0
	_voices.unit_size = 8.0
	_voices.max_distance = 80.0
	g.world.add_child(_voices)
	_dog = AudioStreamPlayer3D.new()
	_dog.stream = load(SND_DIR + "dog.wav")
	_dog.unit_size = 25.0
	_dog.max_distance = 220.0
	g.world.add_child(_dog)
	_amb_rng.seed = hash(g._city_name) + 11
	var k := 1.0 / float(g._city_data.get("scale", 10))
	for poi: Array in g._city_data.get("pois", []):
		var kind := String(poi[2])
		if kind in TALKY or kind.begins_with("shop:"):
			var at := Vector2(poi[0], poi[1]) * k
			var c := g._cell(at, SND_CELL)
			if not _snd_talky.has(c):
				_snd_talky[c] = []
			(_snd_talky[c] as Array).append(at)

func _street_snd_tick(dt: float, off: bool) -> void:
	if _amb.is_empty():
		return
	for p: AudioStreamPlayer in _amb:
		if off and p.playing:
			p.stop()
		elif not off and not p.playing:
			p.play(_amb_rng.randf_range(0.0, 3.0))
	if off:
		if _voices.playing:
			_voices.stop()
		if _dog.playing:
			_dog.stop()
		return
	if not _voices.playing:
		_voices.play()
	_amb_t -= dt
	if _amb_t <= 0.0:
		_amb_t = 0.5
		var base := linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8))))
		var v := 0.0 if g._walking else absf(g._v)
		var hush := 0.0 if g._walking else 7.0 + 9.0 * clampf(v / 14.0, 0.0, 1.0)   # (in the car: the glass, the engine)
		var c := g._cell(g._pos, SND_CELL)
		var trees := 0
		var near := INF
		var talk := Vector2.INF
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cc := c + Vector2i(dx, dz)
				trees += int(_snd_trees.get(cc, 0))
				for q: Vector2 in _snd_talky.get(cc, []):
					if q.distance_to(g._pos) < near:
						near = q.distance_to(g._pos)
						talk = q
		var green := clampf(float(trees) / 30.0, 0.0, 1.0)
		# birds by day where there are trees (a dawn-and-dusk chorus: louder in the evening)
		_amb_db[0] = (base - 25.0 + 9.0 * green + (2.0 if g._evening else 0.0) - hush) if (not g._night and trees > 0) else -80.0
		# crickets at night in the gardens, a few starting in the evening
		_amb_db[1] = (base - 26.0 + 6.0 * green - hush) if g._night else ((base - 34.0 - hush) if g._evening else -80.0)
		# people talking at the nearest place they would (fewer at night)
		if talk != Vector2.INF and near < 70.0:
			_voices.position = Vector3(talk.x, g._h(talk) + 1.4, talk.y)
			_amb_db[2] = base - 9.0 - hush * 0.8 - (5.0 if g._night else 0.0)
		else:
			_amb_db[2] = -80.0
		# a dog, a street or two away, now and then where people live
		_dog_t -= 0.5
		if _dog_t <= 0.0:
			_dog_t = _amb_rng.randf_range(35.0, 100.0)
			if g._liveliness(g._pos) > 0.15 and not _dog.playing:
				var d := Vector2.from_angle(_amb_rng.randf() * TAU) * _amb_rng.randf_range(45.0, 120.0)
				var at := g._pos + d
				_dog.position = Vector3(at.x, g._h(at) + 0.6, at.y)
				_dog.pitch_scale = _amb_rng.randf_range(0.85, 1.2)
				_dog.volume_db = base - 4.0 - hush
				_dog.play()
	for i in range(2):
		var p: AudioStreamPlayer = _amb[i]
		p.volume_db = move_toward(p.volume_db, _amb_db[i], dt * 10.0)
	_voices.volume_db = move_toward(_voices.volume_db, _amb_db[2], dt * 10.0)
