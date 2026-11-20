extends RefCounted
## Street furniture past the basics, the things that make a street read as a real one:
## power lines on their poles, flags (on the lamp posts of Givatayim's main roads, off
## balconies, on flagpoles at schools), billboards and lit ad columns, fences round pitches
## and schoolyards, hedges and railings along parks, bike racks and parked scooters.
##
## Built with the city, a square at a time (see the game's _build_tile): power lines and
## fences, like the kerbs, are strung by every square they cross, each keeping its own
## piece; everything else belongs to the square it stands in. Every kind is a multimesh of one small "kit" mesh (its colours
## in the vertex colours) or one mesh per map square, so a kind costs a draw or two where it
## is seen and nothing where it is not. Placement asks the game the same questions as
## everything else that stands by a street: not on the asphalt (`_off_road`), not in a
## building (`_push_out`), not on top of a lamp or a tree (`_clear_of_posts`).

var g: Node                    ## the streets game: its roads, ground height and helpers
var med := false               ## Givatayim's look (else Bedford's)
var _kit_mat: StandardMaterial3D
var _ad_mat: ShaderMaterial
var _flag_mat: ShaderMaterial
var _fence_mats := {}
var _kits := {}
var _count := {}
var where := {}                ## kind -> transforms of what went in (for tests and tours)
var _flag_seen := {}           ## 60 m squares that have their flagpole
var _life_taken := {}          ## 25 m squares that have their rack or scooters

const SEEN := 320.0            ## poles, lamps: thin, gone in the haze
const WIRE_SEEN := 200.0       ## wires: past this they are less than a pixel and shimmer
const NEAR_SEEN := 140.0       ## racks, scooters, flags
const CELL := 400.0            ## the map squares wires, fences and hedges are cut into
const FENCE_SEEN := 220.0
const MAIN := {"primary": true, "secondary": true, "tertiary": true, "trunk": true}
const FAST := {"motorway": true, "trunk": true, "motorway_link": true, "trunk_link": true}
## the wind the flags on flagpoles fly in (they all agree, as real ones do)
const WIND := Vector2(0.8, -0.6)

const FLAG_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float glow = 0.0;
void vertex() {
	// UV.x: how free this bit of cloth is (0 where it is tied on, 1 at the free edge)
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.37 + o.z * 0.23;
	float w = UV.x;
	VERTEX.z += (sin(TIME * 3.4 + VERTEX.x * 3.1 + VERTEX.y * 1.7 + ph) * 0.1
		+ sin(TIME * 5.3 + VERTEX.x * 6.0 + ph * 1.7) * 0.035) * w;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	EMISSION = COLOR.rgb * glow;
}
"""

## an ad's face glows (vertex alpha 1), its frame does not (alpha 0)
const AD_SHADER := """
shader_type spatial;
uniform float glow = 0.12;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.4;
	EMISSION = COLOR.rgb * glow * COLOR.a;
}
"""

## a mesh fence as one see-through panel: bars every `gap` metres, a rail top and bottom;
## UV is metres along it and up it, UV2.x its height. Far off, where a bar is less than a
## pixel, it turns into an even haze rather than shimmering.
const FENCE_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec4 col : source_color;
uniform float gap = 0.12;
uniform float haze = 0.45;
void fragment() {
	vec2 fw = fwidth(UV);
	float d = abs(fract(UV.x / gap + 0.5) - 0.5) * gap;
	float bar = 1.0 - smoothstep(0.012, 0.012 + fw.x * 1.5, d);
	float rail = step(UV2.x - 0.07, UV.y) + step(UV.y, 0.06);
	float mesh = 1.0 - smoothstep(0.005, 0.005 + fw.y * 1.5, abs(fract(UV.y / 0.5 + 0.5) - 0.5) * 0.5);
	float a = max(max(bar, clamp(rail, 0.0, 1.0)), mesh * 0.5);
	a = max(a, clamp(fw.x / gap * 2.0, 0.0, 1.0) * haze);
	ALBEDO = col.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = 0.6;
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
"""

func _init(game: Node) -> void:
	g = game
	med = String(g._place.get("look", "")) == "med"

## ---- kit meshes: a Buf of coloured parts as one mesh ---------------------------------------

func _kit() -> StandardMaterial3D:
	if _kit_mat == null:
		_kit_mat = g._vc_mat()   # shared with the signs: merged into the same meshes
	return _kit_mat

func _mesh(b, m: Material = null) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	am.surface_set_material(0, m if m != null else _kit())
	return am

func _tone(t: String) -> Color:
	return g._tone[t]

## a box of size `s` round `c`, turned by `bs`
func _box(b, c: Vector3, s: Vector3, col: Color, bs := Basis()) -> void:
	var ax := bs.x * s.x * 0.5
	var ay := bs.y * s.y * 0.5
	var az := bs.z * s.z * 0.5
	for f: Array in [[ax, ay, az], [-ax, ay, az], [ay, ax, az], [-ay, ax, az], [az, ax, ay], [-az, ax, ay]]:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := c + n
		var nn := n.normalized()
		b.tri(o - u - v, o + u - v, o + u + v, nn, col)
		b.tri(o - u - v, o + u + v, o - u + v, nn, col)

