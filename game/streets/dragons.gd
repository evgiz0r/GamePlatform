extends RefCounted
## Dragons over the town (the user: "Dragons fighting above the city and we watch the fight.
## The one dragon starts flying towards us and we hide behind a building"). Played by
## scenario.gd's "dragons" beat as one timeline of its own, in game time:
##   0 .. WATCH      from the street, looking up: two dragons circling the towers ahead, closing
##                   in and breathing fire at each other, drawing apart again
##   .. CLOSE        the camera up among the roofs, round the fight
##   .. DIVE         back on the street: the red one breaks off and comes straight at us
##   .. HIDE         the camera runs to the far side of the nearest building
##   .. OVER         it sweeps over the roof, low, roaring; then out again: it flies off
## The dragons are made with Blender (tools/blender/recipes/dragon_body.py, dragon_wing.py):
## a body and a wing, mirrored for the other side, flapped here about the shoulder. Fire is
## CPU particles (the Compatibility renderer), the roar a made sound. Traffic stops dead.

const WATCH := 16.0
const CLOSE := 26.0
const DIVE := 30.0
const HIDE := 32.0
const OVER := 36.5
const END := 42.0
const HIGH := 58.0            ## the fight's height over the ground (m)
const RING := 46.0            ## its circle's radius
const AHEAD := 150.0          ## the fight's middle, this far ahead of where we stand
const PASS_UP := 15.0         ## the dive goes this far over our heads...
const PASS_SIDE := 6.0        ## ...and this far to the side (through the lens, the camera was inside it)
const SCALE := 1.0            ## the models are made in metres

var g: Node
var t := 0.0
var on := false
var center := Vector3.ZERO    ## the fight's middle, on the ground under it
var viewer := Vector3.ZERO    ## where "we" stand
var hide_at := Vector3.ZERO   ## behind the building
var dragons: Array = []       ## {node, wl, wr, fire, pos, prev, ang, roar}
var cam: Camera3D = null
var said := {}                ## captions given (once each)
var events := {}              ## for tests: what happened, when

func _init(game: Node) -> void:
	g = game

func start(view_pos: Vector2, view_dir: Vector2) -> void:
	on = true
	t = 0.0
	var side := Vector2(-view_dir.y, view_dir.x)
	var hit: Dictionary = g._nearest_seg(view_pos, 20.0, true)
	var half := float((g._roads[int(hit["road"])] as Dictionary)["w"]) * 0.5 if not hit.is_empty() else 4.0
	var vp := view_pos + side * (half + 1.6)   # (on the pavement, not the road)
	# a spot with the sky clear in front: no post, sign or tree within a few metres (the first
	# stood behind a road sign that filled the view)
	for k in range(12):
		if g._push_out(vp, 3.0, true, false) == Vector2.ZERO:
			break
		vp += view_dir * 3.0
	viewer = Vector3(vp.x, g._h(vp) + 1.65, vp.y)
	var c := view_pos + view_dir * AHEAD
	center = Vector3(c.x, g._h(c), c.y)
	hide_at = _hide_spot(vp, view_dir)
	var reds := [g._real_col("red"), g._real_col("orange").lerp(g._real_col("yellow"), 0.3)]
	var greens := [g._real_col("green").darkened(0.15), g._real_col("yellow").lerp(g._real_col("green"), 0.4)]
	for k in range(2):
		dragons.append(_make(reds if k == 0 else greens, float(k) * PI))
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 4000.0
	g.world.add_child(cam)
	cam.make_current()
	# the street goes still: every car where it is
	if g._traffic != null:
		for car in g._traffic.cars:
			if car.alive:
				car.hit = maxf(float(car.hit), END + 5.0)
	events["start"] = t

func stop() -> void:
	on = false
	for d: Dictionary in dragons:
		if is_instance_valid(d["node"]):
			(d["node"] as Node).queue_free()
	dragons = []
	if cam != null and is_instance_valid(cam):
		cam.queue_free()
	cam = null
	if g.cam != null:
		g.cam.make_current()

