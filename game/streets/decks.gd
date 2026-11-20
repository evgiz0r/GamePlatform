extends RefCounted
## Roads off the ground: bridges, the embankments up to them, cuttings and tunnels -- "decks".
##
## A road whose city file gives the height of its surface at every point (`y`, see the format
## at the top of tools/osm_city.py) is a deck: it is drawn, driven and walked at those heights
## instead of on the ground. What it is built as comes from its OSM tags -- a bridge (`br`: a
## slab on piers, parapets), an embankment (`em`: retaining walls down to the ground), a
## cutting (`cu`: the ground cut away over it, walls up to the ground, a railing on top) or a
## tunnel (`tu`: a tube, lit inside, a headwall where it meets the open air). Where a deck
## meets a street on the ground it is at the ground's height. A city without heights has no
## decks: its bridges lie on the ground as before and its tunnels are left out.
##
## The rest of the game asks this file three things: how high the surface under something is
## (`surf`: the ground, or a deck -- whichever is under it at its own level, so a car under a
## bridge stays under it and one in a tunnel is not lifted onto the hill above), what a body
## at a height runs into (`push`: parapets, walls, piers -- each only at its own heights), and
## what to draw in a square of the city (`build`). The decks are kept out of the squares'
## road lists (the game's _tile_roads), so kerbs, parked cars, lamps, people and the rest
## never stand on or under one by mistake: this file draws their asphalt, paint, pavements
## and walls itself.

const STEP_UP := 1.2          ## a car or a walker gets onto a surface this far above its feet
const SLAB := 1.1             ## a bridge's depth under its road
const PARAPET := 1.05         ## the parapet's height over the walkway
const WALL_T := 0.35          ## parapets and walls: thick
const TUBE_H := 5.4           ## a tunnel's ceiling over the road
const PIER_STEP := 17.0       ## a bridge's piers: about this far apart
const BANK := 1.5             ## an embankment's grass bank: metres out for each metre down
const GUARD_H := 0.75         ## the guardrail along the top of a bank
const CELL := 24.0
const SEEN := 700.0           ## the big pieces are drawn this far
const NEAR_SEEN := 260.0      ## railings, lamps, paint

var g: Node                   ## the streets game
var decks := PackedInt32Array()      ## road indices
var _hash := {}               ## cell -> [road * 4096 + segment]: the decks' footprints
var _walls: Array = []        ## [a, b, lo_a, hi_a, lo_b, hi_b, half thickness, what]
var _wall_hash := {}
var holes: Array = []         ## outlines (PackedVector2Array) where the ground is cut away
var hole_boxes: Array = []
var lowest := INF             ## the lowest deck surface (the flat ground far off goes below it)
var _lamp_mat: StandardMaterial3D

func _init(game: Node) -> void:
	g = game

func any() -> bool:
	return not decks.is_empty()

## ---- what a deck is ----------------------------------------------------------------------

## the width from a deck's asphalt edge to its wall: a pavement on a bridge or an embankment
## of a street with pavements, a narrow ledge in a tunnel, a shoulder in a cutting
static func side_of(r: Dictionary, kerbed: bool) -> float:
	if not r["drive"]:
		return 0.0
	match String(r["deck"]):
		"tu":
			return 0.9
		"cu":
			return 0.6
	return (0.2 + 2.4) if kerbed else 0.6

## Called once the roads and the height grid are loaded: each deck's heights checked against
## the ground, its ends put at the ground's height where it meets a street on the ground, and
## its footprint, walls and holes worked out.
func setup() -> void:
	for ri in range(g._roads.size()):
		var r: Dictionary = g._roads[ri]
		if not r.has("ys"):
			continue
		decks.append(ri)
		var pts: PackedVector2Array = r["pts"]
		var ids: PackedInt32Array = r["ids"]
		var ys: PackedFloat32Array = r["ys"]
		var gs := PackedFloat32Array()
		gs.resize(pts.size())
		for j in range(pts.size()):
			gs[j] = g._h(pts[j])
		for j: int in [0, pts.size() - 1]:
			if _meets_ground(ids[j], ri):
				ys[j] = gs[j]
		r["ys"] = ys
		r["gs"] = gs
		if String(r["deck"]) == "":
			r["deck"] = "em" if ys[ys.size() / 2] > gs[gs.size() / 2] else "cu"
		var side := side_of(r, g._kerbed(r))
		r["side"] = side
		r["foot"] = float(r["w"]) * 0.5 + side + WALL_T
		r["_joint0"] = false
		r["_joint1"] = false
		for j in range(pts.size() - 1):
			g._hash_add(_hash, Rect2(pts[j], Vector2.ZERO).expand(pts[j + 1]).grow(float(r["foot"]) + 0.5), CELL, ri * 4096 + j)
		for v in ys:
			lowest = minf(lowest, v)
	for ri: int in decks:   # which ends another deck carries on from
		var r: Dictionary = g._roads[ri]
		var ids: PackedInt32Array = r["ids"]
		for end: int in [0, 1]:
			for e: Vector2i in g._node_roads[ids[0] if end == 0 else ids[ids.size() - 1]]:
				if e.x != ri and (g._roads[e.x] as Dictionary).has("ys"):
					r["_joint%d" % end] = true
	for ri: int in decks:
		_walls_of(ri)
		if String(g._roads[ri]["deck"]) == "cu":
			_holes_of(ri)
	for i in range(_walls.size()):
		var w: Array = _walls[i]
		g._hash_add(_wall_hash, Rect2(w[0], Vector2.ZERO).expand(w[1]).grow(float(w[6]) + 0.5), CELL, i)

## node n is on some road other than ri that is not a deck
func _meets_ground(n: int, ri: int) -> bool:
	for e: Vector2i in g._node_roads[n]:
		var r: Dictionary = g._roads[e.x]
		if e.x != ri and r["drive"] and not r.has("ys"):
			return true   # (a footpath meeting a deck up on its embankment is not a way down)
	return false

## every road at node n is a deck (a joint between two of them: no junction is drawn there)
func deck_only(n: int) -> bool:
	var roads: Array = g._node_roads[n]
	if roads.is_empty():
		return false
	for e: Vector2i in roads:
		if not (g._roads[e.x] as Dictionary).has("ys"):
			return false
	return true

static func is_deck(r: Dictionary) -> bool:
	return r.has("ys")

