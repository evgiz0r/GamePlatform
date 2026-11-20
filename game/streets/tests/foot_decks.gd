extends SceneTree
## Footbridges and footpath tunnels (decks.gd, infer): on foot over each of a real town's
## highest footbridges and through its footpath tunnels -- up the ramp or the stairs, across,
## down the other side -- steered along the path the whole way. Each physics frame it checks
## the walker is at the height of what it is on (the deck's, the ground's), and counts the
## frames it was not, what pushed it back ("steep ground", a wall) and how far along it got.
## Then fixed views of the first few, the game frozen.
##
##   OUT=/tmp/foot game/streets/tests/run.sh foot_decks 1
##   SHOTS=0 ...                        the numbers alone
##   ONLY=3 ...                         only the first three routes
##
## Good: every route walked to its end ("got 100%"), up to its top ("top" the height the
## footbridge clears, about 5.8 m over a street), 0 frames off the level, no pushes; the
## shots show a paved deck with railings, stairs where it is steep, a lit tube under a road.
var g: Node

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("SHOTS") == "0":
		return
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## a footpath deck and the footpath decks it runs on into, end to end: one line to walk
func _chain(ri: int) -> PackedVector2Array:
	var line: PackedVector2Array = (g._roads[ri]["pts"] as PackedVector2Array).duplicate()
	var used := {ri: true}
	for way: int in [1, -1]:
		var cur := ri
		while true:
			var ids: PackedInt32Array = g._roads[cur]["ids"]
			var end_n: int = ids[ids.size() - 1] if way == 1 else ids[0]
			var nxt := -1
			for e: Vector2i in g._node_roads[end_n]:
				var r: Dictionary = g._roads[e.x]
				if not used.has(e.x) and not r["drive"] and r.has("ys"):
					nxt = e.x
					break
			if nxt < 0:
				break
			used[nxt] = true
			var pts: PackedVector2Array = (g._roads[nxt]["pts"] as PackedVector2Array).duplicate()
			var nids: PackedInt32Array = g._roads[nxt]["ids"]
			# its points in the order walked from end_n
			if (nids[0] == end_n) != (way == 1):
				pts.reverse()
			if way == 1:
				line.append_array(pts.slice(1))
			else:
				var head := pts.slice(0, pts.size() - 1)
				head.append_array(line)
				line = head
			cur = nxt
	# and a few metres on the ground either side, to walk on and off
	var a := line[0] + (line[0] - line[1]).normalized() * 6.0
	var b := line[line.size() - 1] + (line[line.size() - 1] - line[line.size() - 2]).normalized() * 6.0
	line.insert(0, a)
	line.append(b)
	return line

func _routes() -> Array:
	var cand: Array = []
	for ri: int in g._decks.decks:
		var r: Dictionary = g._roads[ri]
		if r["drive"] or not (String(r["deck"]) in ["br", "tu"]):
			continue
		var ys: PackedFloat32Array = r["ys"]
		var gs: PackedFloat32Array = r["gs"]
		var up := 0.0
		for j in range(ys.size()):
			up = maxf(up, absf(ys[j] - gs[j]))
		if up < 2.5:
			continue   # (a footbridge over a creek, at the banks' height: nothing to climb)
		cand.append([up + (100.0 if String(r["deck"]) == "tu" else 0.0), ri])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	var taken: Array = []
	for c: Array in cand:
		var ri: int = c[1]
		var r: Dictionary = g._roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var mid: Vector2 = pts[pts.size() / 2].lerp(pts[(pts.size() - 1) / 2], 0.5)
		if taken.any(func(t): return (t as Vector2).distance_to(mid) < 60.0):
			continue
		taken.append(mid)
		var nm := "%s_%s_%d" % ["tunnel" if String(r["deck"]) == "tu" else "bridge",
			String(r["en"] if r["en"] != "" else r["name"]).replace(" ", "_"), ri]
		out.append([nm, _chain(ri), fmod(float(c[0]), 100.0), ri])
	return out

