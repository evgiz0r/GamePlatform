extends GameMode3D
## me -- a stand-in 3D avatar of the person this kit belongs to, filmed doing four things:
## walking down a street, waving, dancing, and teaching at a whiteboard. Not a game: each
## "level" is one short scene that plays itself, made to be recorded with
##   tools/record_video.sh me <level> <seconds> out.mp4
## See GAME.md for what was asked and DEV.md for how the poses work.
##
## The body is the kit's Quaternius person (assets/characters3d/), dressed to match the
## photos. Its clips give the walk; the wave, the dance and the teaching are posed by hand
## every frame on top of a clip (_pose_*), aiming bones at directions in the avatar's own
## space (aim()). When a real-likeness model of the person arrives (a .glb with a humanoid
## skeleton), BODY_* below is where it goes in.

const BODY := "Casual2_Male"
const TALL := 1.78
## Clothes and hair, from the photos. These are a real person's colours, not the game's
## look, so they stay fixed when the palette is swapped (the set around him still reskins).
const SHIRT := Color(0.50, 0.11, 0.07)     ## the brick-red V-neck
const TROUSERS := Color(0.07, 0.07, 0.08)
const HAIR := Color(0.24, 0.15, 0.09)      ## short brown
const SKIN := Color(0.80, 0.58, 0.46)
const BELT := Color(0.12, 0.09, 0.07)

const LEVELS := [
	{"name": "walk", "secs": 10.0},
	{"name": "wave", "secs": 7.0},
	{"name": "dance", "secs": 12.0},
	{"name": "teach", "secs": 17.0},
]

var me: Actor3D
var sk: Skeleton3D
var scene := "walk"
var t := 0.0
var secs := 10.0
var filming := false
var _bones := {}
var _lights: Array[OmniLight3D] = []
var _board_lines: Array = []    ## {"label": Label3D, "text": String, "start": Vector3}
var _cam_from := Vector3.ZERO
var _cam_to := Vector3.ZERO

func _ready() -> void:
	title = "me"
	world_area = Rect2(-8, -4, 16, 8)
	super()

func start(config: Dictionary) -> void:
	var n := clampi(int(config.get("level", 1)), 1, LEVELS.size())
	Flow.current_config["level"] = n
	scene = LEVELS[n - 1]["name"]
	secs = LEVELS[n - 1]["secs"]
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 25.0
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.9
	env.ambient_light_energy = 0.4
	_build_studio()
	_build_me()
	match scene:
		"walk": _build_street()
		"dance": _build_dance_floor()
		"teach": _build_board()
	_tick(0.0)

func film_ready() -> bool:
	return me != null

func film_mode(on: bool) -> void:
	filming = on
	if on and not OS.has_feature("web"):
		view.msaa_3d = Viewport.MSAA_8X
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)

func film_done() -> bool:
	return t > secs + 0.3

## ---- the body -------------------------------------------------------------------

const PART_SIZES := {
	"Head": Vector3(0.64, 0.64, 0.64),
	"Fist.L": Vector3(0.7, 0.7, 0.7), "Fist.R": Vector3(0.7, 0.7, 0.7),
	"Foot.L": Vector3(0.85, 0.85, 0.85), "Foot.R": Vector3(0.85, 0.85, 0.85),
	"UpperLeg.L": Vector3(1.0, 1.16, 1.0), "UpperLeg.R": Vector3(1.0, 1.16, 1.0),
	"Abdomen": Vector3(1.0, 1.06, 1.0),
}

class PartSizes extends SkeletonModifier3D:
	var bones := {}   ## bone index -> scale
	func _process_modification_with_delta(_delta: float) -> void:
		var s := get_skeleton()
		if s == null:
			return
		for i: int in bones:
			s.set_bone_pose_scale(i, bones[i])

func _build_me() -> void:
	me = Actor3D.new()
	world.add_child(me)
	me.set_character(BODY, TALL)
	track3d(me, "@")
	sk = me.find_child("Skeleton3D", true, false) as Skeleton3D
	if me.anim != null:
		# poses are laid over the clip every frame, so the clip must be advanced by hand
		# first (_tick), or it would overwrite them after we set them
		me.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_dress()
	if sk != null:
		for i in sk.get_bone_count():
			_bones[sk.get_bone_name(i)] = i
		# a grown-up's proportions instead of the cartoon's (the numbers the kit's street
		# people use): kept by a modifier, since the clip resets every bone's scale each frame
		var sizes := PartSizes.new()
		for bone: String in PART_SIZES:
			if _bones.has(bone):
				sizes.bones[_bones[bone]] = PART_SIZES[bone]
		sk.add_child(sizes)
		me.model.scale *= 1.06   # back to his height: the smaller head took some off