## a tube from a to e, radius r0 at a and r1 at e (no ends)
func _tube(b, a: Vector3, e: Vector3, r0: float, r1: float, col: Color, sides := 6) -> void:
	var ax := (e - a).normalized()
	var ref := Vector3.FORWARD if absf(ax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var u := ax.cross(ref).normalized()
	var v := ax.cross(u)
	for i in range(sides):
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var d0 := u * cos(t0) + v * sin(t0)
		var d1 := u * cos(t1) + v * sin(t1)
		var nm := (d0 + d1).normalized()
		b.tri(a + d0 * r0, a + d1 * r0, e + d1 * r1, nm, col)
		b.tri(a + d0 * r0, e + d1 * r1, e + d0 * r1, nm, col)

## a flat polygon (fan from its first point) in the plane of `xf`'s X and Y, facing +Z
func _poly(b, xf: Transform3D, pts: Array, col: Color, u2 := Vector2.ZERO) -> void:
	var n := (xf.basis * Vector3.BACK).normalized()
	for i in range(1, pts.size() - 1):
		var p0: Vector2 = pts[0]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		b.tri(xf * Vector3(p0.x, p0.y, 0), xf * Vector3(p1.x, p1.y, 0), xf * Vector3(p2.x, p2.y, 0), n, col,
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, u2)

func _rect(x0: float, y0: float, x1: float, y1: float) -> Array:
	return [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]

## many copies of one kit, cut into map squares
func _place(mesh: Mesh, xforms: Array, seen: float, name: String, shadows := false, colours: Array = []) -> void:
	if xforms.is_empty():
		return
	if g._over():
		await g._pause()
	g._chunked(mesh, xforms, seen, colours, null, shadows)
	_count[name] = int(_count.get(name, 0)) + xforms.size()
	if not where.has(name):
		where[name] = []
	(where[name] as Array).append_array(xforms)

func _mark(name: String, p: Vector2) -> void:
	if not where.has(name):
		where[name] = []
	(where[name] as Array).append(Transform3D(Basis(), Vector3(p.x, _h(p), p.y)))

## ---- where things can stand -----------------------------------------------------------------

## on the pavement: off the asphalt by `margin`, out of buildings by `room`, `posts` metres
## from the nearest lamp, tree or sign
func _free(p: Vector2, margin: float, room: float, posts: float) -> bool:
	for kc: Array in g._keep_clear:   # (where a filmed walk shows nothing: details.gd's `clear`)
		if p.distance_to(kc[0]) <= kc[1]:
			return false
	return g._off_road(p, margin) and not g._in_junction(p, margin) \
			and g._push_out(p, room, false, false) == Vector2.ZERO and g._clear_of_posts(p, posts)

func _h(p: Vector2) -> float:
	return g._h(p)

## a stable number in [0, 1) for anything
func _rnd(key) -> float:
	return float(posmod(hash(key), 100003)) / 100003.0

## spots every `step` metres along a road, `off` metres out from its middle on one side
## (+1 right of the way it is drawn, -1 left), clear of junctions: [p, along, out]
func _walk_road(r: Dictionary, step: float, first: float, off: float, side: float, keep: float) -> Array:
	var out: Array = []
	var pts: PackedVector2Array = r["pts"]
	var ids: PackedInt32Array = r["ids"]
	var s := first
	for j in range(pts.size() - 1):
		var a := pts[j]
		var b := pts[j + 1]
		var L := a.distance_to(b)
		if L < 0.01:
			continue
		var d := (b - a) / L
		var o := Vector2(-d.y, d.x) * side
		var ka: float = (float(g._node_r[ids[j]]) + keep) if (g._node_roads[ids[j]] as Array).size() >= 2 else 0.0
		var kb: float = (float(g._node_r[ids[j + 1]]) + keep) if (g._node_roads[ids[j + 1]] as Array).size() >= 2 else 0.0
		while s < L:
			if s > ka and s < L - kb:
				out.append([a + d * s + o * off, d, o])
			s += step
		s -= L
	return out

## ---- power lines --------------------------------------------------------------------------
## Poles down one side of a share of the streets (most of Bedford's, about half of
## Givatayim's), three wires sagging from pole to pole, a transformer every so often. In
## Givatayim the poles are concrete; in Bedford they are wood, a phone cable hangs lower
## down, and the street lamps hang off them (those streets then get no lamp posts of their
## own: see `_wired` in the game).
func wires() -> void:
	var poles: Array = []
	var trafos: Array = []
	var arms: Array = []
	var heads: Array = []
	var wire = g.new_cbuf(CELL)
	wire.clip = true   # every square the street crosses strings it; each keeps its own stretch
	var H := 9.0 if med else 10.0
	var spacing := 34.0 if med else 40.0
	var spans := 0
	for ri: int in g._tile_roads.get(g._tile, []):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"] or r["k"] == "service" or FAST.has(r["k"]) or r.get("ring", false):
			continue
		if g._over():
			await g._pause()
		var share := 0.85 if not med else (0.6 if MAIN.has(r["k"]) else 0.45)
		if _rnd(ri * 31 + 7) >= share:
			continue
		var hw: float = float(r["w"]) * 0.5
		var side := 1.0 if posmod(hash(ri), 2) == 0 else -1.0
		var last_p := Vector2.INF
		var last_at: Array = []
		var n := 0
		for sp: Array in _walk_road(r, spacing, 6.0 + _rnd(ri) * 12.0, hw + 0.55, side, 3.0):
			var p: Vector2 = sp[0]
			var d: Vector2 = sp[1]
			var out: Vector2 = sp[2]
			# a pole in this square keeps clear of its lamps and trees; one in the next square is
			# taken as clear (its trees are not up yet) so the wire still runs to it
			var mine: bool = g._mine(p)
			if not (_free(p, 0.25, 0.45, 2.2) if mine else (g._off_road(p, 0.25) and g._push_out(p, 0.45, false, false) == Vector2.ZERO)):
				continue
			var gy := _h(p)
			# the crossarm goes across the street: local X along `out`
			var bs := Basis(Vector3.UP, atan2(-out.y, out.x))
			if mine:
				poles.append(Transform3D(bs, Vector3(p.x, gy, p.y)))
				g._add_post(p, 0.14)
			n += 1
			var at: Array = []
			for x: float in [-0.75, 0.0, 0.75]:
				var q := p + out * x
				at.append(Vector3(q.x, gy + H - 0.45, q.y))
			if not med:
				var q := p - out * 0.15
				at.append(Vector3(q.x, gy + H - 2.9, q.y))   # the phone cable, lower down
			if n % 6 == 3 and mine:
				trafos.append(Transform3D(bs, Vector3(p.x, gy, p.y)))
			if mine and not med and (n % 2 == 0 or MAIN.has(r["k"])):
				# a street lamp on its arm over the road
				var toward := -out
				var abs_ := Basis(Vector3.UP, atan2(-toward.y, toward.x))
				arms.append(Transform3D(abs_, Vector3(p.x, gy + 7.4, p.y)))
				var hp := p + toward * 2.3
				heads.append(Transform3D(abs_, Vector3(hp.x, gy + 7.55, hp.y)))
				g._pool_at.append(Vector3(hp.x + toward.x * 0.5, hp.y + toward.y * 0.5, 7.5))
			if last_p != Vector2.INF and last_p.distance_to(p) < spacing * 1.6 \
					and g._push_out((last_p + p) * 0.5, 0.3, false, false) == Vector2.ZERO:
				for i in range(at.size()):
					_cable(wire, last_at[i], at[i], 0.05 if i < 3 else 0.07)
				if mine:
					spans += 1
			last_p = p
			last_at = at
		if not med and n > 0:
			g._wired[ri] = true
	await _place(_pole_kit(H), poles, SEEN, "power_poles")
	await _place(_trafo_kit(H), trafos, SEEN, "transformers")
	if not arms.is_empty():
		await _place(_cobra_arm_kit(), arms, SEEN, "pole_lamps")
		var head := BoxMesh.new()
		head.size = Vector3(0.7, 0.16, 0.32)
		head.material = g._surface("lamp")
		g._chunked(head, heads, SEEN)
	g._add_mesh(wire, g._surface("cable"), false, WIRE_SEEN)
	_count["wire_spans"] = int(_count.get("wire_spans", 0)) + spans

## one wire from a to e sagging in the middle: two thin ribbons crossed, so it shows from
## below and from the side
func _cable(b, a: Vector3, e: Vector3, w: float) -> void:
	var L := Vector2(a.x, a.z).distance_to(Vector2(e.x, e.z))
	var sag := 0.25 + L * 0.012
	var side := (e - a).cross(Vector3.UP).normalized() * w * 0.5
	var up := Vector3.UP * w * 0.5
	var prev := a
	var col: Color = Color.WHITE
	for i in range(1, 5):
		var t := i / 4.0
		var q := a.lerp(e, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
		b.tri(prev - side, prev + side, q + side, Vector3.UP, col)
		b.tri(prev - side, q + side, q - side, Vector3.UP, col)
		var n := side.normalized()
		b.tri(prev - up, prev + up, q + up, n, col)
		b.tri(prev - up, q + up, q - up, n, col)
		prev = q

func _pole_kit(H: float) -> ArrayMesh:
	var b = g.new_buf()
	var col := _tone("concrete") if med else _tone("trunk")
	var arm := _tone("pole")
	var ins := _tone("insulator")
	if med:
		_tube(b, Vector3.ZERO, Vector3(0, H, 0), 0.16, 0.09, col, 6)
	else:
		_tube(b, Vector3.ZERO, Vector3(0, H, 0), 0.15, 0.12, col, 7)
	_box(b, Vector3(0, H - 0.6, 0), Vector3(1.9, 0.1, 0.1), arm if med else col)
	for x: float in [-0.75, 0.0, 0.75]:
		_box(b, Vector3(x, H - 0.48, 0), Vector3(0.07, 0.16, 0.07), ins)
	if not med:
		_box(b, Vector3(-0.15, H - 2.9, 0), Vector3(0.12, 0.12, 0.12), arm)   # the phone cable's clamp
	return _mesh(b)

func _trafo_kit(H: float) -> ArrayMesh:
	var b = g.new_buf()
	var col := _tone("trafo")
	if med:
		# a box on a bracket on the street-away side, cooling fins down its sides
		_box(b, Vector3(0.62, H - 3.6, 0), Vector3(0.75, 1.15, 0.7), col)
		_box(b, Vector3(0.62, H - 3.6, 0.38), Vector3(0.6, 0.9, 0.06), col.darkened(0.15))
		_box(b, Vector3(0.62, H - 3.6, -0.38), Vector3(0.6, 0.9, 0.06), col.darkened(0.15))
		_box(b, Vector3(0.3, H - 4.25, 0), Vector3(0.6, 0.08, 0.5), _tone("pole"))
	else:
		_tube(b, Vector3(0.42, H - 2.4, 0), Vector3(0.42, H - 1.3, 0), 0.3, 0.3, col, 8)
		_box(b, Vector3(0.42, H - 1.25, 0), Vector3(0.55, 0.08, 0.55), col.darkened(0.1))
	return _mesh(b)

## Bedford's street lamp: an arm out over the road from the power pole (+X toward it)
func _cobra_arm_kit() -> ArrayMesh:
	var b = g.new_buf()
	var col := _tone("pole")
	_tube(b, Vector3(0.1, 0, 0), Vector3(1.0, 0.25, 0), 0.04, 0.035, col, 4)
	_tube(b, Vector3(1.0, 0.25, 0), Vector3(2.1, 0.2, 0), 0.035, 0.03, col, 4)
	return _mesh(b)

## ---- lamps and bus stops: kits the game plants itself --------------------------------------

## Givatayim's main-road lamp: a plinth, a dark-green pole with a collar, a curved arm out
## along +X to where the lantern hangs (the game hangs the lit lantern at x 1.6, y 6.85);
## `double`: an arm each way, for the middle of a dual carriageway
func ornate_kit(double: bool) -> ArrayMesh:
	var key := "ornate%s" % double
	if _kits.has(key):
		return _kits[key]
	var b = g.new_buf()
	var col := _tone("lampgreen")
	_tube(b, Vector3.ZERO, Vector3(0, 0.9, 0), 0.18, 0.13, col, 8)
	_tube(b, Vector3(0, 0.9, 0), Vector3(0, 7.0, 0), 0.085, 0.06, col, 7)
	_tube(b, Vector3(0, 2.85, 0), Vector3(0, 3.1, 0), 0.12, 0.12, col, 7)
	_tube(b, Vector3(0, 7.0, 0), Vector3(0, 7.4, 0), 0.05, 0.015, col, 5)
	for sg: float in ([1.0, -1.0] if double else [1.0]):
		var arc := [Vector3(0, 6.55, 0), Vector3(0.35, 7.0, 0), Vector3(0.8, 7.28, 0), Vector3(1.25, 7.3, 0),
			Vector3(1.6, 7.16, 0), Vector3(1.6, 7.05, 0)]
		for i in range(arc.size() - 1):
			var a: Vector3 = arc[i]
			var e: Vector3 = arc[i + 1]
			_tube(b, Vector3(a.x * sg, a.y, 0), Vector3(e.x * sg, e.y, 0), 0.04, 0.035, col, 5)
		_tube(b, Vector3(0.05 * sg, 6.05, 0), Vector3(0.55 * sg, 7.08, 0), 0.022, 0.022, col, 4)   # the brace
	var am: ArrayMesh = _mesh(b)
	_kits[key] = am
	return am

## a bus shelter's roof, curved front to back (local +Z toward the street), 3.6 m long
func bus_roof_kit() -> ArrayMesh:
	if _kits.has("busroof"):
		return _kits["busroof"]
	var b = g.new_buf()
	var col := _tone("signblue") if med else _tone("cartrim")
	var R := 1.3
	var prev := Vector2.INF
	for i in range(9):
		var t := lerpf(-0.75, 0.9, i / 8.0)
		var q := Vector2(R * sin(t), R * cos(t) - R + 0.2)   # (z, y)
		if prev != Vector2.INF:
			var n := Vector3(0, q.x - prev.x, -(q.y - prev.y)).normalized()
			if n.y < 0.0:
				n = -n
			for side: float in [1.0, -1.0]:
				var off := n * 0.02 * side
				b.tri(Vector3(-1.8, prev.y, prev.x) + off, Vector3(1.8, prev.y, prev.x) + off, Vector3(1.8, q.y, q.x) + off, n * side, col)
				b.tri(Vector3(-1.8, prev.y, prev.x) + off, Vector3(1.8, q.y, q.x) + off, Vector3(-1.8, q.y, q.x) + off, n * side, col)
		prev = q
	var am: ArrayMesh = _mesh(b)
	_kits["busroof"] = am
	return am

## the stop's own sign on its pole: a yellow plate, a bus on it and the route numbers
## (local +Z toward the street; both faces)
func bus_sign_kit() -> ArrayMesh:
	if _kits.has("bussign"):
		return _kits["bussign"]
	var b = g.new_buf()
	var yellow := Palette.col("warn").lerp(Palette.col("ink"), 0.1)
	var dark := Palette.col("bg")
	var white := _tone("mark")
	_box(b, Vector3(0, 0, 0), Vector3(0.5, 0.78, 0.035), yellow)
	for z: float in [0.02, -0.02]:
		var bs := Basis() if z > 0.0 else Basis(Vector3.UP, PI)
		var at := func(x: float, y: float) -> Transform3D: return Transform3D(bs, bs * Vector3(x, y, absf(z)))
		_poly(b, at.call(0, 0.2), _rect(-0.17, -0.07, 0.17, 0.08), dark)          # the bus
		_poly(b, at.call(0, 0.2), _rect(-0.14, 0.0, 0.14, 0.05), yellow)          # its windows
		for wx: float in [-0.1, 0.1]:
			var wheel: Array = []
			for i in range(8):
				wheel.append(Vector2(wx + cos(TAU * i / 8.0) * 0.035, -0.07 + sin(TAU * i / 8.0) * 0.035))
			_poly(b, at.call(0, 0.2), wheel, dark)
		for row in range(3):
			for col in range(2):
				var x := -0.11 + col * 0.22
				var y := -0.05 - row * 0.11
				_poly(b, at.call(x, y), _rect(-0.09, -0.04, 0.09, 0.04), white)
				_poly(b, Transform3D(bs, bs * Vector3(x, y, absf(z) + 0.003)), _rect(-0.05, -0.022, 0.05, 0.022), dark)
	var am: ArrayMesh = _mesh(b)
	_kits["bussign"] = am
	return am

func retint() -> void:
	for tone: String in _fence_mats:
		(_fence_mats[tone] as ShaderMaterial).set_shader_parameter("col", _tone(tone))

## ---- everything else, built after the places ------------------------------------------------
func build() -> void:
	await flags()
	await ads()
	await fences()
	await kerbside()   # (before the racks and scooters: they keep clear of these)
	await street_life()
	await cats()
	for k: String in _count:
		g._dressing[k] = _count[k]

func set_night(on: bool) -> void:
	if _ad_mat != null:
		_ad_mat.set_shader_parameter("glow", 1.1 if on else 0.12)
	if _flag_mat != null:
		_flag_mat.set_shader_parameter("glow", 0.0)

## ---- flags --------------------------------------------------------------------------------
## Israel's on staffs off the lamp posts of Givatayim's main roads (the game records those
## as it plants the lamps) and hanging off a balcony here and there; on a flagpole at each
## school, Israel's or Canada's. They wave: the cloth moves in the shader, more the further
## from where it is tied.
func flags() -> void:
	var country := "il" if med else "ca"
	var poles: Array = []
	var flown: Array = []
	var k := 1.0 / float(g._city_data.get("scale", 10))
	var seen := _flag_seen
	var all_pois: Array = g._city_data.get("pois", [])
	for pi: int in g._tile_pois.get(g._tile, []):
		var p: Array = all_pois[pi]
		if not (String(p[2]) in ["school", "kindergarten", "townhall", "police", "community_centre", "library"]):
			continue
		if g._over():
			await g._pause()
		var at := Vector2(p[0], p[1]) * k
		var cell := Vector2i((at / 60.0).round())
		if seen.has(cell):
			continue
		seen[cell] = true
		var spot: Array = g._facade_spot(at)
		var n: Vector2 = spot[1]
		for back: float in [3.5, 5.0, 2.5]:
			var q: Vector2 = (spot[0] as Vector2) + n * back
			if _free(q, 1.0, 0.6, 2.0):
				var gy := _h(q)
				poles.append(Transform3D(Basis(), Vector3(q.x, gy, q.y)))
				var w := WIND.normalized()
				flown.append(Transform3D(Basis(Vector3.UP, atan2(-w.y, w.x)), Vector3(q.x, gy + 7.6, q.y)))
				g._add_post(q, 0.1)
				break
	var b = g.new_buf()
	_tube(b, Vector3.ZERO, Vector3(0, 7.8, 0), 0.06, 0.04, _tone("mark"), 6)
	_box(b, Vector3(0, 7.85, 0), Vector3(0.12, 0.1, 0.12), _tone("lamp"))
	await _place(_mesh(b), poles, SEEN, "flagpoles")
	await _place(_flag_kit("fly", country), flown, NEAR_SEEN * 1.5, "flags_flown")
	if med:
		await _place(_flag_kit("staff", "il"), g._flag_spots, NEAR_SEEN * 1.5, "flags_on_lamps")
		await _place(_flag_kit("hang", "il"), g._balcony_flags, NEAR_SEEN, "flags_on_balconies")

func _flag_material() -> ShaderMaterial:
	if _flag_mat == null:
		_flag_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = FLAG_SHADER
		_flag_mat.shader = sh
	return _flag_mat

## A flag as a mesh. "fly": tied along its left edge at the origin, flying along +X, top
## at y 0 (for a flagpole). "hang": hanging from its top edge, centred, facing +Z (off a
## balcony). "staff": on a short staff up and out along +X from a lamp post, hanging from it.
## "car": a small one on a plastic stick clipped to a car's window (the origin), the stick up
## and a little back, the flag flying back along +X.
func _flag_kit(how: String, country: String) -> ArrayMesh:
	var key := how + country
	if _kits.has(key):
		return _kits[key]
	var b = g.new_buf()
	var W := 1.1 if country == "il" else 1.2
	var H := 0.8 if country == "il" else 0.6
	var xf := Transform3D()
	if how == "hang":
		xf = Transform3D(Basis(), Vector3(-W * 0.5, 0, 0))
	elif how == "staff":
		var tilt := 0.42
		var sb := Basis(Vector3.BACK, tilt)
		_tube(b, Vector3.ZERO, sb * Vector3(W + 0.35, 0, 0), 0.025, 0.02, _tone("mark"), 4)
		xf = Transform3D(sb, sb * Vector3(0.25, -0.02, 0))
	elif how == "car":   # 40 x 30 cm on a 55 cm stick (the cloth drawn at 0.38 of a full flag's size)
		var top := Vector3(0.07, 0.55, 0)
		_tube(b, Vector3.ZERO, top, 0.008, 0.006, _tone("cartrim"), 4)
		xf = Transform3D(Basis().scaled(Vector3(0.38, 0.38, 1.0)), top)
	# the cloth, cut into a grid so it can bend; UV.x says how free each corner is
	var slack := func(u: float, v: float) -> float:
		return u / W if how == "fly" else clampf(-v / H, 0.0, 1.0)
	var piece := func(u0: float, v0: float, u1: float, v1: float, z: float, col: Color) -> void:
		var n := (xf.basis * Vector3.BACK).normalized() * (1.0 if z >= 0.0 else -1.0)
		var c := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
		var P := func(q: Vector2) -> Vector3: return xf * Vector3(q.x, q.y, z)
		var F := func(q: Vector2) -> Vector2: return Vector2(slack.call(q.x, q.y), 0)
		b.tri(P.call(c[0]), P.call(c[1]), P.call(c[2]), n, col, F.call(c[0]), F.call(c[1]), F.call(c[2]))
		b.tri(P.call(c[0]), P.call(c[2]), P.call(c[3]), n, col, F.call(c[0]), F.call(c[2]), F.call(c[3]))
	var white := _tone("mark")
	var nu := 6
	var nv := 4
	for i in range(nu):
		for j in range(nv):
			piece.call(W * i / nu, -H * j / nv, W * (i + 1) / nu, -H * (j + 1) / nv, 0.0, white)
	# what is printed on it, a hair in front of the cloth on both sides
	for z: float in [0.012, -0.012]:
		if country == "il":
			var blue := _tone("signblue")
			for band: Array in [[0.1, 0.22], [0.78, 0.9]]:
				for i in range(nu):
					piece.call(W * i / nu, -H * float(band[0]), W * (i + 1) / nu, -H * float(band[1]), z, blue)
			# the star: two triangles drawn as bars
			var c := Vector2(W * 0.5, -H * 0.5)
			for flip: float in [1.0, -1.0]:
				var tri: Array = []
				for t in range(3):
					var a := PI * 0.5 + TAU * t / 3.0
					tri.append(c + Vector2(cos(a), sin(a) * flip) * 0.16)
				for t in range(3):
					var p0: Vector2 = tri[t]
					var p1: Vector2 = tri[(t + 1) % 3]
					var nn := (p1 - p0).normalized().orthogonal() * 0.016
					var q := [p0 - nn, p1 - nn, p1 + nn, p0 + nn]
					var n3 := (xf.basis * Vector3.BACK).normalized() * signf(z)
					var P := func(v: Vector2) -> Vector3: return xf * Vector3(v.x, v.y, z * 1.4)
					var F := func(v: Vector2) -> Vector2: return Vector2(slack.call(v.x, v.y), 0)
					b.tri(P.call(q[0]), P.call(q[1]), P.call(q[2]), n3, blue, F.call(q[0]), F.call(q[1]), F.call(q[2]))
					b.tri(P.call(q[0]), P.call(q[2]), P.call(q[3]), n3, blue, F.call(q[0]), F.call(q[2]), F.call(q[3]))
		else:
			var red := _tone("signred")
			for band: Array in [[0.0, 0.25], [0.75, 1.0]]:
				for j in range(nv):
					piece.call(W * float(band[0]), -H * j / nv, W * float(band[1]), -H * (j + 1) / nv, z, red)
			# the maple leaf, roughly: a star of points round its middle
			var leaf := [Vector2(0, 0.5), Vector2(0.08, 0.32), Vector2(0.2, 0.38), Vector2(0.16, 0.12),
				Vector2(0.42, 0.24), Vector2(0.36, 0.1), Vector2(0.46, 0.06), Vector2(0.25, -0.12),
				Vector2(0.28, -0.22), Vector2(0.03, -0.18), Vector2(0.03, -0.45), Vector2(-0.03, -0.45),
				Vector2(-0.03, -0.18), Vector2(-0.28, -0.22), Vector2(-0.25, -0.12), Vector2(-0.46, 0.06),
				Vector2(-0.36, 0.1), Vector2(-0.42, 0.24), Vector2(-0.16, 0.12), Vector2(-0.2, 0.38),
				Vector2(-0.08, 0.32)]
			var c := Vector2(W * 0.5, -H * 0.5)
			var n3 := (xf.basis * Vector3.BACK).normalized() * signf(z)
			for t in range(leaf.size()):
				var p0: Vector2 = c + (leaf[t] as Vector2) * 0.42
				var p1: Vector2 = c + (leaf[(t + 1) % leaf.size()] as Vector2) * 0.42
				var P := func(v: Vector2) -> Vector3: return xf * Vector3(v.x, v.y, z * 1.4)
				var F := func(v: Vector2) -> Vector2: return Vector2(slack.call(v.x, v.y), 0)
				b.tri(P.call(c), P.call(p0), P.call(p1), n3, red, F.call(c), F.call(p0), F.call(p1))
	var am: ArrayMesh = _mesh(b, _flag_material())
	_kits[key] = am
	return am

## ---- billboards and ad columns ------------------------------------------------------------
## Lit ad columns on the pavements of the main roads, both faces lit at night; big
## billboards on two legs by the faster roads where there is room; and an ad panel at the
## end of each bus shelter (the game records where). The ads are made up: a colour, a big
## round picture, a headline and a logo -- at driving speed that is what an ad is.
const AD_KINDS := 3
func ads() -> void:
	var columns: Array = []
	var boards: Array = []
	for i in range(AD_KINDS):
		columns.append([])
		boards.append([])
	var n := 0
	var nb := 0
	for ri: int in g._tile_roads.get(g._tile, []):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"]:
			continue
		if g._over():
			await g._pause()
		var hw: float = float(r["w"]) * 0.5
		if MAIN.has(r["k"]) and r["k"] != "trunk":
			var side := 1.0
			for sp: Array in _walk_road(r, 150.0, 40.0 + _rnd(ri) * 60.0, hw + 1.6, 1.0, 8.0):
				side = -side
				var d: Vector2 = sp[1]
				var p: Vector2 = (sp[0] as Vector2) - (sp[2] as Vector2) * (hw + 1.6) * (1.0 - side)
				if g._mine(p) and _free(p, 0.9, 0.9, 2.5):
					var gy := _h(p)
					var face := Basis(Vector3.UP, atan2(d.x, d.y))   # faces up and down the street
					(columns[posmod(hash(Vector2i(p.round())), AD_KINDS)] as Array).append(Transform3D(face, Vector3(p.x, gy, p.y)))
					g._add_post(p, 0.7)
					n += 1
		if r["k"] in ["primary", "trunk", "motorway", "secondary"]:
			for sp: Array in _walk_road(r, 260.0, 90.0 + _rnd(ri + 5) * 120.0, hw + 6.0, 1.0, 20.0):
				var p: Vector2 = sp[0]
				var d: Vector2 = sp[1]
				var out: Vector2 = sp[2]
				if not (g._mine(p) and _free(p, 3.0, 4.5, 6.0) and _free(p + d * 2.6, 2.5, 1.0, 1.0) and _free(p - d * 2.6, 2.5, 1.0, 1.0)):
					continue
				# facing the traffic coming, turned a little toward the road
				var look := (-d * cos(0.35) - out * sin(0.35)).normalized()
				var gy := _h(p)
				(boards[posmod(hash(Vector2i(p.round())), AD_KINDS)] as Array).append(Transform3D(Basis(Vector3.UP, atan2(look.x, look.y)), Vector3(p.x, gy, p.y)))
				g._add_post(p + d * 2.4, 0.2)
				g._add_post(p - d * 2.4, 0.2)
				nb += 1
	for xf: Transform3D in g._stop_ads:
		(columns[n % AD_KINDS] as Array).append(xf)
		n += 1
	for i in range(AD_KINDS):
		await _place(_column_kit(i), columns[i], SEEN * 0.7, "ad_columns")
		await _place(_board_kit(i), boards[i], SEEN * 1.6, "billboards")

func _ad_material() -> ShaderMaterial:
	if _ad_mat == null:
		_ad_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = AD_SHADER
		_ad_mat.shader = sh
		_ad_mat.set_shader_parameter("glow", 1.1 if g._night else 0.12)
	return _ad_mat

## a made-up ad, w by h, on the plane z (facing +Z if `front`, else -Z), centred at (0, cy)
func _ad_face(b, w: float, h: float, cy: float, z: float, front: bool, kind: int) -> void:
	var roles := ["accent", "player", "warn", "friend", "prize", "hazard"]
	var bg_col: Color = Palette.col(roles[kind % roles.size()]).lerp(Palette.col("bg"), 0.25)
	var pic: Color = Palette.col(roles[(kind + 2) % roles.size()]).lerp(Palette.col("ink"), 0.2)
	var ink := Palette.col("ink")
	var dark := Palette.col("bg")
	bg_col.a = 1.0
	pic.a = 1.0
	ink.a = 1.0
	dark.a = 1.0
	var bs := Basis() if front else Basis(Vector3.UP, PI)
	var put := func(pts: Array, dz: float, col: Color) -> void:
		var shifted: Array = []
		for q: Vector2 in pts:
			shifted.append(q + Vector2(0, cy))
		_poly(b, Transform3D(bs, bs * Vector3(0, 0, z + dz)), shifted, col)
	put.call(_rect(-w * 0.5, -h * 0.5, w * 0.5, h * 0.5), 0.0, bg_col)
	# the picture: a big disc, high or to one side
	var pc := Vector2(w * (0.18 if kind % 2 == 0 else -0.18), h * 0.12)
	var r := minf(w, h) * 0.3
	var disc: Array = []
	for i in range(14):
		disc.append(pc + Vector2(cos(TAU * i / 14.0), sin(TAU * i / 14.0)) * r)
	put.call(disc, 0.004, pic)
	# the headline: two bold bars and a thin one, across the bottom
	put.call(_rect(-w * 0.42, -h * 0.3, w * 0.3, -h * 0.2), 0.004, ink)
	put.call(_rect(-w * 0.42, -h * 0.38, w * 0.1, -h * 0.33), 0.004, ink)
	# a logo in the corner
	put.call(_rect(w * 0.22, -h * 0.45, w * 0.44, -h * 0.34), 0.004, dark)

func _column_kit(kind: int) -> ArrayMesh:
	var key := "column%d" % kind
	if _kits.has(key):
		return _kits[key]
	var b = g.new_buf()
	var frame := _tone("cartrim")
	frame.a = 0.0
	_box(b, Vector3(0, 0.15, 0), Vector3(1.2, 0.3, 0.42), frame)
	_box(b, Vector3(0, 1.25, 0), Vector3(1.32, 1.9, 0.3), frame)
	_box(b, Vector3(0, 2.25, 0), Vector3(1.4, 0.1, 0.36), frame)
	for front: bool in [true, false]:
		_ad_face(b, 1.16, 1.72, 1.25, 0.152, front, kind + (0 if front else 1))
	var am: ArrayMesh = _mesh(b, _ad_material())
	_kits[key] = am
	return am

func _board_kit(kind: int) -> ArrayMesh:
	var key := "board%d" % kind
	if _kits.has(key):
		return _kits[key]
	var b = g.new_buf()
	var steel := _tone("pole")
	steel.a = 0.0
	for x: float in [-2.4, 2.4]:
		_tube(b, Vector3(x, 0, 0), Vector3(x, 4.4, 0), 0.14, 0.12, steel, 6)
	_box(b, Vector3(0, 5.9, -0.1), Vector3(6.4, 3.3, 0.16), steel)
	_box(b, Vector3(0, 4.25, 0.35), Vector3(6.2, 0.06, 0.6), steel)   # the walkway under it
	_ad_face(b, 6.1, 3.0, 5.9, 0.0, true, kind + 3)
	var am: ArrayMesh = _mesh(b, _ad_material())
	_kits[key] = am
	return am

## ---- fences, railings and hedges ------------------------------------------------------------
## A tall green mesh fence round every sports pitch and schoolyard; along the edges of a
## park that face a street, a hedge or (in Givatayim) a low white railing; and the fences
## and hedges OSM maps itself, where the bake has them.
func fences() -> void:
	var green = g.new_cbuf(CELL)
	var white = g.new_cbuf(CELL)
	var posts = g.new_cbuf(CELL)
	var rails = g.new_cbuf(CELL)
	var hedge = g.new_cbuf(CELL)
	var chain = g.new_cbuf(CELL)
	var chain_posts = g.new_cbuf(CELL)
	for b in [green, white, posts, rails, hedge, chain, chain_posts]:
		b.clip = true   # every square a fence reaches runs it; each keeps its own stretch
	var fence_col := _tone("fencegreen")
	var rail_col := _tone("railing")
	var metres := {"fence": 0.0, "railing": 0.0, "hedge": 0.0}
	for kind: String in ["pitch", "school"]:
		for ring: PackedVector2Array in g._rings_near(kind):
			if g._over():
				await g._pause()
			var area: float = g._area(ring)
			if area < 150.0 or (kind == "pitch" and area > 25000.0):
				continue   # (a whole sports park is not fenced round, its pitches are)
			var H := 3.2 if kind == "pitch" else 2.1
			for i in range(ring.size()):
				var a := ring[i]
				var e := ring[(i + 1) % ring.size()]
				var got := _fence_line(green, posts, a, e, H, fence_col, 2.6, false, 2)
				if g._mine((a + e) * 0.5):
					if got > 0.0:
						_mark("fence", (a + e) * 0.5)
					metres["fence"] += got
	for ring: PackedVector2Array in g._rings_near("park"):
		if g._over():
			await g._pause()
		var parea: float = g._area(ring)
		if parea < 200.0 or parea > 40000.0:
			continue   # a city park, not a big open one: those are not railed round
		for i in range(ring.size()):
			var a := ring[i]
			var e := ring[(i + 1) % ring.size()]
			if a.distance_to(e) < 4.0:
				continue
			var mid := (a + e) * 0.5
			var hit: Dictionary = g._nearest_seg(mid, 12.0, true, true)
			if hit.is_empty():
				continue   # only the sides along a street
			var pick := _rnd(Vector2i((mid * 2.0).round()))
			if med and pick < 0.3:
				var m := _fence_line(white, rails, a, e, 1.05, rail_col, 2.4, true, 2)
				if g._mine(mid):
					metres["railing"] += m
					_mark("railing", mid)
			elif pick < (0.55 if med else 0.35):
				var m := _hedge_line(hedge, a, e)
				if g._mine(mid):
					metres["hedge"] += m
					_mark("hedge", mid)
	var k := 1.0 / float(g._city_data.get("scale", 10))
	var all_bars: Array = g._city_data.get("barriers", [])
	for bi: int in g._tile_bars.get(g._tile, []):
		if g._over():
			await g._pause()
		var bar: Array = all_bars[bi]
		var flat: Array = bar[0]
		var kind := String(bar[1])
		for i in range(0, flat.size() - 2, 2):
			var a := Vector2(flat[i], flat[i + 1]) * k
			var e := Vector2(flat[i + 2], flat[i + 3]) * k
			if not g._tile_rect(g._tile).grow(2.0).intersects(Rect2(a, Vector2.ZERO).expand(e).grow(0.5)):
				continue   # a stretch of it nowhere near this square
			if g._over():
				await g._pause()
			var m := 0.0
			if kind == "hedge":
				m = _hedge_line(hedge, a, e)
			elif kind == "fence":
				if med:
					m = _fence_line(green, posts, a, e, 1.8, fence_col, 2.5, false, 2)
				else:
					# Bedford's mapped fences are mostly chain-link: along the highway, round
					# yards and lots (tens of kilometres of them, so a post every other piece)
					m = _fence_line(chain, chain_posts, a, e, 1.8, _tone("pole"), 3.0, false, 2)
			if g._mine(a) and metres.has(kind):
				metres[kind] += m
	for job: Array in [[green, _fence_material("fencegreen", 0.12), FENCE_SEEN], [white, _fence_material("railing", 0.15), FENCE_SEEN * 0.7],
			[posts, g._surface("fencegreen"), FENCE_SEEN], [rails, g._surface("railing"), FENCE_SEEN * 0.7],
			[hedge, g._surface("bush"), FENCE_SEEN * 1.2], [chain, _fence_material("pole", 0.08), FENCE_SEEN * 0.8],
			[chain_posts, g._surface("pole"), FENCE_SEEN * 0.8]]:
		if g._over():
			await g._pause()
		g._add_mesh(job[0], job[1], false, job[2])
	for key: String in metres:
		_count[key + "_m"] = int(_count.get(key + "_m", 0)) + int(metres[key])

func _fence_material(tone: String, gap: float) -> ShaderMaterial:
	if _fence_mats.has(tone):
		return _fence_mats[tone]
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FENCE_SHADER
	m.shader = sh
	m.set_shader_parameter("col", _tone(tone))
	m.set_shader_parameter("gap", gap)
	m.set_meta("tone", tone)
	_fence_mats[tone] = m
	return m

## pieces of the line a-e that are not on a road or in a building, about `step` long
## (roads false: only buildings looked for -- the caller knows it is off the roads, and the
## look for the nearest road is the dear one)
## `body`: how far the thing reaches either side of its line (a hedge 0.4 m): kept that much
## further off the asphalt. A hedge checked with a fence's margins (its middle 0.2 m clear,
## its ends 0.2 m in) stood half a metre into the lane -- city_check found 18 in Givatayim.
func _open_pieces(a: Vector2, e: Vector2, step: float, roads := true, body := 0.0) -> Array:
	var L := a.distance_to(e)
	var n := maxi(1, int(ceil(L / step)))
	var out: Array = []
	# a run of about 8 m whose ends and middle are all clear is taken whole; only a run
	# that touches a road or a building is looked at piece by piece (a school's fence is
	# kilometres of the first kind)
	var per := maxi(1, int(8.0 / maxf(L / n, 0.1)))
	var i := 0
	while i < n:
		var j := mini(i + per, n)
		var q0 := a.lerp(e, float(i) / n)
		var q1 := a.lerp(e, float(j) / n)
		var whole := j - i > 1 and _clear_at(q0, roads, body) and _clear_at(q1, roads, body) and _clear_at((q0 + q1) * 0.5, roads, body)
		for k in range(i, j):
			var p0 := a.lerp(e, float(k) / n)
			var p1 := a.lerp(e, float(k + 1) / n)
			# (a piece by its middle alone could end most of a metre into the road where the
			# fence met it at a slant: the car ran into the end -- its ends too, where roads count)
			if whole or _clear_at((p0 + p1) * 0.5, roads, body) and (not roads or g._off_road(p0, body - 0.2) and g._off_road(p1, body - 0.2)):
				out.append([p0, p1])
		i = j
	return out

func _clear_at(m: Vector2, roads := true, body := 0.0) -> bool:
	return (not roads or g._off_road(m, 0.2 + body)) and g._push_out(m, 0.15, false, false) == Vector2.ZERO

## a see-through panel H high from a to e (the shader draws the bars), a post every
## `post_every` pieces of about `step` metres
func _fence_line(panel, posts, a: Vector2, e: Vector2, H: float, col: Color, step: float, rail := false,
		post_every := 1, base := 0.0) -> float:
	var done := 0.0
	var run := 0.0
	var i := 0
	for pc: Array in _open_pieces(a, e, step):
		var p0: Vector2 = pc[0]
		var p1: Vector2 = pc[1]
		var L := p0.distance_to(p1)
		var y0 := _h(p0) + base   # (base: standing on a wall that high)
		var y1 := _h(p1) + base
		var A := Vector3(p0.x, y0, p0.y)
		var B := Vector3(p1.x, y1, p1.y)
		var up := Vector3.UP * H
		var n := (B - A).cross(Vector3.UP).normalized()
		var u2 := Vector2(H, 0)
		if g._mine(p0):   # (each square along the fence works it out: one records it)
			g.add_wall(p0, p1, 0.06)
		panel.tri(A, B, B + up, n, col, Vector2(run, 0), Vector2(run + L, 0), Vector2(run + L, H), u2)
		panel.tri(A, B + up, A + up, n, col, Vector2(run, 0), Vector2(run + L, H), Vector2(run, H), u2)
		if i % post_every == 0:   # a post: four sides, no ends (nobody sees its top)
			for f: Array in [[Vector3(0.03, 0, 0), Vector3(0, 0, 0.03)], [Vector3(-0.03, 0, 0), Vector3(0, 0, 0.03)],
					[Vector3(0, 0, 0.03), Vector3(0.03, 0, 0)], [Vector3(0, 0, -0.03), Vector3(0.03, 0, 0)]]:
				var o: Vector3 = A + f[0]
				var u: Vector3 = f[1]
				posts.tri(o - u, o + u, o + u + up, (f[0] as Vector3).normalized(), col)
				posts.tri(o - u, o + u + up, o - u + up, (f[0] as Vector3).normalized(), col)
		i += 1
		if rail:   # a solid round top rail on a railing
			_tube(posts, A + up, B + up, 0.035, 0.035, col, 4)
		run += L
		done += L
	return done

## a fence standing on a wall, A to B its foot along the wall's top (laid straight, one
## panel, a post every `post_gap` metres): for the front gardens, whose wall was already
## checked clear and made solid. Takes and returns the distance along for the bars.
func wall_fence(panel, posts, A: Vector3, B: Vector3, H: float, col: Color, post_gap: float, rail: bool,
		run: float) -> float:
	var L := Vector2(A.x, A.z).distance_to(Vector2(B.x, B.z))
	var up := Vector3.UP * H
	var n := (B - A).cross(Vector3.UP).normalized()
	var u2 := Vector2(H, 0)
	panel.tri(A, B, B + up, n, col, Vector2(run, 0), Vector2(run + L, 0), Vector2(run + L, H), u2)
	panel.tri(A, B + up, A + up, n, col, Vector2(run, 0), Vector2(run + L, H), Vector2(run, H), u2)
	var np := maxi(1, int(round(L / post_gap)))
	for k in range(np):   # a post: four sides, no ends (nobody sees its top)
		var o0 := A.lerp(B, float(k) / np)
		for f: Array in [[Vector3(0.03, 0, 0), Vector3(0, 0, 0.03)], [Vector3(-0.03, 0, 0), Vector3(0, 0, 0.03)],
				[Vector3(0, 0, 0.03), Vector3(0.03, 0, 0)], [Vector3(0, 0, -0.03), Vector3(0.03, 0, 0)]]:
			var o: Vector3 = o0 + f[0]
			var u: Vector3 = f[1]
			posts.tri(o - u, o + u, o + u + up, (f[0] as Vector3).normalized(), col)
			posts.tri(o - u, o + u + up, o - u + up, (f[0] as Vector3).normalized(), col)
	if rail:   # a solid round top rail
		_tube(posts, A + up, B + up, 0.035, 0.035, col, 4)
	return run + L

## a hedge from a to e: a clipped green bank about a metre high, its top a little uneven
func _hedge_line(buf, a: Vector2, e: Vector2, roads := true) -> float:
	var done := 0.0
	var col := Color.WHITE
	var pieces := _open_pieces(a, e, 2.5, roads, 0.4)
	for pi in range(pieces.size()):
		var pc: Array = pieces[pi]
		var p0: Vector2 = pc[0]
		var p1: Vector2 = pc[1]
		# an end only where the hedge stops: between two pieces of it the end is inside it
		var open0 := pi == 0 or (pieces[pi - 1][1] as Vector2) != p0
		var open1 := pi == pieces.size() - 1 or (pieces[pi + 1][0] as Vector2) != p1
		var d := (p1 - p0).normalized()
		var s := Vector2(-d.y, d.x)
		if g._mine(p0):
			g.add_wall(p0, p1, 0.4)
		var h0 := 0.9 + _rnd(Vector2i((p0 * 3.0).round())) * 0.35
		var h1 := 0.9 + _rnd(Vector2i((p1 * 3.0).round())) * 0.35
		var y0 := _h(p0)
		var y1 := _h(p1)
		# a trapezium in section: 0.9 wide at the foot, 0.6 at the top
		var lo := [p0 - s * 0.45, p1 - s * 0.45, p1 + s * 0.45, p0 + s * 0.45]
		var hi := [p0 - s * 0.3, p1 - s * 0.3, p1 + s * 0.3, p0 + s * 0.3]
		var Y := [y0, y1, y1, y0]
		var T := [h0, h1, h1, h0]
		var top: Array = []
		var foot: Array = []
		for i in range(4):
			top.append(Vector3((hi[i] as Vector2).x, float(Y[i]) + float(T[i]), (hi[i] as Vector2).y))
			foot.append(Vector3((lo[i] as Vector2).x, float(Y[i]) - 0.05, (lo[i] as Vector2).y))
		buf.tri(top[0], top[1], top[2], Vector3.UP, col)
		buf.tri(top[0], top[2], top[3], Vector3.UP, col)
		for i in range(4):
			if i == 1 and not open1 or i == 3 and not open0:
				continue
			var j := (i + 1) % 4
			var n := Vector3(((lo[i] as Vector2) + (lo[j] as Vector2) - p0 - p1).x, 0.4, ((lo[i] as Vector2) + (lo[j] as Vector2) - p0 - p1).y).normalized()
			buf.tri(foot[i], foot[j], top[j], n, col)
			buf.tri(foot[i], top[j], top[i], n, col)
		done += p0.distance_to(p1)
	return done

## ---- what stands at the kerb ----------------------------------------------------------------
## As a walk down Givatayim's streets has them: bollards -- black with a yellow reflective
## band, now and then white -- a pair either side of each zebra on both pavements, so no
## car parks across the way over; on the main roads a white railing of tubes along the kerb
## instead, 4 m either side of the crossing; a red fire hydrant at the kerb every 130 m or
## so; a grey utility cabinet at the back of the pavement every 150-200 m; a black bin on
## the main and shopping streets. All of it solid to the car (posts).
func kerbside() -> void:
	var kh: float = g.KERB_H
	var bollards: Array = []
	var bollard_white: Array = []
	var rails: Array = []
	var hydrants: Array = []
	var cabinets: Array = []
	var bins: Array = []
	for ni: int in g._tile_nodes.get(g._tile, []):
		if not g._crossing_set.has(ni):
			continue
		if g._over():
			await g._pause()
		var c: Vector2 = g._nodes[ni]
		for e: Vector2i in g._node_roads[ni]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"]:
				continue
			if r["k"] == "service" or FAST.has(r["k"]):
				break
			var pts: PackedVector2Array = r["pts"]
			var d := (pts[mini(e.y + 1, pts.size() - 1)] - pts[maxi(e.y - 1, 0)]).normalized()
			var side := Vector2(-d.y, d.x)
			var hw: float = float(r["w"]) * 0.5
			var railed: bool = med and MAIN.has(r["k"])
			var white: bool = _rnd(ni * 7 + 3) < 0.25 or g._white_bollards.has(ni)   # (or as filmed: details.gd)
			for sg: float in [-1.0, 1.0]:          # both pavements
				for way: float in [-1.0, 1.0]:     # both sides of the zebra
					if railed:   # 1.2 m panels from 2.1 m out to 6 m
						for k in range(3):
							var m := c + d * way * (2.1 + 1.2 * k + 0.6) + side * sg * (hw + 0.42)
							if not _free(m, 0.15, 0.4, 0.5):
								break
							# (its ends too: at a corner the kerb turns away and a panel's end
							# stood out in the road)
							var ends_ok := true
							for q: Vector2 in [m - d * 0.6, m + d * 0.6]:
								if not g._off_road(q, 0.1) or g._in_junction(q, 0.1):
									ends_ok = false
							if not ends_ok:
								break
							rails.append(Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3(m.x, _h(m) + kh, m.y)))
							g._add_post(m - d * 0.6, 0.06)
							g._add_post(m + d * 0.6, 0.06)
					else:
						for k in range(2):
							var p := c + d * way * (2.1 + 1.3 * k) + side * sg * (hw + 0.42)
							if _free(p, 0.15, 0.3, 0.7):
								(bollard_white if white else bollards).append(Transform3D(Basis(), Vector3(p.x, _h(p) + kh, p.y)))
								g._add_post(p, 0.11)
			break   # one road is enough: the zebra's own (as the game lays it)
	for ri: int in g._tile_roads.get(g._tile, []):
		var r: Dictionary = g._roads[ri]
		if not r["drive"] or r["pv"] or r["k"] == "service" or FAST.has(r["k"]):
			continue
		if g._over():
			await g._pause()
		var hw: float = float(r["w"]) * 0.5
		var sd := 1.0 if posmod(ri, 2) == 0 else -1.0
		for sp: Array in _walk_road(r, 130.0, 20.0 + _rnd(ri + 11) * 90.0, hw + 0.4, sd, 6.0):
			var p: Vector2 = sp[0]
			if g._mine(p) and _free(p, 0.15, 0.3, 1.2):
				hydrants.append(Transform3D(Basis(Vector3.UP, _rnd(p.round()) * TAU), Vector3(p.x, _h(p) + kh, p.y)))
				g._add_post(p, 0.16)
		var back: float = hw + g.KERB_W + g.PAVE_W - 0.3
		for sp: Array in _walk_road(r, 150.0 + _rnd(ri + 5) * 50.0, 30.0 + _rnd(ri + 17) * 90.0, back, -sd, 10.0):
			var p: Vector2 = sp[0]
			var out: Vector2 = sp[2]
			if g._mine(p) and _free(p, 1.0, 0.45, 1.2):
				cabinets.append(Transform3D(Basis(Vector3.UP, atan2(-out.x, -out.y)), Vector3(p.x, _h(p) + kh, p.y)))
				g._add_post(p, 0.55)
		if MAIN.has(r["k"]) or r["k"] == "residential" and _rnd(ri + 23) < 0.25:
			for sp: Array in _walk_road(r, 75.0, 12.0 + _rnd(ri + 29) * 50.0, hw + 0.55, sd, 8.0):
				var p: Vector2 = sp[0]
				if g._mine(p) and _free(p, 0.2, 0.4, 1.0):
					bins.append(Transform3D(Basis(Vector3.UP, _rnd(p.round() + Vector2(1, 1)) * TAU), Vector3(p.x, _h(p) + kh, p.y)))
					g._add_post(p, 0.3)
					if med and _rnd(p.round() + Vector2(5, 2)) < 0.25:   # a cat by the bin, as there often is
						var d: Vector2 = sp[1]
						var c := p + d * (0.5 if _rnd(p.round() + Vector2(2, 9)) < 0.5 else -0.5)
						g.cat_at(c, _h(c) + kh, -(sp[2] as Vector2).rotated((_rnd(p.round() + Vector2(4, 4)) - 0.5) * 2.0), "sit")
	await _place(_bollard_kit(false), bollards, NEAR_SEEN * 1.2, "bollards")
	await _place(_bollard_kit(true), bollard_white, NEAR_SEEN * 1.2, "bollards_white")
	await _place(_rail_kit(), rails, NEAR_SEEN * 1.3, "railings_at_crossings")
	await _place(_hydrant_kit(), hydrants, NEAR_SEEN, "hydrants")
	await _place(_cabinet_kit(), cabinets, SEEN * 0.6, "cabinets", true)
	await _place(_bin_kit(), bins, NEAR_SEEN, "bins")
	if med:
		await _recycling()

## ---- recycling -----------------------------------------------------------------------------
## By one junction in six of the residential streets, at the back of the pavement a few metres
## round the corner, as Givatayim has them: a big blue bin for paper, often an orange cage for
## packaging beside it, now and then a purple bell for glass. Solid (posts).
func _recycling() -> void:
	var paper: Array = []
	var cages: Array = []
	var glass: Array = []
	for ni: int in g._tile_nodes.get(g._tile, []):
		if (g._node_roads[ni] as Array).size() < 3 or _rnd(ni * 13 + 5) > 0.25:
			continue
		if g._over():
			await g._pause()
		var c: Vector2 = g._nodes[ni]
		for e: Vector2i in g._node_roads[ni]:
			var r: Dictionary = g._roads[e.x]
			if not r["drive"] or not (r["k"] in ["residential", "living_street", "tertiary"]):
				continue
			var pts: PackedVector2Array = r["pts"]
			var nb := e.y + 1 if e.y + 1 < pts.size() else e.y - 1
			var d := (pts[nb] - pts[e.y]).normalized()   # away from the junction
			var side := Vector2(-d.y, d.x) * (1.0 if _rnd(ni * 7 + 1) < 0.5 else -1.0)
			var back: float = float(r["w"]) * 0.5 + g.KERB_W + g.PAVE_W - 0.5
			var at := c + d * (float(g._node_r[ni]) + 7.0 + _rnd(ni * 3 + 2) * 6.0) + side * back
			var face := Basis(Vector3.UP, atan2(-side.x, -side.y))   # front to the street
			var kinds := ["paper"]
			if _rnd(ni * 11 + 3) < 0.6:
				kinds.append("cage")
			if _rnd(ni * 17 + 9) < 0.3:
				kinds.append("glass")
			var k := 0
			for kind: String in kinds:
				var p := at + d * (float(k) * 1.35)
				if not (g._mine(p) and _free(p, 0.6, 0.6, 0.9)):
					continue
				var xf := Transform3D(face, Vector3(p.x, _h(p) + g.KERB_H, p.y))
				(paper if kind == "paper" else (cages if kind == "cage" else glass)).append(xf)
				g._add_post(p, 0.55 if kind != "glass" else 0.5)
				k += 1
			break   # one corner of the junction
	await _place(_paper_bin_kit(), paper, NEAR_SEEN * 1.2, "recycle_paper")
	await _place(_cage_kit(), cages, NEAR_SEEN * 1.2, "recycle_cages")
	await _place(_glass_bell_kit(), glass, NEAR_SEEN * 1.2, "recycle_glass")

## the paper bin: a blue box 1.0 x 0.8 x 1.3 m, its lid a shade darker, a slot on the front
## (+Z) and a white label over it
func _paper_bin_kit() -> ArrayMesh:
	if _kits.has("paper_bin"):
		return _kits["paper_bin"]
	var b = g.new_buf()
	var blue: Color = _tone("signblue")
	_box(b, Vector3(0, 0.62, 0), Vector3(1.0, 1.2, 0.8), blue)
	_box(b, Vector3(0, 1.26, 0), Vector3(1.04, 0.1, 0.84), blue.darkened(0.25))
	_box(b, Vector3(0, 1.0, 0.401), Vector3(0.6, 0.07, 0.01), _tone("tyre"))
	_box(b, Vector3(0, 0.78, 0.401), Vector3(0.42, 0.18, 0.01), _tone("mark"))
	for sx: float in [-0.42, 0.42]:   # its wheels' housings
		_box(b, Vector3(sx, 0.06, 0.25), Vector3(0.1, 0.12, 0.16), _tone("tyre"))
	var am: ArrayMesh = _mesh(b)
	_kits["paper_bin"] = am
	return am

## the packaging cage: an orange frame 1.1 x 0.9 x 1.6 m, open bars all round
func _cage_kit() -> ArrayMesh:
	if _kits.has("cage"):
		return _kits["cage"]
	var b = g.new_buf()
	var orange: Color = Palette.col("hazard").lerp(Palette.col("warn"), 0.55)
	var hw := 0.55
	var hd := 0.45
	var H := 1.6
	for y: float in [0.05, H * 0.5, H]:   # rims
		_box(b, Vector3(0, y, hd), Vector3(2 * hw, 0.05, 0.05), orange)
		_box(b, Vector3(0, y, -hd), Vector3(2 * hw, 0.05, 0.05), orange)
		_box(b, Vector3(hw, y, 0), Vector3(0.05, 0.05, 2 * hd), orange)
		_box(b, Vector3(-hw, y, 0), Vector3(0.05, 0.05, 2 * hd), orange)
	for i in range(7):   # the bars, front and back
		var x := -hw + 2.0 * hw * float(i) / 6.0
		_box(b, Vector3(x, H * 0.5, hd), Vector3(0.025, H, 0.025), orange)
		_box(b, Vector3(x, H * 0.5, -hd), Vector3(0.025, H, 0.025), orange)
	for i in range(1, 5):   # and the sides
		var z := -hd + 2.0 * hd * float(i) / 5.0
		_box(b, Vector3(hw, H * 0.5, z), Vector3(0.025, H, 0.025), orange)
		_box(b, Vector3(-hw, H * 0.5, z), Vector3(0.025, H, 0.025), orange)
	# what is in it: a heap of plastic bottles and cartons, a lighter mass half way up
	_box(b, Vector3(0, 0.32, 0), Vector3(2 * hw - 0.1, 0.55, 2 * hd - 0.1), _tone("mark").lerp(_tone("signblue"), 0.15))
	_box(b, Vector3(0.1, 0.68, -0.05), Vector3(0.7, 0.2, 0.55), _tone("mark").lerp(orange, 0.2))
	var am: ArrayMesh = _mesh(b)
	_kits["cage"] = am
	return am

## the glass bell: a purple dome 1.4 m high, a round mouth near the top
func _glass_bell_kit() -> ArrayMesh:
	if _kits.has("glass_bell"):
		return _kits["glass_bell"]
	var b = g.new_buf()
	var purple: Color = _natural(Palette.col("prize"), 0.7)
	_tube(b, Vector3(0, 0, 0), Vector3(0, 1.1, 0), 0.55, 0.45, purple, 12)
	_tube(b, Vector3(0, 1.1, 0), Vector3(0, 1.4, 0), 0.45, 0.12, purple.darkened(0.08), 12)
	_box(b, Vector3(0, 1.05, 0.47), Vector3(0.2, 0.2, 0.02), _tone("tyre"))   # the mouth
	var am: ArrayMesh = _mesh(b)
	_kits["glass_bell"] = am
	return am

## a palette colour with only `keep` of its saturation (as the game's own _natural)
func _natural(c: Color, keep: float) -> Color:
	return g._natural(c, keep)

## a bollard, 0.85 m: black with a yellow reflective band near the top, or plain white
func _bollard_kit(white: bool) -> ArrayMesh:
	var key := "bollard%s" % white
	if _kits.has(key):
		return _kits[key]
	var b = g.new_buf()
	var body: Color = _tone("mark") if white else _tone("cartrim").darkened(0.35)
	var band: Color = _tone("mark").darkened(0.15) if white else _tone("markyellow")
	_tube(b, Vector3.ZERO, Vector3(0, 0.6, 0), 0.095, 0.09, body, 10)
	_tube(b, Vector3(0, 0.6, 0), Vector3(0, 0.7, 0), 0.091, 0.091, band, 10)
	_tube(b, Vector3(0, 0.7, 0), Vector3(0, 0.82, 0), 0.09, 0.085, body, 10)
	_tube(b, Vector3(0, 0.82, 0), Vector3(0, 0.86, 0), 0.085, 0.03, body, 10)   # its rounded top
	var am: ArrayMesh = _mesh(b)
	_kits[key] = am
	return am

## a 1.2 m panel of pedestrian railing along local X: white tubes, posts at each end, a top
## rail and one lower down
func _rail_kit() -> ArrayMesh:
	if _kits.has("rail"):
		return _kits["rail"]
	var b = g.new_buf()
	var col: Color = _tone("railing")
	for x: float in [-0.6, 0.6]:
		_tube(b, Vector3(x, 0, 0), Vector3(x, 0.98, 0), 0.03, 0.03, col, 6)
	_tube(b, Vector3(-0.6, 0.95, 0), Vector3(0.6, 0.95, 0), 0.025, 0.025, col, 6)
	_tube(b, Vector3(-0.6, 0.45, 0), Vector3(0.6, 0.45, 0), 0.02, 0.02, col, 6)
	for x: float in [-0.3, 0.0, 0.3]:   # the hoops' uprights between
		_tube(b, Vector3(x, 0.45, 0), Vector3(x, 0.95, 0), 0.015, 0.015, col, 5)
	var am: ArrayMesh = _mesh(b)
	_kits["rail"] = am
	return am

## a fire hydrant, red: its body, the dome on top, an outlet each side and one to the front
func _hydrant_kit() -> ArrayMesh:
	if _kits.has("hydrant"):
		return _kits["hydrant"]
	var b = g.new_buf()
	var red: Color = _tone("signred")
	_tube(b, Vector3.ZERO, Vector3(0, 0.08, 0), 0.15, 0.15, red.darkened(0.2), 10)   # the flange
	_tube(b, Vector3(0, 0.08, 0), Vector3(0, 0.55, 0), 0.11, 0.1, red, 10)
	_tube(b, Vector3(0, 0.55, 0), Vector3(0, 0.66, 0), 0.12, 0.05, red, 10)
	_tube(b, Vector3(0, 0.66, 0), Vector3(0, 0.71, 0), 0.03, 0.02, red.darkened(0.3), 6)
	for dx: float in [-1.0, 1.0]:
		_tube(b, Vector3(0.08 * dx, 0.38, 0), Vector3(0.19 * dx, 0.38, 0), 0.045, 0.045, red, 8)
	_tube(b, Vector3(0, 0.3, 0.08), Vector3(0, 0.3, 0.18), 0.06, 0.06, red, 8)
	var am: ArrayMesh = _mesh(b)
	_kits["hydrant"] = am
	return am

## a utility cabinet: grey sheet metal on a concrete plinth, its doors' seam and a vent,
## facing +Z
func _cabinet_kit() -> ArrayMesh:
	if _kits.has("cabinet"):
		return _kits["cabinet"]
	var b = g.new_buf()
	var grey: Color = _tone("pole").lerp(_tone("mark"), 0.25)
	_box(b, Vector3(0, 0.06, 0), Vector3(1.1, 0.12, 0.5), _tone("concrete") if g._tone.has("concrete") else grey.darkened(0.2))
	_box(b, Vector3(0, 0.77, 0), Vector3(1.0, 1.3, 0.4), grey)
	_box(b, Vector3(0, 1.45, 0), Vector3(1.06, 0.06, 0.46), grey.darkened(0.12))   # its lid
	_box(b, Vector3(0, 0.77, 0.205), Vector3(0.015, 1.2, 0.01), grey.darkened(0.45))   # the doors' seam
	_box(b, Vector3(0.3, 1.2, 0.205), Vector3(0.25, 0.12, 0.01), grey.darkened(0.3))  # a vent
	var am: ArrayMesh = _mesh(b)
	_kits["cabinet"] = am
	return am

## a street bin: a dark drum on a short post, a ring round its mouth
func _bin_kit() -> ArrayMesh:
	if _kits.has("bin"):
		return _kits["bin"]
	var b = g.new_buf()
	var dark: Color = _tone("cartrim").darkened(0.3)
	_tube(b, Vector3.ZERO, Vector3(0, 0.25, 0), 0.04, 0.04, dark, 6)
	_tube(b, Vector3(0, 0.25, 0), Vector3(0, 0.9, 0), 0.22, 0.25, dark, 12)
	_tube(b, Vector3(0, 0.88, 0), Vector3(0, 0.93, 0), 0.26, 0.26, dark.lightened(0.15), 12)
	var am: ArrayMesh = _mesh(b)
	_kits["bin"] = am
	return am

## A tree pit of bare earth, 1.1 m square, its edge a low concrete kerb along the street (+Z),
## dead leaves on the soil and a black drip hose looped round the trunk
func pit_kit() -> ArrayMesh:
	if _kits.has("pit"):
		return _kits["pit"]
	var b = g.new_buf()
	var soil: Color = _tone("ground").darkened(0.42)
	var edge: Color = _tone("kerb")
	var hose: Color = _tone("tyre")
	var leaf: Color = _tone("ground").lerp(_tone("woodfence"), 0.5)
	var s := 0.55
	b.flat(Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s), 0.012, soil)   # (just over the pavers: under them it was not seen)
	for side: int in range(4):   # the edging: 7 cm wide, its top 3 cm over the pavers
		var bs := Basis(Vector3.UP, PI * 0.5 * side)
		_box(b, bs * Vector3(0, 0.02, s + 0.035), Vector3(2.0 * s + 0.14, 0.07, 0.07), edge, bs)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in range(14):   # leaves on the soil
		var c := Vector3(rng.randf_range(-s + 0.05, s - 0.05), 0.016, rng.randf_range(-s + 0.05, s - 0.05))
		if Vector2(c.x, c.z).length() < 0.2:
			continue
		var a := rng.randf() * TAU
		var u := Vector3(cos(a), 0, sin(a)) * 0.05
		var w := Vector3(-sin(a), 0, cos(a)) * 0.025
		b.tri(c - u, c + w, c + u, Vector3.UP, leaf.darkened(rng.randf() * 0.3))
		b.tri(c - u, c + u, c - w, Vector3.UP, leaf.darkened(rng.randf() * 0.3))
	var prev := Vector3.ZERO
	for i in range(13):   # the hose, round the trunk and away under the edge
		var a := TAU * i / 12.0
		var p := Vector3(cos(a) * 0.32, 0.024, sin(a) * 0.32)
		if i > 0:
			_tube(b, prev, p, 0.009, 0.009, hose, 4)
		prev = p
	_tube(b, Vector3(0.32, 0.024, 0), Vector3(0.32, 0.024, s + 0.08), 0.009, 0.009, hose, 4)
	var am: ArrayMesh = _mesh(b)
	_kits["pit"] = am
	return am

