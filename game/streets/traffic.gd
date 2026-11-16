extends RefCounted
## Other cars: a couple of dozen driving the real streets round the player, in their lane,
## keeping their distance, slowing for corners and stopping at red lights.
##
## Each car follows a path of lane points planned on the road graph the way autodrive plans
## the player's: a road to its end, then a pick of the ways on (mostly straight on, main
## roads rather than side streets, never against a one-way). They are not physics: they
## move along the path at their own speed, and the player's car bumps into them as it
## would a parked one. All of them are one multimesh, drawn between physics ticks like the
## player's car, so a few dozen cost about what one does.

const COUNT := 22
const NEAR := 240.0          ## further than this from the player a car is taken away...
const SPAWN_MIN := 120.0     ## ...and put back on a street this far off,
const SPAWN_MAX := 215.0     ##    out of sight when it can be
const ACCEL := 2.0           ## m/s^2
const BRAKE := 3.0           ## what a driver plans to brake at
const BRAKE_HARD := 7.5      ## what it will do when it has to
const GAP := 2.2             ## bumper to bumper when stopped (m)
const HEADWAY := 1.2         ## seconds behind the car in front, moving
const LEN := 4.4
const LANE_W := 1.5          ## a car on my path: its middle within this of my lane line
const CURVE_LAT := 2.6       ## sideways pull a driver takes a corner at (m/s^2)
const LIGHT_SKIP := 45.0     ## lights this close after one already passed are the far side of the same junction
## how much traffic each kind of road gets, and how keen a driver is to turn into it
const KIND_W := {"motorway": 1.0, "trunk": 1.0, "primary": 1.0, "secondary": 1.0, "tertiary": 0.85,
	"motorway_link": 0.6, "trunk_link": 0.6, "primary_link": 0.6, "secondary_link": 0.6,
	"tertiary_link": 0.5, "unclassified": 0.45, "residential": 0.3, "living_street": 0.08}

class Car:
	var pts := PackedVector2Array()   ## the lane ahead (and a little behind)
	var cum := PackedFloat32Array()   ## distance along it to each point
	var node := PackedInt32Array()    ## the graph node at each point
	var vmax := PackedFloat32Array()  ## the speed allowed at each point (limit, corners)
	var end := Vector3i(-1, 0, 0)     ## the last leg planned: road, last index, direction
	var k := 0                        ## the segment it is on
	var s := 0.0                      ## how far along pts
	var v := 0.0
	var pos := Vector2.ZERO
	var yaw := 0.0                    ## atan2(dir.x, dir.y): the multimesh's way of turning
	var pitch := 0.0
	var prev_pos := Vector2.ZERO
	var prev_yaw := 0.0
	var pace := 1.0                   ## this driver's share of the limit
	var braking := 0.0                ## brake lights, 0..1
	var wait := 0.0                   ## seconds held up by another car
	var blocker := -2                 ## who holds it up: a car's index, -1 the player
	var ignore := 0.0                 ## seconds it ignores crossing cars (a standoff broken)
	var hit := 0.0                    ## seconds it sits stunned after the player hit it
	var last_light := -1000.0         ## s at the last light it drove through
	var alive := false

var g: Node                           ## the game: its road graph, lights, ground, player
var cars: Array = []
var rng := RandomNumberGenerator.new()
var hit_index := -1                   ## the car the player last bumped
var _clock := 0.0
## junctions taken: node -> [car, until (clock), way in, way out]. A car about to cross a
## junction takes it; another whose way crosses that one waits at its edge till it is free.
## Without this, cars from side streets only saw each other once inside it, too late.
var _taken := {}
var _degree := {}                     ## node -> how many ways out of it (3+: a junction)
const TAKE_AHEAD := 22.0              ## a junction is taken this far before it
var _mm: MultiMesh
var _brake_mat: ShaderMaterial
var _roads: Array
var _node_roads: Array
var _node_r: PackedFloat32Array

const BRAKE_SHADER := """
shader_type spatial;
uniform vec4 col : source_color;
varying float brake;
void vertex() { brake = INSTANCE_CUSTOM.r; }
void fragment() {
	ALBEDO = col.rgb;
	EMISSION = col.rgb * (0.25 + 2.8 * brake);
}
"""

