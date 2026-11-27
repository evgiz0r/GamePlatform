extends RefCounted
## The HUD's buttons, the "more" drawer, folding (see AUTO_BTN for the layout) (moved out of streets.gd; `g` is the game).

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game


const RESUME_BTN := Rect2(280, 74, 80, 24)  ## paused by hand: the way back out (pause is in the drawer)
const MORE_RECT := Rect2(246, 40, 314, 282) ## the drawer, left of the right-hand buttons and above the bottom row
const KEYS_RECT := Rect2(110, 46, 420, 262)

func _view_name() -> String:
	if g._zoomed():
		return ("eyes" if g._walking else "seat") if g._zoom_seat else ("behind" if g._walking else "chase")
	if g._walking:
		return "eyes" if g._cockpit else "behind"
	return "seat" if g._cockpit else "chase"

## the camera: chase <-> seat. From above, it says which it lands in and a tap swaps that
## (the view from above is the map button's now, MAP_BTN)
func _next_view() -> void:
	if g._zoomed():
		g._zoom_seat = not g._zoom_seat
	else:
		g._set_cockpit(not g._cockpit)

## the map button: up over the city (paused; drag, pinch, hold a street to drive there), or
## back down to the car, the city going on again if it was going before
## (not under the perf view's panel, which covers the minimap too)
func _map_btn_shown() -> bool:
	return not g._hud_folded and not g._perf_view and not g._drive_map._trace_view

func _toggle_map() -> void:
	if g._zoom > 0.0:
		g._zoom_set(0.0)
	else:
		g._zoom_set(Streets.MAP_ZOOM)
		g._more_open = false

func _time_now() -> String:
	return "night" if g._night else ("evening" if g._evening else "day")

## straight to a time of day: _next_time round until there (it goes day, evening, night)
func _set_time_of_day(to: String) -> void:
	if g._tod_busy:
		return
	g._tod_busy = true
	for i in range(3):
		if _time_now() == to or not g.is_inside_tree():
			break
		await g._next_time()
	g._tod_busy = false

## the drawer's rows: [label, y, [[text, key]...], key now, what]
func _more_rows() -> Array:
	return [
		["time of day", 58, [["day", "day"], ["evening", "evening"], ["night", "night"]], _time_now(), "time"],
		["road", 100, [["dry", "dry"], ["wet", "wet"]], "wet" if g._wet else "dry", "road"],
		["autodrive", 142, [["keeps rules", "rules"], ["green wave", "wave"], ["racer", "racer"]], g._ap_style, "style"],
		["steering assist, when you drive", 184, [["off", "off"], ["on", "on"]], "on" if g._assist else "off", "assist"],
		["", 220, [["resume" if g._paused else "pause", "pause"], ["keys", "keys"], ["perf view", "perf"]],
			"pause" if g._paused else ("perf" if g._perf_view or g._drive_map._trace_view else ""), "act"],
	]

func _seg_rect(row: Array, i: int) -> Rect2:
	var n: int = (row[2] as Array).size()
	var w := (MORE_RECT.size.x - 24.0 - 4.0 * (n - 1)) / n
	return Rect2(MORE_RECT.position.x + 12.0 + i * (w + 4.0), float(row[1]) + 6.0, w, 24.0)

func _draw_more() -> void:
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	if g._more_open:
		g._hud.draw_rect(MORE_RECT, Color(bg, 0.92))
		g._hud.draw_rect(MORE_RECT, Color(Palette.col("accent"), 0.6), false, 1.5)
		for row: Array in _more_rows():
			if String(row[0]) != "":
				g._hud.draw_string(g._font, Vector2(MORE_RECT.position.x + 12.0, float(row[1]) + 2.0), String(row[0]),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(ink, 0.7))
			var opts: Array = row[2]
			for i in range(opts.size()):
				var col := Palette.col("hazard") if String(opts[i][1]) == "racer" else Palette.col("accent")
				g._hud_btn(_seg_rect(row, i), String(opts[i][0]), col, String(opts[i][1]) == String(row[3]), 11)
		# what a screenshot needs to say (it sat over the map; the user: the small notes took room)
		var x := MORE_RECT.position.x + 12.0
		var w := MORE_RECT.size.x - 24.0
		g._hud.draw_string(g._font, Vector2(x, 262), "%d fps · worst %d ms · quality %d" % [Engine.get_frames_per_second(), int(g._perf._worst_ms()), g._quality],
			HORIZONTAL_ALIGNMENT_LEFT, w, 9, Color(ink, 0.75))
		g._hud.draw_string(g._font, Vector2(x, 274), g._build_line(), HORIZONTAL_ALIGNMENT_LEFT, w, 9, Color(ink, 0.75))
		var ll := g._load_line()
		if ll != "":
			g._hud.draw_multiline_string(g._font, Vector2(x, 285), ll, HORIZONTAL_ALIGNMENT_LEFT, w, 8, 2, Color(ink, 0.6))
		if not g._credits.is_empty():
			g._hud.draw_multiline_string(g._font, Vector2(x, 306), g._credit_line(g._credits), HORIZONTAL_ALIGNMENT_LEFT, w, 8, 2, Color(ink, 0.6))
	if g._keys_open:
		g._hud.draw_rect(KEYS_RECT, Color(bg, 0.95))
		g._hud.draw_rect(KEYS_RECT, Color(Palette.col("accent"), 0.6), false, 1.5)
		g._hud_text(KEYS_RECT.position + Vector2(0, 20), "keys", KEYS_RECT.size.x, 13, Palette.col("player"))
		var keys := [
			["arrows / WASD", "drive"], ["space · shift", "autodrive on · off"],
			["Q · E", "indicators"], ["H", "horn"],
			["L", "lights"], ["C", "seat / chase"],
			["M · Z", "map · up over the city"], ["wheel · - =", "zoom"],
			["G", "look round"], ["F", "walk / get in"],
			["K", "pause"], ["V · R", "green wave · racer"],
			["P", "perf view"], ["", ""],
		]
		for i in range(keys.size()):
			var at := KEYS_RECT.position + Vector2(16.0 + (i % 2) * 204.0, 46.0 + (i / 2) * 26.0)
			g._hud.draw_string(g._font, at, String(keys[i][0]), HORIZONTAL_ALIGNMENT_LEFT, 84, 11, Palette.col("accent"))
			g._hud.draw_string(g._font, at + Vector2(88, 0), String(keys[i][1]), HORIZONTAL_ALIGNMENT_LEFT, 110, 11, ink)
		g._hud_text(Vector2(KEYS_RECT.position.x, KEYS_RECT.end.y - 10), "tap anywhere to close", KEYS_RECT.size.x, 9, Color(ink, 0.6))