func _dress() -> void:
	# "Face" is the cartoon's big white eyes: a deeper shade of the skin reads as features
	var cols := {"Skin": SKIN, "Shirt": SHIRT, "Pants": TROUSERS, "Belt": BELT, "Hair": HAIR, "Face": SKIN.darkened(0.42)}
	for mi: MeshInstance3D in me.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null or not cols.has(src.resource_name):
				continue
			var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = cols[src.resource_name]
			m.roughness = 0.85 if src.resource_name != "Hair" else 0.7
			mi.set_surface_override_material(s, m)

## Point bone `bone` (its +Y, which runs along the limb) toward `dir`, given in the avatar's
## own space: +X its left, +Y up, +Z the way it faces. `w` blends from the clip's pose (0) to
## fully aimed (1). Parents first: a child's position follows its parent's new pose.
func aim(bone: String, dir: Vector3, w: float = 1.0) -> void:
	if sk == null or not _bones.has(bone) or w <= 0.0:
		return
	var i: int = _bones[bone]
	var g := sk.get_bone_global_pose(i)
	var to_sk := (sk.global_basis.orthonormalized().inverse() * me.global_basis.orthonormalized())
	var d := (to_sk * dir).normalized()
	var cur := g.basis.y.normalized()
	if cur.dot(d) > 0.9999:
		return
	var q := Quaternion(cur, d)
	q = Quaternion.IDENTITY.slerp(q, clampf(w, 0.0, 1.0))
	g.basis = Basis(q) * g.basis
	sk.set_bone_global_pose(i, g)

## Turn a bone about an axis in the avatar's space, by `deg` degrees (on top of the clip).
func twist(bone: String, axis: Vector3, deg: float) -> void:
	if sk == null or not _bones.has(bone) or absf(deg) < 0.01:
		return
	var i: int = _bones[bone]
	var g := sk.get_bone_global_pose(i)
	var to_sk := (sk.global_basis.orthonormalized().inverse() * me.global_basis.orthonormalized())
	g.basis = Basis((to_sk * axis).normalized(), deg_to_rad(deg)) * g.basis
	sk.set_bone_global_pose(i, g)

## Reach for a world point with an arm ("L" or "R"): the upper arm toward it, bent a little,
## the forearm straight at it. Good enough for pointing and writing within arm's length.
func reach(side: String, target: Vector3, w: float = 1.0, bend: float = 0.25) -> void:
	if sk == null or not _bones.has("UpperArm." + side):
		return
	var sh := sk.global_transform * sk.get_bone_global_pose(_bones["UpperArm." + side]).origin
	var d := me.global_basis.orthonormalized().inverse() * (target - sh)
	var down := Vector3(0, -1, 0)
	aim("UpperArm." + side, d.normalized() * (1.0 - bend) + down * bend, w)
	var el := sk.global_transform * sk.get_bone_global_pose(_bones["LowerArm." + side]).origin
	var d2 := me.global_basis.orthonormalized().inverse() * (target - el)
	aim("LowerArm." + side, d2, w)
	aim("Fist." + side, d2, w)

## ---- the scenes ---------------------------------------------------------------

func _process(delta: float) -> void:
	_tick(delta)

func _tick(delta: float) -> void:
	if me == null:
		return
	t += delta
	match scene:
		"walk": _walk()
		"wave": _wave()
		"dance": _dance()
		"teach": _teach()
	if me.anim != null:
		me.anim.advance(delta)
	match scene:
		"wave": _pose_wave()
		"dance": _pose_dance()
		"teach": _pose_teach()
	if t > secs + 1.5 and not filming:
		t = 0.0   # (in the menu, loop the scene)
		_board_reset()

static func ease01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## 0 before a, ramps to 1 by a+r, holds, ramps back to 0 from b-r to b.
static func window(x: float, a: float, b: float, r: float = 0.5) -> float:
	return ease01((x - a) / r) * (1.0 - ease01((x - (b - r)) / r))

