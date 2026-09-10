class_name Actor3D extends Node3D
## An animated 3D character with no setup -- the 3D Blob.set_actor():
##
##   var a := Actor3D.new()
##   world.add_child(a)
##   a.set_character("Casual_Male")   # assets/characters3d/, scaled to 1.8 units tall
##   a.play("Walk")                   # loops; play("Death", false) plays once and holds
##   a.face(direction)                # turn to walk that way
##
## Origin is between the feet. A missing file gives a capsule-and-head placeholder in a
## palette role and a playtest warning, so a game never depends on the art existing.
## Clip names live in assets/INDEX.md (Walk, Run, Idle, Death, ...).

const DIR := "res://assets/characters3d/"

var character := ""
var model: Node3D = null
var anim: AnimationPlayer = null
var height := 1.8
var _clip := ""

func set_character(name: String, tall: float = 1.8, role_if_missing: String = "prize") -> void:
	for c in get_children():
		c.queue_free()
	character = name
	height = tall
	anim = null
	_clip = ""
	var path := ""
	for ext: String in ["gltf", "glb"]:
		if ResourceLoader.exists(DIR + name + "." + ext):
			path = DIR + name + "." + ext
			break
	if path == "":
		Probe.note("no character named '%s' in assets/characters3d/ -- see assets/INDEX.md" % name)
		model = _placeholder(role_if_missing)
		add_child(model)
		return
	var scn: PackedScene = load(path)
	model = scn.instantiate()
	add_child(model)
	GameMode3D.fit(model, tall, true)
	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer

## Play a clip by name. Returns false (and warns in the report) if it does not exist.
func play(clip: String, loop: bool = true, speed: float = 1.0) -> bool:
	if anim == null or not anim.has_animation(clip):
		if anim != null:
			Probe.note("character '%s' has no clip '%s' -- clips: %s" % [character, clip, ", ".join(anim.get_animation_list())])
		return false
	if clip == _clip:
		anim.speed_scale = speed
		return true
	# glTF imports drop loop flags; set them on the way in
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	anim.speed_scale = speed
	anim.play(clip)
	_clip = clip
	return true

## Turn to face a world direction. Quaternius characters face +Z, so look at the point
## BEHIND us along -dir (look_at aims -Z).
func face(dir: Vector3) -> void:
	var d := dir
	d.y = 0.0
	if d.length_squared() < 0.0001 or not is_inside_tree():
		return
	look_at(global_position - d.normalized(), Vector3.UP)

func _placeholder(role: String) -> Node3D:
	var root := Node3D.new()
	var gm := get_parent()
	while gm != null and not (gm is GameMode3D):
		gm = gm.get_parent()
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = height * 0.18
	cm.height = height * 0.66
	if gm != null:
		cm.material = gm.mat(role, 0.5)
	body.mesh = cm
	body.position = Vector3(0, height * 0.42, 0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = height * 0.13
	sm.height = height * 0.26
	if gm != null:
		sm.material = gm.mat("ink", 0.3)
	head.mesh = sm
	head.position = Vector3(0, height * 0.84, 0)
	root.add_child(head)
	return root
