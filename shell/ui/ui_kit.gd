class_name UIKit
## Tiny helpers so every shell screen looks the same and follows the active palette.

static func panel(size: Vector2) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.col("bg_alt")
	sb.border_color = Palette.col("accent")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = size
	return p

static func label(text: String, size: int = 16, role: String = "ink") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Palette.col(role))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", Palette.col("ink"))
	b.add_theme_color_override("font_hover_color", Palette.col("player"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.col("bg")
	sb.border_color = Palette.col("accent")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Palette.col("accent").darkened(0.55)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.pressed.connect(on_press)
	return b

static func center_column(nodes: Array) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	for n in nodes:
		var wrap := HBoxContainer.new()
		wrap.alignment = BoxContainer.ALIGNMENT_CENTER
		wrap.add_child(n)
		v.add_child(wrap)
	return v
