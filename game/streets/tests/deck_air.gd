extends SceneTree
## Where a car leaves the road on a deck: autodrive put on a deck road (`AT=x,z`, facing
## `FACE` degrees, 0 east, +z south; on the highest surface there) and driven for `SECS`;
## every quarter second, and every frame it is in the air, prints where it is, its height,
## the surface under it, its speed and the deck it is on. For a run of tests/decks.gd that
## reports frames "in the air".
##
##   AT=745.6,-1127.6 FACE=200 LEVEL=7 $GODOT --headless --fixed-fps 60 --path . \
##       -s res://game/streets/tests/deck_air.gd
var g: Node

func _initialize() -> void:
	_run()

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var at := OS.get_environment("AT").split(",")
	var p := Vector2(float(at[0]), float(at[1]))
	var face := deg_to_rad(float(OS.get_environment("FACE")))
	g._pos = p
	g._yaw = face
	g._y = g._decks.surf(p, 1.0e6)
	if not g._land_on_road(p, 30.0, Vector2.from_angle(face)):
		print("no road near ", p)
		quit()
		return
	g._set_auto(true)
	var t := 0.0
	var next := 0.0
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 14.0
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		if t >= next or g._air:
			next = t + 0.25 if t >= next else next
			var on: int = g._decks.deck_at(g._pos, g._y, 1.5)
			var what := "ground"
			if on >= 0:
				var r: Dictionary = g._roads[on]
				what = "%s %s #%d" % [r["deck"], r["en"] if r["en"] != "" else r["name"], on]
			print("t %5.2f  at (%.1f, %.1f)  y %.2f  surf %.2f  ground %.2f  v %.1f km/h  %s%s" % [t, g._pos.x, g._pos.y,
				g._y, g._decks.surf(g._pos, g._y), g._h(g._pos), g._v * 3.6, what, "  AIR" if g._air else ""])
	quit()
