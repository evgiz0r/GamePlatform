extends RefCounted
## Railways: the tracks OpenStreetMap maps (each track its own line), the platforms beside
## them, the stations' names, and trains running along them. From the city file's `rails`,
## `platforms` and `stations` (tools/osm_city.py); a town baked before those were kept has
## none, and nothing here does anything.
##
## The rest of the game asks this file to set up (`setup`, with the city data, before the
## trees: the beds are ground nothing grows on), to draw a square (`build`), to move the
## trains (`tick`) and whether a point is on a track (`on_track`: a bridge's pier is not put
## there). Tracks in a tunnel (an underground metro) are left out; the rest lie on the ground
## on a ballast bed, a bridge's too. Trains are seen, not solid: the lines here run where no
## car goes (the Ayalon's median), and a level crossing is still to come.

const GAUGE := 1.435
const BED_TOP := 0.35         ## the ballast bed's top over the ground
const BED_HALF := 1.7         ## half its top's width, one track
const BED_FOOT := 2.6         ## half its foot's width
const SLEEPER_STEP := 0.65    ## concrete sleepers, this far apart
const RAIL_H := 0.16
const RAIL_HALF := 0.035
const SEEN := 900.0           ## the beds drawn this far
const NEAR := 260.0           ## sleepers and rails
const PLATFORM_TOP := 1.05    ## a platform's top over the rails' (Israel's high platforms)
const COACH_L := 26.0
const COACH_GAP := 0.9
const COACH_W := 2.9
const COACH_H := 4.4          ## double-deck coaches
const COACHES := 5
const TRAIN_V := 22.0         ## m/s through the city
const TRAIN_SEEN := 1200.0

var g: Node
var tracks: Array = []        ## [PackedVector2Array (every few metres), kind, name, service, feet]
## (feet: the bed's half-width at its foot at each point -- narrower where a road's asphalt
## runs close beside it, as along the Ayalon, so its slope does not come up through the road)
var _tile_tracks := {}        ## square -> track indices
var _seg_hash := {}           ## cell -> track * 4096 + segment, for on_track
const CELL := 40.0
var platforms: Array = []     ## PackedVector2Array outlines, counter-clockwise
var _tile_platforms := {}
var stations: Array = []      ## [Vector2, name, name_en]
var lines: Array = []         ## [PackedVector2Array path, PackedFloat32Array metres along]
var trains: Array = []        ## {line, s, dir, wait, node, coaches}
var _mats := {}

func _init(game: Node) -> void:
	g = game

func any() -> bool:
	return not tracks.is_empty()

## ---- setting up --------------------------------------------------------------------------

func setup(data: Dictionary, k: float) -> void:
	for r: Dictionary in data.get("rails", []):
		if r.has("tu") or String(r.get("k", "")) == "subway":
			continue   # (underground: nothing to see)
		var flat: Array = r["p"]
		var pts := PackedVector2Array()
		for i in range(0, flat.size() - 1, 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])) * k)
		if pts.size() < 2:
			continue
		var ti := tracks.size()
		var dense := _dense(pts, 6.0)
		var feet := PackedFloat32Array()
		for p in dense:
			var on: Dictionary = g._nearest_seg(p, 12.0, true)
			feet.append(clampf(float(on["edge"]) - 0.15, BED_HALF + 0.15, BED_FOOT) if not on.is_empty() else BED_FOOT)
		tracks.append([dense, String(r.get("k", "rail")), String(r.get("name", "")), String(r.get("sv", "")), feet])
		var seen := {}
		for j in range(dense.size() - 1):
			var box := Rect2(dense[j], Vector2.ZERO).expand(dense[j + 1]).grow(BED_FOOT + 1.0)
			for t: Vector2i in g._tiles_over(box):
				if not seen.has(t):
					seen[t] = true
					g._bucket(_tile_tracks, t, ti)
			g._hash_add(_seg_hash, box, CELL, ti * 4096 + j)
		# nothing grows on the bed (open land's wild trees): its outline, a piece at a time
		for j0 in range(0, dense.size() - 1, 8):
			var piece := dense.slice(j0, mini(j0 + 9, dense.size()))
			if piece.size() < 2:
				continue
			var a: PackedVector2Array = g._offset_line(piece, BED_FOOT + 1.5)
			var b: PackedVector2Array = g._offset_line(piece, -(BED_FOOT + 1.5))
			b.reverse()
			a.append_array(b)
			g._hash_add(g._no_grow, g._bld_box_of(a), 60.0, g._no_rings.size())
			g._no_rings.append(a)
	for pl: Dictionary in data.get("platforms", []):
		var flat: Array = pl["p"]
		var pts := PackedVector2Array()
		for i in range(0, flat.size() - 1, 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])) * k)
		if pts.size() < 2:
			continue
		var ring := PackedVector2Array()
		if pl.has("a") and pts.size() >= 4:
			ring = pts.slice(0, pts.size() - 1) if pts[0].distance_to(pts[pts.size() - 1]) < 0.5 else pts
		else:
			ring = _platform_of_line(pts)
		if ring.size() < 3 or not _near_a_track(ring):
			continue   # (a light rail's platform underground, a bus platform: no track by it)
		if Geometry2D.is_polygon_clockwise(ring):
			ring.reverse()
		var pi := platforms.size()
		platforms.append(ring)
		for t: Vector2i in g._tiles_over(g._bld_box_of(ring)):
			g._bucket(_tile_platforms, t, pi)
		g._hash_add(g._no_grow, g._bld_box_of(ring), 60.0, g._no_rings.size())
		g._no_rings.append(ring)
	for st: Array in data.get("stations", []):
		var p := Vector2(float(st[0]), float(st[1])) * k
		if on_track(p, 60.0):
			stations.append([p, String(st[2]), String(st[3])])
	_make_lines()
	_tally()

