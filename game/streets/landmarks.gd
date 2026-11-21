extends RefCounted
## A town's landmarks: what it is known by, that OSM draws as one more box. Each is found by
## its building's name in the bake (BY_CITY, this game's towns only); a named outline is
## often only the podium, the tower a part on it, so it is the tallest building standing in
## that outline that gets it. And in every town the red lights on a tall building's roof at
## night (aviation obstruction lights): a city's skyline at night is mostly those.
##
## What a landmark can have:
##   "glass": n       its curtain wall in one glass tone (0-3: the shader's glass, glass_b ..
##                    glass_d), not the one its outline's hash picks
##   "crown": [a, b]  a band round its top from a to b metres under the roof: metal by day,
##                    lit at night (Azrieli's tops are lit)
##   "shaft": [to, w] a concrete shaft on its roof, w square, up to `to` metres over the
##                    ground, with two antenna platforms round it
##   "mast": [to, w, striped]  a mast on the roof (or on the shaft) up to `to` m over the ground, w thick,
##                    red and white bands if striped, a red light at its tip
## "market": [[street name, kind], ...] -- stalls down both sides of each such piece of street,
##   a walkway kept down its middle: a counter of produce in crates, a rack of goods behind,
##   poles and a sloping canvas over it (the Carmel market, down HaCarmel's pedestrian street)
## "tiles": rectangles whose small houses (a footprint FOOT_MIN-FOOT_MAX m2, no taller than
##   TILE_MAX) get pitched red tile roofs over two old storeys' walls (Sarona's Templer
##   houses, restored among the towers)
##
## Sources for the heights: OSM's outlines and heights where it has them, else the city's
## own survey (tools/osm_city.py's SURVEYS); the Marganit
## tower's mast to 138 m and the Matcal tower's to 107 m are Wikipedia's figures.

const BY_CITY := {
	"tel_aviv": {
		"landmarks": [
			["עזריאלי עגול", {"glass": 1, "crown": [1.0, 7.0]}],     # Azrieli: the round tower
			["עזריאלי משולש", {"glass": 1, "crown": [1.0, 6.0]}],    # the triangular one
			["עזריאלי מרובע", {"glass": 1, "crown": [1.0, 6.0]}],    # the square one
			["מגדל המטכ\"ל", {"mast": [107.0, 1.2, false]}],         # the Matcal tower, HaKirya
			["מגדל מרגנית", {"shaft": [118.0, 7.0], "mast": [138.0, 1.6, true]}],   # Marganit: the IDF's radio tower
			["מגדל שלום מאיר", {"mast": [142.0, 1.0, false]}],    # Shalom Meir (1965): the antenna on its roof
			["מגדל האופרה", {}],   # the Opera tower by the sea: OSM draws its stepped floors in their stone
		],
		"market": [["הכרמל", "pedestrian"]],   # the Carmel market
		"tiles": [Rect2(-560, 180, 400, 230)],   # Sarona
	},
}
const LAMP_H := 90.0          ## a building this tall (over its ground) carries red lights on its roof
const FOOT_MIN := 80.0
const FOOT_MAX := 450.0
const TILE_MAX := 16.0       ## (the city's survey measures a pitched roof to its ridge: two storeys of Sarona come out 9-16 m)
const SEEN := 2600.0          ## the night's red lights, seen from across the town

var g: Node
var _tile_items := {}         ## square -> [[kind, building index, what], ...]
var _mats := {}
var _lit: Array = []          ## [material, colour by night] lit at night
var count := {}               ## what was found: for the tests
var found: Array = []         ## [name, building, its height, where, what] per landmark (the
                              ## city's file is let go of once it is built)

func _init(game: Node) -> void:
	g = game

