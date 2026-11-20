extends SceneTree
## The loading bar's "about N s" against what the load really took. Starts from no history
## (the log, user://streets_load.json, set aside and put back after), then loads Givatayim
## twice -- the first says "timing it", the second estimates from the first -- and Tel Aviv,
## estimated from Givatayim's numbers with the file scaled by size. For each load: what the
## text said along the way and how long was really left then.
##   STREETS_BUILD_ALL=0 $GODOT --headless --path . -s res://game/streets/tests/load_bar.gd
## Good: the second Givatayim within ~1 s all the way; Tel Aviv's first guess within ~2x
## (another city's numbers), better once its own file is read (`pace`).
const LOG := "user://streets_load.json"
var g: Node

func _initialize() -> void:
	_run()

func _game(old: int) -> Node:   # (old: the last load's game, by id -- it may be freed by now)
	for n in root.find_children("*", "Node2D", true, false):
		if n.get_instance_id() != old and n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd") and n.is_inside_tree():
			return n
	return null

func _load(lvl: int) -> void:
	var old := g.get_instance_id() if is_instance_valid(g) else 0
	g = null
	root.get_node("Flow").start_game("streets", {"level": lvl})
	var said: Array = []   # [ms, text, bar fraction]
	var t0 := Time.get_ticks_msec()
	while g == null or not g._loaded:
		await process_frame
		if g == null:
			g = _game(old)
			continue
		var eta = g._load_eta
		if eta != null and is_instance_valid(eta) and (said.is_empty() or said[-1][1] != eta.text):
			said.append([Time.get_ticks_msec(), eta.text, g._load_fill.size.x / g.LOAD_W])
	var end := Time.get_ticks_msec()
	print("%s: %.1f s from start to the car" % [g._city_name, (end - t0) / 1000.0])
	var errs: Array = []
	for s: Array in said:
		var left := (end - int(s[0])) / 1000.0
		var txt := String(s[1])
		var guess := -1.0
		if txt.begins_with("about "):
			guess = float(txt.split(" ")[1])
		elif txt == "almost there":
			guess = 0.75
		if guess >= 0.0:
			errs.append(absf(guess - left))
		print("  %5.1f s in, bar %3d%%: %-26s really %.1f s left" % [(int(s[0]) - t0) / 1000.0, int(float(s[2]) * 100.0), txt, left])
	if not errs.is_empty():
		var worst := 0.0
		var sum := 0.0
		for e: float in errs:
			worst = maxf(worst, e)
			sum += e
		print("  off by %.1f s on average, %.1f s at worst (%d readings)" % [sum / errs.size(), worst, errs.size()])

func _run() -> void:
	var kept := FileAccess.get_file_as_string(LOG) if FileAccess.file_exists(LOG) else ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))
	await create_timer(0.3).timeout
	for lvl in [1, 1, 7]:
		await _load(lvl)
		await create_timer(1.0).timeout
	print("log: ", FileAccess.get_file_as_string(LOG))
	if kept != "":
		var f := FileAccess.open(LOG, FileAccess.WRITE)
		f.store_string(kept)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))
	quit(0)