# walk: down the pavement past the lamps, the camera trucking alongside
const WALK_SPEED := 1.35
func _walk() -> void:
	me.play("Walk", true, 1.0)
	var x := -6.5 + WALK_SPEED * t
	me.position = Vector3(x, 0.14, 0.0)
	me.face(Vector3(1, 0, 0))
	var cx := x + 0.6
	look_from(Vector3(cx + 1.4, 1.45, 3.3), Vector3(x + 0.3, 0.95, 0.0))

# wave: stands, notices the camera, waves three or four times
func _wave() -> void:
	me.play("Idle", true, 1.0)
	me.position = Vector3.ZERO
	me.rotation = Vector3(0, deg_to_rad(lerpf(-25.0, 0.0, ease01(t / 1.2))), 0)
	var k := ease01(t / secs)
	look_from(Vector3(0.3, 1.5, lerpf(3.6, 2.5, k)), Vector3(0, 1.15, 0))

func _pose_wave() -> void:
	var w := window(t, 1.0, secs - 0.8, 0.6)
	var s := sin((t - 1.0) * 9.0)
	# right arm out and up, forearm up, swinging side to side from the elbow
	aim("UpperArm.R", Vector3(-0.85, 0.45, 0.25), w)
	aim("LowerArm.R", Vector3(-0.15 + 0.45 * s, 1.0, 0.2), w)
	aim("Fist.R", Vector3(-0.1 + 0.6 * s, 1.0, 0.25), w)
	twist("Head", Vector3(0, 0, 1), -6.0 * w)   # a friendly tilt
	twist("Head", Vector3(1, 0, 0), 4.0 * sin(t * 2.0) * w)

# dance: 120 beats a minute on a lit floor, two moves borrowed from the photos -- fists
# pumping in turn, then one finger to the ceiling with the other hand pointing across
const BPM := 120.0
func _dance() -> void:
	me.play("Idle", true, 1.0)
	var beat := t * BPM / 60.0
	var ph := beat * PI
	me.position = Vector3(0.12 * sin(ph * 0.5), 0.05 * absf(sin(ph)), 0)
	me.rotation = Vector3(0, deg_to_rad(14.0 * sin(ph * 0.5)), 0)
	var a := 0.9 * sin(t * 0.45)   # swing round him and back, never behind
	look_from(Vector3(2.9 * sin(a), 1.45 + 0.15 * sin(t * 0.7), 2.9 * cos(a)), Vector3(0, 1.0, 0))
	for i in _lights.size():
		var L := _lights[i]
		L.light_energy = 1.2 + 1.6 * maxf(0.0, sin(ph + i * PI * 0.5))

func _pose_dance() -> void:
	var beat := t * BPM / 60.0
	var ph := beat * PI
	var bar := int(beat / 4.0)
	var w := ease01(t / 0.6)
	twist("Torso", Vector3(0, 1, 0), -10.0 * sin(ph * 0.5) * w)
	twist("Torso", Vector3(0, 0, 1), 5.0 * sin(ph * 0.5) * w)
	twist("Head", Vector3(1, 0, 0), 8.0 * absf(sin(ph)) * w)
	if bar % 3 != 2:
		# fists pumping: elbows tucked, forearms up, alternating on the beat
		var l := 0.5 + 0.5 * sin(ph)
		var r := 1.0 - l
		aim("UpperArm.L", Vector3(0.35, -0.75, 0.35 + 0.25 * l), w)
		aim("LowerArm.L", Vector3(0.05, 0.2 + 0.9 * l, 1.0), w)
		aim("Fist.L", Vector3(0.0, 0.5 + l, 0.8), w)
		aim("UpperArm.R", Vector3(-0.35, -0.75, 0.35 + 0.25 * r), w)
		aim("LowerArm.R", Vector3(-0.05, 0.2 + 0.9 * r, 1.0), w)
		aim("Fist.R", Vector3(0.0, 0.5 + r, 0.8), w)
	else:
		# one finger to the ceiling, bouncing; the other hand points across the body
		var up := 0.12 * sin(ph * 2.0)
		aim("UpperArm.L", Vector3(0.8, 0.5 + up, 0.0), w)
		aim("LowerArm.L", Vector3(-0.1, 1.0, 0.1), w)
		aim("Fist.L", Vector3(-0.1, 1.0, 0.1), w)
		aim("UpperArm.R", Vector3(-0.3, -0.8, 0.3), w)
		aim("LowerArm.R", Vector3(0.9, 0.1 + up, 0.6), w)
		aim("Fist.R", Vector3(1.0, 0.0, 0.5), w)

