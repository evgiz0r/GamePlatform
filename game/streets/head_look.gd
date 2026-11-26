extends RefCounted
## The driver's head: looking left and right where a driver would (moved out of streets.gd; `g` is the game).
## Slowing for a junction, a light, a stop or give-way sign: left, right, left again (traffic
## comes from the left first, driving on the right), once a junction; into a turn as the
## wheel goes over; at people on the crossing ahead; over the right shoulder reversing.
## Autodrive's driver always does; yours while "look" is on. The seat view turns with the
## head, the chase camera swings a little toward it, and the head in the car turns.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const LOOK_BTN := Rect2(566, 176, 66, 22)    ## looking round while you drive yourself (key G: glance); hidden while autodrive drives or you walk
var _head_yaw := 0.0                         ## where the driver looks: radians left (+) of ahead
var _head_plan: Array = []                   ## a scan still to do: [[yaw, seconds held], ...]
var _head_hold := 0.0
var _head_at := Vector2.INF                  ## where the last scan was (once a junction: its
var _head_at_t := 0.0                        ## points 10-30 m apart are one) and how long ago
var _head_check := 0.0
var _look_on := true                         ## looking round while you drive (autodrive always)

func _head_tick(dt: float) -> void:
	var want := 0.0
	_head_at_t += dt
	if g._walking or not (g._auto or _look_on):
		_head_plan = []
	else:
		_head_check -= dt
		# the look left and right: standing or all but, at a junction, a light or a sign,
		# once a junction. (Rolling below 23 km/h near any junction, it fired again and again
		# in slow traffic and turned the seat view half round each time.)
		if _head_check <= 0.0 and _head_plan.is_empty() and absf(g._v) < 2.5 and g._gear > 0:
			_head_check = 0.2
			var j := _junction_ahead_me(16.0)
			# only first in line and about to go: at a light, once it is green (it looked
			# left and right at every red, from behind a queue of cars); with a car in front,
			# not yet -- it looks when it is the one pulling out
			if j >= 0 and g._sig_set.has(j) and g._light_at(j, g._fwd()) not in ["g", ""]:
				j = -1
			if j >= 0 and _car_ahead_me(12.0):
				j = -1
			if j >= 0 and (g._nodes[j].distance_to(_head_at) > 45.0 or _head_at_t > 20.0):
				_head_at = g._nodes[j]
				_head_at_t = 0.0
				_head_plan = [[0.9, 0.5], [-0.9, 0.55], [0.5, 0.3]]
		if not _head_plan.is_empty():
			if absf(g._v) > 6.0:
				_head_plan = []   # (off again before it was done: eyes on the road)
			else:
				want = float(_head_plan[0][0])
				if absf(_head_aim - want) < 0.05:
					_head_hold += dt
					if _head_hold >= float(_head_plan[0][1]):
						_head_hold = 0.0
						_head_plan.pop_front()
		elif g._gear < 0 and absf(g._v) > 0.2:
			want = -1.2   # over the right shoulder, reversing
		elif g._auto and g._ap_give_car >= 0 and absf(g._v) < 3.0 and g._traffic.cars[g._ap_give_car].alive:
			# giving way: at the car it waits for, following it by
			want = clampf(-g._fwd().angle_to(g._traffic.cars[g._ap_give_car].pos - g._pos), -1.2, 1.2)
		else:
			# standing for people on the crossing ahead: at one of them, held a moment (the
			# nearest, chosen afresh every frame, sent the eyes from one to the next)
			_head_person_t -= dt
			if absf(g._v) < 2.0:
				if _head_person_t <= 0.0:
					_head_person = _person_ahead_me(14.0)
					_head_person_t = 1.5
				if _head_person != Vector2.INF:
					want = clampf(-g._fwd().angle_to(_head_person - g._pos), -1.0, 1.0)
			else:
				_head_person = Vector2.INF
	# eased: the aim moves at a head's pace and the head follows it smoothly. (The steering
	# was in it too, on top of the seat view's own lead into a turn: every small correction
	# autodrive made swung the view.)
	_head_aim = move_toward(_head_aim, want, 2.2 * dt)
	_head_yaw = lerpf(_head_yaw, _head_aim, 1.0 - exp(-dt * 7.0))
	if g._player_car_mat != null:
		# the head drawn in the car leans a little into a turn as well (the seat view does
		# that by itself)
		_head_steer = lerpf(_head_steer, clampf(-g._steer * 0.8, -0.35, 0.35), 1.0 - exp(-dt * 3.0))
		g._player_car_mat.set_shader_parameter("head_turn", _head_yaw + _head_steer)

var _head_aim := 0.0                         ## where the head is heading for (eased toward)
var _head_person := Vector2.INF              ## the person it is looking at, held a moment
var _head_person_t := 0.0
var _head_steer := 0.0                       ## the drawn head's lean into a turn
const SEAT_HEAD := 0.7                       ## how much of the head's turn the seat view takes

func _toggle_look() -> void:
	_look_on = not _look_on
	g._show_banner("looking round as you drive: " + ("on" if _look_on else "off"), 1.4)
	Probe.event("look", {"on": _look_on})

## the next junction (3+ ways) or signalled point on the road ahead within `reach`, or -1
func _junction_ahead_me(reach: float) -> int:
	var hit := g._nearest_seg(g._pos, 12.0, true, true)
	if hit.is_empty():
		return -1
	var r: Dictionary = g._roads[hit["road"]]
	var pts: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var sj: int = hit["seg"]
	var dir := 1 if (pts[sj + 1] - pts[sj]).dot(g._fwd()) >= 0.0 else -1
	var k := sj + 1 if dir > 0 else sj
	var d := g._pos.distance_to(pts[k])
	while d <= reach:
		var n := ids[k]
		if g._node_ways(n) >= 3 or g._sig_set.has(n) or g._signs.has(n):
			return n
		var nk := k + dir
		if nk < 0 or nk >= pts.size():
			return -1
		d += pts[k].distance_to(pts[nk])
		k = nk
	return -1

## a car in front within `reach` (on autodrive's planned lane, or straight ahead driving yourself)
func _car_ahead_me(reach: float) -> bool:
	var path := g._ap_pts if (g._auto and g._ap_pts.size() >= 2) else PackedVector2Array([g._pos, g._pos + g._fwd() * (reach + 2.0)])
	var lead: Array = g._traffic.lead_on(path, g._pos, reach, false)
	return float(lead[0]) < reach

## the nearest person in front within `reach` (on a crossing, stepping off the kerb)
func _person_ahead_me(reach: float) -> Vector2:
	var best := Vector2.INF
	var bd := reach
	for q: Vector3 in g._people_near(g._pos + g._fwd() * reach * 0.5, reach * 0.5 + 2.0):
		var p := Vector2(q.x, q.z)
		var d := p.distance_to(g._pos)
		if d < bd and (p - g._pos).dot(g._fwd()) > 2.0:
			bd = d
			best = p
	return best

func _clear_behind(from: Vector2, dir: Vector2, want: float) -> float:
	if absf(g._view_y - g._h(from)) > 2.5:
		return want   # (in a tunnel, on a bridge: the houses round it are not behind the car)
	var s := 1.0
	while s <= want + 0.6:
		var p := from + dir * s
		for i: int in g._near(g._bld_hash, p, 0.1, Streets.BLD_CELL):
			var box: Rect2 = g._bld_box[i]
			if box.has_point(p) and Geometry2D.is_point_in_polygon(p, g._blds[i]):
				return maxf(2.2, s - 0.8)
		s += 0.5
	return want
