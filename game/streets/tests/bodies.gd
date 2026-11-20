extends RefCounted
## Bodies, not middles: how far two things' real outlines run into each other, for the tests.
##
## Five of twenty bug fixes in one day were the same mistake -- a long thing judged at its
## middle point: a bus stopped with its middle at the stop line (its front 4 m into the
## junction), autodrive keeping its distance from a bus's middle (inside its back), a car
## waiting crossways seen by its middle only (its nose in the turn, hit), garden walls and
## hedges checked at their middles (their ends on the road). A check written with these
## cannot make it: every vehicle is a box its own length and width, a wall a box its own
## length and thickness, a post a circle.
##
## A box is [centre: Vector2, forward: Vector2 (unit), half width, half length].
## Every *_depth function returns how far the two run into each other (m): > 0 overlapping,
## <= 0 apart.

const SIZE := {"sedan": Vector2(0.9, 2.3), "hatch": Vector2(0.86, 2.0), "suv": Vector2(0.96, 2.35),
	"van": Vector2(0.98, 2.5), "taxi": Vector2(0.9, 2.3), "bus": Vector2(1.25, 5.9), "moto": Vector2(0.3, 0.95),
	"truck": Vector2(1.1, 3.4)}

## a traffic car's box (forward is (sin yaw, cos yaw) in traffic.gd)
static func car_box(c) -> Array:
	var hs: Vector2 = SIZE.get(c.kind, Vector2(0.9, c.len * 0.5))
	return [c.pos, Vector2(sin(c.yaw), cos(c.yaw)), hs.x, maxf(hs.y, c.len * 0.5)]

## the player's car (forward is (cos yaw, sin yaw) in streets.gd: g._fwd())
static func player_box(g) -> Array:
	return [g._pos, g._fwd(), g.CAR_WIDTH * 0.5, g.CAR_LEN * 0.5]

## a wall from a to b, half thickness r, as a box
static func wall_box(a: Vector2, b: Vector2, r: float) -> Array:
	var d := b - a
	var l := d.length()
	return [(a + b) * 0.5, d / l if l > 0.001 else Vector2.RIGHT, r, l * 0.5]

static func front(box: Array) -> Vector2:
	return (box[0] as Vector2) + (box[1] as Vector2) * float(box[3])

static func corners(box: Array) -> PackedVector2Array:
	var c: Vector2 = box[0]
	var f: Vector2 = box[1]
	var s := Vector2(-f.y, f.x)
	var hw: float = box[2]
	var hl: float = box[3]
	return PackedVector2Array([c + f * hl + s * hw, c + f * hl - s * hw, c - f * hl - s * hw, c - f * hl + s * hw])

## two boxes (separating axes): the smallest overlap along any axis
static func box_depth(a: Array, b: Array) -> float:
	var fa: Vector2 = a[1]
	var fb: Vector2 = b[1]
	var d: Vector2 = (b[0] as Vector2) - (a[0] as Vector2)
	var least := INF
	for ax: Vector2 in [fa, Vector2(-fa.y, fa.x), fb, Vector2(-fb.y, fb.x)]:
		var ra := float(a[2]) * absf(Vector2(-fa.y, fa.x).dot(ax)) + float(a[3]) * absf(fa.dot(ax))
		var rb := float(b[2]) * absf(Vector2(-fb.y, fb.x).dot(ax)) + float(b[3]) * absf(fb.dot(ax))
		least = minf(least, ra + rb - absf(d.dot(ax)))
	return least

## a circle (a post, a tree) and a box
static func circle_depth(p: Vector2, r: float, b: Array) -> float:
	var f: Vector2 = b[1]
	var rel := p - (b[0] as Vector2)
	var lx := rel.dot(Vector2(-f.y, f.x))
	var ly := rel.dot(f)
	var hw: float = b[2]
	var hl: float = b[3]
	var qx := clampf(lx, -hw, hw)
	var qy := clampf(ly, -hl, hl)
	if qx == lx and qy == ly:   # its middle inside the box
		return r + minf(hw - absf(lx), hl - absf(ly))
	return r - Vector2(lx - qx, ly - qy).length()

## a polygon (a building's outline) and a box: the deepest of the box's corners and the
## middles of its sides inside the outline (how far in from its nearest edge), or <= 0
static func poly_depth(poly: PackedVector2Array, b: Array) -> float:
	var pts := corners(b)
	var c: Vector2 = b[0]
	var f: Vector2 = b[1]
	pts.append(c + f * float(b[3]))
	pts.append(c - f * float(b[3]))
	var deepest := 0.0
	var n := poly.size()
	for q: Vector2 in pts:
		if not Geometry2D.is_point_in_polygon(q, poly):
			continue
		var best := INF
		for i in range(n):
			best = minf(best, Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % n]).distance_to(q))
		deepest = maxf(deepest, best)
	return deepest

## whatever solid the box runs deepest into, from the game's own lists (buildings you cannot
## drive under, walls, posts): [depth, "building 12" / "wall 3" / "post 40"], depth <= 0 when
## clear. At the ground's level only (a bridge's deck over them is not in them).
static func into_solid(g, b: Array) -> Array:
	var c: Vector2 = b[0]
	var reach := float(b[3]) + 1.0
	var best := [0.0, ""]
	for i: int in g._near(g._bld_hash, c, reach, g.BLD_CELL):
		if g._bld_solid[i] == 0 or not (g._bld_box[i] as Rect2).grow(reach).has_point(c):
			continue
		var d := poly_depth(g._blds[i], b)
		if d > float(best[0]):
			best = [d, "building %d" % i]
	for i: int in g._near(g._wall_hash, c, reach, g.BLD_CELL):
		var a: Vector2 = g._walls[i * 2]
		var e: Vector2 = g._walls[i * 2 + 1]
		if a.distance_to(e) < 0.01:
			continue
		var d := box_depth(wall_box(a, e, g._wall_r[i]), b)
		if d > float(best[0]):
			best = [d, "wall %d" % i]
	for i: int in g._near(g._post_hash, c, reach, g.BLD_CELL):
		var d := circle_depth(g._posts[i], g._post_r[i], b)
		if d > float(best[0]):
			best = [d, "post %d" % i]
	return best