## a platform mapped as a line (its edge along the track): a slab 4 m deep on the side away
## from the nearest track
func _platform_of_line(pts: PackedVector2Array) -> PackedVector2Array:
	var mid := pts[pts.size() / 2].lerp(pts[(pts.size() - 1) / 2], 0.5)
	var d := (pts[pts.size() - 1] - pts[0]).normalized()
	var side := Vector2(-d.y, d.x)
	var t := _nearest_track(mid, 30.0)
	if not t.is_empty() and (t["q"] as Vector2).direction_to(mid).dot(side) < 0.0:
		side = -side
	var a := pts.duplicate()
	var b: PackedVector2Array = g._offset_line(pts, 4.0 if side.dot(Vector2(-d.y, d.x)) > 0.0 else -4.0)
	b.reverse()
	a.append_array(b)
	return a

func _near_a_track(ring: PackedVector2Array) -> bool:
	for p in ring:
		if on_track(p, 12.0):
			return true
	return false

## the nearest track's point to p within reach: {track, seg, q, d} or {}
func _nearest_track(p: Vector2, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for cx in range(floori((p.x - reach) / CELL), floori((p.x + reach) / CELL) + 1):
		for cz in range(floori((p.y - reach) / CELL), floori((p.y + reach) / CELL) + 1):
			for code: int in _seg_hash.get(Vector2i(cx, cz), []):
				var pts: PackedVector2Array = tracks[code / 4096][0]
				var j := code % 4096
				var q := Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])
				var d := q.distance_to(p)
				if d < bd:
					bd = d
					best = {"track": code / 4096, "seg": j, "q": q, "d": d}
	return best

