extends SceneTree
## The HUD's buttons (AUTO_BTN and on, the "more" drawer, folding): taps each through
## _hud_tap as a player would, checks what it did, and shoots each state --
## hud_drive / hud_auto / hud_perf / hud_more / hud_night / hud_keys / hud_paused / hud_map / hud_folded / hud_walk.png.
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
	if DisplayServer.get_name() == "headless":   # (HEADLESS=1: the checks without the shots)
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _ok(what: String, ok: bool) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1

func _tap(r: Rect2) -> void:
	g._hud_tap(r.get_center())
	await process_frame

## every button showing now, by name (the game's own list: what it draws and hit-tests)
func _shown() -> Dictionary:
	return g._hud_buttons()

func _rect_circle(r: Rect2, c: Vector2, rad: float) -> bool:
	return c.distance_to(c.clamp(r.position, r.end)) < rad

func _check_layout(state: String) -> void:
	var btn := _shown()
	var screen := Rect2(0, 0, 640, 360)
	var others := {"minimap": Rect2(g._map.position, g._map.size),
		"credit": Rect2(g._osm_lbl.position, g._osm_lbl.size), "speed": Rect2(g._speed_lbl.position, Vector2(130, 50))}
	if g._load_lbl != null and is_instance_valid(g._load_lbl) and g._load_lbl.text != "":   # (the load line, its first seconds)
		others["load line"] = Rect2(g._load_lbl.position, Vector2(g._load_lbl.get_minimum_size().x, 12))
	if g._perf_view:   # (the panel the perf button opens under itself, and its graph: the button first sat on it)
		others["perf view"] = Rect2(g._perf_lbl.position, g._perf_lbl.get_combined_minimum_size().max(g._perf_lbl.size))
		others["frame graph"] = g.PERF_GRAPH
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
		# a finger's reach (HIT_TOUCH round it) kept off the stick's ring, which a touch there is for
		if g._touch_seen and _rect_circle(a.grow(g.HIT_TOUCH), g.STICK_C, g.STICK_R + 5.0):
			bad.append("%s's reach on the stick" % names[i])
	_ok("%s: %d buttons, none overlapping %s" % [state, names.size(), bad], bad.is_empty())

## a finger: each button's middle is that button's; 8 px out from each side it still is,
## unless another button's box is nearer there (then that one's); and a mouse needs the box
func _touch_hits() -> void:
	var bad: Array = []
	var btn: Dictionary = g._hud_buttons()
	for k: String in btn:
		var r: Rect2 = btn[k]
		if g._hud_hit(r.get_center()) != k:
			bad.append("%s's middle" % k)
		for off: Vector2 in [Vector2(0, -r.size.y * 0.5 - 8), Vector2(0, r.size.y * 0.5 + 8), Vector2(-r.size.x * 0.5 - 8, 0), Vector2(r.size.x * 0.5 + 8, 0)]:
			var q := r.get_center() + off
			var near := k
			for o: String in btn:
				var ro: Rect2 = btn[o]
				if o != k and ro.grow(8.0).has_point(q):
					near = ""   # (another as near or nearer: either may win)
			if near != "" and g._hud_hit(q) != k:
				bad.append("%s 8 px out %s: %s" % [k, off, g._hud_hit(q)])
	_ok("a finger 8 px off a button still gets it %s" % [bad], bad.is_empty())
	g._touch_seen = false
	var r0: Rect2 = btn["goto"]
	_ok("a mouse 8 px off does not", g._hud_hit(r0.get_center() + Vector2(0, -r0.size.y * 0.5 - 8)) == "")
	g._touch_seen = true

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
	_touch_hits()
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
	# the perf button: one tap opens the frame times, one closes them; from the drive map
	# (P's next step) it closes that too
	await _tap(g.PERF_BTN)
	_ok("the perf button opens the perf view", g._perf_view and g._perf_lbl.visible)
	await create_timer(1.0).timeout
	await _snap("hud_perf")
	_check_layout("perf view")
	await _tap(g.PERF_BTN)
	_ok("and closes it", not g._perf_view and not g._perf_lbl.visible and not g._drive_map._trace_view)
	g._toggle_perf()
	g._toggle_perf()
	await _tap(g.PERF_BTN)
	_ok("the perf button closes the drive map too", not g._perf_view and not g._drive_map._trace_view)
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
	# pause on the main screen (the user, 23 Nov): autodrive moving, a tap holds the car and
	# the traffic still, the same button lets them go on
	await _tap(g.AUTO_BTN)
	await create_timer(2.0).timeout
	await _tap(g.PAUSE_BTN)
	_ok("the pause button pauses", g._paused)
	var car0: Vector2 = g._pos
	var cars0: Array = g._traffic.cars.map(func(c): return c.pos)
	await create_timer(1.5).timeout
	var still := 0
	for i in range(mini(cars0.size(), g._traffic.cars.size())):
		if g._traffic.cars[i].pos == cars0[i]:
			still += 1
	_ok("paused: the car still (%.2f m) and %d/%d cars" % [g._pos.distance_to(car0), still, cars0.size()], g._pos == car0 and still == cars0.size() and cars0.size() > 0)
	await _snap("hud_paused")
	_check_layout("paused by the button")
	await _tap(g.PAUSE_BTN)
	await create_timer(1.5).timeout
	_ok("the pause button resumes, the car going on (%.1f m)" % g._pos.distance_to(car0), not g._paused and g._pos.distance_to(car0) > 1.0)
	await _tap(g.AUTO_BTN)
	# the camera: chase, seat, chase
	var views: Array = [g._view_name()]
	for i in range(2):
		await _tap(g.VIEW_BTN)
		await create_timer(0.6).timeout
		views.append(g._view_name())
	_ok("the camera goes round %s" % [views], views == ["chase", "seat", "chase"])
	await create_timer(1.0).timeout
	# the map button: up over the city, paused; dragged about; back down, the city going on
	await _tap(g.MAP_BTN)
	await create_timer(2.5).timeout
	_ok("map: up (%.2f), paused" % g._zoom_v, g._zoom > 0.8 and g._zoom_v > 0.6 and g._paused)
	g._zoom_pan(Vector2(-120, 40))
	_ok("map: dragged about (%.0f m)" % g._zoom_off.length(), g._zoom_off.length() > 50.0)
	await _snap("hud_map")
	_check_layout("map")
	await _tap(g.VIEW_BTN)
	_ok("map: the camera button picks the landing (%s)" % g._view_name(), g._view_name() == "seat")
	await _tap(g.VIEW_BTN)
	await _tap(g.MAP_BTN)
	t = 0.0
	while g._zoomed() and t < 10.0:
		await create_timer(0.25).timeout
		t += 0.25
	_ok("map: back down in the chase view, going on (%.1f s)" % t, not g._zoomed() and not g._paused and not g._cockpit)
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
