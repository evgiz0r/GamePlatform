extends SceneTree
## Makes people/moves.res: the clips the streets use, out of Quaternius' Universal Animation
## Library (CC0; the 7.6 MB UAL1_Standard.glb is not in the repo). Run once with the glb at
## $UAL:  UAL=<path inside the project>/UAL1_Standard.glb godot --headless -s res://game/streets/people/make_moves.gd
const KEEP := ["Walk", "Walk_Formal", "Idle", "Idle_Talking", "Jog_Fwd", "Sitting_Enter", "Sitting_Idle",
	"Sitting_Talking", "Sitting_Exit", "Push", "Driving", "Roll", "Interact", "PickUp_Table", "Sprint"]

func _initialize() -> void:
	var lib: Node = (load(OS.get_environment("UAL")) as PackedScene).instantiate()
	var ap: AnimationPlayer = lib.find_children("*", "AnimationPlayer", true, false)[0]
	var out := AnimationLibrary.new()
	for k: String in KEEP:
		var a := ap.get_animation(k)
		if a == null:
			push_error("no clip " + k)
			continue
		out.add_animation(k, a.duplicate(true))
	var err := ResourceSaver.save(out, "res://game/streets/people/moves.res", ResourceSaver.FLAG_COMPRESS)
	print("saved ", out.get_animation_list().size(), " clips, err ", err)
	lib.free()
	quit()
