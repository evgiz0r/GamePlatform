extends SceneTree
## The kinds of material the city is drawn with, as a browser has to compile them: each
## built-in material with its own mix of features is its own shader, and each shader is
## compiled again for every way it is drawn (on its own or instanced, casting shadows or not).
## A browser compiles one program for each, in the warm-up, at tens of ms apiece on a phone
## (tests/web_shaders.js counts them in a real browser). Lists the built-in materials by their
## compiled shader with what sets them apart and who uses them, and the game's own shaders
## with how they are drawn -- what to merge to compile fewer.
##   STREETS_BUILD_ALL=0 LEVEL=1 $GODOT --headless --path . -s res://game/streets/tests/shader_kinds.gd
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(2.0).timeout
	var std := {}      # shader rid -> {feat, users {name: count}, ways {}}
	var custom := {}   # shader -> {names, users, ways}
	for n: Node in g.world.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mats: Array = []
		if gi.material_override != null:
			mats.append(gi.material_override)
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if mats.is_empty() and mesh != null:
			for si in range(mesh.get_surface_count()):
				var m: Material = mesh.surface_get_material(si)
				if gi is MeshInstance3D and (gi as MeshInstance3D).get_surface_override_material(si) != null:
					m = (gi as MeshInstance3D).get_surface_override_material(si)
				if m != null:
					mats.append(m)
		var way := ("instanced" if gi is MultiMeshInstance3D else "single") + ("" if gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else "+shadow")
		var who := String(gi.name).rstrip("0123456789@")
		if who == "" or who.begins_with("@"):
			who = gi.get_parent().name if gi.get_parent() != null else "?"
		for m: Material in mats:
			if m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				var key := _features(bm)   # (as the engine keys its shader for one: by these flags)
				if not std.has(key):
					std[key] = {"feat": _features(bm), "users": {}, "ways": {}}
				std[key]["users"][who] = int(std[key]["users"].get(who, 0)) + 1
				std[key]["ways"][way] = true
			elif m is ShaderMaterial:
				var sm := m as ShaderMaterial
				var key := str(sm.shader.get_instance_id()) if sm.shader != null else "none"
				if not custom.has(key):
					var names: Array = []
					if sm.shader != null:
						for u: Dictionary in sm.shader.get_shader_uniform_list():
							names.append(u["name"])
					custom[key] = {"names": ",".join(names.slice(0, 5)), "users": {}, "ways": {}, "mats": {}}
				custom[key]["users"][who] = int(custom[key]["users"].get(who, 0)) + 1
				custom[key]["ways"][way] = true
				custom[key]["mats"][m.get_instance_id()] = true
	print("built-in materials: %d shaders" % std.size())
	for key: String in std:
		var e: Dictionary = std[key]
		print("  %-70s ways %s  users %s" % [e["feat"], ",".join(e["ways"].keys()), _top(e["users"])])
	print("the game's shaders: %d" % custom.size())
	for key: String in custom:
		var e: Dictionary = custom[key]
		print("  [%s] %d materials  ways %s  users %s" % [e["names"], e["mats"].size(), ",".join(e["ways"].keys()), _top(e["users"])])
	quit()

func _features(m: BaseMaterial3D) -> String:
	var f: Array = []
	f.append(["opaque", "alpha", "scissor", "hash", "prepass"][m.transparency])
	if m.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		f.append(["unshaded", "pixel", "vertex"][m.shading_mode])
	if m.vertex_color_use_as_albedo:
		f.append("vcol")
	if m.albedo_texture != null:
		f.append("tex")
	if m.emission_enabled:
		f.append("emit")
	if m.cull_mode != BaseMaterial3D.CULL_BACK:
		f.append(["back", "nocull", "front"][m.cull_mode])
	if m.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
		f.append("fade%d" % m.distance_fade_mode)
	if m.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		f.append("billboard%d" % m.billboard_mode)
	if m.no_depth_test:
		f.append("nodepth")
	if m.normal_enabled:
		f.append("normalmap")
	if m.roughness_texture != null or m.metallic_texture != null:
		f.append("rm-tex")
	if m.disable_receive_shadows:
		f.append("noshadow-recv")
	if m.shadow_to_opacity:
		f.append("shadow2op")
	if m.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX:
		f.append("spec%d" % m.specular_mode)
	if m.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY:
		f.append("diff%d" % m.diffuse_mode)
	if m.texture_filter != BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS:
		f.append("filter%d" % m.texture_filter)
	if m.uv1_triplanar:
		f.append("triplanar")
	if m.fixed_size:
		f.append("fixed")
	if m.use_point_size:
		f.append("points")
	if m.disable_ambient_light:
		f.append("noambient")
	if m.disable_fog:
		f.append("nofog")
	if m.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY:
		f.append("depth%d" % m.depth_draw_mode)
	if m.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
		f.append("blend%d" % m.blend_mode)
	if m.rim_enabled or m.clearcoat_enabled or m.anisotropy_enabled or m.ao_enabled or m.heightmap_enabled or m.subsurf_scatter_enabled or m.backlight_enabled or m.refraction_enabled or m.detail_enabled:
		f.append("extras")
	if m.metallic > 0.0:
		f.append("metal")
	return " ".join(f)

func _top(users: Dictionary) -> String:
	var ks: Array = users.keys()
	ks.sort_custom(func(a, b): return users[a] > users[b])
	var out: Array = []
	for k in ks.slice(0, 4):
		out.append("%s x%d" % [k, users[k]])
	return ", ".join(out) + (" +%d more" % (ks.size() - 4) if ks.size() > 4 else "")
