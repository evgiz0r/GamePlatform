extends SceneTree
## Roads off the ground (decks.gd) in the made-up test town (level 4): autodrive is put on a
## street just short of each kind of deck -- the hill's tunnel both ways, the flyover, the
## underpass, a river bridge, the ring road's bridge -- and left to drive for a while. Each
## physics frame it checks the car is at the height of a road it is on (the deck's when on
## a deck, the ground's under a bridge), and counts wall hits, frames in the air and which
## decks it drove. Then fixed views of each, the game frozen.
##
##   OUT=/tmp/decks game/streets/tests/run.sh decks 4
##   RUNS=tunnel_east SHOTS=0 ...   only those runs (comma-separated), no fixed views
##   STREETS_BUILD_ALL=0 SHOTS=0 $GODOT --headless --fixed-fps 60 --path . -s \
##       res://game/streets/tests/decks.gd     the numbers alone, in a minute or two
##
## Good: every run reaches its deck and drives it ("decks driven" lists it), 0 frames off
## the level, no "wall" hits, no frames in the air; the shots show the structure whole
## (no ground over a cutting, no road floating over a gap, lamps lit in the tunnel).
var g: Node

## [name, a point near the start, the way to face (radians, 0 east, +z south), seconds]
const RUNS := [
	["tunnel_east", Vector2(108, -250), 0.0, 40.0],
	["tunnel_west", Vector2(628, -250), PI, 40.0],
	["flyover", Vector2(-545, -108), PI * 0.5, 22.0],
	["underpass", Vector2(-105, -108), PI * 0.5, 22.0],
	["river_bridge", Vector2(0, 350), PI * 0.5, 16.0],
	["ring_bridge", Vector2(578, 368), 2.4, 16.0],
]

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return   # (run headless for the numbers alone: --headless -s ...)
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
	print("shot ", name)

## the heights of every road whose asphalt p is on: its deck's, or the ground's
func _levels_at(p: Vector2) -> Array:
	var out: Array = []
	for code: int in g._near(g._seg_hash, p, 2.0, g.SEG_CELL):
		var ri := code / 4096
		var r: Dictionary = g._roads[ri]
		if not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var j := code % 4096
		var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
		if q.distance_to(p) > float(r["w"]) * 0.5:
			continue
		out.append(g._decks.deck_y(ri, q) if r.has("ys") else g._h(q))
	return out

func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("streets", {"level": 4})
	while g == null or not g._loaded:
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("streets.gd"):
				g = n
	var kinds := {}
	for ri: int in g._decks.decks:
		var k := String(g._roads[ri]["deck"])
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("decks: ", kinds, ", holes cut in the ground: ", g._decks.holes.size(), ", walls: ", g._decks._walls.size())
	var only := OS.get_environment("RUNS").split(",", false)
	for run: Array in RUNS:
		if not only.is_empty() and not only.has(run[0]):
			continue
		await _drive(run)
	if OS.get_environment("SHOTS") != "0":
		await _views()
	quit()

func _drive(run: Array) -> void:
	var name: String = run[0]
	var at: Vector2 = run[1]
	var face := Vector2(cos(float(run[2])), sin(float(run[2])))
	if g._auto:
		g._set_auto(false)
	g._y = g._h(at)
	if not g._land_on_road(at, 30.0, face):
		print("%s: no road near %s" % [name, at])
		return
	g._set_auto(true)
	var t := 0.0
	var secs: float = run[3]
	var off := 0
	var worst := 0.0
	var air := 0
	var hits := {}
	var driven := {}
	var was_hit := ""
	var dist := 0.0
	var last := g._pos as Vector2
	var shot_at := [3.0, secs * 0.45, secs * 0.8]
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		dist += (g._pos as Vector2).distance_to(last)
		last = g._pos
		if g._air:
			air += 1
		else:
			var lv := _levels_at(g._pos)
			if not lv.is_empty():
				var best := INF
				for y: float in lv:
					best = minf(best, absf(y - float(g._y)))
				if best > 0.3:
					off += 1
					worst = maxf(worst, best)
		var on: int = g._decks.deck_at(g._pos, g._y, 1.0)
		if on >= 0:
			var r: Dictionary = g._roads[on]
			var key := "%s %s" % [r["deck"], r["en"] if r["en"] != "" else r["name"]]
			driven[key] = float(driven.get(key, 0.0)) + 1.0 / 60.0
		if g._touch_t > 0.45 and String(g._last_hit) != was_hit:
			was_hit = g._last_hit
			var kind := was_hit.split(" ")[0] + (" " + was_hit.split(" ")[1] if was_hit.begins_with("wall") else "")
			hits[kind] = int(hits.get(kind, 0)) + 1
			print("  %s: hit %s at (%.0f, %.0f), %.0f km/h" % [name, was_hit, g._pos.x, g._pos.y, absf(g._v) * 3.6])
		elif g._touch_t <= 0.0:
			was_hit = ""
		if not shot_at.is_empty() and t >= float(shot_at[0]):
			shot_at.pop_front()
			await _snap("%s_%02d" % [name, int(t)])
	var drove: Array = []
	for k: String in driven:
		drove.append("%s %.0fs" % [k, driven[k]])
	print("%s: %.0f m in %.0f s, off the level %d frames (worst %.2f m), in the air %d frames, hits %s, decks driven: %s" % [
		name, dist, secs, off, worst, air, hits, ", ".join(drove)])