## a caption (scenario.gd's _say) at the timeline's moments; true when it is over
func tick(dt: float, say: Callable) -> bool:
	if not on:
		return true
	t += dt
	for k in range(dragons.size()):
		_fly(dragons[k], k, dt)
	_shoot(dt)
	for at: float in [0.5, WATCH - 0.5, CLOSE, DIVE + 0.8, OVER + 1.5]:
		if t >= at and not said.has(at):
			said[at] = true
			var line: String = {0.5: "Over the towers, something huge. Two of them.",
				WATCH - 0.5: "They meet, burn, break apart, and come round again.",
				CLOSE: "The red one turns. It has seen us.", DIVE + 0.8: "Run -- behind the building!",
				OVER + 1.5: "It's gone over. For now."}[at]
			say.call(line, 4.0)
	if t >= END:
		stop()
		return true
	return false

## ---- the dragons ---------------------------------------------------------------------------------

func _make(cols: Array, ang: float) -> Dictionary:
	var root := Node3D.new()
	g.world.add_child(root)
	var body := _load("dragon_body")
	root.add_child(body)
	var wl := _load("dragon_wing")
	var wr := _load("dragon_wing")
	# the shoulders: Blender's (1.2, +-1.1, 1.0) are Godot's (1.2, 1.0, -+1.1); the right
	# wing is the left one mirrored across the body
	wl.position = Vector3(1.2, 1.0, -1.1)
	wr.position = Vector3(1.2, 1.0, 1.1)
	wr.scale = Vector3(1, 1, -1)
	root.add_child(wl)
	root.add_child(wr)
	var mats := {"paint": _mat(cols[0], 0.0), "paint2": _mat((cols[0] as Color).lightened(0.35), 0.0),
		"paint3": _mat(cols[1], 0.4), "dark": _mat(Color(0.1, 0.09, 0.09), 0.0)}
	for n: Node in [body, wl, wr]:
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			for si in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(si)
				var role := String(m.resource_name) if m != null else "paint"
				mi.set_surface_override_material(si, mats.get(role, mats["paint"]))
	var fire := _fire()
	fire.position = Vector3(9.4, 3.4, 0.0)   # (the open jaw)
	root.add_child(fire)
	var roar := AudioStreamPlayer3D.new()
	roar.stream = _roar_sound()
	roar.unit_size = 60.0
	roar.max_distance = 900.0
	roar.volume_db = linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8)))) + 2.0
	root.add_child(roar)
	return {"node": root, "wl": wl, "wr": wr, "fire": fire, "pos": center + Vector3(0, HIGH, 0), "prev": Vector3.ZERO,
		"ang": ang, "roar": roar, "flap": randf() * TAU}

func _load(name: String) -> Node3D:
	var ps := load("res://assets/models/made/%s.glb" % name) as PackedScene
	if ps == null:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		return box
	return ps.instantiate() as Node3D

func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m

## where dragon k is at the timeline's time: circling the fight, drawn together to clash, or
## (the red one) diving at the viewer and over the building
func _where(k: int) -> Vector3:
	var p := _orbit(k, t)
	if k != 0 or t < CLOSE:
		return p
	# the red one: from where it was at CLOSE, round toward us, at us, low over the roof, away
	var from := _orbit(0, CLOSE)
	var sd := Vector3(-(hide_at.z - viewer.z), 0, hide_at.x - viewer.x).normalized()
	var at_us := viewer + Vector3(0, PASS_UP, 0) + sd * PASS_SIDE
	var dir := Vector3(hide_at.x - viewer.x, 0, hide_at.z - viewer.z).normalized()
	var over := hide_at + Vector3(0, 22.0, 0) + dir * 4.0
	var away := hide_at + dir * 260.0 + Vector3(0, 90.0, 0)
	if t < DIVE:
		var u := smoothstep(CLOSE, DIVE, t)
		var mid := from.lerp(at_us, 0.5) + Vector3(0, 35.0, 0)
		return from.lerp(mid, u).lerp(mid.lerp(at_us, u), u)
	if t < OVER:
		var u := (t - DIVE) / (OVER - DIVE)
		var mid := at_us.lerp(over, 0.5) + Vector3(0, 6.0, 0)
		return at_us.lerp(mid, u).lerp(mid.lerp(over, u), u)
	return over.lerp(away, smoothstep(OVER, END, t))

