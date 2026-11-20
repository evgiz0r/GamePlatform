extends SceneTree
## Speed limits: what each kind of road is driven at (OSM's `ms` where the bake has it, else
## the guess by kind), then autodrive for SECS seconds of game time -- how long it spent at
## each limit and how far over the road's limit it went. A town baked before the bake kept
## `ms` shows the guesses alone (50 in town).
##   game/streets/tests/run.sh speed_limits 7      SECS=60 for longer
var g: Node
func _initialize() -> void:
	_run()
func _run() -> void:
	await create_timer(0.5).timeout
	root.get_node("Flow").start_game("streets", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var by := {}
	for r: Dictionary in g._roads:
		if not r["drive"] or r["pv"]:
			continue
		var k := String(r["k"])
		if not by.has(k):
			by[k] = {}
		var kmh := int(round(float(r["speed"]) * 3.6))
		by[k][kmh] = int(by[k].get(kmh, 0)) + 1
	print("road pieces by kind, at km/h:")
	for k: String in by:
		print("  %-15s %s" % [k, str(by[k])])
	await create_timer(1.0).timeout
	g._set_auto(true)
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 40.0
	var t := 0.0
	var at := {}          # limit km/h -> seconds driven under it
	var over_s := 0.0     # seconds more than 10% (and 2 km/h) over the limit
	var worst := 0.0      # km/h over at worst
	var fastest := 0.0
	var last := Time.get_ticks_msec()
	while t < secs:
		await physics_frame
		var dt := 1.0 / float(Engine.physics_ticks_per_second) * Engine.time_scale
		t += dt
		if g._ap_lim.is_empty():
			continue
		var lim := float(g._ap_lim[0]) * 3.6
		var v := absf(float(g._v)) * 3.6
		var key := int(round(lim))
		at[key] = float(at.get(key, 0.0)) + dt
		fastest = maxf(fastest, v)
		if v > lim * 1.1 + 2.0:
			over_s += dt
			worst = maxf(worst, v - lim)
		if Time.get_ticks_msec() - last > 20000:
			last = Time.get_ticks_msec()
			print("  ... %.0f s of %.0f" % [t, secs])
	print("autodrive %.0f s: time under each limit (km/h: s) %s" % [t, str(at)])
	print("  fastest %.0f km/h; over its limit by >10%%: %.1f s, worst %.0f km/h over" % [fastest, over_s, worst])
	quit(0)
