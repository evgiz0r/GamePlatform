extends RefCounted
## Car bodies (moved out of streets.gd; `g` is the game).
## A car is built from its side profile (CAR_SHAPES) as two lofts with smooth normals. The
## lower body is a rounded cross-section at each of a run of stations from the back to the
## front, between the outline's bottom (the sills, the bumpers' curve) and its top (boot,
## waist, bonnet), narrowing at the corners in plan; the cabin is a second loft from the
## waist to the roof line, the windscreen and rear window its sloped ends, the pillars and the
## roof rail in paint. So the light rolls over the shoulders, the bonnet and the roof instead
## of breaking at flat sides. One indexed surface per car shape: each part (paint, glass,
## trim, tyres, rims, lights, plates) is told apart by its vertex colour's alpha, for
## CAR_SHADER, and the lower body's UV2 carries the wheels' place and size so the shader can
## darken the wheel wells and draw the door seams.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const CAR_CORNER := 0.45             ## the plan's corner radius, front and back (m)

class CarMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, col: Color, t := Vector2.ZERO, t2 := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	## a triangle facing `out` (Godot's front faces are clockwise: the winding is fixed to match)
	func tri(a: int, b: int, d: int, out: Vector3) -> void:
		if (v[b] - v[a]).cross(v[d] - v[a]).dot(out) > 0.0:
			idx.append_array([a, d, b])
		else:
			idx.append_array([a, b, d])

	## a Buf's triangle soup as it is, in one colour (boxes: lights, trim)
	func add_buf(b: Streets.Buf, col: Color, t2 := Vector2.ZERO) -> void:
		for i in range(b.v.size()):
			idx.append(vert(b.v[i], b.n[i], col, b.uv[i] if i < b.uv.size() else Vector2.ZERO, t2))

	func mesh(m: Material) -> ArrayMesh:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_INDEX] = idx
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		am.surface_set_material(0, m)
		return am

## the side outline cut straight down at z: (its bottom, its top)
func _span_at(outline: PackedVector2Array, z: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if a.x == b.x or (a.x - z) * (b.x - z) > 0.0:
			continue
		var y := lerpf(a.y, b.y, (z - a.x) / (b.x - a.x))
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return Vector2(lo, hi) if lo <= hi else Vector2(0.5, 0.5)

## the side outline cut across at height y: its front (or back) end
func _end_at(outline: PackedVector2Array, y: float, front: bool) -> float:
	var best := -INF if front else INF
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if a.y == b.y or (a.y - y) * (b.y - y) > 0.0:
			continue
		var z := lerpf(a.x, b.x, (y - a.y) / (b.y - a.y))
		best = maxf(best, z) if front else minf(best, z)
	return best

## the body's half-width at z: full along the sides, rounding off at the four corners
func _plan_w(z: float, hw: float, hl: float) -> float:
	var d := absf(z) - (hl - CAR_CORNER)
	if d <= 0.0:
		return hw
	return hw - CAR_CORNER + sqrt(maxf(CAR_CORNER * CAR_CORNER - d * d, 0.0))

## how far the rounded corner pulls the front (or back) in at x off the middle
func _plan_in(x: float, hw: float) -> float:
	var d := absf(x) - (hw - CAR_CORNER)
	if d <= 0.0:
		return 0.0
	return CAR_CORNER - sqrt(maxf(CAR_CORNER * CAR_CORNER - d * d, 0.0))

## A loft through rings of points (one per station, the same count each), normals smoothed
## over the grid and turned away from each station's middle; `part.call(i, j)` colours the
## quad from station i, ring point j. A vertex is shared by the quads of one part only, so
## glass and paint keep their own edges.
func _loft(cm: CarMesh, rings: Array, mids: PackedVector3Array, closed: bool, part: Callable, t2: Vector2,
		glass_t2 := Vector2.ZERO) -> void:
	var count := rings.size()
	var m: int = (rings[0] as PackedVector3Array).size()
	var nrm: Array = []
	for i in range(count):
		var ring: PackedVector3Array = rings[i]
		var prev: PackedVector3Array = rings[maxi(i - 1, 0)]
		var next: PackedVector3Array = rings[mini(i + 1, count - 1)]
		var nr := PackedVector3Array()
		for j in range(m):
			var jp := (j + 1) % m if closed else mini(j + 1, m - 1)
			var jm := (j - 1 + m) % m if closed else maxi(j - 1, 0)
			var nn := (ring[jp] - ring[jm]).cross(next[j] - prev[j])
			if nn.length_squared() < 1e-12:
				nn = ring[j] - mids[i]
			nn = nn.normalized()
			if nn.dot(ring[j] - mids[i]) < 0.0:
				nn = -nn
			nr.append(nn)
		nrm.append(nr)
	var made := {}
	for i in range(count - 1):
		for j in range(m if closed else m - 1):
			var j1 := (j + 1) % m
			var col: Color = part.call(i, j)
			var pid := int(round(col.a * 100.0))
			var q: Array = []
			for ij: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j1), Vector2i(i, j1)]:
				var key := (ij.x * 1000 + ij.y) * 1000 + pid
				if not made.has(key):
					made[key] = cm.vert((rings[ij.x] as PackedVector3Array)[ij.y], (nrm[ij.x] as PackedVector3Array)[ij.y], col, Vector2.ZERO,
						glass_t2 if pid == 75 else t2)
				q.append(made[key])
			var out: Vector3 = ((rings[i] as PackedVector3Array)[j] + (rings[i + 1] as PackedVector3Array)[j1]) * 0.5 - (mids[i] + mids[i + 1]) * 0.5
			cm.tri(q[0], q[1], q[2], out)
			cm.tri(q[0], q[2], q[3], out)

