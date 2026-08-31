extends Node
## Telemetry + the ASCII "eye". This is how the AI FEELS the game without burning tokens
## on screenshots. A full playtest report is ~1-2k tokens; a single PNG is more than that
## and tells you less about causality.
##
## Game code calls Probe.event() / Probe.track(). In normal play `enabled` is false and
## every call is a cheap early-out, so there is no cost to shipping the instrumentation.

const MAX_EVENTS := 500
const MAX_SNAPS := 3

var enabled := false
var t := 0.0
var title := "untitled"

## The slice of the world the ASCII snapshot renders. GameMode sets this.
var world_rect := Rect2(0, 0, 640, 360)

var _events: Array = []
var _counts := {}
var _tracked: Array = []
var _snaps: Array = []
var _notes: Array = []
var _fps_min := 9999.0

func reset(new_title: String) -> void:
	title = new_title
	t = 0.0
	_events.clear(); _counts.clear(); _tracked.clear()
	_snaps.clear(); _notes.clear()
	player_seen = false
	hazard_seen = false
	_fps_min = 9999.0

func _process(delta: float) -> void:
	if not enabled:
		return
	t += delta
	var fps := Engine.get_frames_per_second()
	if fps > 0.0 and t > 1.0:
		_fps_min = minf(_fps_min, fps)

## ---- recording -------------------------------------------------------------

func event(kind: String, data: Dictionary = {}) -> void:
	if not enabled:
		return
	count(kind)
	if _events.size() < MAX_EVENTS:
		_events.append({"t": t, "kind": kind, "data": data})

func count(key: String, n: int = 1) -> void:
	if not enabled:
		return
	_counts[key] = _counts.get(key, 0) + n

## A problem worth surfacing in the report (unreachable pickup, spawn off-screen...).
func note(msg: String) -> void:
	if not enabled:
		return
	if not _notes.has(msg):
		_notes.append(msg)

## Register a node so it shows up in ASCII snapshots. `sym` should be one char.
func track(node: Node2D, sym: String) -> void:
	if not enabled:
		return
	var s := sym.substr(0, 1)
	if s == "@":
		player_seen = true
	elif s == "x":
		hazard_seen = true
	_tracked.append({"ref": weakref(node), "sym": s})

func counts() -> Dictionary:
	return _counts

## ---- perception (used by sim bots, and by checks) --------------------------

var player_seen := false
var hazard_seen := false

func first_with(sym: String) -> Node2D:
	for e in _tracked:
		if e["sym"] == sym:
			var n = e["ref"].get_ref()
			if n != null and is_instance_valid(n):
				return n
	return null

func nearest(from: Vector2, sym: String) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for e in _tracked:
		if e["sym"] != sym:
			continue
		var n = e["ref"].get_ref()
		if n == null or not is_instance_valid(n):
			continue
		var d: float = from.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

## ---- the ASCII eye ---------------------------------------------------------

## Renders tracked nodes into a text grid. This is the single most useful signal:
## it shows the AI *spatially* what happened -- enemies clumped in a corner, the player
## stuck in a wall, a pickup spawned outside the play area.
func snapshot(cols: int = 48, rows: int = 14) -> String:
	if not enabled:
		return ""
	var grid: Array = []
	for r in rows:
		var row: Array = []
		for c in cols:
			row.append(".")
		grid.append(row)

	var live := 0
	for entry in _tracked:
		var n = entry["ref"].get_ref()
		if n == null or not is_instance_valid(n):
			continue
		live += 1
		var p: Vector2 = n.global_position
		var fx := (p.x - world_rect.position.x) / maxf(1.0, world_rect.size.x)
		var fy := (p.y - world_rect.position.y) / maxf(1.0, world_rect.size.y)
		if fx < 0.0 or fx >= 1.0 or fy < 0.0 or fy >= 1.0:
			note("%s at %s is outside the play area" % [entry["sym"], str(p.round())])
			continue
		var cx := clampi(int(fx * cols), 0, cols - 1)
		var cy := clampi(int(fy * rows), 0, rows - 1)
		grid[cy][cx] = entry["sym"]

	var out := "+" + "-".repeat(cols) + "+\n"
	for r in rows:
		out += "|" + "".join(grid[r]) + "|\n"
	out += "+" + "-".repeat(cols) + "+"
	_prune()
	return out

func capture(label: String = "") -> void:
	if not enabled:
		return
	var head := "t=%.1fs  %s" % [t, label]
	_snaps.append(head + "\n" + snapshot())

func _prune() -> void:
	var kept: Array = []
	for e in _tracked:
		if e["ref"].get_ref() != null:
			kept.append(e)
	_tracked = kept

## ---- the report ------------------------------------------------------------

func report(header: Dictionary = {}) -> String:
	var L: Array = []
	L.append("=== PLAYTEST: %s ===" % title)
	for k in header:
		L.append("%s: %s" % [k, str(header[k])])
	L.append("duration: %.1fs" % t)

	L.append("")
	L.append("-- TIMELINE (first time each thing happened) --")
	var seen := {}
	for e in _events:
		if seen.has(e["kind"]):
			continue
		seen[e["kind"]] = true
		var extra := "" if e["data"].is_empty() else "  " + str(e["data"])
		L.append("  %6.2fs  %-18s x%d%s" % [e["t"], e["kind"], _counts.get(e["kind"], 1), extra])
	if seen.is_empty():
		L.append("  (nothing was recorded -- the game may not be emitting events)")

	L.append("")
	L.append("-- COUNTS --")
	var parts: Array = []
	for k in _counts:
		parts.append("%s=%d" % [k, _counts[k]])
	L.append("  " + ("  ".join(parts) if parts.size() > 0 else "(none)"))

	if _snaps.size() > 0:
		L.append("")
		L.append("-- WHAT IT LOOKED LIKE --")
		for s in _snaps:
			L.append(s)

	if _notes.size() > 0:
		L.append("")
		L.append("-- WARNINGS --")
		for n in _notes:
			L.append("  ! " + n)

	return "\n".join(L)
