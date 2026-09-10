extends SceneTree
## Where does a game's start-up time go? Times load()+instantiate() of every 3D asset.
## (A game's own start() is timed by the sim runner: see "startup" in a playtest report.)
##   $GODOT --headless --path . -s tools/load_times.gd
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var game := args[0] if args.size() > 0 else "drop"
	print("== assets (load + instantiate, cold)")
	var total := 0
	for dir in ["res://assets/characters3d/", "res://assets/models/car/", "res://assets/models/city-commercial/", "res://assets/models/city-suburban/", "res://assets/models/food/", "res://assets/models/space/", "res://assets/models/city-roads/"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not (f.ends_with(".glb") or f.ends_with(".gltf")):
				continue
			var t0 := Time.get_ticks_msec()
			var scn: PackedScene = load(dir + f)
			var t1 := Time.get_ticks_msec()
			var n := scn.instantiate()
			var t2 := Time.get_ticks_msec()
			n.free()
			total += t2 - t0
			if t2 - t0 >= 15:
				print("   %5d ms  (load %4d + inst %4d)  %s" % [t2 - t0, t1 - t0, t2 - t1, f])
	print("   total %d ms" % total)
	quit()