## the tracks within reach of `at`, as pairs of points (the minimap's multiline)
func map_lines(at: Vector2, reach: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var box := Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	for t: Array in tracks:
		var pts: PackedVector2Array = t[0]
		for j in range(pts.size() - 1):
			if box.has_point(pts[j]) or box.has_point(pts[j + 1]):
				out.append(pts[j])
				out.append(pts[j + 1])
	return out

## p is within `r` metres of a track's middle line (a bridge's pier is not stood there)
func on_track(p: Vector2, r := BED_FOOT) -> bool:
	return not _nearest_track(p, r).is_empty()

## Where trains run: chains of tracks joined end to end (they share an end point), the
## straightest way on at each join, sidings and yards left out; the long ones, a train each.
func _make_lines() -> void:
	var ends := {}   # end point (rounded to the decimetre) -> [[track, at start?]]
	for ti in range(tracks.size()):
		if String(tracks[ti][3]) != "" or String(tracks[ti][1]) != "rail":
			continue   # (a siding, a yard's track; trams and light rail are not run yet)
		var pts: PackedVector2Array = tracks[ti][0]
		for e: int in [0, 1]:
			var ep: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var key := Vector2i(roundi(ep.x * 10.0), roundi(ep.y * 10.0))
			if not ends.has(key):
				ends[key] = []
			(ends[key] as Array).append([ti, e == 0])
	var used := {}
	var cands: Array = []
	for ti in range(tracks.size()):
		if used.has(ti) or String(tracks[ti][3]) != "" or String(tracks[ti][1]) != "rail":
			continue
		# walk back to the chain's first track, then forward along it
		var vis := {}
		var path := _walk(ti, true, ends, vis)
		path.reverse()
		var fwd := _walk(ti, false, ends, vis)
		for v: int in vis:
			used[v] = true
		var chain := PackedVector2Array()
		for seg: PackedVector2Array in path:
			chain.append_array(seg if chain.is_empty() else seg.slice(1))
		var own: PackedVector2Array = tracks[ti][0]
		chain.append_array(own if chain.is_empty() else own.slice(1))
		for seg: PackedVector2Array in fwd:
			chain.append_array(seg.slice(1))
		used[ti] = true
		cands.append(chain)
	cands.sort_custom(func(a, b): return _length(a) > _length(b))
	for chain: PackedVector2Array in cands:
		if lines.size() >= 4 or _length(chain) < 600.0:
			break
		# not one that runs alongside a line already taken (the same double track's other
		# direction is fine; the same track walked twice is not)
		var dup := false
		for ln: Array in lines:
			var other: PackedVector2Array = ln[0]
			var mid := chain[chain.size() / 2]
			var close := INF
			for j in range(other.size() - 1):
				close = minf(close, Geometry2D.get_closest_point_to_segment(mid, other[j], other[j + 1]).distance_to(mid))
			dup = dup or close < 1.0
		if dup:
			continue
		var cum := PackedFloat32Array([0.0])
		for j in range(1, chain.size()):
			cum.append(cum[j - 1] + chain[j - 1].distance_to(chain[j]))
		lines.append([chain, cum])

## from track ti's end (its start when `back`), the tracks on, the straightest each time:
## their points, each in the direction walked
func _walk(ti: int, back: bool, ends: Dictionary, seen: Dictionary) -> Array:
	var out: Array = []
	var cur := ti
	var at_start := back
	seen[ti] = true
	for _step in range(60):
		var pts: PackedVector2Array = tracks[cur][0]
		var p: Vector2 = pts[0] if at_start else pts[pts.size() - 1]
		var heading: Vector2 = (pts[0] - pts[1]).normalized() if at_start else (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		var key := Vector2i(roundi(p.x * 10.0), roundi(p.y * 10.0))
		var best := -1
		var best_start := true
		var best_dot := 0.5   # (no sharper than 60 degrees: a crossover's diverging leg is not "on")
		for e: Array in ends.get(key, []):
			var tj: int = e[0]
			if seen.has(tj):
				continue
			var q: PackedVector2Array = tracks[tj][0]
			var dir: Vector2 = (q[1] - q[0]).normalized() if bool(e[1]) else (q[q.size() - 2] - q[q.size() - 1]).normalized()
			if dir.dot(heading) > best_dot:
				best_dot = dir.dot(heading)
				best = tj
				best_start = bool(e[1])
		if best < 0:
			break
		seen[best] = true
		var q: PackedVector2Array = tracks[best][0]
		if best_start:
			out.append(q)
		else:
			var r := q.duplicate()
			r.reverse()
			out.append(r)
		cur = best
		at_start = not best_start
	if back:
		for i in range(out.size()):
			var r: PackedVector2Array = (out[i] as PackedVector2Array).duplicate()
			r.reverse()
			out[i] = r
	return out

func _length(pts: PackedVector2Array) -> float:
	var L := 0.0
	for j in range(pts.size() - 1):
		L += pts[j].distance_to(pts[j + 1])
	return L

func _dense(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var n := maxi(1, ceili(pts[i - 1].distance_to(pts[i]) / step))
		for q in range(1, n + 1):
			out.append(pts[i - 1].lerp(pts[i], float(q) / n))
	return out

func _tally() -> void:
	var L := 0.0
	for t: Array in tracks:
		L += _length(t[0])
	g._dressing["rail_m"] = int(L)
	g._dressing["rail_platforms"] = platforms.size()
	g._dressing["rail_lines"] = lines.size()

## ---- materials (from the palette's roles, through the game's own tones) -------------------

func _mat(name: String) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var tone: Dictionary = g._tone
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	match name:
		"ballast":   # grey-brown stone, darker than the bare ground it lies on (at first it was
			# the same pale grey, and from beside the line the bed was not there)
			m.albedo_color = (tone["metal"] as Color).lerp(tone["sand"], 0.3).darkened(0.15)
		"sleeper":   # concrete, weathered (plain concrete came out white beside the stone)
			m.albedo_color = (tone["concrete"] as Color).lerp(tone["metal"], 0.45)
		"rail":
			m.albedo_color = (tone["metal"] as Color).lerp(tone["railing"], 0.35)
			m.metallic = 0.7
			m.roughness = 0.4
		"platform":
			m.albedo_color = tone["concrete"]
		"edge":      # the platform's yellow safety line
			m.albedo_color = tone["markyellow"]
		"coach":
			m.albedo_color = Palette.col("ink").lerp(Palette.col("bg_alt"), 0.12)
			m.roughness = 0.5
		"stripe":
			m.albedo_color = Palette.col("player").lerp(Palette.col("bg"), 0.35)
			m.roughness = 0.5
		"window":
			m.albedo_color = Palette.col("bg").lerp(Palette.col("bg_alt"), 0.4)
			m.roughness = 0.15
			m.metallic_specular = 0.8
		"under":
			m.albedo_color = Palette.col("bg").lerp(Palette.col("bg_alt"), 0.3)
		"mast":      # galvanised steel
			m.albedo_color = (tone["metal"] as Color).lerp(tone["concrete"], 0.4)
			m.metallic = 0.5
			m.roughness = 0.5
		"wire":
			m.albedo_color = Palette.col("bg").lerp(Palette.col("bg_alt"), 0.25)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"lamp":      # headlights: lit day and night, as trains run
			m.albedo_color = Palette.col("ink")
			m.emission_enabled = true
			m.emission = Palette.col("ink").lerp(Palette.col("warn"), 0.15)
			m.emission_energy_multiplier = 2.5
		"taillamp":
			m.albedo_color = Palette.col("hazard")
			m.emission_enabled = true
			m.emission = Palette.col("hazard")
			m.emission_energy_multiplier = 2.0
		"roof":   # canopies and roofs: grey metal (the palette's bg_alt alone came out lilac)
			m.albedo_color = (tone["metal"] as Color).lerp(tone["concrete"], 0.55)
	_mats[name] = m
	return m

## ---- drawing a square --------------------------------------------------------------------

func _y(p: Vector2) -> float:
	return g._h(p)

func build() -> void:
	var list: Array = _tile_tracks.get(g._tile, [])
	var pl_list: Array = _tile_platforms.get(g._tile, [])
	if list.is_empty() and pl_list.is_empty():
		return
	var bed: RefCounted = g._clip_buf(g.CHUNK)
	var steel: RefCounted = g._clip_buf(g.GROUND_CELL)
	var sleepers: Array = []
	for ti: int in list:
		if g._over():
			await g._pause()
		var pts: PackedVector2Array = tracks[ti][0]
		# the bed: a flat top and its slopes down to the ground
		var top_l: PackedVector2Array = g._offset_line(pts, BED_HALF)
		var top_r: PackedVector2Array = g._offset_line(pts, -BED_HALF)
		var feet: PackedFloat32Array = tracks[ti][4]
		var foot_l: PackedVector2Array = g._offset_line(pts, BED_FOOT)
		var foot_r: PackedVector2Array = g._offset_line(pts, -BED_FOOT)
		for j in range(pts.size()):   # (pulled in where a road runs close)
			foot_l[j] = top_l[j] + (foot_l[j] - top_l[j]) * (feet[j] - BED_HALF) / (BED_FOOT - BED_HALF)
			foot_r[j] = top_r[j] + (foot_r[j] - top_r[j]) * (feet[j] - BED_HALF) / (BED_FOOT - BED_HALF)
		for j in range(pts.size() - 1):
			var y0 := _y(pts[j])
			var y1 := _y(pts[j + 1])
			var tl0 := Vector3(top_l[j].x, y0 + BED_TOP, top_l[j].y)
			var tl1 := Vector3(top_l[j + 1].x, y1 + BED_TOP, top_l[j + 1].y)
			var tr0 := Vector3(top_r[j].x, y0 + BED_TOP, top_r[j].y)
			var tr1 := Vector3(top_r[j + 1].x, y1 + BED_TOP, top_r[j + 1].y)
			var fl0 := Vector3(foot_l[j].x, y0 - 0.05, foot_l[j].y)
			var fl1 := Vector3(foot_l[j + 1].x, y1 - 0.05, foot_l[j + 1].y)
			var fr0 := Vector3(foot_r[j].x, y0 - 0.05, foot_r[j].y)
			var fr1 := Vector3(foot_r[j + 1].x, y1 - 0.05, foot_r[j + 1].y)
			bed.tri(tl0, tl1, tr1, Vector3.UP, Color.WHITE)
			bed.tri(tl0, tr1, tr0, Vector3.UP, Color.WHITE)
			bed.quad3(fl0, fl1, tl1, tl0)
			bed.quad3(tr0, tr1, fr1, fr0)
		# the rails: a narrow box each side of the gauge
		var rail_y := BED_TOP + 0.18
		for side: float in [-1.0, 1.0]:
			for edge in [[GAUGE * 0.5 * side - RAIL_HALF, GAUGE * 0.5 * side + RAIL_HALF]]:
				var a: PackedVector2Array = g._offset_line(pts, float(edge[0]))
				var b: PackedVector2Array = g._offset_line(pts, float(edge[1]))
				for j in range(pts.size() - 1):
					if not g._mine(pts[j]):
						continue
					var y0 := _y(pts[j]) + rail_y
					var y1 := _y(pts[j + 1]) + rail_y
					var a0 := Vector3(a[j].x, y0 + RAIL_H, a[j].y)
					var a1 := Vector3(a[j + 1].x, y1 + RAIL_H, a[j + 1].y)
					var b0 := Vector3(b[j].x, y0 + RAIL_H, b[j].y)
					var b1 := Vector3(b[j + 1].x, y1 + RAIL_H, b[j + 1].y)
					steel.tri(a0, a1, b1, Vector3.UP, Color.WHITE)
					steel.tri(a0, b1, b0, Vector3.UP, Color.WHITE)
					steel.quad3(Vector3(a0.x, y0, a0.z), Vector3(a1.x, y1, a1.z), a1, a0)
					steel.quad3(b0, b1, Vector3(b1.x, y1, b1.z), Vector3(b0.x, y0, b0.z))
		# the sleepers, every SLEEPER_STEP along it
		var acc := 0.0
		for j in range(pts.size() - 1):
			var L := pts[j].distance_to(pts[j + 1])
			var d := (pts[j + 1] - pts[j]) / maxf(L, 0.001)
			while acc < L:
				var p := pts[j] + d * acc
				if g._mine(p):
					sleepers.append(Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(p.x, _y(p) + BED_TOP + 0.09, p.y)))
				acc += SLEEPER_STEP
			acc -= L
	g._add_mesh(bed, _mat("ballast"), false, SEEN)
	g._add_mesh(steel, _mat("rail"), false, NEAR)
	if not sleepers.is_empty():
		var sm := BoxMesh.new()
		sm.size = Vector3(2.6, 0.18, 0.26)
		sm.material = _mat("sleeper")
		g._chunked(sm, sleepers, NEAR)
	for pi: int in pl_list:
		_platform(pi)
	await _wires(list)

## ---- the overhead line ---------------------------------------------------------------------

const WIRE_H := 5.6           ## the contact wire over the rails' top
const MESSENGER := 1.1        ## the messenger wire above it
const MAST_STEP := 50.0
const MAST_OFF := 3.2         ## a mast beside its track's middle
const MAST_H := 7.6

## Masts every MAST_STEP on each outer side of the tracks (a side with no other track within
## 8 m), each with an arm reaching in over its track and the others on that side -- from both
## sides they meet over a corridor of three like a portal; a contact wire and a messenger
## over each track, coming down to clear a bridge's slab. Every main-line track is wired
## (the Ayalon line is; the baker does not keep OSM's electrified= yet). No mast on a road or
## under a bridge.
func _wires(list: Array) -> void:
	var wire: RefCounted = g._clip_buf(g.GROUND_CELL)
	var masts: Array = []
	var arms: Array = []
	var top_y := BED_TOP + 0.18 + RAIL_H
	for ti: int in list:
		if String(tracks[ti][1]) != "rail" or String(tracks[ti][3]) in ["yard", "siding", "spur"]:
			continue
		if g._over():
			await g._pause()
		var pts: PackedVector2Array = tracks[ti][0]
		# the wires: each point's height, under a bridge the slab's underside less 0.4 m
		var hs := PackedFloat32Array()
		for p in pts:
			var gy := _y(p)
			var h := gy + top_y + WIRE_H
			if g._decks != null and g._decks.any():
				for ri: int in g._decks._under(p):
					var dy: float = g._decks._under(p)[ri][1]
					if dy > gy + 2.0:
						h = minf(h, dy - g._decks.SLAB - 0.4)
			hs.append(maxf(h, gy + top_y + 4.6))
		for j in range(pts.size() - 1):
			if not g._mine(pts[j]):
				continue
			var d := (pts[j + 1] - pts[j]).normalized()
			var n := Vector2(-d.y, d.x) * 0.025
			for lift: float in [0.0, MESSENGER]:
				if lift > 0.0 and hs[j] < _y(pts[j]) + top_y + WIRE_H - 0.1:
					continue   # (under a bridge: the contact wire alone)
				var a0 := Vector3(pts[j].x, hs[j] + lift, pts[j].y)
				var a1 := Vector3(pts[j + 1].x, hs[j + 1] + lift, pts[j + 1].y)
				var o := Vector3(n.x, 0.0, n.y)
				wire.quad3(a0 - o, a1 - o, a1 + o, a0 + o)   # (seen from below)
				wire.quad3(a0 + o, a1 + o, a1 + o + Vector3(0, 0.05, 0), a0 + o + Vector3(0, 0.05, 0))
		# the masts
		var cum := 0.0
		var next := MAST_STEP * 0.5
		for j in range(pts.size() - 1):
			var L := pts[j].distance_to(pts[j + 1])
			var d := (pts[j + 1] - pts[j]) / maxf(L, 0.001)
			while next < cum + L:
				var p := pts[j] + d * (next - cum)
				next += MAST_STEP
				if not g._mine(p):
					continue
				for sd: float in [1.0, -1.0]:
					var side := Vector2(-d.y, d.x) * sd
					if _other_track(p + side * 4.0, ti, 4.5):
						continue   # (another track on this side: its mast, or one further out)
					var mp := p + side * MAST_OFF
					var on: Dictionary = g._nearest_seg(mp, 6.0, true)
					if not on.is_empty() and float(on["edge"]) < 0.6:
						continue   # (no mast in a road)
					if g._decks != null and g._decks.any() and not g._decks._under(mp).is_empty():
						continue   # (nor under a bridge)
					# the arm: in over this track and any others on the far side, up to 12 m
					var reach := MAST_OFF + 0.6
					for k in range(1, 4):
						if _other_track(p - side * (4.2 * k), ti, 1.6):
							reach = MAST_OFF + 4.2 * k + 0.6
					var gy := _y(mp)
					masts.append(Transform3D(Basis(), Vector3(mp.x, gy + MAST_H * 0.5, mp.y)))
					var am := mp - side * reach * 0.5
					# (the length along the arm's own axis: Basis.scaled() stretches along the
					# world's, and the arms came out skewed along the track)
					var arm_b := Basis(Vector3.UP, atan2(side.x, side.y)) * Basis.from_scale(Vector3(1.0, 1.0, reach))
					arms.append(Transform3D(arm_b, Vector3(am.x, gy + MAST_H - 0.6, am.y)))
			cum += L
	g._add_mesh(wire, _mat("wire"), false, NEAR)
	var mm := BoxMesh.new()
	mm.size = Vector3(0.3, MAST_H, 0.3)
	mm.material = _mat("mast")
	g._chunked(mm, masts, SEEN * 0.5)
	var am_mesh := BoxMesh.new()
	am_mesh.size = Vector3(0.14, 0.18, 1.0)
	am_mesh.material = _mat("mast")
	g._chunked(am_mesh, arms, SEEN * 0.5)

## another track than ti within r of p
func _other_track(p: Vector2, ti: int, r: float) -> bool:
	for cx in range(floori((p.x - r) / CELL), floori((p.x + r) / CELL) + 1):
		for cz in range(floori((p.y - r) / CELL), floori((p.y + r) / CELL) + 1):
			for code: int in _seg_hash.get(Vector2i(cx, cz), []):
				if code / 4096 == ti:
					continue
				var pts: PackedVector2Array = tracks[code / 4096][0]
				var j := code % 4096
				if Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1]).distance_to(p) < r:
					return true
	return false

