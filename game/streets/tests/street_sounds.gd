extends SceneTree
## The street's own sounds (streets.gd "the sounds of the street"): out of the car at the
## start, standing, by day then at night, recording the game's mix (an AudioEffectRecord on
## the master bus) to $OUT/street_day.wav and $OUT/street_night.wav to listen to, and
## printing every two seconds what each layer is easing to -- birds, crickets, voices (dB),
## how far the voices are, the trees round you -- with a dog made to bark early on. Good:
## birds and voices by day and no crickets; crickets and no birds at night; the voices
## a few dB down at night. Run it headless (the silent audio driver still mixes).
##   OUT=/tmp/x $GODOT --headless --path . -s res://game/streets/tests/street_sounds.gd
var g: Node
var rec: AudioEffectRecord

func _initialize() -> void:
	_run()

func _listen(name: String, secs: float) -> void:
	rec.set_recording_active(true)
	var t := 0.0
	while t < secs:
		await create_timer(2.0).timeout
		t += 2.0
		var c: Vector2i = g._cell(g._pos, g.Sounds.SND_CELL)
		var trees := 0
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				trees += int(g._sounds._snd_trees.get(c + Vector2i(dx, dz), 0))
		var vp: Vector3 = g._sounds._voices.position
		print("%s %2d s: birds %5.1f  crickets %5.1f  voices %5.1f dB at %3d m  dog %s  (trees round: %d)" % [name, int(t),
			g._sounds._amb_db[0], g._sounds._amb_db[1], g._sounds._amb_db[2], int(Vector2(vp.x, vp.z).distance_to(g._pos)), g._sounds._dog.playing, trees])
	rec.set_recording_active(false)
	var w: AudioStreamWAV = rec.get_recording()
	w.save_to_wav(OS.get_environment("OUT") + "/street_%s.wav" % name)

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	g._get_out()
	g._sounds._dog_t = 4.0   # (a bark early, to hear one)
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	await _listen("day", 14.0)
	g._set_night(true)
	await create_timer(2.0).timeout
	await _listen("night", 10.0)
	quit(0)
