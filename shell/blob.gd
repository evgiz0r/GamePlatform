class_name Blob extends Node2D
## A good-looking placeholder actor with no asset files required. Draws a glowing shape
## in a PALETTE ROLE, so it reskins for free. Assign `texture` later to swap in real art
## without touching game logic.

@export var role := "ink"
@export var radius := 8.0
@export_enum("circle", "square", "triangle", "diamond") var shape := "circle"
@export var glow := true
@export var texture: Texture2D = null
## Sprites are 16x16; the viewport is 640x360, so they need scaling up to read well.
@export var texture_scale := 2.0
## Mirror horizontally. Set this rather than negating scale, which fights Juice.pop().
@export var flip_h := false

var _frames: Array[Texture2D] = []
var _clip := ""
var _fps := 8.0
var _loop := true
var _anim_t := 0.0
var actor := ""

func _ready() -> void:
	Bus.palette_changed.connect(queue_redraw)
	set_process(false)

## The easy way to use real art: b.set_sprite("wizard") / ("penguin") / ("sword").
## Looks in characters/, animals/, then items/. Pass a full res:// path to be explicit.
## An unknown name leaves the shape placeholder in place and warns in the playtest report.
func set_sprite(name: String, scale: float = 2.0) -> void:
	texture_scale = scale
	if name.begins_with("res://"):
		if ResourceLoader.exists(name):
			texture = load(name)
		else:
			Probe.note("sprite not found: " + name)
		queue_redraw()
		return
	for dir in ["characters", "animals", "items"]:
		var path := "res://assets/%s/%s.png" % [dir, name]
		if ResourceLoader.exists(path):
			texture = load(path)
			queue_redraw()
			return
	Probe.note("no sprite named '%s' in assets/ -- see assets/INDEX.md" % name)

## ---- animation -------------------------------------------------------------
## Frames live in assets/actors/<actor>/. A clip is either a numbered run --
## walk1.png, walk2.png -- or a single pose like idle.png. Pick the folder with
## set_actor(), then play() a clip by name. See assets/INDEX.md for what exists.
##
##   b.set_actor("adventurer")
##   b.play("walk", 10.0)          # loops walk1 -> walk2
##   b.play("cheer", 6.0, false)   # plays once and holds the last frame

func set_actor(name: String, scale: float = 0.5) -> void:
	actor = name
	texture_scale = scale
	_clip = ""
	# The neon halo is tuned for 16x16 shapes. Behind an 80x110 character it reads as a
	# dark smear rather than a glow, so actors opt out by default. Set glow back to true
	# afterwards if a particular game wants it.
	glow = false

## Returns false if the clip does not exist, so callers can fall back.
func play(clip: String, fps: float = 8.0, loop: bool = true) -> bool:
	if clip == _clip:
		return true
	var frames := _load_clip(clip)
	if frames.is_empty():
		Probe.note("actor '%s' has no clip or pose named '%s' -- see assets/INDEX.md"
			% [actor, clip])
		return false
	_clip = clip
	_frames = frames
	_fps = fps
	_loop = loop
	_anim_t = 0.0
	texture = _frames[0]
	set_process(_frames.size() > 1)
	queue_redraw()
	return true

func _load_clip(clip: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	if actor == "":
		return out
	var base := "res://assets/actors/%s/%s" % [actor, clip]
	for i in range(1, 10):
		var numbered := "%s%d.png" % [base, i]
		if not ResourceLoader.exists(numbered):
			break
		var tex: Texture2D = load(numbered)
		out.append(tex)
	if out.is_empty() and ResourceLoader.exists(base + ".png"):
		var single: Texture2D = load(base + ".png")
		out.append(single)
	return out

func _process(delta: float) -> void:
	if _frames.size() < 2:
		set_process(false)
		return
	_anim_t += delta * _fps
	var i := int(_anim_t)
	if not _loop and i >= _frames.size():
		i = _frames.size() - 1
		set_process(false)
	texture = _frames[i % _frames.size()]
	queue_redraw()

## ---- drawing ---------------------------------------------------------------

func _draw() -> void:
	var c := Palette.col(role)
	if flip_h:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
	if texture != null:
		var s := texture.get_size() * texture_scale
		if glow:
			# a soft tinted copy behind the sprite -- this is what makes art read as "neon"
			draw_texture_rect(texture, Rect2(-s * 0.5 * 1.3, s * 1.3), false, Color(c.r, c.g, c.b, 0.22))
		draw_texture_rect(texture, Rect2(-s * 0.5, s), false)
		return
	if glow:
		draw_circle(Vector2.ZERO, radius * 1.9, Color(c.r, c.g, c.b, 0.13))
		draw_circle(Vector2.ZERO, radius * 1.35, Color(c.r, c.g, c.b, 0.16))
	match shape:
		"square":
			draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), c)
		"triangle":
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -radius), Vector2(radius, radius), Vector2(-radius, radius)]), c)
		"diamond":
			draw_colored_polygon(PackedVector2Array([
				Vector2(0, -radius), Vector2(radius, 0), Vector2(0, radius), Vector2(-radius, 0)]), c)
		_:
			draw_circle(Vector2.ZERO, radius, c)
			draw_circle(Vector2.ZERO, radius * 0.45, Color(1, 1, 1, 0.55))
