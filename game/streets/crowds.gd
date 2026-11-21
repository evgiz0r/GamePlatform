extends RefCounted
## People where the street walkers never go: shoppers down a market's walkway, stopping at
## its stalls, and people on a beach -- walking or jogging along the wet sand, and a few
## standing in the sea. The street walkers (streets.gd's _walkers) keep to the pavements of
## kerbed roads, so a market's pedestrian street and the sand stood empty.
##
## Lines to walk ("promenades") are handed in as the town is set up: landmarks.gd's
## _market_line gives each market piece with its stalls as stops, beach.gd's setup each
## stretch of shore inland of the water, and the spots in the water for the waders. People
## are made the first time a line is near you (a town with none makes nobody), put down
## where you cannot see them appear (streets.gd's _spawn_ok), walk their line and turn back
## at its ends, and are taken away unseen when you have left them behind.

const MARKET_PEOPLE := 28     ## shoppers kept round you in a market (a crowd: within 50 m either way of you)
const SHORE_PEOPLE := 12      ## walkers and joggers along the shore
const WADERS := 9             ## people standing in the sea
const SHORE_OFF := Vector2(3.5, 9.0)   ## the shore's walkers this far up from the water
const WADE_OFF := Vector2(3.0, 16.0)   ## the waders this far out
const MAKE_PER_TICK := 2      ## people made a frame while the pools fill (a model each: a stutter all at once)

var g: Node
var lines: Array = []         ## {kind "market" | "shore", pts, cum, hw (half the width walked), stops (add_line), box}
var wade_spots: Array = []    ## [where, facing, y]: for g._place_still(..., "wade")
var strollers: Array = []     ## {actor, kind, li (line), s, dir, speed, lane, lat, stop_t, ...}
var waders: Array = []        ## {actor, spot}
var stalls_up := {}           ## Vector2i(stall's middle x10): the stalls that were built (landmarks.gd)
var count := {}               ## for the tests: lines by kind, stops taken, people placed
var _want := {"market": 0, "shore": 0}
var _near_t := 0.0
var _near := {"market": [], "shore": []}   ## the lines within reach now, by kind

var rng: RandomNumberGenerator
var _headless := DisplayServer.get_name() == "headless"   ## (no stalls are built headless: every stop is taken as one)

func _init(game: Node) -> void:
	g = game
	rng = g._people_rng

## a line to walk; `hw` how far either side of it people walk; `stops` [[s, side, where, face]]
func add_line(kind: String, pts: PackedVector2Array, hw: float, stops: Array = []) -> void:
	if pts.size() < 2:
		return
	var cum := PackedFloat32Array([0.0])
	var box := Rect2(pts[0], Vector2.ZERO)
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
		box = box.expand(pts[i])
	if cum[cum.size() - 1] < 12.0:
		return
	stops.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	lines.append({"kind": kind, "pts": pts, "cum": cum, "hw": hw, "stops": stops, "box": box})
	count[kind + "_lines"] = int(count.get(kind + "_lines", 0)) + 1
	count[kind + "_m"] = int(count.get(kind + "_m", 0)) + int(cum[cum.size() - 1])

func add_wade_spot(p: Vector2, face: Vector2, y: float) -> void:
	wade_spots.append([p, face, y])
	count["wade_spots"] = int(count.get("wade_spots", 0)) + 1

## everyone placed, for streets.gd's list of who is where (dicts with "actor")
func everyone() -> Array:
	return strollers + waders

## every frame from streets.gd's _people_tick
func tick(dt: float) -> void:
	if lines.is_empty() and wade_spots.is_empty():
		return
	_near_t -= dt
	if _near_t <= 0.0:
		_near_t = 1.5
		_find_near()
		g._place_still(waders, wade_spots, "wade")
		for c: Dictionary in waders:
			var ca: Actor3D = c["actor"]
			g._people_awake(ca, Vector2(ca.position.x, ca.position.z))
	_make(dt)
	var placed := false
	for w: Dictionary in strollers:
		var a: Actor3D = w["actor"]
		if int(w["li"]) < 0:
			w["retry"] = float(w.get("retry", 0.0)) - dt
			if float(w["retry"]) <= 0.0 and not placed:
				w["retry"] = 0.7
				placed = true
				_place(w)
			continue
		if _walk(w, dt) and not placed:
			placed = true
			_retire(w)