func setup(game: Node) -> void:
	g = game
	_roads = g._roads
	_node_roads = g._node_roads
	_node_r = g._node_r
	rng.seed = hash(g._city_name) + 23
	var mesh: ArrayMesh = g._parked_mesh()
	_brake_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = BRAKE_SHADER
	_brake_mat.shader = sh
	mesh.surface_set_material(mesh.get_surface_count() - 1, _brake_mat)   # the tail lights
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = mesh
	_mm.instance_count = COUNT
	var b: Rect2 = g._bounds
	_mm.custom_aabb = AABB(Vector3(b.position.x - 500.0, -200.0, b.position.y - 500.0),
		Vector3(b.size.x + 1000.0, 600.0, b.size.y + 1000.0))   # no box to recompute every frame
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	g.world.add_child(mi)
	var palette := [Palette.col("ink"), Palette.col("ink").lerp(Palette.col("bg_alt"), 0.35),
		Palette.col("bg_alt").lerp(Palette.col("ink"), 0.3), Palette.col("bg").lerp(Palette.col("bg_alt"), 0.5),
		Palette.col("player").lerp(Palette.col("bg"), 0.5), Palette.col("hazard").lerp(Palette.col("bg"), 0.3),
		Palette.col("warn").lerp(Palette.col("bg"), 0.45), Palette.col("ink").lerp(Palette.col("bg_alt"), 0.2)]
	for i in range(COUNT):
		var c := Car.new()
		c.pace = rng.randf_range(0.82, 1.06)
		cars.append(c)
		_mm.set_instance_color(i, palette[rng.randi() % palette.size()])
		c.alive = _spawn(c, true)
		_hide_or_show(i)
	retint()

func retint() -> void:
	_brake_mat.set_shader_parameter("col", Palette.col("hazard"))

func alive_count() -> int:
	var n := 0
	for c: Car in cars:
		if c.alive:
			n += 1
	return n

## ---- every physics tick ------------------------------------------------------------------

func tick(dt: float) -> void:
	_clock += dt
	var me: Vector2 = g._pos
	for i in range(cars.size()):
		var c: Car = cars[i]
		c.prev_pos = c.pos
		c.prev_yaw = c.yaw
		if not c.alive or c.pos.distance_to(me) > NEAR or (c.wait > 25.0 and not _in_view(c.pos)):
			c.alive = _spawn(c, false)
			_hide_or_show(i)
			continue
		while c.cum[c.cum.size() - 1] - c.s < 140.0:
			if not _next(c):
				break
		_trim(c)
		var vt := _target(c, i, dt)
		if c.hit > 0.0:
			c.hit -= dt
			vt = 0.0
		var was := c.v
		c.v = move_toward(c.v, vt, (ACCEL if vt > c.v else BRAKE_HARD) * dt)
		c.braking = clampf(c.braking + (dt * 8.0 if c.v < was - 0.01 or c.v < 0.2 else -dt * 4.0), 0.0, 1.0)
		var before := c.s
		c.s = minf(c.s + c.v * dt, c.cum[c.cum.size() - 1])
		_passed_lights(c, before)
		if c.s >= c.cum[c.cum.size() - 1] - 0.01:
			c.alive = false   # the end of a road with nowhere on: gone, back elsewhere next tick
			continue
		_place(c)

