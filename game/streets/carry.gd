extends RefCounted
## What people carry (moved out of streets.gd; `g` is the game).
## Things in people's hands and on their backs: a shopping bag or a handbag hanging from one
## hand, a backpack, a box held in front (the carrying walk had arms out round nothing). Each
## is a few boxes kept at a bone of the figure's skeleton (Held), so it goes with the hand or
## rides on the back; one mesh (one draw) each, shared, for the few who have one. (tests/people_carry.gd)
## what someone has: "" (nothing), "bag", "handbag", "backpack", or "box" for the carrying walk

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

func _what_carried(seed: int, carrying: bool) -> String:
	if carrying:
		return "box"
	var r := posmod(seed * 2654435761, 1000) / 1000.0
	return "bag" if r < 0.17 else ("handbag" if r < 0.27 else ("backpack" if r < 0.4 else ""))

var _carry_meshes := {}               ## the boxes' sizes, places and colours -> one mesh, shared
var _carry_mat: StandardMaterial3D = null

## one thing in one mesh (one draw, not one a box), its colours in the vertices: [size,
## position, colour] boxes, made once for each different set and shared
func _carry_mesh(h: Node3D, boxes: Array) -> void:
	var key := str(boxes)
	var mesh: ArrayMesh = _carry_meshes.get(key)
	if mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for bx: Array in boxes:
			var bm := BoxMesh.new()
			bm.size = bx[0]
			var arr := bm.get_mesh_arrays()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var c: Color = bx[2]   # (as is: converted to linear, as the batched kit's are, they drew darker)
			for i: int in arr[Mesh.ARRAY_INDEX]:
				st.set_color(c)
				st.set_normal(n[i])
				st.add_vertex(v[i] + (bx[1] as Vector3))
		mesh = st.commit()
		_carry_meshes[key] = mesh
	if _carry_mat == null:
		_carry_mat = StandardMaterial3D.new()
		_carry_mat.vertex_color_use_as_albedo = true
		_carry_mat.roughness = 0.8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _carry_mat
	h.add_child(mi)

## Things held, moved to their bones every frame after the animation (and PartSizes) has
## posed them. A hand's bag hangs straight down from the hand, whatever the arm's swing (on a
## BoneAttachment3D it tilted with the arm, flat as a sheet of paper); the back's turns with it.
class Held extends SkeletonModifier3D:
	var items := []   ## [bone index, holder (a child of the skeleton, in metres), upright]

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for it: Array in items:
			var pose := sk.get_bone_global_pose(it[0])
			var h: Node3D = it[1]
			var keep := h.scale
			h.transform = Transform3D(Basis() if it[2] else pose.basis.orthonormalized(), pose.origin)
			h.scale = keep

## A holder at a bone, in metres (the figure is fitted, i.e. scaled, and a child of the
## skeleton would take that on); moved there every frame by the skeleton's Held
func _bone_holder(a: Actor3D, bone: String, upright: bool) -> Node3D:
	var sks := a.model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var sk: Skeleton3D = sks[0]
	var bi := sk.find_bone(bone)
	if bi < 0:
		bi = sk.find_bone(g._people_maker().bone_for(bone))   # (the same place on people.gd's figures)
	if bi < 0:
		return null
	var held: Held = null
	for m in sk.get_children():
		if m is Held:
			held = m
	if held == null:
		held = Held.new()
		sk.add_child(held)   # (after PartSizes: run after it, so the bones are where they are drawn)
	var s: Vector3 = sk.global_transform.basis.get_scale()
	var h := Node3D.new()
	sk.add_child(h)
	h.scale = Vector3(1.0 / s.x, 1.0 / s.y, 1.0 / s.z)
	held.items.append([bi, h, upright])
	return h