## A car body of a CAR_SHAPES kind, facing +Z, its wheels on y = 0. `extras`: the wheels,
## lights and number plates too (the player's car has its own, which turn and light up).
func _car_body(kind: String, extras: bool) -> CarMesh:
	var shape: Array = Streets.CAR_SHAPES[kind]
	var low := PackedVector2Array(shape[0])
	var cab: Array = shape[1]
	var hw: float = shape[2]
	var hl: float = shape[3]
	var wz: float = shape[4]
	var wr: float = shape[5]
	var lift := 0.08 if kind in ["suv", "van"] else (0.05 if kind == "mpv" else (0.12 if kind == "truck" else 0.0))
	var cm := CarMesh.new()
	var paint := Color(1, 1, 1, 1.0)
	var glass := Color(g._tone["carglass"], 0.75)
	var trim := Color(g._tone["cartrim"], 0.5)
	var wheels := Vector2(wz, wr)
	var zmin := INF
	var zmax := -INF
	for p in low:
		zmin = minf(zmin, p.x)
		zmax = maxf(zmax, p.x)
	# ---- the lower body: 16 stations, closer together toward the ends where it curves
	var rings: Array = []
	var mids := PackedVector3Array()
	var stations := 16
	for i in range(stations):
		var z := lerpf(zmin + 0.004, zmax - 0.004, 0.5 - 0.5 * cos(PI * i / (stations - 1)))
		var sp := _span_at(low, z)
		var yb := sp.x
		var yt := sp.y
		var h := maxf(yt - yb, 0.001)
		var w := _plan_w(z, hw, hl)
		var half: Array = [Vector2(0.0, yb), Vector2(w - 0.12, yb), Vector2(w - 0.03, yb + minf(0.07, h * 0.25)),
			Vector2(w, yb + h * 0.45), Vector2(w - 0.025, yt - minf(0.09, h * 0.25)),
			Vector2(w - 0.09, yt - minf(0.012, h * 0.05)), Vector2(w * 0.55, yt + 0.025), Vector2(0.0, yt + 0.035)]
		var ring := PackedVector3Array()
		for p: Vector2 in half:
			ring.append(Vector3(p.x, p.y, z))
		for k in range(half.size() - 2, 0, -1):
			ring.append(Vector3(-(half[k] as Vector2).x, (half[k] as Vector2).y, z))
		rings.append(ring)
		mids.append(Vector3(0.0, (yb + yt) * 0.5, z))
	_loft(cm, rings, mids, true, func(_i: int, _j: int) -> Color: return paint, wheels)
	# ---- the cabin, from the waist to the roof line
	var c0: Vector2 = cab[0]   # windscreen foot
	var c1: Vector2 = cab[1]   # windscreen top
	var c2: Vector2 = cab[2]   # rear top
	var c3: Vector2 = cab[3]   # rear foot
	var pillars: Array = [-0.26] if kind in ["sedan", "hatch"] else ([-0.32] if kind == "mini" else [-0.2, -1.25])
	var zs: Array = []
	for k in range(9):
		zs.append(lerpf(c3.x, c0.x, k / 8.0))
	zs.append_array([c1.x, c2.x])
	for pz: float in pillars:
		zs.append_array([pz - 0.06, pz + 0.06])
	var back_pillar := c2.x + 0.05 if kind in ["sedan", "hatch", "mini"] else c3.x + 0.18
	zs.append(back_pillar)
	zs.sort()
	var cz: Array = []
	for z: float in zs:
		if cz.is_empty() or z - float(cz[-1]) > 0.01:
			cz.append(clampf(z, c3.x, c0.x))
	var roof := func(z: float) -> float:
		if z >= c1.x:
			return lerpf(c1.y, c0.y, inverse_lerp(c1.x, c0.x, z))
		if z >= c2.x:
			return lerpf(c2.y, c1.y, inverse_lerp(c2.x, c1.x, z))
		return lerpf(c3.y, c2.y, inverse_lerp(c3.x, c2.x, z))
	rings = []
	mids = PackedVector3Array()
	for z: float in cz:
		var yb := _span_at(low, z).y
		var top := maxf(float(roof.call(z)), yb + 0.004)
		var w := _plan_w(z, hw, hl)
		var wb := w - 0.05
		var wt := w - 0.27
		var gh: Array = [Vector2(wb, yb - 0.01), Vector2(wt, maxf(yb, top - 0.05)), Vector2(wt - 0.07, top), Vector2(0.0, top + 0.02)]
		var ring := PackedVector3Array()
		for p: Vector2 in gh:
			ring.append(Vector3(p.x, p.y, z))
		for k in range(gh.size() - 2, -1, -1):
			ring.append(Vector3(-(gh[k] as Vector2).x, (gh[k] as Vector2).y, z))
		rings.append(ring)
		mids.append(Vector3(0.0, yb - 0.3, z))
	var cab_part := func(i: int, j: int) -> Color:
		var zc := (float(cz[i]) + float(cz[i + 1])) * 0.5
		if j == 1 or j == 4:
			return paint                      # the roof rail, the A- and C-pillars' edges
		if j == 2 or j == 3:
			return glass if (zc > c1.x or zc < c2.x) else paint   # windscreen, rear window / roof
		if zc < back_pillar:
			return paint
		for pz: float in pillars:
			if absf(zc - pz) < 0.06:
				return paint                  # the B-pillar (an SUV's and a van's C too)
		return glass
	# the glass carries where the front seats are -- just behind the windscreen's foot, the
	# cushion a little under the waist -- for the shader's people
	var seats := Vector2(c0.x - (0.75 if kind == "truck" else (1.3 if kind in ["suv", "van", "mpv"] else 1.15)), _span_at(low, c0.x).y - 0.45)
	_loft(cm, rings, mids, false, cab_part, Vector2.ZERO, seats)
	# ---- trim: bumper lips, the grille, mirrors, door handles
	var tb := Streets.Buf.new()
	var zf := _end_at(low, 0.4 + lift, true)
	var zr := _end_at(low, 0.4 + lift, false)
	g._box(tb, Vector3(0, 0.32 + lift, zf - 0.07), Vector3((hw - 0.2) * 2.0, 0.1, 0.16))
	g._box(tb, Vector3(0, 0.32 + lift, zr + 0.07), Vector3((hw - 0.2) * 2.0, 0.1, 0.16))
	var gy := 0.58 + lift
	g._box(tb, Vector3(0, gy, _end_at(low, gy, true) - 0.025), Vector3(0.72, 0.13, 0.06))
	for sx: float in [-1.0, 1.0]:
		for hz: float in ([c0.x - 0.42] if kind == "truck" else [c0.x - 0.42, float(pillars[0]) - 0.4]):
			var hy := _span_at(low, hz).y - 0.11
			g._box(tb, Vector3(sx * (_plan_w(hz, hw, hl) + 0.004), hy, hz), Vector3(0.02, 0.035, 0.15))
	cm.add_buf(tb, trim)
	var mb := Streets.Buf.new()
	for sx: float in [-1.0, 1.0]:
		g._box(mb, Vector3(sx * (hw + 0.07), c0.y + 0.08, c0.x - 0.14), Vector3(0.15, 0.1, 0.08))
	cm.add_buf(mb, paint)
	if not extras:
		return cm
	# ---- wiper arms at the windscreen's foot, a shark-fin aerial at the roof's back, roof
	# rails on an SUV and an estate
	var fit := Streets.Buf.new()
	var ws := func(y: float) -> float:   # the windscreen's surface at height y
		return lerpf(c0.x, c1.x, clampf((y - c0.y) / maxf(c1.y - c0.y, 0.01), 0.0, 1.0))
	if kind != "truck":
		for sx: float in [-1.0, 1.0]:
			var wy := c0.y + 0.04
			g._box(fit, Vector3(sx * 0.27 - 0.08, wy, float(ws.call(wy)) + 0.02), Vector3(0.5, 0.018, 0.022))
		if kind in ["sedan", "hatch", "mini", "wagon", "suv"]:
			g._box(fit, Vector3(0, c2.y + 0.04, c2.x + 0.28), Vector3(0.05, 0.07, 0.17))
		if kind in ["suv", "wagon"]:
			for sx: float in [-1.0, 1.0]:
				g._box(fit, Vector3(sx * (hw - 0.36), maxf(c1.y, c2.y) + 0.06, (c1.x + c2.x) * 0.5), Vector3(0.035, 0.035, absf(c1.x - c2.x) + 0.3))
				for foot: float in [c1.x - 0.05, c2.x + 0.05]:
					g._box(fit, Vector3(sx * (hw - 0.36), maxf(c1.y, c2.y) + 0.03, foot), Vector3(0.05, 0.05, 0.08))
	cm.add_buf(fit, trim)
	if kind in ["sedan", "hatch", "mini", "wagon", "suv"]:
		# a learner's roof sign, a new driver's in the back window, a parking permit on the
		# windscreen: kept only on the cars the shader picks (vertex())
		var top := maxf(c1.y, c2.y)
		var lz := (c1.x + c2.x) * 0.5
		var lb := Streets.Buf.new()
		g._box(lb, Vector3(0, top + 0.12, lz), Vector3(0.4, 0.22, 0.07))
		cm.add_buf(lb, Color(g._real_col("red"), 0.52), Vector2(0.0, top + 0.12))
		var ry := lerpf(c3.y, c2.y, 0.32)
		var rz := lerpf(c3.x, c2.x, 0.32) - 0.04
		var nb := Streets.Buf.new()
		g._box(nb, Vector3(0.36, ry, rz), Vector3(0.27, 0.13, 0.01))
		cm.add_buf(nb, Color(1, 1, 1, 0.54), Vector2(0.36, ry))
		var py := c0.y + 0.09
		var pb := Streets.Buf.new()
		g._box(pb, Vector3(-(hw - 0.42), py, float(ws.call(py)) + 0.025), Vector3(0.09, 0.07, 0.006))
		cm.add_buf(pb, Color(1, 1, 1, 0.56), Vector2(-(hw - 0.42), py))
	# ---- wheels: tyres, their sidewalls, five-spoke rims (just proud of the body, in the
	# dark wells the shader paints round them)
	var tyre := Color(g._tone["tyre"], 0.3)
	var rim := Color(g._tone["rim"], 0.4)
	for wzs: float in [wz, -wz]:
		for sx: float in [-1.0, 1.0]:
			# (UV2: the wheel's middle, which the shader turns the front ones about as it steers)
			_wheel(cm, Vector3(sx * (hw - 0.09), wr, wzs), wr, sx, tyre, rim, 0.11, false, Vector2(sx * (hw - 0.09), wzs))
	# ---- lights: panels laid on the body's front and back, following its rounded corners
	# (UV2 x 1: drawn as a car's lamps, the indicators in them -- CAR_SHADER)
	var hy := 0.68 + lift
	var ty := _span_at(low, zmin + 0.12).y - 0.15
	for sx: float in [-1.0, 1.0]:
		_lamp(cm, low, hw, sx * (hw - 0.3), hy, 0.36, 0.12, true, Color(g._tone["tank"], 0.1), Vector2(1, 0))
		_lamp(cm, low, hw, sx * (hw - 0.27), ty, 0.32, 0.14, false, Color(g._tone["tank"], 0.0), Vector2(1, 0))
	# the indicators' repeaters on the door mirrors, and the third brake light at the top of
	# the rear window (UV2 x 2)
	var rb := Streets.Buf.new()
	for sx: float in [-1.0, 1.0]:
		g._box(rb, Vector3(sx * (hw + 0.115), c0.y + 0.055, c0.x - 0.098), Vector3(0.05, 0.016, 0.006))
	cm.add_buf(rb, Color(g._tone["tank"], 0.1), Vector2(2, 0))
	if kind != "truck":
		var by := c2.y - 0.05
		var bz := lerpf(c3.x, c2.x, clampf((by - 0.02 - c3.y) / maxf(c2.y - c3.y, 0.01), 0.0, 1.0)) - 0.015
		var bb := Streets.Buf.new()
		g._box(bb, Vector3(0, by, bz), Vector3(0.34, 0.03, 0.012))
		cm.add_buf(bb, Color(g._tone["tank"], 0.0), Vector2(2, 0))
	var plate := Color(Palette.col("warn") if String(g._place.get("look", "")) == "med" else Palette.col("ink"), 0.65)
	for front: bool in [true, false]:
		var py := (0.45 if front else 0.6) + lift
		var pz := _end_at(low, py, front) + (0.012 if front else -0.012)
		var s := 1.0 if front else -1.0
		var a := cm.vert(Vector3(-0.26 * s, py - 0.06, pz), Vector3(0, 0, s), plate, Vector2(0, 1))
		var b := cm.vert(Vector3(0.26 * s, py - 0.06, pz), Vector3(0, 0, s), plate, Vector2(1, 1))
		var d := cm.vert(Vector3(0.26 * s, py + 0.06, pz), Vector3(0, 0, s), plate, Vector2(1, 0))
		var e := cm.vert(Vector3(-0.26 * s, py + 0.06, pz), Vector3(0, 0, s), plate, Vector2(0, 0))
		cm.tri(a, b, d, Vector3(0, 0, s))
		cm.tri(a, d, e, Vector3(0, 0, s))
	return cm

