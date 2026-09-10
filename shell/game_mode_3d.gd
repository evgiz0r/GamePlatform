class_name GameMode3D extends GameMode
## THE 3D CONTRACT. A 3D game is still a one-Node2D scene that extends this instead of
## GameMode, so the menu, pause, score HUD, high scores, palette reskin and headless
## self-play all keep working exactly as they do for 2D games. In exchange this adds:
##
##   world       a Node3D to put your game in (its own World3D inside a SubViewport)
##   cam / sun   a camera and a key light, already set up; look_from() re-aims them
##   mat(role)   a StandardMaterial3D in a PALETTE ROLE that re-tints when /look changes
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

var view: SubViewport
var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment

var _mats := {}            ## "role|emission" -> StandardMaterial3D
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
	vc.name = "View3D"
	vc.stretch = true
	vc.position = play_area.position
	vc.size = play_area.size
	# Games read taps in _input() on this Node2D, like every 2D game; the container must
	# not swallow them, and nothing inside the 3D view takes GUI input.
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vc)

	view = SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(play_area.size)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_disable_input = true
	view.handle_input_locally = false
	vc.add_child(view)

	world = Node3D.new()
	world.name = "World"
	view.add_child(world)

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
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
		env.background_color = Palette.col("bg")
	for k in _mats:
		_tint(_mats[k])

## ---- screen <-> world ---------------------------------------------------------

## Where a screen point (640x360 space, as delivered to _input) hits the plane Y=y.
## Returns Vector3.INF when the ray misses (looking at the sky); check with is_finite().
func ground_point(screen: Vector2, y: float = 0.0) -> Vector3:
	var p := screen - play_area.position
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
	return cam.unproject_position(w) + play_area.position

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