# teach: explains to the camera, turns and writes on the board, then points at it
#   0-3.2 talk with his hands  3.2-11 write  11-17 point at the lines and explain
const BOARD_POS := Vector3(1.1, 1.55, -0.55)   ## centre of the writing surface
const BOARD_SIZE := Vector2(2.6, 1.3)
const LINES := ["how a city moves:", "roads + cars + people", "= streets"]
const CHAR_W := 0.085                          ## metres per character on the board
const WRITE_FROM := 3.4
const WRITE_TO := 11.0
func _teach() -> void:
	var writing := t >= WRITE_FROM - 0.4 and t < WRITE_TO + 0.3
	me.play("Idle", true, 1.0)
	var pen := _pen_point()
	var spot := Vector3(-0.45, 0, 0.3)
	if writing:
		spot = Vector3(clampf(pen.x - 0.2, -0.6, 1.9), 0, 0.05)
	me.position = me.position.lerp(spot, 1.0 - exp(-4.0 * get_process_delta_time())) if t > 0.05 else spot
	var turn := window(t, WRITE_FROM - 0.6, WRITE_TO + 0.6, 0.6)
	var face_cam := deg_to_rad(20.0)
	var face_board := deg_to_rad(160.0)
	me.rotation = Vector3(0, lerp_angle(face_cam, face_board, turn), 0)
	_board_write()
	look_from(Vector3(0.9 + 0.3 * sin(t * 0.2), 1.6, 4.3), Vector3(0.55, 1.25, -0.3))

func _pose_teach() -> void:
	var writing := window(t, WRITE_FROM, WRITE_TO, 0.5)
	var talk := 1.0 - writing
	# talking hands: forearms forward, opening and closing, the two out of step
	if talk > 0.0:
		var a := sin(t * 3.1)
		var b := sin(t * 2.3 + 1.3)
		aim("UpperArm.R", Vector3(-0.35, -0.85, 0.3 + 0.15 * b), talk)
		aim("LowerArm.R", Vector3(-0.25 - 0.35 * b, 0.15 + 0.15 * a, 1.0), talk)
		var pointing := window(t, WRITE_TO + 0.8, secs - 0.5, 0.6)
		if pointing > 0.0:
			# point at the line he is talking about, one after the other (the board is
			# on his left, so the left hand)
			var k := int((t - WRITE_TO - 0.8) / 1.6) % LINES.size()
			var target: Vector3 = _line_start(k) + Vector3(0.5, 0, 0.05)
			aim("UpperArm.L", Vector3(0.35, -0.85, 0.3), talk * (1.0 - pointing))
			reach("L", target, pointing * talk, 0.1)
		else:
			aim("UpperArm.L", Vector3(0.35, -0.85, 0.3 + 0.15 * a), talk)
			aim("LowerArm.L", Vector3(0.25 + 0.35 * a, 0.15 + 0.15 * b, 1.0), talk)
		twist("Head", Vector3(0, 1, 0), 6.0 * sin(t * 1.3) * talk)
	if writing > 0.0:
		reach("R", _pen_point() + Vector3(0, 0, 0.06), writing, 0.15)
		twist("Head", Vector3(1, 0, 0), 8.0 * writing)

## ---- the sets ------------------------------------------------------------------

func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	world.add_child(mi)
	return mi

func _plain(role: String, rough: float = 0.8) -> StandardMaterial3D:
	return mat(role, 0.0, rough)

func _build_studio() -> void:
	# a floor that catches the light, a soft back wall, two neon strips
	_box(Vector3(40, 0.1, 30), Vector3(0, -0.05, 0), _plain("bg_alt", 0.55))
	_box(Vector3(40, 8, 0.2), Vector3(0, 4, -4.0), _plain("bg", 0.9))
	_box(Vector3(14, 0.06, 0.06), Vector3(0, 3.2, -3.85), mat("accent", 1.4))
	_box(Vector3(14, 0.06, 0.06), Vector3(0, 0.25, -3.85), mat("friend", 1.2))
	var key := OmniLight3D.new()
	key.position = Vector3(2.5, 3.0, 3.0)
	key.omni_range = 12.0
	key.light_energy = 0.7
	key.light_color = Color(1.0, 0.95, 0.9)
	world.add_child(key)

