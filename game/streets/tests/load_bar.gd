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
var loads: Array = []   # per load, for the verdict: {first text, worst off, first guess, left then}

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
		var eta = g._load_bar._load_eta
		if eta != null and is_instance_valid(eta) and (said.is_empty() or said[-1][1] != eta.text):
			said.append([Time.get_ticks_msec(), eta.text, g._load_bar._load_fill.size.x / g.LoadBar.LOAD_W])
	var end := Time.get_ticks_msec()
	print("%s: %.1f s from start to the car" % [g._city_name, (end - t0) / 1000.0])
	var errs: Array = []
	var seen := {"first": "", "worst": -1.0, "guess": -1.0, "left": 0.0}
	for s: Array in said:
		var left := (end - int(s[0])) / 1000.0
		var txt := String(s[1])
		if seen["first"] == "":
			seen["first"] = txt
		var guess := -1.0
		if txt.begins_with("about "):
			guess = float(txt.split(" ")[1])
		elif txt == "almost there":
			guess = 0.75
		if guess >= 0.0:
			errs.append(absf(guess - left))
			seen["worst"] = maxf(float(seen["worst"]), absf(guess - left))
			if float(seen["guess"]) < 0.0:
				seen["guess"] = guess
				seen["left"] = left
		print("  %5.1f s in, bar %3d%%: %-26s really %.1f s left" % [(int(s[0]) - t0) / 1000.0, int(float(s[2]) * 100.0), txt, left])
	if not errs.is_empty():
		var worst := 0.0
		var sum := 0.0
		for e: float in errs:
			worst = maxf(worst, e)
			sum += e
		print("  off by %.1f s on average, %.1f s at worst (%d readings)" % [sum / errs.size(), worst, errs.size()])
	loads.append(seen)

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
	# What the bar promises: the first load on a device says "timing it", every later one how
	# long is left. The fix's second Givatayim load said "about 3 s" with 2.9 left, and the
	# header's good is "within ~1 s all the way"; the text rounds up to the second, so a
	# reading can be most of a second off by that alone: worst under 1.5 s. Tel Aviv, guessed
	# from Givatayim's numbers, said "about 5 s" with 6.6 left: its first guess within 2x.
	var timing: bool = loads.size() == 3 and String(loads[0]["first"]).begins_with("timing")
	var giv: float = float(loads[1]["worst"]) if loads.size() == 3 else -1.0
	var ta: float = float(loads[2]["guess"]) / maxf(float(loads[2]["left"]), 0.01) if loads.size() == 3 and float(loads[2]["guess"]) >= 0.0 else -1.0
	var ok := timing and giv >= 0.0 and giv < 1.5 and ta >= 0.5 and ta <= 2.0
	print("REGRESS load_bar: %s -- the first load %s, Givatayim's second off by %.1f s at worst, Tel Aviv's first guess %.2fx what was left (good 'timing it', under 1.5 s, 0.5-2x)" % [
		"PASS" if ok else "FAIL", "said 'timing it'" if timing else "said '%s'" % (loads[0]["first"] if not loads.is_empty() else "nothing"), giv, ta])
	quit(0)
