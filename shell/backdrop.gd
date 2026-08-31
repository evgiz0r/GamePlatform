class_name Backdrop extends Node2D
## Depth for free. Flow puts one behind every game, so no game has to think about its
## background and none of them look like a black void. Palette-driven, so it reskins too.

@export var area := Rect2(0, 0, 640, 360)

var _stars: Array = []

func _ready() -> void:
	z_index = -100
	z_as_relative = false
	Bus.palette_changed.connect(queue_redraw)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9021
	for i in 70:
		_stars.append({
			"p": Vector2(rng.randf_range(0, area.size.x), rng.randf_range(0, area.size.y)),
			"r": rng.randf_range(0.6, 1.8),
			"a": rng.randf_range(0.10, 0.42),
		})

func _draw() -> void:
	var bg := Palette.col("bg")
	var alt := Palette.col("bg_alt")
	var accent := Palette.col("accent")

	draw_rect(area, bg)

	# a soft glow pooled at the bottom, so the field has a floor and a horizon
	var steps := 26
	for i in steps:
		var f := float(i) / float(steps)
		var y := area.position.y + area.size.y * (0.45 + 0.55 * f)
		var h := area.size.y * 0.55 / float(steps) + 1.0
		draw_rect(Rect2(area.position.x, y, area.size.x, h),
			Color(alt.r, alt.g, alt.b, 0.06 + 0.16 * f))

	# faint grid — reads as "arcade" without competing with the actors
	var step := 40.0
	var gx := area.position.x
	while gx <= area.end.x:
		draw_line(Vector2(gx, area.position.y), Vector2(gx, area.end.y),
			Color(accent.r, accent.g, accent.b, 0.05), 1.0)
		gx += step
	var gy := area.position.y
	while gy <= area.end.y:
		draw_line(Vector2(area.position.x, gy), Vector2(area.end.x, gy),
			Color(accent.r, accent.g, accent.b, 0.05), 1.0)
		gy += step

	for s in _stars:
		draw_circle(s["p"], s["r"], Color(1, 1, 1, s["a"]))
