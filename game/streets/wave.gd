extends RefCounted
## The green wave: "any crossroads i approach switches to green for my car". A switch (the
## "wave" button, key V) for the player's car, driving or on autodrive: the junction with
## lights it comes up to runs its own clock for a while instead of the city's one, and that
## clock goes the quickest proper way to green for the car's way -- the cross street's green
## ends as usual (flashing, amber, red all round, red-and-amber for you), so its traffic and
## its people stop as they would -- then holds there until the car is through. Afterwards the
## junction runs its own cycle, cutting its greens short, until it shows what the city's
## clock shows, and goes back to it.
##
## Everything that reads a light (traffic, autodrive, people at crossings, the red-run count)
## reads it through streets.gd's _ph_at / _t_at, which ask here first. The lamps are one
## multimesh per group and colour across the whole city, so a junction on its own clock gets
## its own lamps drawn over the shared ones, a touch bigger (they hide them), for as long as
## it is on it.

const REACH_MIN := 150.0      ## a junction this far ahead is asked for green...
const REACH_S := 14.0         ## ...or as far as this many seconds at the car's speed (the cross street's green ends, then 9.5 s of change)
const REACH_MAX := 260.0
const AHEAD_COS := 0.77       ## within ~40 degrees of where the car faces
const MIN_CROSS_GREEN := 4.0  ## the cross street keeps its green at least this long once it got it
const RELEASE_GREEN := 6.0    ## let go: its green ends after this, and it waits at red all round for the city's clock
const RELEASE_MAX := 90.0     ## ...and it rejoins the city's clock after this whatever (seconds)
const PICK_EVERY := 0.2       ## seconds between looks for the junction ahead

var g: Node
var on := false
var ovr := {}                 ## site -> {ph, t, hold, grp, rel (seconds let go, -1 held), node, n_lamps, key}
var targets := {}             ## site -> group: the sites being held green for the car
var _lamps := {}              ## site -> [[kind ("car" / "walk"), group 0/1, colour, Vector3], ...]
var _pick_t := 0.0
var count := {}               ## for tests: asked, held, back in step, forced back

func _init(game: Node) -> void:
	g = game

## a lamp put up at `site` (streets.gd's _build_signals and _build_walk_lights)
func lamp(site: int, kind: String, grp: int, col: int, at: Vector3) -> void:
	if site < 0:
		return
	if not _lamps.has(site):
		_lamps[site] = []
	(_lamps[site] as Array).append([kind, grp, col, at])

func phase(site: int) -> int:
	return int(ovr[site]["ph"]) if ovr.has(site) else g._sig_phase

func time(site: int) -> float:
	return float(ovr[site]["t"]) if ovr.has(site) else g._sig_t

## held green for the car: its green does not end while it is held
func held(site: int, grp: int) -> bool:
	if not ovr.has(site):
		return false
	var o: Dictionary = ovr[site]
	return bool(o["hold"]) and int(o["grp"]) == grp \
			and String(g.SIGNAL_CYCLE[int(o["ph"])][grp]) == "g"

func set_on(v: bool) -> void:
	on = v
	if not on:
		_let_go()