## circling the fight's middle; every 8 s the two close in for a couple of seconds and part
func _orbit(k: int, when: float) -> Vector3:
	var ang := when * 0.42 + (0.0 if k == 0 else PI)
	var cyc := fmod(when, 8.0)
	var close := smoothstep(4.5, 6.0, cyc) * (1.0 - smoothstep(6.5, 7.8, cyc))
	var r := RING * (1.0 - 0.85 * close) + 10.0 * sin(when * 0.9 + k)
	var h := HIGH + 14.0 * sin(when * 0.6 + k * 1.7) + 12.0 * close
	return center + Vector3(cos(ang) * r, h, sin(ang) * r)

func _fly(d: Dictionary, k: int, dt: float) -> void:
	var p := _where(k)
	var prev: Vector3 = d["pos"]
	d["pos"] = p
	var node: Node3D = d["node"]
	node.position = p
	var vel := (p - prev) / maxf(dt, 0.001)
	if vel.length() > 0.5:
		# facing along its way (the model faces +X), banked into its turns
		var fwd := vel.normalized()
		var up := Vector3.UP
		var side := fwd.cross(up)
		if side.length() < 0.1:
			side = Vector3.BACK
		side = side.normalized()
		up = side.cross(fwd).normalized()
		var was: Vector3 = d.get("vprev", vel)
		var turn := Vector2(was.x, was.z).angle_to(Vector2(vel.x, vel.z)) if Vector2(was.x, was.z).length() > 0.1 else 0.0
		var bank := clampf(turn / maxf(dt, 0.001) * 0.35, -0.6, 0.6)
		node.basis = Basis(fwd, up, side).rotated(fwd, -bank).orthonormalized()
	d["vprev"] = vel
	# the wings: a slow heavy beat, faster when it climbs or dives
	var climb := clampf(absf(vel.y) / 20.0, 0.0, 1.0)
	d["flap"] = float(d["flap"]) + dt * (2.6 + 2.0 * climb)
	var a := sin(float(d["flap"])) * (0.55 + 0.2 * climb)
	(d["wl"] as Node3D).rotation = Vector3(a, 0, 0)
	(d["wr"] as Node3D).rotation = Vector3(a, 0, 0)

## fire: when the two close in, each breathes at the other; the red one at us as it dives
func _shoot(_dt: float) -> void:
	if dragons.size() < 2:
		return
	var cyc := fmod(t, 8.0)
	var duel := t < CLOSE and cyc > 5.2 and cyc < 6.8
	var dive := t > DIVE - 2.5 and t < DIVE + 0.6
	for k in range(2):
		var f: CPUParticles3D = dragons[k]["fire"]
		var want := duel or (k == 0 and dive)
		if want != f.emitting:
			f.emitting = want
			if want:
				events["fire"] = int(events.get("fire", 0)) + 1
				var roar: AudioStreamPlayer3D = dragons[k]["roar"]
				if not Audio.muted():
					roar.play()

