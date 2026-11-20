extends SceneTree
## What the game sounds like: drives on autodrive for $SECS seconds (default 25) from the start,
## recording the game's own mix (an AudioEffectRecord on the master bus), and saves it as
## $OUT/sound_drive.wav to listen to, printing its loudness and how much of it a laptop's or a
## phone's speaker can play (above 200 Hz) second by second, with the speed. Run it headless,
## where the frames are fast (the silent audio driver still mixes, a little faster than real
## time, so the picture is right, not the timing):
##   OUT=/tmp/x $GODOT --headless --path . -s res://game/streets/tests/sound_drive.gd
var g: Node
var rec: AudioEffectRecord

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	await create_timer(1.0).timeout
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 25.0
	await create_timer(2.0).timeout   # (standing first: the idle)
	g._set_auto(true)
	var t := 0.0
	while t < secs:
		await create_timer(1.0).timeout
		t += 1.0
		print("%3d s  %3d km/h  rpm %4d  gear %d" % [int(t), int(absf(g._v) * 3.6), int(g._rpm), g._gear_n])
	rec.set_recording_active(false)
	var w: AudioStreamWAV = rec.get_recording()
	w.save_to_wav(OS.get_environment("OUT") + "/sound_drive.wav")
	# loudness and speaker share, per second of the recording
	var frames := w.data.size() / 4
	var rate := w.mix_rate
	for s in range(0, frames / rate):
		var sum := 0.0
		var hi := 0.0
		var prev := 0.0
		for i in range(s * rate, (s + 1) * rate, 2):
			var l := float(w.data.decode_s16(i * 4)) / 32768.0
			sum += l * l
			hi += (l - prev) * (l - prev)   # (a first difference: the highs, roughly)
			prev = l
		var rms := sqrt(sum / (rate / 2))
		print("second %2d: %5.1f dB, brightness %.2f" % [s, linear_to_db(maxf(rms, 1e-6)), sqrt(hi / maxf(sum, 1e-9))])
	quit(0)
