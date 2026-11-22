extends SceneTree
## The perf view (P, or a tap on the fps text) readable over the HUD: its lines once ran down
## over the build line and under the minimap, which was made after it and drew over it -- a
## user's screenshot from a work laptop (22 Nov 2026) had half its hitch and load lines
## unreadable. Opens the view a few seconds into a drive with four hitch lines in it (the most
## it keeps), checks it is drawn above every HUD part it overlaps and that the build line is
## its first line rather than a label of its own under it, and saves a shot.
##   game/streets/tests/run.sh perf_view 4        (about a minute; the shot: $OUT/perf_view.png)
## Good: CHECK ... PASS twice, and in the shot every line of the view on its dark backing.
var g: Node
var fails := 0

func _initialize() -> void:
	_run()

func check(what: String, ok: bool) -> void:
	print("CHECK %s: %s" % [what, "PASS" if ok else "FAIL"])
	if not ok:
		fails += 1

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	g._set_auto(true)
	await create_timer(4.0).timeout
	for i in range(4):   # (as a slow machine's view reads: four hitches, the most it keeps)
		g._hitches.push_front("%.1f s  %d ms (usual 140)  traffic 18 · people 16 · traffic: follow 11 · car 5 · building (trees) 4 · rest 271" % [
			10.0 + i, 240 + 20 * i])
	g._hitches.resize(mini(g._hitches.size(), 4))   # (the game keeps four)
	g._toggle_perf()
	await create_timer(1.0).timeout
	var pl: Label = g._perf_lbl
	var r := pl.get_global_rect()
	var over: Array = []
	for c: Node in g._hud.get_children():
		if c == pl or not (c is Control) or not (c as Control).visible or c.is_queued_for_deletion():
			continue
		var cc := c as Control
		if not cc.get_global_rect().intersects(r):
			continue
		# drawn over it (the minimap was), or text under it showing through its backing (the
		# load line, its first 20 s)
		var above := cc.z_index > pl.z_index or (cc.z_index == pl.z_index and c.get_index() > pl.get_index())
		if above or (c is Label and (c as Label).text.strip_edges() != "" and c.modulate.a > 0.05):
			over.append(str(c.name) + (" '" + (c as Label).text.left(20) + "'" if c is Label else ""))
	print("perf view: %d lines, %s; over it or showing through: %s" % [pl.text.count("\n") + 1, str(r), str(over)])
	check("nothing else in the HUD is drawn over the perf view or shows through it", over.is_empty())
	check("the build line is the perf view's first line, not a label under it",
		not g._ver_lbl.visible and pl.text.begins_with(g._ver_lbl.text))
	var out := OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/streets-tests/perf_view"
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/perf_view.png")
	print("PERF VIEW: %s (shot %s/perf_view.png)" % ["PASS" if fails == 0 else "%d FAILED" % fails, out])
	quit(1 if fails > 0 else 0)