## a light panel w x h centred at (cx, cy) on the body's front (or back), each corner set on
## the rounded surface (a hair proud of it), so it bends round the corner as real ones do
func _lamp(cm: CarMesh, low: PackedVector2Array, hw: float, cx: float, cy: float, w: float, h: float, front: bool, col: Color,
		t2 := Vector2.ZERO) -> void:
	var s := 1.0 if front else -1.0
	var grid: Array = []
	# (2.5 cm proud of the body, five points across to follow its curve: at 8 mm and three
	# points the body bulged through between them and the two fought for the pixels, the lamp
	# a speckle of red on white -- worst on a phone's coarser depth buffer)
	for row in range(2):
		var y := cy + (float(row) - 0.5) * h
		var line: Array = []
		for k in range(5):
			var x := cx + (float(k) - 2.0) * w * 0.25
			var z := _end_at(low, y, front) - s * (_plan_in(x, hw) - 0.025)
			var nrm := Vector3(x / hw * 0.7, 0.1, s).normalized()
			# (UV for CAR_SHADER's lamps: x 0 at the inner end to 1 at the outer, y 0 low to 1 high)
			var u := float(k) / 4.0 if cx > 0.0 else 1.0 - float(k) / 4.0
			line.append(cm.vert(Vector3(x, y, z), nrm, col, Vector2(u, float(row)), t2))
		grid.append(line)
	var out := Vector3(cx / hw * 0.7, 0.1, s)
	for k in range(4):
		cm.tri(grid[0][k], grid[0][k + 1], grid[1][k + 1], out)
		cm.tri(grid[0][k], grid[1][k + 1], grid[1][k], out)

