extends SceneTree
## Where a frame's draw calls go, and what each way of cutting them buys. A browser on a slow
## laptop pays ~0.1 ms of CPU a draw call (WebGL's checks, ANGLE's Direct3D, Godot's own work in
## wasm): a work laptop's frames were 70-120 ms of drawing at 600-820 draws (22 Nov 2026), and
## no quality level lowered the count. At the start (or AT=x,z), still, quality 2, this counts
## the draws of the view and of the shadow pass (Viewport.get_render_info), then again with
## every draw range of REACH_FROM m or more scaled down (0.7, 0.5, 0.35), then with each kind of
## thing hidden in turn -- the draws each kind costs.
##   game/streets/tests/run.sh draw_budget 4        (a few minutes; STREETS_BUILD_ALL=1 default)
## Read: "reach 0.5: 412 draws (view 300, shadow 112), -204" is what that level would save.
var g: Node
const REACH_FROM := 150.0

func _initialize() -> void:
	_run()

var _cpu := 0.0   ## the last count's CPU time preparing and sending the 3D view's frame (ms, mean)
var _objs := 0

## draws of the whole frame, of the 3D view's own pass and its shadow pass; and (in _cpu) the
## CPU time the renderer spent on the 3D view a frame, the mean of 12 -- what a slow laptop's
## browser pays per draw and per object, as near as this machine shows it (llvmpipe rasterises
## on other threads; this is the submitting)
func _count() -> Vector3i:
	for i in range(4):
		await process_frame
	var vp: Viewport = g.view
	var rid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var t := 0.0
	for i in range(12):
		await RenderingServer.frame_post_draw
		t += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	_cpu = t / 12.0
	_objs = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var view := vp.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var shadow := vp.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return Vector3i(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), view, shadow)

var _base_cpu := 0.0
func _line(label: String, c: Vector3i, base: Vector3i) -> void:
	if c == base and _base_cpu == 0.0:
		_base_cpu = _cpu
	print("  %-40s %4d draws (view %4d, shadow %4d) %+5d · %5d objects · cpu %5.1f ms %+5.1f" % [label, c.x, c.y, c.z, c.x - base.x,
		_objs, _cpu, _cpu - _base_cpu])

func _kind(gi: GeometryInstance3D) -> String:
	var n: Node = gi
	while n != null and n != g.world:
		# (by its script's path: naming the class here compiles actor3d.gd before the
		# autoloads exist, and every person then fails to be made -- "Nonexistent function 'new'")
		if n is Skeleton3D or (n.get_script() != null and String(n.get_script().resource_path).ends_with("actor3d.gd")):
			return "people"
		n = n.get_parent()
	var m: Material = gi.material_override
	if m == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (gi as MeshInstance3D).mesh.surface_get_material(0)
	if m == null and gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null and (gi as MultiMeshInstance3D).multimesh.mesh != null:
		var mm := (gi as MultiMeshInstance3D).multimesh.mesh
		m = mm.surface_get_material(0) if mm.get_surface_count() > 0 else null
	var code := ""
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		code = (m as ShaderMaterial).shader.code
	if m == g._car_shader_mat:
		return "cars (parked, traffic)"
	if m == g._tone_material:
		return "batched (one mesh a square and range)"
	if m == g._wall_mat or m == g._roof_mat:
		return "walls and roofs"
	if m == g._ground_shader_mat or m == g._kerb_mat:
		return "ground and kerbs"
	if code.contains("crown") or code.contains("bark") or code.contains("frond") or g._tree_mats.has(m):
		return "trees"
	if gi is MultiMeshInstance3D:
		return "other multimeshes (kits)"
	return "other meshes"

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	if OS.get_environment("AT") != "":
		var p := OS.get_environment("AT").split(",")
		g._land_on_road(Vector2(float(p[0]), float(p[1])), 20.0, Vector2.ZERO)
	g._set_quality(2)
	g.set_physics_process(false)   # (everything holds still: the counts compare)
	await create_timer(1.0).timeout
	var all: Array = []
	for gi in g.world.find_children("*", "GeometryInstance3D", true, false):
		all.append(gi)
	print("DRAW BUDGET (level %s, at %s, quality 2): %d drawables" % [OS.get_environment("LEVEL"), str(g._pos.round()), all.size()])
	var base := await _count()
	_line("as it is", base, base)
	# by draw range: how many drawables have each, and what scaling the far ones buys
	var bands := {"none (always)": 0, "under 150 m": 0, "150-300 m": 0, "300-600 m": 0, "600 m and over": 0}
	for gi: GeometryInstance3D in all:
		var r := gi.visibility_range_end
		var k := "none (always)" if r <= 0.0 else ("under 150 m" if r < 150.0 else ("150-300 m" if r < 300.0 else ("300-600 m" if r < 600.0 else "600 m and over")))
		bands[k] += 1
	print("  draw ranges: %s" % str(bands))
	var saved: Array = []
	for gi: GeometryInstance3D in all:
		saved.append(gi.visibility_range_end)
	for f: float in [0.7, 0.5, 0.35]:
		for i in range(all.size()):
			if saved[i] >= REACH_FROM:
				(all[i] as GeometryInstance3D).visibility_range_end = saved[i] * f
		_line("reach %.2f (ranges %d m+ scaled)" % [f, int(REACH_FROM)], await _count(), base)
	for i in range(all.size()):
		(all[i] as GeometryInstance3D).visibility_range_end = saved[i]
	# the depth pre-pass: every opaque thing drawn once for depth, then again with its colour
	ProjectSettings.set_setting("rendering/driver/depth_prepass/enable", false)
	_line("no depth pre-pass", await _count(), base)
	ProjectSettings.set_setting("rendering/driver/depth_prepass/enable", true)
	_line("the pre-pass back", await _count(), base)
	# the sun's shadows (a shader of every material changes with them: measured, not a level)
	g.sun.shadow_enabled = false
	_line("no sun shadows (not a level: recompiles)", await _count(), base)
	g.sun.shadow_enabled = true
	g._set_quality(0)
	_line("quality 0 (as the ladder sets it)", await _count(), base)
	g._set_quality(2)
	_line("quality 2 again", await _count(), base)
	# by kind: each hidden in turn
	var kinds := {}
	for gi: GeometryInstance3D in all:
		var k := _kind(gi)
		if not kinds.has(k):
			kinds[k] = []
		kinds[k].append(gi)
	for k: String in kinds:
		var was: Array = []
		for gi: GeometryInstance3D in kinds[k]:
			was.append(gi.visible)
			gi.visible = false
		_line("without %s (%d)" % [k, kinds[k].size()], await _count(), base)
		for i in range(kinds[k].size()):
			(kinds[k][i] as GeometryInstance3D).visible = was[i]
	# the shadow pass: casters by kind (each caster in the shadow's box is a draw there)
	var off: Array = []
	for gi: GeometryInstance3D in all:
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and _kind(gi) != "walls and roofs" and _kind(gi) != "batched (one mesh a square and range)":
			off.append([gi, gi.cast_shadow])
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line("shadows only from walls, roofs, batches", await _count(), base)
	for e: Array in off:
		(e[0] as GeometryInstance3D).cast_shadow = e[1]
	print("DRAW BUDGET done")
	quit(0)
