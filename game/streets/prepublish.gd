extends SceneTree
## Run by tools/publish_web.sh before each web export, headless: works out each town's
## bridges, tunnels and ramps once for the build, so a player's load does not (see "bridges
## and tunnels worked out when the build is made" in streets.gd). For every town and level
## setting: one load working them out and recording what it did, one load from that record,
## and the record kept in baked/ only if both leave the game in the same state -- everything
## the city file's loading sets, the decks' own state, the details'. A town that differs is
## left out (the player's load works it out, as before) and said so here.
##   $GODOT --headless --path . -s res://game/streets/prepublish.gd
## Not committed (.gitignore): made again for every build, removed after the export.
var G: GDScript                      ## streets.gd, loaded once the kit's autoloads are up
const SKIP := ["_stage_ms", "_part_us", "_bake_rec", "_bake_use", "_dressing"]

func _initialize() -> void:
	# never left running: an error stops a function, not the process (the build would hang)
	create_timer(600.0).timeout.connect(func():
		print("prepublish: out of time, stopped")
		quit(1))
	_run()

func _run() -> void:
	await process_frame   # (the autoloads streets.gd names are there from now)
	G = load("res://game/streets/streets.gd")
	var dir: String = "res://game/streets/" + G.BAKED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for old: String in DirAccess.get_files_at(dir):   # (none of an older build's left over)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + old))
	var done := {}
	var kept := 0
	for lv: Dictionary in G.LEVELS:
		if not lv.has("city") or lv.get("routes", false) or lv.get("walks", false):
			continue
		var file: String = G.baked_file(lv)
		if done.has(file):
			continue
		done[file] = true
		var t0 := Time.get_ticks_msec()
		print("prepublish: %s ..." % file)
		var a = G.new()
		a._place = lv
		a._bake_rec = {}
		if not a._load_city(String(lv["city"])) or not (a._bake_rec as Dictionary).has("decks"):
			print("prepublish: %s -- nothing to bake" % file)
			a.free()
			continue
		var rec: Dictionary = a._bake_rec
		if (rec["decks"].get("decks", []) as Variant).is_empty() and (rec["data"] as Dictionary).is_empty():
			print("prepublish: %s -- no bridges or tunnels, nothing to bake" % file)
			a.free()
			continue
		var t1 := Time.get_ticks_msec()
		var b = G.new()
		b._place = lv
		b._bake_use = rec
		b._load_city(String(lv["city"]))
		var t2 := Time.get_ticks_msec()
		var bad := _differs(a, b)
		if bad != "":
			print("prepublish: %s NOT baked -- loaded from the record, %s differs (the player's load works it out)" % [file, bad])
		else:
			var f := FileAccess.open_compressed(dir + file, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
			f.store_var(rec)
			f.close()
			kept += 1
			print("prepublish: %s baked -- %d ms worked out, %d ms from the record, %d KB" % [
				file, t1 - t0, t2 - t1, FileAccess.get_file_as_bytes(dir + file).size() / 1024])
		a.free()
		b.free()
	print("prepublish: %d of %d baked" % [kept, done.size()])
	quit(0)

## the first thing two loads disagree on ("" if none): the game's own state, then the decks'
## and the details' (objects are compared by what they hold)
func _differs(a: Object, b: Object) -> String:
	var va: Dictionary = G._vars_of(a)
	var vb: Dictionary = G._vars_of(b)
	for k: String in va:
		if k in SKIP:
			continue
		if not vb.has(k) or va[k] != vb[k]:
			return k
	var da: Dictionary = (va.get("_dressing", {}) as Dictionary).duplicate()
	var db: Dictionary = (vb.get("_dressing", {}) as Dictionary).duplicate()
	db.erase("decks_baked")
	if da != db:
		return "_dressing"
	for o: String in ["_decks", "_details"]:
		var oa = a.get(o)
		var ob = b.get(o)
		if (oa == null) != (ob == null):
			return o
		if oa != null:
			var sa: Dictionary = G._vars_of(oa)
			var sb: Dictionary = G._vars_of(ob)
			for k: String in sa:
				if not sb.has(k) or sa[k] != sb[k]:
					return "%s.%s" % [o, k]
	return ""