## a flat lamp w x h at c facing +Z (front) or -Z, with a car lamp's UV (x 0 inner to 1
## outer, y 0 low to 1 high) and UV2 x 1: drawn as a car's lamps, indicators and all (a bus's,
## a truck's box's)
func _lamp_quad(cm: CarMesh, c: Vector3, w: float, h: float, front: bool, col: Color) -> void:
	var s := 1.0 if front else -1.0
	var out := Vector3(0, 0, s)
	var q: Array = []
	for corner: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var u := 0.5 + corner.x * signf(c.x if c.x != 0.0 else 1.0)
		q.append(cm.vert(c + Vector3(corner.x * w, corner.y * h, 0.0), out, col, Vector2(u, corner.y + 0.5), Vector2(1, 0)))
	cm.tri(q[0], q[1], q[2], out)
	cm.tri(q[0], q[2], q[3], out)

## a tyre round the X axis at c, its outer side facing `side` (+1/-1): tread, sidewall, and the
## rim (UV: the disc's own -1..1, for the shader's spokes)
func _wheel(cm: CarMesh, c: Vector3, r: float, side: float, tyre: Color, rim: Color, half := 0.11,
		both := false, t2 := Vector2.ZERO) -> void:
	var seg := 10
	var rr := r * 0.62
	var out := Vector3(side, 0, 0)
	var tread: Array = []
	for k in range(seg + 1):
		var a := TAU * k / seg
		var dir := Vector3(0, cos(a), sin(a))
		tread.append([cm.vert(c + dir * r - out * half, dir, tyre, Vector2.ZERO, t2), cm.vert(c + dir * r + out * half, dir, tyre, Vector2.ZERO, t2),
			cm.vert(c + dir * r + out * half, out, tyre, Vector2.ZERO, t2), cm.vert(c + dir * rr + out * half, out, tyre, Vector2.ZERO, t2)])
	for k in range(seg):
		var a0: Array = tread[k]
		var a1: Array = tread[k + 1]
		var dir := Vector3(0, cos(TAU * (k + 0.5) / seg), sin(TAU * (k + 0.5) / seg))
		cm.tri(a0[0], a1[0], a1[1], dir)
		cm.tri(a0[0], a1[1], a0[1], dir)
		cm.tri(a0[2], a1[2], a1[3], out)
		cm.tri(a0[2], a1[3], a0[3], out)
	for o: Vector3 in ([out, -out] if both else [out]):
		var hub := cm.vert(c + o * (half - 0.004), o, rim, Vector2.ZERO, t2)
		var ring: Array = []
		for k in range(seg + 1):
			var a := TAU * k / seg
			ring.append(cm.vert(c + Vector3(0, cos(a), sin(a)) * rr + o * (half - 0.004), o, rim, Vector2(cos(a), sin(a)), t2))
		for k in range(seg):
			cm.tri(hub, ring[k], ring[k + 1], o)
		if both and o == -out:   # the far side's sidewall too (a scooter is seen from both)
			for k in range(seg):
				var a0 := TAU * k / seg
				var a1 := TAU * (k + 1) / seg
				var p0 := cm.vert(c + Vector3(0, cos(a0), sin(a0)) * r + o * half, o, tyre)
				var p1 := cm.vert(c + Vector3(0, cos(a1), sin(a1)) * r + o * half, o, tyre)
				var q0 := cm.vert(c + Vector3(0, cos(a0), sin(a0)) * rr + o * half, o, tyre)
				var q1 := cm.vert(c + Vector3(0, cos(a1), sin(a1)) * rr + o * half, o, tyre)
				cm.tri(p0, p1, q1, o)
				cm.tri(p0, q1, q0, o)

