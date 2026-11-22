extends RefCounted
## The opening: "on bringup when the graphics load in the background we will play
## something ... instead of these wierd hickups where we see things pop on the screen". Only
## the squares right round the start are built before the car is shown; the rest of what is
## near used to go up in view, building by building, the first seconds of every drive. Now,
## as the car would be shown, the view is up over the town instead -- high, turning slowly
## round where you will start, under the town's name, and the parts not built yet
## lying flat as their stand-ins (standins.gd) -- while the city waits (paused) and the
## squares round the car are built at the hurried pace. Once they are all up (MIN_S at the
## least, MAX_S at most) the view comes down to the car, which is where the drive begins.
## A tap, a click or a key skips it.
##
## Not for the tests, the bots, a filmed walk or a test route: their runs are compared run
## to run (see `wanted`). STREETS_OPENING=1 has it anyway, =0 never.

const MIN_S := 4.0            ## the opening lasts at least this...
const MAX_S := 20.0           ## ...and comes down after this whatever is still to build
const HIGH := 0.82            ## how high the view starts (the zoom's 0..1)
const TURN := 0.1             ## how fast it turns round (rad/s)

var g: Node
var on := false
var t := 0.0
var squares_at_end := -1      ## for tests: squares still bare near the car when it came down
var skipped := false
var shown: Array = []         ## for tests: the story's lines put on screen
var _title: Label
var _story_lbl: Label         ## the town's own story, a line at a time (cities/stories/<town>.json)
var _story: Array = []
var _story_i := -1
var _story_t := 0.0
const STORY_S := 3.4          ## seconds a line stays up

func _init(game: Node) -> void:
	g = game

## whether this run gets an opening
static func wanted(game: Node) -> bool:
	var env := OS.get_environment("STREETS_OPENING")
	if env != "":
		return env == "1"
	if Probe.enabled or DisplayServer.get_name() == "headless" or game._whole_first():
		return false
	for a: String in OS.get_cmdline_args():
		if a == "-s" or a == "--script":
			return false   # (a scene test)
	return true

func start() -> void:
	on = true
	t = 0.0
	g._zoom_set(HIGH)
	g._zoom_v = HIGH   # (start up there: not rising from the car through the half-built street)
	_title = Label.new()
	_title.text = "the streets are going up -- tap to start now"   # (the town's name: the game's own banner, above)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", g._font)
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Palette.col("ink"))
	_title.add_theme_color_override("font_outline_color", Palette.col("bg"))
	_title.add_theme_constant_override("outline_size", 8)
	_title.position = Vector2(120, 150)
	_title.size = Vector2(400, 30)
	g._hud.add_child(_title)
	_story = _story_lines()
	if not _story.is_empty():
		_title.add_theme_font_size_override("font_size", 11)
		_title.position = Vector2(120, 214)
		_story_lbl = Label.new()
		_story_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_story_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_story_lbl.add_theme_font_override("font", g._font)
		_story_lbl.add_theme_font_size_override("font_size", 17)
		_story_lbl.add_theme_color_override("font_color", Palette.col("ink"))
		_story_lbl.add_theme_color_override("font_outline_color", Palette.col("bg"))
		_story_lbl.add_theme_constant_override("outline_size", 8)
		_story_lbl.position = Vector2(90, 150)
		_story_lbl.size = Vector2(460, 60)
		g._hud.add_child(_story_lbl)
		var credit := Label.new()   # (the lines are our own words from these: credited)
		credit.text = "about the town: " + String(_story_src)
		credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		credit.add_theme_font_override("font", g._font)
		credit.add_theme_font_size_override("font_size", 9)
		credit.add_theme_color_override("font_color", Color(Palette.col("ink"), 0.9))
		credit.add_theme_color_override("font_outline_color", Palette.col("bg"))
		credit.add_theme_constant_override("outline_size", 5)
		credit.position = Vector2(120, 232)
		credit.size = Vector2(400, 14)
		_title.add_child(credit)
		credit.position = Vector2(0, 18)
	Probe.event("opening", {"start": true})

var _story_src := ""

## the town's story (cities/stories/<town>.json, written from Wikipedia, Wikivoyage and the
## town's own pages): its tagline, then its lines in a shuffled order, a new one each run
func _story_lines() -> Array:
	var path := "res://game/streets/cities/stories/%s.json" % String(g._city_id)
	var d = null
	if ResourceLoader.exists(path):   # (imported as a JSON resource: what a web build carries)
		var res = load(path)
		if res is JSON:
			d = (res as JSON).data
	if d == null and FileAccess.file_exists(path):
		d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return []
	var lines: Array = (d.get("lines", []) as Array).duplicate()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(lines.size() - 1, 0, -1):   # (shuffled: a different few each time)
		var j := rng.randi_range(0, i)
		var tmp = lines[i]
		lines[i] = lines[j]
		lines[j] = tmp
	var out: Array = []
	if String(d.get("tagline", "")) != "":
		out.append(String(d["tagline"]))
	out.append_array(lines)
	# the credit, short: the wikis it was written from (CC BY-SA), and "news and guides" for the rest
	var src: Array = []
	var other := false
	for so in d.get("sources", []):
		var title := String((so as Dictionary).get("title", ""))
		var site := "Wikipedia" if (title.contains("Wikipedia") or title.contains("Hamichlol")) else ("Wikivoyage" if title.contains("Wikivoyage") else "")
		if site != "" and not src.has(site):
			src.append(site)
		other = other or site == ""
	_story_src = ", ".join(src) + (" (CC BY-SA)" if not src.is_empty() else "") + (", news and guides" if other else "")
	return out

## each frame while it runs (streets.gd's _frame)
func tick(dt: float) -> void:
	if not on:
		return
	t += dt
	g._zoom_yaw_to += TURN * dt
	if _title != null:
		_title.modulate.a = clampf(t / 0.6, 0.0, 1.0) * clampf((MAX_S - t) / 0.6, 0.2, 1.0)
	if _story_lbl != null:
		_story_t -= dt
		if _story_t <= 0.0:
			_story_i = (_story_i + 1) % _story.size()
			_story_lbl.text = String(_story[_story_i])
			shown.append(_story_lbl.text)
			_story_t = STORY_S
		# (each line fades in and out over its few seconds)
		var into := STORY_S - _story_t
		_story_lbl.modulate.a = clampf(into / 0.4, 0.0, 1.0) * clampf(_story_t / 0.4, 0.0, 1.0)
	var least := MIN_S if _story.is_empty() else STORY_S * 2.0   # (two of the town's lines at least)
	if (t >= least and not g._bare_near()) or t >= MAX_S:
		end()

func end(by_hand := false) -> void:
	if not on:
		return
	on = false
	skipped = by_hand
	squares_at_end = 0
	for tt: Vector2i in g._tiles_todo:
		if g._tile_dist(tt, g._pos) < g.NEAR_FIRST:
			squares_at_end += 1
	if _title != null:
		_title.queue_free()
		_title = null
	if _story_lbl != null:
		_story_lbl.queue_free()
		_story_lbl = null
	g._zoom_set(0.0)   # (down to the car; the city goes on: it was running before we rose)
	Probe.event("opening", {"secs": snappedf(t, 0.1), "skipped": by_hand, "bare_near": squares_at_end})
