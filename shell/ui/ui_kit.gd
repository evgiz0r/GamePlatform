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

## A vertically centered column of controls that scrolls instead of running off the
## bottom of the canvas once it has more in it than one screen holds -- the main menu
## grows a button for every game plus its own settings row, and eventually that is more
## than 360px of buttons. custom_minimum_size pins the column to at least a full screen
## tall, so VBoxContainer's own centering still looks exactly as before whenever the
## content is short enough to fit; only once it genuinely overflows does the extra spill
## past 360 and the ScrollContainer below take over, with no visible change either way.
static func center_column(nodes: Array) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(0, 360)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for n in nodes:
		var wrap := HBoxContainer.new()
		wrap.alignment = BoxContainer.ALIGNMENT_CENTER
		wrap.add_child(n)
		v.add_child(wrap)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(v)
	return scroll