## A city bus, 11.8 m: a rounded box -- the body in its colour below and above a band of
## windows all round, pillars between them, a big windscreen with the lit route sign over
## it, glazed doors on the kerb side (the car's -X), the air-conditioning box on the roof,
## the wheels in dark wells. One loft like the cars' (see _car_body), its ends flat faces
## in bands. Faces +Z.
func _bus_mesh() -> ArrayMesh:
	var cm := CarMesh.new()
	var hw := 1.25
	var hl := 5.9
	var rc := 0.3                       # the plan's corner radius
	var paint := Color(1, 1, 1, 1.0)
	var glass := Color(g._tone["carglass"], 0.75)
	var trim := Color(g._tone["cartrim"], 0.5)
	var wheels := Vector2(3.0, 0.5)     # (both axles' |z|, wheel radius): the wells
	var ys: Array = [0.32, 0.42, 1.0, 2.55, 2.9, 3.05]   # bottom, sill, window foot, top, roof edge, roof
	var pillars: Array = []
	for i in range(9):
		pillars.append(-hl + 0.7 + i * 1.32)
	var doors: Array = [Vector2(3.65, 4.85), Vector2(-0.9, 0.35)]
	var zs: Array = []
	for d: float in [0.0, 0.04, 0.1, 0.18, 0.3]:
		zs.append_array([-hl + d, hl - d])
	for pz: float in pillars:
		zs.append_array([pz - 0.06, pz + 0.06])
	for dz: Vector2 in doors:
		zs.append_array([dz.x, dz.y])
	zs.append_array([-hl + 0.6, hl - 0.6])
	zs.sort()
	var st: Array = []
	for z: float in zs:
		if st.is_empty() or z - float(st[-1]) > 0.01:
			st.append(z)
	var rings: Array = []
	var mids := PackedVector3Array()
	for z: float in st:
		var d := absf(z) - (hl - rc)
		var w := hw if d <= 0.0 else hw - rc + sqrt(maxf(rc * rc - d * d, 0.0))
		var half: Array = [Vector2(0.0, ys[0]), Vector2(w - 0.08, ys[0]), Vector2(w, ys[1]), Vector2(w, ys[2]),
			Vector2(w, ys[3]), Vector2(w, ys[4]), Vector2(w - 0.15, ys[5]), Vector2(0.0, float(ys[5]) + 0.02)]
		var ring := PackedVector3Array()
		for p: Vector2 in half:
			ring.append(Vector3(p.x, p.y, z))
		for k in range(half.size() - 2, 0, -1):
			ring.append(Vector3(-(half[k] as Vector2).x, (half[k] as Vector2).y, z))
		rings.append(ring)
		mids.append(Vector3(0.0, 1.6, z))
	var part := func(i: int, j: int) -> Color:
		var zc := (float(st[i]) + float(st[i + 1])) * 0.5
		var kerb := j >= 7
		var band := j if j < 7 else 13 - j   # the same band on either side
		for dz: Vector2 in doors:
			if kerb and zc > dz.x and zc < dz.y and (band == 2 or band == 3):
				return glass                  # the doors, glazed top to bottom
		if band == 3:
			if absf(zc) > hl - 0.45:
				return paint                  # the corners
			for pz: float in pillars:
				if absf(zc - pz) < 0.06:
					return paint
			return glass
		return trim if band <= 1 else paint
	_loft(cm, rings, mids, true, part, wheels)
	# the two ends: flat faces in bands -- bumper, panel, windscreen (rear window), route sign
	for front: bool in [true, false]:
		var z := hl if front else -hl
		var s := 1.0 if front else -1.0
		var w := hw - rc
		var bands: Array = [[ys[0], ys[1], trim], [ys[1], ys[2], paint], [ys[2], ys[3], glass],
			[ys[3], ys[4], Color(Palette.col("warn"), 0.1) if front else paint], [ys[4], ys[5], paint]]
		for b: Array in bands:
			var y0: float = b[0]
			var y1: float = b[1]
			var w0 := w - (0.08 if y0 <= float(ys[0]) else 0.0)
			var w1 := w - (0.15 if y1 >= float(ys[5]) else 0.0)
			var a := cm.vert(Vector3(-w0, y0, z), Vector3(0, 0, s), b[2])
			var bb := cm.vert(Vector3(w0, y0, z), Vector3(0, 0, s), b[2])
			var c := cm.vert(Vector3(w1, y1, z), Vector3(0, 0, s), b[2])
			var e := cm.vert(Vector3(-w1, y1, z), Vector3(0, 0, s), b[2])
			cm.tri(a, bb, c, Vector3(0, 0, s))
			cm.tri(a, c, e, Vector3(0, 0, s))
	# the roof's air conditioning, the mirrors on their arms
	var tb := Streets.Buf.new()
	g._box(tb, Vector3(0, 3.2, -1.2), Vector3(1.6, 0.26, 2.8))
	for sx: float in [-1.0, 1.0]:
		g._box(tb, Vector3(sx * (hw + 0.12), 2.15, hl - 0.25), Vector3(0.06, 0.4, 0.1))
	cm.add_buf(tb, trim)
	# lights low on the front, tall ones at the back (a car's lamps: the indicators in them),
	# a repeater on each side behind the front door
	var lamps := Streets.Buf.new()
	var tails := Streets.Buf.new()
	var reps := Streets.Buf.new()
	for sx: float in [-1.0, 1.0]:
		g._box(lamps, Vector3(sx * (hw - 0.45), 0.62, hl + 0.004), Vector3(0.36, 0.14, 0.01))
		g._box(tails, Vector3(sx * (hw - 0.22), 1.0, -hl - 0.004), Vector3(0.2, 0.42, 0.01))
		_lamp_quad(cm, Vector3(sx * (hw - 0.45), 0.62, hl + 0.012), 0.36, 0.14, true, Color(g._tone["tank"], 0.1))
		_lamp_quad(cm, Vector3(sx * (hw - 0.22), 1.0, -hl - 0.012), 0.2, 0.42, false, Color(g._tone["tank"], 0.0))
		g._box(reps, Vector3(sx * (hw + 0.012), 1.0, hl - 2.2), Vector3(0.02, 0.07, 0.16))
	cm.add_buf(lamps, Color(g._tone["cartrim"], 0.5))
	cm.add_buf(tails, Color(g._tone["cartrim"], 0.5))
	cm.add_buf(reps, Color(g._tone["tank"], 0.1), Vector2(2, 0))
	for wz: float in [wheels.x, -wheels.x]:
		for sx: float in [-1.0, 1.0]:
			_wheel(cm, Vector3(sx * (hw - 0.2), wheels.y, wz), wheels.y, sx, Color(g._tone["tyre"], 0.3), Color(g._tone["rim"], 0.4), 0.16)
	var am := cm.mesh(g._car_material())
	am.custom_aabb = am.get_aabb().grow(0.1)
	g._car_meshes["bus"] = am
	return am

