extends SceneTree
## The HUD's buttons (AUTO_BTN and on, the "more" drawer, folding): taps each through
## _hud_tap as a player would, checks what it did, and shoots each state --
## hud_drive / hud_auto / hud_more / hud_night / hud_keys / hud_folded / hud_walk.png.
## Checks, every state: the buttons on screen inside the screen and none overlapping another,
## the minimap, the stick's ring or the credit. And the autodrive styles: the player's
## autodrive is the racer by default, a script's _set_auto (the bots, routes, scene tests)
## keeps the rules.
##   game/streets/tests/run.sh hud_layout 4
var g: Node
var fails := 0

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _ok(what: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1

func _tap(r: Rect2) -> void:
	g._hud_tap(r.get_center())
	await process_frame

## every button showing now, by name
func _shown() -> Dictionary:
	var out := {}
	if g._hud_folded:
		out["show"] = g.SHOW_BTN
	else:
		if not g._walking:
			out["auto"] = g.AUTO_BTN
			if g._auto:
				out["style"] = g.STYLE_BTN
		out["goto"] = g.GOTO_BTN
		out["walk"] = g.WALK_BTN
		out["more"] = g.MORE_BTN
		out["fold"] = g.FOLD_BTN
		out["view"] = g.VIEW_BTN
		if not g._walking and not g._auto:
			out["look"] = g.LOOK_BTN
	if g._paused and not g._zoomed():
		out["resume"] = g.RESUME_BTN
	return out

func _check_layout(state: String) -> void:
	var btn := _shown()
	var screen := Rect2(0, 0, 640, 360)
	var others := {"minimap": Rect2(g._map.position, g._map.size),
		"credit": Rect2(g._osm_lbl.position, g._osm_lbl.size), "speed": Rect2(g._speed_lbl.position, Vector2(130, 50))}
	if g._load_lbl != null and is_instance_valid(g._load_lbl) and g._load_lbl.text != "":   # (the load line, its first seconds)
		others["load line"] = Rect2(g._load_lbl.position, Vector2(g._load_lbl.get_minimum_size().x, 12))
	if g._touch_seen:
		others["stick"] = Rect2(g.STICK_C - Vector2.ONE * (g.STICK_R + 5.0), Vector2.ONE * (g.STICK_R + 5.0) * 2.0)
	var bad: Array = []
	var names: Array = btn.keys()
	for i in range(names.size()):
		var a: Rect2 = btn[names[i]]
		if not screen.encloses(a):
			bad.append("%s off the screen" % names[i])
		for j in range(i + 1, names.size()):
			if a.intersects(btn[names[j]]):
				bad.append("%s on %s" % [names[i], names[j]])
		for o: String in others:
			if a.intersects(others[o]):
				bad.append("%s on the %s" % [names[i], o])
	_ok("%s: %d buttons, none overlapping %s" % [state, names.size(), bad], bad.is_empty())

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.5).timeout
	g._touch_seen = true   # (as on a phone: the stick drawn, its room kept)
	await _snap("hud_drive")
	_check_layout("driving")
	_ok("the style starts as racer", g._ap_style == "racer")
	# a script's autodrive keeps the rules
	g._set_auto(true)
	_ok("a script's _set_auto keeps the rules (racing %s, wave %s)" % [g._racing(), g._wave.on], not g._racing() and not g._wave.on)
	g._set_auto(false)
	# the player's: racer, no wave
	await _tap(g.AUTO_BTN)
	_ok("the autodrive button: on, racing, no wave", g._auto and g._racing() and not g._wave.on)
	await create_timer(1.0).timeout
	await _snap("hud_auto")
	_check_layout("autodrive")
	var seen: Array = [g._ap_style]
	for i in range(3):
		await _tap(g.STYLE_BTN)
		seen.append(g._ap_style)
	_ok("the style chip goes round %s" % [seen], seen == ["racer", "rules", "wave", "racer"])
	# the drawer
	await _tap(g.MORE_BTN)
	_ok("more opens the drawer", g._more_open)
	g._mouse_at = g._seg_rect(g._more_rows()[0], 2).get_center()   # a mouse over "night": filled as hovered
	await _snap("hud_more")
	g._mouse_at = Vector2.INF
	var rows: Array = g._more_rows()
	await _tap(g._seg_rect(rows[2], 1))   # autodrive: green wave
	_ok("the drawer's green wave: wave on, racer off", g._wave.on and not g._racing() and g._ap_style == "wave")
	await _tap(g._seg_rect(rows[2], 2))   # back to racer
	await _tap(g._seg_rect(rows[1], 1))   # wet
	_ok("the drawer's wet", g._wet)
	await _tap(g._seg_rect(rows[0], 2))   # night: through evening
	var t := 0.0
	while (g._tod_busy or not g._night) and t < 20.0:
		await create_timer(0.25).timeout
		t += 0.25
	_ok("the drawer's night (%.1f s)" % t, g._night and not g._tod_busy)
	await _snap("hud_more_night")
	await _tap(Rect2(300, 345, 1, 1))   # outside: closes it
	_ok("a tap outside closes the drawer", not g._more_open)
	await _tap(g.AUTO_BTN)   # you drive: look shows
	await create_timer(0.5).timeout
	await _snap("hud_night")
	_check_layout("night, you drive")
	# the keys card
	await _tap(g.MORE_BTN)
	rows = g._more_rows()
	await _tap(g._seg_rect(rows[4], 1))
	_ok("keys opens the keys card", g._keys_open and not g._more_open)
	await _snap("hud_keys")
	await _tap(Rect2(320, 180, 1, 1))
	_ok("a tap closes the keys card", not g._keys_open)
	# pause from the drawer, resume from the screen
	await _tap(g.MORE_BTN)
	rows = g._more_rows()
	await _tap(g._seg_rect(rows[4], 0))
	await _tap(Rect2(300, 345, 1, 1))
	_ok("paused from the drawer", g._paused)
	_check_layout("paused")
	await _tap(g.RESUME_BTN)
	_ok("resume on screen", not g._paused)
	# the camera round
	var views: Array = [g._view_name()]
	for i in range(3):
		await _tap(g.VIEW_BTN)
		await create_timer(0.6).timeout
		views.append(g._view_name())
	_ok("the camera goes round %s" % [views], views == ["chase", "seat", "above", "chase"])
	await create_timer(1.0).timeout
	# folded
	await _tap(g.FOLD_BTN)
	_ok("folded", g._hud_folded)
	await create_timer(1.8).timeout
	await _snap("hud_folded")
	_check_layout("folded")
	await _tap(g.SHOW_BTN)
	_ok("show unfolds", not g._hud_folded)
	# on foot
	await _tap(g.WALK_BTN)
	await create_timer(1.5).timeout
	_ok("walk gets out", g._walking)
	await _snap("hud_walk")
	_check_layout("walking")
	print("hud_layout: %d failed" % fails)
	quit(1 if fails > 0 else 0)