## a platform: a slab up at the coaches' floor, a yellow line along its edge by the track,
## a canopy over its middle, the station's name on it
func _platform(pi: int) -> void:
	var ring: PackedVector2Array = platforms[pi]
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	if not g._mine(c):
		return
	var top := _y(c) + BED_TOP + 0.18 + RAIL_H + PLATFORM_TOP
	var slab: RefCounted = g._clip_buf(g.CHUNK)
	slab.clip = false
	var tris := Geometry2D.triangulate_polygon(ring)
	for i in range(0, tris.size() - 2, 3):
		var a := ring[tris[i]]
		var b := ring[tris[i + 1]]
		var d := ring[tris[i + 2]]
		slab.tri(Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(d.x, top, d.y), Vector3.UP, Color.WHITE)
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		slab.quad3(Vector3(a.x, _y(a) - 0.1, a.y), Vector3(b.x, _y(b) - 0.1, b.y), Vector3(b.x, top, b.y), Vector3(a.x, top, a.y))
	g._add_mesh(slab, _mat("platform"), true, SEEN)
	# the long axis: the platform's longest side
	var ax := Vector2.RIGHT
	var longest := 0.0
	for i in range(ring.size()):
		var e := ring[(i + 1) % ring.size()] - ring[i]
		if e.length() > longest:
			longest = e.length()
			ax = e.normalized()
	var length := 0.0
	var width := 0.0
	for p in ring:
		length = maxf(length, absf((p - c).dot(ax)) * 2.0)
		width = maxf(width, absf((p - c).dot(Vector2(-ax.y, ax.x))) * 2.0)
	# a canopy over the middle half, on posts
	var roof := BoxMesh.new()
	roof.size = Vector3(maxf(width - 1.2, 2.0), 0.18, length * 0.5)
	roof.material = _mat("roof")
	var mi := MeshInstance3D.new()
	mi.mesh = roof
	mi.position = Vector3(c.x, top + 3.6, c.y)
	mi.rotation.y = atan2(ax.x, ax.y)
	mi.visibility_range_end = SEEN
	g.world.add_child(mi)
	var posts: Array = []
	for f: float in [-0.22, 0.0, 0.22]:
		var p := c + ax * length * f
		posts.append(Transform3D(Basis(), Vector3(p.x, top + 1.8, p.y)))
	var pm := CylinderMesh.new()
	pm.top_radius = 0.12
	pm.bottom_radius = 0.12
	pm.height = 3.6
	pm.material = _mat("roof")
	g._chunked(pm, posts, NEAR)
	# the station's name, if one stands near: hung under the canopy
	for st: Array in stations:
		if (st[0] as Vector2).distance_to(c) < 250.0:
			var lb := Label3D.new()
			lb.text = String(st[1]) + ("\n" + String(st[2]) if String(st[2]) != "" else "")
			lb.font = g._font
			lb.font_size = 72
			lb.pixel_size = 0.012
			lb.outline_size = 10
			lb.modulate = Palette.col("ink")
			lb.outline_modulate = Palette.col("bg")
			lb.set_meta("role", "ink")
			lb.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			lb.position = Vector3(c.x, top + 3.0, c.y)
			lb.visibility_range_end = 300.0
			g.world.add_child(lb)
			break