func setup(data: Dictionary, city: String) -> void:
	var blds: Array = data["buildings"]
	var cfg: Dictionary = BY_CITY.get(city, {})
	for lm: Array in cfg.get("landmarks", []):
		var bi := _tallest_in(blds, String(lm[0]))
		if bi < 0:
			push_warning("landmarks: no building named %s" % lm[0])
			continue
		var what: Dictionary = lm[1]
		if what.has("glass"):
			blds[bi]["_glass"] = int(what["glass"])
		_add(bi, ["landmark", bi, what])
		count["landmarks"] = int(count.get("landmarks", 0)) + 1
		found.append([lm[0], bi, float(blds[bi]["_h"]), Vector2i(_mid(blds[bi]["_ring"])), what])
	for box: Rect2 in cfg.get("tiles", []):
		for bi in range(blds.size()):
			var bd: Dictionary = blds[bi]
			var ring: PackedVector2Array = bd["_ring"]
			if ring.size() < 3 or not box.has_point(_mid(ring)) or float(bd["_base"]) > 0.0 or float(bd["_h"]) > TILE_MAX:
				continue
			var foot := absf(_area(ring))
			if foot < FOOT_MIN or foot > FOOT_MAX:
				continue
			bd["_tile"] = true
			bd["_h"] = clampf(float(bd["_h"]), 5.5, 7.5)   # (two storeys under the eaves)
			g._bld_top[bi] = bd["_h"]
			count["tiled"] = int(count.get("tiled", 0)) + 1
	for mk: Array in cfg.get("market", []):
		_market_line(String(mk[0]), String(mk[1]))
	for bi in range(blds.size()):
		if float(blds[bi]["_h"]) >= LAMP_H:
			_add(bi, ["lamps", bi, {}])
			count["lit_roofs"] = int(count.get("lit_roofs", 0)) + 1

const STALL_STEP := 2.7       ## a stall every this many metres along the street, each side
const STALL_GAP := 7          ## every so many places on a side left open (a doorway, an alley)

## stalls down both sides of each piece of street so named: one item per stall, in the square
## it stands in, [where, along, out (away from the walkway), seed]
func _market_line(name: String, kind: String) -> void:
	for r: Dictionary in g._roads:
		if String(r["name"]) != name or String(r["k"]) != kind:
			continue
		var pts: PackedVector2Array = r["pts"]
		var off := clampf(float(r["w"]) * 0.5 - 0.95, 1.6, 2.6)
		var total := 0.0
		for j in range(pts.size() - 1):
			total += pts[j].distance_to(pts[j + 1])
		var s := 6.0
		var n := 0
		var stops: Array = []   # (for the shoppers, crowds.gd: where to stand at each stall)
		while s < total - 6.0:
			var at := _along(pts, s)
			var p: Vector2 = at[0]
			var a: Vector2 = at[1]
			for side: float in [-1.0, 1.0]:
				var seed := hash(Vector2i(p.round()) * int(side + 2.0))
				if posmod(n + (seed % 3), STALL_GAP) == 0:
					continue
				var o := Vector2(-a.y, a.x) * side
				var c := p + o * off
				var t: Vector2i = g._tile_of(c)
				if not _tile_items.has(t):
					_tile_items[t] = []
				(_tile_items[t] as Array).append(["stall", -1, [c, a, o, seed]])
				count["stall_places"] = int(count.get("stall_places", 0)) + 1
				stops.append([s, side, c - o * 1.0, o, c])
			s += STALL_STEP
			n += 1
		# the shoppers walk the walkway between the stalls' counters (0.55 m in front of each
		# stall's middle line, its posts 0.65 m round): their line the street's middle
		g._crowd.add_line("market", pts, maxf(off - 1.0, 0.5), stops)

## the point s metres along a line, and the way along it there
func _along(pts: PackedVector2Array, s: float) -> Array:
	for j in range(pts.size() - 1):
		var seg := pts[j].distance_to(pts[j + 1])
		if s <= seg and seg > 0.01:
			var d := (pts[j + 1] - pts[j]) / seg
			return [pts[j] + d * s, d]
		s -= seg
	var d2 := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	return [pts[pts.size() - 1], d2]

