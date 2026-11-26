extends RefCounted
## The drive map: the last two minutes from the recorder (drivelog.gd), drawn north up (moved out of streets.gd; `g` is the game).
## Your track coloured by speed (red standing, green at the limit), autodrive's lane ahead,
## the other cars' tracks faint, a cross where something was hit, a ring where it was put
## back on the road, a dot and the seconds where it stood still (not at a light) 3 s or more.
## "save log" downloads the two minutes as JSON (tests/drive_log_map.py draws one).

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const TRACE_RECT := Rect2(96, 36, 448, 252)
const TRACE_SAVE := Rect2(452, 262, 84, 20)
var _trace_view := false
var _trace_roads := PackedVector2Array()   ## the streets in view, world metres, gathered on opening
var _trace_box := Rect2()

func _trace_frame() -> Rect2:
	var box := Rect2(g._pos, Vector2.ZERO)
	for sm: Dictionary in g._log.samples:
		box = box.expand(Vector2(float(sm["x"]), float(sm["z"])))
	box = box.grow(25.0)
	var want := TRACE_RECT.size.x / TRACE_RECT.size.y
	if box.size.x / maxf(box.size.y, 1.0) < want:
		box = box.grow_individual((box.size.y * want - box.size.x) * 0.5, 0, (box.size.y * want - box.size.x) * 0.5, 0)
	else:
		box = box.grow_individual(0, (box.size.x / want - box.size.y) * 0.5, 0, (box.size.x / want - box.size.y) * 0.5)
	if box.size.x < 150.0:
		box = box.grow((150.0 - box.size.x) * 0.5)
	return box

func _draw_trace() -> void:
	var ink := Palette.col("ink")
	var bg := Palette.col("bg")
	g._hud.draw_rect(TRACE_RECT, Color(bg, 0.9))
	if _trace_roads.is_empty():
		_trace_box = _trace_frame()
		var seen := {}
		for code: int in g._near(g._seg_hash, _trace_box.get_center(), maxf(_trace_box.size.x, _trace_box.size.y) * 0.5, Streets.SEG_CELL):
			if seen.has(code):
				continue
			seen[code] = true
			var r: Dictionary = g._roads[code / 4096]
			if not r["drive"]:
				continue
			var pts: PackedVector2Array = r["pts"]
			_trace_roads.append(pts[code % 4096])
			_trace_roads.append(pts[code % 4096 + 1])
	var box := _trace_box
	var sc := TRACE_RECT.size.x / box.size.x
	var to := func(p: Vector2) -> Vector2: return TRACE_RECT.position + (p - box.position) * sc
	var roads := PackedVector2Array()
	for p: Vector2 in _trace_roads:
		roads.append(to.call(p))
	if not roads.is_empty():
		g._hud.draw_multiline(roads, Color(ink, 0.25), maxf(1.0, 7.0 * sc))
	# the other cars, faint
	var tracks := {}
	for sm: Dictionary in g._log.samples:
		for c: Array in sm["cars"]:
			if not tracks.has(c[0]):
				tracks[c[0]] = PackedVector2Array()
			(tracks[c[0]] as PackedVector2Array).append(to.call(Vector2(float(c[2]), float(c[3]))))
	for id in tracks:
		var tr: PackedVector2Array = tracks[id]
		for k in range(1, tr.size()):
			if tr[k - 1].distance_to(tr[k]) < 25.0 * sc:   # (sent elsewhere: no line across)
				g._hud.draw_line(tr[k - 1], tr[k], Color(ink, 0.3), 1.0)
	# mine, by speed; and the standstills
	var prev := Vector2.INF
	var still := 0.0
	var still_at := Vector2.ZERO
	for sm: Dictionary in g._log.samples:
		var q: Vector2 = to.call(Vector2(float(sm["x"]), float(sm["z"])))
		var v := absf(float(sm["v"]))
		if prev != Vector2.INF and prev.distance_to(q) < 40.0:
			var k := clampf(v / 14.0, 0.0, 1.0)
			g._hud.draw_line(prev, q, Palette.col("hazard").lerp(Palette.col("friend"), k), 2.0)
		prev = q
		if v < 0.3 and sm["why"] != "light":
			if still == 0.0:
				still_at = q
			still += 1.0 / Streets.DriveLog.HZ
		else:
			if still >= 3.0:
				g._hud.draw_circle(still_at, 2.5, Palette.col("warn"))
				g._hud.draw_string(g._font, still_at + Vector2(3, -3), "%ds" % int(still), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Palette.col("warn"))
			still = 0.0
	# what happened
	for ev: Array in g._log.events:
		var at := Vector2.INF
		for sm: Dictionary in g._log.samples:
			if float(sm["t"]) >= float(ev[0]):
				at = to.call(Vector2(float(sm["x"]), float(sm["z"])))
				break
		if at == Vector2.INF:
			continue
		match String(ev[1]):
			"hit":
				g._hud.draw_line(at - Vector2(4, 4), at + Vector2(4, 4), Palette.col("hazard"), 2.0)
				g._hud.draw_line(at - Vector2(4, -4), at + Vector2(4, -4), Palette.col("hazard"), 2.0)
			"rescue", "unstuck":
				g._hud.draw_arc(at, 6.0, 0.0, TAU, 16, Palette.col("warn"), 1.5)
			"junction", "pass bus":
				g._hud.draw_circle(at, 2.0, Palette.col("accent"))
	# autodrive's lane ahead, and the car
	if g._auto and g._ap_pts.size() > 1:
		var lane := PackedVector2Array()
		var s := 0.0
		for k in range(g._ap_pts.size()):
			if k > 0:
				s += g._ap_pts[k - 1].distance_to(g._ap_pts[k])
			if s > 80.0:
				break
			lane.append(to.call(g._ap_pts[k]))
		g._hud.draw_polyline(lane, Color(Palette.col("accent"), 0.9), 1.5)
	var c: Vector2 = to.call(g._pos)
	var f := g._fwd()
	var sd := Vector2(-f.y, f.x)
	g._hud.draw_colored_polygon(PackedVector2Array([c + f * 7.0, c - f * 4.0 + sd * 4.0, c - f * 4.0 - sd * 4.0]), Palette.col("player"))
	var metres := 0.0
	for k in range(1, g._log.samples.size()):
		var a: Dictionary = g._log.samples[k - 1]
		var b: Dictionary = g._log.samples[k]
		metres += Vector2(float(a["x"]), float(a["z"])).distance_to(Vector2(float(b["x"]), float(b["z"])))
	var why: String = g._ap_why if g._auto else "(you drive)"
	g._hud.draw_string(g._font, TRACE_RECT.position + Vector2(6, 13), "the last %d s, %d m · held by: %s · tap the fps text to close" % [
		int(g._log.samples.size() / Streets.DriveLog.HZ), int(metres), why], HORIZONTAL_ALIGNMENT_LEFT, TRACE_RECT.size.x - 12, 9, ink)
	g._hud.draw_rect(TRACE_SAVE, Color(bg, 0.9))
	g._hud.draw_rect(TRACE_SAVE, Color(Palette.col("accent"), 0.9), false, 1.5)
	g._hud.draw_string(g._font, TRACE_SAVE.position + Vector2(0, 14), "save log", HORIZONTAL_ALIGNMENT_CENTER, TRACE_SAVE.size.x, 10, Palette.col("accent"))

func _save_log() -> void:
	var where := g._log.save(self)
	g._show_banner(("drive log saved: " + where.get_file()) if where != "" else "could not save the log", 2.5)
	Probe.event("drive_log", {"file": where})
