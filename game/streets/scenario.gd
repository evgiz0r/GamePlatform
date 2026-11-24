extends RefCounted
## Scenarios: a town plays out a script -- "a virtual tour in a city. like a guide, where we
## stop and look and explain" and "some scenario ( aka movie i guess ) happening in a city.
## doesnt have to be related to the city itself". One player for both: a script is a list of
## BEATS, each running until it is done --
##   ["say", text, secs]                 a caption across the lower third
##   ["drive", where, label, style]      autodrive there ("go to"), in an autodrive style
##   ["look", where, text, secs]         stop: the view up over `where`, turning round it, the
##                                       city held still, a caption; then back down to the car
##   ["chase", secs]                     the getaway (below) until lost, caught or out of time
##   ["drive_for", where, label, style, secs]  a drive that ends after secs (or there)
##   ["time", "day" | "evening" | "night"]     the time of day, now
##   ["wet", on]                         after rain, or dry
##   ["shots", [name, ...], secs]        the camera from now on: each shot in turn for secs --
##                                       "usual" (the game's own view), "above" (high over the
##                                       car), "kerb" (low at the roadside ahead as the car comes
##                                       by), "orbit" (round the car), "chaser" (behind the car
##                                       on your tail), "back" (ahead of the car looking back);
##                                       [] puts the game's view back
##   ["siren", on]                       the car's own siren and flashing lights; the traffic
##                                       ahead pulls aside and stops for it
##   ["end", text]                       the last caption; the city goes on, the drive is yours
## A level with "scenario" in LEVELS runs one -- "night_tour" (the tour after dark, ending in
## the rain), "ambulance" (a siren through town to the hospital), "day" (the town from morning
## to night in a few minutes, cutting between shots) -- or: "tour" (built from the town's own story,
## cities/stories/<town>.json: its named streets in an order that drives well, each one a stop
## with who it is named for; the neighbourhoods and history as the captions between) or
## "getaway" (a car with flashing lights on your tail, through the town in racer style: lose
## it). While a tour drives, a street with a story is explained as the car turns into it.
## It waits for the opening (opening.gd) to come down first. Any key or tap during a "look"
## goes on to the next beat; taking the wheel ends the script (the drive is yours).

const STOPS := 6              ## a tour's stops at most
const LOOK_S := 9.0           ## seconds a tour stops at each
const LOOK_Z := 0.34          ## how high the view goes over a stop
const DRIVE_MAX := 150.0      ## seconds to get to a stop before going on regardless
const CHASE_TOP := 17.0       ## the chaser's pace (m/s, 61 km/h): racer outruns it on open road, not through traffic and corners
const CHASE_START := 50.0     ## metres behind at the start
const CHASE_SPOT_S := 1.0     ## seconds before it speeds up ("they spot you")
const CHASE_ACC := 3.0        ## how fast it picks up speed (m/s^2)
const HOP := 900.0            ## a tour's next stop no further than this from the last, where it can
const CHASE_CAUGHT := 11.0    ## ...this close (and held, CHASE_HOLD) and you are caught; it tails at 10 (at 6 the usual view sat inside it)
const CHASE_LOST := 130.0     ## ...this far and you lost it
## The redo (24 Nov: the user, "All the scenarios are very weak"): each one now has a goal
## said on a title card, a live line saying how it is going, stakes (a clock, a chaser that
## gets faster), moments that answer what happened, and an end card with how it went, stars
## and the best so far.
const TITLE_S := 3.5          ## the title card's seconds
const GOALS := {
	"tour": "Six of the town's streets and who they are named for. Sit back.",
	"night_tour": "The town after dark. Sit back.",
	"getaway": "Lose the police car, or reach the safe house. Take the wheel any time.",
	"ambulance": "Get the patient to the hospital before the clock runs out. Take the wheel any time.",
	"day": "Morning to night in three minutes.",
	"dragons": "Look up.",
	"delivery": "Three pizzas, three real addresses. The faster, the bigger the tip. Take the wheel any time.",
	"wedding": "Lead the convoy to the hall before the ceremony starts. Everyone hoots.",
	"shabbat": "Friday, the hour before sunset: the town winds down. Sit back.",
	"gan": "Two kids, two kindergartens, one clock: both picked up and home before it runs out.",
	"taxi": "Pick up whoever waves you down, take them where they're going. Quick and in one piece pays. Take the wheel any time.",
}
const CHASE_EDGE := 1.0       ## m/s faster than you were at that point of your trail, at first...
const CHASE_EDGE2 := 2.6      ## ...and once backup has joined
const CHASE_RED_M := 10.0     ## metres a red light you run puts between you
var _trail_v := 0.0
const CHASE_RAMP := 3.5       ## m/s the chaser gains over its first minute ("backup joins")
const CHASE_GRACE := 30.0     ## no catch in the first seconds (Ashdod: autodrive stood 4 s for a person on a zebra at the first junction and was caught at 20 s, both runs)
const CHASE_HOLD := 3.5       ## seconds held (on your bumper, you near stopped) before it counts as caught: a touch is a close call
const CLOSE_IN := 18.0        ## the chaser within this...
const CLOSE_OUT := 28.0       ## ...and then back past this: a close call
const TOUR_SKIP_S := 30.0     ## a tour's drive longer than this, still far off: cut ahead to near the stop
const TOUR_SKIP_M := 160.0   ## (260: Arlosoroff, 200 m off by a one-way's long way round, took 138 s uncut)
const DROP_SKIP_S := 30.0     ## a drop's drive watched longer than this, still far: the cut
var skipped_s := 0.0          ## seconds of clock charged for cuts
const DROP_PACE := 6.0        ## m/s by road a drop's clock allows
const DROPS := 3              ## a delivery's addresses
const SCEN_BEST := "user://streets_scenarios.json"   ## the best of each scenario (not SaveData's: see streets.gd PREFS_PATH)

## how it is going, for the end card and the tests
var run_t := 0.0              ## seconds since the title card
var top_v := 0.0
var close_calls := 0
var closest := INF
var tips := 0
var drops_done := 0
var stars := 0
var skips := 0                ## a tour's cuts ahead
var _reds0 := 0
var _limit := 0.0             ## the ambulance's clock
var _late_said := false
var _close := false
var _hold_t := 0.0
var _backup_said := false
var _drop_t: Array = []       ## a delivery's drops: seconds each took
var _stop_names: Array = []   ## a tour's stops reached
var _title: Control = null
var _strip: Label = null
var _card: Control = null

var g: Node
var kind := ""
var on := false
var beats: Array = []
var i := -1
var t := 0.0
var story: Dictionary = {}
var shown: Array = []         ## for tests: every caption put up
var reached := 0              ## for tests: stops arrived at
var result := ""              ## "lost", "caught", "gave up", "done"
var _cap: Label
var _cap_t := 0.0
var _street_said := {}        ## streets explained on this drive already
var _last_street := ""

## the chase
var _chaser: Node3D
var _lights: Array = []       ## [red, blue] MeshInstance3D
var _siren: AudioStreamPlayer3D
var _trail: Array = []        ## [where, yaw, odometer] of the player, every 0.5 m
var _gap := CHASE_START       ## metres of the player's trail between the chaser and the car
var _vc := 0.0                ## the chaser's speed
var _cut_t := 0.0
var _back_cam: Camera3D = null   ## the chase's cut: looking back at the chaser

func _init(game: Node) -> void:
	g = game

## build the script for this level (called once the city is up)
func setup(id: String) -> void:
	kind = id
	story = _load_story()
	if id == "tour":
		beats = _tour_beats()
	elif id == "night_tour":
		beats = [["time", "night"]] + _tour_beats()
		beats[1][1] = "By night -- " + String(beats[1][1])
		beats.insert(beats.size() - 1, ["wet", true])
		beats.insert(beats.size() - 1, ["say", "And then the rain: the streets shining under the lamps.", 6.0])
	elif id == "getaway":
		beats = _getaway_beats()
	elif id == "ambulance":
		beats = _ambulance_beats()
	elif id == "day":
		beats = _day_beats()
	elif id == "dragons":
		beats = [["time", "evening"], ["dragons"],
			["end", "Dragons over %s. The streets will talk about nothing else." % String(story.get("town", g._city_name))]]
	elif id == "delivery":
		beats = _delivery_beats()
	elif id == "taxi":
		beats = _taxi_beats()
	elif id == "wedding":
		beats = _wedding_beats()
	elif id == "shabbat":
		beats = _shabbat_beats()
	elif id == "gan":
		beats = _gan_beats()
	# every one opens on its title card: what it is and what counts as winning it
	beats.insert(0, ["title", String(g._place.get("name", id)), String(GOALS.get(id, "")), TITLE_S])
	Probe.event("scenario", {"kind": id, "beats": beats.size()})

func start() -> void:
	on = true
	i = -1
	_reds0 = g._reds
	_next()

## ---- the scripts ----------------------------------------------------------------------------

## the town's named streets with a story, the nearest first from where the car is, then the
## nearest to that, STOPS of them; the captions between from the neighbourhoods and history
func _tour_beats() -> Array:
	var out: Array = []
	var streets: Dictionary = story.get("streets", {})
	var cands: Array = []   # [where, en name, text]
	for key: String in streets:
		var at := _street_mid(key)
		if at != Vector2.INF:
			cands.append([at, key, String(streets[key])])
	var town := String(story.get("town", g._city_name))
	out.append(["say", "A tour of %s -- %s" % [town, String(story.get("tagline", ""))], 4.0])
	var here: Vector2 = g._pos
	var extras: Array = []
	for n: Dictionary in story.get("neighbourhoods", []):
		extras.append("%s: %s" % [String(n.get("name", "")), String(n.get("mood", ""))])
	for h in story.get("history", []):
		extras.append(String(h))
	var k := 0
	while not cands.is_empty() and k < STOPS:
		# the nearest stop that is not right here; a hop of HOP at most where there is one
		var bi := 0
		var bd := INF
		for j in range(cands.size()):
			var d := (cands[j][0] as Vector2).distance_to(here)
			if d < bd and d > 60.0:
				bd = d
				bi = j
		if bd > HOP and k > 0:
			break   # (the rest are far off: the tour ends here rather than cross town)
		var c: Array = cands[bi]
		cands.remove_at(bi)
		if bd == INF:
			continue
		if k > 0 and k - 1 < extras.size():
			out.append(["say", String(extras[k - 1]), 5.0])
		out.append(["drive", c[0], String(c[1]), "wave"])   # (the lights turn green for the tour)
		out.append(["look", c[0], "%s -- %s" % [String(c[1]), String(c[2])], LOOK_S])
		here = c[0]
		k += 1
	out.append(["end", "That was %s. The streets are yours -- drive on, or pick another tour." % town])
	return out

## somewhere 1.2-2 km off on a main street, autodrive there in racer style, the chaser behind,
## filmed: the camera cutting between the usual view, from behind the chaser, from above, at the
## kerb and looking back; slow motion through each red light it runs
func _getaway_beats() -> Array:
	var goal := _far_main_street(800.0, 1300.0)   # (1.2-2 km was 2.5 km by road: a chase that long only ever ended caught)
	return [["say", "The getaway. They're right behind you -- lose them.", 3.0],
		["shots", ["usual", "chaser", "above", "kerb", "back", "usual", "orbit"], 5.0],
		["drive_on", goal, "the safe house", "racer"],
		["chase", 150.0],
		["shots", [], 0.0],
		["end", ""]]