## a fixed camera: eye at (x, metres over the surface there, z), looking at (x, metres over
## the surface there, z). "top": the highest surface (a bridge's deck, the hill over a
## tunnel), "low": the lowest (the ground under a bridge, a tunnel's road)
func _view(name: String, eye: Vector3, look: Vector3, mode := "top") -> void:
	var e2 := Vector2(eye.x, eye.z)
	var l2 := Vector2(look.x, look.z)
	var lv := 1.0e6 if mode == "top" else -1.0e6
	var ey: float = g._decks.surf(e2, lv) + g.road_top() + eye.y
	var ly: float = g._decks.surf(l2, lv) + g.road_top() + look.y
	g.look_from(Vector3(eye.x, ey, eye.z), Vector3(look.x, ly, look.z))
	g._sky_follow()
	await create_timer(0.4).timeout
	await _snap(name)

func _views() -> void:
	if g._auto:
		g._set_auto(false)   # (its junction prompt over every picture)
	g.set_physics_process(false)
	if process_frame.is_connected(g._frame):
		process_frame.disconnect(g._frame)
	g._car.visible = false
	# HaNasi's bridge over the river: from the water, from the bank, from its deck
	await _view("view_river_under", Vector3(-32, 3.2, 404), Vector3(0, 4.0, 404), "low")
	await _view("view_river_bank", Vector3(-40, 1.7, 372), Vector3(0, 0.5, 404), "top")
	await _view("view_river_deck", Vector3(2.5, 1.5, 365), Vector3(2.5, 1.0, 440), "top")
	await _view("view_river_air", Vector3(60, 28, 470), Vector3(0, 0, 404))
	# the ring road's skewed bridge, from the water
	await _view("view_ring_bridge", Vector3(505, 3.0, 405), Vector3(534, 5.0, 417), "low")
	# the flyover: from the boulevard under it, beside its embankment, from its top
	await _view("view_flyover_under", Vector3(-590, 1.6, 1.5), Vector3(-545, 6.0, 1.0), "low")
	await _view("view_flyover_side", Vector3(-572, 1.7, -111), Vector3(-545, 3.0, -50), "low")
	await _view("view_flyover_top", Vector3(-543, 1.5, -85), Vector3(-543, 0.5, 10), "top")
	await _view("view_flyover_air", Vector3(-610, 35, -90), Vector3(-545, 0, -10))
	# the underpass: down its cutting to the mouth, and from the boulevard over it
	await _view("view_underpass", Vector3(-103, 1.8, -95), Vector3(-105, 1.0, -22), "low")
	await _view("view_underpass_over", Vector3(-118, 1.7, -27), Vector3(-105, -4.0, -55), "top")
	await _view("view_underpass_air", Vector3(-160, 30, -110), Vector3(-105, 0, -40))
	# the hill's tunnel: into its west mouth, inside it, out of its east mouth, the hill above
	await _view("view_tunnel_west", Vector3(104, 2.0, -252), Vector3(170, 0.5, -250), "low")
	await _view("view_tunnel_inside", Vector3(300, 1.8, -248), Vector3(380, 1.5, -250), "low")
	await _view("view_tunnel_east", Vector3(636, 2.4, -248), Vector3(570, 0.5, -250), "low")
	await _view("view_tunnel_air", Vector3(60, 60, -330), Vector3(200, 0, -250))
