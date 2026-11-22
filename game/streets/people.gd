extends RefCounted
## The people: Quaternius' Universal Base Characters (CC0, people/body_*.gltf) moving with the
## Universal Animation Library's clips (CC0, people/moves.res, made by people/make_moves.gd).
## The free bodies come bare (made to be dressed by other packs), so they are dressed here,
## by the bone that moves each vertex most: chest, shoulders and upper arms (the forearms too
## for long sleeves) a shirt; hips and thighs (and calves, unless shorts) trousers; feet shoes;
## the rest skin, from the light skin texture times the person's own tone. Body, eyes,
## eyebrows and hair are joined into ONE mesh (each vertex's part in its colour's red), shared
## by everyone with the same body, hair and cut, with one material per person for its
## colours: one draw a person, as the kit's figures were. DEV.md "The people".
##
## streets.gd still makes every person as before (Actor3D.set_character, then _humanize);
## _humanize hands the Actor3D here, which swaps its model and AnimationPlayer for these. The
## game's clip names are kept: Walk, Idle, Run (the library's jog), Walk_Carry (the plain walk:
## its Push leans into a heavy load), SitDown (sitting), Roll.

const DIR := "res://game/streets/people/"
const HAIR_M := ["hair_simpleparted", "hair_buzzed", "hair_simpleparted", "hair_buzzed", "", "hair_beard"]
const HAIR_F := ["hair_long", "hair_buns", "hair_long", "hair_buzzedfemale", "hair_long"]
## parts: 0 skin, 1 shirt, 2 trousers, 3 shoes, 4 eyes, 5 eyebrows, 6 hair
const SHADER := """
shader_type spatial;
uniform sampler2D skin_tex : source_color, filter_linear_mipmap;
uniform sampler2D eye_tex : source_color, filter_linear_mipmap;
uniform sampler2D hair_tex : source_color, filter_linear_mipmap;
uniform vec4 cols[7];
uniform float fade_from = 1e6;   // gone past this distance...
uniform float fade_to = 1e6;     // ...dissolving in, a dither, from here
void fragment() {
	int i = clamp(int(COLOR.r * 8.0 + 0.5), 0, 6);
	vec3 c;
	float rough = 0.9;
	if (i == 0) {
		c = texture(skin_tex, UV).rgb * cols[0].rgb;
		rough = 0.6;
	} else if (i == 4) {
		c = texture(eye_tex, UV).rgb;
		rough = 0.3;
	} else if (i >= 5) {
		c = texture(hair_tex, UV).rgb * cols[i].rgb;
		rough = 0.75;
	} else {
		c = cols[i].rgb;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	float d = length((VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz);
	float keep = clamp((fade_from - d) / max(fade_from - fade_to, 0.001), 0.0, 1.0);
	if (keep < 0.999 && keep < fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))))) {
		discard;
	}
}
"""

var g: Node
var _scenes := {}        ## path -> PackedScene
var _joined := {}        ## "body|hair|sleeves|shorts" -> [ArrayMesh, Skin, hair texture]
var _libs := {}          ## "" / "talk" -> AnimationLibrary under the game's clip names
var _shader: Shader

func _init(game: Node) -> void:
	g = game

func on() -> bool:
	return OS.get_environment("STREETS_OLD_PEOPLE") != "1" and ResourceLoader.exists(DIR + "moves.res")

func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]

## the game's clip names over the library's: "talk" has the talking idle as its Idle
func _lib(kind: String) -> AnimationLibrary:
	if _libs.has(kind):
		return _libs[kind]
	var src: AnimationLibrary = load(DIR + "moves.res")
	var out := AnimationLibrary.new()
	for k: StringName in src.get_animation_list():
		out.add_animation(k, src.get_animation(k))
	# (copies, not the same Animation: Actor3D.play sets a clip's loop flag on the way in)
	# (Walk_Carry: the library's Push leans into a heavy load -- a pushchair or a box looked shoved)
	var alias := {"Run": "Jog_Fwd", "Walk_Carry": "Walk", "SitDown": "Sitting_Idle", "Death": "Roll"}
	if kind == "talk":
		alias["Idle"] = "Idle_Talking"
	for k: String in alias:
		if out.has_animation(k):
			out.remove_animation(k)
		out.add_animation(k, (src.get_animation(alias[k]) as Animation).duplicate())
	_libs[kind] = out
	return out