func tick(dt: float) -> void:
	if g._sites.is_empty():
		return
	_pick_t -= dt
	if _pick_t <= 0.0:
		_pick_t = PICK_EVERY
		_pick()
	var cyc: Array = g.SIGNAL_CYCLE
	for s: int in ovr.keys():
		var o: Dictionary = ovr[s]
		var grp := int(o["grp"])
		var step: Array = cyc[int(o["ph"])]
		var mine := String(step[grp])
		var theirs := String(step[3 - grp])
		if bool(o["hold"]):
			if mine == "g":
				o["t"] = minf(float(o["t"]) + dt, float(step[0]) * 0.5)   # (held: its green never runs out)
			elif mine == "gf":
				_jump(o, grp, "g", "r")   # its green was ending: back to the steady green
			elif theirs == "g" and float(o["t"]) >= MIN_CROSS_GREEN:
				_next(o)   # the cross street's green ends now (flashing, amber, red...)
			elif mine == "r" and theirs == "r" and float(o["t"]) + dt >= float(step[0]):
				# red all round (after either way's amber): on to the car's way next, the
				# cross street not given a green it would only lose at once
				if not _jump(o, grp, "ry", "r"):
					_jump(o, grp, "g", "r")
			else:
				_run(o, dt)
		else:
			o["rel"] = float(o["rel"]) + dt
			var gs: Array = cyc[g._sig_phase]
			if (String(step[1]) == String(gs[1]) and String(step[2]) == String(gs[2])) or float(o["rel"]) > RELEASE_MAX:
				count["back" if float(o["rel"]) <= RELEASE_MAX else "forced"] = int(count.get("back" if float(o["rel"]) <= RELEASE_MAX else "forced", 0)) + 1
				_drop(s)
				continue
			if (String(step[1]) == "g" or String(step[2]) == "g") and float(o["t"]) >= RELEASE_GREEN:
				_next(o)   # its green ends (flashing, amber, red all round)
			elif theirs == "r" and mine == "r" and float(o["t"]) + dt >= float(step[0]):
				# red all round, done: on into the city's clock -- its red-and-amber where
				# the city's has it, the red-and-amber for the way the city has on green, or
				# waiting here at red while the city's is in its own change (back in step
				# within a cycle: cutting greens to catch up took minutes)
				o["t"] = float(step[0]) - dt
				for c in [1, 2]:
					var gc := String(gs[c])
					if gc == "ry":
						o["ph"] = g._sig_phase
						o["t"] = g._sig_t
						break
					if gc == "g":
						if not _jump(o, c, "ry", "r"):
							o["ph"] = g._sig_phase   # (no red-and-amber here: straight to green, as the city's)
							o["t"] = g._sig_t
						break
			else:
				_run(o, dt)
		_show(s)

## the sites ahead of the car held green its way (all of them within reach: two junctions
## 80 m apart each need their 9.5 s of change before the car is there); the ones held before
## and not ahead now let go
func _pick() -> void:
	var now := {}   # site -> group
	if on and not g._walking:
		var fwd: Vector2 = g._fwd()
		var pos: Vector2 = g._pos
		var reach := clampf(maxf(REACH_MIN, absf(g._v) * REACH_S), REACH_MIN, REACH_MAX)
		for s in range(g._sites.size()):
			var site: Dictionary = g._sites[s]
			var d: Vector2 = (site["c"] as Vector2) - pos
			var dist := d.length()
			if dist > reach:
				continue
			# ahead; or one held already, while the car is still in it
			var ahead := dist > 1.0 and d.dot(fwd) / dist > AHEAD_COS
			if not ahead and not (targets.has(s) and dist < 35.0 and d.dot(fwd) > -12.0):
				continue
			var n: int = (site["nodes"] as Array)[0]
			now[s] = g._light_group(n, fwd)
	for s: int in targets:
		if not now.has(s) and ovr.has(s):
			ovr[s]["hold"] = false   # through (or turned away): let go
			ovr[s]["rel"] = 0.0
	targets = now
	for s: int in now:
		var grp: int = now[s]
		if not ovr.has(s):
			ovr[s] = {"ph": g._sig_phase, "t": g._sig_t, "hold": true, "grp": grp, "rel": -1.0, "node": null, "n_lamps": 0, "key": ""}
			count["asked"] = int(count.get("asked", 0)) + 1
			Probe.event("green_wave", {"site": s, "light": String(g.SIGNAL_CYCLE[g._sig_phase][grp])})
		else:
			var o: Dictionary = ovr[s]
			if not bool(o["hold"]):
				o["rel"] = -1.0
			o["hold"] = true
			o["grp"] = grp   # (the way the car comes in can change: it turned onto another way in)