## an iron tree grate round a street tree's trunk, flat on the pavement: a ring of slots
## round a plain rim, the soil showing in the middle (for the game's street trees)
func grate_kit() -> ArrayMesh:
	if _kits.has("grate"):
		return _kits["grate"]
	var b = g.new_buf()
	var iron: Color = _tone("metal")
	var soil: Color = _tone("ground").darkened(0.35)
	var seg := 16
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var u0 := Vector3(cos(a0), 0, sin(a0))
		var u1 := Vector3(cos(a1), 0, sin(a1))
		for ring: Array in [[0.0, 0.24, soil], [0.24, 0.32, iron], [0.32, 0.52, iron.darkened(0.35)], [0.52, 0.62, iron]]:
			var r0: float = ring[0]
			var r1: float = ring[1]
			var col: Color = ring[2]
			if ring[1] == 0.52 and i % 2 == 0:
				col = iron   # the bars between the slots
			b.tri(u0 * r0, u1 * r0, u1 * r1, Vector3.UP, col)
			b.tri(u0 * r0, u1 * r1, u0 * r1, Vector3.UP, col)
	var am: ArrayMesh = _mesh(b)
	_kits["grate"] = am
	return am

## ---- bike racks and scooters ----------------------------------------------------------------
## By the kerb in front of shops, cafes, schools and the library: a rack of three hoops,
## often with a bike or two in it; and in Givatayim, a few scooters parked nose-in.
func street_life() -> void:
	var racks: Array = []
	var bikes: Array = []
	var bike_cols: Array = []
	var scooters: Array = []
	var scooter_cols: Array = []
	var bike_paint := [Palette.col("hazard").lerp(Palette.col("bg"), 0.3), _tone("signblue"), _tone("mark"), _tone("cartrim")]
	# (a red scooter is a paint's red: the palette's hazard, pink here, made pink scooters)
	var hz := Palette.col("hazard")
	var red := Color.from_hsv(0.99, clampf(hz.s, 0.55, 0.8), clampf(hz.v * 0.62, 0.35, 0.6))
	var scooter_paint := [_tone("mark"), _tone("cartrim"), red, _tone("rim")]
	var k := 1.0 / float(g._city_data.get("scale", 10))
	var taken := _life_taken
	var all_pois: Array = g._city_data.get("pois", [])
	for pi: int in g._tile_pois.get(g._tile, []):
		var p: Array = all_pois[pi]
		var kind := String(p[2])
		if not (kind.begins_with("shop:") or kind in ["cafe", "restaurant", "fast_food", "ice_cream", "bar", "pub",
				"school", "library", "bank", "pharmacy", "community_centre"]):
			continue
		var at := Vector2(p[0], p[1]) * k
		var cell := Vector2i((at / 25.0).round())
		if taken.has(cell):
			continue
		taken[cell] = true
		if g._over():
			await g._pause()
		var hit: Dictionary = g._nearest_seg(at, 40.0, true, true)
		if hit.is_empty():
			continue
		var r: Dictionary = g._roads[hit["road"]]
		if FAST.has(r["k"]):
			continue
		var q: Vector2 = hit["q"]
		var out := (at - q).normalized()
		if out == Vector2.ZERO:
			continue
		var pts: PackedVector2Array = r["pts"]
		var sj: int = hit["seg"]
		var d := (pts[sj + 1] - pts[sj]).normalized()
		var kerb := q + out * (float(r["w"]) * 0.5 + 0.75)
		var back := q + out * (float(r["w"]) * 0.5 + 1.25)   # a bike sticks out 0.85 m each side
		var roll := _rnd(cell)
		if roll < 0.4 or (kind in ["school", "library"]):
			# a rack: hoops square to the kerb, 0.8 m apart
			var placed := 0
			for i in range(3):
				var s := back + d * (float(i) - 1.0) * 0.8
				if not _free(s, 0.5, 0.7, 0.6):
					continue
				var gy := _h(s)
				var bs := Basis(Vector3.UP, atan2(-out.y, out.x))   # local X across the kerb
				racks.append(Transform3D(bs, Vector3(s.x, gy, s.y)))
				g._add_post(s, 0.35)
				placed += 1
				if _rnd(cell + Vector2i(i, 7)) < 0.55:
					bikes.append(Transform3D(bs, Vector3(s.x, gy, s.y) + Vector3(d.x, 0, d.y) * 0.28))
					bike_cols.append(bike_paint[int(_rnd(cell + Vector2i(i, 9)) * 4.0) % 4])
		if med and roll > 0.35:
			# scooters, nose to the kerb, a little skew
			var many := 1 + int(_rnd(cell + Vector2i(3, 3)) * 3.0)
			var along := 3.0 if roll < 0.4 else 0.0
			for i in range(many):
				var s := kerb + d * (along + float(i) * 0.9) + out * 0.3
				if not _free(s, 0.45, 0.8, 0.8):
					continue
				var gy := _h(s)
				var look := (-out).rotated(0.25 * (1.0 if i % 2 == 0 else -1.0))
				var bs := Basis(Vector3.UP, atan2(look.x, look.y))
				scooters.append(Transform3D(bs, Vector3(s.x, gy, s.y)))
				scooter_cols.append(scooter_paint[int(_rnd(cell + Vector2i(i, 1)) * 4.0) % 4])
				g._add_post(s, 0.45)
	await _place(_rack_kit(), racks, NEAR_SEEN, "bike_racks")
	await _place(_bike_kit(), bikes, NEAR_SEEN, "bikes", false, bike_cols)
	await _place(_scooter_kit(), scooters, NEAR_SEEN * 1.2, "scooters", false, scooter_cols)

