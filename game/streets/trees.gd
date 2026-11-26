extends RefCounted
## Trees: leaf cards, bark, palm fronds (moved out of streets.gd; `g` is the game).
## A crown is a cloud of cards, each a cluster of leaves from textures/leaves_atlas.png
## (2x2: broad leaves, small narrow ones, feathery fronds, needle sprays; made by
## textures/leaf_atlas.py from Poly Haven's CC0 leaf photos). The vertex shader turns every
## card to face the camera (or the sun, in the shadow pass: dappled shadows), lights it as
## if the crown were a soft ball, and gives every tree its own outline -- cards pushed out
## here and in there, a few left out -- and a little sway in the wind. The leaf kind and the
## colour come in each copy's instance colour (alpha: the atlas cell), so all of this costs
## no more draw calls than the plain balls did. The photos are divided by each cell's average
## colour, so the palette's leaf tone still decides the colour.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const CROWN_SHADER := """
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;
uniform sampler2D leaves : filter_linear_mipmap, repeat_disable;
uniform vec3 leaf_col : source_color;
uniform vec3 cell_mean[4];
uniform float card_size = 0.5;     // half a card, in the crown's own size
uniform float keep = 1.0;          // the share of cards drawn (fewer at the lowest quality)
varying vec3 tint;
varying vec2 cuv;
varying float shade;
varying float lighter;
varying flat int cell;
varying flat float core;   // 1 on a conifer's solid middle (UV2.y -1): plain geometry, no card
float h1(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
void vertex() {
	core = UV2.y < -0.5 ? 1.0 : 0.0;
	tint = COLOR.rgb;
	cell = int(clamp(floor(COLOR.a * 4.0), 0.0, 3.0));
	if (core > 0.5) {
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		cuv = vec2(0.5);
		shade = 0.4;
		lighter = 0.0;
	} else {
	vec3 o = MODEL_MATRIX[3].xyz;
	float seed = h1(o.x * 0.37 + o.z * 1.13);
	float r = UV2.x;        // the card's own random number
	float out_ = UV2.y;     // 0 deep in the crown .. 1 at its surface
	vec3 n = NORMAL;        // out from the crown's middle
	vec3 p = VERTEX + n * (sin(dot(n, vec3(2.1, 1.3, 1.7)) * 2.0 + seed * 6.28) * 0.16
		+ sin(dot(n, vec3(-1.4, 2.3, 0.9)) * 3.0 + seed * 11.0) * 0.1);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	float sz = length(MODEL_MATRIX[2].xyz);
	float sc = mix((sx + sz) * 0.5, sy, 0.25);
	bool alive = fract(r * 13.7 + seed * 7.31) < keep * 0.9;
	float s = alive ? card_size * (0.75 + 0.5 * fract(r * 5.3)) * sc * inversesqrt(keep) : 0.0;
	vec3 c = (MODELVIEW_MATRIX * vec4(p, 1.0)).xyz;
	float t = TIME * 1.1 + seed * 6.28;
	c.x += (sin(t) * 0.035 + sin(t * 2.7 + r * 6.0) * 0.03 * out_) * sc;
	vec2 k = UV * 2.0 - 1.0;
	float a = r * 6.2832 + seed * 3.0;
	VERTEX = c + vec3(k.x * cos(a) - k.y * sin(a), k.x * sin(a) + k.y * cos(a), 0.0) * s;
	vec3 nv = normalize((MODELVIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = normalize(mix(nv, vec3(0.0, 0.0, 1.0), 0.2));
	cuv = UV;
	// deep in the crown and underneath it darker; some clumps lighter, some darker
	shade = mix(0.58, 1.0, out_) * mix(0.78, 1.05, clamp(p.y * 0.5 + 0.5, 0.0, 1.0)) * (0.88 + 0.24 * h1(r * 3.1 + seed));
	lighter = step(0.82, h1(r * 7.7 + seed * 2.0));
	}
}
void fragment() {
	vec2 uv = (cuv * 0.94 + 0.03 + vec2(float(cell % 2), float(cell / 2))) * 0.5;
	vec4 t = texture(leaves, uv);
	// smaller mipmaps average the leaves' edges away: thicken the alpha with distance, or
	// far trees thin out to nothing
	vec2 ts = uv * 1024.0;
	vec2 dx = dFdx(ts);
	vec2 dy = dFdy(ts);
	float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	vec3 c = leaf_col * tint * clamp(t.rgb / cell_mean[cell], vec3(0.0), vec3(2.5)) * shade;
	c *= mix(vec3(1.0), vec3(1.16, 1.1, 0.78), lighter * 0.8);
	ALBEDO = core > 0.5 ? leaf_col * tint * shade : c;
	ALPHA = core > 0.5 ? 1.0 : clamp(t.a * (1.0 + lod * 0.35), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
"""

## Bark: a photo (textures/) over its average, times the palette's trunk tone and the copy's
## colour (birches and eucalyptus pale), with its bumps
const BARK_SHADER := """
shader_type spatial;
uniform sampler2D bark_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 bark_mean = vec3(0.5);
uniform vec3 bark_col : source_color;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float textured = 1.0;
void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 c = bark_col * COLOR.rgb;
	if (textured > 0.5) {
		c *= clamp(texture(bark_tex, uv).rgb / bark_mean, vec3(0.0), vec3(2.5));
		NORMAL_MAP = vec3(texture(bark_nrm, uv).rg, 1.0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
}
"""

## A palm frond: a strip along the frond (UV.y 0 at the trunk .. 1 at the tip, UV.x -1..1
## across), cut by the shader into a rib and leaflets slanting out toward the tip, narrow
## at both ends, the tips drying yellow
const FROND_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 leaf_col : source_color;
void fragment() {
	float u = abs(UV.x);
	float v = UV.y;
	float edge = 0.1 + 0.9 * pow(sin(clamp(v, 0.0, 1.0) * 3.14159), 0.6);
	float f = v * 34.0 - u * 1.8;
	float k = fract(f);
	float aa = fwidth(f) + 0.001;
	float leaflet = 1.0 - smoothstep(0.58 - aa, 0.58 + aa, k);
	float inside = 1.0 - smoothstep(edge - 0.04, edge, u);
	float rib = 1.0 - smoothstep(0.03, 0.05, u);
	ALPHA = max(rib, leaflet * inside);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 c = leaf_col * COLOR.rgb * (0.78 + 0.35 * u) * mix(1.06, 0.82, k);
	c = mix(c, c * vec3(1.3, 1.18, 0.66), smoothstep(0.72, 1.0, v) * 0.6 * (1.0 - rib));
	ALBEDO = mix(c, leaf_col * COLOR.rgb * vec3(1.1, 1.05, 0.7), rib * 0.6);
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
}
"""

## a broad-leaved crown's lumps (middle, radius), in the crown's own size: close enough to
## read as one crown, not a bunch of balls
const CROWN_LUMPS := [[Vector3(0, 0, 0), 1.0], [Vector3(0.45, 0.1, 0.25), 0.78], [Vector3(-0.4, 0.15, -0.3), 0.75],
	[Vector3(0.05, 0.45, -0.02), 0.72]]
## the atlas cell each kind's leaves come from: 0 broad, 1 small and narrow, 2 feathery, 3 needles
const LEAF_CELL := {"ficus": 0, "round": 0, "maple": 0, "oak": 0, "acacia": 2, "olive": 1, "birch": 1,
	"eucalyptus": 1, "pine": 3, "cypress": 3, "spruce": 3, "date": 0, "fan": 0}
## each cell's average colour as stored (leaf_atlas.py prints them), for the shader to divide by
const LEAF_MEAN := [Vector3(0.332, 0.355, 0.113), Vector3(0.333, 0.357, 0.116),
	Vector3(0.405, 0.433, 0.230), Vector3(0.200, 0.294, 0.138)]
var _tree_mats: Array = []           ## [crown, cone, bark, palm bark, fronds] materials, for the palette

func _tree_shader_mat(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = code
	m.shader = sh
	return m

## the materials, once per city: cards for crowns and cones (each its own card size), two
## barks, the fronds
func _make_tree_mats() -> Array:
	var atlas := load(Streets.TEX_DIR + "leaves_atlas.png") as Texture2D
	var means := PackedVector3Array(LEAF_MEAN)
	var crown := _tree_shader_mat(CROWN_SHADER)
	crown.set_shader_parameter("leaves", atlas)
	crown.set_shader_parameter("cell_mean", means)
	crown.set_shader_parameter("card_size", 0.5)
	var cone := crown.duplicate() as ShaderMaterial
	cone.set_shader_parameter("card_size", 0.75)
	var bark := _tree_shader_mat(BARK_SHADER)
	bark.set_shader_parameter("bark_tex", g._tex("bark_brown_02_diff"))
	bark.set_shader_parameter("bark_nrm", g._tex("bark_brown_02_nor"))
	bark.set_shader_parameter("bark_mean", Streets.TEX_MEAN["bark_brown_02"])
	bark.set_shader_parameter("uv_scale", Vector2(1.0, 1.0))
	var pbark := bark.duplicate() as ShaderMaterial
	pbark.set_shader_parameter("bark_tex", g._tex("palm_tree_bark_diff"))
	pbark.set_shader_parameter("bark_nrm", g._tex("palm_tree_bark_nor"))
	pbark.set_shader_parameter("bark_mean", Streets.TEX_MEAN["palm_tree_bark"])
	pbark.set_shader_parameter("uv_scale", Vector2(1.0, 3.5))
	var fronds := _tree_shader_mat(FROND_SHADER)
	_tree_mats = [crown, cone, bark, pbark, fronds]
	_retint_trees()
	_tree_quality()
	return _tree_mats

func _retint_trees() -> void:
	if _tree_mats.is_empty():
		return
	for i in [0, 1, 4]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("leaf_col", g._tone["leaf"])
	for i in [2, 3]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("bark_col", g._tone["trunk"])

## the lowest web quality: two cards in three (each bigger), and plain bark
func _tree_quality() -> void:
	if _tree_mats.is_empty():
		return
	for i in [0, 1]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("keep", 1.0 if g._quality > 0 else 0.67)
	for i in [2, 3]:
		(_tree_mats[i] as ShaderMaterial).set_shader_parameter("textured", 1.0 if g._quality > 0 else 0.0)

## One card per corner set: VERTEX the card's middle (the shader spreads its corners across
## the screen), UV the corner, UV2 (the card's random number, how far out of the crown it
## is), NORMAL out from the crown's middle.
func _cards_mesh(cards: Array, m: Material, core: Array = []) -> ArrayMesh:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for cd: Array in cards:
		var at: Vector3 = cd[0]
		var n: Vector3 = cd[1]
		var r: float = cd[2]
		var o: float = cd[3]
		var b := v.size()
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			v.append(at)
			nr.append(n)
			uv.append(corner)
			uv2.append(Vector2(r, o))
			col.append(Color.WHITE)
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	# solid core triangles: [position, normal] per corner, UV2.y -1 so the shader leaves them be
	for i in range(core.size()):
		idx.append(v.size())
		v.append(core[i][0])
		nr.append(core[i][1])
		uv.append(Vector2(0.5, 0.5))
		uv2.append(Vector2(0.0, -1.0))
		col.append(Color.WHITE)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = nr
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TEX_UV2] = uv2
	a[Mesh.ARRAY_COLOR] = col
	a[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	am.surface_set_material(0, m)
	# the cards reach past their middles: a box round the whole crown, or a copy whose
	# middle is just off screen is culled with its leaves still in view
	am.custom_aabb = AABB(Vector3(-2.6, -2.2, -2.6), Vector3(5.2, 4.6, 5.2))
	return am

## a broad-leaved crown: cards through the same few lumps the plain crown had, most of them
## near the outside so the outline is full
func _card_crown(blobs: Array, n: int, m: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var vol := 0.0
	for bl: Array in blobs:
		vol += pow(float(bl[1]), 3.0)
	var cards: Array = []
	for _i in range(n):
		var pick := rng.randf() * vol
		var bl: Array = blobs[0]
		for b2: Array in blobs:
			pick -= pow(float(b2[1]), 3.0)
			bl = b2
			if pick <= 0.0:
				break
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var o := 0.35 + 0.65 * sqrt(rng.randf())
		var at: Vector3 = (bl[0] as Vector3) + dir * float(bl[1]) * o
		cards.append([at, (at + Vector3(0, 0.15, 0)).normalized(), rng.randf(), o])
	return _cards_mesh(cards, m)

## a conifer: cards up a cone (the old cone mesh's shape: 6 high, 1.8 round at the foot,
## centred), more toward the foot, and one on the tip, round a dark solid cone a little
## smaller: a real conifer is dense, and through a gap you see more needles, not sky
func _card_cone(n: int, m: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var cards: Array = [[Vector3(0, 2.75, 0), Vector3.UP, 0.5, 1.0]]
	for _i in range(n - 1):
		var y := -2.7 + 5.3 * pow(rng.randf(), 0.8)
		var rmax := 1.8 * (3.0 - y) / 6.0
		var o := 0.4 + 0.6 * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var at := Vector3(cos(a) * rmax * o, y, sin(a) * rmax * o)
		cards.append([at, Vector3(cos(a), 0.35, sin(a)).normalized(), rng.randf(), o])
	var core: Array = []
	var sides := 8
	for j in range(sides):
		var a0 := TAU * j / sides
		var a1 := TAU * (j + 1) / sides
		var p0 := Vector3(cos(a0) * 1.15, -2.9, sin(a0) * 1.15)
		var p1 := Vector3(cos(a1) * 1.15, -2.9, sin(a1) * 1.15)
		var tip := Vector3(0, 2.3, 0)
		var n0 := Vector3(cos(a0), 0.25, sin(a0)).normalized()
		var n1 := Vector3(cos(a1), 0.25, sin(a1)).normalized()
		core.append_array([[p0, n0], [p1, n1], [tip, Vector3.UP]])
	var am := _cards_mesh(cards, m, core)
	am.custom_aabb = AABB(Vector3(-2.6, -3.6, -2.6), Vector3(5.2, 7.4, 5.2))
	return am

## A trunk (2.6 high, centred, like the cylinder it replaces) with smooth sides, bark UVs in
## metres and, if asked, branches forking up into the crown from its top half, which show
## through the gaps between the leaves
class Tubes:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	func tube(a: Vector3, b: Vector3, ra: float, rb: float, sides: int) -> void:
		var axis := (b - a).normalized()
		var side := axis.cross(Vector3.FORWARD if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var side2 := axis.cross(side)
		var L := a.distance_to(b)
		var base := v.size()
		for j in range(sides + 1):
			var ang := TAU * j / sides
			var out := side * cos(ang) + side2 * sin(ang)
			var along := -side * sin(ang) + side2 * cos(ang)
			for e in range(2):
				v.append(a.lerp(b, float(e)) + out * (ra if e == 0 else rb))
				nr.append(out)
				tg.append_array([along.x, along.y, along.z, 1.0])
				uv.append(Vector2(float(j) / sides * 0.9 * (ra + rb) / 0.27, L * float(e)))
				col.append(Color.WHITE)
		# (wound clockwise seen from outside, Godot's front: it was the other way round for
		# years -- every trunk drawn inside out, its near side culled and the far side's inside
		# showing, lit from behind: tests/backface_scan.gd, 24 Nov 2026)
		for j in range(sides):
			var i0 := base + j * 2
			idx.append_array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2])

	func mesh(m: Material) -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = nr
		a[Mesh.ARRAY_TANGENT] = tg
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = col
		a[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(0, m)
		return am

func _trunk_mesh(branches: int, m: Material) -> ArrayMesh:
	var t := Tubes.new()
	t.tube(Vector3(0, -1.3, 0), Vector3(0, 1.3, 0), 0.16, 0.11, 7)
	for i in range(branches):
		var ang := TAU * i / branches + 0.4
		var d := Vector3(cos(ang) * 0.75, 1.0, sin(ang) * 0.75).normalized()
		var s := Vector3(0, 0.45 + 0.3 * (i % 2), 0)
		t.tube(s, s + d * 1.6, 0.075, 0.03, 5)
	return t.mesh(m)

## Palm fronds as strips the frond shader cuts into leaflets: nine drooping, three young ones
## standing up in the middle. UV.x -1..1 across, UV.y 0 at the trunk .. 1 at the tip; the
## two halves fold up a little from the rib, as real fronds do.
func _frond_mesh(m: Material) -> ArrayMesh:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for i in range(12):
		var young := i >= 9
		var a := TAU * i / 9.0 + 0.3 * (i % 2) if not young else TAU * (i - 9) / 3.0 + 0.5
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var segs := 7
		var base := v.size()
		for s in range(segs + 1):
			var t := float(s) / segs
			var p := dir * 3.1 * t + Vector3(0, 2.1 * t - 2.8 * t * t, 0) if not young \
				else dir * 1.1 * t + Vector3(0, 2.0 * t - 0.4 * t * t, 0)
			var fwd := (dir * 3.1 + Vector3(0, 2.1 - 5.6 * t, 0)).normalized() if not young \
				else (dir * 1.1 + Vector3(0, 2.0 - 0.8 * t, 0)).normalized()
			var w := 0.48 if not young else 0.32
			var fold := Vector3(0, 0.14, 0)
			var up := side.cross(fwd).normalized()
			if up.y < 0.0:
				up = -up
			for k in [-1.0, 0.0, 1.0]:
				v.append(p + side * w * k + fold * absf(k))
				nr.append(up)
				uv.append(Vector2(k, t))
				col.append(Color.WHITE)
		for s in range(segs):
			var r0 := base + s * 3
			var r1 := r0 + 3
			idx.append_array([r0, r1, r0 + 1, r0 + 1, r1, r1 + 1, r0 + 1, r1 + 1, r0 + 2, r0 + 2, r1 + 1, r1 + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, m)
	return am