## a tap in the drawer (or the keys card, or anywhere while either is open): true if it took it
func _more_tap(p: Vector2) -> bool:
	if g._keys_open:
		g._keys_open = false
		return true
	if not g._more_open:
		return false
	if Streets.MORE_BTN.grow(3).has_point(p) or not MORE_RECT.has_point(p):
		g._more_open = false   # (a tap outside closes it, and does nothing else)
		return true
	for row: Array in _more_rows():
		var opts: Array = row[2]
		for i in range(opts.size()):
			if not _seg_rect(row, i).grow(2).has_point(p):
				continue
			var k := String(opts[i][1])
			match String(row[4]):
				"time":
					if k != _time_now():
						_set_time_of_day(k)
				"road":
					if (k == "wet") != g._wet:
						g._set_wet(k == "wet")
				"style":
					if k != g._ap_style:
						g._set_ap_style(k)
				"assist":
					if (k == "on") != g._assist:
						g._assist = k == "on"
						g._prefs_save()
						g._show_banner("steering assist " + k + (" when you drive" if g._auto else ""), 1.2)
						Probe.event("assist", {"on": g._assist})
				"act":
					if k == "pause":
						g._toggle_pause()
					elif k == "keys":
						g._more_open = false
						g._keys_open = true
					elif k == "perf":
						g._toggle_perf()
			return true
	return true

## a tap on one of the HUD's own buttons: done, and true; false if there is no button there
func _hud_tap(p: Vector2) -> bool:
	if _more_tap(p):
		return true
	match _hud_hit(p):
		"resume", "pause":
			g._toggle_pause()
		"show":
			g._hud_folded = false
			g._prefs_save()
		"auto":
			g._auto_by_hand(not g._auto)
		"style":
			g._set_ap_style(Streets.AP_STYLES[(Streets.AP_STYLES.find(g._ap_style_now()) + 1) % Streets.AP_STYLES.size()])
		"goto":
			g._open_picker.call_deferred()   # after this click, so it does not hit the list
		"walk":
			g._toggle_walk()
		"more":
			g._more_open = true
		"fold":
			g._hud_folded = true
			g._prefs_save()
			g._show_banner("buttons folded away: \"show\" brings them back", 1.6)
		"view":
			_next_view()
		"map":
			_toggle_map()
		"perf":
			if g._perf_view or g._drive_map._trace_view:   # (the drive map too: P and the drawer go round to it)
				g._drive_map._trace_view = false
				g._perf_view = false
				g._perf_lbl.visible = false
			else:
				g._toggle_perf()
		"look":
			g._head_look._toggle_look()
		_:
			return false
	return true

## the HUD's buttons showing now, by name -> their box (as _draw_hud draws them)
func _hud_buttons() -> Dictionary:
	var out := {}
	if g._paused and not g._zoomed() and not g._more_open:
		out["resume"] = RESUME_BTN
	if g._hud_folded:
		out["show"] = Streets.SHOW_BTN
		return out
	if not g._walking:
		out["auto"] = Streets.AUTO_BTN
		if g._auto:
			out["style"] = Streets.STYLE_BTN
	out["goto"] = Streets.GOTO_BTN
	out["pause"] = Streets.PAUSE_BTN
	out["walk"] = Streets.WALK_BTN
	out["more"] = Streets.MORE_BTN
	out["fold"] = Streets.FOLD_BTN
	out["view"] = Streets.VIEW_BTN
	out["perf"] = Streets.PERF_BTN
	if _map_btn_shown():
		out["map"] = Streets.MAP_BTN
	if not g._walking and not g._auto:
		out["look"] = Streets.HeadLook.LOOK_BTN
	return out

## Which button a tap at p is for, "" for none. A mouse must land on it (3 px to spare); a
## finger has HIT_TOUCH px round each, and the nearest box wins where two reach -- the boxes
## are drawn small (the user wanted the screen kept clear) but 22 px is about 4 mm on a phone
## held sideways, under half a fingertip.
const HIT_TOUCH := 10.0
func _hud_hit(p: Vector2) -> String:
	var slop := HIT_TOUCH if g._touch_seen else 3.0
	var best := ""
	var best_d := INF
	var btns := _hud_buttons()
	for k: String in btns:
		var r: Rect2 = btns[k]
		var d := Vector2(maxf(0.0, maxf(r.position.x - p.x, p.x - r.end.x)), maxf(0.0, maxf(r.position.y - p.y, p.y - r.end.y))).length()
		if d <= slop and d < best_d:
			best = k
			best_d = d
	return best

## is there a button (or the open drawer) under p? -- a touch there is the button's, not the
## stick's or the view's (the button itself acts on the click the touch emulates)
func _on_hud_button(p: Vector2) -> bool:
	return g._more_open or g._keys_open or _hud_hit(p) != ""