func _run() -> void:
	await create_timer(0.3).timeout
	var level := int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	root.get_node("Flow").start_game("streets", {"level": level})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var kinds := {}
	for ri: int in g._decks.decks:
		var r: Dictionary = g._roads[ri]
		if not r["drive"]:
			kinds[String(r["deck"])] = int(kinds.get(String(r["deck"]), 0)) + 1
	print("footpath decks: ", kinds, "  inferred: ", g._inferred)
	var routes := _routes()
	var only := int(OS.get_environment("ONLY")) if OS.get_environment("ONLY") != "" else 8
	routes = routes.slice(0, only)
	await create_timer(0.5).timeout
	g._toggle_walk()
	for rt: Array in routes:
		await _walk(rt)
	Input.action_release("move_up")
	Input.action_release("action_a")
	if OS.get_environment("SHOTS") != "0":
		await _views(routes.slice(0, 3))
	quit()

## along `line` on foot (running), steering for a point a few metres on along it
func _walk(rt: Array) -> void:
	var name: String = rt[0]
	var line: PackedVector2Array = rt[1]
	var cum := PackedFloat32Array([0.0])
	for i in range(1, line.size()):
		cum.append(cum[i - 1] + line[i - 1].distance_to(line[i]))
	var total: float = cum[cum.size() - 1]
	g._pos = line[0]
	g._prev_pos = line[0]
	g._y = g._walk_y(line[0])
	g._yaw = atan2(line[1].y - line[0].y, line[1].x - line[0].x)
	g._v = 0.0
	Input.action_press("move_up")
	Input.action_press("action_a")
	var t := 0.0
	var secs := total / 5.0 + 8.0
	var off := 0
	var worst := 0.0
	var top := -INF
	var low := INF
	var reached := 0.0
	var pushes := {}   # what pushed it: frames
	var on_deck := {}
	while t < secs and reached < total - 1.0:
		var p_was: Vector2 = g._pos
		await physics_frame
		var dt := Engine.time_scale / Engine.physics_ticks_per_second
		t += dt
		# pushed: moved other than its own step (the label alone is not a push: placing the
		# people relabels "last hit" every tick as it tries spots for them)
		var shove: float = ((g._pos - p_was) - g._fwd() * g._v * dt).length()
		if shove > 0.03:
			var why := String(g._last_hit).split(" ")[0] + (" " + String(g._last_hit).split(" ")[1] if String(g._last_hit).begins_with("wall") else "")
			pushes[why] = int(pushes.get(why, 0)) + 1
			if int(pushes[why]) <= 2:
				print("  %s: pushed %.2f m (%s) at (%.1f, %.1f), %.0f m along, y %.2f over the ground %.2f" % [name, shove, g._last_hit,
					g._pos.x, g._pos.y, reached, g._y, g._h(g._pos)])
		# where along the line it is, and a point 3 m on
		var best := INF
		var at := 0.0
		for i in range(line.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(g._pos, line[i], line[i + 1])
			var d: float = q.distance_to(g._pos)
			if d < best - 0.01 and absf(cum[i] + q.distance_to(line[i]) - reached) < 25.0:
				best = d
				at = cum[i] + q.distance_to(line[i])
		reached = maxf(reached, at)
		var aim := _along(line, cum, minf(at + 3.0, total))
		g._yaw = atan2(aim.y - g._pos.y, aim.x - g._pos.x)
		if OS.get_environment("TRACE") != "" and fmod(t, 0.5) < Engine.time_scale / Engine.physics_ticks_per_second:
			print("    t %.1f at (%.1f, %.1f) %.0f m along, y %.2f ground %.2f surf %.2f, v %.1f, walking %s, ts %.2f" % [t, g._pos.x, g._pos.y, reached,
				g._y, g._h(g._pos), g._decks.surf(g._pos, g._y), g._v, g._walking, Engine.time_scale])
		var want: float = g._walk_y(g._pos, g._y)
		var miss := absf(float(g._y) - want)
		if miss > 0.35:
			off += 1
			worst = maxf(worst, miss)
			if off <= 2:
				var dk: int = g._decks.deck_at(g._pos, want, 0.3)
				print("  %s: off the level by %.2f m at (%.1f, %.1f), %.0f m along, on %s" % [name, miss, g._pos.x, g._pos.y, reached,
					("%s %s" % [g._roads[dk]["deck"], g._roads[dk]["k"]]) if dk >= 0 else "the ground"])
		top = maxf(top, float(g._y) - g._h(g._pos))
		low = minf(low, float(g._y) - g._h(g._pos))
		var on: int = g._decks.deck_at(g._pos, g._y, 1.0)
		if on >= 0:
			on_deck[String(g._roads[on]["deck"])] = true
	Input.action_release("move_up")
	Input.action_release("action_a")
	print("%s: %.0f m long, %.1f m %s the ground at most (wanted %.1f), got %.0f%% in %.0f s, off the level %d frames (worst %.2f m), pushed %s, on %s" % [
		name, total, -low if name.begins_with("tunnel") else top, "under" if name.begins_with("tunnel") else "over", float(rt[2]), 100.0 * reached / maxf(total, 0.001), t, off, worst, pushes, on_deck.keys()])

func _along(line: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in range(line.size() - 1):
		if s <= cum[i + 1]:
			return line[i].lerp(line[i + 1], (s - cum[i]) / maxf(cum[i + 1] - cum[i], 0.001))
	return line[line.size() - 1]

## for each of the first routes: from the ground beside it, from its deck (or inside), and
## from above
func _views(routes: Array) -> void:
	g.set_physics_process(false)
	if process_frame.is_connected(g._frame):
		process_frame.disconnect(g._frame)
	for rt: Array in routes:
		var ri: int = rt[3]
		var r: Dictionary = g._roads[ri]
		var pts: PackedVector2Array = r["pts"]
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
		var total: float = cum[cum.size() - 1]
		var mid := _along(pts, cum, total * 0.5)
		var d := (_along(pts, cum, minf(total * 0.5 + 2.0, total)) - _along(pts, cum, maxf(total * 0.5 - 2.0, 0.0))).normalized()
		var side := Vector2(-d.y, d.x)
		var deck_y: float = g._decks.deck_y(ri, mid) + g.road_top()
		var tunnel := String(r["deck"]) == "tu"
		# beside it, on the ground (for a tunnel: looking down its ramp at the mouth)
		var low := mid + side * 22.0 - d * 8.0
		var gy: float = g._h(low) + g.road_top()
		if tunnel:
			var e0: Vector2 = pts[0] - (pts[1] - pts[0]).normalized() * 16.0
			g.look_from(Vector3(e0.x, g._h(e0) + g.road_top() + 1.8, e0.y), Vector3(pts[0].x, deck_y + 1.0, pts[0].y))
		else:
			g.look_from(Vector3(low.x, gy + 1.7, low.y), Vector3(mid.x, deck_y + 0.5, mid.y))
		g._sky_follow()
		await create_timer(0.4).timeout
		await _snap("%s_side" % rt[0])
		# on it: along the deck from a third of the way
		var on := _along(pts, cum, total * 0.3)
		var ahead := _along(pts, cum, minf(total * 0.8, total))
		g.look_from(Vector3(on.x, g._decks.deck_y(ri, on) + g.road_top() + 1.6, on.y), Vector3(ahead.x, g._decks.deck_y(ri, ahead) + g.road_top() + 1.2, ahead.y))
		await create_timer(0.4).timeout
		await _snap("%s_on" % rt[0])
		# from above
		var air := mid + side * 30.0 - d * 30.0
		g.look_from(Vector3(air.x, g._h(air) + g.road_top() + 26.0, air.y), Vector3(mid.x, deck_y, mid.y))
		await create_timer(0.4).timeout
		await _snap("%s_air" % rt[0])