## a market stall at c, its walkway side toward -o: a counter of crates, a rack behind, four
## poles and a canvas sloping down toward the walkway
func _stall(b, c: Vector2, o: Vector2, seed: int) -> void:
	var gy: float = g._h(c)
	var x3 := Vector3(o.y, 0.0, -o.x)
	var z3 := Vector3(o.x, 0.0, o.y)
	var bs := Basis(x3, Vector3.UP, z3)
	var base := Vector3(c.x, gy, c.y)
	var P := func(u: float, v: float, w: float) -> Vector3: return base + x3 * u + Vector3.UP * v + z3 * w
	var wood: Color = g._tone["woodfence"]
	var metal: Color = g._tone["metal"]
	# produce in its own colours (the palette's purples and pinks made a market of sweets):
	# tomatoes, oranges, greens, lemons and peppers, aubergines
	var goods := ["red", "orange", "green", "yellow", "maroon", "green", "red"]
	var cols: Array = []
	for k in range(6):
		cols.append(g._real_col(goods[posmod(seed / (k + 3) + k, goods.size())]))
	g._furn._box(b, P.call(0.0, 0.45, 0.0), Vector3(2.3, 0.9, 1.1), wood, bs)   # the counter
	for k in range(4):   # crates of produce on it, tipped toward the walkway
		g._furn._box(b, P.call(-0.85 + 0.567 * k, 0.97, -0.12), Vector3(0.52, 0.14, 0.72), cols[k],
			bs * Basis(Vector3.RIGHT, 0.18))
	g._furn._box(b, P.call(0.0, 0.95, 0.68), Vector3(2.3, 1.9, 0.24), wood.darkened(0.25), bs)   # the rack
	for row in range(2):
		for k in range(4):
			g._furn._box(b, P.call(-0.85 + 0.567 * k, 1.2 + 0.42 * row, 0.5), Vector3(0.5, 0.26, 0.14),
				cols[(k + row * 2 + 1) % cols.size()], bs)
	for u: float in [-1.18, 1.18]:
		for w: float in [-0.6, 0.78]:
			g._furn._box(b, P.call(u, 1.25 + (0.0 if w < 0.0 else 0.2), w), Vector3(0.05, 2.5 + (0.0 if w < 0.0 else 0.4), 0.05), metal, bs)
	var hue: String = ["blue", "white", "red", "green", "orange", "cream", "blue"][posmod(seed >> 4, 7)]
	var canvas: Color = g._real_col(hue).lerp(g._real_col("white"), 0.15)
	g._furn._box(b, P.call(0.0, 2.6, 0.1), Vector3(2.55, 0.04, 2.0), canvas, bs * Basis(Vector3.RIGHT, -0.2))

func _add(bi: int, item: Array) -> void:
	var t: Vector2i = g._tile_of(_mid(g._city_data["buildings"][bi]["_ring"]))
	if not _tile_items.has(t):
		_tile_items[t] = []
	(_tile_items[t] as Array).append(item)

## the tallest building whose middle is inside the outline of the one named (itself, if none)
func _tallest_in(blds: Array, name: String) -> int:
	var named := -1
	for bi in range(blds.size()):
		if String(blds[bi].get("name", "")) == name:
			named = bi
			break
	if named < 0:
		return -1
	var outline: PackedVector2Array = blds[named]["_ring"]
	var box := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		box = box.expand(p)
	var best := named
	for bi in range(blds.size()):
		var ring: PackedVector2Array = blds[bi]["_ring"]
		if ring.size() < 3 or not box.has_point(ring[0]):
			continue
		if Geometry2D.is_point_in_polygon(_mid(ring), outline) and float(blds[bi]["_h"]) > float(blds[best]["_h"]):
			best = bi
	return best

## the building's roof over the sea's level, as _build_buildings puts it (its height over
## the average ground under its outline)
func _top(bi: int) -> float:
	var bd: Dictionary = g._city_data["buildings"][bi]
	var ring: PackedVector2Array = bd["_ring"]
	var sum := 0.0
	for p in ring:
		sum += g._h(p)
	return sum / ring.size() + float(bd["_h"])