func _carry(a: Actor3D, what: String, seed: int) -> void:
	if what == "" or a == null or a.model == null:
		return
	# people.gd's figures: the backpack upright (their chest bone's own axes are not the body's),
	# the box held by people.gd's Carry
	var newer := not a.model.find_children("*", "Skeleton3D", true, false).is_empty() 		and (a.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D).find_bone("spine_03") >= 0
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	var alt := Palette.col("bg_alt")
	var wn := Palette.col("warn")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 991
	var dark := [bg.lerp(alt, 0.3), g._natural(wn.lerp(bg, 0.7), 0.5), g._natural(Palette.col("player").lerp(bg, 0.6), 0.5),
		g._natural(Palette.col("hazard").lerp(bg, 0.55), 0.5), ink.lerp(alt, 0.6)]
	match what:
		"bag", "handbag":
			# hanging from the hand (the figure faces +z): flat side to the leg
			var h := _bone_holder(a, "Fist.L" if rng.randf() < 0.5 else "Fist.R", true)
			if h == null:
				return
			if what == "bag":   # a supermarket's thin white plastic, or a shop's paper or cloth bag
				var c: Color = [ink.lerp(alt, 0.12), ink.lerp(alt, 0.12), g._natural(wn.lerp(ink, 0.45), 0.4),
					g._natural(Palette.col("friend").lerp(bg, 0.4), 0.5)][rng.randi() % 4]
				var tall: float = [0.3, 0.34, 0.38][rng.randi() % 3]
				_carry_mesh(h, [[Vector3(0.11, tall, 0.27), Vector3(0, -0.07 - tall * 0.5, 0), c],
					[Vector3(0.02, 0.07, 0.1), Vector3(0, -0.04, 0), c.darkened(0.1)]])   # (and the handles)
			else:   # a handbag, its strap in the hand
				var c: Color = dark[rng.randi() % dark.size()]
				_carry_mesh(h, [[Vector3(0.1, 0.2, 0.27), Vector3(0, -0.15, 0), c],
					[Vector3(0.015, 0.06, 0.12), Vector3(0, -0.03, 0), c.darkened(0.3)]])
		"backpack":
			var h := _bone_holder(a, "Torso", newer)
			if h == null:
				return
			var c: Color = dark[rng.randi() % dark.size()]
			var z := -0.13 if newer else -0.165
			var y := -0.08 if newer else 0.06
			_carry_mesh(h, [[Vector3(0.3, 0.4, 0.15), Vector3(0, y, z), c],
				[Vector3(0.24, 0.16, 0.06), Vector3(0, y - 0.1, z - 0.095), c.darkened(0.2)]])   # (and its front pocket)
		"box":   # a cardboard box on the forearms, the hands under its front
			if newer:   # (people.gd's: the arms held round it, the box between the hands)
				if not g._ppl.box(a, g._natural(wn.lerp(bg, 0.35), 0.55)):
					return
				g._people_lod(a)
				return
			var h := _bone_holder(a, "Torso", false)
			if h == null:
				return
			_carry_mesh(h, [[Vector3(0.42, 0.28, 0.32), Vector3(0, -0.02, 0.36), g._natural(wn.lerp(bg, 0.45), 0.55)]])
	g._people_lod(a)

## A person in one piece. The figures are one mesh of six parts (skin, shirt, trousers, belt,
## face, hair), and each part is a surface of its own: a draw call, and another in the
## shadow pass, every frame -- 8 people in view were 48 of the 217 draws. Joined into one
## surface, with each vertex's part in its colour's red, and one material per person whose
## six colours are what the parts were, a person is one draw. The joined mesh is made once
## per figure and shared (a mesh per person would be ~0.7 MB each).
const PIECE_SHADER := """
shader_type spatial;
uniform vec4 parts[6];
uniform float fade_from = 1e6;   // gone past this distance...
uniform float fade_to = 1e6;     // ...dissolving in, a dither, from here
void fragment() {
	int i = clamp(int(COLOR.r * 8.0 + 0.5), 0, 5);
	ALBEDO = parts[i].rgb;
	ROUGHNESS = 0.85;
	float d = length((VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz);
	float keep = clamp((fade_from - d) / max(fade_from - fade_to, 0.001), 0.0, 1.0);
	if (keep < 0.999 && keep < fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))))) {
		discard;
	}
}
"""
var _piece_meshes := {}               ## a figure's mesh -> the same in one surface
var _piece_shader: Shader = null

func _one_piece(mi: MeshInstance3D) -> void:
	var src := mi.mesh
	if src == null or src.get_surface_count() < 2 or src.get_surface_count() > 6 or src.get_blend_shape_count() > 0:
		return
	if _piece_shader == null:
		_piece_shader = Shader.new()
		_piece_shader.code = PIECE_SHADER
	var one: ArrayMesh = _piece_meshes.get(src)
	if one == null:
		var verts := PackedVector3Array()
		var nrms := PackedVector3Array()
		var bones := PackedInt32Array()
		var wts := PackedFloat32Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for si in range(src.get_surface_count()):
			var arr := src.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var off := verts.size()
			if arr[Mesh.ARRAY_BONES] == null or (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() != v.size() * 4:
				return   # (not the 4-bone skinned figures this is for)
			verts.append_array(v)
			nrms.append_array(arr[Mesh.ARRAY_NORMAL])
			bones.append_array(arr[Mesh.ARRAY_BONES])
			wts.append_array(arr[Mesh.ARRAY_WEIGHTS])
			var part := PackedColorArray()
			part.resize(v.size())
			part.fill(Color(float(si) / 8.0, 0.0, 0.0))
			cols.append_array(part)
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			for k in ix:
				idx.append(k + off)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = nrms
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = wts
		arrays[Mesh.ARRAY_COLOR] = cols
		arrays[Mesh.ARRAY_INDEX] = idx
		one = ArrayMesh.new()
		one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_piece_meshes[src] = one
	var m := ShaderMaterial.new()
	m.shader = _piece_shader
	m.set_meta("piece", true)
	var parts: Array[Vector4] = []
	for si in range(6):
		var c := Color.WHITE
		if si < src.get_surface_count():
			var sm := mi.get_active_material(si) as BaseMaterial3D
			if sm != null:
				c = sm.albedo_color
		c = c.srgb_to_linear()
		parts.append(Vector4(c.r, c.g, c.b, 1.0))
	m.set_shader_parameter("parts", parts)
	for si in range(src.get_surface_count()):
		mi.set_surface_override_material(si, null)
	mi.mesh = one
	mi.set_surface_override_material(0, m)