## ---- trains ------------------------------------------------------------------------------

## the places on line li a train stops: where a platform lies beside its track (its middle
## within 12 m of the line), one for each station's group of platforms, metres along
func _stops_of(li: int) -> PackedFloat32Array:
	var path: PackedVector2Array = lines[li][0]
	var cum: PackedFloat32Array = lines[li][1]
	var out := PackedFloat32Array()
	for ring: PackedVector2Array in platforms:
		var c := Vector2.ZERO
		for p in ring:
			c += p
		c /= ring.size()
		var best := 12.0
		var at := -1.0
		for j in range(path.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(c, path[j], path[j + 1])
			if q.distance_to(c) < best:
				best = q.distance_to(c)
				at = cum[j] + path[j].distance_to(q)
		if at >= 0.0 and not Array(out).any(func(x): return absf(x - at) < 120.0):
			out.append(at)
	out.sort()
	return out

func _make_train() -> Node3D:
	var root := Node3D.new()
	for i in range(COACHES):
		var coach := Node3D.new()
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(COACH_W, COACH_H - 1.0, COACH_L)
		bm.material = _mat("coach")
		body.mesh = bm
		body.position.y = 1.0 + (COACH_H - 1.0) * 0.5
		coach.add_child(body)
		for row: float in [1.75, 3.65]:   # two decks of windows
			var w := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(COACH_W + 0.04, 0.85, COACH_L - 3.0)
			wm.material = _mat("window")
			w.mesh = wm
			w.position.y = row + 0.35
			coach.add_child(w)
		var s := MeshInstance3D.new()
		var smm := BoxMesh.new()
		smm.size = Vector3(COACH_W + 0.05, 0.3, COACH_L - 0.4)
		smm.material = _mat("stripe")
		s.mesh = smm
		s.position.y = 1.25
		coach.add_child(s)
		var under := MeshInstance3D.new()   # bogies and the frame, dark, under the body
		var um := BoxMesh.new()
		um.size = Vector3(COACH_W - 0.5, 0.8, COACH_L - 2.0)
		um.material = _mat("under")
		under.mesh = um
		under.position.y = 0.55
		coach.add_child(under)
		var roof := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(COACH_W - 0.4, 0.25, COACH_L - 0.6)
		rm.material = _mat("roof")
		roof.mesh = rm
		roof.position.y = COACH_H + 0.1
		coach.add_child(roof)
		# a cab at each end of the train (it runs either way, push-pull): the front's face,
		# its windscreen and lamps -- white ahead (coach 0 leads, its +Z end), red behind
		if i == 0 or i == COACHES - 1:
			var end := COACH_L * 0.5 if i == 0 else -COACH_L * 0.5
			var out := signf(end)
			_box(coach, Vector3(COACH_W - 0.1, 1.9, 0.3), Vector3(0.0, 1.95, end + out * 0.1), "stripe")
			_box(coach, Vector3(COACH_W - 0.5, 0.9, 0.3), Vector3(0.0, 3.25, end + out * 0.12), "window")
			for sx: float in [-0.95, 0.95]:
				_box(coach, Vector3(0.38, 0.22, 0.12), Vector3(sx, 1.35, end + out * 0.28), "lamp" if i == 0 else "taillamp")
		for m: Node in coach.get_children():
			(m as GeometryInstance3D).visibility_range_end = TRAIN_SEEN
		# its sound: the rumble from the middle coach, the horn from the leading one
		if i == COACHES / 2 or i == 0:
			var sp := AudioStreamPlayer3D.new()
			sp.name = "rumble" if i == COACHES / 2 else "horn"
			sp.stream = load(SND_DIR + ("train.wav" if i == COACHES / 2 else "train_horn.wav"))
			sp.unit_size = 14.0 if i == COACHES / 2 else 30.0
			sp.max_distance = 500.0 if i == COACHES / 2 else 900.0
			sp.position.y = 1.5
			coach.add_child(sp)
		root.add_child(coach)
	return root

const SND_DIR := "res://game/streets/sounds/"

## The trains heard (from the game's engine-sound step, which runs paused too): the rumble
## while a train is out, louder with its speed (and a low hum standing at a platform), the horn
## once as it pulls away from one; silent when the sound is off, paused or the run is over.
func sound(off: bool) -> void:
	var base := linear_to_db(maxf(0.0001, float(SaveData.data.get("volume_sfx", 0.8))))
	for tr: Dictionary in trains:
		var node: Node3D = tr["node"]
		var coaches: Array = node.get_children()
		var rumble: AudioStreamPlayer3D = (coaches[COACHES / 2] as Node3D).get_node("rumble")
		var horn: AudioStreamPlayer3D = (coaches[0] as Node3D).get_node("horn")
		var out := node.visible and not off
		if not out:
			if rumble.playing:
				rumble.stop()
			if horn.playing:
				horn.stop()
			tr["horn"] = false
			continue
		if not rumble.playing:
			rumble.play(fmod(float(tr["line"]) * 1.3, 4.0))
		var v: float = tr["v"]
		rumble.volume_db = base + (2.0 + 20.0 * log(maxf(v, 0.4) / TRAIN_V) / log(10.0))
		rumble.pitch_scale = 0.75 + 0.25 * clampf(v / TRAIN_V, 0.0, 1.2)
		if bool(tr.get("horn", false)):
			tr["horn"] = false
			horn.volume_db = base - 2.0
			horn.play()

func _box(parent: Node3D, size: Vector3, at: Vector3, mat: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(mat)
	mi.mesh = bm
	mi.position = at
	parent.add_child(mi)

## the dark: the coaches' windows lit warm (one material, shared)
func set_night(on: bool) -> void:
	var w := _mat("window")
	w.emission_enabled = on
	w.emission = Palette.col("ink").lerp(Palette.col("warn"), 0.45)
	w.emission_energy_multiplier = 0.9

## the point and heading a distance s along line li
func _along(li: int, s: float) -> Array:
	var path: PackedVector2Array = lines[li][0]
	var cum: PackedFloat32Array = lines[li][1]
	s = clampf(s, 0.0, cum[cum.size() - 1])
	var j := cum.bsearch(s) - 1
	j = clampi(j, 0, path.size() - 2)
	var t := (s - cum[j]) / maxf(cum[j + 1] - cum[j], 0.001)
	return [path[j].lerp(path[j + 1], t), (path[j + 1] - path[j]).normalized()]

const ACCEL := 0.6            ## m/s^2 pulling away
const DECEL := 0.7            ## braking for a station
const DWELL := 30.0           ## seconds at a platform

## A train on each line, one direction then the other, a while apart; slowing for each
## station's platforms, standing DWELL at them with its middle at the platform's, pulling
## away again. `s` is coach 0's middle (the leading coach, whichever way it runs).
func tick(dt: float) -> void:
	if lines.is_empty():
		return
	if trains.is_empty():
		for li in range(lines.size()):
			var node := _make_train()
			node.visible = false
			g.world.add_child(node)
			trains.append({"line": li, "s": 0.0, "dir": 1 if li % 2 == 0 else -1, "wait": 8.0 + li * 25.0,
					"node": node, "v": TRAIN_V, "dwell": 0.0, "served": -INF, "stops": _stops_of(li)})
	var train_l := COACHES * (COACH_L + COACH_GAP)
	var mid_off := (COACHES - 1) * (COACH_L + COACH_GAP) * 0.5   # coach 0 to the train's middle
	for tr: Dictionary in trains:
		var cum: PackedFloat32Array = lines[int(tr["line"])][1]
		var total: float = cum[cum.size() - 1]
		var dir := int(tr["dir"])
		if float(tr["wait"]) > 0.0:
			tr["wait"] = float(tr["wait"]) - dt
			if float(tr["wait"]) <= 0.0:
				tr["s"] = -train_l if dir > 0 else total + train_l
				tr["v"] = TRAIN_V
				tr["served"] = -INF
				(tr["node"] as Node3D).visible = true
			continue
		if float(tr["dwell"]) > 0.0:
			tr["dwell"] = float(tr["dwell"]) - dt
			if float(tr["dwell"]) <= 0.0:
				tr["horn"] = true   # (pulling out: heard once, see sound())
		else:
			# the next stop ahead not yet served: brake to stand with the middle at it
			var to_stop := INF
			for st: float in tr["stops"]:
				if absf(st - float(tr["served"])) < 1.0:
					continue
				var d := (st + mid_off * dir - float(tr["s"])) * dir
				if d > -0.5 and d < to_stop:
					to_stop = d
			var want := TRAIN_V
			if to_stop < INF:
				want = minf(TRAIN_V, sqrt(2.0 * DECEL * maxf(to_stop, 0.0)))
			var v: float = tr["v"]
			v = minf(v + ACCEL * dt, want) if v < want else want
			if to_stop < 0.4 and v < 0.6:
				v = 0.0
				tr["dwell"] = DWELL
				for st: float in tr["stops"]:   # (which one it is standing at)
					if absf(st + mid_off * dir - float(tr["s"])) < 2.0:
						tr["served"] = st
				Probe.event("train_stop", {"line": int(tr["line"])})
			tr["v"] = v
			tr["s"] = float(tr["s"]) + v * dt * dir
		var s: float = tr["s"]
		if (dir > 0 and s > total + train_l) or (dir < 0 and s < -train_l):
			tr["wait"] = 40.0 + fmod(float(tr["line"]) * 37.0, 50.0)
			tr["dir"] = -dir
			(tr["node"] as Node3D).visible = false
			continue
		var coaches: Array = (tr["node"] as Node3D).get_children()
		for i in range(coaches.size()):
			var sc := s - float(i) * (COACH_L + COACH_GAP) * dir
			var coach: Node3D = coaches[i]
			if sc < 0.0 or sc > total:
				coach.visible = false
				continue
			coach.visible = true
			# the coach's ends on the line, its body between them
			var f: Array = _along(int(tr["line"]), sc + COACH_L * 0.45 * dir)
			var b: Array = _along(int(tr["line"]), sc - COACH_L * 0.45 * dir)
			var fp: Vector2 = f[0]
			var bp: Vector2 = b[0]
			var mid := (fp + bp) * 0.5
			var fwd := (fp - bp).normalized() if fp.distance_to(bp) > 0.1 else (f[1] as Vector2) * dir
			coach.position = Vector3(mid.x, _y(mid) + BED_TOP + 0.18 + RAIL_H, mid.y)
			coach.rotation = Vector3(0.0, atan2(fwd.x, fwd.y), 0.0)
