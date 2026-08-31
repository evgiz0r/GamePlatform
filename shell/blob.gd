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

func _ready() -> void:
	Bus.palette_changed.connect(queue_redraw)

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

func _draw() -> void:
	var c := Palette.col(role)
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
