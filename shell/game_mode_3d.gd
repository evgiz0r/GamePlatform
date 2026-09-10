class_name GameMode3D extends GameMode
## THE 3D CONTRACT. A 3D game is still a one-Node2D scene that extends this instead of
## GameMode, so the menu, pause, score HUD, high scores, palette reskin and headless
## self-play all keep working exactly as they do for 2D games. In exchange this adds:
##
##   world       a Node3D to put your game in (its own World3D inside a SubViewport)
##   cam / sun   a camera and a key light, already set up; look_from() re-aims them
##   mat(role)   a StandardMaterial3D in a PALETTE ROLE that re-tints when /look changes
##   model("taxi", 3.0)     a glTF from assets/models/ scaled to 3 units, feet on the ground
##   add_box_collision(body, pivot)   a BoxShape3D sized from that model (things that fall)
##   Actor3D (shell/actor3d.gd)       animated characters: set_character() + play("Walk")
##   ground_point(screen)   where a tap on the screen lands on the Y=0 ground plane
##   to_screen(world)       the opposite: where a 3D point is on the 640x360 screen
##   track3d(node, "@")     Probe.track for Node3D -- bots and ASCII maps see 3D actors
##   shake3d() / hit3d()    camera juice (Juice.shake only knows Camera2D)
##
## Minimum viable 3D game:
##   extends GameMode3D
##   func start(_cfg): var m := MeshInstance3D.new(); m.mesh = BoxMesh.new();
##                     m.mesh.material = mat("player"); world.add_child(m)
##
## The ground is the X/Z plane; +Z is toward the camera (screen bottom) with the default
## look_from. world_area is the slice of that plane that maps onto play_area for the
## ASCII eye, so bots and reports stay in 2D screen space and need no 3D knowledge.

## World X/Z rectangle (x, z, width, depth) that fills play_area in the ASCII snapshot.
@export var world_area := Rect2(-12, -7, 24, 14)

const MODELS_DIR := "res://assets/models/"

var view: SubViewport
var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment

var _mats := {}            ## "role|emission" -> StandardMaterial3D
var _vc: SubViewportContainer
var _res_scale := 1.0      ## 3D pixels per design pixel (see _fit_resolution)
var _proxies: Array = []   ## {"ref": weakref(Node3D), "proxy": Node2D}
var _shake := 0.0
var _shake_decay := 14.0
var _cam_base := Transform3D()

func _ready() -> void:
	super()
	_build_view()
	Bus.palette_changed.connect(_retint)
	# Proxies and shake are synced from the tree's frame signal rather than _process so a
	# game that overrides _process without calling super() cannot silently break them.
	get_tree().process_frame.connect(_sync)

func _build_view() -> void:
	var vc := SubViewportContainer.new()
	_vc = vc
	vc.name = "View3D"
	# The kit's design space is 640x360 with nearest-neighbour filtering (pixel art). 3D
	# rendered at that size and blown up looks like a potato, so the viewport renders at
	# the real window resolution and is scaled DOWN into the design space with linear
	# filtering (_fit_resolution). Nothing in game code has to know: taps and to_screen()
	# stay in 640x360 coordinates.
	vc.stretch = false
	vc.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	vc.position = play_area.position
	# Games read taps in _input() on this Node2D, like every 2D game; the container must
	# not swallow them, and nothing inside the 3D view takes GUI input.
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vc)

	view = SubViewport.new()
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_disable_input = true
	view.handle_input_locally = false
	view.msaa_3d = Viewport.MSAA_4X   # smooth edges; supported by the Compatibility renderer
	vc.add_child(view)
	_fit_resolution()
	get_tree().root.size_changed.connect(_fit_resolution)

	world = Node3D.new()
	world.name = "World"
	view.add_child(world)

	env = Environment.new()
	# a soft gradient sky in palette colours (bg at the top, bg_alt at the horizon) so the
	# world has a horizon instead of a flat wall; re-tinted with the palette
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.35
	# Linear, not Filmic: filmic desaturates the bright emissive colours and a pink
	# "accent" came out orange, which defeats palette roles. Emissive materials at
	# 0.4-0.9 already read as neon against the dark background.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# No glow. In the Compatibility renderer, glow inside this SubViewport washed the whole
	# frame a flat bright purple (tested 4.7.2, shots.sh). Leave it off.
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	view.add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false   # cheap on phones; turn on per game if the look needs it
	view.add_child(sun)

	cam = Camera3D.new()
	cam.fov = 50.0
	cam.current = true
	view.add_child(cam)
	look_from(Vector3(0, 18, 15), Vector3.ZERO)
	_retint()

