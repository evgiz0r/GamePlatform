extends RefCounted
## Parks and pitches (moved out of streets.gd; `g` is the game).
## Along the paths through a park: benches facing the path, low park lamps (lit at night,
## with their pools). In a big enough park, a playground: a slide tower, swings and a
## sandpit on a soft floor. On a sports pitch: its lines, and goals or basketball hoops.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game


var _parks: Array = []               ## [outline, box] of the parks and lawns big enough for benches
var _park_hash := {}

func _parks_setup() -> void:
	for kind: String in ["park", "grass"]:
		for ring: PackedVector2Array in g._area_rings.get(kind, []):
			if g._area(ring) >= 400.0:
				g._hash_add(_park_hash, g._bld_box_of(ring), 60.0, _parks.size())
				_parks.append([ring, g._bld_box_of(ring)])

func _build_parks() -> void:
	var parks := _parks
	var park_hash := _park_hash
	var benches: Array = []
	var posts: Array = []
	var globes: Array = []
	for ri: int in g._tile_roads.get(g._tile, []):
		var r: Dictionary = g._roads[ri]
		if r["drive"]:
			continue
		if g._over():
			await g._pause()
		var flip := posmod(ri, 2) == 0
		var pts: PackedVector2Array = r["pts"]
		var hw: float = float(r["w"]) * 0.5
		var s_bench := 6.0
		var s_lamp := 12.0
		for j in range(pts.size() - 1):
			var a := pts[j]
			var b := pts[j + 1]
			var L := a.distance_to(b)
			if L < 0.5:
				continue
			var d := (b - a) / L
			var side := Vector2(-d.y, d.x)
			var mid := (a + b) * 0.5
			var inside := false
			for pi: int in g._near(park_hash, mid, 1.0, 60.0):
				var pk: Array = parks[pi]
				if (pk[1] as Rect2).grow(2.0).has_point(mid) and Geometry2D.is_point_in_polygon(mid, pk[0]):
					inside = true
					break
			if not inside:
				s_bench -= L
				s_lamp -= L
				continue
			while s_bench < L:
				flip = not flip
				var out := side * (1.0 if flip else -1.0)
				var q := a + d * s_bench + out * (hw + 0.75)
				if g._mine(q) and g._push_out(q, 0.9, true) == Vector2.ZERO and g._off_road(q, 1.0):
					benches.append(Transform3D(Basis(Vector3.UP, atan2(-out.x, -out.y)), g._g3(q, 0.0)))
					g._bench_spots.append([q, -out])   # (where someone sits: _place_sitters)
					g._add_post(q, 0.5)
				s_bench += 19.0
			s_bench -= L
			while s_lamp < L:
				var q := a + d * s_lamp - side * (hw + 0.6) * (1.0 if flip else -1.0)
				if g._mine(q) and g._push_out(q, 0.5, true) == Vector2.ZERO and g._off_road(q, 1.0):
					var gy := g._h(q)
					posts.append(Transform3D(Basis(), Vector3(q.x, gy + 1.8, q.y)))
					globes.append(Transform3D(Basis(), Vector3(q.x, gy + 3.75, q.y)))
					g._pool_at.append(Vector3(q.x, q.y, 4.5))
					g._add_post(q, 0.1)
				s_lamp += 27.0
			s_lamp -= L
	var bench := g._cached("bench", func() -> Mesh:
		# the bench made with Blender (tools/blender/recipes/bench.py: slats, iron ends, arms);
		# the boxes below if its file is missing
		var made: ArrayMesh = g._models.mesh("bench") if g._models != null else null
		if made != null:
			made.surface_set_material(0, g._surface("furniture"))
			return made
		var bench_buf := Streets.Buf.new()
		g._box(bench_buf, Vector3(0, 0.44, 0), Vector3(1.7, 0.07, 0.46))
		g._box(bench_buf, Vector3(0, 0.74, -0.22), Vector3(1.7, 0.36, 0.06))
		for sx: float in [-0.72, 0.72]:
			g._box(bench_buf, Vector3(sx, 0.22, 0), Vector3(0.07, 0.44, 0.42))
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bench_buf.arrays())
		am.surface_set_material(0, g._surface("furniture"))
		return am)
	g._chunked(bench, benches, 160.0, [], null, true)
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.06
	post.height = 3.6
	post.radial_segments = 6
	post.rings = 1
	post.material = g._surface("pole")
	var globe := SphereMesh.new()
	globe.radius = 0.22
	globe.height = 0.44
	globe.radial_segments = 8
	globe.rings = 4
	globe.material = g._surface("lamp")
	g._chunked(post, posts, Streets.LAMP_RANGE)
	g._chunked(globe, globes, Streets.LAMP_RANGE)
	# playgrounds, in the bigger parks
	var play := {"friend": Streets.CBuf.new(Streets.CHUNK), "warn": Streets.CBuf.new(Streets.CHUNK), "accent": Streets.CBuf.new(Streets.CHUNK),
		"player": Streets.CBuf.new(Streets.CHUNK), "pole": Streets.CBuf.new(Streets.CHUNK), "soft": Streets.CBuf.new(Streets.CHUNK), "sand": Streets.CBuf.new(Streets.CHUNK)}
	var made := 0
	for ring: PackedVector2Array in g._rings_near("park") + g._rings_near("grass"):
		if g._area(ring) < 1500.0 or not g._ring_mine(ring):
			continue
		var spot := _clear_spot(ring, 7.0)
		if not spot.is_finite():
			continue
		_playground(play, spot, float(posmod(g._hash_i(spot), 360)) * PI / 180.0)
		g._landmarks.append([spot, "playground"])
		made += 1
	var mats := {"friend": g.mat("friend", 0.12), "warn": g.mat("warn", 0.12), "accent": g.mat("accent", 0.12),
		"player": g.mat("player", 0.12), "pole": g._surface("pole"), "soft": g._surface("rubber"), "sand": g._surface("sand")}
	for k: String in play:
		g._add_mesh(play[k], mats[k], k != "soft" and k != "sand", 260.0)
	# pitches: lines, and goals or hoops
	var lines := Streets.CBuf.new(Streets.GROUND_CELL)
	var frames := Streets.CBuf.new(Streets.CHUNK)
	var pitches := 0
	for ring: PackedVector2Array in g._rings_near("pitch"):
		if g._ring_mine(ring):
			_sports_pitch(ring, lines, frames)
			pitches += 1
	g._add_mesh(lines, g._surface("mark"), false, Streets.DETAIL_RANGE)
	g._add_mesh(frames, g._surface("mark"), true, 260.0)
	g._tally("benches", benches.size())
	g._tally("playgrounds", made)
	g._tally("pitches", pitches)