## Turn a made Actor3D (any of the kit's figures, its height set) into one of these people.
func make(a: Actor3D, seed: int) -> void:
	var female := String(a.character).contains("Female")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if a.model != null:
		a.remove_child(a.model)
		a.model.queue_free()
	var body := "body_female" if female else "body_male"
	var inst: Node3D = _scene(DIR + body + ".gltf").instantiate()
	a.add_child(inst)
	a.model = inst
	GameMode3D.fit(inst, a.height, true)
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var ap := AnimationPlayer.new()
	inst.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", _lib(""))
	a.anim = ap
	# a street's build, not a superhero's: narrower shoulders and chest (the neck given back,
	# so the head keeps its shape), broader or slighter from person to person
	var sizes = g.PartSizes.new()
	var nar := (0.86 if not female else 0.93) * rng.randf_range(0.95, 1.06)
	sizes.bones[sk.find_bone("spine_03")] = Vector3(nar, 1.0, 0.9)
	sizes.bones[sk.find_bone("neck_01")] = Vector3(1.0 / nar, 1.0, 1.0 / 0.9)
	sizes.bones[sk.find_bone("spine_02")] = Vector3(lerpf(nar, 1.0, 0.5), 1.0, 0.95)
	sk.add_child(sizes)
	var wd := rng.randf_range(0.94, 1.08)
	inst.scale *= Vector3(wd, 1.0, wd)
	# the look: from the game's palette-mixed ranges (_people_looks)
	var looks: Dictionary = g._people_looks()
	var pick := {}
	for k: String in looks:
		pick[k] = looks[k][rng.randi() % (looks[k] as Array).size()]
	var hairs: Array = HAIR_F if female else HAIR_M
	var hair: String = hairs[rng.randi() % hairs.size()]
	var long_sleeves := rng.randf() < 0.3
	var shorts := not female and rng.randf() < 0.25
	var j := _join(inst, sk, body, hair, long_sleeves, shorts)
	if j.is_empty():
		return
	var main: MeshInstance3D = null
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).to_lower().begins_with("superhero"):
			main = mi
		else:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
	main.mesh = j[0]
	main.skin = j[1]
	var m := ShaderMaterial.new()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	m.shader = _shader
	m.set_meta("piece", true)   # (streets.gd's _people_lod sets its fade)
	m.set_shader_parameter("skin_tex", load(DIR + ("skin_female.png" if female else "skin_male.png")))
	m.set_shader_parameter("eye_tex", load(DIR + "eye.png"))
	m.set_shader_parameter("hair_tex", j[2])
	var skin_c: Color = pick["skin"]
	var avg := SKIN_AVG.srgb_to_linear()
	var tone := skin_c.srgb_to_linear()
	# by brightness only, the texture's own skin hue kept: channel by channel, a greyish tone
	# over the texture's tiny blue (0.095 linear) tripled the blue -- grey-blue women
	var k := clampf(tone.get_luminance() / avg.get_luminance(), 0.42, 1.3)
	var f := Vector4(k, k, k, 1.0)
	var hair_c: Color = pick["hair"]
	var shoes: Color = (pick["belt"] as Color).darkened(0.2)
	var cols: Array[Vector4] = [f]
	for c: Color in [pick["shirt"], pick["pants"], shoes, Color.WHITE, hair_c.darkened(0.15), hair_c.lightened(0.25)]:
		var l := c.srgb_to_linear()
		cols.append(Vector4(l.r, l.g, l.b, 1.0))
	m.set_shader_parameter("cols", cols)
	main.set_surface_override_material(0, m)

## the skin textures' average colour (both bodies' light skin, measured: sRGB 0.66, 0.47, 0.34),
## to turn a person's tone into a factor on the texture (from the texture at run time it came
## out blue-white: a compressed texture read back is not its colours)
const SKIN_AVG := Color(0.66, 0.47, 0.34)