## which lines are within reach, and how many people each kind wants now
func _find_near() -> void:
	var reach := Rect2(g._pos - Vector2.ONE * g.PEOPLE_RANGE, Vector2.ONE * g.PEOPLE_RANGE * 2.0)
	_near = {"market": [], "shore": []}
	for li in range(lines.size()):
		var ln: Dictionary = lines[li]
		if (ln["box"] as Rect2).grow(5.0).intersects(reach):
			(_near[ln["kind"]] as Array).append(li)
	_want["market"] = MARKET_PEOPLE if not (_near["market"] as Array).is_empty() else 0
	_want["shore"] = SHORE_PEOPLE if not (_near["shore"] as Array).is_empty() else 0
	if not wade_spots.is_empty() and waders.size() < WADERS:
		for sp: Array in wade_spots:
			if (sp[0] as Vector2).distance_to(g._pos) < g.PEOPLE_RANGE:
				_want["wade"] = WADERS
				break

## the pools, filled a couple of people a frame the first time they are wanted
func _make(_dt: float) -> void:
	var made := 0
	for kind: String in ["market", "shore"]:
		var have := 0
		for w: Dictionary in strollers:
			if String(w["kind"]) == kind:
				have += 1
		while have < int(_want[kind]) and made < MAKE_PER_TICK:
			var a := _person(have + (0 if kind == "market" else 3))
			a.visible = false
			if a.anim != null:
				a.anim.active = false
			var w := {"actor": a, "kind": kind, "li": -1, "s": 0.0, "dir": 1.0, "lane": 0.0, "lat": 0.0,
				"stop_t": 0.0, "retry": 0.0}
			if kind == "market":
				w["speed"] = rng.randf_range(0.55, 1.05)   # (a market is walked slowly, looking)
				w["carry"] = false
				var k := rng.randi()
				# bags of shopping in hand (the carrying walk round nothing was arms out for a hug)
				g._carry(a, "bag" if k % 100 < 40 else ("handbag" if k % 100 < 52 else ("backpack" if k % 100 < 60 else "")), k)
			else:
				w["run"] = rng.randf() < 0.25              # (joggers along the water's edge)
				w["speed"] = rng.randf_range(2.4, 3.1) if w["run"] else rng.randf_range(0.9, 1.35)
				w["carry"] = false
			strollers.append(w)
			have += 1
			made += 1
	while waders.size() < int(_want.get("wade", 0)) and made < MAKE_PER_TICK:
		var a := _person(waders.size() + 1)
		a.play("Idle", true, rng.randf_range(0.6, 0.95))
		a.visible = false
		waders.append({"actor": a, "spot": Vector2.INF})
		made += 1

func _person(k: int) -> Actor3D:
	var a := Actor3D.new()
	g.world.add_child(a)
	a.set_character(g.PEOPLE[k % g.PEOPLE.size()], rng.randf_range(g.ADULT_LO, g.ADULT_HI))
	g._humanize(a, hash(a.get_instance_id()))
	g._people_lod(a)
	return a

## onto a line near you, somewhere you cannot see them appear (behind you, past where people
## are drawn, behind a block); a few tries, then again on a later frame
func _place(w: Dictionary) -> void:
	var a: Actor3D = w["actor"]
	var near: Array = _near[w["kind"]]
	var have := 0
	for o: Dictionary in strollers:
		if String(o["kind"]) == String(w["kind"]) and int(o["li"]) >= 0:
			have += 1
	if near.is_empty() or have >= int(_want[w["kind"]]):
		return
	for _try in range(6):
		var li: int = near[rng.randi() % near.size()]
		var ln: Dictionary = lines[li]
		var pts: PackedVector2Array = ln["pts"]
		var cum: PackedFloat32Array = ln["cum"]
		var total := cum[cum.size() - 1]
		var s := rng.randf() * total
		if String(ln["kind"]) == "market" and _try < 4:   # (a crowd round you, not spread down the whole market)
			s = clampf(_s_near(ln, g._pos) + rng.randf_range(-50.0, 50.0), 0.0, total)
		var lane := rng.randf_range(-1.0, 1.0) * float(ln["hw"])
		var p := _at(ln, s, lane)
		var d: float = p.distance_to(g._pos)
		if d > g.PEOPLE_SEEN + 8.0 or not g._spawn_ok(p):
			continue
		if g._push_out(p, 0.3, true, false) != Vector2.ZERO:
			continue
		w["li"] = li
		w["s"] = s
		w["lane"] = lane
		w["lat"] = lane
		w["dir"] = 1.0 if rng.randf() < 0.5 else -1.0
		w["stop_t"] = 0.0
		w["lane_t"] = rng.randf_range(2.0, 7.0)
		w["next_stop"] = s + float(w["dir"]) * 2.0
		w.erase("yaw")
		_go(w)
		a.visible = true
		count["placed_" + String(w["kind"])] = int(count.get("placed_" + String(w["kind"]), 0)) + 1
		return

