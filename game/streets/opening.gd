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
var _title: Label

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
	Probe.event("opening", {"start": true})

## each frame while it runs (streets.gd's _frame)
func tick(dt: float) -> void:
	if not on:
		return
	t += dt
	g._zoom_yaw_to += TURN * dt
	if _title != null:
		_title.modulate.a = clampf(t / 0.6, 0.0, 1.0) * clampf((MAX_S - t) / 0.6, 0.2, 1.0)
	if (t >= MIN_S and not g._bare_near()) or t >= MAX_S:
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
	g._zoom_set(0.0)   # (down to the car; the city goes on: it was running before we rose)
	Probe.event("opening", {"secs": snappedf(t, 0.1), "skipped": by_hand, "bare_near": squares_at_end})