## the height of road ri's surface level with p (as the ground's: add the road's own lift)
func deck_y(ri: int, p: Vector2) -> float:
	var r: Dictionary = g._roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var ys: PackedFloat32Array = r["ys"]
	var best := INF
	var y := ys[0]
	for j in range(pts.size() - 1):
		var a := pts[j]
		var ab := pts[j + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		var d := p.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			y = lerpf(ys[j], ys[j + 1], t)
	return y

## the same on segment j, at a point q on it
func seg_y(ri: int, j: int, q: Vector2) -> float:
	var r: Dictionary = g._roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var ys: PackedFloat32Array = r["ys"]
	var ab := pts[j + 1] - pts[j]
	var t := clampf((q - pts[j]).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return lerpf(ys[j], ys[j + 1], t)

## How high the surface under p is, for something whose feet are at y: the highest of the
## ground and the decks there that is no more than STEP_UP above its feet (or, when every one
## is, the lowest). Over an open cutting there is no ground, only the cutting's road.
func surf(p: Vector2, y: float) -> float:
	var ground: float = g._h(p)
	if _hash.is_empty():
		return ground
	var on := _under(p)
	if on.is_empty():
		return ground
	# What it is on, in this order: a deck whose carriageway it is on; one whose pavement or
	# parapet it is within; the ground (not over a cutting). Of each, the one nearest its own
	# height that it can reach (no more than STEP_UP above its feet). A divided road's two
	# carriageways overlap at the median, at not quite the same height: a car on one stayed
	# on whichever was higher, or nearer, and then fell off the end of the wrong one.
	var lanes: Array = []
	var sides: Array = []
	var past: Array = []   # just past a deck's end, where another deck carries on (a bend's outside)
	var open := true
	for ri: int in on:
		var r: Dictionary = g._roads[ri]
		if String(r["deck"]) == "cu":
			open = false   # (in a cutting the ground beside is not under you, however shallow it is)
		var c: float = on[ri][1]
		if bool(on[ri][2]):
			past.append(c)
		else:
			(lanes if float(on[ri][0]) < float(r["w"]) * 0.5 + 0.3 else sides).append(c)
	# On a street's asphalt over a cutting or a tunnel (a street across an underpass's mouth,
	# a cutting's shallow top under a street's lanes): the street carries a body at its level.
	var on_street := false
	for ri: int in on:
		if String(g._roads[ri]["deck"]) in ["cu", "tu"]:
			on_street = _street_over(p)
			break
	if not open and on_street:
		open = true
	var low := ground if open else INF
	# (a deck well under ground the body can reach -- a tunnel under the street it is on -- is
	# not what it is on: ranked first, the tunnel's road won, and a car on the street dropped
	# 7 m into it; inside the tunnel the ground overhead is out of reach, so it is still found.
	# On a street, at its level, anything under it at all)
	var buried := -INF
	if open and ground <= y + STEP_UP:
		buried = ground - (0.3 if on_street and y >= ground - 0.3 else 1.5)
	for group: Array in [lanes, sides, past, [ground] if open else []]:
		var best := NAN
		for c: float in group:
			low = minf(low, c)
			if c <= y + STEP_UP and c >= buried and (is_nan(best) or absf(c - y) < absf(best - y)):
				best = c
		if not is_nan(best):
			return best
	return low

## p is on the asphalt of a street on the ground (a road that is no deck)
func _street_over(p: Vector2) -> bool:
	for code: int in g._near(g._seg_hash, p, 1.0, g.SEG_CELL):
		var r: Dictionary = g._roads[code / 4096]
		if r.has("ys") or not r["drive"]:
			continue
		var pts: PackedVector2Array = r["pts"]
		var j := code % 4096
		if Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p) <= float(r["w"]) * 0.5:
			return true
	return false

## the decks whose footprint p is in: road -> [distance from its middle line, its surface's
## height there], each from the road's nearest segment (several segments of one road are
## near any point on it, and the next one's end is not the height here)
func _under(p: Vector2) -> Dictionary:
	var near := {}   # road -> [distance, segment, how far along it (unclamped)]
	for code: int in _hash.get(g._cell(p, CELL), []):
		var ri := code / 4096
		var j := code % 4096
		var pts: PackedVector2Array = g._roads[ri]["pts"]
		var a := pts[j]
		var ab := pts[j + 1] - a
		var raw := (p - a).dot(ab) / maxf(ab.length_squared(), 0.000001)
		var d := p.distance_to(a + ab * clampf(raw, 0.0, 1.0))
		if not near.has(ri) or d < float(near[ri][0]):
			near[ri] = [d, j, raw]
	var out := {}
	for ri: int in near:
		var r: Dictionary = g._roads[ri]
		var d: float = near[ri][0]
		var j: int = near[ri][1]
		var raw: float = near[ri][2]
		var n: int = (r["pts"] as PackedVector2Array).size()
		# past the road's end: the next road, or the ground, is there -- though not just past it:
		# where two decks meet at a bend, the outside lane is past the end of the one and
		# before the start of the other, and a car there fell through between them
		var seg_len := (r["pts"] as PackedVector2Array)[j].distance_to((r["pts"] as PackedVector2Array)[j + 1])
		var past := maxf(-raw if j == 0 else 0.0, raw - 1.0 if j == n - 2 else 0.0) * seg_len
		# (only where another deck carries on from that end, and only as a last resort: see surf)
		var joint: bool = r["_joint0"] if raw < 0.0 else r["_joint1"]
		if d > float(r["foot"]) or (past > 0.0 and (past > 3.0 or not joint)):
			continue
		var ys: PackedFloat32Array = r["ys"]
		out[ri] = [d, lerpf(ys[j], ys[j + 1], clampf(raw, 0.0, 1.0)), past > 0.0]
	return out

## the deck road under p at height y (within `slack` of its surface), or -1
func deck_at(p: Vector2, y: float, slack := 1.5) -> int:
	var on := _under(p)
	var best := -1
	var bd := INF
	for ri: int in on:
		var dy: float = absf(float(on[ri][1]) - y)
		if dy < slack and dy < bd:
			bd = dy
			best = ri
	return best

## Where another deck's road comes in -- a slip road meeting a road up on its embankment --
## p (on deck ri, at height y) lies on that road: on its carriageway (`inner` false) or
## anywhere inside its walls (`inner` true). There a parapet or a walkway opens.
func open_at(ri: int, p: Vector2, y: float, inner := true) -> bool:
	var on := _under(p)
	for rj: int in on:
		if rj == ri or absf(float(on[rj][1]) - y) > 1.2:
			continue
		var r: Dictionary = g._roads[rj]
		var reach := float(r["w"]) * 0.5 + (float(r["side"]) if inner else 0.2)
		if float(on[rj][0]) < reach:
			return true
	return false

## An embankment slopes down to the ground as a grass bank (BANK out for each metre down),
## a guardrail along its top, wherever there is room: not where its foot would land on
## another road or in a building (the old streets' ramps between their houses) -- there it
## is a retaining wall and a parapet. The bank's width at a point of deck ri (p on its middle
## line, `out` the unit way outward on that side, y its surface there): > 0 a bank that wide,
## 0 too low to need either, -1 a wall.
func bank_at(ri: int, p: Vector2, out: Vector2, y: float) -> float:
	var r: Dictionary = g._roads[ri]
	if String(r["deck"]) != "em":
		return -1.0
	var edge := float(r["w"]) * 0.5 + float(r["side"])
	var top := p + out * edge
	var drop: float = y - float(g._h(top))
	if drop < 0.4:
		return 0.0
	var width := drop * BANK
	for f: float in [0.5, 1.0]:
		var q := top + out * width * f
		var on: Dictionary = g._nearest_seg(q, 12.0, true)
		if not on.is_empty() and int(on["road"]) != ri and float(on["edge"]) < 0.5:
			return -1.0
		if _in_building(q, 0.6):
			return -1.0
	return width

func _in_building(c: Vector2, rad: float) -> bool:
	for i: int in g._near(g._bld_hash, c, rad, g.BLD_CELL):
		if g._bld_solid[i] == 0 or not (g._bld_box[i] as Rect2).grow(rad).has_point(c):
			continue
		if g._poly_push(g._blds[i], c, rad) != Vector2.ZERO:
			return true
	return false

## the unit way out from a line's middle on side sd, at each of its points
func _outs(pts: PackedVector2Array, sd: float) -> PackedVector2Array:
	var one: PackedVector2Array = g._offset_line(pts, sd)
	var out := PackedVector2Array()
	for i in range(pts.size()):
		out.append((one[i] - pts[i]).normalized())
	return out

## a deck's own point is at street level there (within half a metre of the ground)
func _low(r: Dictionary, p: Vector2, y: float) -> bool:
	return absf(y - float(g._h(p))) < 0.5

## ---- what you run into: parapets, walls, piers --------------------------------------------

## one side of each deck: [a, b, lo_a, hi_a, lo_b, hi_b, half thickness, what], kept only
## where there is something to hit (an embankment's or a cutting's wall where it stands up)
func _walls_of(ri: int) -> void:
	var r: Dictionary = g._roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var ys: PackedFloat32Array = r["ys"]
	var gs: PackedFloat32Array = r["gs"]
	var kind := String(r["deck"])
	var off := float(r["w"]) * 0.5 + float(r["side"]) + WALL_T * 0.5
	var walk: float = g.KERB_H if float(r["side"]) > 1.0 else 0.0
	# Where a ramp or a cutting starts at a junction its wall is a kerb-high step, and a car
	# turning in sweeps over the corner: no wall to hit there (one clipped it at 10 km/h).
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var ids: PackedInt32Array = r["ids"]
	var clear_a := 0.0
	var clear_b := 0.0
	if kind in ["em", "cu"]:   # (at street level: a junction up on an embankment keeps its walls)
		var last := ids.size() - 1
		if (g._node_roads[ids[0]] as Array).size() >= 3 and absf(ys[0] - gs[0]) < 0.5:
			clear_a = float(g._node_r[ids[0]]) + 6.0
		if (g._node_roads[ids[last]] as Array).size() >= 3 and absf(ys[last] - gs[last]) < 0.5:
			clear_b = float(g._node_r[ids[last]]) + 6.0
	var total := cum[cum.size() - 1]
	for sd: float in [-1.0, 1.0]:
		var line: PackedVector2Array = g._offset_line(pts, off * sd)
		var outs := _outs(pts, sd)
		var banks := PackedFloat32Array()
		for j in range(pts.size()):
			banks.append(bank_at(ri, pts[j], outs[j], ys[j]) if kind == "em" else -1.0)
		for j in range(pts.size() - 1):
			if cum[j] < clear_a or cum[j + 1] > total - clear_b:
				continue   # (any piece that reaches into the corner)
			if banks[j] >= 0.0 and banks[j + 1] >= 0.0 and maxf(banks[j], banks[j + 1]) > 0.0:
				# a bank: the guardrail along its top stops a car on the deck; its foot, as
				# steep as a wall, stops one on the ground beside it
				var mid_b := (line[j] + line[j + 1]) * 0.5
				if not open_at(ri, mid_b, (ys[j] + ys[j + 1]) * 0.5):
					_walls.append([line[j], line[j + 1], ys[j] - 0.3, ys[j] + 0.9, ys[j + 1] - 0.3, ys[j + 1] + 0.9, 0.1, "guardrail"])
				var e0 := float(r["w"]) * 0.5 + float(r["side"])
				var f0 := pts[j] + outs[j] * (e0 + banks[j])
				var f1 := pts[j + 1] + outs[j + 1] * (e0 + banks[j + 1])
				_walls.append([f0, f1, gs[j] - 1.0, gs[j] + 1.0, gs[j + 1] - 1.0, gs[j + 1] + 1.0, 0.3, "bank"])
				continue
			var band := []
			for k: int in [j, j + 1]:
				match kind:
					"br":
						band.append_array([ys[k] - SLAB - 0.2, ys[k] + walk + PARAPET])
					"em":
						band.append_array([gs[k] - 1.0, ys[k] + walk + PARAPET])
					"cu":
						band.append_array([ys[k] - 0.3, maxf(gs[k], ys[k]) + 1.1])
					_:
						band.append_array([ys[k] - 0.3, ys[k] + TUBE_H])
			var rise := maxf(absf(ys[j] - gs[j]), absf(ys[j + 1] - gs[j + 1]))
			if kind in ["em", "cu"] and rise < 0.3:
				continue
			var mid := (line[j] + line[j + 1]) * 0.5
			if open_at(ri, mid, (ys[j] + ys[j + 1]) * 0.5):
				continue   # (another deck's road comes in here)
			_walls.append([line[j], line[j + 1], band[0], band[1], band[2], band[3], WALL_T * 0.5, kind])
	if kind == "br":
		for pier: Array in piers(ri):
			var c: Vector2 = pier[0]
			var across: Vector2 = pier[1]
			var half: float = pier[2]
			var top: float = pier[3] - SLAB
			var foot: float = g._h(c) - 1.0
			_walls.append([c - across * half, c + across * half, foot, top, foot, top, float(pier[4]) * 0.5, "pier"])

## Where a bridge stands on the ground below: [middle, across (unit), half its width across,
## the deck's height there, its thickness along the road], every PIER_STEP or so wherever the
## deck is more than 2 m up -- not on another road's asphalt (a pier in a boulevard's median
## is fine, one in its lanes is not) -- and a thick one where each end leaves the bank.
func piers(ri: int) -> Array:
	var r: Dictionary = g._roads[ri]
	if r.has("_piers"):
		return r["_piers"]
	var pts: PackedVector2Array = r["pts"]
	var ys: PackedFloat32Array = r["ys"]
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total := cum[cum.size() - 1]
	var half := float(r["w"]) * 0.5 + float(r["side"])
	var out: Array = []
	var n := maxi(1, roundi(total / PIER_STEP))
	var marks: Array = []
	for k in range(1, n):
		marks.append([total * k / n, 1.3])
	# the abutments: where the deck first stands 1.5 m over the ground, from each end
	for from_end: bool in [false, true]:
		var s := 0.0
		while s < total * 0.5:
			var at: float = (total - s) if from_end else s
			var p: Vector2 = g._along(pts, cum, at)
			if _y_along(ys, cum, at) - g._h(p) > 1.5:
				marks.append([at, 2.2])
				break
			s += 1.0
	for m: Array in marks:
		var at: float = m[0]
		var p: Vector2 = g._along(pts, cum, at)
		var y := _y_along(ys, cum, at)
		if y - g._h(p) < 2.0 and float(m[1]) < 2.0:
			continue
		var d: Vector2 = (g._along(pts, cum, minf(at + 1.0, total)) - g._along(pts, cum, maxf(at - 1.0, 0.0))).normalized()
		var across := Vector2(-d.y, d.x)
		var on: Dictionary = g._nearest_seg(p, 30.0, true)
		if not on.is_empty() and int(on["road"]) != ri and not is_deck(g._roads[int(on["road"])]) and float(on["edge"]) < 1.0:
			continue   # (someone else's lanes)
		var clash := false
		for o: Array in out:
			if (o[0] as Vector2).distance_to(p) < 6.0:
				clash = true
		if not clash:
			out.append([p, across, half - 0.6, y, float(m[1])])
	r["_piers"] = out
	return out

func _y_along(ys: PackedFloat32Array, cum: PackedFloat32Array, s: float) -> float:
	for i in range(1, cum.size()):
		if cum[i] >= s:
			return lerpf(ys[i - 1], ys[i], (s - cum[i - 1]) / maxf(cum[i] - cum[i - 1], 0.001))
	return ys[ys.size() - 1]

## How far to move a circle (radius r, its body from y to y + 1.6) out of the walls it
## overlaps at its own heights: a car under a bridge does not hit its parapets, one in a
## tunnel does not hit the cutting's railing above.
func push(c: Vector2, r: float, y: float) -> Vector2:
	if _walls.is_empty():
		return Vector2.ZERO
	var out := Vector2.ZERO
	for i: int in g._near(_wall_hash, c, r + 0.5, CELL):
		var w: Array = _walls[i]
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var q := c + out
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
		var lo := lerpf(w[2], w[4], t)
		var hi := lerpf(w[3], w[5], t)
		if y + 1.6 < lo or y + 0.15 > hi:
			continue
		var cp := a + ab * t
		var d := q - cp
		var need: float = r + float(w[6])
		if d.length_squared() < need * need:
			var nrm := d.normalized() if d.length() > 0.001 else ab.orthogonal().normalized()
			out += nrm * (need - d.length())
			g._last_hit = "wall %s" % w[7]
	return out

## ---- the ground cut away over the cuttings ------------------------------------------------

## the outline of each stretch of a cutting that lies below the ground
func _holes_of(ri: int) -> void:
	var r: Dictionary = g._roads[ri]
	var pts: PackedVector2Array = r["pts"]
	var ys: PackedFloat32Array = r["ys"]
	var gs: PackedFloat32Array = r["gs"]
	var f: float = r["foot"]
	var run := PackedVector2Array()
	for j in range(pts.size()):
		var deep := gs[j] - ys[j] > 0.05
		if deep:
			if run.is_empty() and j > 0:
				run.append(pts[j - 1].lerp(pts[j], 0.5))
			run.append(pts[j])
		if (not deep or j == pts.size() - 1) and run.size() >= 2:
			if not deep:
				run.append(pts[j - 1].lerp(pts[j], 0.5))
			var a: PackedVector2Array = g._offset_line(run, f)
			var b: PackedVector2Array = g._offset_line(run, -f)
			b.reverse()
			a.append_array(b)
			holes.append(a)
			var box := Rect2(a[0], Vector2.ZERO)
			for p in a:
				box = box.expand(p)
			hole_boxes.append(box)
			run = PackedVector2Array()
		elif not deep:
			run = PackedVector2Array()

## The ground mesh's triangles with the holes cut out: given one triangle's corners (with
## their normals), the triangles to draw instead -- itself when it misses every hole.
func cut_tri(v: Array, nrm: Array) -> Array:
	var tri := PackedVector2Array([Vector2(v[0].x, v[0].z), Vector2(v[1].x, v[1].z), Vector2(v[2].x, v[2].z)])
	var box := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
	var polys: Array = [tri]
	var hit := false
	for i in range(holes.size()):
		if not (hole_boxes[i] as Rect2).intersects(box):
			continue
		var next: Array = []
		for poly: PackedVector2Array in polys:
			var cut := Geometry2D.clip_polygons(poly, holes[i])
			for c: PackedVector2Array in cut:
				if c.size() >= 3:   # (a hole is a long strip: never inside one triangle)
					next.append(c)
			# (a hole's edge parallel to one of the triangle's leaves it a smaller triangle:
			# the same three corners' count, so compare the areas)
			if cut.size() != 1 or absf(_area(cut[0]) - _area(poly)) > 0.001:
				hit = true
		polys = next
	if not hit:
		return [[v, nrm]]
	var out: Array = []
	var a2 := tri[0]
	var b2 := tri[1]
	var c2 := tri[2]
	var den := (b2.y - c2.y) * (a2.x - c2.x) + (c2.x - b2.x) * (a2.y - c2.y)
	for poly: PackedVector2Array in polys:
		var idx := Geometry2D.triangulate_polygon(poly)
		for k in range(0, idx.size(), 3):
			var t3: Array = []
			var n3: Array = []
			for m in range(3):
				var p := poly[idx[k + m]]
				var w0 := ((b2.y - c2.y) * (p.x - c2.x) + (c2.x - b2.x) * (p.y - c2.y)) / den
				var w1 := ((c2.y - a2.y) * (p.x - c2.x) + (a2.x - c2.x) * (p.y - c2.y)) / den
				var w2 := 1.0 - w0 - w1
				t3.append(Vector3(p.x, v[0].y * w0 + v[1].y * w1 + v[2].y * w2, p.y))
				n3.append(((nrm[0] as Vector3) * w0 + (nrm[1] as Vector3) * w1 + (nrm[2] as Vector3) * w2).normalized())
			# wound as the ground's own triangles are (clockwise seen from above)
			if ((t3[1] as Vector3) - (t3[0] as Vector3)).cross((t3[2] as Vector3) - (t3[0] as Vector3)).y > 0.0:
				t3 = [t3[0], t3[2], t3[1]]
				n3 = [n3[0], n3[2], n3[1]]
			out.append([t3, n3])
	return out

static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(poly.size()):
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5

## ---- the camera -----------------------------------------------------------------------------

## A chase camera (eye) behind a car at height y: kept under a tunnel's ceiling and between
## its walls while the car is in one.
func keep_eye(eye: Vector3, car: Vector2, y: float) -> Vector3:
	var ri := deck_at(car, y, 2.5)
	if ri < 0 or String(g._roads[ri]["deck"]) != "tu":
		return eye
	var r: Dictionary = g._roads[ri]
	var e2 := Vector2(eye.x, eye.z)
	var on: Dictionary = _nearest_on(ri, e2)
	var room := float(r["w"]) * 0.5 + float(r["side"]) - 0.6
	var q: Vector2 = on["q"]
	if e2.distance_to(q) > room:
		e2 = q + (e2 - q).normalized() * room
	var top: float = deck_y(ri, e2) + g.road_top() + TUBE_H - 0.7
	return Vector3(e2.x, minf(eye.y, top), e2.y)

func _nearest_on(ri: int, p: Vector2) -> Dictionary:
	var pts: PackedVector2Array = g._roads[ri]["pts"]
	var best := INF
	var out := {}
	for j in range(pts.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
		if q.distance_squared_to(p) < best:
			best = q.distance_squared_to(p)
			out = {"seg": j, "q": q}
	return out

## ---- drawing: a square of the city at a time ------------------------------------------------

func _lamp() -> StandardMaterial3D:
	if _lamp_mat == null:
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_lamp_mat.albedo_color = Color(1.0, 0.86, 0.62)
	return _lamp_mat

## the decks that reach the square being built
func build() -> void:
	var list: Array = g._tile_decks.get(g._tile, [])
	if list.is_empty():
		return
	var asphalt: RefCounted = g._clip_buf(g.CHUNK)
	var marks: RefCounted = g._clip_buf(g.GROUND_CELL)
	var yellow: RefCounted = g._clip_buf(g.GROUND_CELL)
	var walk: RefCounted = g._clip_buf(g.CHUNK)
	var kerb: RefCounted = g._clip_buf(g.CHUNK)
	var conc: RefCounted = g._clip_buf(g.CHUNK)
	var stone: RefCounted = g._clip_buf(g.CHUNK)
	var rail: RefCounted = g._clip_buf(g.GROUND_CELL)
	var tile: RefCounted = g._clip_buf(g.CHUNK)      # a tunnel's tiled walls
	var tube: RefCounted = g._clip_buf(g.CHUNK)      # its ceiling and upper walls
	var lamps: RefCounted = g._clip_buf(g.GROUND_CELL)
	var grass: RefCounted = g._clip_buf(g.CHUNK)     # embankments' banks
	for ri: int in list:
		if g._over():
			await g._pause()
		var r: Dictionary = g._roads[ri]
		var pts: PackedVector2Array = _dense(r["pts"], 4.0)
		var hw := float(r["w"]) * 0.5
		g._on_deck = ri
		g._ribbon(asphalt, pts, hw, g.Y_ROAD)
		g._markings(marks, r, yellow)
		g._on_deck = -1
		# a junction in the air (only decks meet there): its middle filled, at its height
		var ids: PackedInt32Array = r["ids"]
		for n: int in [ids[0], ids[ids.size() - 1]]:
			if (g._node_roads[n] as Array).size() >= 3 and deck_only(n) and g._mine(g._nodes[n]) \
					and int((g._node_roads[n] as Array)[0].x) == ri:
				g._on_deck = ri
				g._disc(asphalt, g._nodes[n], float(g._node_r[n]) * 1.05, g.Y_ROAD)
				g._on_deck = -1
		match String(r["deck"]):
			"br", "em":
				_raised(ri, pts, walk, kerb, conc, stone, grass, rail)
			"cu":
				_cutting(ri, pts, conc, rail)
			"tu":
				_tunnel(ri, pts, walk, kerb, tile, tube, lamps)
	for job: Array in [[asphalt, "asphalt", SEEN, false], [marks, "mark", NEAR_SEEN, false], [yellow, "markyellow", NEAR_SEEN, false],
			[walk, "pavement", SEEN, false], [kerb, "kerb", NEAR_SEEN, false], [conc, "concrete", SEEN, true],
			[stone, "stonewall", SEEN, true], [rail, "railing", NEAR_SEEN, true], [grass, "grass", SEEN, false]]:
		g._add_mesh(job[0], g._surface(job[1]), job[3], job[2])
	# the tube: its own meshes, casting shadows from both faces so the sun stays out of it
	for job: Array in [[tile, g._surface("lobby")], [tube, g._surface("recess")]]:
		_solid(job[0], job[1])
	_solid(lamps, _lamp(), false)

func _solid(buf: RefCounted, m: Material, shadows := true) -> void:
	for key: Vector2i in buf.parts():
		var part: RefCounted = buf.parts()[key]
		if part.empty():
			continue
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.arrays())
		am.surface_set_material(0, m)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = SEEN
		g.world.add_child(mi)

func _dense(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var n := maxi(1, ceili(pts[i - 1].distance_to(pts[i]) / step))
		for k in range(1, n + 1):
			out.append(pts[i - 1].lerp(pts[i], float(k) / n))
	return out

## a line `off` metres to the side of a deck's middle, at its surface + lift (and the ground
## under each point, for walls that go down to it)
func _edge(ri: int, pts: PackedVector2Array, off: float, lift: float) -> Array:
	var line: PackedVector2Array = g._offset_line(pts, off)
	var up := PackedVector3Array()
	var down := PackedFloat32Array()
	var e: float = g.road_top() - g.Y_ROAD   # (the ground's own lift on hills)
	for p in line:
		up.append(Vector3(p.x, deck_y(ri, p) + e + lift, p.y))
		down.append(g._h(p) + e)
	return [up, down]

## a wall face between two lines (each a PackedVector3Array), facing `face`'s side
func _face(buf: RefCounted, a: PackedVector3Array, b: PackedVector3Array, out_dir: float, along: PackedVector2Array,
		gap := PackedByteArray()) -> void:
	for i in range(a.size() - 1):
		if not gap.is_empty() and (gap[i] == 1 or gap[i + 1] == 1):
			continue
		var d := (along[mini(i + 1, along.size() - 1)] - along[i]).normalized()
		var n := Vector3(-d.y, 0.0, d.x) * out_dir
		buf.tri(a[i], a[i + 1], b[i + 1], n, Color.WHITE)
		buf.tri(a[i], b[i + 1], b[i], n, Color.WHITE)

## a flat strip between two lines, facing up (or down)
func _strip(buf: RefCounted, a: PackedVector3Array, b: PackedVector3Array, up := true, gap := PackedByteArray()) -> void:
	for i in range(a.size() - 1):
		if not gap.is_empty() and (gap[i] == 1 or gap[i + 1] == 1):
			continue
		var n := Vector3.UP if up else Vector3.DOWN
		buf.tri(a[i], a[i + 1], b[i + 1], n, Color.WHITE)
		buf.tri(a[i], b[i + 1], b[i], n, Color.WHITE)

func _lowered(line: PackedVector3Array, to: PackedFloat32Array, extra: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in range(line.size()):
		out.append(Vector3(line[i].x, to[i] + extra, line[i].z))
	return out

func _shifted(line: PackedVector3Array, dy: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in line:
		out.append(v + Vector3(0, dy, 0))
	return out

## A bridge or an embankment: the pavement (or a shoulder) each side, the parapets, and under
## it a slab on piers (a bridge) or retaining walls down to the ground (an embankment).
func _raised(ri: int, pts: PackedVector2Array, walk: RefCounted, kerb: RefCounted, conc: RefCounted, stone: RefCounted,
		grass: RefCounted, rail: RefCounted) -> void:
	var r: Dictionary = g._roads[ri]
	var hw := float(r["w"]) * 0.5
	var side := float(r["side"])
	var bridge := String(r["deck"]) == "br"
	var paved := side > 1.0
	var top: float = g.KERB_H if paved else g.Y_ROAD
	for sd: float in [-1.0, 1.0]:
		var kerb_in: Array = _edge(ri, pts, hw * sd, g.Y_ROAD - 0.02)
		var kerb_top: Array = _edge(ri, pts, hw * sd, top)
		var inner: Array = _edge(ri, pts, (hw + side) * sd, top)
		var outer: Array = _edge(ri, pts, (hw + side + WALL_T) * sd, top)
		# the parapet: full height on a bridge; on an embankment it grows out of the ground
		# with the drop beside it (at the foot of the ramp it is nothing)
		var p_in := PackedVector3Array()
		var p_out := PackedVector3Array()
		var foot := PackedVector3Array()
		var under := PackedVector3Array()
		for i in range(pts.size()):
			var vi: Vector3 = (inner[0] as PackedVector3Array)[i]
			var vo: Vector3 = (outer[0] as PackedVector3Array)[i]
			var drop: float = vo.y - top - (outer[1] as PackedFloat32Array)[i]
			var ph := PARAPET if bridge else PARAPET * clampf((drop - 0.15) / 0.6, 0.0, 1.0)
			p_in.append(vi + Vector3(0, ph, 0))
			p_out.append(vo + Vector3(0, ph, 0))
			foot.append(Vector3(vo.x, (outer[1] as PackedFloat32Array)[i] - 0.4, vo.z))
			under.append(vo + Vector3(0, -SLAB - top, 0))
		var line: PackedVector2Array = g._offset_line(pts, hw * sd)
		# gaps: the walkway where it would lie on another road's carriageway (a slip road's
		# mouth up on the embankment; the street a ramp's foot runs into), the parapet and
		# its wall where another deck's road comes in
		var walk_line: PackedVector2Array = g._offset_line(pts, (hw + side * 0.5) * sd)
		var wall_line: PackedVector2Array = g._offset_line(pts, (hw + side + WALL_T * 0.5) * sd)
		var gap_walk := PackedByteArray()
		var gap_wall := PackedByteArray()
		for i in range(pts.size()):
			var y := deck_y(ri, pts[i])
			var low := _low(r, pts[i], y)
			gap_walk.append(1 if open_at(ri, walk_line[i], y, false) or (low and g._asphalt_other(walk_line[i], ri)) else 0)
			gap_wall.append(1 if open_at(ri, wall_line[i], y) else 0)
		# a grass bank where there is room (bank_at), else the wall: a point is the bank's
		# only when it and both its neighbours are, so the wall reaches into each change
		var outs := _outs(pts, sd)
		var widths := PackedFloat32Array()
		for i in range(pts.size()):
			widths.append(-1.0 if bridge else bank_at(ri, pts[i], outs[i], deck_y(ri, pts[i])))
		var gap_bank := PackedByteArray()
		var gap_w := PackedByteArray()
		for i in range(pts.size()):
			var b_here := widths[i] > 0.0
			var b_all := b_here and (i == 0 or widths[i - 1] >= 0.0) and (i == pts.size() - 1 or widths[i + 1] >= 0.0)
			gap_bank.append(0 if b_here or (widths[i] == 0.0) else 1)
			gap_w.append(1 if gap_wall[i] == 1 or b_all else 0)
		if paved:
			_face(kerb, kerb_in[0], kerb_top[0], -sd, line, gap_walk)
		_strip(walk if paved else conc, kerb_top[0], inner[0], true, gap_walk)
		_face(conc, inner[0], p_in, -sd, line, gap_w)              # the parapet's inner face
		_strip(conc, p_in, p_out, true, gap_w)                     # its top
		if bridge:
			_face(conc, p_out, under, sd, line, gap_w)             # the slab's edge and the parapet's outside
		else:
			_face(stone, p_out, foot, sd, line, gap_w)             # the retaining wall, down into the ground
			_bank(ri, pts, sd, outs, widths, gap_bank, inner[0], grass, rail, top)
	if bridge:
		var lo_l: Array = _edge(ri, pts, -(hw + side + WALL_T), -SLAB)
		var lo_r: Array = _edge(ri, pts, hw + side + WALL_T, -SLAB)
		_strip(conc, lo_l[0], lo_r[0], false)
		for pier: Array in piers(ri):
			var c: Vector2 = pier[0]
			if not g._mine(c):
				continue
			var across: Vector2 = pier[1]
			var along := Vector2(across.y, -across.x)
			var half: float = pier[2]
			var thick: float = pier[4]
			var y_top: float = float(pier[3]) - SLAB + (g.road_top() - g.Y_ROAD)
			var y_bot: float = g._h(c) - 1.5
			var mid := Vector3(c.x, (y_top + y_bot) * 0.5, c.y)
			g._obox(conc, mid, Vector3(half * 2.0, y_top - y_bot, thick), atan2(along.x, along.y))
			# rounded noses up and down stream: a column at each end
			for e: float in [-1.0, 1.0]:
				var q := c + across * half * e
				g._obox(conc, Vector3(q.x, mid.y, q.y), Vector3(thick, y_top - y_bot, thick), atan2(along.x, along.y) + PI * 0.25)
	# where a bridge's span starts off an embankment: the embankment's end wall under it
	if not bridge:
		var ids: PackedInt32Array = r["ids"]
		for end: int in [0, ids.size() - 1]:
			var into_bridge := false
			for e: Vector2i in g._node_roads[ids[end]]:
				if e.x != ri and String((g._roads[e.x] as Dictionary).get("deck", "")) == "br":
					into_bridge = true
			if not into_bridge:
				continue
			var p: Vector2 = (r["pts"] as PackedVector2Array)[end]
			if not g._mine(p):
				continue
			var nxt: Vector2 = (r["pts"] as PackedVector2Array)[1 if end == 0 else end - 1]
			var d := (nxt - p).normalized()
			var y: float = deck_y(ri, p) + (g.road_top() - g.Y_ROAD)
			var gy: float = g._h(p) - 1.0
			var c := p + d * 0.6
			g._obox(stone, Vector3(c.x, (y + gy) * 0.5, c.y), Vector3((hw + side + WALL_T) * 2.0, y - gy, 1.2), atan2(d.x, d.y))

## the grass bank down one side of an embankment, from the walkway's (or shoulder's) edge
## to the ground BANK out for each metre down, and the guardrail along its top
func _bank(ri: int, pts: PackedVector2Array, sd: float, outs: PackedVector2Array, widths: PackedFloat32Array,
		gap: PackedByteArray, edge_top: PackedVector3Array, grass: RefCounted, rail: RefCounted, top: float) -> void:
	var r: Dictionary = g._roads[ri]
	var e0 := float(r["w"]) * 0.5 + float(r["side"])
	var lift: float = g.road_top() - g.Y_ROAD
	var feet := PackedVector3Array()
	for i in range(pts.size()):
		var f := pts[i] + outs[i] * (e0 + maxf(widths[i], 0.0))
		feet.append(Vector3(f.x, float(g._h(f)) + lift - 0.15, f.y))
	for i in range(pts.size() - 1):
		if gap[i] == 1 or gap[i + 1] == 1 or maxf(widths[i], widths[i + 1]) <= 0.0:
			continue
		grass.quad3(edge_top[i] + Vector3(0, -0.03, 0), edge_top[i + 1] + Vector3(0, -0.03, 0), feet[i + 1], feet[i])
	# the guardrail: a post every 2 m, a steel beam along them
	var rl: PackedVector2Array = g._offset_line(pts, (e0 - 0.15) * sd)
	var acc := 0.0
	for i in range(pts.size() - 1):
		var L := rl[i].distance_to(rl[i + 1])
		if gap[i] == 1 or gap[i + 1] == 1 or minf(widths[i], widths[i + 1]) <= 0.0:
			acc = 0.0
			continue
		var y0: float = edge_top[i].y
		var y1: float = edge_top[i + 1].y
		var yaw := atan2(rl[i + 1].x - rl[i].x, rl[i + 1].y - rl[i].y)
		var m := (rl[i] + rl[i + 1]) * 0.5
		if g._mine(m):
			g._obox(rail, Vector3(m.x, (y0 + y1) * 0.5 + GUARD_H - 0.17, m.y), Vector3(0.05, 0.3, L + 0.02), yaw, -atan2(y1 - y0, L))
		while acc < L:
			var q := rl[i].lerp(rl[i + 1], acc / maxf(L, 0.001))
			if g._mine(q):
				g._obox(rail, Vector3(q.x, lerpf(y0, y1, acc / maxf(L, 0.001)) + GUARD_H * 0.5, q.y), Vector3(0.1, GUARD_H, 0.1), yaw)
			acc += 2.0
		acc -= L

## A cutting: a shoulder each side, walls up to the ground with a coping, a railing along the
## top where it is deep enough to fall into. (The ground over it is cut away: cut_tri.)
func _cutting(ri: int, pts: PackedVector2Array, conc: RefCounted, rail: RefCounted) -> void:
	var r: Dictionary = g._roads[ri]
	var hw := float(r["w"]) * 0.5
	var side := float(r["side"])
	var e: float = g.road_top() - g.Y_ROAD
	for sd: float in [-1.0, 1.0]:
		var edge_l: PackedVector2Array = g._offset_line(pts, hw * sd)
		var sh_in: Array = _edge(ri, pts, hw * sd, g.Y_ROAD)
		var sh_out: Array = _edge(ri, pts, (hw + side) * sd, g.Y_ROAD)
		var w_in: Array = _edge(ri, pts, (hw + side) * sd, 0.0)
		var w_out: Array = _edge(ri, pts, (hw + side + WALL_T) * sd, 0.0)
		var deep := PackedByteArray()
		for i in range(w_in[0].size()):
			deep.append(1 if (w_in[1] as PackedFloat32Array)[i] - (w_in[0] as PackedVector3Array)[i].y > 0.05 else 0)
		_strip(conc, sh_in[0], sh_out[0])
		var top_in := _lowered(w_in[0], w_in[1], 0.12)
		var top_out := _lowered(w_out[0], w_out[1], 0.12)
		for i in range(top_in.size()):   # (no lower than the road where the ground is)
			top_in[i].y = maxf(top_in[i].y, (w_in[0] as PackedVector3Array)[i].y + g.Y_ROAD)
			top_out[i].y = maxf(top_out[i].y, (w_out[0] as PackedVector3Array)[i].y + g.Y_ROAD)
		var line := PackedVector2Array()
		var a := PackedVector3Array()
		var b := PackedVector3Array()
		var c := PackedVector3Array()
		var dd := PackedVector3Array()
		for i in range(top_in.size()):
			if deep[i] == 0 and (i == 0 or deep[i - 1] == 0) and (i == top_in.size() - 1 or deep[i + 1] == 0):
				continue
			line.append(edge_l[i])
			a.append((w_in[0] as PackedVector3Array)[i] + Vector3(0, -0.1, 0))
			b.append(top_in[i])
			c.append(top_out[i])
		if a.size() >= 2:
			_face(conc, a, b, -sd, line)
			_strip(conc, b, c)
		# the railing on top: posts every 2.4 m and a rail, where the drop is a metre or more
		var rl: Array = _edge(ri, pts, (hw + side + WALL_T * 0.5) * sd, 0.0)
		var s := 0.0
		for i in range(rl[0].size() - 1):
			var p0: Vector3 = rl[0][i]
			var p1: Vector3 = rl[0][i + 1]
			var g0: float = rl[1][i]
			var g1: float = rl[1][i + 1]
			if g0 - p0.y < 1.0 or g1 - p1.y < 1.0:
				s += Vector2(p1.x - p0.x, p1.z - p0.z).length()
				continue
			var q0 := Vector3(p0.x, g0 + 0.12, p0.z)
			var q1 := Vector3(p1.x, g1 + 0.12, p1.z)
			if not g._mine(Vector2(q0.x, q0.z)):
				continue
			var L := Vector2(q1.x - q0.x, q1.z - q0.z).length()
			var yaw := atan2(q1.x - q0.x, q1.z - q0.z)
			g._obox(rail, (q0 + q1) * 0.5 + Vector3(0, 1.0, 0), Vector3(0.06, 0.06, L), yaw)
			g._obox(rail, (q0 + q1) * 0.5 + Vector3(0, 0.55, 0), Vector3(0.04, 0.04, L), yaw)
			while s < L:
				var q := q0.lerp(q1, s / maxf(L, 0.001))
				g._obox(rail, q + Vector3(0, 0.5, 0), Vector3(0.06, 1.0, 0.06), yaw)
				s += 2.4
			s -= L

## A tunnel: a raised walk each side, tiled walls, the ceiling, two rows of lamps, and a
## headwall over each mouth that opens to the air.
func _tunnel(ri: int, pts: PackedVector2Array, walk: RefCounted, kerb: RefCounted, tile: RefCounted, tube: RefCounted, lamps: RefCounted) -> void:
	var r: Dictionary = g._roads[ri]
	var hw := float(r["w"]) * 0.5
	var side := float(r["side"])
	var e: float = g.road_top() - g.Y_ROAD
	for sd: float in [-1.0, 1.0]:
		var line: PackedVector2Array = g._offset_line(pts, hw * sd)
		var k_lo: Array = _edge(ri, pts, hw * sd, g.Y_ROAD - 0.02)
		var k_hi: Array = _edge(ri, pts, hw * sd, g.KERB_H + 0.12)
		var w_lo: Array = _edge(ri, pts, (hw + side) * sd, g.KERB_H + 0.12)
		var w_band: Array = _edge(ri, pts, (hw + side) * sd, 2.8)
		var w_hi: Array = _edge(ri, pts, (hw + side) * sd, TUBE_H)
		_face(kerb, k_lo[0], k_hi[0], -sd, line)
		_strip(walk, k_hi[0], w_lo[0])
		_face(tile, w_lo[0], w_band[0], -sd, line)
		_face(tube, w_band[0], w_hi[0], -sd, line)
	var c_l: Array = _edge(ri, pts, -(hw + side), TUBE_H)
	var c_r: Array = _edge(ri, pts, hw + side, TUBE_H)
	_strip(tube, c_l[0], c_r[0], false)
	# lamps: a row each side under the ceiling, a fitting every 5 m
	for sd: float in [-1.0, 1.0]:
		var row: Array = _edge(ri, pts, (hw - 0.6) * sd, TUBE_H - 0.12)
		var line: PackedVector2Array = g._offset_line(pts, (hw - 0.6) * sd)
		var acc := 0.0
		for i in range(line.size() - 1):
			var L := line[i].distance_to(line[i + 1])
			while acc < L:
				var p: Vector3 = (row[0][i] as Vector3).lerp(row[0][i + 1], acc / maxf(L, 0.001))
				if g._mine(Vector2(p.x, p.z)):
					g._obox(lamps, p, Vector3(0.35, 0.1, 1.6), atan2(line[i + 1].x - line[i].x, line[i + 1].y - line[i].y))
				acc += 5.0
			acc -= L
	# headwalls where it opens to the air
	var src: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	for end: int in [0, ids.size() - 1]:
		var open := false
		for ev: Vector2i in g._node_roads[ids[end]]:
			if ev.x != ri and String((g._roads[ev.x] as Dictionary).get("deck", "")) != "tu":
				open = true
		var p := src[end]
		if not open or not g._mine(p):
			continue
		var into := (src[1 if end == 0 else end - 1] - p).normalized()
		var across := Vector2(-into.y, into.x)
		var y0 := deck_y(ri, p) + e + TUBE_H
		var reach := hw + side + WALL_T + 0.8
		var top := y0
		for k in range(-4, 5):
			top = maxf(top, g._h(p + across * reach * k / 4.0) + e)
		top += 0.35
		var face := p - into * 0.25
		g._obox(tube, Vector3(face.x, (y0 + top) * 0.5, face.y), Vector3(reach * 2.0, top - y0, 0.5), atan2(into.x, into.y))
		# a lintel over the mouth, a little proud of the wall
		var lip := p - into * 0.55
		g._obox(tube, Vector3(lip.x, y0 + 0.35, lip.y), Vector3((hw + side) * 2.0 + 0.6, 0.7, 0.4), atan2(into.x, into.y))

## ---- heights for a real town's bridges, worked out from OSM's tags and the ground ----------
##
## OSM says which ways are bridges but not how high: a bridge way is mostly just the span,
## the ramps up to it ordinary ways. infer() writes heights (`y`) into a city file's data as
## it loads, as if the bake had: wherever a bridge crosses a road or a path it must clear it
## (CLEAR_ROAD, CLEAR_PATH over the ground there); that lift spreads out along the drivable
## roads from the crossing, falling by a ramp's grade, through junctions (an interchange's
## junctions end up up on the embankment and its slip roads come down from them) but never
## onto the road crossed. Each road is cut where its lift runs out: the lifted part becomes a
## deck (a bridge stays a bridge, the rest embankments), the rest stays on the ground. A
## bridge that crosses nothing (a creek's) spans straight from one end to the other. Bridges
## shorter than MIN_BRIDGE are culverts and stay as they were; tunnels are left out still.
const CLEAR_ROAD := 6.4       ## a bridge's road over a road: 5.2 m clear, and the deck
const CLEAR_PATH := 4.4       ## ... over a footpath, a cycleway
const RAMP_FAST := 0.05       ## a ramp's grade on a motorway, a trunk road, a slip road
const RAMP := 0.07            ## ... on anything else
const MIN_BRIDGE := 8.0
const CLEAR_UNDER := 6.2      ## a tunnel's road under what it crosses: 4.8 m clear, the roof, a little earth
const MIN_TUNNEL := 20.0      ## shorter "tunnels" are passages under a building: on the ground
const FAST := {"motorway": true, "trunk": true, "motorway_link": true, "trunk_link": true, "primary_link": true}
const CAP_FAST := 0.07        ## the steepest a ramp may be, when there is no room for a gentler one
const CAP := 0.10
## which of two bridges that cross goes over, when OSM gives no layer: a slip road or a lesser
## road over the main line
const MAIN_LINE := {"motorway": 3, "trunk": 3, "primary": 2, "secondary": 1}

static func _hgt(hg: Dictionary, p: Vector2, k: float) -> float:
	var x0 := float(hg["x0"])
	var z0 := float(hg["z0"])
	var st := float(hg["step"])
	var nx := int(hg["nx"])
	var nz := int(hg["nz"])
	var hh: Array = hg["h"]
	var fx := clampf((p.x - x0) / st, 0.0, float(nx) - 1.001)
	var fz := clampf((p.y - z0) / st, 0.0, float(nz) - 1.001)
	var i := int(fx)
	var j := int(fz)
	var ax := fx - i
	var az := fz - j
	var r := j * nx + i
	if ax + az <= 1.0:
		return (float(hh[r]) + (float(hh[r + 1]) - float(hh[r])) * ax + (float(hh[r + nx]) - float(hh[r])) * az) * k
	var h11 := float(hh[r + nx + 1])
	return (h11 + (float(hh[r + nx]) - h11) * (1.0 - ax) + (float(hh[r + 1]) - h11) * (1.0 - az)) * k

## the city file's data, edited in place; returns what it did (for the report)
static func infer(data: Dictionary, drive: Dictionary) -> Dictionary:
	var hg: Dictionary = data.get("height", {})
	if hg.is_empty() or data["roads"].is_empty():
		return {}
	var k := 1.0 / float(data.get("scale", 10))
	var nd: Array = data["nodes"]
	var roads: Array = data["roads"]
	var pos := func(i: int) -> Vector2: return Vector2(float(nd[i * 2]), float(nd[i * 2 + 1])) * k
	var add_node := func(p: Vector2) -> int:
		nd.append(roundi(p.x / k))
		nd.append(roundi(p.y / k))
		return nd.size() / 2 - 1
	var drv := func(r: Dictionary) -> bool: return drive.has(String(r.get("k", "")))
	var gnd := {}
	var ground := func(n: int) -> float:
		if not gnd.has(n):
			gnd[n] = _hgt(hg, pos.call(n), k)
		return gnd[n]
	# the bridges worth the name: drivable, in chains of ways at least MIN_BRIDGE long
	var at := {}
	for ri in range(roads.size()):
		for n in roads[ri]["n"]:
			if not at.has(int(n)):
				at[int(n)] = []
			(at[int(n)] as Array).append(ri)
	var is_br := {}
	var seen := {}
	for ri in range(roads.size()):
		var r: Dictionary = roads[ri]
		if seen.has(ri) or not r.has("br") or not drv.call(r) or r.has("y"):
			continue
		var comp: Array = [ri]
		seen[ri] = true
		var todo: Array = [ri]
		var total := 0.0
		while not todo.is_empty():
			var a: int = todo.pop_back()
			var ns: Array = roads[a]["n"]
			for j in range(ns.size() - 1):
				total += (pos.call(int(ns[j])) as Vector2).distance_to(pos.call(int(ns[j + 1])))
			for e in [ns[0], ns[ns.size() - 1]]:
				for b: int in at[int(e)]:
					if not seen.has(b) and roads[b].has("br") and drv.call(roads[b]):
						seen[b] = true
						comp.append(b)
						todo.append(b)
		if total >= MIN_BRIDGE:
			for b: int in comp:
				is_br[b] = true
	var any_tu := false
	for r: Dictionary in roads:
		any_tu = any_tu or (r.has("tu") and drv.call(r) and not r.has("y"))
	if is_br.is_empty() and not any_tu:
		return {}
	# every other road's segments in a grid, to find what each bridge crosses
	var cell := 32.0
	var grid := {}
	for ri in range(roads.size()):
		if is_br.has(ri) or roads[ri].has("br") or roads[ri].has("tu"):
			continue
		var ns: Array = roads[ri]["n"]
		for j in range(ns.size() - 1):
			var a: Vector2 = pos.call(int(ns[j]))
			var b: Vector2 = pos.call(int(ns[j + 1]))
			var c0 := Vector2i(floori(minf(a.x, b.x) / cell), floori(minf(a.y, b.y) / cell))
			var c1 := Vector2i(floori(maxf(a.x, b.x) / cell), floori(maxf(a.y, b.y) / cell))
			for cx in range(c0.x, c1.x + 1):
				for cz in range(c0.y, c1.y + 1):
					var key := Vector2i(cx, cz)
					if not grid.has(key):
						grid[key] = []
					(grid[key] as Array).append(ri * 4096 + j)
	# the crossings: a node put in the bridge where it crosses, needing that much lift
	var lift := {}        # node -> metres over the ground it must be
	var pinned := {}      # nodes that stay on the ground: the roads crossed
	var over_roads: Array = []   # crossing nodes over a road (to report the clearance left)
	var over_name := {}
	var crossed := 0
	for ri: int in is_br:
		var ns: Array = roads[ri]["n"]
		var out: Array = [ns[0]]
		for j in range(ns.size() - 1):
			var a: Vector2 = pos.call(int(ns[j]))
			var b: Vector2 = pos.call(int(ns[j + 1]))
			var hits: Array = []   # [t along ab, point, clearance]
			var c0 := Vector2i(floori(minf(a.x, b.x) / cell), floori(minf(a.y, b.y) / cell))
			var c1 := Vector2i(floori(maxf(a.x, b.x) / cell), floori(maxf(a.y, b.y) / cell))
			var done := {}
			for cx in range(c0.x, c1.x + 1):
				for cz in range(c0.y, c1.y + 1):
					for code: int in grid.get(Vector2i(cx, cz), []):
						if done.has(code):
							continue
						done[code] = true
						var rj := code / 4096
						var sj := code % 4096
						var ms: Array = roads[rj]["n"]
						if int(ms[sj]) in [int(ns[j]), int(ns[j + 1])] or int(ms[sj + 1]) in [int(ns[j]), int(ns[j + 1])]:
							continue
						var x = Geometry2D.segment_intersects_segment(a, b, pos.call(int(ms[sj])), pos.call(int(ms[sj + 1])))
						if x == null:
							continue
						var under_road: bool = drv.call(roads[rj])
						hits.append([a.distance_to(x) / maxf(a.distance_to(b), 0.001), x, CLEAR_ROAD if under_road else CLEAR_PATH,
							roads[rj].get("name_en", roads[rj].get("name", roads[rj]["k"]))])
						if under_road:   # (the road crossed stays on the ground, where it passes under)
							for m in ms:
								if (pos.call(int(m)) as Vector2).distance_to(x) < 80.0:
									pinned[int(m)] = true
			hits.sort_custom(func(p, q): return p[0] < q[0])
			for hit: Array in hits:
				var n: int = add_node.call(hit[1])
				out.append(n)
				if float(hit[2]) >= CLEAR_ROAD:
					over_roads.append(n)
					over_name[n] = "%s over %s" % [roads[ri].get("name_en", roads[ri].get("name", roads[ri]["k"])), hit[3]]
				lift[n] = maxf(float(lift.get(n, 0.0)), float(hit[2]))
				crossed += 1
			out.append(ns[j + 1])
		roads[ri]["n"] = out
	# rebuild the node -> roads map with the new nodes, then spread the lift: the drivable
	# roads as a graph, each step losing its ramp's grade, never onto a pinned node
	at = {}
	for ri in range(roads.size()):
		for n in roads[ri]["n"]:
			if not at.has(int(n)):
				at[int(n)] = []
			(at[int(n)] as Array).append(ri)
	var spread := func(seeds: Array, frozen: Dictionary) -> void:
		var queue: Array = seeds.duplicate()
		while not queue.is_empty():
			var best := 0
			for i in range(queue.size()):
				if float(lift[queue[i]]) > float(lift[queue[best]]):
					best = i
			var u: int = queue[best]
			queue.remove_at(best)
			var lu: float = lift[u]
			for ri: int in at.get(u, []):
				var r: Dictionary = roads[ri]
				if not drv.call(r):
					continue
				var grade := RAMP_FAST if FAST.has(String(r["k"])) else RAMP
				var ns: Array = r["n"]
				for j in range(ns.size()):
					if int(ns[j]) != u:
						continue
					for step: int in [-1, 1]:
						if j + step < 0 or j + step >= ns.size():
							continue
						var v := int(ns[j + step])
						if (pinned.has(v) and not is_br.has(ri)) or frozen.has(v):
							continue
						# (the road's own grade, not its height over a ground that may fall away too)
						var top_v := float(ground.call(u)) + lu - grade * (pos.call(u) as Vector2).distance_to(pos.call(v))
						var lv := top_v - float(ground.call(v))
						if lv > float(lift.get(v, 0.0)) + 0.01 and lv > 0.0:
							lift[v] = lv
							if not queue.has(v):
								queue.append(v)
	spread.call(lift.keys(), {})
	# a bridge over another bridge (a stack of ramps): the upper -- OSM's layer, else the lesser
	# road -- must clear the lower's deck as the first round left it
	var later := {}
	var stacked := 0
	var bkeys: Array = is_br.keys()
	for ai in range(bkeys.size()):
		for bi in range(ai + 1, bkeys.size()):
			var ra: Dictionary = roads[bkeys[ai]]
			var rb: Dictionary = roads[bkeys[bi]]
			var na: Array = ra["n"]
			var nb: Array = rb["n"]
			for j in range(na.size() - 1):
				for m in range(nb.size() - 1):
					var a0: Vector2 = pos.call(int(na[j]))
					var a1: Vector2 = pos.call(int(na[j + 1]))
					var b0: Vector2 = pos.call(int(nb[m]))
					var b1: Vector2 = pos.call(int(nb[m + 1]))
					if int(na[j]) in [int(nb[m]), int(nb[m + 1])] or int(na[j + 1]) in [int(nb[m]), int(nb[m + 1])]:
						continue
					var x = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
					if x == null:
						continue
					var la := int(ra.get("ly", 1))
					var lb := int(rb.get("ly", 1))
					var a_up := la > lb if la != lb else int(MAIN_LINE.get(String(ra["k"]), 0)) < int(MAIN_LINE.get(String(rb["k"]), 0))
					var up_n: Array = na if a_up else nb
					var lo_n: Array = nb if a_up else na
					var uj: int = j if a_up else m
					var lj: int = m if a_up else j
					var t_lo := (pos.call(int(lo_n[lj])) as Vector2).distance_to(x) / maxf((pos.call(int(lo_n[lj])) as Vector2).distance_to(pos.call(int(lo_n[lj + 1]))), 0.001)
					var lo_lift := lerpf(float(lift.get(int(lo_n[lj]), 0.0)), float(lift.get(int(lo_n[lj + 1]), 0.0)), t_lo)
					# the nearer of the upper's two points carries it (no new node: rare enough)
					var u0: Vector2 = pos.call(int(up_n[uj]))
					var u1: Vector2 = pos.call(int(up_n[uj + 1]))
					var un := int(up_n[uj]) if u0.distance_to(x) < u1.distance_to(x) else int(up_n[uj + 1])
					later[un] = maxf(float(later.get(un, 0.0)), lo_lift + CLEAR_ROAD)
					for q in lo_n:
						later["frozen_%d" % int(q)] = true
					stacked += 1
	var frozen := {}
	var seeds: Array = []
	for key in later:
		if key is String:
			frozen[int(String(key).substr(7))] = true
		elif float(later[key]) > float(lift.get(key, 0.0)):
			lift[key] = later[key]
			seeds.append(key)
	spread.call(seeds, frozen)
	# no ramp steeper than CAP: each lift at most what a ramp from the nearest node held on
	# the ground can climb to (a slip road too short for the lift at its top is steep, not a
	# cliff: the lift at the top gives)
	var cap := {}
	var queue: Array = []
	for n in pinned:
		if at.has(n):
			cap[n] = float(ground.call(n))   # (a height, not a lift)
			queue.append(n)
	while not queue.is_empty():
		var best := 0
		for i in range(queue.size()):
			if float(cap[queue[i]]) < float(cap[queue[best]]):
				best = i
		var u: int = queue[best]
		queue.remove_at(best)
		var cu: float = cap[u]
		if cu - float(ground.call(u)) > 12.0:
			continue
		for ri: int in at.get(u, []):
			var r: Dictionary = roads[ri]
			if not drv.call(r):
				continue
			var grade := CAP_FAST if FAST.has(String(r["k"])) else CAP
			var ns: Array = r["n"]
			for j in range(ns.size()):
				if int(ns[j]) != u:
					continue
				for step: int in [-1, 1]:
					if j + step < 0 or j + step >= ns.size():
						continue
					var v := int(ns[j + step])
					var cv := cu + grade * (pos.call(u) as Vector2).distance_to(pos.call(v))
					if cv < float(cap.get(v, INF)) - 0.01:
						cap[v] = cv
						if not queue.has(v):
							queue.append(v)
	var capped := 0
	for n in lift:
		var room := float(cap.get(n, INF)) - float(ground.call(n))
		if float(lift[n]) > room + 0.01:
			lift[n] = maxf(room, 0.0)
			capped += 1
	# Tunnels, the mirror of the bridges: a drivable tunnel way that runs under something lies
	# CLEAR_UNDER down along all of it (OSM's tunnel way is the covered part), and the depth
	# rises back to the ground along the roads either side -- cuttings -- at a ramp's grade,
	# never through a junction (the next crossing is at street level) nor onto what it runs
	# under. One that runs under nothing mapped (a passage through a building) is put back on
	# the ground. Depths go into `lift` as negative lifts: the rest treats them alike.
	var is_tu := {}
	var dig := {}
	var branch: Array = []   # tunnel ways under nothing mapped: a passage, or a branch of a tunnel
	for ri in range(roads.size()):
		var r: Dictionary = roads[ri]
		if not r.has("tu") or not drv.call(r) or r.has("y"):
			continue
		var ns: Array = r["n"]
		var own := String(r.get("name", ""))
		var over: Array = []
		var total := 0.0
		for j in range(ns.size() - 1):
			var a: Vector2 = pos.call(int(ns[j]))
			var b: Vector2 = pos.call(int(ns[j + 1]))
			total += a.distance_to(b)
			var c0 := Vector2i(floori(minf(a.x, b.x) / cell), floori(minf(a.y, b.y) / cell))
			var c1 := Vector2i(floori(maxf(a.x, b.x) / cell), floori(maxf(a.y, b.y) / cell))
			for cx in range(c0.x, c1.x + 1):
				for cz in range(c0.y, c1.y + 1):
					for code: int in grid.get(Vector2i(cx, cz), []):
						var ms: Array = roads[code / 4096]["n"]
						var sj := code % 4096
						if int(ms[sj]) in [int(ns[j]), int(ns[j + 1])] or int(ms[sj + 1]) in [int(ns[j]), int(ns[j + 1])]:
							continue   # (its own next piece, a road meeting it: not over it)
						if own != "" and String(roads[code / 4096].get("name", "")) == own:
							continue   # (the other half of a divided road, crossing its line by a metre
							           # where the halves close in at a mouth: not over it -- it held
							           # Begin's southbound underpass up in Tel Aviv)
						var xt = Geometry2D.segment_intersects_segment(a, b, pos.call(int(ms[sj])), pos.call(int(ms[sj + 1])))
						if xt != null:
							over.append([code / 4096, xt])
		if over.is_empty() and int(r.get("ly", 0)) < 0 and String(r["k"]) != "service":
			branch.append(ri)   # (decided below: on the ground, unless it joins a tunnel)
			continue
		if over.is_empty() or total < MIN_TUNNEL:
			r.erase("tu")   # (on the ground, where the game drew it before it had tunnels)
			continue
		is_tu[ri] = true
		for ov: Array in over:
			if drv.call(roads[int(ov[0])]):
				for m in roads[int(ov[0])]["n"]:
					if (pos.call(int(m)) as Vector2).distance_to(ov[1]) < 80.0:
						pinned[int(m)] = true
	# A tunnel way under nothing mapped, below the ground, that meets a tunnel at an end is a
	# branch of it, dug with it (Lova Eliav's two links into Begin's underpass, underground):
	# put back on the ground, it made the junction they meet at a street's and held the
	# tunnel up. The rest are passages: on the ground as before.
	var grew := true
	while grew:
		grew = false
		for ri: int in branch.duplicate():
			var ns: Array = roads[ri]["n"]
			var joins := false
			for e in [ns[0], ns[ns.size() - 1]]:
				for rj: int in at.get(int(e), []):
					joins = joins or is_tu.has(rj)
			if joins:
				is_tu[ri] = true
				branch.erase(ri)
				grew = true
	for ri: int in branch:
		roads[ri].erase("tu")
	var junction := func(n: int) -> bool:   # more than two ways out of n, along drivable roads
		var ends := 0
		for rj: int in at.get(n, []):
			if drv.call(roads[rj]):
				var mn: Array = roads[rj]["n"]
				ends += 1 if int(mn[0]) == n or int(mn[mn.size() - 1]) == n else 2
		return ends >= 3
	# how deep each point may be: CAP down for each metre from the nearest point held at street
	# level (what a tunnel runs under, a junction off it). A tunnel that cannot get down to
	# CLEAR_UNDER between them is too short for its cuttings: it stays on the ground.
	var room := {}
	var rq: Array = []
	var dropped: Array = []
	var near_tu: Array = []   # (only near a tunnel does it matter: the whole town took 15 s)
	for ri: int in is_tu:
		for n in roads[ri]["n"]:
			near_tu.append(pos.call(int(n)))
	for n in at:
		if is_tu.is_empty():
			break
		var p: Vector2 = pos.call(int(n))
		var close := false
		for q: Vector2 in near_tu:
			if q.distance_squared_to(p) < 40000.0:
				close = true
				break
		if not close:
			continue
		var on_tu := false
		for rj: int in at[n]:
			on_tu = on_tu or is_tu.has(rj)
		if pinned.has(n) or (junction.call(n) and not on_tu):
			room[n] = 0.0
			rq.append(n)
	while not rq.is_empty():
		var best := 0
		for i in range(rq.size()):
			if float(room[rq[i]]) < float(room[rq[best]]):
				best = i
		var u: int = rq[best]
		rq.remove_at(best)
		if float(room[u]) > CLEAR_UNDER + 1.0:
			continue
		for rj: int in at.get(u, []):
			if not drv.call(roads[rj]):
				continue
			var mn: Array = roads[rj]["n"]
			for j in range(mn.size()):
				if int(mn[j]) != u:
					continue
				for step: int in [-1, 1]:
					if j + step < 0 or j + step >= mn.size():
						continue
					var v := int(mn[j + step])
					var rv := float(room[u]) + CAP * (pos.call(u) as Vector2).distance_to(pos.call(v))
					if rv < float(room.get(v, INF)) - 0.01:
						room[v] = rv
						if not rq.has(v):
							rq.append(v)
	for ri: int in is_tu.keys():
		var deep_enough := true
		for n in roads[ri]["n"]:
			deep_enough = deep_enough and float(room.get(int(n), INF)) >= CLEAR_UNDER - 0.8
		if not deep_enough:
			var mr := INF
			var why := -1
			for n in roads[ri]["n"]:
				if float(room.get(int(n), INF)) < mr:
					mr = float(room.get(int(n), INF))
					why = int(n)
			dropped.append("%s at (%d, %d): %.1f m room, held %s" % [roads[ri].get("name_en", roads[ri].get("name", roads[ri]["k"])),
				int(pos.call(why).x), int(pos.call(why).y), mr, "pinned" if pinned.has(why) else ("junction" if junction.call(why) else "near")])
			is_tu.erase(ri)
			roads[ri].erase("tu")
			continue
		for n in roads[ri]["n"]:
			dig[int(n)] = CLEAR_UNDER
	var dq: Array = dig.keys()
	while not dq.is_empty():
		var best := 0
		for i in range(dq.size()):
			if float(dig[dq[i]]) > float(dig[dq[best]]):
				best = i
		var u: int = dq[best]
		dq.remove_at(best)
		for ri: int in at.get(u, []):
			var r: Dictionary = roads[ri]
			if not drv.call(r) or is_tu.has(ri):
				continue
			var grade := RAMP_FAST if FAST.has(String(r["k"])) else RAMP
			var ns: Array = r["n"]
			for j in range(ns.size()):
				if int(ns[j]) != u:
					continue
				for step: int in [-1, 1]:
					if j + step < 0 or j + step >= ns.size():
						continue
					var v := int(ns[j + step])
					if pinned.has(v) or junction.call(v):
						continue   # (the cutting comes up to a junction, which stays at street level)
					var bot := float(ground.call(u)) - float(dig[u]) + grade * (pos.call(u) as Vector2).distance_to(pos.call(v))
					var dv := float(ground.call(v)) - bot
					if dv > float(dig.get(v, 0.0)) + 0.01 and dv > 0.0:
						dig[v] = dv
						if not dq.has(v):
							dq.append(v)
	for n in dig:
		if float(lift.get(n, 0.0)) <= 0.05:
			lift[n] = -minf(float(dig[n]), float(room.get(n, INF)))
	# where a ramp runs out part way along a segment: a node there, on the ground
	for ri in range(roads.size()):
		var r: Dictionary = roads[ri]
		if not drv.call(r) or is_br.has(ri) or is_tu.has(ri):
			continue
		var ns: Array = r["n"]
		var any := false
		for n in ns:
			any = any or absf(float(lift.get(int(n), 0.0))) > 0.05
		if not any:
			continue
		var grade := RAMP_FAST if FAST.has(String(r["k"])) else RAMP
		var out: Array = [ns[0]]
		for j in range(ns.size() - 1):
			var la := float(lift.get(int(ns[j]), 0.0))
			var lb := float(lift.get(int(ns[j + 1]), 0.0))
			if (absf(la) > 0.05) != (absf(lb) > 0.05):
				var a: Vector2 = pos.call(int(ns[j]))
				var b: Vector2 = pos.call(int(ns[j + 1]))
				var L := maxf(a.distance_to(b), 0.001)
				# where the ramp (or the cutting), at its grade, meets the ground (which slopes too)
				var g_from := float(ground.call(int(ns[j]) if absf(la) > absf(lb) else int(ns[j + 1])))
				var g_to := float(ground.call(int(ns[j + 1]) if absf(la) > absf(lb) else int(ns[j])))
				var off := la if absf(la) > absf(lb) else lb
				var closing := grade + signf(off) * (g_to - g_from) / L
				var t := (absf(off) / closing) / L if closing > 0.001 else 1.0
				if t < 0.98:
					var p: Vector2 = a.lerp(b, t) if absf(la) > absf(lb) else b.lerp(a, t)
					out.append(add_node.call(p))
			out.append(ns[j + 1])
		r["n"] = out
	# each road cut into its lifted runs (decks) and the rest (as it was)
	var made: Array = []
	var decks := 0
	for ri in range(roads.size()):
		var r: Dictionary = roads[ri]
		var ns: Array = r["n"]
		var up := func(n) -> bool: return absf(float(lift.get(int(n), 0.0))) > 0.05
		if not is_br.has(ri) and not is_tu.has(ri) and (not drv.call(r) or not ns.any(up)):   # (a footpath stays on the ground)
			made.append(r)
			continue
		var runs: Array = []   # [from, to, off the ground?]
		if is_br.has(ri) or is_tu.has(ri):
			runs = [[0, ns.size() - 1, true]]
		else:
			var start := 0
			for j in range(ns.size() - 1):
				var seg_up: bool = up.call(ns[j]) or up.call(ns[j + 1])
				var nxt_up: bool = j + 2 < ns.size() and (up.call(ns[j + 1]) or up.call(ns[j + 2]))
				if j + 1 == ns.size() - 1 or seg_up != nxt_up:
					runs.append([start, j + 1, seg_up])
					start = j + 1
		for run: Array in runs:
			var part := r.duplicate()
			part["n"] = ns.slice(int(run[0]), int(run[1]) + 1)
			if bool(run[2]):
				var pn: Array = part["n"]
				var g0 := float(ground.call(int(pn[0]))) + float(lift.get(int(pn[0]), 0.0))
				var g1 := float(ground.call(int(pn[pn.size() - 1]))) + float(lift.get(int(pn[pn.size() - 1]), 0.0))
				# a point every few metres, the lift straight between the road's own points,
				# so the profile can be rounded over its crests (a bridge's peak, where two
				# ramps meet, was a sharp crest a car took off from)
				var dn: Array = [pn[0]]
				var lf: Array = [float(lift.get(int(pn[0]), 0.0))]
				var fixed: Array = [true]
				for j in range(pn.size() - 1):
					var a: Vector2 = pos.call(int(pn[j]))
					var b: Vector2 = pos.call(int(pn[j + 1]))
					var la := float(lift.get(int(pn[j]), 0.0))
					var lb := float(lift.get(int(pn[j + 1]), 0.0))
					var parts := maxi(1, ceili(a.distance_to(b) / 6.0))
					for q in range(1, parts):
						dn.append(add_node.call(a.lerp(b, float(q) / parts)))
						lf.append(lerpf(la, lb, float(q) / parts))
						fixed.append(false)
					dn.append(pn[j + 1])
					lf.append(lb)
					# a point other roads meet at keeps its height (theirs is the same)
					fixed.append(j + 1 == pn.size() - 1 or (at.get(int(pn[j + 1]), []) as Array).size() > 1)
				var cum := [0.0]
				for j in range(1, dn.size()):
					cum.append(float(cum[j - 1]) + (pos.call(int(dn[j - 1])) as Vector2).distance_to(pos.call(int(dn[j]))))
				var total: float = cum[cum.size() - 1]
				var yv: Array = []
				var floor_y: Array = []
				var ceil_y: Array = []
				for j in range(dn.size()):
					var gj := float(ground.call(int(dn[j])))
					var y := gj + float(lf[j])
					if part.has("br"):   # a bridge spans: never down into the valley it crosses
						y = maxf(y, lerpf(g0, g1, float(cum[j]) / maxf(total, 0.001)))
					yv.append(y)
					if float(lf[j]) < 0.0:   # dug: never up out of the ground, a tunnel never shallower
						floor_y.append(y - 0.6)
						ceil_y.append(minf(gj, y + (0.0 if part.has("tu") else 0.6)))
					else:
						floor_y.append(gj if not part.has("br") else y - 0.6)
						ceil_y.append(INF)
				for _pass in range(8):
					var nxt := yv.duplicate()
					for j in range(1, dn.size() - 1):
						if not bool(fixed[j]):
							nxt[j] = clampf(0.25 * float(yv[j - 1]) + 0.5 * float(yv[j]) + 0.25 * float(yv[j + 1]), float(floor_y[j]), float(ceil_y[j]))
					yv = nxt
				var ys: Array = []
				for y in yv:
					ys.append(roundi(float(y) / k))
				part["n"] = dn
				part["y"] = ys
				if not part.has("br") and not part.has("tu"):
					var dug_n := 0
					for v in lf:
						dug_n += 1 if float(v) < 0.0 else -1
					part["cu" if dug_n > 0 else "em"] = 1
				decks += 1
			made.append(part)
	data["roads"] = made
	var low := INF
	var short := 0
	var short_at: Array = []
	for n: int in over_roads:
		low = minf(low, float(lift.get(n, 0.0)))
		if float(lift.get(n, 0.0)) < CLEAR_ROAD - 0.5:
			short += 1
			if short_at.size() < 12:
				short_at.append("%s at (%d, %d): %.1f m" % [over_name.get(n, "?"), int(pos.call(n).x), int(pos.call(n).y), float(lift.get(n, 0.0))])
	return {"bridges": is_br.size(), "tunnels": is_tu.size(), "crossings": crossed, "stacked": stacked, "capped": capped, "decks": decks,
		"over_roads": over_roads.size(), "short_of_clear": short, "lowest_over_road": snappedf(low, 0.1), "short_at": short_at, "tunnels_dropped": dropped}
