extends RefCounted
## The sky: a photograph (moved out of streets.gd; `g` is the game).
## By day the sky is a photo (textures/sky_day.jpg: the upper half of Poly Haven's CC0
## "kloofendal_48d_partly_cloudy_puresky", tonemapped by textures/hdr_sky.py; in the evening
## sky_evening.jpg, their "kloppenheim_06_puresky" kept darker), on a dome that
## follows the camera, drawn unlit and through no fog. It is turned so the sun in it stands
## where the sunlight comes from, and fades into the fog at the horizon. The shell keeps its
## own procedural sky behind it (it retints that on a palette change), which shows at night,
## when the dome is hidden. The palette's sky tone tints it lightly, as it does everything.
## Each: the photo; where its sun is across it (0..1); its average colour and its colour
## along the horizon, as stored (hdr_sky.py prints all three); where the sunlight comes from
## (the light's rotation, degrees: the evening sun in the west-south-west, where it sets in
## Givatayim in the autumn, 13 degrees up -- the photo's is 5, which made every shadow 12
## times the height of what cast it); its colour (palette roles: ink toward warn) and energy.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const SKIES := {
	"day": {"photo": "sky_day.jpg", "sun_u": 0.595, "mean": Vector3(0.626, 0.686, 0.792),
		"horizon": Vector3(0.742, 0.758, 0.801), "sun": Vector3(-50, -28, 0), "warm": 0.22, "energy": 1.1},
	"evening": {"photo": "sky_evening.jpg", "sun_u": 0.6118, "mean": Vector3(0.44, 0.523, 0.623),
		"horizon": Vector3(0.598, 0.592, 0.584), "sun": Vector3(-13, -78, 0), "warm": 0.55, "energy": 1.3},
}
var _sky_tex := {}                   ## photo -> its texture, once loaded

func _sky_now() -> Dictionary:
	return SKIES["evening" if g._evening else "day"]
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, shadows_disabled;
uniform sampler2D photo : filter_linear, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform vec3 horizon = vec3(0.75);
uniform float turn = 0.0;
varying vec3 dir;
void vertex() { dir = VERTEX; }
void fragment() {
	vec3 d = normalize(dir);
	float up = clamp(d.y, 0.0, 1.0);
	float u = atan(d.x, -d.z) / 6.2831853 + 0.5 + turn;
	float v = 1.0 - asin(up) / 1.5707963;
	vec3 c = texture(photo, vec2(u, v)).rgb;
	ALBEDO = mix(horizon, c * tint, smoothstep(0.0, 0.07, up));
}
"""
var _sky_dome: MeshInstance3D
var _sky_mat: ShaderMaterial

## the palette's say in the sky: its sky tone's hue (not its brightness) over the photo's
func _sky_tint() -> Vector3:
	var t: Color = g._tone.get("sky", Color(0.6, 0.7, 0.8))
	var lt := maxf(t.get_luminance(), 0.01)
	var m: Vector3 = _sky_now()["mean"]
	var lm := m.dot(Vector3(0.2126, 0.7152, 0.0722))
	var ratio := Vector3(t.r / lt, t.g / lt, t.b / lt) / (m / lm)
	return Vector3.ONE.lerp(ratio, 0.25)

## one of the photo's colours, tinted as the dome draws it
## no magenta in the light: green lifted to the middle of red and blue when it is the lowest.
## The day's haze (the fog, 205/190/192) and the shade's fill (201/197/200) had green lowest --
## a pink cast over the whole scene, worst far off where the fog is thick; daylight's haze and
## shade go grey to blue, never pink. tests/tint_card.gd
static func _unpink(c: Color) -> Color:
	var mid := (c.r + c.b) * 0.5
	if c.g < mid:
		c.g = mid
	return c

func _sky_col(c: Vector3) -> Color:
	var t := _sky_tint()
	return Color(c.x * t.x, c.y * t.y, c.z * t.z)

## what the glass and the paint reflect: [overhead, horizon], the photo's by day
func _sky_reflect() -> Array:
	if g._night or _sky_dome == null:
		var sk := g.env.sky.sky_material as ProceduralSkyMaterial
		return [sk.sky_top_color, sk.sky_horizon_color]
	return [_sky_col(_sky_now()["mean"]), _sky_col(_sky_now()["horizon"])]

func _build_sky_dome() -> void:
	var tex := _sky_photo()
	if tex == null:
		return
	_sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	_sky_mat.shader = sh
	_sky_mat.set_shader_parameter("photo", tex)
	# a whole sphere, not Godot's hemisphere: that one closes with a flat disc at its middle's
	# height, and the dome stands on the eye -- a plane through the eye, edge-on, that a phone's
	# GPU drew now and then as a flickering line straight across the screen at the horizon,
	# over near hedges too (tests/horizon_line.gd). The lower half is the horizon's haze.
	var mesh := SphereMesh.new()
	mesh.radius = 1900.0
	mesh.height = 3800.0
	mesh.is_hemisphere = false
	mesh.radial_segments = 32
	mesh.rings = 20
	mesh.material = _sky_mat
	_sky_dome = MeshInstance3D.new()
	_sky_dome.mesh = mesh
	_sky_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky_dome.extra_cull_margin = 4000.0
	g.world.add_child(_sky_dome)
	_retint_sky_dome()

## the dome round the camera, wherever it went this frame
var sky_drop := 0.0                  ## tests: the dome this far below the eye (tests/horizon_line.gd)

func _retint_sky_dome() -> void:
	if _sky_dome == null:
		return
	_sky_dome.visible = not g._night
	var t := _sky_tint()
	_sky_mat.set_shader_parameter("tint", t)
	var hz: Vector3 = _sky_now()["horizon"]
	_sky_mat.set_shader_parameter("photo", _sky_photo())
	_sky_mat.set_shader_parameter("horizon", Vector3(hz.x * t.x, hz.y * t.y, hz.z * t.z))
	# turn the photo so its sun is where the light comes from (the light shines down its -Z)
	var to_sun := g.sun.global_transform.basis.z if g.sun.is_inside_tree() else Basis.from_euler(g.sun.rotation).z
	_sky_mat.set_shader_parameter("turn", float(_sky_now()["sun_u"]) - (atan2(to_sun.x, -to_sun.z) / TAU + 0.5))

func _sky_photo() -> Texture2D:
	var f: String = _sky_now()["photo"]
	if not _sky_tex.has(f):
		_sky_tex[f] = load(Streets.TEX_DIR + f) as Texture2D
	return _sky_tex[f]
