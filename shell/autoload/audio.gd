extends Node
## SFX pool + music. Tolerant of missing files on purpose: a game that asks for a sound
## that has not been added yet should NOT crash, it should just be silent and say so once.

const POOL_SIZE := 12
const SFX_DIR := "res://assets/audio/sfx/"

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer
var _cache := {}
var _missing := {}

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	add_child(_music)

## The one global on/off. Checked here rather than in each game, so every game -- current
## and future -- respects it automatically with no per-game code at all. A per-game volume
## trick (see CLAUDE.md) still applies on top of this when sound IS on; this is a separate,
## harder gate that skips playback entirely regardless of any volume math upstream.
func muted() -> bool:
	return bool(SaveData.data.get("muted", false))

## play("jump") looks for res://assets/audio/sfx/jump.ogg (or .wav)
func play(sound: String, pitch_jitter: float = 0.08, volume_db: float = 0.0) -> void:
	if muted():
		return
	var stream: AudioStream = _load(sound)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db + linear_to_db(SaveData.data.get("volume_sfx", 0.8))
	p.play()

func music(track: String, fade: float = 0.6) -> void:
	if muted():
		return
	var stream: AudioStream = _load(track, "res://assets/audio/music/")
	if stream == null:
		return
	if _music.playing and _music.stream == stream:
		return
	_music.stream = stream
	_music.volume_db = linear_to_db(maxf(0.001, SaveData.data.get("volume_music", 0.7)))
	_music.play()

func stop_music() -> void:
	_music.stop()

func _load(name: String, dir: String = SFX_DIR) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	for ext in [".ogg", ".wav", ".mp3"]:
		var path: String = dir + name + ext
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			_cache[name] = s
			return s
	if not _missing.has(name):
		_missing[name] = true
		Probe.note("sound '%s' is missing (looked in %s) -- game ran silent" % [name, dir])
	return null