## ---- street cats ---------------------------------------------------------------------------
## Givatayim's strays, as a walk down its streets has them: sitting on a garden wall or curled
## up on it, by the bins, on the pavement at a parked car's nose (the game picks the spots:
## cat_at). A few ellipsoids and tubes, white and pale grey with tabby stripes, that each
## cat's coat (its instance colour) tints -- ginger, grey, black, cream, brown. They hold
## still, as street cats mostly do: nothing to do per frame, and merged into the batches like
## the rest of the kit (no draws of their own).
const CAT_COATS := ["cat_ginger", "cat_ginger", "cat_grey", "cat_black", "cat_cream", "cat_brown", "cat_grey", "cat_ginger"]

func cats() -> void:
	for kind: String in ["sit", "loaf"]:
		var xf: Array = []
		var cols: Array = []
		for c: Array in g._cat_spots:
			if c[1] == kind:
				xf.append(c[0])
				cols.append(_tone(CAT_COATS[int(c[2]) % CAT_COATS.size()]))
		await _place(_cat_kit(kind), xf, NEAR_SEEN * 0.7, "cats_" + kind, false, cols)

## an ellipsoid of radii r round c, turned by bs; `stripes`: every other strip of its upper
## half darker (a tabby's)
func _ellipsoid(b, c: Vector3, r: Vector3, col: Color, bs := Basis(), stripes := false, seg := 7, rings := 4) -> void:
	var P := func(i: int, j: int) -> Vector3:
		var la := -PI * 0.5 + PI * j / rings
		var lo := TAU * i / seg
		return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
	for j in range(rings):
		for i in range(seg):
			var u := [P.call(i, j), P.call(i + 1, j), P.call(i + 1, j + 1), P.call(i, j + 1)]
			var w: Array = []
			for q: Vector3 in u:
				w.append(c + bs * (q * r))
			var n := (bs * (((u[0] + u[2]) as Vector3) * 0.5 / r)).normalized()
			var k := col
			if stripes and j >= rings / 2 and i % 2 == 0:
				k = col * 0.72
			k = Color(k.r, k.g, k.b) * (0.86 if n.y > 0.55 else 1.0)   # (the back a shade darker)
			b.tri(w[0], w[1], w[2], n, k)
			b.tri(w[0], w[2], w[3], n, k)

