extends SceneTree
## What "getting the graphics ready" really compiles. The warm-up grouped the city's drawables
## by material (it now groups by code: `_shader_key`), but a browser compiles a shader per distinct shader CODE and
## variant, not per material: Godot's StandardMaterial3D generates one shader for every set of
## switches (its flags, modes, which textures are set -- not its colours or numbers), shared by
## all the materials that have that set; a ShaderMaterial compiles its Shader once. And each is
## compiled again as a variant for a multimesh (instancing, with or without per-copy colour /
## custom data) and for the shadow pass (when the node casts shadows).
## Prints: material kinds (what the warm-up counts), code kinds (what compiles), and the code
## kinds with the most materials folded in, and each code kind's switches when asked (LIST=1);
## then each shader code by name with the programs it needs -- one for each of drawn plain /
## instanced, and again for the shadow pass when it casts shadows -- which is what the
## browser compiles (light variants aside).
##   tests/run.sh warm_census 1
var g: Node
var _names := {}   # a distinctive line of each of the game's shaders -> the constant's name
var _codes := {}   # each shader constant's name -> its code

func _initialize() -> void:
	_run()

## the switches of a standard material: every stored bool / enum, and which textures are set
static func code_key(m: Material) -> String:
	if m == null:
		return "none"
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		return "shader:%d" % (sh.get_instance_id() if sh != null else 0)
	if m is ShaderMaterial or not m is BaseMaterial3D:
		return m.get_class()
	var parts: Array = [m.get_class()]
	for p: Dictionary in m.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var t := int(p["type"])
		var v = m.get(p["name"])
		if t == TYPE_BOOL and v:
			parts.append(p["name"])
		elif t == TYPE_INT and int(v) != 0 and not String(p["name"]).begins_with("render_priority"):
			parts.append("%s=%d" % [p["name"], v])
		elif t == TYPE_OBJECT and v != null and String(p["name"]) != "next_pass":
			parts.append(p["name"] + "+")
	return " ".join(parts)

## a code key's name: a shader by the game's constant holding its code, a standard
## material by its switches
func _name(ck: String, m: Material) -> String:
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		var code := (m as ShaderMaterial).shader.code
		for k: String in _codes:   # the whole code, as it is used (or with the far shade, or a #define first)
			if code == _codes[k] or code == g._with_far(_codes[k]) or code.ends_with(_codes[k]):
				return k
		for key: String in _names:
			if code.contains(key):
				return _names[key]
		return "shader (%s...)" % code.substr(0, 60).replace("\n", " ")
	return ck.replace("texture_filter=3 texture_repeat stencil_reference=1", "").replace("shading_mode=1", "").strip_edges()

func _material(gi: GeometryInstance3D) -> Material:
	var m: Material = gi.material_override
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
		mesh = (gi as MultiMeshInstance3D).multimesh.mesh
	if m == null and mesh != null and mesh.get_surface_count() > 0:
		m = mesh.surface_get_material(0)
		if m == null and gi is MeshInstance3D:
			m = (gi as MeshInstance3D).get_surface_override_material(0)
	return m

## the variant: instanced or not (and the multimesh's per-copy data), casting shadows or not
func _variant(gi: GeometryInstance3D) -> String:
	var v := "mesh"
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		v = "mm" + ("+col" if mm != null and mm.use_colors else "") + ("+cust" if mm != null and mm.use_custom_data else "")
	if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		v += " shadow"
	return v

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	for sc: Script in [g.get_script(), g._furn.get_script()]:
		var consts := sc.get_script_constant_map()
		for k: String in consts:
			if typeof(consts[k]) == TYPE_STRING and String(consts[k]).contains("shader_type"):
				var longest := ""
				for line: String in String(consts[k]).split("\n"):
					if line.strip_edges().length() > longest.length() and not line.strip_edges().begins_with("//"):
						longest = line.strip_edges()
				_names[longest] = k + "?"
				_codes[k] = String(consts[k])
	g._set_quality(2)   # (the browser's starting quality)
	await create_timer(0.5).timeout
	var mat_kinds := {}    # the warm-up's key -> nodes
	var code_kinds := {}   # code key + variant -> [nodes, {material ids}]
	var codes := {}        # code key alone -> materials
	var nodes := 0
	var progs := {}   # code key -> {"plain"/"instanced" + " shadow pass": true}
	var named := {}   # code key -> name
	var users := {}   # code key -> nodes
	for gi: GeometryInstance3D in g.world.find_children("*", "GeometryInstance3D", true, false):
		if not gi.visible:
			continue
		nodes += 1
		var m := _material(gi)
		var mk: String = g._shader_key(gi)
		mat_kinds[mk] = int(mat_kinds.get(mk, 0)) + 1
		var ck := code_key(m)
		var key := ck + " | " + _variant(gi)
		if not code_kinds.has(key):
			code_kinds[key] = [0, {}]
		code_kinds[key][0] += 1
		code_kinds[key][1][m.get_instance_id() if m != null else 0] = true
		if not progs.has(ck):
			progs[ck] = {}
			named[ck] = _name(ck, m) if not gi is Label3D else "Label3D"
		var inst := "instanced" if gi is MultiMeshInstance3D else "plain"
		progs[ck][inst] = true
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			progs[ck][inst + " shadow pass"] = true
		users[ck] = int(users.get(ck, 0)) + 1
		if not codes.has(ck):
			codes[ck] = {}
		codes[ck][m.get_instance_id() if m != null else 0] = true
	print("drawables %d: the warm-up's kinds %d, shader codes %d, codes x variants %d" % [nodes, mat_kinds.size(), codes.size(), code_kinds.size()])
	var rows: Array = []
	for k: String in code_kinds:
		rows.append([k, code_kinds[k][0], (code_kinds[k][1] as Dictionary).size()])
	rows.sort_custom(func(a, b): return a[2] > b[2] or (a[2] == b[2] and a[1] > b[1]))
	for r: Array in rows if OS.get_environment("LIST") != "" else rows.slice(0, 12):
		print("  %3d materials, %5d nodes: %s" % [r[2], r[1], r[0]])
	var total := 0
	var prow: Array = []
	for ck: String in progs:
		total += (progs[ck] as Dictionary).size()
		prow.append([named[ck], (progs[ck] as Dictionary).keys(), users[ck], (codes[ck] as Dictionary).size()])
	prow.sort_custom(func(a, b): return a[2] < b[2])
	print("programs to compile (shader codes x plain/instanced x shadow pass): %d" % total)
	for r: Array in prow:
		print("  %-44s %5d nodes, %2d materials: %s" % [r[0], r[2], r[3], ", ".join(r[1])])
	quit(0)