## a point inside `ring` with nothing solid or a path within `r` of it, nearest its middle
func _clear_spot(ring: PackedVector2Array, r: float) -> Vector2:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	var box := g._bld_box_of(ring)
	var best := Vector2.INF
	var bd := INF
	for i in range(40):
		var q := c if i == 0 else Vector2(lerpf(box.position.x, box.end.x, fposmod(i * 0.618, 1.0)),
			lerpf(box.position.y, box.end.y, fposmod(i * 0.382 + 0.17, 1.0)))
		if not Geometry2D.is_point_in_polygon(q, ring):
			continue
		var ok := true
		for k in range(8):
			var e := q + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * r
			if not Geometry2D.is_point_in_polygon(e, ring):
				ok = false
				break
		if not ok or g._push_out(q, r, true) != Vector2.ZERO:
			continue
		var hit := g._nearest_seg(q, r + 3.0, false)
		if not hit.is_empty() and float(hit["edge"]) < r:
			continue
		if q.distance_to(c) < bd:
			bd = q.distance_to(c)
			best = q
	return best

const PLAY_ROLES := {"paint": "warn", "paint2": "player", "paint3": "accent", "plastic": "friend",
	"wood": "friend", "metal": "pole", "rubber": "pole", "dark": "pole", "*": "pole"}
func _playground(b: Dictionary, at: Vector2, yaw: float) -> void:
	var gy := g._h(at)
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	var P := func(q: Vector2, y: float) -> Vector3: return Vector3(q.x, gy + y, q.y)
	var floor_buf: Streets.Buf = b["soft"]
	var seg := 16
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		floor_buf.tri(P.call(at, 0.04), P.call(at + Vector2(cos(a0), sin(a0)) * 7.0, 0.04),
			P.call(at + Vector2(cos(a1), sin(a1)) * 7.0, 0.04), Vector3.UP, Color.WHITE)
	# each model's +X along `along`, its middle at q (the models' own frame: +X ahead, up)
	var put := func(name: String, q: Vector2, along: Vector2) -> void:
		var bs := Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(-along.y, 0, along.x))
		g._models.stamp_into(b, PLAY_ROLES, name, Transform3D(bs, P.call(q, 0.04)))
	put.call("slide", at - side * 3.0 - fwd * 0.4, fwd)        # (down the chute along fwd)
	g._add_post(at - side * 3.0 - fwd * 1.6, 0.7)
	put.call("swings", at + side * 3.2, side)                   # (the bar along fwd, swinging across)
	g._add_post(at + side * 3.2 + fwd * 1.7, 0.2)
	g._add_post(at + side * 3.2 - fwd * 1.7, 0.2)
	put.call("climber", at + fwd * 4.2 - side * 1.2, fwd)
	g._add_post(at + fwd * 4.2 - side * 1.2, 1.9)
	put.call("seesaw", at + fwd * 4.6 + side * 3.0, side)
	put.call("picnic", at - fwd * 3.6 + side * 3.7, fwd)   # (a picnic table by the sandpit, for the grown-ups)
	g._add_post(at - fwd * 3.6 + side * 3.7, 0.9)
	# the sandpit
	var sp := at + fwd * -3.4
	for e: float in [-1.5, 1.5]:
		g._obox(b["friend"], P.call(sp + fwd * e, 0.15), Vector3(3.2, 0.3, 0.15), yaw)
		g._obox(b["friend"], P.call(sp + side * e, 0.15), Vector3(3.2, 0.3, 0.15), yaw + PI * 0.5)
	g._obox(b["sand"], P.call(sp, 0.08), Vector3(2.9, 0.12, 2.9), yaw)