## an ear: a thin pyramid from a base round `at` up to `tip`
func _ear(b, at: Vector3, tip: Vector3, col: Color) -> void:
	var s := Vector3(0.022, 0, 0)
	var f := Vector3(0, 0, 0.012)
	var base := [at - s - f, at + s - f, at + f]
	for i in range(3):
		var p0: Vector3 = base[i]
		var p1: Vector3 = base[(i + 1) % 3]
		b.tri(p0, p1, tip, (p0 + p1 - at * 2.0).normalized() + Vector3.UP * 0.3, col)

## a cat facing +Z, its feet at y 0: "sit" (upright on its haunches, about 30 cm tall, the
## tail round its paws) or "loaf" (lying with its paws tucked under, 40 cm long)
func _cat_kit(kind: String) -> ArrayMesh:
	var key := "cat_" + kind
	if _kits.has(key):
		return _kits[key]
	var b = g.new_buf()
	var fur := Color(0.84, 0.84, 0.84)   # (vertex colours are stored 0..1: the fur below white,
	var pale := Color(1.0, 0.98, 0.94)   # so the muzzle and chest can be lighter)
	var dark := Color(0.06, 0.06, 0.05)   # eyes and nose: not tinted by the coat
	var head := Vector3(0, 0.275, 0.055)
	if kind == "sit":
		_ellipsoid(b, Vector3(0, 0.075, -0.03), Vector3(0.09, 0.075, 0.10), fur, Basis(), true)          # haunches
		_ellipsoid(b, Vector3(0, 0.16, 0.025), Vector3(0.062, 0.1, 0.06), fur, Basis(Vector3.RIGHT, 0.25), true)   # chest
		_ellipsoid(b, Vector3(0, 0.17, 0.06), Vector3(0.04, 0.06, 0.03), pale)                          # bib
		for sx: float in [-1.0, 1.0]:   # front legs
			_tube(b, Vector3(0.028 * sx, 0.13, 0.06), Vector3(0.03 * sx, 0.0, 0.075), 0.017, 0.015, fur, 5)
		# the tail, along the ground round the front paws
		var tail := [Vector3(0.0, 0.03, -0.12), Vector3(0.08, 0.02, -0.08), Vector3(0.11, 0.016, 0.0),
			Vector3(0.09, 0.016, 0.07), Vector3(0.045, 0.016, 0.1)]
		for i in range(tail.size() - 1):
			_tube(b, tail[i], tail[i + 1], 0.019, 0.017, fur if i % 2 == 0 else fur * 0.72, 5)
	else:
		head = Vector3(0, 0.14, 0.17)
		_ellipsoid(b, Vector3(0, 0.075, 0.0), Vector3(0.095, 0.075, 0.17), fur, Basis(), true)          # the loaf
		_ellipsoid(b, Vector3(0, 0.06, 0.13), Vector3(0.05, 0.045, 0.04), pale)                          # chest, paws tucked
		var tail := [Vector3(-0.06, 0.02, -0.15), Vector3(-0.1, 0.018, -0.04), Vector3(-0.1, 0.018, 0.07)]
		for i in range(tail.size() - 1):
			_tube(b, tail[i], tail[i + 1], 0.019, 0.017, fur if i % 2 == 0 else fur * 0.72, 5)
	_ellipsoid(b, head, Vector3(0.058, 0.052, 0.056), fur, Basis(), true)
	_ellipsoid(b, head + Vector3(0, -0.013, 0.05), Vector3(0.027, 0.02, 0.02), pale)   # muzzle
	_ellipsoid(b, head + Vector3(0, -0.006, 0.068), Vector3(0.007, 0.005, 0.004), dark, Basis(), false, 4, 2)   # nose
	for sx: float in [-1.0, 1.0]:
		_ear(b, head + Vector3(0.033 * sx, 0.038, -0.004), head + Vector3(0.045 * sx, 0.085, -0.01), fur)
		_ellipsoid(b, head + Vector3(0.022 * sx, 0.012, 0.05), Vector3(0.009, 0.007, 0.005), dark, Basis(), false, 4, 2)   # eyes
	var am: ArrayMesh = _mesh(b)
	_kits[key] = am
	return am

