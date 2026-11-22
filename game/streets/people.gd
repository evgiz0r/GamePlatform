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
	if (i <= 1) {   // skin or shirt: by the smooth field in green, so the collar is a line, not the triangles' zigzag
		i = COLOR.g > 0.5 ? 1 : 0;
	}
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

## Looking at a phone: the right hand up in front of the chest, the head bowed over it, on
## top of whatever the clip does (walking, standing). The axes were measured on these bones
## (tests: turning each 0.8 rad and reading where the hand and the head's up went): the upper
## arm and the forearm about their x bring the hand forward and up, +z on the forearm brings it
## in; the head about its x drops the chin.
class Phone extends SkeletonModifier3D:
	var upper := -1
	var fore := -1
	var head := -1
	var t := 0.0

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or upper < 0:
			return
		t += delta
		var glance := 0.06 * sin(t * 0.7)   # (now and then a little up from it)
		# (0.45 and 1.55 brought the hand to the mouth: eating, or a call, not reading)
		sk.set_bone_pose_rotation(upper, sk.get_bone_pose_rotation(upper) * Quaternion(Vector3(1, 0, 0), 0.22))
		sk.set_bone_pose_rotation(fore, sk.get_bone_pose_rotation(fore) * Quaternion(Vector3(1, 0, 0.45).normalized(), 1.15))
		sk.set_bone_pose_rotation(head, sk.get_bone_pose_rotation(head) * Quaternion(Vector3(1, 0, 0), 0.38 + glance))

## Carrying a box in front: both arms held still (a walk's swing would carry the hands off the
## box), the hands at its sides low in front, and the box kept between them, upright, every
## frame. Each arm's pose is the walk's own at mid-stride, where the two hands are level
## (1.05 s: at 0 the standing clip has the right arm back), turned by angles found by a search
## for hands at (+-0.15, 1.07, 0.3) body units, the forearms near level (DEV.md "The people").
class Carry extends SkeletonModifier3D:
	var arms := []   ## [bone, its rotation]
	var hl := -1
	var hr := -1
	var box: Node3D = null

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b: Array in arms:
			sk.set_bone_pose_rotation(b[0], b[1])
		if box != null and hl >= 0 and hr >= 0:
			var keep := box.scale
			box.transform = Transform3D(Basis(), (sk.get_bone_global_pose(hl).origin + sk.get_bone_global_pose(hr).origin) * 0.5)
			box.scale = keep

