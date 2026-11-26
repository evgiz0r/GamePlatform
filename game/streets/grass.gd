extends RefCounted
## Grass blades near the camera (moved out of streets.gd; `g` is the game).
## A lawn drawn flat looked like a green carpet from a walker's height. Blades on every lawn
## would be millions of triangles; instead one patch of them (4 x 4 m, GRASS_BLADES) repeated
## in a grid that moves with the camera, a square at a time, and the shader grows each blade
## only where grass grows -- the far-shadow picture's green (_build_far_shadows) -- at the
## ground's height there (the height grid as a texture, interpolated as _h does), shorter
## further off and gone by GRASS_REACH. Off at the lowest two qualities; a smaller grid at 2.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D mask : filter_linear, repeat_disable;   // green: where grass grows
uniform vec4 mask_rect = vec4(0.0);
uniform sampler2D hmap : filter_nearest, repeat_disable;  // the ground's height grid
uniform vec4 h_info = vec4(0.0, 0.0, 1.0, 0.0);           // its corner (x, z), its step, 1 if hilly
uniform ivec2 h_size = ivec2(1, 1);
uniform vec3 col_a : source_color = vec3(0.3, 0.5, 0.2);   // the lawn
uniform vec3 col_b : source_color = vec3(0.5, 0.5, 0.25);  // drier blades among it
uniform float greenness = 0.5;
uniform float reach = 18.0;
uniform int cut_n = 0;           // the garden paths near the camera (_grass_cuts): no blades on them
uniform vec4 cut_a[24];          // each one's middle (x, z) and its way along (x, z)
uniform vec2 cut_b[24];          // ... its half length and half width
varying float tip;
varying vec3 tint;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float ground(vec2 p) {   // as the game's _h: the grid's triangles
	if (h_info.w < 0.5) { return 0.0; }
	float fx = clamp((p.x - h_info.x) / h_info.z, 0.0, float(h_size.x) - 1.001);
	float fz = clamp((p.y - h_info.y) / h_info.z, 0.0, float(h_size.y) - 1.001);
	int i = int(fx);
	int j = int(fz);
	float ax = fx - float(i);
	float az = fz - float(j);
	float h00 = texelFetch(hmap, ivec2(i, j), 0).r;
	float h10 = texelFetch(hmap, ivec2(i + 1, j), 0).r;
	float h01 = texelFetch(hmap, ivec2(i, j + 1), 0).r;
	float h11 = texelFetch(hmap, ivec2(i + 1, j + 1), 0).r;
	if (ax + az <= 1.0) { return h00 + (h10 - h00) * ax + (h01 - h00) * az; }
	return h11 + (h01 - h11) * (1.0 - ax) + (h10 - h11) * (1.0 - az);
}
void vertex() {
	// a blade's three corners all sit at its root (VERTEX); UV says which corner (x across,
	// y up), UV2 is the blade's own two random numbers
	vec3 root = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = root.xz;
	float gy = ground(p) + (h_info.w > 0.5 ? 0.07 : 0.0) + 0.015;
	float d = distance(vec3(p.x, gy, p.y), CAMERA_POSITION_WORLD);   // (from up high: none)
	float m = textureLod(mask, (p - mask_rect.xy) * mask_rect.zw, 0.0).g;
	float n = noise(p / 70.0) * 0.65 + noise(p / 15.0) * 0.35;
	float wild = smoothstep(0.62 - greenness * 0.45, 0.78 - greenness * 0.4, n);
	float grow = m > 0.75 ? 1.0 : (m > 0.25 ? wild * 0.85 : 0.0);
	grow *= 1.0 - smoothstep(reach * 0.6, reach, d);
	for (int i = 0; i < cut_n; i++) {
		vec2 r = p - cut_a[i].xy;
		if (abs(dot(r, cut_a[i].zw)) < cut_b[i].x && abs(dot(r, vec2(-cut_a[i].w, cut_a[i].z))) < cut_b[i].y) {
			grow = 0.0;
		}
	}
	float h = (0.06 + 0.1 * UV2.x) * grow;
	float a = UV2.y * 6.2831853;
	vec3 side = vec3(cos(a), 0.0, sin(a));
	vec3 lean = vec3(-sin(a), 0.0, cos(a)) * (0.2 + 0.35 * UV2.x);
	float sway = sin(TIME * 1.7 + p.x * 0.31 + p.y * 0.23) * 0.15 + sin(TIME * 3.1 + p.x * 1.3) * 0.05;
	vec3 w = vec3(p.x, gy, p.y);
	if (h > 0.004) {
		w += side * UV.x * (0.011 + 0.007 * UV2.y) * (1.0 - UV.y)
			+ (vec3(0.0, 1.0, 0.0) + lean + vec3(sway, 0.0, sway * 0.6)) * UV.y * h;
	}
	VERTEX = w - MODEL_MATRIX[3].xyz;   // (the grid moves, it does not turn)
	NORMAL = vec3(0.0, 1.0, 0.0);
	tip = UV.y;
	tint = mix(col_a, col_b, step(0.82, fract(UV2.x * 7.3)) * 0.7 + (1.0 - clamp(m * 2.0 - 1.0, 0.0, 1.0)) * 0.25);
}
void fragment() {
	// (a blade's base as dark as the lawn under it read as black spikes: barely darker, and
	// the tips lighter than the lawn, as sunlit blades are)
	ALBEDO = tint * mix(0.9, 1.35, tip);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }   // (double-sided: seen from behind, the renderer turned it to the ground, and the blade went black)
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
"""
const GRASS_PATCH := 4.0             ## metres a patch of blades covers
const GRASS_BLADES := 520            ## blades a patch (about 32 a square metre)
const GRASS_REACH := 18.0            ## metres from the camera blades grow to
var _grass: MultiMeshInstance3D
var _grass_mat: ShaderMaterial

func _build_grass() -> void:
	if g._fs_tex == null and (not g._far_later or DisplayServer.get_name() == "headless"):
		return   # (no picture of where grass grows: a headless run)
	var b := Streets.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in range(GRASS_BLADES):
		var at := Vector3(rng.randf() * GRASS_PATCH, 0, rng.randf() * GRASS_PATCH)
		var u2 := Vector2(rng.randf(), rng.randf())
		b.tri(at, at, at, Vector3.UP, Color.WHITE, Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), u2)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	_grass_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	_grass_mat.shader = sh
	am.surface_set_material(0, _grass_mat)
	if g._hnx > 0:
		g._set_hmap(_grass_mat)
	_grass_mat.set_shader_parameter("reach", GRASS_REACH)
	_grass_mat.set_shader_parameter("greenness", 0.85 if String(g._place.get("look", "")) == "north" else 0.35)
	# the grid round the camera, nearest patches first (a smaller grid shows only the first)
	var k := int(ceil(GRASS_REACH / GRASS_PATCH)) + 1
	var cells: Array = []
	for j in range(-k, k):
		for i in range(-k, k):
			cells.append(Vector2i(i, j))
	cells.sort_custom(func(a: Vector2i, c: Vector2i) -> bool:
		return Vector2(a.x + 0.5, a.y + 0.5).length() < Vector2(c.x + 0.5, c.y + 0.5).length())
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = am
	mm.instance_count = cells.size()
	for n in range(cells.size()):
		var c: Vector2i = cells[n]
		mm.set_instance_transform(n, Transform3D(Basis(), Vector3(c.x * GRASS_PATCH, 0, c.y * GRASS_PATCH)))
	mm.custom_aabb = AABB(Vector3(-k * GRASS_PATCH, -600, -k * GRASS_PATCH), Vector3(2 * k * GRASS_PATCH, 1800, 2 * k * GRASS_PATCH))
	_grass = MultiMeshInstance3D.new()
	_grass.multimesh = mm
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.world.add_child(_grass)
	_grass_retint()
	_grass_quality()


func _grass_retint() -> void:
	if _grass_mat == null:
		return
	_grass_mat.set_shader_parameter("mask", g._fs_tex if g._fs_tex != null else g._fs_blank())
	_grass_mat.set_shader_parameter("mask_rect", g._fs_rect)
	var gr: Color = g._tone["grass"]
	_grass_mat.set_shader_parameter("col_a", gr)
	_grass_mat.set_shader_parameter("col_b", gr.lerp(g._tone.get("sand", gr), 0.45))

## how many of the patches show: all at the top quality, the nearer ones at 2, none below
func _grass_quality() -> void:
	if _grass == null:
		return
	_grass.visible = g._quality >= 2
	var all := _grass.multimesh.instance_count
	_grass.multimesh.visible_instance_count = all if g._quality >= 3 else int(all * 0.55)

## the grid under the camera, a patch at a time (each frame, with the sky)
func _grass_follow() -> void:
	if _grass == null or not _grass.visible:
		return
	var c := g.cam.global_position
	var at := Vector3(floorf(c.x / GRASS_PATCH) * GRASS_PATCH, 0, floorf(c.z / GRASS_PATCH) * GRASS_PATCH)
	if at != _grass.position:
		_grass.position = at
		_grass_cuts_near(Vector2(c.x, c.z))

## The front gardens' paths across their lawns, to keep the blades off (grass poked up
## through the slabs). The picture of where grass grows is a metre or two a pixel and drawn
## before most gardens are laid, so it cannot hold a 1.3 m path; the shader is handed the
## ones near the camera instead, as the grid moves (24 at most: about a street's worth).
var _cut_c := PackedVector2Array()    ## a path's middle
var _cut_u := PackedVector2Array()    ## its way along (unit)
var _cut_s := PackedVector2Array()    ## its half length, half width
var _cut_hash := {}

func _grass_cut(c: Vector2, u: Vector2, half_len: float, half_w: float) -> void:
	var i := _cut_c.size()
	_cut_c.append(c)
	_cut_u.append(u)
	_cut_s.append(Vector2(half_len, half_w))
	g._hash_add(_cut_hash, Rect2(c, Vector2.ZERO).grow(half_len + half_w), Streets.BLD_CELL, i)

func _grass_cuts_near(c: Vector2) -> void:
	if _grass_mat == null:
		return
	var near: Array = g._near(_cut_hash, c, GRASS_REACH + 2.0, Streets.BLD_CELL).duplicate()   # (one cell: the hash's own array)
	near.sort_custom(func(a: int, b: int) -> bool: return _cut_c[a].distance_squared_to(c) < _cut_c[b].distance_squared_to(c))
	var a: Array = []
	var b: Array = []
	for i: int in near.slice(0, 24):
		a.append(Vector4(_cut_c[i].x, _cut_c[i].y, _cut_u[i].x, _cut_u[i].y))
		b.append(_cut_s[i])
	while a.size() < 24:
		a.append(Vector4.ZERO)
		b.append(Vector2.ZERO)
	_grass_mat.set_shader_parameter("cut_a", a)
	_grass_mat.set_shader_parameter("cut_b", b)
	_grass_mat.set_shader_parameter("cut_n", mini(near.size(), 24))
