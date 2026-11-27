extends RefCounted
## The loading bar (moved out of streets.gd; `g` is the game).
## A bar under the loading text and "about N s" (user: "those steps where I don't know how long
## I have to wait -- sometimes 3 seconds, sometimes 20"). The estimate is this device's own last
## load of the city (LOAD_LOG): the city file, the set-up, one square, the warm-up -- the last
## kept twice, as it was on the same build (the browser kept its compiled shaders) and on the
## first load of a new build (it compiles them again: the slow case). No load of this city
## yet: another city's, its file scaled by size. None at all: the bar by phase, no seconds.
## Slower or quicker than last time so far, the rest is taken to be so too (`pace`).

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const LOAD_LOG := "user://streets_load.json"
const LOAD_PHASES := ["file", "setup", "squares", "warm"]
const LOAD_W := 400.0                ## the bar's width (the loading text's)
var _load_est := {}                  ## ms: file, setup, square (each), n (squares), warm; empty: no history
var _load_at := {}                   ## phase -> ms it began
var _load_phase := "file"
var _load_n := 1                     ## steps in the phase (squares; the warm-up's frames)
var _load_i := 0                     ## the step it is on
var _load_i_at := 0                  ## ms that step began
var _load_squares := 1.0             ## squares built behind the text this time
var _load_fill: ColorRect
var _load_eta: Label
var _build_id := ""                  ## res://build.txt: which build this is

func _load_bar_begin() -> void:
	var track := ColorRect.new()
	track.color = Palette.col("bg_alt")
	track.position = Vector2(0, 50)
	track.size = Vector2(LOAD_W, 6)
	g._loading.add_child(track)
	_load_fill = ColorRect.new()
	_load_fill.color = Palette.col("accent")
	_load_fill.position = track.position
	_load_fill.size = Vector2(0, 6)
	g._loading.add_child(_load_fill)
	_load_eta = UIKit.label("", 13, "ink")
	_load_eta.add_theme_font_override("font", g._font)
	_load_eta.add_theme_color_override("font_outline_color", Palette.col("bg"))
	_load_eta.add_theme_constant_override("outline_size", 4)
	_load_eta.position = Vector2(0, 60)
	_load_eta.size = Vector2(LOAD_W, 20)
	_load_eta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_load_eta.modulate.a = 0.8
	g._loading.add_child(_load_eta)
	if FileAccess.file_exists("res://build.txt"):
		_build_id = FileAccess.get_file_as_string("res://build.txt").strip_edges()
	_load_est = _load_guess()
	_load_into("file")

func _load_log() -> Dictionary:
	if not FileAccess.file_exists(LOAD_LOG):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(LOAD_LOG))
	return d if d is Dictionary else {}

func _city_kb(id: String) -> float:
	var f := FileAccess.open(get_script().resource_path.get_base_dir() + "/cities/" + id + ".json", FileAccess.READ)
	return f.get_length() / 1024.0 if f != null else 0.0

## what this load should take, from the log
func _load_guess() -> Dictionary:
	var log := _load_log()
	var city := String(g._place["city"])
	var mine: Dictionary = log.get(city, {})
	var src := mine
	var scale := 1.0
	if not src.has("square"):   # this city never loaded here: another one's, the file scaled
		src = {}
		for k: String in log:
			if (log[k] as Dictionary).has("square") and float((log[k] as Dictionary).get("file_kb", 0.0)) > 0.0:
				src = log[k]
				break
		if src.is_empty():
			return {}
		scale = _city_kb(city) / float(src["file_kb"])
	var new_build := String(mine.get("build", "")) != _build_id
	return {"file": float(src["file"]) * scale, "setup": float(src["setup"]), "square": float(src["square"]),
		"n": float(src["n"]), "warm": float(src["warm_new"] if new_build else src["warm"])}

func _load_into(phase: String, n: int = 1) -> void:
	_load_phase = phase
	_load_at[phase] = Time.get_ticks_msec()
	_load_n = maxi(n, 1)
	_load_i = 0
	_load_i_at = _load_at[phase]
	if phase == "squares":
		_load_squares = float(maxi(n, 1))
		if not _load_est.is_empty():
			_load_est["n"] = _load_squares
	_load_tick()

func _load_sub(i: int) -> void:
	_load_i = i
	_load_i_at = Time.get_ticks_msec()
	_load_tick()

func _load_phase_ms(phase: String) -> float:
	return float(_load_est["square"]) * float(_load_est["n"]) if phase == "squares" else float(_load_est[phase])

func _load_tick() -> void:
	if _load_fill == null or not is_instance_valid(_load_fill):
		return
	var idx := LOAD_PHASES.find(_load_phase)
	var through := clampf(float(_load_i) / _load_n, 0.0, 1.0)
	if _load_est.is_empty():   # the first load on this device: the bar by phase alone
		var w := [0.15, 0.1, 0.5, 0.25]
		var f := 0.0
		for i in range(idx):
			f += w[i]
		_load_fill.size.x = LOAD_W * (f + w[idx] * through)
		_load_eta.text = "timing it, for next time"
		return
	var now := Time.get_ticks_msec()
	var total := 0.0
	var done := 0.0
	for i in range(LOAD_PHASES.size()):
		var ms := _load_phase_ms(LOAD_PHASES[i])
		total += ms
		if i < idx:
			done += ms
	var step := _load_phase_ms(_load_phase) / _load_n
	done += step * _load_i + minf(float(now - _load_i_at), step * 0.9)
	var spent := float(now - int(_load_at["file"]))
	var pace := clampf(spent / done, 0.5, 3.0) if done > 1500.0 else 1.0
	var left := (total - done) * pace / 1000.0
	_load_fill.size.x = LOAD_W * clampf(done / maxf(total, 1.0), 0.0, 1.0)
	_load_eta.text = "almost there" if left < 1.5 else "about %d s" % ceili(left)

## what this load took, for the next one's estimate
func _load_save() -> void:
	if not _load_at.has("warm") or not _load_at.has("squares"):
		return
	var now := Time.get_ticks_msec()
	var log := _load_log()
	var city := String(g._place["city"])
	var old: Dictionary = log.get(city, {})
	var squares := float(int(_load_at["warm"]) - int(_load_at["squares"]))
	var warm := float(now - int(_load_at["warm"]))
	var same := old.has("warm") and String(old.get("build", "")) == _build_id
	var rec := {"file": float(int(_load_at["setup"]) - int(_load_at["file"])),
		"setup": float(int(_load_at["squares"]) - int(_load_at["setup"])),
		"square": squares / maxf(_load_squares, 1.0), "n": _load_squares, "file_kb": _city_kb(city), "build": _build_id,
		"warm": warm if same or not old.has("warm") else float(old["warm"]),
		"warm_new": float(old.get("warm_new", warm)) if same else warm}
	log[city] = rec
	var f := FileAccess.open(LOAD_LOG, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(log))