## Glancing at you: when you come within a few metres, in front of them or to a side, about
## half of the people turn their head to you for a couple of seconds -- the neck a little, the
## head the rest, about the skeleton's up (whatever the clip does) -- and then back, and do not
## look again until you have gone and come back. Turned in the skeleton's space, where the
## body faces +z (a backpack's -z is behind).
class Glance extends SkeletonModifier3D:
	static var at := Vector3(1e9, 0, 0)   ## you, in the world (people.gd's me_at, every frame)
	var neck := -1
	var head := -1
	var curious := true
	var held := 0.0          ## how long it has looked this time
	var spent := false       ## looked already; again only once you have gone
	var turn := 0.0          ## the head's turn now, radians, eased

	func _process_modification_with_delta(delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or head < 0:
			return
		var want := 0.0
		var d2 := sk.global_position.distance_squared_to(at)
		if d2 > 81.0:      # 9 m: gone, may look again next time
			spent = false
			held = 0.0
		elif curious and not spent and d2 < 49.0 and d2 > 0.5:
			var hp := sk.get_bone_global_pose(head).origin
			var d := sk.global_transform.affine_inverse() * at - hp
			var yaw := atan2(d.x, d.z)
			if absf(yaw) < 1.9:   # (not someone already behind them)
				want = clampf(yaw, -1.1, 1.1)
				held += delta
				if held > 2.4:
					spent = true
		if want == 0.0 and absf(turn) < 0.002:
			turn = 0.0
			return
		turn = move_toward(turn, want, delta * 2.6)
		for b: Array in [[neck, 0.35], [head, 0.65]]:
			if b[0] < 0:
				continue
			var gp := sk.get_bone_global_pose(b[0])
			sk.set_bone_global_pose(b[0], Transform3D(Basis(Vector3.UP, turn * float(b[1])) * gp.basis, gp.origin))

## the turns from the walk's mid-stride: [bone, axis, angle] (+x brings a hand forward and up
## on both arms; +z on the right arm, -z on the left, brings it in)
const CARRY_TURNS := [["upperarm_l", Vector3(1, 0, -0.3), 0.6], ["lowerarm_l", Vector3(1, 0, 0), 0.2],
	["upperarm_r", Vector3(1, 0, 0.6), 0.7], ["lowerarm_r", Vector3(1, 0, 0.2), 0.2]]

var g: Node
var _scenes := {}        ## path -> PackedScene
var _joined := {}        ## "body|hair|sleeves|shorts" -> [ArrayMesh, Skin, hair texture]
var _libs := {}          ## "" / "talk" -> AnimationLibrary under the game's clip names
var _shader: Shader

func _init(game: Node) -> void:
	g = game

## where you are, for Glance
func me_at(p: Vector3) -> void:
	Glance.at = p

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
		alias["SitDown"] = "Sitting_Talking"   # (a cafe's people seated at their table, talking)
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
	a._clip = ""   # (a person made again, as a child, would keep the old clip's name: play() skips a clip it thinks is on)
	# a street's build, not a superhero's: narrower shoulders and chest (the neck given back,
	# so the head keeps its shape), broader or slighter from person to person
	# who: a child (asked for by the caller, set_meta("child")), an older person (one in seven
	# grown-ups: grey hair, and streets.gd slows their walk), or anyone
	var child := a.has_meta("child")
	var old := not child and rng.randf() < 0.14
	if old:
		a.set_meta("old", true)
	var sizes = g.PartSizes.new()
	var nar := (0.86 if not female else 0.93) * rng.randf_range(0.95, 1.06) * (0.92 if child else 1.0)
	sizes.bones[sk.find_bone("spine_03")] = Vector3(nar, 1.0, 0.9)
	sizes.bones[sk.find_bone("neck_01")] = Vector3(1.0 / nar, 1.0, 1.0 / 0.9)
	sizes.bones[sk.find_bone("spine_02")] = Vector3(lerpf(nar, 1.0, 0.5), 1.0, 0.95)
	if child:   # a child's head is big for its body: the same body, smaller, the head kept larger
		sizes.bones[sk.find_bone("Head")] = Vector3.ONE * 1.22
	sk.add_child(sizes)
	var gl := Glance.new()
	gl.neck = sk.find_bone("neck_01")
	gl.head = sk.find_bone("Head")
	gl.curious = posmod(seed * 7919, 100) < 50   # (not from rng: a draw here would reshuffle everyone's clothes)
	sk.add_child(gl)   # (before the held things: they go where the bones end up)
	var wd := rng.randf_range(0.94, 1.08)
	inst.scale *= Vector3(wd, 1.0, wd)
	# the look: from the game's palette-mixed ranges (_people_looks)
	var looks: Dictionary = g._people_looks()
	var pick := {}
	for k: String in looks:
		pick[k] = looks[k][rng.randi() % (looks[k] as Array).size()]
	# not dressed in the skin's own colour (a pale shirt on pale skin read as bare to the waist):
	# the next of the colours instead (in order, no draw: the rest of the look stays the same)
	for part: String in ["shirt", "pants"]:
		var opts: Array = looks[part]
		var at := opts.find(pick[part])
		for n in range(opts.size()):
			var c: Color = opts[(at + n) % opts.size()]
			if _apart(c, _skin_seen(pick["skin"])) >= SKIN_APART:
				pick[part] = c
				break
	# and no cloth brighter than CLOTH_V: a cream shirt in the sun came out (1, 1, 0.81) on
	# screen, a pale yellow that read as bare skin (tests/people_glance.gd's _collar shots)
	for part: String in ["shirt", "pants"]:
		var c: Color = pick[part]
		if c.v > CLOTH_V:
			c.v = CLOTH_V
			pick[part] = c
	var hairs: Array = HAIR_F if female else HAIR_M
	if child:
		hairs = ["hair_buns", "hair_long", "hair_buzzedfemale"] if female else ["hair_simpleparted", "hair_buzzed"]
	elif old and not female:
		hairs = ["hair_buzzed", "", "hair_simpleparted"]
	var hair: String = hairs[rng.randi() % hairs.size()]
	var long_sleeves := rng.randf() < (0.45 if old else 0.3)
	# shorts for a quarter of the men and most boys; for women the same cut is a skirt (hips and
	# thighs in its colour, the calves bare), a third of them, some of those a dress
	var shorts := rng.randf() < (0.6 if child else (0.25 if not female else 0.34))
	var dress := female and shorts and rng.randf() < 0.35
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
	# by brightness only, the texture's own skin hue kept (_skin_seen): channel by channel, a
	# greyish tone over the texture's tiny blue (0.095 linear) tripled the blue -- grey-blue women
	var k := clampf(skin_c.srgb_to_linear().get_luminance() / SKIN_AVG.srgb_to_linear().get_luminance(), 0.42, 1.3)
	var f := Vector4(k, k, k, 1.0)
	var hair_c: Color = pick["hair"]
	if old:   # grey to white, from the palette's light and dark (greyed: no tint in it)
		hair_c = g._greyed(Palette.col("ink").lerp(Palette.col("bg"), rng.randf_range(0.1, 0.45)), 1.0)
	if dress:
		pick["pants"] = pick["shirt"]
	var shoes: Color = (pick["belt"] as Color).darkened(0.2)
	var cols: Array[Vector4] = [f]
	for c: Color in [pick["shirt"], pick["pants"], shoes, Color.WHITE, hair_c.darkened(0.15), hair_c.lightened(0.25)]:
		var l := c.srgb_to_linear()
		cols.append(Vector4(l.r, l.g, l.b, 1.0))
	m.set_shader_parameter("cols", cols)
	main.set_surface_override_material(0, m)

## the brightest a shirt or trousers may be (HSV value, sRGB)
const CLOTH_V := 0.72
## how far (sRGB, straight-line) clothes are kept from the skin's colour
const SKIN_APART := 0.2

## the skin as drawn: the texture's light skin times the tone's brightness factor (as make() does)
static func _skin_seen(tone: Color) -> Color:
	var avg := SKIN_AVG.srgb_to_linear()
	var k := clampf(tone.srgb_to_linear().get_luminance() / avg.get_luminance(), 0.42, 1.3)
	return Color(avg.r * k, avg.g * k, avg.b * k).linear_to_srgb()

static func _apart(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

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
	var nb := sk.find_bone("neck_01")
	var neck_at := sk.get_bone_global_rest(nb).origin if nb >= 0 else Vector3(0, 1.5, 0)
	var collar := neck_at.y - COLLAR_BELOW
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
				var cloth := 1.0   # (green: 1 dressed, 0 skin; at the collar, between them by height)
				if part < 0:
					var bn := _bind_name(ms, int(top[0][1]), sk)
					part = _cloth(bn, v[i].y, long_sleeves, shorts, collar)
					cloth = 0.0 if part == 0 else 1.0
					# round the neck, whichever bone moves a vertex (the chest's and the neck's
					# alternate there: by bone the line zigzagged), by its height
					if (part <= 1) and Vector2(v[i].x - neck_at.x, v[i].z - neck_at.z).length() < COLLAR_R and v[i].y > collar - 0.12:
						cloth = clampf(0.5 + (collar - v[i].y) / 0.03, 0.0, 1.0)
				cols.append(Color(float(part) / 8.0, cloth, 0.0))
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

## the collar: this far below the neck bone's root (body units, T-pose; the man's neck is
## 3.5 higher than the woman's, so one height for both bared the man's chest). The shader cuts
## skin from shirt on this line, from a field in each vertex's green, not on the triangles' edges
const COLLAR_BELOW := 0.015
const COLLAR_R := 0.13   ## how far round the neck's middle the line is cut by height

## what a body vertex is dressed in, by the bone that moves it most
func _cloth(bone: String, y: float, long_sleeves: bool, shorts: bool, collar: float) -> int:
	if bone.begins_with("spine") or bone.begins_with("clavicle") or bone.begins_with("upperarm") \
			or (long_sleeves and bone.begins_with("lowerarm")):
		return 1
	if bone == "pelvis" or bone.begins_with("thigh") or (not shorts and bone.begins_with("calf")):
		return 2
	if bone.begins_with("foot") or bone.begins_with("ball"):
		return 3
	if bone.begins_with("neck") and y < collar:   # (the collar, round the neck's base; body units, T-pose)
		return 1
	return 0

## the bones things are held at, on these figures: a hand, the chest
static func bone_for(where: String) -> String:
	return {"Fist.L": "hand_l", "Fist.R": "hand_r", "Torso": "spine_03"}.get(where, where)

## someone carrying a box (Carry): the arms held round it and the box between the hands;
## false when the figure is not one of these
func box(a: Actor3D, colour: Color) -> bool:
	if a == null or a.model == null or a.anim == null or not a.anim.has_animation("Walk"):
		return false
	var sks := a.model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return false
	var sk: Skeleton3D = sks[0]
	var walk: Animation = a.anim.get_animation("Walk")
	var c := Carry.new()
	for t: Array in CARRY_TURNS:
		var bi := sk.find_bone(t[0])
		var tr := -1
		for k in range(walk.get_track_count()):
			if walk.track_get_type(k) == Animation.TYPE_ROTATION_3D and String(walk.track_get_path(k)).ends_with(":" + String(t[0])):
				tr = k
		if bi < 0 or tr < 0:
			return false
		c.arms.append([bi, walk.rotation_track_interpolate(tr, 1.05) * Quaternion((t[1] as Vector3).normalized(), t[2])])
	c.hl = sk.find_bone("hand_l")
	c.hr = sk.find_bone("hand_r")
	sk.add_child(c)   # (after PartSizes, before Held)
	var s: Vector3 = sk.global_transform.basis.get_scale()
	var h := Node3D.new()
	sk.add_child(h)
	h.scale = Vector3(1.0 / s.x, 1.0 / s.y, 1.0 / s.z)   # (in metres)
	c.box = h
	# a cardboard box, the hands at its sides near the bottom, a little in front of its middle
	g._carry_mesh(h, [[Vector3(0.3, 0.26, 0.3), Vector3(0, 0.07, -0.08), colour],
		[Vector3(0.06, 0.012, 0.302), Vector3(0, 0.2, -0.08), colour.darkened(0.12)]])   # (and the tape across its top)
	return true

## someone looking at their phone (Phone): the pose, and a phone in the right hand
func phone(a: Actor3D) -> void:
	if a == null or a.model == null:
		return
	var sks := a.model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var ph := Phone.new()
	ph.upper = sk.find_bone("upperarm_r")
	ph.fore = sk.find_bone("lowerarm_r")
	ph.head = sk.find_bone("Head")
	if ph.upper < 0 or ph.fore < 0 or ph.head < 0:
		return
	sk.add_child(ph)   # (after PartSizes and before Held: the phone goes where the hand ends up)
	for m in sk.get_children():
		if m is Glance:
			(m as Glance).curious = false   # (eyes on the screen)
	var h: Node3D = g._bone_holder(a, "hand_r", true)
	if h == null:
		return
	# a dark slab across the palm, its face tipped up toward the eyes
	g._carry_mesh(h, [[Vector3(0.075, 0.012, 0.15), Vector3(0.02, 0.0, 0.06), g._greyed(Palette.col("bg"), 0.9)],
		[Vector3(0.065, 0.002, 0.13), Vector3(0.02, 0.007, 0.06), g._greyed(Palette.col("ink").lerp(Palette.col("player"), 0.3), 0.5)]])   # (its lit screen)
	a.set_meta("phone", true)