func _run(o: Dictionary, dt: float) -> void:
	var cyc: Array = g.SIGNAL_CYCLE
	o["t"] = float(o["t"]) + dt
	if float(o["t"]) >= float(cyc[int(o["ph"])][0]):
		_next(o)

func _next(o: Dictionary) -> void:
	o["ph"] = (int(o["ph"]) + 1) % g.SIGNAL_CYCLE.size()
	o["t"] = 0.0

## to the step where group `grp` shows `mine` and the other `theirs`
func _jump(o: Dictionary, grp: int, mine: String, theirs: String) -> bool:
	var cyc: Array = g.SIGNAL_CYCLE
	for k in range(cyc.size()):
		if String(cyc[k][grp]) == mine and String(cyc[k][3 - grp]) == theirs:
			o["ph"] = k
			o["t"] = 0.0
			return true
	return false

func _let_go() -> void:
	for s: int in targets:
		if ovr.has(s):
			ovr[s]["hold"] = false
			ovr[s]["rel"] = 0.0
	targets = {}

func _drop(s: int) -> void:
	var o: Dictionary = ovr[s]
	if o["node"] != null and is_instance_valid(o["node"]):
		(o["node"] as Node).queue_free()
	ovr.erase(s)

## ---- its own lamps -----------------------------------------------------------------------
func _show(s: int) -> void:
	var o: Dictionary = ovr[s]
	var lamps: Array = _lamps.get(s, [])
	if lamps.is_empty():
		return   # (its square is not built yet: nothing to draw)
	if o["node"] == null or int(o["n_lamps"]) != lamps.size():
		_make_lamps(s, o, lamps)
	var step: Array = g.SIGNAL_CYCLE[int(o["ph"])]
	var blink := fmod(float(o["t"]), 1.0) < 0.5
	var key := "%s%s%s" % [step[1], step[2], blink]
	if key == String(o["key"]):
		return
	o["key"] = key
	var cols: Array = g._signal_cols()
	var mats: Array = o["mats"]
	for gg in range(2):
		var st := String(step[1 + gg])
		var lit := [st == "r" or st == "ry", st == "y" or st == "ry", st == "g" or (st == "gf" and blink)]
		for ci in range(3):
			g._light_lamp(mats[gg][ci], cols[ci], lit[ci])
		var walk := st == "r" and String(step[2 - gg]) == "g"
		g._light_lamp(mats[2 + gg][0], cols[0], not walk)
		g._light_lamp(mats[2 + gg][1], cols[2], walk)

func _make_lamps(s: int, o: Dictionary, lamps: Array) -> void:
	if o["node"] != null and is_instance_valid(o["node"]):
		(o["node"] as Node).queue_free()
	var root := Node3D.new()
	root.name = "wave_%d" % s
	g.world.add_child(root)
	var mats: Array = []
	for i in range(4):
		var row: Array = []
		for c in range(3 if i < 2 else 2):
			row.append(StandardMaterial3D.new())
		mats.append(row)
	var car_bulb := SphereMesh.new()   # (a little bigger than the shared ones, 0.11 and 0.08: it hides them)
	car_bulb.radius = 0.125
	car_bulb.height = 0.25
	car_bulb.radial_segments = 8
	car_bulb.rings = 3
	var walk_bulb := SphereMesh.new()
	walk_bulb.radius = 0.095
	walk_bulb.height = 0.19
	walk_bulb.radial_segments = 8
	walk_bulb.rings = 3
	for l: Array in lamps:
		var mi := MeshInstance3D.new()
		var car := String(l[0]) == "car"
		mi.mesh = car_bulb if car else walk_bulb
		mi.material_override = mats[(0 if car else 2) + int(l[1])][int(l[2])]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = l[3]
		root.add_child(mi)
	o["node"] = root
	o["mats"] = mats
	o["n_lamps"] = lamps.size()
	o["key"] = ""
