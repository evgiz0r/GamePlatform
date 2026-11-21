extends SceneTree
# Writes the packs tools/split_pck.py laid out, with Godot's own PCKPacker, so their format is
# always this engine's. Usage (tools/publish_web.sh runs it):
#   $GODOT --headless --path . -s res://tools/pack_write.gd -- <work dir>/manifest.json
# The main pack replaces <export dir>/index.pck; the others are written beside it.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var m = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if args.size() > 0 else null
	if typeof(m) != TYPE_DICTIONARY:
		printerr("pack_write: no manifest")
		quit(1)
		return
	var ok := true
	for pk in m["packs"]:
		var path: String = m["out"].path_join(pk["name"])
		var w := PCKPacker.new()
		ok = ok and w.pck_start(path + ".tmp") == OK
		for f in pk["files"]:
			ok = ok and w.add_file(f[0], f[1]) == OK
		ok = ok and w.flush() == OK
		if not ok:
			printerr("pack_write: could not write ", path)
			break
		DirAccess.rename_absolute(path + ".tmp", path)
	quit(0 if ok else 1)