## A scooter and its rider, 1.9 m, made of rounded pieces: two small spoked wheels, the
## body and the leg shield in its colour, a dark seat and floorboard, the handlebars, a lamp
## at each end; the rider in a dark jacket and trousers, arms out to the bars, a helmet
## with its visor. Faces +Z. Without `rider`: one parked on the pavement.
func _moto_mesh(rider := true) -> ArrayMesh:
	var cm := CarMesh.new()
	var paint := Color(1, 1, 1, 1.0)
	var trim := Color(g._tone["cartrim"], 0.5)
	var jacket := Color(g._tone["cartrim"].lerp(g._tone["carglass"], 0.3), 0.5)
	var legs := Color(g._tone["cartrim"].darkened(0.2), 0.5)
	var helmet := Color(g._tone["mark"], 0.5)
	for wz: float in [0.62, -0.62]:
		_wheel(cm, Vector3(0, 0.25, wz), 0.25, 1.0, Color(g._tone["tyre"], 0.3), Color(g._tone["rim"], 0.4), 0.05, true)
	_blobm(cm, Vector3(0, 0.55, -0.32), Vector3(0.2, 0.2, 0.5), paint)            # the body over the back wheel
	_blobm(cm, Vector3(0, 0.62, 0.42), Vector3(0.22, 0.32, 0.07), paint)          # the leg shield
	_blobm(cm, Vector3(0, 0.44, 0.63), Vector3(0.08, 0.05, 0.2), paint)           # the front mudguard
	_blobm(cm, Vector3(0, 0.77, -0.3), Vector3(0.16, 0.06, 0.38), trim)           # the seat
	var tb := Streets.Buf.new()
	g._box(tb, Vector3(0, 0.36, 0.08), Vector3(0.32, 0.06, 0.52))                   # the floorboard
	g._box(tb, Vector3(0, 0.86, 0.5), Vector3(0.05, 0.46, 0.05))                    # the column
	g._box(tb, Vector3(0, 1.08, 0.48), Vector3(0.62, 0.04, 0.04))                   # the bars
	cm.add_buf(tb, trim)
	_blobm(cm, Vector3(0, 0.98, 0.57), Vector3(0.07, 0.06, 0.03), Color(g._tone["tank"], 0.1), 8, 4)
	_blobm(cm, Vector3(0, 0.62, -0.84), Vector3(0.07, 0.04, 0.03), Color(g._tone["tank"], 0.0), 8, 4)
	# indicators either side, front and back (CAR_SHADER's repeaters: amber, lit as it blinks)
	var ib := Streets.Buf.new()
	for sx: float in [-1.0, 1.0]:
		g._box(ib, Vector3(sx * 0.17, 0.95, 0.56), Vector3(0.05, 0.035, 0.035))
		g._box(ib, Vector3(sx * 0.13, 0.64, -0.82), Vector3(0.05, 0.035, 0.035))
	cm.add_buf(ib, Color(g._tone["tank"], 0.1), Vector2(2, 0))
	# the rider, leaning a little to the bars: a torso, arms bent at the elbow, knees up
	if rider:
		_moto_rider(cm, jacket, legs, helmet)
	var am := cm.mesh(g._car_material())
	am.custom_aabb = am.get_aabb().grow(0.1)
	g._car_meshes["moto" if rider else "moto_parked"] = am
	return am