func _build_street() -> void:
	_box(Vector3(40, 0.14, 2.6), Vector3(0, 0.07, 0.0), _plain("bg", 0.7))       # pavement
	_box(Vector3(40, 0.16, 0.18), Vector3(0, 0.08, 1.35), mat("friend", 0.15))      # kerb
	for i in 7:
		var x := -9.0 + i * 3.4
		var lamp := model("light-square", 3.2)
		lamp.position = Vector3(x, 0.14, -1.15)
		world.add_child(lamp)
		var bulb := OmniLight3D.new()
		bulb.position = Vector3(x, 3.0, -0.8)
		bulb.omni_range = 4.0
		bulb.light_energy = 1.2
		bulb.light_color = Palette.col("prize")
		world.add_child(bulb)
	me.position.y = 0.14

func _build_dance_floor() -> void:
	var roles := ["accent", "friend", "prize", "player"]
	for ix in range(-3, 4):
		for iz in range(-2, 3):
			var role: String = roles[posmod(ix + iz, 4)]
			var tm := StandardMaterial3D.new()   # a dim tile: the coloured lights do the rest
			tm.albedo_color = Palette.col(role).darkened(0.7)
			tm.roughness = 0.35
			tm.emission_enabled = true
			tm.emission = Palette.col(role)
			tm.emission_energy_multiplier = 0.08
			_box(Vector3(0.96, 0.04, 0.96), Vector3(ix, 0.02, iz), tm)
	for i in 4:
		var L := OmniLight3D.new()
		var a := i * TAU / 4.0 + 0.4
		L.position = Vector3(3.0 * cos(a), 2.8, 3.0 * sin(a))
		L.omni_range = 7.0
		L.light_color = Palette.col(roles[i])
		world.add_child(L)
		_lights.append(L)

func _build_board() -> void:
	var c := BOARD_POS
	_box(Vector3(BOARD_SIZE.x + 0.12, BOARD_SIZE.y + 0.12, 0.04), c + Vector3(0, 0, -0.03), _plain("bg_alt", 0.4))
	_box(Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.03), c, _plain("ink", 0.25))
	_box(Vector3(BOARD_SIZE.x, 0.05, 0.12), c + Vector3(0, -BOARD_SIZE.y / 2 - 0.03, 0.05), _plain("bg_alt"))  # tray
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.05, c.y - BOARD_SIZE.y / 2, 0.05), Vector3(c.x + sx * (BOARD_SIZE.x / 2 - 0.2), (c.y - BOARD_SIZE.y / 2) / 2, c.z - 0.05), _plain("bg_alt"))
	for k in LINES.size():
		var l := Label3D.new()
		l.text = ""
		l.font_size = 64
		l.pixel_size = 0.0028
		l.outline_size = 0
		l.modulate = Palette.col("bg") if k < 2 else Palette.col("hazard")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.shaded = false
		l.double_sided = false
		l.position = _line_start(k)
		world.add_child(l)
		_board_lines.append({"label": l, "text": LINES[k]})

func _line_start(k: int) -> Vector3:
	return BOARD_POS + Vector3(-BOARD_SIZE.x / 2 + 0.18, 0.38 - k * 0.36, 0.02)

func _chars_written() -> float:
	var total := 0
	for s: String in LINES:
		total += s.length()
	return clampf((t - WRITE_FROM) / (WRITE_TO - WRITE_FROM), 0.0, 1.0) * total

## Where the pen is now: the end of what has been written so far.
func _pen_point() -> Vector3:
	var n := _chars_written()
	for k in LINES.size():
		var ln: int = LINES[k].length()
		if n <= ln or k == LINES.size() - 1:
			var wob := Vector3(0, 0.03 * sin(t * 23.0), 0)
			return _line_start(k) + Vector3(minf(n, ln) * CHAR_W, 0, 0) + wob
		n -= ln
	return _line_start(0)

func _board_write() -> void:
	var n := int(_chars_written())
	for e: Dictionary in _board_lines:
		var s: String = e["text"]
		(e["label"] as Label3D).text = s.substr(0, clampi(n, 0, s.length()))
		n -= s.length()

func _board_reset() -> void:
	for e: Dictionary in _board_lines:
		(e["label"] as Label3D).text = ""
