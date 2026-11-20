extends SceneTree
## Does a script parse and compile? `tools/check_script.sh res://game/<name>/<name>.gd`
## (several paths at once are fine). Seconds, against minutes for a playtest -- run it after
## every edit to a long script, and after merging another session's work.
## Exit code 0 when all of them load, 1 when one does not (the engine prints why above).
func _initialize() -> void:
	var bad := 0
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		push_error("which script? tools/check_script.sh res://game/<name>/<name>.gd")
		quit(2)
		return
	for p: String in paths:
		var s := load(p) as Script
		var ok := s != null and s.can_instantiate()
		print("%s  %s" % ["ok  " if ok else "FAIL", p])
		if not ok:
			bad += 1
	quit(1 if bad > 0 else 0)