## the hospital (a street the story says it is on; else a main street 1-2 km off), siren on:
## the traffic ahead pulls aside, every light turns green, the racer's lines round the rest
func _ambulance_beats() -> Array:
	var goal := Vector2.INF
	var label := "the hospital"
	var streets: Dictionary = story.get("streets", {})
	for key: String in streets:
		if String(streets[key]).to_lower().contains("hospital"):
			goal = _street_mid(key)
			if goal != Vector2.INF:
				label = "the hospital, on %s" % key
				break
	if goal == Vector2.INF or goal.distance_to(g._pos) < 500.0:
		goal = _far_main_street(1000.0, 1800.0)
	# the clock: the way there at an ambulance's town pace (streets wind: 1.45 x the crow's
	# flight, at 12 m/s), and twenty seconds to spare
	var limit := roundf(goal.distance_to(g._pos) * 1.45 / 12.0 + 20.0)
	return [["say", "A call comes in. %d:%02d to get the patient to %s." % [int(limit) / 60, int(limit) % 60, label], 3.0],
		["timer", limit],
		["siren", true],
		["shots", ["usual", "kerb", "above", "orbit", "kerb", "usual"], 6.0],
		["drive_for", goal, label, "racer", limit + 90.0],
		["siren", false],
		["shots", [], 0.0],
		["end", "ambulance"]]

## the town from morning to night: a drive from one of its story's streets to the next at each
## time of day, the camera cutting between shots, the town's rhythm and lines between
func _day_beats() -> Array:
	var town := String(story.get("town", g._city_name))
	var stops: Array = []
	for b: Array in _tour_beats():
		if String(b[0]) == "drive":
			stops.append([b[1], b[2]])
	if stops.size() < 3:
		var far := _far_main_street(600.0, 1400.0)
		stops = [[far, "across town"], [g._pos, "back again"], [far, "across town"]]
	var rhythm := String(story.get("rhythm", "")).split(". ", false)
	var lines: Array = (story.get("lines", []) as Array).duplicate()
	var say := func(k: int) -> String:
		if k < rhythm.size():
			return String(rhythm[k]).trim_suffix(".") + "."
		return String(lines[k % maxi(lines.size(), 1)]) if not lines.is_empty() else ""
	# the hour on the line under the street, and the traffic the hour has: the rush full, the
	# evening thinner, the night nearly empty -- truer, and the quiet hours cost less to run
	return [["time", "day"], ["clock", 7 * 60 + 20, 4.0, "morning rush"],
		["say", "A day in %s." % town, 3.0],
		["shots", ["above", "kerb", "usual", "orbit", "kerb"], 6.0],
		["say", "Morning. " + String(say.call(0)), 5.0],
		["drive_for", stops[0][0], String(stops[0][1]), "rules", 55.0],
		["time", "evening"], ["clock", 18 * 60 + 30, 2.5, "evening"], ["quiet", 14],
		["say", "Evening. " + String(say.call(1)), 5.0],
		["drive_for", stops[1][0], String(stops[1][1]), "wave", 50.0],
		["time", "night"], ["clock", 23 * 60 + 10, 3.0, "night"], ["quiet", 5],
		["say", "Night. " + String(say.call(2)), 5.0],
		["drive_for", stops[2][0], String(stops[2][1]), "wave", 45.0],
		["wet", true], ["clock", 4 * 60 + 40, 1.5, "before dawn"], ["quiet", 2],
		["say", "Rain before dawn. The streets shine, and empty.", 6.0],
		["shots", ["above"], 8.0],
		["say", "%s." % String(story.get("tagline", town)), 5.0],
		["shots", [], 0.0],
		["end", "That was a day in %s." % town]]

## ---- running it ------------------------------------------------------------------------------

## for the test: any shot's camera (the director's, the chase's cut, the dragons') near the
## ground and inside a building -- a camera is a person or a mounted lens, never in a wall
var cam_in_building := 0
func _cam_check() -> void:
	var c: Camera3D = g.get_viewport().get_camera_3d() if g.view == null else g.view.get_camera_3d()
	if c == null or c == g.cam:
		return
	var p: Vector3 = c.global_position
	var p2 := Vector2(p.x, p.z)
	if p.y < g._h(p2) + 4.0 and g._push_out(p2, 0.15, false, false) != Vector2.ZERO:
		cam_in_building += 1
		if cam_in_building == 1:
			print("[scenario] camera inside a building at %s, beat %s, %.1f s" % [p2, beats[i][0] if i >= 0 and i < beats.size() else "-", t])

func tick(dt: float) -> void:
	_caption_tick(dt)
	if not on:
		return
	if g._opening != null and g._opening.on:
		return   # (its own opening first)
	if i < 0 or i >= beats.size():
		return
	t += dt
	if String(beats[i][0]) != "title":
		run_t += dt
		top_v = maxf(top_v, absf(float(g._v)))
	_strip_tick()
	_shots_tick(dt)
	_slowmo_tick()
	_cam_check()
	if _siren_on:
		_yield_tick()
	if not _convoy.is_empty():
		_convoy_tick(dt)
	if _clock_m >= 0.0:
		_clock_m = fmod(_clock_m + _clock_rate * dt, 1440.0)
	var b: Array = beats[i]
	match String(b[0]):
		"title":
			if t >= float(b[3]):
				_title_off()
				_next()
		"say":
			if t >= float(b[2]):
				_next()
		"deliver", "ride":
			_deliver_tick(b)
		"pickup":
			_pickup_tick(b, dt)
		"timer":
			_next()
		"drive_for":
			var there: bool = (not g._dest_on and t > 2.0) or (g._pos as Vector2).distance_to(b[1]) < 35.0
			if _limit > 0.0 and not _late_said and _limit - run_t <= 30.0:
				_late_said = true
				_say("30 seconds left -- hurry!" if _limit - run_t > 0.0 else "Late -- keep going!", 2.5)
				Audio.play("voice_hurry_up", 0.0, -6.0)
			if there or t >= float(b[4]):
				reached += 1 if there else 0
				if _limit > 0.0:
					var left := _limit - run_t
					stars = 3 if left >= _limit * 0.25 else (2 if left >= 0.0 else 1)
					if not there:
						stars = 0
				_next()
		"time", "wet", "shots", "siren", "convoy", "quiet", "clock":
			_next()
		"dragons":
			if _dragons.tick(dt, func(text: String, secs: float) -> void: _say(text, secs)):
				_next()
			else:
				_dragons.camera(dt)
		"drive":
			_street_words()
			var at: Vector2 = b[1]
			# there: at the stop, or at the kerb "go to" chose for it (it can only stop where a
			# street lets it -- Givatayim's tour gave up on two stops 150 s on, parked beside them)
			var by_kerb: bool = g._dest_on and (g._pos as Vector2).distance_to(g._dest_stop) < 20.0 and absf(g._v) < 2.0
			if (not g._dest_on and t > 2.0) or (g._pos as Vector2).distance_to(at) < 35.0 or by_kerb or t > DRIVE_MAX:
				var got: bool = ((g._pos as Vector2).distance_to(at) < 60.0 or by_kerb or not g._dest_on) and t <= DRIVE_MAX
				reached += 1 if got else 0
				if got:
					_stop_names.append(String(b[2]))
					Audio.play("pickup", 0.05, -10.0)
				g._set_auto(false)
				_next()
			elif t > TOUR_SKIP_S and _skip_i != i and (g._pos as Vector2).distance_to(at) > TOUR_SKIP_M:
				_skip_ahead(b)   # (no minute of driving between stops: a cut to the street, as a film does)
			elif not g._auto and t > 3.0:
				_finish("yours")   # (taken over by hand: the drive is yours)
		"drive_on":
			_next()   # (started; the chase beat after it runs while it drives)
		"look":
			g._zoom_yaw_to += 0.22 * dt
			if t >= float(b[3]):
				g._zoom_set(0.0)
				_next()
		"chase":
			_chase_tick(dt)
			if result != "" or t >= float(b[1]):
				if result == "":
					result = "gave up"
				_end_chase()
				_next()
		"end":
			pass

func _next() -> void:
	i += 1
	t = 0.0
	if i >= beats.size():
		_finish("done")
		return
	var b: Array = beats[i]
	match String(b[0]):
		"title":
			_title_on(String(b[1]), String(b[2]))
		"timer":
			_limit = float(b[1])
			run_t = 0.0
		"deliver", "ride":
			_deliver_start(b)
		"pickup":
			_pickup_start(b)
		"say":
			_say(String(b[1]), float(b[2]))
		"time":
			_set_time(String(b[1]))
		"wet":
			g._set_wet(bool(b[1]))
		"shots":
			_shots = b[1]
			_shot_len = float(b[2])
			_shot_i = -1
			_shot_t = 0.0
			if _shots.is_empty():
				_cam_usual()
		"siren":
			_set_siren(bool(b[1]))
		"convoy":
			_convoy_on(int(b[1]))
		"quiet":
			if g._traffic != null:
				g._traffic.set_cap(int(b[1]))
		"clock":
			_clock_m = float(b[1])
			_clock_rate = float(b[2])
			_clock_what = String(b[3])
		"dragons":
			g._set_auto(false)
			g._v = 0.0
			_dragons = Dragons.new(g)
			_dragons.start(g._pos, g._fwd())
		"drive_for":
			if g._zoomed():
				g._zoom_set(0.0)
			g._set_dest(b[1], String(b[2]))
			g._ap_style = String(b[3])
			g._apply_ap_style()
			if _siren_on and g._wave != null:
				g._wave.set_on(true)   # (an ambulance: racer's lines and every light green too)
			g._set_auto(true)
			_say("Next: %s" % String(b[2]), 2.5)
		"drive", "drive_on":
			if g._zoomed():
				g._zoom_set(0.0)
			if String(b[0]) == "drive":
				_street_said[String(b[2])] = true   # (the stop says it: not on the way in too)
			g._set_dest(b[1], String(b[2]))
			g._ap_style = String(b[3])
			g._apply_ap_style()
			g._set_auto(true)
			_say(("Next: %s" % String(b[2])) if String(b[0]) == "drive" else String(b[2]), 2.5)
		"look":
			g._zoom_set(LOOK_Z)
			g._zoom_off = (b[1] as Vector2) - (g._pos as Vector2)
			_say(String(b[2]), float(b[3]))
			Probe.event("scenario_look", {"at": Vector2i(b[1]), "what": String(b[2]).left(40)})
		"chase":
			_start_chase()
			Audio.play("voice_go", 0.0, -6.0)
		"end":
			var txt := String(b[1])
			if kind == "getaway":
				txt = {"lost": "You lost them. Nobody followed you home.", "caught": "Caught. They boxed you in.",
					"home": "The garage door comes down behind you. Safe.",
					"gave up": "They gave up the chase -- you got away."}.get(result, "")
				stars = {"lost": 3, "home": 2, "gave up": 2}.get(result, 1 if run_t > 60.0 else 0)
				if stars >= 2 and close_calls == 0 and result == "home":
					stars = 3   # (clean: never let them near)
			if kind == "ambulance":
				var left := _limit - run_t
				txt = ("At the hospital's door with %s to spare. The town goes on as if nothing happened." % _mmss(left)) if stars >= 2 \
					else ("At the hospital, %s late. They rush the stretcher in." % _mmss(-left) if stars == 1 else "Stuck. Another ambulance had to take over.")
			elif kind == "delivery":
				txt = "Shift over: %d of %d delivered, %d in tips." % [drops_done, DROPS, tips]
			elif kind == "wedding":
				var lw := _limit - run_t
				txt = ("The hall's lights, the music already playing, %s to spare. Mazal tov!" % _mmss(lw)) if stars >= 2 \
					else "They held the ceremony for you. Mazal tov -- just."
			elif kind == "gan":
				var lg := _limit - run_t
				txt = ("Home, both of them, with %s to spare. Snack time." % _mmss(lg)) if stars >= 2 \
					else "Home at last. Two tired kids and one tired parent."
			elif kind == "taxi":
				txt = "Light off. %d fares, %d on the meter and in tips." % [drops_done, tips]
			_say(txt, 6.0)
			_finish(result if result != "" else "done")

