extends Node
## One locked palette drives the whole look. /look swaps the active palette and every
## game instantly reskins, because game code asks for ROLES (ink, hazard, friend...)
## rather than raw colors.

const PALETTES := {
	"neon_candy": {
		"bg":      Color("0b0919"),
		"bg_alt":  Color("161033"),
		"ink":     Color("f4f1ff"),
		"player":  Color("3df5ff"),
		"friend":  Color("6affc2"),
		"hazard":  Color("ff3d81"),
		"warn":    Color("ffd23d"),
		"prize":   Color("b06bff"),
		"accent":  Color("ff8adf"),
	},
	"ice": {
		"bg": Color("06101c"), "bg_alt": Color("0e2038"), "ink": Color("eaf6ff"),
		"player": Color("7ee8ff"), "friend": Color("a6ffe4"), "hazard": Color("4f7dff"),
		"warn": Color("d6f1ff"), "prize": Color("c0e8ff"), "accent": Color("6fd3ff"),
	},
	"sunset": {
		"bg": Color("1a0a1f"), "bg_alt": Color("34103a"), "ink": Color("fff2e8"),
		"player": Color("ffd166"), "friend": Color("ff9f5a"), "hazard": Color("ef476f"),
		"warn": Color("ffd166"), "prize": Color("ff6ad5"), "accent": Color("ff8f5a"),
	},
	"jungle": {
		"bg": Color("07160f"), "bg_alt": Color("0f2a1c"), "ink": Color("eaffef"),
		"player": Color("9dff6a"), "friend": Color("5ce1a0"), "hazard": Color("ff5c5c"),
		"warn": Color("ffe066"), "prize": Color("6affd8"), "accent": Color("b9ff5c"),
	},
	"haunted": {
		"bg": Color("0d0a12"), "bg_alt": Color("1c1526"), "ink": Color("e8e0ff"),
		"player": Color("b6ff5c"), "friend": Color("9d8aff"), "hazard": Color("ff4d6d"),
		"warn": Color("ffc857"), "prize": Color("7af5ff"), "accent": Color("c77dff"),
	},
}

var active := "neon_candy"

func use(name: String) -> void:
	if PALETTES.has(name):
		active = name
		RenderingServer.set_default_clear_color(col("bg"))
		Bus.palette_changed.emit()

func col(role: String) -> Color:
	var p: Dictionary = PALETTES[active]
	return p.get(role, Color.MAGENTA)

func names() -> Array:
	return PALETTES.keys()