func _moto_rider(cm: CarMesh, jacket: Color, legs: Color, helmet: Color) -> void:
	_limb(cm, Vector3(0, 0.98, -0.22), Vector3(0, 1.5, -0.06), 0.16, jacket)
	for sx: float in [-1.0, 1.0]:
		var shoulder := Vector3(sx * 0.18, 1.42, -0.07)
		var elbow := Vector3(sx * 0.26, 1.2, 0.17)
		var hand := Vector3(sx * 0.3, 1.1, 0.45)
		_limb(cm, shoulder, elbow, 0.06, jacket)
		_limb(cm, elbow, hand, 0.05, jacket)
		var hip := Vector3(sx * 0.11, 0.9, -0.2)
		var knee := Vector3(sx * 0.15, 0.93, 0.2)
		var foot := Vector3(sx * 0.14, 0.42, 0.2)
		_limb(cm, hip, knee, 0.08, legs)
		_limb(cm, knee, foot, 0.065, legs)
	_blobm(cm, Vector3(0, 1.66, 0.0), Vector3(0.13, 0.14, 0.14), helmet)          # the helmet
	_blobm(cm, Vector3(0, 1.64, 0.1), Vector3(0.1, 0.055, 0.06), Color(g._tone["carglass"], 0.75), 8, 4)   # its visor