## Body, eyes, eyebrows and a hairstyle as one surface on the body's skin: [mesh, skin, hair
## texture], made once for each body, hair and cut
func _join(inst: Node3D, sk: Skeleton3D, body: String, hair: String, long_sleeves: bool, shorts: bool) -> Array:
	var key := "%s|%s|%s|%s" % [body, hair, long_sleeves, shorts]
	if _joined.has(key):
		return _joined[key]
	var main: MeshInstance3D = null
	var extra: Array = []   # [MeshInstance3D, part]
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name).to_lower()
		if nm.begins_with("superhero"):
			main = mi
		elif nm.begins_with("eyes"):
			extra.append([mi, 4])
		elif nm.begins_with("eyebrows"):
			extra.append([mi, 5])
	if main == null:
		return []
	var hair_inst: Node3D = null
	var hair_tex: Texture2D = null
	if hair != "":
		hair_inst = _scene(DIR + hair + ".gltf").instantiate()
		for mi: MeshInstance3D in hair_inst.find_children("*", "MeshInstance3D", true, false):
			extra.append([mi, 6])
			var hm := mi.mesh.surface_get_material(0) as StandardMaterial3D
			if hm != null and hm.albedo_texture != null:
				hair_tex = hm.albedo_texture
	if hair_tex == null:
		hair_tex = load(DIR + "hair_1.png")
	var skin: Skin = main.skin
	var bind_of := {}   # bone name -> the body skin's bind index
	for b in range(skin.get_bind_count()):
		bind_of[_bind_name(skin, b, sk)] = b
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var parts: Array = [[main, -1]]
	parts.append_array(extra)
	for pr: Array in parts:
		var mi: MeshInstance3D = pr[0]
		for si in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var we: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bo.is_empty() or v.is_empty():
				continue
			var per := bo.size() / v.size()
			var off := verts.size()
			# this mesh's bind indices -> the body's
			var remap := PackedInt32Array()
			var ms: Skin = mi.skin
			for b in range(ms.get_bind_count() if ms != null else 0):
				remap.append(int(bind_of.get(_bind_name(ms, b, sk), 0)))
			verts.append_array(v)
			nrms.append_array(arr[Mesh.ARRAY_NORMAL])
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			if uv.size() != v.size():
				uv.resize(v.size())
			uvs.append_array(uv)
			for i in range(v.size()):
				# 4 influences each (the body's 8 cut to its 4 strongest, renormalised)
				var top := []
				for k in range(per):
					top.append([we[i * per + k], bo[i * per + k]])
				top.sort_custom(func(x, y): return x[0] > y[0])
				var tw := 0.0
				for k in range(4):
					tw += float(top[k][0]) if k < top.size() else 0.0
				for k in range(4):
					if k < top.size():
						var bi: int = top[k][1]
						bones.append(remap[bi] if bi < remap.size() else bi)
						wts.append(float(top[k][0]) / maxf(tw, 0.0001))
					else:
						bones.append(0)
						wts.append(0.0)
				var part: int = pr[1]
				if part < 0:
					part = _cloth(_bind_name(ms, int(top[0][1]), sk), v[i].y, long_sleeves, shorts)
				cols.append(Color(float(part) / 8.0, 0.0, 0.0))
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			for k in ix:
				idx.append(k + off)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = wts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var one := ArrayMesh.new()
	one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if hair_inst != null:
		hair_inst.free()
	_joined[key] = [one, skin, hair_tex]
	return _joined[key]

func _bind_name(s: Skin, b: int, sk: Skeleton3D) -> String:
	if s == null or b < 0 or b >= s.get_bind_count():
		return ""
	var n := String(s.get_bind_name(b))
	return n if n != "" else sk.get_bone_name(s.get_bind_bone(b))

## what a body vertex is dressed in, by the bone that moves it most
func _cloth(bone: String, y: float, long_sleeves: bool, shorts: bool) -> int:
	if bone.begins_with("spine") or bone.begins_with("clavicle") or bone.begins_with("upperarm") \
			or (long_sleeves and bone.begins_with("lowerarm")):
		return 1
	if bone == "pelvis" or bone.begins_with("thigh") or (not shorts and bone.begins_with("calf")):
		return 2
	if bone.begins_with("foot") or bone.begins_with("ball"):
		return 3
	if bone.begins_with("neck") and y < 1.47:   # (the collar, round the neck's base; body units, T-pose)
		return 1
	return 0

## the bones things are held at, on these figures: a hand, the chest
static func bone_for(where: String) -> String:
	return {"Fist.L": "hand_l", "Fist.R": "hand_r", "Torso": "spine_03"}.get(where, where)