## a hoop of tube, its plane across local X (bikes go in along X)
func _rack_kit() -> ArrayMesh:
	var b = g.new_buf()
	var col := _tone("rim")
	var pts: Array = []
	for i in range(7):
		var t := PI * i / 6.0
		pts.append(Vector3(cos(t) * 0.35, 0.6 + sin(t) * 0.25, 0))
	_tube(b, Vector3(0.35, 0, 0), pts[0], 0.03, 0.03, col, 5)
	for i in range(6):
		_tube(b, pts[i], pts[i + 1], 0.03, 0.03, col, 5)
	_tube(b, pts[6], Vector3(-0.35, 0, 0), 0.03, 0.03, col, 5)
	return _mesh(b)

## a bike standing in a rack: two wheels, a frame, saddle and bars, along local X (the
## frame is white: each copy's colour paints it)
func _bike_kit() -> ArrayMesh:
	var b = g.new_buf()
	var frame := Color.WHITE
	var tyre := _tone("tyre")
	for cx: float in [-0.52, 0.52]:
		var prev := Vector3(cx + 0.33, 0.34, 0)
		for i in range(1, 11):
			var t := TAU * i / 10.0
			var q := Vector3(cx + cos(t) * 0.33, 0.34 + sin(t) * 0.33, 0)
			_tube(b, prev, q, 0.025, 0.025, tyre, 4)
			prev = q
	var rear := Vector3(-0.52, 0.34, 0)
	var front := Vector3(0.52, 0.34, 0)
	var crank := Vector3(-0.05, 0.3, 0)
	var seat := Vector3(-0.2, 0.82, 0)
	var head := Vector3(0.38, 0.82, 0)
	for pair: Array in [[rear, crank], [crank, seat], [seat, rear], [crank, head], [seat, head], [head, front]]:
		_tube(b, pair[0], pair[1], 0.022, 0.022, frame, 4)
	_box(b, seat + Vector3(0, 0.08, 0), Vector3(0.24, 0.05, 0.1), tyre)
	_tube(b, head, head + Vector3(0, 0.14, 0), 0.02, 0.02, frame, 4)
	_tube(b, head + Vector3(0, 0.14, -0.26), head + Vector3(0, 0.14, 0.26), 0.018, 0.018, tyre, 4)
	return _mesh(b)

