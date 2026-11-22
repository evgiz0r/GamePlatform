extends SceneTree
## You on foot at a walk, a jog and a sprint: which clip your figure plays and how fast, and
## what its feet then cover (the clip's own pace, tests/foot_slide.gd CLIP=, times its speed)
## against how fast you go -- the slide. Speeds set by hand on the walking figure each tick.
##   LEVEL=1 $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/sprint_clip.gd
var g: Node
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
	g._get_out()
	await create_timer(1.0).timeout
	var pace := {"Walk": g._walk_clip_v(), "Run": 1.05 if g._people_maker().on() else 0.53, "Sprint": g.SPRINT_CLIP_V}
	for v: float in [1.4, 2.1, 4.5, 7.0, 9.5]:
		var seen := ""
		var sc := 0.0
		for f in range(30):
			g._v = v
			await process_frame
			seen = g._me_anim
			sc = float(g._me.anim.speed_scale) if g._me.anim != null else 0.0
		var feet: float = float(pace.get(seen, 0.0)) * sc
		print("  %.1f m/s: %s x%.2f, feet %.2f m/s, slide %.2f" % [v, seen, sc, feet, v - feet])
	quit()
