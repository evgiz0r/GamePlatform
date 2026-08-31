class_name Blob extends Node2D
## A good-looking placeholder actor with no asset files required. Draws a glowing shape
## in a PALETTE ROLE, so it reskins for free. Assign `texture` later to swap in real art
## without touching game logic.

@export var role := "ink"
@export var radius := 8.0
@export_enum("circle", "square", "triangle", "diamond") var shape := "circle"
@export var glow := true
@export var texture: Texture2D = null

func _ready() -> void:
	Bus.palette_changed.connect(queue_redraw)

func _draw() -> void:
	var c := Palette.col(role)
	if texture != null:
		var s := texture.get_size()
		if glow:
			draw_texture_rect(texture, Rect2(-s * 0.5 * 1.25, s * 1.25), false, Color(c, 0.20))
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
