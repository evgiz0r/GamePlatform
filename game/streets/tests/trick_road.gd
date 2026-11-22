extends SceneTree
## The trick road (level 36, data_tools/make_showcase.py): its test drive started as the level
## starts it -- watch only, autodrive on, once round -- and traced. Every half second, and every
## frame the car is in the air, where it is, its height and the surface under it, its speed and
## the piece of road it is on; each take-off and landing (how fast it met the ground, a hard one
## over 5 m/s); per piece the slowest and fastest it went. With a display, a still each time the
## car enters a piece and a few in the air (`OUT`), from the chase camera.
##
##   OUT=<dir> game/streets/tests/run.sh trick_road 36      (stills; ~2 min on this PC)
##   SECS=120 ... headless for the numbers alone
## Good: "arrived" once round in about 1:40; take-offs off the jump's kicker and the bridge's
## drop, each landing under 5 m/s; 0 crashes; the tunnel driven at the road's speed.
var g: Node

func _initialize() -> void:
	_run()

func _game() -> Node:
	for n in root.find_children("*", "Node2D", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
			return n
	return null

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("OUT") == "":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")

func _run() -> void:
	await create_timer(0.3).timeout
	var lv := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 36
	root.get_node("Flow").start_game("streets", {"level": lv})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		g = _game()
	print("watching: %s, autodrive %s, route %s" % [g._watching(), g._auto, g._route.get("id", "none")])
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 150.0
	var t := 0.0
	var next := 0.0
	var was_air := false
	var air_t := 0.0
	var air_from := Vector2.ZERO
	var top := 0.0
	var piece := ""
	var span := {}   # piece -> [slowest, fastest] km/h
	var takeoffs := 0
	var hard := 0
	var air_shots := 0
	var crashes0: int = int(g.get("_crashes")) if g.get("_crashes") != null else 0
	var arrived := false
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		var on: int = g._decks.deck_at(g._pos, g._y, 1.5)
		var seg: Dictionary = g._nearest_seg(g._pos, 12.0, true, true, g._y)
		var name := "?"
		if on >= 0:
			name = String(g._roads[on]["en"])
		elif not seg.is_empty():
			name = String(g._roads[int(seg["road"])]["en"])
		var kmh: float = absf(g._v) * 3.6
		if name != piece:
			piece = name
			print("t %6.2f  onto %s at %.0f km/h  (%.1f, %.1f) y %.2f" % [t, name, kmh, g._pos.x, g._pos.y, g._y])
			await _snap("%03d_%s" % [int(t), name.replace(" ", "_").to_lower()])
		if not span.has(name):
			span[name] = [kmh, kmh]
		span[name][0] = minf(span[name][0], kmh)
		span[name][1] = maxf(span[name][1], kmh)
		if g._air and not was_air:
			takeoffs += 1
			air_t = 0.0
			air_from = g._pos
			top = g._y
			print("t %6.2f  TAKE-OFF at %.0f km/h on %s (%.1f, %.1f) y %.2f" % [t, kmh, name, g._pos.x, g._pos.y, g._y])
		if g._air:
			air_t += 1.0 / 60.0
			top = maxf(top, g._y)
			if air_shots < 12 and fmod(air_t, 0.2) < 1.0 / 60.0:
				air_shots += 1
				await _snap("%03d_air_%d" % [int(t), air_shots])
		if was_air and not g._air:
			var ground: float = g._decks.surf(g._pos, g._y)
			print("t %6.2f  LANDED after %.2f s, %.1f m on, %.1f m up at most (%.1f over the take-off), %.0f km/h; vy %.1f" % [t, air_t,
				g._pos.distance_to(air_from), top - ground, top, kmh, g._vy])
		was_air = g._air
		if t >= next:
			next = t + 0.5
			print("t %6.2f  (%.1f, %.1f)  y %.2f  surf %.2f  %3.0f km/h  %s%s" % [t, g._pos.x, g._pos.y, g._y,
				g._decks.surf(g._pos, g._y), kmh, name, "  AIR" if g._air else ""])
		if not g._dest_on and t > 5.0:
			print("t %6.2f  ARRIVED (no destination left)" % t)
			arrived = true
			break
	var crashes: int = (int(g.get("_crashes")) if g.get("_crashes") != null else 0) - crashes0
	print("pieces (slowest-fastest km/h):")
	for k: String in span:
		print("  %-14s %3.0f-%3.0f" % [k, span[k][0], span[k][1]])
	print("take-offs %d, arrived %s, crashes %d, auto %s, watching %s" % [takeoffs, arrived, crashes, g._auto, g._watching()])
	quit()