var _end_tick := -1

## ended `secs` of game time ago or more (the recorder stops there)
func done_for(secs: float) -> bool:
	return _end_tick >= 0 and Engine.get_physics_frames() - _end_tick >= int(secs * Engine.physics_ticks_per_second)

const Dragons := preload("res://game/streets/dragons.gd")
var _dragons = null           ## the dragons' scene (dragons.gd), while it plays

func _finish(how: String) -> void:
	on = false
	if _dragons != null and _dragons.on:
		_dragons.stop()
	if _end_tick < 0:
		_end_tick = Engine.get_physics_frames()
	_cam_usual()
	_set_siren(false)
	if _slow_until > 0:
		Engine.time_scale = 1.0
		_slow_until = 0
	if result == "":
		result = how
	if _chaser != null:
		_end_chase()
	_title_off()
	if _strip != null:
		_strip.visible = false
	if g._traffic != null and g._traffic.cap < g._traffic.COUNT:
		g._traffic.set_cap(g._traffic.COUNT)   # (the streets fill again)
	_convoy_off()
	_gan_crowd_off()
	if how != "yours":
		_end_card()
	Probe.event("scenario_end", {"kind": kind, "result": result, "reached": reached, "stars": stars,
		"secs": int(run_t), "close_calls": close_calls, "tips": tips, "skips": skips})

## ---- captions --------------------------------------------------------------------------------

func _say(text: String, secs: float) -> void:
	if text == "":
		return
	if _cap == null:
		_cap = Label.new()
		_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cap.add_theme_font_override("font", g._font)
		_cap.add_theme_font_size_override("font_size", 15)
		_cap.add_theme_color_override("font_color", Palette.col("ink"))
		_cap.add_theme_color_override("font_outline_color", Palette.col("bg"))
		_cap.add_theme_constant_override("outline_size", 7)
		_cap.position = Vector2(80, 262)
		_cap.set_meta("film", true)   # (kept on screen when filming)
		_cap.size = Vector2(480, 54)
		g._hud.add_child(_cap)
	_cap.text = text
	_cap_t = secs
	shown.append(text)

func _caption_tick(dt: float) -> void:
	if _cap == null:
		return
	_cap_t -= dt
	_cap.modulate.a = clampf(_cap_t / 0.5, 0.0, 1.0)

## a street with a story, explained as the car turns into it (once a drive)
func _street_words() -> void:
	var en := String(g._street_en_lbl.text) if g._street_en_lbl != null else ""
	if en == "" or en == _last_street:
		return
	_last_street = en
	var streets: Dictionary = story.get("streets", {})
	for key: String in streets:
		if not _street_said.has(key) and _same_street(key, en):
			_street_said[key] = true
			_say("%s -- %s" % [key, String(streets[key])], 5.0)
			return

## ---- finding places ------------------------------------------------------------------------

func _load_story() -> Dictionary:
	var path := "res://game/streets/cities/stories/%s.json" % String(g._city_id)
	var d = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is JSON:
			d = (res as JSON).data
	if d == null and FileAccess.file_exists(path):
		d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

static func _key(s: String) -> String:
	var n := s.to_lower()
	for pre in ["sderot ", "derekh ", "derech ", "rehov ", "street", "road", "boulevard", "avenue", "drive"]:
		n = n.replace(pre, "")
	return "".join(Array(n.split(" ", false))).replace("'", "").replace("-", "")

func _same_street(key: String, en: String) -> bool:
	var a := _key(key)
	var b := _key(en)
	return a != "" and b != "" and (a == b or (a.length() > 4 and b.contains(a)) or (b.length() > 4 and a.contains(b)))

## the middle of the longest piece of a street by its English name, inside the town
func _street_mid(key: String) -> Vector2:
	var best := Vector2.INF
	var bl := 0.0
	for r: Dictionary in g._roads:
		if not r["drive"] or r["pv"] or r.has("ys") or not _same_street(key, String(r["en"])):
			continue
		var pts: PackedVector2Array = r["pts"]
		var L := 0.0
		for j in range(pts.size() - 1):
			L += pts[j].distance_to(pts[j + 1])
		var mid := pts[pts.size() / 2]
		if L > bl and g._in_city(mid) and g._bounds.grow(-120.0).has_point(mid):
			var on: Dictionary = g._nearest_seg(mid, 25.0, true, true)   # (on a public street "go to" can end at)
			if on.is_empty():
				continue
			bl = L
			best = on["q"]
	return best

func _far_main_street(lo: float, hi: float) -> Vector2:
	var best := Vector2.INF
	var bd := -1.0
	for r: Dictionary in g._roads:
		if not r["drive"] or not (String(r["k"]) in ["primary", "secondary", "tertiary"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var mid := pts[pts.size() / 2]
		var d := mid.distance_to(g._pos)
		if d >= lo and d <= hi and g._bounds.grow(-150.0).has_point(mid) and d > bd:
			bd = d
			best = mid
	return best if best != Vector2.INF else (g._pos as Vector2) + Vector2(800, 0)

## ---- the getaway ----------------------------------------------------------------------------

func _start_chase() -> void:
	_trail = [[g._pos, g._yaw, 0.0, 0.0]]
	_gap = CHASE_START
	_vc = 9.0   # (already rolling: from a standstill it fell 100 m behind and the chase was "lost" in 16 s)
	_reds_seen = g._reds
	_reds0 = g._reds
	result = ""
	_chaser = _police_car()
	# the siren: two tones, rising and falling (made here, as the horn is)
	var rate := 22050
	var buf := PackedFloat32Array()
	buf.resize(rate * 2)
	var ph := 0.0
	for k in range(buf.size()):
		var s := float(k) / rate
		var f := 650.0 + 300.0 * (0.5 + 0.5 * sin(TAU * s * 0.5))
		ph += TAU * f / rate
		buf[k] = tanh(1.8 * sin(ph)) * 0.6
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = g._wav(buf, rate, true)
	_siren.unit_size = 14.0
	_siren.max_distance = 260.0
	_siren.volume_db = linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8)))) - 4.0
	_chaser.add_child(_siren)
	if not Audio.muted():
		_siren.play()
	Probe.event("chase", {"start": true})

func _chase_tick(dt: float) -> void:
	if _chaser == null:
		return
	# the player's trail, a point every half metre
	var last: Array = _trail[_trail.size() - 1]
	var moved := (g._pos as Vector2).distance_to(last[0])
	if moved >= 0.5:
		_trail.append([g._pos, g._yaw, float(last[2]) + moved, absf(float(g._v))])
	# the chaser goes along it at its own pace: it gains when you are slower than it
	if t > CHASE_SPOT_S:
		# backup joins as it goes: the chaser's pace climbs over the first minute, so a
		# getaway that has not shaken it by then gets harder, not longer
		# it drives the same streets you did, through the same traffic: its pace is yours where
		# it now is on your trail, and a little more (the siren clears its way), to its top.
		# (At a flat 17 m/s it caught autodrive in 26-43 s every run: racer's town pace is
		# 10-15 m/s with the queues, so a chase was over before it began.)
		var top := CHASE_TOP + CHASE_RAMP * clampf((t - 20.0) / 40.0, 0.0, 1.0)
		var edge := CHASE_EDGE + (CHASE_EDGE2 - CHASE_EDGE) * clampf((t - 20.0) / 40.0, 0.0, 1.0)
		_vc = minf(_vc + CHASE_ACC * dt, minf(top, _trail_v + edge))
		# and it cannot drive through you: close up, it closes no faster than a car does on the
		# one in front (stopped in a queue you were caught at full speed in 4 s, every run)
		_vc = minf(_vc, maxf(float(g._v), 0.0) + maxf(_gap - CHASE_CAUGHT + 1.0, 0.0) * 0.7)
		if t > 45.0 and not _backup_said:
			_backup_said = true
			_say("Backup's joined -- two of them now, and faster.", 2.5)
			_chaser2 = _police_car()
	var vp := maxf(float(g._v), 0.0)
	_gap += (vp - _vc) * dt
	_gap = maxf(_gap, 0.0)
	var head := float(_trail[_trail.size() - 1][2])
	var want := head - _gap
	# its place on the trail: the point at `want` metres along it
	while _trail.size() > 2 and float(_trail[1][2]) < want - BACKUP_BEHIND - 2.0:
		_trail.remove_at(0)   # (kept a little behind it: the backup car drives there)
	var at := _trail_at(want)
	var p: Vector2 = at[0]
	var yaw: float = at[1]
	if want < float(_trail[0][2]):
		_trail_v = CHASE_TOP   # (still behind where you started: open road to it -- your standing start there held it at 1 m/s and every run was "lost" in 12-24 s)
	else:
		_trail_v = at[2]
	if _chaser2 != null:
		var at2 := _trail_at(want - BACKUP_BEHIND)
		var p2: Vector2 = at2[0]
		_chaser2.position = Vector3(p2.x, g._h(p2), p2.y)
		_chaser2.rotation = Vector3(0, -float(at2[1]) + PI * 0.5, 0)
	_chaser.position = Vector3(p.x, g._h(p), p.y)
	_chaser.rotation = Vector3(0, -yaw + PI * 0.5, 0)
	# the lights take turns, four times a second (the backup's the other way round)
	var on_red := fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
	for k in range(_lights.size()):
		(_lights[k] as Node3D).visible = on_red if (k % 2 == 0) != (k >= 2) else not on_red
	# the camera cuts: every 7 s, 3 s from just ahead of the car looking back at the chaser
	# behind it (the usual view the rest of the time)
	_cut_t += dt
	if not _shots.is_empty():
		_cut_t = 0.0   # (a shot list runs the camera: the director's, not this cut)
	if _cut_t > 7.0 and _back_cam == null:
		_back_cam = Camera3D.new()
		_back_cam.fov = 55.0
		g.world.add_child(_back_cam)
		_back_cam.make_current()
	if _back_cam != null:
		var fw: Vector2 = g._fwd()
		var eye: Vector2 = (g._pos as Vector2) + fw * 9.0 + Vector2(-fw.y, fw.x) * 2.5
		_back_cam.position = Vector3(eye.x, g._h(eye) + 2.2, eye.y)
		var me3 := Vector3(g._pos.x, _chaser.position.y, g._pos.y)
		_back_cam.look_at(_chaser.position.lerp(me3, 0.35) + Vector3.UP, Vector3.UP)   # (between it and you)
		if _cut_t > 10.0:
			_end_cut()
	if g._reds > _reds_seen:   # (through a red light: a moment of slow motion)
		_reds_seen = g._reds
		_slowmo(1.6)
		# and the chaser has to slow for the crossing traffic you went through: a red run buys
		# a few metres (racer's reason to run them)
		_gap += CHASE_RED_M
		if (g._reds - _reds0) % 2 == 1:
			_say("Through the red -- they have to brake for the cross traffic.", 2.2)
	closest = minf(closest, _gap) if t > CHASE_SPOT_S else closest
	# a close call: it came within CLOSE_IN and you got away again -- said, slowed, counted
	if _gap < CLOSE_IN:
		_close = true
	elif _close and _gap > CLOSE_OUT:
		_close = false
		close_calls += 1
		_say(["Close call!", "Shook them off -- for now.", "Too close!"][close_calls % 3], 1.8)
		Audio.play("impact_light", 0.05, -8.0)
		_slowmo(0.9)
	# caught only when held within reach for a moment (a touch at a queue is a close call)
	_hold_t = _hold_t + dt if _gap <= CHASE_CAUGHT + 1.0 and absf(float(g._v)) < 3.0 else 0.0
	if _hold_t >= CHASE_HOLD and t > CHASE_GRACE:
		result = "caught"
	elif _gap >= CHASE_LOST:
		result = "lost"
	elif not g._dest_on and t > 3.0:
		result = "home"   # (at the safe house: home free)