## this square's: built with the square
func build() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var items: Array = _tile_items.get(g._tile, [])
	if items.is_empty():
		return
	var lamps: Array = []
	var stalls = null
	for it: Array in items:
		if String(it[0]) == "stall":
			var st: Array = it[2]
			var c: Vector2 = st[0]
			var o: Vector2 = st[2]
			# (not into a building, a wall or what stands there already)
			if g._push_out(c, 0.9, true) != Vector2.ZERO:
				continue
			if stalls == null:
				stalls = g.new_cbuf(400.0)
			_stall(stalls, c, o, int(st[3]))
			var a: Vector2 = st[1]
			g._add_post(c + a * 0.7, 0.65)
			g._add_post(c - a * 0.7, 0.65)
			g._crowd.stalls_up[Vector2i((c * 10.0).round())] = true
			count["stalls"] = int(count.get("stalls", 0)) + 1
			continue
		var bi: int = it[1]
		var ring: PackedVector2Array = g._city_data["buildings"][bi]["_ring"]
		var top := _top(bi)
		if String(it[0]) == "lamps":
			lamps.append_array(_roof_corners(ring, top + 0.7))
			continue
		var what: Dictionary = it[2]
		# (a shaft's and a mast's heights are over the ground at the building's foot -- the
		# figures are a tower's height -- not over the map's lowest point: Shalom Meir's ground
		# stands 15 m up, and its mast to "142" ended under its own roof)
		var ground := top - float(g._city_data["buildings"][bi]["_h"])
		if what.has("crown"):
			_crown(ring, top - float(what["crown"][1]), top - float(what["crown"][0]))
		var foot := top
		var mid := _mid(ring)
		if what.has("shaft"):
			var s: Array = what["shaft"]
			var w := float(s[1])
			var s_to := ground + float(s[0])
			_box(Vector3(w, s_to - top, w), Vector3(mid.x, (top + s_to) * 0.5, mid.y), "concrete")
			for f: float in [0.55, 0.85]:   # its antenna platforms
				var y := lerpf(top, s_to, f)
				_disc(w * 0.85, 0.7, Vector3(mid.x, y, mid.y), "concrete")
			foot = s_to
			lamps.append(Vector3(mid.x + w * 0.5 + 0.3, s_to + 0.3, mid.y))
		if what.has("mast"):
			var m: Array = what["mast"]
			var to := ground + float(m[0])
			var bands := 7 if bool(m[2]) else 1
			for b in range(bands):
				var y0 := lerpf(foot, to, float(b) / bands)
				var y1 := lerpf(foot, to, float(b + 1) / bands)
				var r := float(m[1]) * 0.5 * (1.0 - 0.45 * float(b) / bands)   # tapering
				_cyl(r, y1 - y0, Vector3(mid.x, (y0 + y1) * 0.5, mid.y), "red" if bool(m[2]) and b % 2 == 0 else ("white" if bool(m[2]) else "steel"))
			lamps.append(Vector3(mid.x, to + 0.4, mid.y))
			lamps.append(Vector3(mid.x, lerpf(foot, to, 0.5), mid.y))
	if not lamps.is_empty():
		_lamps(lamps)
	if stalls != null:
		g._add_mesh(stalls, g._vc_mat(), true, 400.0)

## the corners of a roof that a light goes on: its outline's furthest points each way
func _roof_corners(ring: PackedVector2Array, y: float) -> Array:
	var mid := _mid(ring)
	var out: Array = []
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var best := ring[0]
		for p in ring:
			if (p - mid).dot(d) > (best - mid).dot(d):
				best = p
		var q := best + (mid - best).normalized() * 0.6   # (just inside the parapet)
		if out.all(func(o): return Vector2(o.x, o.z).distance_to(q) > 4.0):
			out.append(Vector3(q.x, y, q.y))
	return out

## a band round the outline from y0 to y1, standing a little proud of the glass
func _crown(ring: PackedVector2Array, y0: float, y1: float) -> void:
	var n := ring.size()
	var ccw := _area(ring) > 0.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		if a.distance_to(b) < 0.05:
			continue
		var e := (b - a).normalized()
		var out := Vector2(e.y, -e.x) if ccw else Vector2(-e.y, e.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + out * 0.5, ring):
			out = -out
		var a2 := a + out * 0.35
		var b2 := b + out * 0.35
		var nrm := Vector3(out.x, 0, out.y)
		var q := [Vector3(a2.x, y0, a2.y), Vector3(b2.x, y0, b2.y), Vector3(b2.x, y1, b2.y), Vector3(a2.x, y1, a2.y)]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm)
			st.add_vertex(q[idx])
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	# (the winding either way: drawn from both sides)
	_node(mesh, "crown", g.VIEW_RANGE + 400.0)