## a pitch: the tightest rectangle round it, its lines (inset a metre), and a goal at each
## end (a basketball hoop on a small court)
func _sports_pitch(ring: PackedVector2Array, lines: Streets.Buf, frames: Streets.Buf) -> void:
	var best := INF
	var u := Vector2.RIGHT
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	for i in range(ring.size()):
		var e := (ring[(i + 1) % ring.size()] - ring[i]).normalized()
		if e == Vector2.ZERO:
			continue
		var v := Vector2(-e.y, e.x)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in ring:
			var q := Vector2(p.dot(e), p.dot(v))
			mn = mn.min(q)
			mx = mx.max(q)
		if (mx.x - mn.x) * (mx.y - mn.y) < best:
			best = (mx.x - mn.x) * (mx.y - mn.y)
			u = e
			lo = mn
			hi = mx
	var v := Vector2(-u.y, u.x)
	if hi.y - lo.y > hi.x - lo.x:   # u along the long side
		var t := u
		u = v
		v = -t
		var l2 := Vector2(-hi.y, lo.x)
		var h2 := Vector2(-lo.y, hi.x)
		lo = l2
		hi = h2
	var L := hi.x - lo.x
	var W := hi.y - lo.y
	if L < 12.0 or W < 7.0 or best > 12000.0:
		return
	g._landmarks.append([u * (lo.x + hi.x) * 0.5 + v * (lo.y + hi.y) * 0.5, "pitch"])
	var at := func(a: float, b: float) -> Vector2: return u * a + v * b
	var strip := func(p0: Vector2, p1: Vector2) -> void:
		var d := (p1 - p0).normalized()
		var n := Vector2(-d.y, d.x) * 0.06
		lines.quad3(g._g3(p0 - n, 0.05), g._g3(p1 - n, 0.05), g._g3(p1 + n, 0.05), g._g3(p0 + n, 0.05))
	var x0 := lo.x + 1.0
	var x1 := hi.x - 1.0
	var y0 := lo.y + 1.0
	var y1 := hi.y - 1.0
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	for e: Array in [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0], [cx, y0, cx, y1]]:
		strip.call(at.call(e[0], e[1]), at.call(e[2], e[3]))
	var cr := minf(3.0, (y1 - y0) * 0.16)
	for i in range(16):
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		strip.call(at.call(cx + cos(a0) * cr, cy + sin(a0) * cr), at.call(cx + cos(a1) * cr, cy + sin(a1) * cr))
	var yaw := atan2(u.x, u.y)
	for end: Array in [[x0, 1.0], [x1, -1.0]]:
		var gp: Vector2 = at.call(end[0], cy)
		var gy := g._h(gp)
		if L >= 34.0:   # football: two posts and a bar
			var gw := minf(5.0, (y1 - y0) * 0.3)
			for sd: float in [-0.5, 0.5]:
				var q := gp + v * gw * sd
				g._obox(frames, Vector3(q.x, gy + 1.1, q.y), Vector3(0.1, 2.2, 0.1), yaw)
			g._obox(frames, Vector3(gp.x, gy + 2.2, gp.y), Vector3(gw + 0.1, 0.1, 0.1), yaw)
		else:   # a hoop: a pole off the end line and a backboard over it
			var q := gp - u * 0.6 * float(end[1])
			g._obox(frames, Vector3(q.x, gy + 1.6, q.y), Vector3(0.12, 3.2, 0.12), yaw)
			var bb := gp + u * 0.3 * float(end[1])
			g._obox(frames, Vector3(bb.x, gy + 3.35, bb.y), Vector3(1.6, 1.0, 0.06), yaw)