func _end_cut() -> void:
	_cut_t = 0.0
	if _back_cam != null and is_instance_valid(_back_cam):
		_back_cam.queue_free()
	_back_cam = null
	if g.cam != null:
		g.cam.make_current()

func _end_chase() -> void:
	_end_cut()
	if _chaser != null and is_instance_valid(_chaser):
		_chaser.queue_free()
	_chaser = null
	if _chaser2 != null and is_instance_valid(_chaser2):
		_chaser2.queue_free()
	_chaser2 = null
	_lights = []
	Probe.event("chase", {"result": result, "gap": snappedf(_gap, 0.1)})

## ---- the director's camera, the time of day, slow motion, the siren ----------------------------

var _shots: Array = []
var _shot_len := 5.0
var _shot_i := -1
var _shot_t := 0.0
var _cam: Camera3D = null
var _kerb_at := Vector3.ZERO
var _orbit := 0.0
var _slow_until := 0
var _reds_seen := 0
var _siren_on := false
var _car_bar: Node3D = null
var _car_siren: AudioStreamPlayer3D = null
var shots_seen := {}          ## for tests: shot -> times cut to

func _shots_tick(dt: float) -> void:
	if _shots.is_empty() or g._zoomed():
		return
	var b: Array = beats[i]
	if not (String(b[0]) in ["drive", "drive_on", "drive_for", "chase", "say"]):
		return
	_shot_t -= dt
	if _shot_t <= 0.0:
		_shot_t = _shot_len
		_shot_i = (_shot_i + 1) % _shots.size()
		var name := String(_shots[_shot_i])
		if name == "chaser" and _chaser == null:
			name = "kerb"   # (no chaser in this one)
		if name == "back" and _chaser == null:
			name = "orbit"
		shots_seen[name] = int(shots_seen.get(name, 0)) + 1
		if name == "kerb":
			# a spot at the roadside some way ahead, low: the car comes by it
			var fw: Vector2 = g._fwd()
			var ahead: Vector2 = (g._pos as Vector2) + fw * clampf(absf(g._v) * 2.5 + 12.0, 15.0, 45.0)
			var side := Vector2(-fw.y, fw.x)
			var hit: Dictionary = g._nearest_seg(ahead, 20.0, true)
			var half := float((g._roads[int(hit["road"])] as Dictionary)["w"]) * 0.5 if not hit.is_empty() else 4.0
			# the kerb on either side, else the road's edge: never a spot inside a building (a
			# day in Givatayim had 92 frames of camera in a wall, Shabbat eve 11 -- tests/scenario.gd)
			var at := Vector2.INF
			for cand: Vector2 in [ahead + side * (half + 1.2), ahead - side * (half + 1.2), ahead + side * maxf(half - 0.6, 0.5)]:
				if g._push_out(cand, 0.6, false, false) == Vector2.ZERO:
					at = cand
					break
			if at == Vector2.INF:
				name = "orbit"
			else:
				_kerb_at = Vector3(at.x, g._h(at) + 0.9, at.y)
		if name == "usual":
			_cam_usual()
		else:
			_cam_own()
		_shot_name = name
	if _cam == null or _shot_name == "usual":
		return
	var car := Vector3(g._view_pos.x, float(g._view_y) + 1.0, g._view_pos.y)
	var fw2: Vector2 = g._fwd()
	match _shot_name:
		"above":
			_cam.position = car + Vector3(-fw2.x * 14.0, 26.0, -fw2.y * 14.0)
			_cam.look_at(car + Vector3(fw2.x * 6.0, 0, fw2.y * 6.0), Vector3.UP)
		"kerb":
			_cam.position = _kerb_at
			_cam.look_at(car, Vector3.UP)
		"orbit":
			_orbit += dt * 0.35
			_cam.position = car + Vector3(cos(_orbit) * 11.0, 4.5, sin(_orbit) * 11.0)
			_cam.look_at(car, Vector3.UP)
		"chaser":
			if _chaser != null:
				var cp := _chaser.position
				var to := (car - cp)
				to.y = 0.0
				var d := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
				_cam.position = cp - d * 6.0 + Vector3(0, 2.6, 0)
				_cam.look_at(car, Vector3.UP)
		"back":
			var eye: Vector2 = (g._pos as Vector2) + fw2 * 9.0 + Vector2(-fw2.y, fw2.x) * 2.5
			_cam.position = Vector3(eye.x, g._h(eye) + 2.2, eye.y)
			var tgt := car if _chaser == null else _chaser.position.lerp(car, 0.35) + Vector3.UP
			_cam.look_at(tgt, Vector3.UP)

var _shot_name := "usual"

func _cam_own() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 58.0
		_cam.far = 3000.0
		g.world.add_child(_cam)
	_cam.make_current()

func _cam_usual() -> void:
	_shot_name = "usual"
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	if g.cam != null:
		g.cam.make_current()

func _set_time(to: String) -> void:
	match to:
		"day":
			if g._night:
				g._set_night(false)
			if g._evening:
				await g._set_evening(false)
		"evening":
			if g._night:
				g._set_night(false)
			if not g._evening:
				await g._set_evening(true)
		"night":
			if g._evening:
				await g._set_evening(false)
			if not g._night:
				g._set_night(true)
	Probe.event("scenario_time", {"to": to})

## a moment of slow motion: the world at a third of its pace for `secs` of real time
func _slowmo(secs: float) -> void:
	Engine.time_scale = 0.35
	_slow_until = Time.get_ticks_msec() + int(secs * 1000.0)
	shots_seen["slow motion"] = int(shots_seen.get("slow motion", 0)) + 1

func _slowmo_tick() -> void:
	if _slow_until > 0 and Time.get_ticks_msec() >= _slow_until:
		_slow_until = 0
		Engine.time_scale = 1.0

## the car's own light bar and siren (an ambulance's): made as the chaser's are
func _set_siren(on_: bool) -> void:
	_siren_on = on_
	if on_ and _car_bar == null and g._car != null:
		_car_bar = Node3D.new()
		g._car.add_child(_car_bar)
		for col: Color in [Color(1, 0.1, 0.1), Color(0.15, 0.35, 1)]:
			var mi := _lamp(col)
			_car_bar.add_child(mi)
		(_car_bar.get_child(0) as Node3D).position = Vector3(-0.3, 1.55, 0.1)
		(_car_bar.get_child(1) as Node3D).position = Vector3(0.3, 1.55, 0.1)
		_car_siren = _make_siren()
		g._car.add_child(_car_siren)
		if not Audio.muted():
			_car_siren.play()
	elif not on_ and _car_bar != null:
		for c in _held:   # (everyone stopped for it goes on)
			c.hit = 0.0
		_held = {}
		_car_bar.queue_free()
		_car_bar = null
		if _car_siren != null:
			_car_siren.queue_free()
			_car_siren = null
	if _car_bar != null:
		var red := fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
		(_car_bar.get_child(0) as Node3D).visible = red
		(_car_bar.get_child(1) as Node3D).visible = not red

func _lamp(col: Color) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	var bx := BoxMesh.new()
	bx.size = Vector3(0.5, 0.14, 0.22)
	var mi := MeshInstance3D.new()
	mi.mesh = bx
	mi.material_override = m
	return mi

func _make_siren() -> AudioStreamPlayer3D:
	var rate := 22050
	var buf := PackedFloat32Array()
	buf.resize(rate * 2)
	var ph := 0.0
	for k in range(buf.size()):
		var sec := float(k) / rate
		var f := 650.0 + 300.0 * (0.5 + 0.5 * sin(TAU * sec * 0.5))
		ph += TAU * f / rate
		buf[k] = tanh(1.8 * sin(ph)) * 0.6
	var sp := AudioStreamPlayer3D.new()
	sp.stream = g._wav(buf, rate, true)
	sp.unit_size = 14.0
	sp.max_distance = 260.0
	sp.volume_db = linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8)))) - 4.0
	return sp

## the traffic ahead going the car's way, in the lanes beside its line, pulls aside and stops
## for the siren; a car in its own lane drives on ahead of it (held still, the ambulance stood
## behind the very car it had stopped for 2 minutes -- tests/scenario.gd LEVEL=25), and one it
## is held behind is let go
var yielded := 0              ## for tests: cars that pulled over
var _held := {}               ## car -> true: stopped for the siren
func _yield_tick() -> void:
	_set_siren(true)   # (the bar's lamps taking turns)
	if g._traffic == null:
		return
	var fw: Vector2 = g._fwd()
	var side := Vector2(-fw.y, fw.x)
	for c in g._traffic.cars:
		if not c.alive:
			continue
		var rel: Vector2 = (c.pos as Vector2) - (g._pos as Vector2)
		var ahead := rel.dot(fw)
		var lat := absf(rel.dot(side))
		var mine := lat < 1.8   # (in the ambulance's own lane)
		var behind_it: bool = g._ap_lead_i >= 0 and g._ap_lead_i < g._traffic.cars.size() and g._traffic.cars[g._ap_lead_i] == c
		if _held.has(c) and (mine or (behind_it and float(g._ap_wait) > 1.0) or ahead < -6.0):
			c.hit = 0.0   # (let go: on it goes)
			_held.erase(c)
			continue
		if mine or ahead < 4.0 or ahead > 70.0 or lat > 8.0:
			continue
		if Vector2(sin(c.yaw), cos(c.yaw)).dot(fw) < 0.3:
			continue   # (the other way: they carry on)
		if not _held.has(c):
			yielded += 1
			_held[c] = true
		c.hit = maxf(float(c.hit), 2.5)   # (stopped beside the way, for the siren to go by)

## ---- the redo: title card, the live line, the end card, the delivery, the tour's cuts ----------

static func _mmss(secs: float) -> String:
	var s := int(maxf(secs, 0.0))
	return "%d:%02d" % [s / 60, s % 60]

func _ui_label(size: int, role: String) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", g._font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Palette.col(role))
	l.add_theme_color_override("font_outline_color", Palette.col("bg"))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("film", true)
	return l

func _band(rect: Rect2, alpha: float) -> ColorRect:
	var c := ColorRect.new()
	var col := Palette.col("bg")
	col.a = alpha
	c.color = col
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("film", true)
	return c