## a scooter, nose along local +Z: two small wheels, the floor, the leg shield and the
## seat over the engine (the body is white: each copy's colour paints it)
func _scooter_kit() -> ArrayMesh:
	var b = g.new_buf()
	var body := Color.WHITE
	var dark := _tone("tyre")
	var trim := _tone("rim")
	for z: float in [-0.58, 0.62]:
		_tube(b, Vector3(-0.06, 0.22, z), Vector3(0.06, 0.22, z), 0.22, 0.22, dark, 8)
	_box(b, Vector3(0, 0.33, 0.05), Vector3(0.36, 0.08, 0.7), body)              # the floor
	_box(b, Vector3(0, 0.72, 0.42), Vector3(0.42, 0.75, 0.12), body, Basis(Vector3.RIGHT, -0.2))   # leg shield
	_box(b, Vector3(0, 0.55, -0.4), Vector3(0.42, 0.42, 0.62), body)             # over the engine
	_box(b, Vector3(0, 0.8, -0.35), Vector3(0.34, 0.1, 0.62), dark)              # the seat
	_tube(b, Vector3(0, 0.75, 0.5), Vector3(0, 1.08, 0.55), 0.03, 0.03, trim, 4)
	_tube(b, Vector3(-0.32, 1.1, 0.55), Vector3(0.32, 1.1, 0.55), 0.025, 0.025, dark, 4)
	_box(b, Vector3(0, 1.08, 0.6), Vector3(0.22, 0.1, 0.1), body)                # the headlamp
	_box(b, Vector3(0, 0.62, -0.75), Vector3(0.3, 0.12, 0.1), Palette.col("hazard"))   # tail light
	return _mesh(b)
