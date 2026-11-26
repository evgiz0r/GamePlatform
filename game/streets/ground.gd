extends RefCounted
## The bare ground: patches, not one flat colour (moved out of streets.gd; `g` is the game).
## Open land drawn in one colour read as empty, a grey plain. A shader breaks it into
## patches of grass, bare earth and darker scrub (two sizes of noise, by world position, so
## it does not swim): nothing more to draw, just a different colour per pixel. The north is
## mostly green; Givatayim's few open lots are mostly dry.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const GROUND_SHADER := """
shader_type spatial;
uniform vec4 base : source_color;
uniform vec4 green : source_color;
uniform vec4 dark : source_color;
uniform float greenness = 0.5;
uniform vec4 rock : source_color;
uniform float textured = 1.0;
// the made-up town's mountains (0: none): limestone in ledges, red soil, dark scrub and the
// shadows of clouds going over, on every steep slope and everything above `mountain_from`
uniform float mountains = 0.0;
uniform float mountain_from = 100000.0;
uniform vec4 scrub : source_color;
uniform vec4 soil : source_color;
uniform sampler2D grass_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_mean = vec3(0.5);
varying vec3 wpos;
varying float wup;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wup = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}
void fragment() {
	float n = noise(wpos.xz / 70.0) * 0.65 + noise(wpos.xz / 15.0) * 0.35;
	float g = smoothstep(0.62 - greenness * 0.45, 0.78 - greenness * 0.4, n);
	vec3 c = mix(base.rgb, green.rgb, g);
	c = mix(c, dark.rgb, smoothstep(0.62, 0.9, noise(wpos.xz / 31.0 + 17.0)) * 0.55);
	// a mountainside steeper than any town street is bare rock, in bands and blotches
	float bare = smoothstep(0.86, 0.74, wup + (noise(wpos.xz / 9.0) - 0.5) * 0.08);
	vec3 stone = rock.rgb * (0.72 + 0.28 * noise(vec2(wpos.y * 0.45, (wpos.x + wpos.z) * 0.03))) * (0.85 + 0.3 * noise(wpos.xz / 6.0));
	c = mix(c, stone, bare);
	float mtn = 0.0;
	if (mountains > 0.5) {
		mtn = max(bare, smoothstep(mountain_from, mountain_from + 30.0, wpos.y + (noise(wpos.xz / 60.0) - 0.5) * 24.0));
		// limestone laid down in beds: a ledge every 5 m or so of height, wavering, its face
		// catching the light and a dark seam under it -- from the town they read as contours
		// (beds 4-12 m thick by where you are, so they break up rather than ruling the slope)
		float thick = mix(4.0, 12.0, noise(wpos.xz / 160.0 + 21.0));
		float bed = fract(wpos.y / thick + (noise(wpos.xz / 34.0) - 0.5) * 1.3 + noise(wpos.xz / 9.0) * 0.12);
		float face = smoothstep(0.0, 0.3, bed) * (1.0 - 0.5 * smoothstep(0.55, 1.0, bed));
		vec3 m = rock.rgb * 0.7 * (0.75 + 0.35 * noise(wpos.xz / 13.0 + 3.0)) * mix(0.45, 1.05, face);
		// red soil in hollows, and dark scrub and pine in the folds and low down, thinning
		// toward the crests
		m = mix(m, soil.rgb * (0.8 + 0.35 * noise(wpos.xz / 6.0)), smoothstep(0.56, 0.72, noise(wpos.xz / 26.0 + 40.0)) * 0.7);
		float fold = noise(wpos.xz / 46.0 + 11.0) * 0.65 + noise(wpos.xz / 12.0 + 5.0) * 0.35;
		float scrubby = smoothstep(0.46, 0.6, fold + (wup - 0.7) * 0.5 - max(wpos.y - mountain_from, 0.0) / 600.0);
		m = mix(m, scrub.rgb * (0.65 + 0.6 * noise(wpos.xz / 3.5)), scrubby);
		// a sprinkle of bushes over the bare rock too, darker dots that thin out with height
		float dots = step(0.64 + max(wpos.y - mountain_from, 0.0) / 900.0, noise(wpos.xz / 2.2 + 9.0));
		m = mix(m, scrub.rgb * 0.8, dots * (1.0 - scrubby) * 0.8);
		// clouds' shadows drifting over
		float cl = noise(wpos.xz / 190.0 + vec2(TIME * 0.011, TIME * 0.004)) * 0.7 + noise(wpos.xz / 75.0 + vec2(TIME * 0.019, 0.3)) * 0.3;
		m *= 1.0 - 0.4 * smoothstep(0.56, 0.7, cl);
		c = mix(c, m, mtn);
	}
	c *= 0.94 + 0.06 * noise(wpos.xz / 2.5);
	if (textured > 0.5) {   // the lawn photo (see TONE_SHADER), over earth and grass alike
		// Its 2 m repeat lines up into a grid further off, so it fades out with distance (the
		// noise above, which never repeats, carries the far ground), and a second copy 7.3 m
		// across, turned, breaks up the repeat nearer in.
		float kd = 1.0 - smoothstep(25.0, 110.0, length(VERTEX));
		vec2 uv = wpos.xz * 0.5;
		vec3 t = texture(grass_tex, uv).rgb;
		vec3 t2 = texture(grass_tex, vec2(wpos.z, -wpos.x) * 0.137 + vec2(0.31, 0.77)).rgb;
		float lawn = (1.0 - bare * 0.6) * (1.0 - mtn * 0.75);   // less of the lawn photo on bare rock
		// the lawn's colours only where it is grass: bare earth (and rock) takes just its light
		// and dark -- its greens and yellows on grey earth came out as speckles of colour
		vec3 lw = vec3(0.2126, 0.7152, 0.0722);
		float gg = g * (1.0 - bare);
		vec3 d1 = mix(vec3(dot(t, lw) / dot(grass_mean, lw)), t / grass_mean, gg);
		vec3 d2 = mix(vec3(dot(t2, lw) / dot(grass_mean, lw)), t2 / grass_mean, gg);
		c *= mix(vec3(1.0), clamp(d1, vec3(0.0), vec3(2.6)), 0.85 * kd * lawn);
		c *= mix(vec3(1.0), clamp(d2, vec3(0.0), vec3(2.6)), 0.3 * lawn * (1.0 - smoothstep(60.0, 260.0, length(VERTEX))));
		vec2 xy = (texture(grass_nrm, uv).rg * 2.0 - 1.0) * 0.8 * kd;
		vec3 b = vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
		vec3 tx = (VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
		tx = normalize(tx - NORMAL * dot(NORMAL, tx));
		NORMAL = normalize(tx * b.x + cross(NORMAL, tx) * b.y + NORMAL * b.z);
	}
	ALBEDO = c * far_shade(wpos, length(VERTEX)) * mix(1.0, 0.82, wet * step(0.7, wup));   // (wet earth, darker)
	ROUGHNESS = mix(0.95, 0.75, wet);
}
"""
var _ground_shader_mat: ShaderMaterial

func _ground_mat() -> ShaderMaterial:
	if _ground_shader_mat == null:
		_ground_shader_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = g._with_far(GROUND_SHADER)
		_ground_shader_mat.shader = sh
		g._far(_ground_shader_mat)
		_ground_shader_mat.set_shader_parameter("grass_tex", g._tex("leafy_grass_diff"))
		_ground_shader_mat.set_shader_parameter("grass_nrm", g._tex("leafy_grass_nor"))
		_ground_shader_mat.set_shader_parameter("grass_mean", Streets.TEX_MEAN["leafy_grass"])
		_ground_shader_mat.set_shader_parameter("textured", 1.0 if g._quality > 0 else 0.0)
		_retint_ground()
	return _ground_shader_mat

func _retint_ground() -> void:
	if _ground_shader_mat == null:
		return
	var north := String(g._place.get("look", "")) == "north"
	var base: Color = g._tone["ground"]
	var green: Color = g._tone["grass"]
	_ground_shader_mat.set_shader_parameter("base", base)
	_ground_shader_mat.set_shader_parameter("green", green.lerp(base, 0.25))
	_ground_shader_mat.set_shader_parameter("dark", green.lerp(Palette.col("bg"), 0.45))
	_ground_shader_mat.set_shader_parameter("greenness", 0.8 if north else 0.3)
	_ground_shader_mat.set_shader_parameter("rock", g._tone["rock"])
	# the made-up town's mountains (see GROUND_SHADER): dark olive scrub, red-brown soil
	_ground_shader_mat.set_shader_parameter("mountains", 1.0 if g._made_up and g._hnx > 0 else 0.0)
	_ground_shader_mat.set_shader_parameter("mountain_from", g._mtn_from)
	var veg := Palette.col("friend").lerp(Palette.col("warn"), 0.35)
	_ground_shader_mat.set_shader_parameter("scrub", g._natural(veg.lerp(Palette.col("bg"), 0.66), 0.5))
	# (the palette's warn, its yellow, darkened and a touch of its hazard: an earth brown -- its
	# hazard alone is pink in most palettes)
	_ground_shader_mat.set_shader_parameter("soil", g._natural(Palette.col("warn").lerp(Palette.col("hazard"), 0.25).lerp(Palette.col("bg"), 0.55), 0.4))

## the same noise in script, for clumping what grows on open land where the green is
func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash01(i)
	var b := _hash01(i + Vector2(1, 0))
	var c := _hash01(i + Vector2(0, 1))
	var d := _hash01(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

func _hash01(p: Vector2) -> float:
	return fposmod(sin(p.dot(Vector2(12.9898, 78.233))) * 43758.5453, 1.0)