## the title card: the scenario's name, and under it what it asks of you
func _title_on(name_: String, goal: String) -> void:
	_title_off()
	_hush_banner()
	_title = _band(Rect2(0, 140, 640, 92), 0.6)
	var t1 := _ui_label(28, "accent")
	t1.text = name_
	t1.position = Vector2(20, 148)
	t1.size = Vector2(600, 40)
	_title.add_child(t1)
	t1.position -= _title.position
	var t2 := _ui_label(13, "ink")
	t2.text = goal
	t2.position = Vector2(60, 190) - _title.position
	t2.size = Vector2(520, 36)
	_title.add_child(t2)
	g._hud.add_child(_title)
	_title.modulate.a = 0.0
	var tw := _title.create_tween()
	tw.tween_property(_title, "modulate:a", 1.0, 0.35)
	Audio.play("open", 0.0, -10.0)

func _title_off() -> void:
	if _title != null and is_instance_valid(_title):
		var c := _title
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.4)
		tw.tween_callback(c.queue_free)
	_title = null

## the live line under the street's name: how it is going, in one line
func _strip_tick() -> void:
	var txt := _strip_text()
	if txt == "":
		if _strip != null:
			_strip.visible = false
		return
	if _strip == null:
		_strip = _ui_label(13, "player")
		_strip.position = Vector2(120, 50)
		_strip.size = Vector2(400, 20)
		g._hud.add_child(_strip)
	_strip.visible = true
	_strip.text = txt
	_strip.add_theme_color_override("font_color", Palette.col(_strip_role))

var _strip_role := "player"

func _left_m() -> float:
	if not g._dest_on:
		return 0.0
	if g._auto and g._ap_pts.size() > 1:
		return g._ap_len()   # (by road, as the HUD's own line says it)
	return (g._pos as Vector2).distance_to(g._dest)

func _dist_txt(m: float) -> String:
	return ("%.1f km" % (m / 1000.0)) if m >= 1000.0 else ("%d m" % int(m))

func _strip_text() -> String:
	if i < 0 or i >= beats.size() or String(beats[i][0]) == "title":
		return ""
	_strip_role = "player"
	match kind:
		"tour", "night_tour":
			var n := 0
			var k := 0
			for j in range(beats.size()):
				if String(beats[j][0]) == "drive":
					n += 1
					if j <= i:
						k = n
			if k == 0:
				return ""
			var b: Array = beats[i]
			if String(b[0]) == "drive":
				return "stop %d of %d · %s · %s" % [k, n, String(b[2]), _dist_txt(_left_m())]
			return "stop %d of %d · %s" % [k, n, _mmss(run_t)]
		"getaway":
			if _chaser == null:
				return ""
			var bars := int(clampf(_gap / CHASE_LOST, 0.0, 1.0) * 8.0 + 0.5)
			_strip_role = "hazard" if _gap < CLOSE_IN else ("warn" if _gap < 45.0 else "friend")
			var home := (" · safe house %s" % _dist_txt(_left_m())) if g._dest_on else ""
			return "police %d m  %s%s%s" % [int(_gap), "▮".repeat(bars), "▯".repeat(8 - bars), home]
		"ambulance":
			if _limit <= 0.0:
				return ""
			var left := _limit - run_t
			_strip_role = "friend" if left > 30.0 else ("warn" if left > 0.0 else "hazard")
			return "patient: %s%s · hospital %s" % ["" if left >= 0.0 else "late ", _mmss(absf(left)), _dist_txt(_left_m())]
		"day", "shabbat":
			if _clock_m < 0.0:
				return ""
			_strip_role = "accent"
			var n: int = g._traffic.alive_count() if g._traffic != null else 0
			return "%02d:%02d · %s · %d %s about" % [int(_clock_m) / 60, int(_clock_m) % 60, _clock_what, n, "car" if n == 1 else "cars"]
		"wedding":
			if _limit <= 0.0:
				return ""
			var lw := _limit - run_t
			_strip_role = "friend" if lw > 30.0 else ("warn" if lw > 0.0 else "hazard")
			return "ceremony in %s%s · the hall %s" % ["" if lw >= 0.0 else "-", _mmss(absf(lw)), _dist_txt(_left_m())]
		"gan":
			if _limit <= 0.0:
				return ""
			var lg := _limit - run_t
			_strip_role = "friend" if lg > 30.0 else ("warn" if lg > 0.0 else "hazard")
			var bg: Array = beats[i]
			var where := "home"
			if String(bg[0]) == "pickup":
				where = "%s at the gan on %s" % [String(bg[5]), String(bg[2])]
			return "%s%s · %s %s · %d of 2 picked up" % ["" if lg >= 0.0 else "late ", _mmss(absf(lg)), where,
				_dist_txt(_left_m()), drops_done]
		"taxi":
			var b: Array = beats[i]
			if String(b[0]) == "pickup":
				return "fare %d of %d · waving on %s · %s · earned %d" % [drops_done + 1, DROPS, String(b[2]), _dist_txt(_left_m()), tips]
			if String(b[0]) != "ride":
				return "earned %d" % tips
			var left := float(b[3]) - t
			_strip_role = "friend" if left > 20.0 else ("warn" if left > 0.0 else "hazard")
			return "fare %d of %d · to %s · %s%s · earned %d" % [drops_done + 1, DROPS, String(b[2]), "" if left >= 0.0 else "late ",
				_mmss(absf(left)), tips]
		"delivery":
			var b: Array = beats[i]
			if String(b[0]) != "deliver":
				return "tips %d" % tips
			var left := float(b[3]) - t
			_strip_role = "friend" if left > 20.0 else ("warn" if left > 0.0 else "hazard")
			return "drop %d of %d · %s · %s%s · tips %d" % [drops_done + 1, DROPS, String(b[2]), "" if left >= 0.0 else "late ",
				_mmss(absf(left)), tips]
	return ""

## a tour's long drive: a moment's fade, then the car near the stop (in its lane, stopped) and on
var _skip_t := -1.0
var _skip_i := -1
func _skip_ahead(b: Array, style := "", charge := false) -> void:
	_skip_i = i
	_skip_t = 0.0
	var fade := _band(Rect2(0, 0, 640, 360), 1.0)
	fade.modulate.a = 0.0
	g._hud.add_child(fade)
	var at: Vector2 = b[1]
	var from: Vector2 = g._pos
	var st := style if style != "" else String(b[3])
	var tw := fade.create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 0.45)
	var beat := i
	tw.tween_callback(func() -> void:
		if beat != i or not on:
			return   # (the beat ended under the fade -- a fare reached as it began: its stale "go to" made every later ride "arrive" in 2 s)
		var before: float = _left_m()
		var near := _route_back(CUT_BACK_M)
		if near == Vector2.INF:
			near = at + (from - at).normalized() * 80.0
		g._jump_to(near, "")
		g._set_dest(at, String(b[2]))
		g._ap_style = st
		g._apply_ap_style()
		g._set_auto(true)
		skips += 1
		if charge:
			# the clock pays for the road skipped, at the pace it allows: a cut is no shortcut
			# (at a fair clip, 1.6 x the clock's pace: charged at the clock's own, every cut
			# left the drop "running late" the moment it ended)
			var skipped := maxf(before - CUT_BACK_M, 0.0) / (DROP_PACE * 1.6)
			t += skipped
			run_t += skipped
			skipped_s += skipped
		Probe.event("scenario_skip", {"to": String(b[2])}))
	tw.tween_interval(0.25)
	tw.tween_property(fade, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		fade.queue_free()
		_skip_t = -1.0)
	_say("A little later, nearing %s..." % String(b[2]), 3.0)

## ---- the delivery ---------------------------------------------------------------------------

## DROPS of the town's own addresses, each 200-450 m from the last; a clock for each from the
## distance (as the ambulance's), the tip from how much of it was left
func _delivery_beats() -> Array:
	var town := String(story.get("town", g._city_name))
	var out: Array = [["say", "Friday night in %s. Three pizzas in the back, still hot." % town, 3.5]]
	var from: Vector2 = g._pos
	var used := {}
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if OS.get_environment("SCEN_SEED") != "":
		rng.seed = int(OS.get_environment("SCEN_SEED"))
	var en := {}
	for r: Dictionary in g._roads:
		if String(r["en"]) != "":
			en[r["name"]] = r["en"]
	for k in range(DROPS):
		var cands: Array = []
		for st: String in g._addr:
			if used.has(st) or st.is_valid_int():
				continue
			for a: Array in g._addr[st]:
				var p: Vector2 = a[1]
				var d := p.distance_to(from)
				if d < 200.0 or d > 450.0 or not g._in_city(p) or not g._bounds.grow(-150.0).has_point(p):   # (250-600: Givatayim ran 6-7 min, one drop 4:40 by its one-ways)
					continue
				cands.append([p, st, String(a[0])])
				break   # (one a street)
		if cands.is_empty():
			break
		var c: Array = cands[rng.randi() % cands.size()]
		if g._nearest_seg(c[0], 40.0, true, true).is_empty():
			cands.erase(c)
			if cands.is_empty():
				break
			c = cands[rng.randi() % cands.size()]
		used[c[1]] = true
		var name_: String = String(en.get(c[1], c[1]))
		# (at 1.5 x the crow's flight / 10 m/s autodrive was late on two of three in Givatayim:
		# its pace there, lights and corners, is nearer 6)
		var secs := roundf((c[0] as Vector2).distance_to(from) * 1.5 / 7.0 + 30.0)
		out.append(["deliver", c[0], "%s %s" % [name_, c[2]], secs])
		from = c[0]
	out.append(["end", ""])
	return out

var _drop_style_racer := false

func _deliver_start(b: Array) -> void:
	if g._zoomed():
		g._zoom_set(0.0)
	g._set_dest(b[1], String(b[2]))
	g._ap_style = "wave"   # (keeps the rules; the lights help)
	g._apply_ap_style()
	g._set_auto(true)
	_drop_style_racer = false
	_drop_fixed = false
	_crash0 = Probe._events.size()
	_say("Next: %s" % String(b[2]), 2.0)

var _drop_fixed := false
var _drop_route := 0.0        ## the way there by road, as autodrive first planned it
var _crash0 := 0
func _deliver_tick(b: Array) -> void:
	if OS.get_environment("SCEN_DEBUG") != "" and int(t * 4.0) != int((t - 0.02) * 4.0):
		print("[scen dbg] %s t %.1f pos %s to %s dest_on %s dest %s stop %s auto %s v %.1f pts %d" % [b[0], t, Vector2i(g._pos), Vector2i(b[1]), g._dest_on, Vector2i(g._dest), Vector2i(g._dest_stop), g._auto, g._v, g._ap_pts.size()])
	# the clock, once autodrive has its way there: by road at a delivery's town pace (by the crow's
	# flight, Givatayim's winding one-ways made autodrive late on every drop: 3:25 for 600 m)
	if not _drop_fixed and t > 1.0 and g._auto and g._ap_pts.size() > 1:
		_drop_fixed = true
		_drop_route = g._ap_len()
		b[3] = roundf(g._ap_len() / DROP_PACE + 25.0)
		_say("%s -- %s on the clock." % [String(b[2]), _mmss(float(b[3]))], 3.0)
	var secs := float(b[3])
	var left := secs - t
	# late: autodrive drops the rules (only autodrive: a person drives as they like)
	if left < secs * 0.3 and not _drop_style_racer and g._auto:
		_drop_style_racer = true
		g._ap_style = "racer"
		g._apply_ap_style()
		_say("Running late -- the rules can wait.", 2.5)
		Audio.play("voice_hurry_up", 0.0, -6.0)
	# a long drive, watched: the same cut as a tour's, the clock charged for it (Givatayim's
	# shift ran 6-7 min of mostly driving)
	if g._auto and t > DROP_SKIP_S and _skip_i != i and _skip_t < 0.0 and _left_m() > TOUR_SKIP_M * 1.5:
		_skip_ahead(b, String(g._ap_style), true)
	var there: bool = (not g._dest_on and t > 2.0 and (g._pos as Vector2).distance_to(b[1]) < 60.0) or (g._pos as Vector2).distance_to(b[1]) < 18.0
	if there:
		var tip := 2 if left < 0.0 else int(round(4.0 + 14.0 * clampf(left / secs, 0.0, 1.0)))
		if String(b[0]) == "ride":
			# the meter (a flag fall and by the km driven) and a tip; less for every knock on the way
			var fare := 12 + int(_drop_route / 1000.0 * 6.0)
			tip = maxi(tip - 3 * _knocks(), 0)
			_say(("%s -- fare %d, tip %d." % [String(b[4]), fare, tip]), 3.5)
			tips += fare
			_fare_off(true)
		tips += tip
		drops_done += 1
		_drop_t.append(int(t))
		if g._dest_on:
			g._clear_dest()
		g._v = minf(float(g._v), 3.0)
		if String(b[0]) != "ride":
			_say(("Delivered, %s -- tip %d!" if left >= 0.0 else "Delivered cold, %s late -- tip %d.") % [_mmss(absf(left)), tip], 3.0)
		Audio.play("coin", 0.0, -4.0)
		Juice.text(g._hud, Vector2(320, 150), "+%d" % tip, Palette.col("prize"))
		_next()
	elif left < -90.0:
		_drop_t.append(-1)
		_say("They cancelled the order. On to the next.", 3.0)
		Audio.play("voice_wrong", 0.0, -8.0)
		_next()

