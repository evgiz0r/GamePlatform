extends RefCounted
## Where a frame's time goes (moved out of streets.gd; `g` is the game).
## Every part of a physics tick and of a drawn frame is timed (the script's own work, in
## microseconds). The time from one drawn frame to the next that no part accounts for is
## the engine's: drawing the 3D, the shadows, the browser. A frame much slower than the ones
## round it is a hitch: the parts that took its time are kept (the perf view, P or a tap on
## the fps text, shows them with a graph of the last frames) and reported as a "hitch" event
## and a [hitch] line, so a playtest names what chokes.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const PERF_FRAMES := 150
const PERF_RECT := Rect2(486, 74, 146, 20)   ## the fps text: tap it for the perf view
const PERF_GRAPH := Rect2(8, 96, 150, 30)    ## the perf view's frame times, as bars
var _frame_at := 0
var _frame_ms := PackedFloat32Array()   ## the last frames' times, ms, oldest overwritten first
var _frame_i := 0
var _hitches: Array = []             ## newest first, a few: "12.3 s  95 ms  people 61 · rest 30"
var _hitch_n := 0
var _prof_sum := {}                  ## part -> microseconds over the current 2 s spell
var _prof_n := 0                     ## frames in it
var _prof_wall := 0.0                ## their total time, ms
var _prof_spell := 0
var _prof_avg := ""                  ## the last spell's average frame, part by part
## how many parts the average names (5; STREETS_PROF_PARTS=n for tests that want them all)
var _PROF_WORDS := int(OS.get_environment("STREETS_PROF_PARTS")) if OS.get_environment("STREETS_PROF_PARTS") != "" else 5
var _prof_ticks := 0                 ## physics ticks in the current spell (a slow frame runs several)
## "--perf-log" among the command line's user args (a test in a browser): each 2 s spell's frame
## rate and its average frame, part by part, printed
var _perf_log := OS.get_cmdline_user_args().has("--perf-log")

func _prof_frame() -> void:
	var now := Time.get_ticks_usec()
	if _frame_at == 0:
		_frame_at = now
		g._prof = {}
		return
	var ms := (now - _frame_at) / 1000.0
	_frame_at = now
	if _frame_ms.size() < PERF_FRAMES:
		_frame_ms.append(ms)
	else:
		_frame_ms[_frame_i] = ms
		_frame_i = (_frame_i + 1) % PERF_FRAMES
	if ms > 25.0 and _frame_ms.size() > 30:
		var sorted := _frame_ms.duplicate()
		sorted.sort()
		var typical := sorted[sorted.size() / 2]
		if ms > maxf(25.0, typical * 2.0 + 8.0):
			_hitch(ms, typical)
	# the average frame over a 2 s spell, part by part: what it costs all the time, not in spikes
	for k: String in g._prof:
		_prof_sum[k] = int(_prof_sum.get(k, 0)) + int(g._prof[k])
	_prof_n += 1
	_prof_wall += ms
	if now - _prof_spell > 2000000 and _prof_n > 0:
		var parts: Array = []
		var script_ms := 0.0
		for k: String in _prof_sum:
			var pm := float(_prof_sum[k]) / 1000.0 / _prof_n
			if not ":" in k:
				script_ms += pm
			parts.append([pm, k])
		parts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var words: Array = []
		for i in range(mini(_PROF_WORDS, parts.size())):
			words.append(("%s %.2f" if _PROF_WORDS > 5 else "%s %.1f") % [parts[i][1], float(parts[i][0])])
		_prof_avg = "average %.1f ms: drawing and engine %.1f · script %.1f in %.1f ticks (%s)" % [_prof_wall / _prof_n,
			_prof_wall / _prof_n - script_ms, script_ms, float(_prof_ticks) / _prof_n, ", ".join(words)]
		_prof_ticks = 0
		if _perf_log:
			print("[perf] quality %d, %.1f fps%s; %s; %s" % [g._quality, 1000.0 * _prof_n / maxf(_prof_wall, 1.0),
				" (the city still building)" if g._bg_build else "", _prof_avg, g._gpu_line()])
		_prof_sum = {}
		_prof_n = 0
		_prof_wall = 0.0
		_prof_spell = now
	g._prof = {}

func _hitch(ms: float, typical: float) -> void:
	var parts: Array = []
	var script_ms := 0.0
	for k: String in g._prof:
		var pm := float(g._prof[k]) / 1000.0
		if not ":" in k:   # "traffic: route" is already inside "traffic"
			script_ms += pm
		parts.append([pm, k])
	parts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var words: Array = []
	for i in range(mini(5, parts.size())):
		if float(parts[i][0]) >= 1.0:
			var part: String = parts[i][1]
			if part == "building" and g._bstep_slow != "":   # which step of a square ran long (_pause)
				part = "building (%s)" % g._bstep_slow
			words.append("%s %d" % [part, int(round(float(parts[i][0])))])
	words.append("rest %d" % int(round(ms - script_ms)))
	g._bstep_slow = ""
	g._bstep_slow_us = 0
	var line := "%.1f s  %d ms (usual %d)  %s" % [Time.get_ticks_msec() / 1000.0, int(ms), int(typical), " · ".join(words)]
	_hitches.push_front(line)
	if _hitches.size() > 4:
		_hitches.pop_back()
	_hitch_n += 1
	print("[hitch] ", line)
	if _hitch_n <= 40:
		Probe.event("hitch", {"ms": int(ms), "usual": int(typical), "parts": " · ".join(words),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))})

## the slowest of the last frames (ms)
func _worst_ms() -> float:
	var w := 0.0
	for v in _frame_ms:
		w = maxf(w, v)
	return w