## Render the 3D view at the window's real pixel size (capped at 3x the design space, so a
## 4K monitor does not render 12 megapixels) and scale it down into play_area.
func _fit_resolution() -> void:
	var win := Vector2(get_window().size)
	var k := minf(win.x / play_area.size.x, win.y / play_area.size.y)
	_res_scale = clampf(floorf(k * 2.0) / 2.0, 1.0, 3.0)   # half steps: 1, 1.5, 2 ... 3
	view.size = Vector2i(play_area.size * _res_scale)
	_vc.size = Vector2(view.size)
	_vc.scale = Vector2.ONE / _res_scale

## Re-aim the camera. Also the base pose that shake3d() jitters around.
func look_from(pos: Vector3, target: Vector3) -> void:
	cam.position = pos
	cam.look_at(target, Vector3.UP)
	_cam_base = cam.transform

## ---- palette-driven materials ----------------------------------------------

## A material in a palette role. `emission` > 0 makes it glow (neon). Cached per role so a
## game can call this freely; all of them re-tint together when the palette changes.
func mat(role: String, emission: float = 0.4, rough: float = 0.6) -> StandardMaterial3D:
	var key := "%s|%.2f" % [role, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.roughness = rough
	m.set_meta("role", role)
	m.set_meta("emission", emission)
	_mats[key] = m
	_tint(m)
	return m

func _tint(m: StandardMaterial3D) -> void:
	var c := Palette.col(m.get_meta("role"))
	var e: float = m.get_meta("emission")
	m.albedo_color = c
	m.emission_enabled = e > 0.0
	m.emission = c
	m.emission_energy_multiplier = e

func _retint() -> void:
	if env != null:
		var bg := Palette.col("bg")
		var alt := Palette.col("bg_alt")
		env.background_color = bg
		var sky := env.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = bg
		sky.sky_horizon_color = alt.lerp(Palette.col("accent"), 0.18)
		sky.ground_horizon_color = alt
		sky.ground_bottom_color = bg
		sky.sky_curve = 0.25
	for k in _mats:
		_tint(_mats[k])

## ---- screen <-> world ---------------------------------------------------------

## Where a screen point (640x360 space, as delivered to _input) hits the plane Y=y.
## Returns Vector3.INF when the ray misses (looking at the sky); check with is_finite().
func ground_point(screen: Vector2, y: float = 0.0) -> Vector3:
	var p := (screen - play_area.position) * _res_scale
	var from := cam.project_ray_origin(p)
	var dir := cam.project_ray_normal(p)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var t := (y - from.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	return from + dir * t

## Screen position of a world point -- for Juice.text() and other 2D overlays.
func to_screen(w: Vector3) -> Vector2:
	return cam.unproject_position(w) / _res_scale + play_area.position

## world_area (X/Z) -> play_area, the mapping the ASCII eye and the bots live in.
func to_play(w: Vector3) -> Vector2:
	var fx := (w.x - world_area.position.x) / maxf(0.001, world_area.size.x)
	var fz := (w.z - world_area.position.y) / maxf(0.001, world_area.size.y)
	return play_area.position + Vector2(fx, fz) * play_area.size

func from_play(p: Vector2) -> Vector3:
	var f := (p - play_area.position) / play_area.size
	return Vector3(world_area.position.x + f.x * world_area.size.x, 0.0,
		world_area.position.y + f.y * world_area.size.y)

func clamp_to_area(w: Vector3, margin: float = 0.0) -> Vector3:
	var r := world_area.grow(-margin)
	return Vector3(clampf(w.x, r.position.x, r.end.x), w.y, clampf(w.z, r.position.y, r.end.y))

## ---- models (the 3D Blob.set_sprite) ------------------------------------------------

## A model by name from assets/models/<kit>/<name>.glb (any kit, first match; or a full
## res:// path), wrapped in a pivot whose origin is the model's bottom centre and scaled so
## its longest side is `size` world units. Missing file: a palette box of that size and a
## playtest warning, so a game never breaks over a filename. Read assets/INDEX.md first.
func model(name: String, size: float = 1.0, role_if_missing: String = "warn") -> Node3D:
	var pivot := Node3D.new()
	pivot.name = name.get_file().get_basename()
	var path := find_model(name)
	var inst: Node3D = null
	if path != "":
		var scn = load(path)
		if scn is PackedScene:
			inst = scn.instantiate()
	if inst == null:
		Probe.note("no model named '%s' in assets/models/ -- see assets/INDEX.md" % name)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * size
		bm.material = mat(role_if_missing, 0.4)
		box.mesh = bm
		box.position = Vector3(0, size * 0.5, 0)
		pivot.add_child(box)
		pivot.set_meta("aabb", AABB(Vector3(-size * 0.5, 0, -size * 0.5), Vector3.ONE * size))
		return pivot
	pivot.add_child(inst)
	fit(inst, size)
	pivot.set_meta("aabb", fitted_aabb(inst))
	return pivot

func find_model(name: String) -> String:
	if name.begins_with("res://"):
		return name if ResourceLoader.exists(name) else ""
	var d := DirAccess.open(MODELS_DIR)
	if d == null:
		return ""
	for kit in d.get_directories():
		for ext: String in ["glb", "gltf"]:
			var p := MODELS_DIR + kit + "/" + name + "." + ext
			if ResourceLoader.exists(p):
				return p
	return ""

## Bounding box of every mesh under `node`, in node-local space (ignores node's own transform).
static func aabb_of(node: Node3D) -> AABB:
	var out: Array = [AABB(), false]
	for c in node.get_children():
		_acc_aabb(c, Transform3D.IDENTITY, out)
	return out[0]

static func _acc_aabb(n: Node, xf: Transform3D, out: Array) -> void:
	if n is Node3D:
		xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var b: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
		out[0] = b if not out[1] else (out[0] as AABB).merge(b)
		out[1] = true
	for c in n.get_children():
		_acc_aabb(c, xf, out)

## Scale `inst` so its longest side (or its height if `by_height`) is `size`, and move it so
## the model is centred on X/Z with its lowest point at Y=0 of its parent. Returns the scale.
static func fit(inst: Node3D, size: float, by_height: bool = false) -> float:
	var b := aabb_of(inst)
	var ref := b.size.y if by_height else maxf(b.size.x, maxf(b.size.y, b.size.z))
	var s := size / ref if ref > 0.0001 else 1.0
	inst.scale = Vector3.ONE * s
	inst.rotation = Vector3.ZERO
	var c := b.get_center()
	inst.position = Vector3(-c.x * s, -b.position.y * s, -c.z * s)
	return s

## The box a fitted model occupies in its parent's space (centred, bottom at Y=0).
static func fitted_aabb(inst: Node3D) -> AABB:
	var b := aabb_of(inst)
	var s := inst.scale.x
	var size := b.size * s
	return AABB(Vector3(-size.x * 0.5, 0.0, -size.z * 0.5), size)

## Give a physics body a BoxShape3D matching a model() pivot that is its direct child.
## Add the pivot to the body first, keep the pivot unrotated (rotate the body instead).
func add_box_collision(body: CollisionObject3D, pivot: Node3D, shrink: float = 0.9) -> CollisionShape3D:
	var b: AABB = pivot.get_meta("aabb") if pivot.has_meta("aabb") else fitted_aabb(pivot.get_child(0))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = b.size * shrink
	cs.shape = bs
	cs.position = pivot.position + b.get_center()
	body.add_child(cs)
	return cs

## ---- Probe bridge ---------------------------------------------------------------

## Probe.track() for 3D nodes: a hidden Node2D proxy follows the node in play_area space,
## so bots (nearest "*", flee "x") and the ASCII maps work unchanged.
func track3d(node: Node3D, sym: String) -> void:
	if not Probe.enabled:
		return
	var proxy := Node2D.new()
	proxy.name = "probe_" + sym
	add_child(proxy)
	proxy.global_position = to_play(node.global_position)
	Probe.track(proxy, sym)
	_proxies.append({"ref": weakref(node), "proxy": proxy})

func _sync() -> void:
	if not is_inside_tree():
		return
	var kept: Array = []
	for e in _proxies:
		var n = e["ref"].get_ref()
		var proxy: Node2D = e["proxy"]
		if n == null or not is_instance_valid(n):
			if is_instance_valid(proxy):
				proxy.queue_free()
			continue
		proxy.global_position = to_play(n.global_position)
		kept.append(e)
	_proxies = kept

	if cam == null:
		return
	if _shake > 0.01:
		_shake = maxf(0.0, _shake - _shake_decay * get_process_delta_time() * _shake)
		var j := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.04
		cam.transform = _cam_base
		cam.transform.origin += _cam_base.basis * j
	elif cam.transform != _cam_base:
		cam.transform = _cam_base

## ---- juice ----------------------------------------------------------------------

## Camera shake in world units of jitter. 3-4 is a thud, 8 is an explosion.
func shake3d(strength: float = 4.0) -> void:
	_shake = maxf(_shake, strength)

## Shake + the shell's hitstop: the standard "something hit something" combo in 3D.
func hit3d(strength: float = 4.0) -> void:
	shake3d(strength)
	Juice.hitstop()