## ---- the end card ------------------------------------------------------------------------------

func _end_card() -> void:
	var lines: Array = []
	var head := "That's a wrap."
	match kind:
		"tour", "night_tour":
			var n := 0
			for b: Array in beats:
				if String(b[0]) == "drive":
					n += 1
			head = "Tour over"
			stars = 3 if reached >= n else (2 if reached >= n - 1 else 1)
			lines.append("%d of %d stops in %s" % [reached, n, _mmss(run_t)])
			if not _stop_names.is_empty():
				lines.append(" · ".join(_stop_names.slice(0, 6)))
		"getaway":
			head = {"lost": "You lost them", "home": "Made it to the safe house", "gave up": "They gave up",
				"caught": "Caught"}.get(result, "Over")
			lines.append("%s on the run · top speed %d km/h" % [_mmss(run_t), int(top_v * 3.6)])
			lines.append("close calls %d · closest %d m · red lights run %d" % [close_calls, int(closest) if closest < INF else 0, g._reds - _reds0])
		"ambulance":
			var left := _limit - run_t
			head = "Patient delivered" if stars >= 2 else ("Late, but there" if stars == 1 else "Didn't make it there")
			lines.append("%s for the run · %s %s" % [_mmss(run_t), _mmss(absf(left)), "to spare" if left >= 0.0 else "late"])
			lines.append("%d cars pulled over for you" % yielded)
		"delivery":
			head = "Shift over"
			var all_ := DROPS * 18
			stars = 3 if tips >= int(all_ * 0.55) else (2 if tips >= int(all_ * 0.37) else (1 if drops_done > 0 else 0))   # (30 / 20 of 54: three on-time drops with a third of the clock left tip ~9 each)
			lines.append("%d of %d delivered · tips %d" % [drops_done, DROPS, tips])
			var per: Array = []
			for s_: int in _drop_t:
				per.append(_mmss(s_) if s_ >= 0 else "cancelled")
			if not per.is_empty():
				lines.append("drops: " + ", ".join(per))
		"wedding":
			var lw := _limit - run_t
			head = "Mazal tov!" if stars >= 2 else "Late to your own party"
			lines.append("%s for the drive · %s %s" % [_mmss(run_t), _mmss(absf(lw)), "to spare" if lw >= 0.0 else "late"])
			lines.append("%d cars in the convoy · %d hoots" % [convoy_n + 1, hoots])
		"shabbat":
			head = "Shabbat shalom"
			stars = 0
			lines.append("%s through %s as it went quiet" % [_mmss(run_t), String(story.get("town", g._city_name))])
		"gan":
			var lg := _limit - run_t
			head = "Everyone home" if stars >= 2 else ("Home, a bit late" if stars == 1 else "Not home yet")
			lines.append("%s for the round · %s %s" % [_mmss(run_t), _mmss(absf(lg)), "to spare" if lg >= 0.0 else "late"])
			lines.append("%d of 2 kids picked up · %d parents waiting at the gates" % [drops_done, gan_parents])
		"taxi":
			head = "End of the shift"
			stars = 3 if tips >= 75 else (2 if tips >= 55 else (1 if drops_done > 0 else 0))
			lines.append("%d of %d fares · earned %d" % [drops_done, DROPS, tips])
			var per2: Array = []
			for s_: int in _drop_t:
				per2.append(_mmss(s_) if s_ >= 0 else "walked off")
			if not per2.is_empty():
				lines.append("rides: " + ", ".join(per2))
		"day":
			head = "Dawn again"
			stars = 0
			lines.append("A day in %s in %s" % [String(story.get("town", g._city_name)), _mmss(run_t)])
		"dragons":
			head = "They're gone"
			stars = 0
	# the best so far, kept in the game's own file
	var key := String(g._place.get("name", kind))
	var best := _best_load()
	var was: Dictionary = best.get(key, {})
	var new_best := stars > 0 and stars > int(was.get("stars", 0))
	if new_best and OS.get_environment("STREETS_PREFS") != "0":
		best[key] = {"stars": stars, "secs": int(run_t), "tips": tips}
		_best_save(best)
	if stars > 0 or not was.is_empty():
		lines.append("new best!" if new_best else ("best: %s" % "★".repeat(int(was.get("stars", 0)))))
	_hush_banner()
	_card = _band(Rect2(150, 74, 340, 170), 0.78)
	var y := 10.0
	var h := _ui_label(22, "accent")
	h.text = head
	h.position = Vector2(10, y)
	h.size = Vector2(320, 30)
	_card.add_child(h)
	y += 34.0
	if stars > 0:
		var st := _ui_label(24, "prize")
		st.text = "★".repeat(stars) + "☆".repeat(3 - stars)
		st.position = Vector2(10, y)
		st.size = Vector2(320, 30)
		_card.add_child(st)
		y += 34.0
	for ln: String in lines:
		var l := _ui_label(12, "ink")
		l.text = ln
		l.position = Vector2(10, y)
		l.size = Vector2(320, 18)
		_card.add_child(l)
		y += 19.0
	_card.size.y = y + 10.0
	g._hud.add_child(_card)
	_card.modulate.a = 0.0
	var tw := _card.create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.4)
	tw.tween_interval(9.0)
	tw.tween_property(_card, "modulate:a", 0.0, 0.8)
	Audio.play("voice_mission_completed" if stars >= 2 else ("voice_mission_failed" if stars == 0 and kind in ["getaway", "ambulance", "delivery"] else "win"), 0.0, -6.0)
	card_lines = [head] + lines
	print("[scenario] end card: %s %s | %s" % [head, "★".repeat(stars), " | ".join(lines)])

var card_lines: Array = []    ## for tests: what the end card said

var _clock_m := -1.0          ## the hour shown on the line ("clock" beat): minutes after midnight; -1 none
var _clock_rate := 0.0        ## minutes of the day a second
var _clock_what := ""

func _best_load() -> Dictionary:
	if not FileAccess.file_exists(SCEN_BEST):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SCEN_BEST))
	return d if d is Dictionary else {}

func _best_save(d: Dictionary) -> void:
	var f := FileAccess.open(SCEN_BEST, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))

## the game's own banner ("arrived: ...", the town's name) would show through a card: quiet it
func _hush_banner() -> void:
	if g._banner != null:
		if g._banner_tw != null:
			g._banner_tw.kill()
		g._banner.modulate.a = 0.0

## ---- the police cars --------------------------------------------------------------------------

const BACKUP_BEHIND := 13.0   ## metres of your trail the backup car keeps behind the first
var _chaser2: Node3D = null   ## the backup (after 45 s): drives your trail behind the first

## a police car with its light bar (its two lamps added to _lights), in the world
func _police_car() -> Node3D:
	var car: Node3D = g.model("police", 4.6)
	g.world.add_child(car)
	var k := 0
	for col: Color in [Color(1, 0.1, 0.1), Color(0.15, 0.35, 1)]:
		var mi := _lamp(col)
		mi.position = Vector3(-0.3 if k == 0 else 0.3, 1.62, 0)
		car.add_child(mi)
		_lights.append(mi)
		k += 1
	return car

## [where, yaw, your speed there] at `odo` metres along your trail
func _trail_at(odo: float) -> Array:
	var j := 0
	while j < _trail.size() - 2 and float(_trail[j + 1][2]) < odo:
		j += 1
	var a: Array = _trail[j]
	var b: Array = _trail[mini(j + 1, _trail.size() - 1)]
	var f := clampf((odo - float(a[2])) / maxf(float(b[2]) - float(a[2]), 0.01), 0.0, 1.0)
	return [(a[0] as Vector2).lerp(b[0], f), lerp_angle(float(a[1]), float(b[1]), f),
		lerpf(float(a[3]) if a.size() > 3 else 0.0, float(b[3]) if b.size() > 3 else 0.0, f)]

## ---- the taxi shift ---------------------------------------------------------------------------

const RIDE_LINES := [
	["To %s, please. And I'm already late.", "Made it! Keep the change."],
	["%s. Take the quick way, not the scenic one.", "Not bad at all."],
	["Can you take me to %s? My phone's dead.", "You're a lifesaver."],
	["%s -- my sister's wedding, I can't miss the toast!", "Just in time, thank you!"],
	["%s, and gently: there's a cake on my lap.", "The cake survived. Thank you."],
	["%s. I'll give you directions -- no, the app's fine.", "Thanks, have a good night."],
]

## DROPS fares: someone waving at the kerb 150-350 m on, then their address 300-600 m from there
func _taxi_beats() -> Array:
	var town := String(story.get("town", g._city_name))
	var out: Array = [["time", "night"], ["say", "Night shift in %s. Light on -- someone's always going somewhere." % town, 3.5]]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if OS.get_environment("SCEN_SEED") != "":
		rng.seed = int(OS.get_environment("SCEN_SEED"))
	var en := {}
	for r: Dictionary in g._roads:
		if String(r["en"]) != "":
			en[r["name"]] = r["en"]
	var used := {}
	var from: Vector2 = g._pos
	var lines := RIDE_LINES.duplicate()
	for k in range(DROPS):
		var pick := _addr_pick(from, 150.0, 350.0, used, rng)
		if pick.is_empty():
			break
		var kerb := _kerb_of(pick[0])
		var dest := _addr_pick(kerb, 300.0, 600.0, used, rng)
		if dest.is_empty():
			break
		var st_name := String(en.get(pick[1], pick[1]))
		var to_name := "%s %s" % [String(en.get(dest[1], dest[1])), String(dest[2])]
		var ln: Array = lines.pop_at(rng.randi() % lines.size())
		out.append(["pickup", kerb, st_name, 0.0, ln[0] % to_name])
		out.append(["ride", dest[0], to_name, 120.0, ln[1]])
		from = dest[0]
	out.append(["end", ""])
	return out

