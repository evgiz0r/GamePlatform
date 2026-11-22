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
##   ["end", text]                       the last caption; the city goes on, the drive is yours
## A level with "scenario" in LEVELS runs one: "tour" (built from the town's own story,
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
const CHASE_START := 60.0     ## metres behind at the start
const CHASE_SPOT_S := 2.0     ## seconds before it moves off ("they spot you")
const CHASE_ACC := 3.0        ## how fast it picks up speed (m/s^2)
const HOP := 900.0            ## a tour's next stop no further than this from the last, where it can
const CHASE_CAUGHT := 7.0     ## ...this close and you are caught
const CHASE_LOST := 160.0     ## ...this far and you lost it

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
	elif id == "getaway":
		beats = _getaway_beats()
	Probe.event("scenario", {"kind": id, "beats": beats.size()})

func start() -> void:
	on = true
	i = -1
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

## somewhere 1.2-2 km off on a main street, autodrive there in racer style, the chaser behind
func _getaway_beats() -> Array:
	var goal := _far_main_street(1200.0, 2000.0)
	return [["say", "The getaway. They're right behind you -- lose them.", 3.0],
		["drive_on", goal, "the safe house", "racer"],
		["chase", 150.0],
		["end", ""]]

## ---- running it ------------------------------------------------------------------------------

func tick(dt: float) -> void:
	_caption_tick(dt)
	if not on:
		return
	if g._opening != null and g._opening.on:
		return   # (its own opening first)
	if i < 0 or i >= beats.size():
		return
	t += dt
	var b: Array = beats[i]
	match String(b[0]):
		"say":
			if t >= float(b[2]):
				_next()
		"drive":
			_street_words()
			var at: Vector2 = b[1]
			# there: at the stop, or at the kerb "go to" chose for it (it can only stop where a
			# street lets it -- Givatayim's tour gave up on two stops 150 s on, parked beside them)
			var by_kerb: bool = g._dest_on and (g._pos as Vector2).distance_to(g._dest_stop) < 20.0 and absf(g._v) < 2.0
			if (not g._dest_on and t > 2.0) or (g._pos as Vector2).distance_to(at) < 35.0 or by_kerb or t > DRIVE_MAX:
				reached += 1 if ((g._pos as Vector2).distance_to(at) < 60.0 or by_kerb or not g._dest_on) and t <= DRIVE_MAX else 0
				g._set_auto(false)
				_next()
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
		"say":
			_say(String(b[1]), float(b[2]))
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
		"end":
			var txt := String(b[1])
			if kind == "getaway":
				txt = {"lost": "You lost them. Nobody followed you home.", "caught": "Caught. They boxed you in.",
					"gave up": "They gave up the chase -- you got away."}.get(result, "")
			_say(txt, 6.0)
			_finish(result if result != "" else "done")

func _finish(how: String) -> void:
	on = false
	if result == "":
		result = how
	if _chaser != null:
		_end_chase()
	Probe.event("scenario_end", {"kind": kind, "result": result, "reached": reached})

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
	_trail = [[g._pos, g._yaw, 0.0]]
	_gap = CHASE_START
	_vc = 0.0
	result = ""
	_chaser = g.model("police", 4.6)
	g.world.add_child(_chaser)
	for col: Color in [Color(1, 0.1, 0.1), Color(0.15, 0.35, 1)]:
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
		_chaser.add_child(mi)
		_lights.append(mi)
	(_lights[0] as Node3D).position = Vector3(-0.3, 1.62, 0)
	(_lights[1] as Node3D).position = Vector3(0.3, 1.62, 0)
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
		_trail.append([g._pos, g._yaw, float(last[2]) + moved])
	# the chaser goes along it at its own pace: it gains when you are slower than it
	if t > CHASE_SPOT_S:
		_vc = minf(_vc + CHASE_ACC * dt, CHASE_TOP)
	var vp := maxf(float(g._v), 0.0)
	_gap += (vp - _vc) * dt
	_gap = maxf(_gap, 0.0)
	var head := float(_trail[_trail.size() - 1][2])
	var want := head - _gap
	# its place on the trail: the point at `want` metres along it
	while _trail.size() > 2 and float(_trail[1][2]) < want:
		_trail.remove_at(0)
	var a: Array = _trail[0]
	var b: Array = _trail[mini(1, _trail.size() - 1)]
	var f := clampf((want - float(a[2])) / maxf(float(b[2]) - float(a[2]), 0.01), 0.0, 1.0)
	var p := (a[0] as Vector2).lerp(b[0], f)
	var yaw := lerp_angle(float(a[1]), float(b[1]), f)
	_chaser.position = Vector3(p.x, g._h(p), p.y)
	_chaser.rotation = Vector3(0, -yaw + PI * 0.5, 0)
	# the lights take turns, four times a second
	var on_red := fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0
	(_lights[0] as Node3D).visible = on_red
	(_lights[1] as Node3D).visible = not on_red
	# the camera cuts: every 7 s, 3 s from just ahead of the car looking back at the chaser
	# behind it (the usual view the rest of the time)
	_cut_t += dt
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
	if _gap <= CHASE_CAUGHT:
		result = "caught"
	elif _gap >= CHASE_LOST:
		result = "lost"
	elif not g._dest_on and t > 3.0:
		result = "lost"   # (at the safe house: home free)

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
	_lights = []
	Probe.event("chase", {"result": result, "gap": snappedf(_gap, 0.1)})