func _fire() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 160
	p.lifetime = 0.9
	p.local_coords = false
	p.direction = Vector3(1, -0.15, 0)
	p.spread = 9.0
	p.initial_velocity_min = 26.0
	p.initial_velocity_max = 34.0
	p.gravity = Vector3(0, 3.0, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.5, 1.6))
	curve.add_point(Vector2(1, 2.4))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	# orange at the jaw, red, then smoke (added on top of a bright sky, the first went white)
	grad.set_color(0, Color(1.0, 0.72, 0.2, 1.0))
	grad.set_color(1, Color(0.22, 0.12, 0.1, 0.0))
	grad.add_point(0.3, Color(1.0, 0.38, 0.06, 0.95))
	grad.add_point(0.65, Color(0.55, 0.12, 0.04, 0.6))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	return p

func _roar_sound() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 2.2)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for k in range(n):
		var s := float(k) / rate
		var env := smoothstep(0.0, 0.25, s) * (1.0 - smoothstep(1.4, 2.2, s))
		var f := 70.0 + 40.0 * sin(s * 2.0) - 15.0 * s
		ph += TAU * f / rate
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.12)   # (a growl: low noise)
		buf[k] = env * (0.55 * tanh(2.5 * sin(ph)) + 0.6 * lp)
	return g._wav(buf, rate, false)

## behind the nearest building from where we stand, on the side away from the fight
func _hide_spot(vp: Vector2, view_dir: Vector2) -> Vector3:
	var best := Vector2.INF
	var bd := INF
	for bi: int in g._near(g._bld_hash, vp, 45.0, g.BLD_CELL):
		var box: Rect2 = g._bld_box[bi]
		var c := box.get_center()
		if c.distance_to(vp) < bd:
			bd = c.distance_to(vp)
			var half := maxf(box.size.x, box.size.y) * 0.5
			best = c - view_dir * (half + 3.0)   # (its far side from the fight ahead)
	if best == Vector2.INF:
		best = vp - view_dir * 25.0
	var out: Vector2 = g._push_out(best, 0.6, true, false)
	best += out
	return Vector3(best.x, g._h(best) + 1.65, best.y)

## ---- the camera ---------------------------------------------------------------------------------

func camera(dt: float) -> void:
	if cam == null or dragons.size() < 2:
		return
	var a: Vector3 = dragons[0]["pos"]
	var b: Vector3 = dragons[1]["pos"]
	var mid := a.lerp(b, 0.5)
	if t < WATCH:
		# from the street, looking up at the fight
		cam.position = viewer
		cam.fov = lerpf(50.0, 38.0, smoothstep(2.0, WATCH, t))
		_look(mid, dt)
	elif t < CLOSE:
		# up among the roofs, round the fight
		var u := (t - WATCH) / (CLOSE - WATCH)
		var ang := 0.7 + u * 1.4
		cam.fov = 58.0
		cam.position = center + Vector3(cos(ang) * 120.0, HIGH - 10.0, sin(ang) * 120.0)
		_look(mid, dt)
	elif t < DIVE:
		# back on the street: the red one coming
		cam.position = viewer
		cam.fov = 55.0
		_look(a, dt)
	elif t < HIDE:
		# running for it: from the street to behind the building, looking back over the shoulder
		var u := smoothstep(DIVE, HIDE, t)
		cam.position = viewer.lerp(hide_at, u) + Vector3(0, sin(u * PI * 6.0) * 0.08, 0)
		_look(a, dt)
	elif t < OVER + 1.0:
		# pressed to the wall, looking up: it sweeps over the roof
		cam.position = hide_at
		cam.fov = 70.0
		_look(a, dt)
	else:
		# a step out: it goes, over the town
		cam.position = hide_at.lerp(viewer, smoothstep(OVER + 1.0, END - 1.0, t) * 0.5)
		cam.fov = 55.0
		_look(a, dt)

var _aim := Vector3.ZERO
func _look(at: Vector3, dt: float) -> void:
	_aim = at if _aim == Vector3.ZERO else _aim.lerp(at, 1.0 - exp(-dt * 4.0))
	if cam.position.distance_to(_aim) > 0.5:
		cam.look_at(_aim, Vector3.UP)