## one of the town's addresses `lo`-`hi` m from `from`, on a street not used yet: [where, street, number]
func _addr_pick(from: Vector2, lo: float, hi: float, used: Dictionary, rng: RandomNumberGenerator) -> Array:
	var cands: Array = []
	for st: String in g._addr:
		if used.has(st) or st.is_valid_int():
			continue
		for a: Array in g._addr[st]:
			var p: Vector2 = a[1]
			var d := p.distance_to(from)
			if d < lo or d > hi or not g._in_city(p) or not g._bounds.grow(-150.0).has_point(p):
				continue
			if g._nearest_seg(p, 40.0, true, true).is_empty():
				continue
			cands.append([p, st, String(a[0])])
			break
	if cands.is_empty():
		return []
	var c: Array = cands[rng.randi() % cands.size()]
	used[c[1]] = true
	return c

## the pavement beside the nearest public street to `p`, on `p`'s side: where a fare stands
func _kerb_of(p: Vector2) -> Vector2:
	var hit: Dictionary = g._nearest_seg(p, 40.0, true, true)
	if hit.is_empty():
		return p
	var r: Dictionary = g._roads[int(hit["road"])]
	var q: Vector2 = hit["q"]
	var side := (p - q).normalized() if p.distance_to(q) > 0.1 else Vector2.RIGHT
	return q + side * (float(r["w"]) * 0.5 + 1.3)

const PICKUP_M := 30.0        ## a fare this near: you pull up and they get in
var _fare: Node3D = null      ## the person waving, while a pickup is on
var _wave_t := 0.0

func _pickup_start(b: Array) -> void:
	if g._zoomed():
		g._zoom_set(0.0)
	var at: Vector2 = b[1]
	_fare_off(false)
	var a := Actor3D.new()
	g.world.add_child(a)
	g._set_character(a, g.PEOPLE[(drops_done * 3 + 1) % g.PEOPLE.size()], 1.15 if kind == "gan" else 1.72)
	g._humanize(a, 4200 + drops_done * 17)
	a.position = Vector3(at.x, g._walk_y(at), at.y)
	if kind == "gan":
		_gan_crowd(at)
	var hit: Dictionary = g._nearest_seg(at, 12.0, true, true)
	var face: Vector2 = ((hit["q"] as Vector2) - at).normalized() if not hit.is_empty() else Vector2.UP
	a.face(Vector3(face.x, 0, face.y))
	a.play("Idle", true, 1.0)
	_fare = a
	g.add_person(a)   # (solid, and autodrive brakes for them: not in the street's own lists)
	if g.has_method("track3d"):
		g.track3d(a, "*")
	_wave_t = 0.0
	g._set_dest(at, ("%s's gan" % String(b[5])) if kind == "gan" else ("a fare on %s" % String(b[2])))
	g._ap_style = "rules" if kind == "gan" else "wave"   # (a parent, kids about: by the rules)
	g._apply_ap_style()
	g._set_auto(true)
	if kind == "gan":
		_say("Next: %s, at the gan on %s." % [String(b[5]), String(b[2])], 2.5)
	else:
		_say("Someone's waving you down on %s." % String(b[2]), 2.5)

func _pickup_tick(b: Array, dt: float) -> void:
	if OS.get_environment("SCEN_DEBUG") != "" and int(t * 0.5) != int((t - dt) * 0.5):
		print("[scen dbg] pickup t %.1f pos %s to %s dest_on %s dest %s stop %s auto %s v %.1f pts %d why %s" % [t, Vector2i(g._pos), Vector2i(b[1]), g._dest_on, Vector2i(g._dest), Vector2i(g._dest_stop), g._auto, g._v, g._ap_pts.size(), g._ap_why])
	_wave_t -= dt
	if _wave_t <= 0.0 and _fare != null and g._ppl != null:
		_wave_t = 2.5
		g._ppl.gesture(_fare, "wave")
	# a long way round, watched: the cut, as for a drop (no clock to charge: they only wait)
	if g._auto and t > DROP_SKIP_S and _skip_i != i and _skip_t < 0.0 and _left_m() > TOUR_SKIP_M * 1.5:
		_skip_ahead(b, String(g._ap_style), kind == "gan")   # (the gan's clock pays for a cut, as a drop's)
	# there: by them, or where "go to" pulled up for them, or near and stood (and they walk over:
	# a run in Givatayim waited out three fares' 150 s each, never stopping where it could be "there")
	var near := (g._pos as Vector2).distance_to(b[1])
	var by_kerb: bool = g._dest_on and (g._pos as Vector2).distance_to(g._dest_stop) < 20.0 and absf(float(g._v)) < 2.0
	# (a fare waves you in on either side of the street: within PICKUP_M you pull up -- "go to"
	# wanted their own kerb and went round the block for it, 100 s and more, every Tel Aviv run)
	var there: bool = (not g._dest_on and t > 2.0 and near < 60.0) or near < PICKUP_M or by_kerb \
		or (near < 60.0 and absf(float(g._v)) < 1.0 and t > 60.0)
	if there:
		if g._dest_on:
			g._clear_dest()
		if g._auto:
			g._set_auto(false)
		g._v = minf(absf(float(g._v)), 2.0)
		_fare_off(false)   # (in they get)
		if kind == "gan":
			drops_done += 1
			_gan_crowd_off()
		Audio.play("open", 0.0, -8.0)
		_say("\"%s\"" % String(b[4]), 3.5)
		_next()
	elif t > 150.0 and kind != "gan":   # (a kid does not give up: the gan's clock is the stake)
		_fare_off(false)
		_drop_t.append(-1)
		_say("They gave up and hailed another cab.", 3.0)
		Audio.play("voice_wrong", 0.0, -8.0)
		i += 1   # (their ride goes with them)
		_next()

## the fare gone: into the car, or (at the end of a ride) out at the kerb and walking off
func _fare_off(out_at_kerb: bool) -> void:
	if _fare != null and is_instance_valid(_fare):
		_fare.queue_free()
	_fare = null
	if out_at_kerb and g._car != null:
		var a := Actor3D.new()
		g.world.add_child(a)
		g._set_character(a, g.PEOPLE[(drops_done * 3 + 1) % g.PEOPLE.size()], 1.72)
		g._humanize(a, 4200 + drops_done * 17)
		var side := Vector2(-g._fwd().y, g._fwd().x)
		var at: Vector2 = (g._pos as Vector2) + side * 2.0
		a.position = Vector3(at.x, g._walk_y(at), at.y)
		a.face(Vector3(side.x, 0, side.y))
		a.play("Walk", true, 1.0)
		g.add_person(a)
		var tw := a.create_tween()
		var to := at + side * 6.0
		tw.tween_property(a, "position", Vector3(to.x, g._walk_y(to), to.y), 4.0)
		tw.tween_callback(a.queue_free)

## knocks since the ride began (the Probe's crash events: none recorded when it is off)
func _knocks() -> int:
	var n := 0
	for k in range(_crash0, Probe._events.size()):
		if String((Probe._events[k] as Dictionary).get("kind", "")) == "crash":
			n += 1
	return n

## the point `back` metres before the end of autodrive's way there (the cut lands on the route,
## not 80 m short by the crow: on Tel Aviv's one-ways that was often 1 km round by road)
const CUT_BACK_M := 110.0
func _route_back(back: float) -> Vector2:
	var pts: PackedVector2Array = g._ap_pts
	if not g._auto or pts.size() < 3:
		return Vector2.INF
	var acc := 0.0
	for k in range(pts.size() - 1, 0, -1):
		acc += pts[k].distance_to(pts[k - 1])
		if acc >= back:
			return pts[k - 1]
	return Vector2.INF

## ---- the kindergarten pick-up -----------------------------------------------------------------

## Four o'clock: two kids at two of the town's own kindergartens (places.gd), then home, all on one
## clock. Light by design: the gans are the town's (already built), the kids are the taxi's
## pickups (one Actor3D each), and the crowd at each gate is GAN_CROWD standing people -- no AI.
const GAN_KIDS := [["Noa", "Abba! I made you a drawing!"], ["Ari", "Can we get ice cream? Pleeease?"]]
const GAN_CROWD := 3          ## parents standing at a gate (static, solid, braked for)
const GAN_PACE := 6.0         ## m/s by crow-line x GAN_WIND the clock allows (a drop's 6 by road)
const GAN_WIND := 1.7         ## road over crow-line (1.45: a round ran 1:39 late, one-ways and two cuts charged; 1.9: 2:14-2:30 to spare)
var _gan_people: Array = []   ## the parents at the gate now
var gan_parents := 0          ## for tests and the end card

func _gan_beats() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if OS.get_environment("SCEN_SEED") != "":
		rng.seed = int(OS.get_environment("SCEN_SEED"))
	var gans: Array = []
	if g._places != null:
		for items: Array in g._places._tile_items.values():
			for it: Array in items:
				if String(it[0]) == "kindergarten" and g._bounds.grow(-150.0).has_point(it[1]) and g._in_city(it[1]):   # (one past the town line: "leaving Givatayim", the road unbuilt)
					gans.append(it[1])
	var en := {}
	for r: Dictionary in g._roads:
		if String(r["en"]) != "":
			en[r["name"]] = r["en"]
	var out: Array = [["time", "day"]]
	var from: Vector2 = g._pos
	var picks: Array = []
	for k in range(GAN_KIDS.size()):
		var cands: Array = []
		for p: Vector2 in gans:
			var d := p.distance_to(from)
			if d >= 250.0 and d <= 550.0 and (picks.is_empty() or p.distance_to(picks[0][0]) > 200.0):
				var hit: Dictionary = g._nearest_seg(p, 40.0, true, true)
				if not hit.is_empty():
					cands.append([p, String((g._roads[int(hit["road"])] as Dictionary)["name"])])
		if cands.is_empty():
			break
		var c: Array = cands[rng.randi() % cands.size()]
		picks.append(c)
		from = c[0]
	var home := _addr_pick(from, 300.0, 600.0, {}, rng)
	var crow := 0.0
	var at: Vector2 = g._pos
	for c: Array in picks:
		crow += at.distance_to(c[0])
		at = c[0]
	if not home.is_empty():
		crow += at.distance_to(home[0])
	var limit := roundf(crow * GAN_WIND / GAN_PACE + 20.0 * picks.size() + 20.0)
	out.append(["say", "The gans close at 16:30, and the whole town is doing the same run. You have %s." % _mmss(limit), 3.5])
	out.append(["timer", limit])
	out.append(["shots", ["usual", "back", "kerb", "above", "orbit"], 7.0])
	for k in range(picks.size()):
		var c: Array = picks[k]
		var st := String(en.get(c[1], c[1]))
		out.append(["pickup", _kerb_of(c[0]), st, 0.0, GAN_KIDS[k][1], GAN_KIDS[k][0]])
	if not home.is_empty():
		out.append(["drive_for", home[0], "home, on %s" % String(en.get(home[1], home[1])), "rules", limit + 90.0])
	out.append(["shots", [], 0.0])
	out.append(["end", ""])
	if OS.get_environment("SCEN_DEBUG") != "":
		print("gan: %d gans in town, picks %s, home %s, clock %d s" % [gans.size(), picks, home, int(limit)])
	return out