## the speed this car wants now: the limit, the corners ahead braked down to in time, a
## red light ahead, the car in front
func _target(c: Car, i: int, dt: float) -> float:
	_seek(c)
	var vt: float = c.vmax[mini(c.k + 1, c.vmax.size() - 1)]
	for j in range(c.k + 1, c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > 90.0:
			break
		vt = minf(vt, sqrt(c.vmax[j] * c.vmax[j] + 2.0 * BRAKE * maxf(dist, 0.0)))
	var lv := _light_ahead(c)
	vt = minf(vt, lv)
	if lv == INF:
		vt = minf(vt, _junction_ahead(c, i))
	# the car (or the player) in front, on this lane
	var look := clampf(10.0 + c.v * 3.0, 18.0, 55.0)
	var best := INF
	var who := -2
	var lead_v := 0.0
	var fwd := Vector2(sin(c.yaw), cos(c.yaw))
	for j in range(cars.size() + 1):
		var q: Vector2
		var ov: float
		var oyaw: float
		if j == cars.size():
			q = g._pos
			ov = maxf(float(g._v), 0.0)
			oyaw = atan2(cos(float(g._yaw)), sin(float(g._yaw)))   # the player's heading, as this file turns

		else:
			if j == i:
				continue
			var o: Car = cars[j]
			if not o.alive:
				continue
			q = o.pos
			ov = o.v
			oyaw = o.yaw
		var d2 := q.distance_squared_to(c.pos)
		if d2 > (look + 6.0) * (look + 6.0) or (q - c.pos).dot(fwd) < -2.0:
			continue
		if c.ignore > 0.0 and j < cars.size() and absf(angle_difference(oyaw, c.yaw)) > 0.8:
			continue   # breaking a standoff: go, and let the crossing car wait
		var gap := _path_gap(c, q, look)
		if gap < best:
			best = gap
			who = -1 if j == cars.size() else j
			# moving with me: its speed along my way, else treat it as standing
			lead_v = ov * maxf(0.0, cos(angle_difference(oyaw, c.yaw)))
	c.ignore = maxf(0.0, c.ignore - dt)
	if best < INF:
		var room := best - LEN - GAP - lead_v * HEADWAY
		var follow := sqrt(maxf(0.0, lead_v * lead_v + 2.0 * BRAKE * maxf(room, 0.0)))
		if room <= 0.0:
			follow = 0.0
		if follow < vt:
			vt = follow
			if c.v < 0.3:
				c.wait += dt
				c.blocker = who
				# two cars each waiting for the other in a junction: the lower number goes
				if c.wait > 2.5 and who >= 0:
					var o: Car = cars[who]
					if o.blocker == i and o.wait > 2.5 and i < who:
						c.ignore = 3.0
						c.wait = 0.0
			return vt
	c.wait = 0.0
	c.blocker = -2
	return vt

## the first traffic light ahead that counts: stop at its line on red, and on amber when
## there is room to; through on green
func _light_ahead(c: Car) -> float:
	var counted := c.last_light
	for j in range(c.k + 1, c.pts.size()):
		var dist := c.cum[j] - c.s
		if dist > 80.0:
			break
		var n := c.node[j]
		if not g._sig_set.has(n) or c.cum[j] - counted < LIGHT_SKIP:
			continue
		counted = c.cum[j]
		var dir := c.pts[j] - c.pts[maxi(j - 1, 0)]
		if dir.length_squared() < 0.01 and j >= 2:
			dir = c.pts[j] - c.pts[j - 2]
		var state: String = g._light_at(n, dir)
		var stop := dist - (_node_r[n] + 2.0)
		if state == "g" or stop < -0.5:
			return INF
		if state == "y" and c.v * c.v > 2.0 * BRAKE * maxf(stop, 0.1):
			return INF   # too late to stop on amber: through
		return sqrt(2.0 * BRAKE * maxf(stop - 0.3, 0.0))
	return INF

## the next junction on my way: take it, or wait at its edge while a car on a crossing
## way has it (or the player is coming into it)
func _junction_ahead(c: Car, i: int) -> float:
	for j in range(c.k + 1, c.pts.size() - 1):
		var dist := c.cum[j] - c.s
		if dist > TAKE_AHEAD + c.v * 1.5:
			return INF
		var n := c.node[j]
		if n < 0 or _ways_out(n) < 3:
			continue
		var edge := dist - (_node_r[n] + 2.0)
		if edge < -1.0:
			return INF   # in it already: carry on through
		var way_in := (c.pts[j] - c.pts[maxi(j - 1, 0)]).normalized()
		var way_out := Vector2.ZERO
		for m in range(j + 1, c.pts.size()):
			if c.cum[m] - c.cum[j] > 3.0:
				way_out = (c.pts[m] - c.pts[j]).normalized()
				break
		var stop := sqrt(2.0 * BRAKE * maxf(edge - 0.3, 0.0))
		# the player coming into it from another way has it
		var to_me: Vector2 = Vector2(_nodes_at(n)) - g._pos
		var pfwd := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
		if to_me.length() < _node_r[n] + 14.0 and float(g._v) > 1.5 and pfwd.dot(to_me) > 0.0 \
				and pfwd.dot(way_in) < 0.85:
			return stop
		var t: Array = _taken.get(n, [])
		if not t.is_empty() and int(t[0]) != i and float(t[1]) > _clock and cars[int(t[0])].alive \
				and _crosses(way_in, way_out, t[2], t[3]):
			return stop
		var through := (dist + _node_r[n] * 2.0 + LEN + 2.0) / maxf(c.v, 2.5)
		_taken[n] = [i, _clock + through + 0.5, way_in, way_out]
		return INF
	return INF

func _nodes_at(n: int) -> Vector2:
	return g._nodes[n]

func _ways_out(n: int) -> int:
	if _degree.has(n):
		return _degree[n]
	var count := 0
	for e: Vector2i in _node_roads[n]:
		var r: Dictionary = _roads[e.x]
		if not r["drive"]:
			continue
		var p: PackedVector2Array = r["pts"]
		if e.y > 0:
			count += 1
		if e.y < p.size() - 1:
			count += 1
	_degree[n] = count
	return count

## do two ways through a junction cross? Not when both come in the same way (the one
## behind follows), and not when they come from opposite sides and both go straight on.
func _crosses(in_a: Vector2, out_a: Vector2, in_b: Vector2, out_b: Vector2) -> bool:
	if in_a.dot(in_b) > 0.85:
		return false
	if in_a.dot(in_b) < -0.85 and in_a.dot(out_a) > 0.85 and in_b.dot(out_b) > 0.85:
		return false
	return true

func _passed_lights(c: Car, before: float) -> void:
	for j in range(c.k, c.pts.size()):
		if c.cum[j] > c.s:
			break
		if c.cum[j] > before and g._sig_set.has(c.node[j]) and c.cum[j] - c.last_light >= LIGHT_SKIP:
			c.last_light = c.cum[j]

## how far along my lane ahead something at q is (centre to centre), or INF if it is not
## on it
func _path_gap(c: Car, q: Vector2, look: float) -> float:
	for j in range(c.k, c.pts.size() - 1):
		var base := c.cum[j] - c.s
		if base > look:
			break
		var a := c.pts[j]
		var b := c.pts[j + 1]
		var cp := Geometry2D.get_closest_point_to_segment(q, a, b)
		if cp.distance_to(q) < LANE_W:
			var along := base + a.distance_to(cp)
			if along > 0.5:
				return along
	return INF

## the same for any lane (the player's autodrive): [gap centre to centre, speed of the car
## there along the lane], or [INF, 0]
func lead_on(path: PackedVector2Array, from: Vector2, look: float, ignore_crossing: bool) -> Array:
	var best := INF
	var bv := 0.0
	if path.size() < 2:
		return [best, bv]
	var start := Geometry2D.get_closest_point_to_segment(from, path[0], path[1])
	for c: Car in cars:
		if not c.alive or c.pos.distance_squared_to(from) > (look + 6.0) * (look + 6.0):
			continue
		var base := -path[0].distance_to(start)
		for j in range(path.size() - 1):
			if base > look:
				break
			var a := path[j]
			var b := path[j + 1]
			var cp := Geometry2D.get_closest_point_to_segment(c.pos, a, b)
			if cp.distance_to(c.pos) < LANE_W:
				var along := base + a.distance_to(cp)
				var dir := (b - a).normalized()
				var cdir := Vector2(sin(c.yaw), cos(c.yaw))
				var same := dir.dot(cdir)
				if along > 0.5 and along < best and not (ignore_crossing and same < 0.6):
					best = along
					bv = c.v * maxf(same, 0.0)
				break
			base += a.distance_to(b)
	return [best, bv]

## ---- the path -----------------------------------------------------------------------------

func _spawn(c: Car, first: bool) -> bool:
	var me: Vector2 = g._pos
	var look := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
	for _try in range(24):
		var ang := rng.randf() * TAU
		var d := rng.randf_range(35.0 if first else SPAWN_MIN, SPAWN_MAX)
		var q := me + Vector2(cos(ang), sin(ang)) * d
		if not first and d < 185.0 and Vector2(cos(ang), sin(ang)).dot(look) > 0.0:
			continue   # in front of the camera and near enough to see it appear
		var hit: Dictionary = g._nearest_seg(q, 40.0, true, true)
		if hit.is_empty():
			continue
		var ri: int = hit["road"]
		var r: Dictionary = _roads[ri]
		if r["k"] == "service" or rng.randf() > float(KIND_W.get(r["k"], 0.25)):
			continue
		var at: Vector2 = hit["q"]
		if at.distance_to(me) < 30.0:
			continue
		var crowded := false
		for o: Car in cars:
			if o != c and o.alive and o.pos.distance_to(at) < 14.0:
				crowded = true
		if crowded:
			continue
		var p: PackedVector2Array = r["pts"]
		var sj: int = hit["seg"]
		var dir := 1 if rng.randf() < 0.5 else -1
		if r["o"] != 0:
			dir = int(r["o"])
		var along := (p[sj + 1] - p[sj]).normalized() * dir
		var lane := _lane(r)
		c.pts = PackedVector2Array([at + Vector2(-along.y, along.x) * lane])
		c.cum = PackedFloat32Array([0.0])
		c.node = PackedInt32Array([-1])
		c.vmax = PackedFloat32Array([float(r["speed"]) * c.pace])
		c.k = 0
		c.s = 0.0
		c.last_light = -1000.0
		_leg(c, ri, sj + 1 if dir > 0 else sj, dir)
		while c.cum[c.cum.size() - 1] < 140.0:
			if not _next(c):
				break
		if c.cum[c.cum.size() - 1] < 20.0:
			continue
		c.v = c.vmax[0] * 0.7
		c.wait = 0.0
		c.hit = 0.0
		c.ignore = 0.0
		_place(c)
		c.prev_pos = c.pos
		c.prev_yaw = c.yaw
		return true
	return false

## the right-hand lane's offset from the middle of a road. Every two-way street gets two,
## however narrow (both ways down the middle met head on).
func _lane(r: Dictionary) -> float:
	return clampf(float(r["w"]) * 0.25, 1.2, 1.9) if r["o"] == 0 else 0.0

## append road `ri` from index `from` to its end in direction `dir`, in the right-hand lane
func _leg(c: Car, ri: int, from: int, dir: int) -> void:
	var r: Dictionary = _roads[ri]
	var p: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var lane := _lane(r)
	var lim := float(r["speed"]) * c.pace
	var last := p.size() - 1 if dir > 0 else 0
	var start := c.pts.size()
	var i := from
	while true:
		var prv := p[i - dir] if (i - dir >= 0 and i - dir < p.size()) else p[i]
		var nxt := p[i + dir] if (i + dir >= 0 and i + dir < p.size()) else p[i]
		var d := (nxt - prv).normalized()
		var q := p[i] + Vector2(-d.y, d.x) * lane
		var tail := c.pts[c.pts.size() - 1]
		c.cum.append(c.cum[c.cum.size() - 1] + tail.distance_to(q))
		c.pts.append(q)
		c.node.append(ids[i])
		c.vmax.append(lim)
		if i == last:
			break
		i += dir
	c.end = Vector3i(ri, last, dir)
	_curves(c, start - 8)

## corners: the radius through the points 5 m either side of each, and the speed that keeps
## the sideways pull comfortable round it
func _curves(c: Car, from_k: int) -> void:
	for k in range(maxi(1, from_k), c.pts.size() - 1):
		var a := _at(c, c.cum[k] - 5.0)
		var b := c.pts[k]
		var d := _at(c, c.cum[k] + 5.0)
		var cr := absf((b - a).cross(d - a))
		if cr < 0.001:
			continue
		var radius := a.distance_to(b) * b.distance_to(d) * d.distance_to(a) / (2.0 * cr)
		c.vmax[k] = minf(c.vmax[k], maxf(sqrt(CURVE_LAT * radius), 2.5))

## at the end of the planned road, the next one: straight on rather than a turn, a main
## road rather than a side street, never against a one-way, back only from a dead end
func _next(c: Car) -> bool:
	if c.end.x < 0:
		return false
	var r: Dictionary = _roads[c.end.x]
	var p: PackedVector2Array = r["pts"]
	var ei := c.end.y
	var dir := c.end.z
	var node: int = (r["ids"] as PackedInt32Array)[ei]
	var prev := clampi(ei - dir, 0, p.size() - 1)
	var came := (p[ei] - p[prev]).normalized()
	var best := Vector3i(-1, 0, 0)
	var best_score := -INF
	var back := Vector3i(-1, 0, 0)
	for e: Vector2i in _node_roads[node]:
		var r2: Dictionary = _roads[e.x]
		if not r2["drive"] or r2["pv"] or r2["k"] == "service":
			continue
		var p2: PackedVector2Array = r2["pts"]
		for d2: int in [1, -1]:
			var nxt := e.y + d2
			if nxt < 0 or nxt >= p2.size():
				continue
			if r2["o"] != 0 and r2["o"] != d2:
				continue
			if e.x == c.end.x and nxt == prev:
				back = Vector3i(e.x, nxt, d2)
				continue
			var go := (p2[nxt] - p2[e.y]).normalized()
			var straight := came.dot(go)
			if straight < -0.7:
				continue
			var score := straight * 1.4 + float(KIND_W.get(r2["k"], 0.25)) * 1.2 + rng.randf() * 1.5
			if score > best_score:
				best_score = score
				best = Vector3i(e.x, nxt, d2)
	if best.x < 0:
		best = back
	if best.x < 0:
		return false
	_leg(c, best.x, best.y, best.z)
	return true

## drop what is well behind, so the path stays short
func _trim(c: Car) -> void:
	if c.k < 12:
		return
	var cut := 10
	var off := c.cum[cut]
	c.pts = c.pts.slice(cut)
	c.node = c.node.slice(cut)
	c.vmax = c.vmax.slice(cut)
	var cum := c.cum.slice(cut)
	for j in range(cum.size()):
		cum[j] -= off
	c.cum = cum
	c.s -= off
	c.last_light -= off
	c.k -= cut

## the segment the car is on, from where it was last
func _seek(c: Car) -> void:
	while c.k < c.cum.size() - 2 and c.cum[c.k + 1] < c.s:
		c.k += 1
	while c.k > 0 and c.cum[c.k] > c.s:
		c.k -= 1

func _at(c: Car, s: float) -> Vector2:
	var n := c.pts.size()
	if s <= 0.0:
		return c.pts[0]
	if s >= c.cum[n - 1]:
		return c.pts[n - 1]
	var j := clampi(c.k, 0, n - 2)
	while j < n - 2 and c.cum[j + 1] < s:
		j += 1
	while j > 0 and c.cum[j] > s:
		j -= 1
	var seg := c.cum[j + 1] - c.cum[j]
	return c.pts[j].lerp(c.pts[j + 1], (s - c.cum[j]) / maxf(seg, 0.001))

## where the body is: the chord between points 2.2 m either side on the lane, so it rounds
## the corners of the lane line instead of pivoting on them
func _place(c: Car) -> void:
	_seek(c)
	var a := _at(c, c.s - 2.2)
	var b := _at(c, c.s + 2.2)
	c.pos = (a + b) * 0.5
	var d := b - a
	if d.length_squared() > 0.01:
		c.yaw = atan2(d.x, d.y)
		if g._hnx > 0:
			c.pitch = atan2(float(g._h(b)) - float(g._h(a)), d.length())

func _in_view(p: Vector2) -> bool:
	var look := Vector2(cos(float(g._yaw)), sin(float(g._yaw)))
	var to: Vector2 = p - g._pos
	return to.length() < 200.0 and to.normalized().dot(look) > 0.3

## ---- every drawn frame --------------------------------------------------------------------

func draw(f: float) -> void:
	for i in range(cars.size()):
		var c: Car = cars[i]
		if not c.alive:
			continue
		var p := c.prev_pos.lerp(c.pos, f)
		var yaw := lerp_angle(c.prev_yaw, c.yaw, f)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -c.pitch)
		_mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, float(g._h(p)) + 0.02, p.y)))
		_mm.set_instance_custom_data(i, Color(c.braking, 0, 0, 0))

func _hide_or_show(i: int) -> void:
	var c: Car = cars[i]
	if not c.alive:
		_mm.set_instance_transform(i, Transform3D(Basis(), Vector3(0, -500, 0)))

## ---- the player's car against them --------------------------------------------------------

## how far to move a circle at `p` (radius r) to be clear of every car: each is two
## circles along its length, like a parked car
func push(p: Vector2, r: float) -> Vector2:
	var out := Vector2.ZERO
	for i in range(cars.size()):
		var c: Car = cars[i]
		if not c.alive or c.pos.distance_squared_to(p) > 64.0:
			continue
		var fwd := Vector2(sin(c.yaw), cos(c.yaw))
		for off: float in [1.25, -1.25]:
			var d := (p + out) - (c.pos + fwd * off)
			var need := r + 0.85
			if d.length() < need:
				out += d.normalized() * (need - d.length()) if d.length() > 0.001 else Vector2(need, 0)
				hit_index = i
	return out

func bumped(i: int) -> void:
	if i >= 0 and i < cars.size():
		var c: Car = cars[i]
		c.hit = 2.5
		c.v = minf(c.v, 1.0)