func _box(size: Vector3, at: Vector3, mat: String) -> void:
	var m := BoxMesh.new()
	m.size = size
	_node(m, mat, g.VIEW_RANGE + 400.0).position = at

func _cyl(r: float, h: float, at: Vector3, mat: String) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r * 0.93
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	_node(m, mat, g.VIEW_RANGE + 400.0).position = at

func _disc(r: float, h: float, at: Vector3, mat: String) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 1
	_node(m, mat, g.VIEW_RANGE + 400.0).position = at

func _node(mesh: Mesh, mat: String, seen: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(mat)
	mi.visibility_range_end = seen
	g.world.add_child(mi)
	return mi

## the red lights: points that keep a few pixels' size however far (quads turned to face the
## eye, sized by distance in the shader), glowing at night and dark by day
const LAMP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform vec4 col : source_color;
varying float phase;
void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length((VIEW_MATRIX * vec4(c, 1.0)).xyz);
	float s = max(1.4, d * 0.011);   // (about 6 pixels at 400 m on a 720-line screen)
	vec3 w = c + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
	phase = fract(c.x * 0.0131 + c.z * 0.0077 + c.y * 0.05);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = max(0.0, 1.0 - dot(q, q));
	float on = 0.35 + 0.65 * smoothstep(0.35, 0.5, abs(fract(TIME * 0.45 + phase) - 0.5) * 2.0);
	ALBEDO = col.rgb * (a * a * 2.4 + smoothstep(0.55, 0.9, a) * 1.5) * on;
}
"""

func _lamps(at: Array) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = at.size()
	for i in range(at.size()):
		mm.set_instance_transform(i, Transform3D(Basis(), at[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat("lamp")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 40.0   # (the quads grow far off: the box would cull them)
	mmi.visibility_range_end = SEEN
	mmi.visible = g._night
	g._night_nodes.append(mmi)
	g.world.add_child(mmi)
	count["lamps"] = int(count.get("lamps", 0)) + at.size()

func _mat(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var red: Color = Palette.col("hazard").lerp(Color.RED, 0.6)
	var m: Material
	match name:
		"lamp":
			var sm := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = LAMP_SHADER
			sm.shader = sh
			sm.set_shader_parameter("col", red)
			m = sm
		"crown":   # brushed metal by day; lit through at night, the cool white of an office's light
			var s := StandardMaterial3D.new()
			s.albedo_color = Palette.col("ink").lerp(Palette.col("bg_alt"), 0.35)
			s.metallic = 0.7
			s.roughness = 0.3
			s.cull_mode = BaseMaterial3D.CULL_DISABLED
			s.emission = g._tone.get("litcool", Palette.col("ink")).lerp(Palette.col("player"), 0.3)
			s.emission_energy_multiplier = 1.6
			s.emission_enabled = g._night
			_lit.append(s)
			m = s
		"concrete":
			var s := StandardMaterial3D.new()
			s.albedo_color = g._tone.get("concrete", Palette.col("bg_alt"))
			s.roughness = 0.9
			m = s
		"red", "white", "steel":
			var s := StandardMaterial3D.new()
			s.albedo_color = {"red": red.lerp(Palette.col("bg"), 0.15), "white": Palette.col("ink").lerp(Palette.col("bg_alt"), 0.1),
				"steel": Palette.col("ink").lerp(Palette.col("bg"), 0.45)}[name]
			s.roughness = 0.5
			s.metallic = 0.3 if name == "steel" else 0.0
			m = s
	_mats[name] = m
	return m

func set_night(on: bool) -> void:
	for s: StandardMaterial3D in _lit:
		s.emission_enabled = on

func _mid(ring: PackedVector2Array) -> Vector2:
	var s := Vector2.ZERO
	for p in ring:
		s += p
	return s / maxf(1.0, ring.size())

func _area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for i in range(ring.size()):
		a += ring[i].x * ring[(i + 1) % ring.size()].y - ring[(i + 1) % ring.size()].x * ring[i].y
	return a * 0.5
