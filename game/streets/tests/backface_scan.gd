extends SceneTree
## Things that vanish from one side (24 Nov 2026). The overhead wires were one-sided ribbons in
## the square's batch, whose shader culls back faces: from the street under them they did not
## show at all, for weeks. This scan finds the whole family, whatever the thing: from SPOTS
## places on the streets round the start, four ways each, looking a little up, it draws the
## view, then again with everything painted flat (_paint): red wherever the nearest surface
## is a face seen from behind and its material culls backs -- a one-sided sheet seen from its
## back (a wire, a sign, a railing, a canopy from under it), which the game leaves out. A solid
## closed thing shows no red (its fronts hide its backs). Each view with more than a few red
## pixels is saved with them painted red on the real picture, worst first. A back face pressed
## flat against a front one (a parapet's inside on the same line as the wall's outside) is not
## one: back faces are drawn a hair (0.1% of the depth) further off, so the front wins. (A first try diffed
## the view against one with every shader recompiled two-sided: the lighting changes too, and
## every edge in the city lit up.)
##
##   OUT=/tmp/bf FULL=1 RES=960x540 game/streets/tests/run.sh backface_scan 1
##   (SPOTS=12 by default; LEVEL as for run.sh)
##
## Good (Givatayim, 24 views): none over BAD pixels. Small ones remain and are listed: a parked
## car's rear underside (~400), a garden wall's far top (~900), the far end of a car (~1,800). Before the trunks were wound
## the right way every view with a tree near had 5,000-100,000. Ends in one REGRESS line.
const BAD := 3000
var g: Node

func _initialize() -> void:
	_run()

func _img() -> Image:
	await RenderingServer.frame_post_draw
	return g.view.get_texture().get_image()

## every drawn thing in the world painted flat: black where we see a face's front, red where we
## see a face's back -- unless its own material draws both sides on purpose (leaves, flags,
## the rails' wires), then black whichever side. A closed solid never shows its back; a sheet
## seen from behind does, and that is what a culling material leaves out.
var _saved := {}
var _dbg_red: ShaderMaterial
var _dbg_black: ShaderMaterial
func _two_sided(m: Material) -> bool:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).cull_mode != BaseMaterial3D.CULL_BACK
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		var code: String = (m as ShaderMaterial).shader.code
		return code.contains("cull_disabled") or code.contains("cull_front")
	return false

func _paint(on: bool) -> void:
	if _dbg_red == null:
		for k in 2:
			var sh := Shader.new()
			sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;\nvoid fragment() { ALBEDO = %s; DEPTH = FRONT_FACING ? FRAGCOORD.z : FRAGCOORD.z * 0.999; }\n" % ("FRONT_FACING ? vec3(0.0) : vec3(1.0, 0.0, 0.0)" if k == 0 else "vec3(0.0)")
			var m := ShaderMaterial.new()
			m.shader = sh
			if k == 0:
				_dbg_red = m
			else:
				_dbg_black = m
	for n in g.world.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if on:
			var m: Material = gi.material_override
			if m == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
				m = (gi as MeshInstance3D).get_active_material(0)
			if m == null and gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null and (gi as MultiMeshInstance3D).multimesh.mesh != null:
				var mm: Mesh = (gi as MultiMeshInstance3D).multimesh.mesh
				m = mm.surface_get_material(0) if mm.get_surface_count() > 0 else null
			_saved[gi] = gi.material_override
			gi.material_override = _dbg_black if _two_sided(m) else _dbg_red
		elif _saved.has(gi):
			gi.material_override = _saved[gi]
	if not on:
		_saved.clear()

func _run() -> void:
	OS.set_environment("STREETS_CAM", "0,0,1.6,0,0")
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	while not g._tiles_todo.is_empty():
		await create_timer(0.5).timeout
	g._car.visible = false
	if DisplayServer.get_name() == "headless":
		print("REGRESS backface_scan: SKIP (needs drawing)")
		quit()
		return
	var spots := int(OS.get_environment("SPOTS")) if OS.get_environment("SPOTS") != "" else 12
	var rng := RandomNumberGenerator.new()
	rng.seed = 2411
	var start: Vector2 = g._pos
	var found: Array = []   # [changed pixels, name, image]
	var views := 0
	var tries := 0
	while views < spots * 4 and tries < spots * 10:
		tries += 1
		# a pavement spot: a random street's edge near the start
		var c := start + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(10.0, 220.0)
		var hit: Dictionary = g._nearest_seg(c, 40.0, true, true)
		if hit.is_empty():
			continue
		var r: Dictionary = g._roads[hit["road"]]
		var pts: PackedVector2Array = r["pts"]
		var along: Vector2 = (pts[int(hit["seg"]) + 1] - pts[int(hit["seg"])]).normalized()
		var side := along.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var p: Vector2 = (hit["q"] as Vector2) + side * (float(r["w"]) * 0.5 + 1.2)
		if g._push_out(p, 0.3, false, false) != Vector2.ZERO:
			continue
		for k in range(4):
			var yaw := along.angle() + k * PI * 0.5
			g._dev_cam[2] = 1.6
			g._dev_cam[4] = 12.0
			for i in 4:
				g._pos = p
				g._prev_pos = p
				g._yaw = yaw
				g._prev_yaw = yaw
				await process_frame
			var a: Image = await _img()
			_paint(true)
			await process_frame
			var b: Image = await _img()
			_paint(false)
			views += 1
			var n := 0
			for y in range(0, a.get_height()):
				for x in range(0, a.get_width()):
					var cb := b.get_pixel(x, y)
					if cb.r > 0.6 and cb.g < 0.3 and cb.b < 0.3:
						n += 1
						a.set_pixel(x, y, Color(1, 0, 0))
			if n > 40:
				found.append([n, "spot%02d_%d" % [views / 4, k], a, p, yaw])
	found.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) > int(y[0]))
	for i in range(mini(found.size(), 12)):
		var f: Array = found[i]
		(f[2] as Image).save_png(OS.get_environment("OUT") + "/" + String(f[1]) + ".png")
		print("  %s: %d pixels only from behind (at %s, heading %.0f deg)" % [f[1], f[0], (f[3] as Vector2).round(), rad_to_deg(float(f[4]))])
	var worst: int = int(found[0][0]) if not found.is_empty() else 0
	print("REGRESS backface_scan: %s (%d views, %d with over 40 pixels seen only from behind; the worst %d want under %d)" % ["PASS" if worst < BAD else "FAIL", views, found.size(), worst, BAD])
	quit()