## how far along a line its nearest point to p is
func _s_near(ln: Dictionary, p: Vector2) -> float:
	var pts: PackedVector2Array = ln["pts"]
	var cum: PackedFloat32Array = ln["cum"]
	var best := 0.0
	var bd := INF
	for i in range(pts.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
		var d := q.distance_squared_to(p)
		if d < bd:
			bd = d
			best = cum[i] + pts[i].distance_to(q)
	return best

func _go(w: Dictionary) -> void:
	var a: Actor3D = w["actor"]
	if w.get("run", false):
		a.play("Run", true, float(w["speed"]) / 3.4)
	else:
		a.play("Walk_Carry" if w["carry"] else "Walk", true, float(w["speed"]) / 1.35)

func _retire(w: Dictionary) -> void:
	var a: Actor3D = w["actor"]
	a.visible = false
	if a.anim != null:
		a.anim.active = false   # (hidden, it still animated every frame)
	w["li"] = -1
	w["retry"] = 0.5

## the point s along a line, `lat` to its left
func _at(ln: Dictionary, s: float, lat: float) -> Vector2:
	var pts: PackedVector2Array = ln["pts"]
	var cum: PackedFloat32Array = ln["cum"]
	var total := cum[cum.size() - 1]
	s = clampf(s, 0.0, total)
	var p: Vector2 = g._along(pts, cum, s)
	var q: Vector2 = g._along(pts, cum, minf(s + 0.6, total)) if s < total - 0.6 else p
	var b: Vector2 = g._along(pts, cum, maxf(s - 0.6, 0.0)) if q == p else p
	var fw := (q - b).normalized() if q != b else Vector2.RIGHT
	return p + Vector2(-fw.y, fw.x) * lat

## a stroller's frame: along the line, aside for others, stopping at a stall now and then;
## true when they should go (out of reach, or at an end of the line out of sight)
func _walk(w: Dictionary, dt: float) -> bool:
	var a: Actor3D = w["actor"]
	var ln: Dictionary = lines[int(w["li"])]
	var cum: PackedFloat32Array = ln["cum"]
	var total := cum[cum.size() - 1]
	var hw: float = ln["hw"]
	var me := a.get_instance_id()
	var cur := Vector2(a.position.x, a.position.z)
	if float(w["stop_t"]) > 0.0:   # at a stall, looking at what is on it
		w["stop_t"] = float(w["stop_t"]) - dt
		var at: Vector2 = w["stop_at"]
		var p := cur.lerp(at, 1.0 - exp(-dt * 3.0))
		p += g._people_apart(p, me, -1)
		p += g._push_out(p, 0.25, true, false)   # (a stall's post or its neighbour's: drawn, 5 frames in one)
		a.position = Vector3(p.x, _y(w, p), p.y)
		var face: Vector2 = w["stop_face"]
		var yaw: float = w.get("yaw", face.angle())
		yaw = lerp_angle(yaw, face.angle(), 1.0 - exp(-dt * 4.0))
		w["yaw"] = yaw
		a.face(Vector3(cos(yaw), 0, sin(yaw)))
		if float(w["stop_t"]) <= 0.0:
			w["next_stop"] = float(w["s"]) + float(w["dir"]) * rng.randf_range(4.0, 12.0)
			_go(w)
		g._people_awake(a, p)
		return p.distance_to(g._pos) > g.PEOPLE_SEEN + 12.0
	# slower behind someone close ahead (a market crowd shuffles; a jogger does not run through)
	var fw0: Vector2 = Vector2(cos(float(w.get("yaw", 0.0))), sin(float(w.get("yaw", 0.0))))
	var pace: float = w["speed"]
	for k in range(g._people_at.size()):
		if g._people_who[k] == me:
			continue
		var rel: Vector2 = g._people_at[k] - cur
		var fore := rel.dot(fw0)
		if fore > 0.2 and fore < 1.3 and absf(rel.dot(Vector2(-fw0.y, fw0.x))) < 0.5:
			pace *= 0.45
			break
	var s: float = float(w["s"]) + float(w["dir"]) * pace * dt
	if s < 0.0 or s > total:
		var end := _at(ln, clampf(s, 0.0, total), float(w["lat"]))
		if g._spawn_ok(end):
			return true   # (on out of the market, up the beach: gone, someone else will come)
		w["dir"] = -float(w["dir"])
		s = clampf(s, 0.0, total)
		w["next_stop"] = s + float(w["dir"]) * 3.0
	w["s"] = s
	# a new place across the way now and then (people drift; a jogger keeps a line)
	w["lane_t"] = float(w.get("lane_t", 3.0)) - dt
	if float(w["lane_t"]) <= 0.0:
		w["lane_t"] = rng.randf_range(3.0, 9.0)
		w["lane"] = clampf(float(w["lane"]) + rng.randf_range(-0.6, 0.6) * hw, -hw, hw)
	# a stall coming up on this side: now and then a stop at it
	var stops: Array = ln["stops"]
	if not stops.is_empty() and (s - float(w["next_stop"])) * float(w["dir"]) >= 0.0:
		w["next_stop"] = s + float(w["dir"]) * rng.randf_range(2.5, 6.0)
		if rng.randf() < 0.35:
			var st := _stop_near(stops, s, float(w["lat"]))
			if not st.is_empty() and (_headless or stalls_up.has(Vector2i(((st[4] as Vector2) * 10.0).round()))):
				w["stop_at"] = st[2]
				w["stop_face"] = st[3]
				w["stop_t"] = rng.randf_range(2.0, 7.0)
				w["lat"] = clampf(float(st[1]) * hw, -hw, hw)
				w["lane"] = w["lat"]
				a.play("Idle", true, rng.randf_range(0.7, 1.0))
				count["stops"] = int(count.get("stops", 0)) + 1
				return false
	var lat: float = w["lat"]
	lat = lerpf(lat, float(w["lane"]), 1.0 - exp(-dt * 1.2))
	w["lat"] = lat
	var p := _at(ln, s, lat)
	var ahead := _at(ln, clampf(s + float(w["dir"]) * 0.6, 0.0, total), lat) - p
	p += g._people_apart(p, me, -1)
	if g._walking and p.distance_to(g._pos) < 0.65 and p.distance_to(g._pos) > 0.01:   # (never into you on foot)
		p = g._pos + (p - g._pos).normalized() * 0.65
	p += g._push_out(p, 0.25, true, false)
	a.position = Vector3(p.x, _y(w, p), p.y)
	if ahead.length_squared() > 0.0001:
		var want := ahead.angle()
		var yaw: float = w.get("yaw", want)
		yaw = lerp_angle(yaw, want, 1.0 - exp(-dt * 5.0))
		w["yaw"] = yaw
		a.face(Vector3(cos(yaw), 0, sin(yaw)))
	g._people_awake(a, p)
	return p.distance_to(g._pos) > g.PEOPLE_SEEN + 12.0

## the stall nearest s on the side of the way `lat` is on (or either, from the middle)
func _stop_near(stops: Array, s: float, lat: float) -> Array:
	var best: Array = []
	var bd := 1.6
	for st: Array in stops:
		var ds := absf(float(st[0]) - s)
		if ds < bd and (absf(lat) < 0.3 or signf(float(st[1])) == signf(lat)):
			bd = ds
			best = st
	return best

func _y(w: Dictionary, p: Vector2) -> float:
	return g._walk_y(p) if String(w["kind"]) == "market" else g._h(p)