## a few parents waiting by the gate, on the pavement beside the kid (each a person: solid, and
## autodrive brakes for them; they stand, so they cost their animation and nothing else)
func _gan_crowd(at: Vector2) -> void:
	_gan_crowd_off()
	var hit: Dictionary = g._nearest_seg(at, 12.0, true, true)
	var along := Vector2.RIGHT
	var face := Vector2.UP
	if not hit.is_empty():
		face = ((hit["q"] as Vector2) - at).normalized()
		along = Vector2(-face.y, face.x)
	for k in range(GAN_CROWD):
		var a := Actor3D.new()
		g.world.add_child(a)
		g._set_character(a, g.PEOPLE[(k * 5 + drops_done * 7 + 2) % g.PEOPLE.size()], 1.62 + 0.06 * (k % 3))
		g._humanize(a, 5100 + k * 13 + drops_done * 31)
		var p := at + along * (1.6 + 1.3 * k) * (1.0 if k % 2 == 0 else -1.0) - face * (0.4 * (k % 2))
		a.position = Vector3(p.x, g._walk_y(p), p.y)
		var look := (along * (-1.0 if k % 2 == 0 else 1.0) + face * 0.5).normalized()
		a.face(Vector3(look.x, 0, look.y))
		a.play("Idle", true, 0.8 + 0.1 * k)
		g.add_person(a)
		_gan_people.append(a)
		gan_parents += 1

func _gan_crowd_off() -> void:
	for a: Node3D in _gan_people:
		if is_instance_valid(a):
			a.queue_free()
	_gan_people.clear()

## ---- the wedding convoy -------------------------------------------------------------------------

## the hall 0.9-1.4 km off; you lead, three decorated cars on your trail hooting; a clock to the
## ceremony (the ambulance's: drive_for with _limit)
func _wedding_beats() -> Array:
	var goal := _ahead_main_street(700.0, 1100.0)   # (0.9-1.4 km: a 3 min drive, long to watch)
	var limit := roundf(goal.distance_to(g._pos) * 1.5 / 7.5 + 25.0)   # (at / 9 m/s it was 0:13 late)
	if OS.get_environment("SCEN_DEBUG") != "":
		print("wedding: from %s to %s" % [g._pos, goal])
	return [["time", "day" if OS.get_environment("SCEN_DAY") != "" else "evening"],
		["say", "The ceremony is at the hall in %s. The cousins are behind you, hands on the horn." % _mmss(limit), 3.5],
		["timer", limit],
		["convoy", 3],
		["shots", ["usual", "back", "above", "kerb", "orbit"], 7.0],
		["drive_for", goal, "the wedding hall", "rules", limit + 90.0],   # (in green-wave style autodrive hit a person on a crossing in 2 runs of 3: a light turned for it as they crossed)
		["shots", [], 0.0],
		["end", ""]]

const CONVOY_GAP := 11.0      ## metres of your trail between the cars
const WEDDING_SAYS := ["Every car on the street joins in the hooting.", "Someone's waving a flag out of the sunroof.",
	"An uncle on the phone: 'Where are you?!'", "A bus driver hoots back. Even he's happy."]
var _convoy: Array = []       ## the following cars (Node3D)
var _ctrail: Array = []       ## [where, yaw, odometer] of your car, every 0.5 m (the chase's trail, its own)
var _horns: Array = []        ## an AudioStreamPlayer3D on each
var _hoot_t := 2.0
var _say_t := 18.0
var hoots := 0                ## for tests and the end card
var convoy_n := 0

func _convoy_on(n: int) -> void:
	_convoy_off()
	_ctrail = [[g._pos, g._yaw, 0.0]]
	var ribbon := _flat("ink")
	var bloom := [_flat("prize"), _flat("accent"), _flat("friend")]
	_dress(g._car, ribbon, bloom)
	var horn := _horn_stream()
	for k in range(n):
		var c: Node3D = g.model(["sedan", "suv", "taxi", "van"][k % 4] if k != 2 else "sedan", 4.4)
		g.world.add_child(c)
		_dress(c, ribbon, bloom)
		var hp := AudioStreamPlayer3D.new()
		hp.stream = horn
		hp.unit_size = 12.0
		hp.max_distance = 200.0
		hp.volume_db = linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8)))) - 8.0
		hp.pitch_scale = 0.92 + 0.08 * k
		c.add_child(hp)
		_convoy.append(c)
		_horns.append(hp)
		convoy_n = _convoy.size()
		c.visible = false   # (until the trail is long enough to put it on)

func _convoy_off() -> void:
	for c in _convoy:
		if is_instance_valid(c):
			c.queue_free()
	_convoy = []
	_horns = []
	if g._car != null and g._car.has_node("wedding"):
		g._car.get_node("wedding").queue_free()

## the cars on your trail, a few metres apart; now and then one hoots (a couple at once, often)
var convoy_us := 0            ## for the test: what the convoy costs (microseconds, all its ticks)
var convoy_ticks := 0
func _convoy_tick(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_convoy_move(dt)
	convoy_us += Time.get_ticks_usec() - t0
	convoy_ticks += 1
	if OS.get_environment("SCEN_DEBUG") != "" and convoy_ticks % 300 == 0:
		print("wedding: at %s, %.0f km/h, %s" % [Vector2i(g._pos), absf(g._v) * 3.6, g._on_name])

func _convoy_move(dt: float) -> void:
	var last: Array = _ctrail[_ctrail.size() - 1]
	var moved := (g._pos as Vector2).distance_to(last[0])
	if moved >= 0.5:
		_ctrail.append([g._pos, g._yaw, float(last[2]) + moved])
	var head := float(_ctrail[_ctrail.size() - 1][2])
	while _ctrail.size() > 2 and float(_ctrail[1][2]) < head - CONVOY_GAP * (_convoy.size() + 1) - 2.0:
		_ctrail.remove_at(0)
	for k in range(_convoy.size()):
		var want := head - CONVOY_GAP * (k + 1)
		var c: Node3D = _convoy[k]
		if want < 0.0:
			continue
		var j := 0
		while j < _ctrail.size() - 2 and float(_ctrail[j + 1][2]) < want:
			j += 1
		var a: Array = _ctrail[j]
		var b: Array = _ctrail[mini(j + 1, _ctrail.size() - 1)]
		var f := clampf((want - float(a[2])) / maxf(float(b[2]) - float(a[2]), 0.01), 0.0, 1.0)
		var p := (a[0] as Vector2).lerp(b[0], f)
		c.position = Vector3(p.x, g._h(p), p.y)
		c.rotation = Vector3(0, -lerp_angle(float(a[1]), float(b[1]), f) + PI * 0.5, 0)
		c.visible = true
	_hoot_t -= dt
	if _hoot_t <= 0.0 and not Audio.muted():
		_hoot_t = randf_range(3.0, 8.0)
		var k := randi() % maxi(_horns.size(), 1)
		if k < _horns.size() and _convoy[k].visible:
			(_horns[k] as AudioStreamPlayer3D).play()
			hoots += 1
			get_tree_timer(randf_range(0.25, 0.7), func() -> void:   # (stopped short: a toot, or a long one)
				if is_instance_valid(_horns[k] if k < _horns.size() else null):
					(_horns[k] as AudioStreamPlayer3D).stop())
	_say_t -= dt
	if _say_t <= 0.0 and String(beats[i][0]) == "drive_for":
		_say_t = 22.0
		_say(WEDDING_SAYS[hoots % WEDDING_SAYS.size()], 3.0)

func get_tree_timer(secs: float, cb: Callable) -> void:
	g.get_tree().create_timer(secs).timeout.connect(cb)

## white ribbons from the bonnet's corners to the roof, a bunch of flowers on the bonnet: a
## node named "wedding" on the car (one shared material each: a few boxes and balls a car)
func _dress(car: Node3D, ribbon: Material, bloom: Array) -> void:
	if car == null:
		return
	var w := Node3D.new()
	w.name = "wedding"
	car.add_child(w)
	for side in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.02, 1.7)
		r.mesh = bm
		r.material_override = ribbon
		r.position = Vector3(0.55 * side, 1.15, 0.0)
		r.rotation = Vector3(0.38, 0.0, 0.0)
		w.add_child(r)
	for k in range(3):
		var f := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.24
		sm.radial_segments = 8
		sm.rings = 4
		f.mesh = sm
		f.material_override = bloom[k % bloom.size()]
		f.position = Vector3(-0.15 + 0.15 * k, 0.98, 1.25 + 0.05 * (k % 2))
		w.add_child(f)
	w.set_meta("film", true)

func _flat(role: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Palette.col(role) if role != "ink" else Color(0.96, 0.96, 0.94)
	m.roughness = 0.6
	return m

func _horn_stream() -> AudioStreamWAV:
	var rate := 22050
	var buf := PackedFloat32Array()
	buf.resize(int(rate * 0.5))
	for k in range(buf.size()):
		var tt := float(k) / rate
		buf[k] = tanh(2.2 * sin(TAU * 410.0 * tt)) + tanh(2.2 * sin(TAU * 515.0 * tt)) * 0.85
	return g._wav(buf, rate, true)

## ---- Shabbat eve ------------------------------------------------------------------------------

## evening; the traffic thinned to a few cars (traffic.gd set_cap -- the cheapest scenario of all:
## fewer cars to move and draw), a slow drive between two of the story's streets, the shots held
## long, then night: "Shabbat has begun", one car left on the road
func _shabbat_beats() -> Array:
	var town := String(story.get("town", g._city_name))
	var stops: Array = []
	for b: Array in _tour_beats():
		if String(b[0]) == "drive":
			stops.append([b[1], b[2]])
	if stops.size() < 2:
		var far := _far_main_street(500.0, 1000.0)
		stops = [[far, "across town"], [g._pos, "home"]]
	return [["time", "evening"], ["clock", 15 * 60 + 15, 0.45, "Friday, to candle lighting"],
		["say", "Friday in %s, the hour before sunset." % town, 4.0],
		["quiet", 8],
		["shots", ["usual", "kerb", "above", "kerb"], 9.0],
		["say", "The shops pull their shutters down. Last bags of challah, a bunch of flowers under an arm.", 6.0],
		["drive_for", stops[0][0], String(stops[0][1]), "rules", 60.0],
		["quiet", 3],
		["say", "The buses have stopped. Streets that roared all week are almost empty.", 6.0],
		["drive_for", stops[1][0], String(stops[1][1]), "rules", 60.0],
		["time", "night"], ["clock", 16 * 60 + 17, 0.3, "Shabbat"],   # (late November, Tel Aviv: candles at 16:17)
		["quiet", 1],
		["say", "Candles in the windows. Shabbat has begun.", 6.0],
		["shots", ["above"], 8.0],
		["say", "Somewhere, a family sings over the wine.", 6.0],
		["shots", [], 0.0],
		["end", "Shabbat shalom."]]

## a main street lo-hi m off the way the car faces (the wedding: Tel Aviv's farthest one took a
## way out where autodrive hit a person on a crossing at (249, 236) in every run -- reported to
## the driving work; the hall is put ahead instead, a straighter drive)
func _ahead_main_street(lo: float, hi: float) -> Vector2:
	var best := Vector2.INF
	var bd := -INF
	var fw: Vector2 = g._fwd()
	for r: Dictionary in g._roads:
		if not r["drive"] or not (String(r["k"]) in ["primary", "secondary", "tertiary"]):
			continue
		var pts: PackedVector2Array = r["pts"]
		var mid := pts[pts.size() / 2]
		var to := mid - (g._pos as Vector2)
		var d := to.length()
		if d < lo or d > hi or not g._bounds.grow(-150.0).has_point(mid):
			continue
		var score := to.normalized().dot(fw)
		if score > bd:
			bd = score
			best = mid
	return best if best != Vector2.INF else _far_main_street(lo, hi)