## A delivery truck, 6.8 m: a van's cab (CAR_SHAPES "truck", built like the cars) with a
## tall white box behind it, its back doors' seam and hinges. Faces +Z.
func _truck_mesh() -> ArrayMesh:
	var cm := _car_body("truck", true)
	var box := Streets.Buf.new()
	g._box(box, Vector3(0, 2.13, -0.98), Vector3(2.3, 2.36, 4.8))
	cm.add_buf(box, Color(g._tone["tank"], 0.5))
	var seam := Streets.Buf.new()
	g._box(seam, Vector3(0, 2.13, -3.385), Vector3(0.03, 2.2, 0.02))
	for sx: float in [-1.0, 1.0]:
		for hy: float in [1.3, 2.9]:
			g._box(seam, Vector3(sx * 1.05, hy, -3.385), Vector3(0.1, 0.06, 0.02))
	cm.add_buf(seam, Color(g._tone["cartrim"], 0.5))
	# its tail lights on the box's back (the cab's own are behind the box), a car's lamps
	for sx: float in [-1.0, 1.0]:
		_lamp_quad(cm, Vector3(sx * 0.9, 0.82, -3.4), 0.34, 0.16, false, Color(g._tone["tank"], 0.0))
	var am := cm.mesh(g._car_material())
	am.custom_aabb = am.get_aabb().grow(0.1)
	g._car_meshes["truck"] = am
	return am

## a limb from a to b: a long rounded piece, `rad` thick
func _limb(cm: CarMesh, a: Vector3, b: Vector3, rad: float, col: Color) -> void:
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up)
	_blobm(cm, (a + b) * 0.5, Vector3(rad, a.distance_to(b) * 0.5 + rad * 0.6, rad), col, 8, 5, Basis(side, up, fwd))

## a rounded blob (an ellipsoid at c with radii r, turned by `turn`), smooth, in one colour
func _blobm(cm: CarMesh, c: Vector3, r: Vector3, col: Color, seg := 10, rings := 6, turn := Basis()) -> void:
	var first := cm.v.size()
	for i in range(rings + 1):
		var th := PI * i / rings
		for j in range(seg + 1):
			var ph := TAU * j / seg
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			cm.vert(c + turn * (u * r), (turn * (u / r)).normalized(), col)
	for i in range(rings):
		for j in range(seg):
			var a := first + i * (seg + 1) + j
			var b := a + seg + 1
			var out: Vector3 = (cm.v[a] + cm.v[b + 1]) * 0.5 - c
			cm.tri(a, b, b + 1, out)
			cm.tri(a, b + 1, a + 1, out)
