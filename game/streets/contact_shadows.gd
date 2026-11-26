extends RefCounted
## Contact shadows (moved out of streets.gd; `g` is the game).
## Where a wall meets the ground, and under a parked car, less of the sky's light gets in and
## the ground is darker: what makes a house stand on the street and a car sit on it, rather
## than float over them (the walls' own feet are darker already, in WALL_SHADER). The
## Compatibility renderer has no ambient occlusion, so it is laid out with the city: soft
## dark strips multiplied over whatever ground is there -- one mesh a square, drawn after the
## ground, writing no depth, gone past AO_SEEN. Its ramp is UV.x (1 at the foot, 0 at the
## rim), its depth COLOR.r, a flat floor to the ramp COLOR.g (the ground under a block on
## columns, dark all over). It lies a little above the pavement, whatever is under it: on a
## lawn or a car park it floats a hand's width up, which a soft dark ramp does not show.
## COLOR.b 1: a tree's shadow instead (see "shadows past the shadows" below), there only
## where the real ones have ended, and not inside a building's.

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const AO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float strength = 0.62;
uniform float far = 150.0;
uniform vec2 sun_off = vec2(0.0);     // a shadow's reach on the ground per metre up
uniform float sun_stretch = 1.0;      // a ball's shadow, longer along the sun's way
varying vec3 wpos;
float h21(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
	if (COLOR.b > 0.5) {
		// a tree's patch is laid round the foot of its trunk (UV2), its crown's height in
		// COLOR.g (/ 40 m): moved out along the sun's way and drawn out, whichever sun it is
		float len = length(sun_off);
		vec2 way = len > 0.001 ? sun_off / len : vec2(1.0, 0.0);
		vec2 rel = VERTEX.xz - UV2;
		float h = COLOR.g * 40.0;
		VERTEX.xz = UV2 + sun_off * h + rel + way * dot(rel, way) * (sun_stretch - 1.0);
		VERTEX.y += len * h * 0.04;   // (on a slope, over the ground rather than in it)
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float d = length(VERTEX);
	float in_bld = texture(far_shadow, (wpos.xz - fs_rect.xy) * fs_rect.zw).r;
	if (COLOR.b > 0.5) {
		// a crown lets some light through: the shadow dappled, its rim soft
		float dap = 0.7 + 0.3 * vn(wpos.xz * 0.9);
		float a = smoothstep(0.0, 0.55, UV.x) * dap;
		float on = clamp((d - fs_near * fs_fade) / (fs_near * (1.0 - fs_fade) + 0.001), 0.0, 1.0);
		ALBEDO = vec3(1.0 - fs_dark * COLOR.r * a * on * (1.0 - in_bld));
	} else {
		float a = max(UV.x * UV.x, COLOR.g);   // (squared: falls away faster than the straight ramp)
		float fade = 1.0 - smoothstep(far * 0.5, far, d);
		ALBEDO = vec3(1.0 - strength * COLOR.r * a * fade);
	}
}
"""
const AO_SEEN := 150.0
const AO_W := 1.7             ## how far out from a wall the ground is darker (m)
var _ao: Streets.CBuf = null          ## this square's contact shadows, while it is built (_build_tile)
var _ao_mat: ShaderMaterial

func _ao_material() -> ShaderMaterial:
	if _ao_mat == null:
		_ao_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = g._with_far(AO_SHADER)
		_ao_mat.shader = sh
		_ao_mat.set_shader_parameter("far", AO_SEEN)
		_ao_mat.render_priority = -1   # (under the other see-through things: leaves, glass)
		g._far(_ao_mat)
	return _ao_mat

## the ground round a building's foot: a strip out from each wall, a fan round each outside
## corner. At an inside corner two strips overlap and it is darker still, as it is. (w
## negative: a strip in under it instead.) Built for every building, so every height is
## looked up once: it was 150 us a building done plainly, a third of the buildings' build.
func _ao_footprint(ring: PackedVector2Array, foot := 1.0, w := AO_W, col := Color(1, 0, 0)) -> void:
	var n := ring.size()
	if n > 1 and ring[0].distance_squared_to(ring[n - 1]) < 0.0001:
		n -= 1
	if n < 3:
		return
	var area := 0.0
	for i in range(n):
		area += ring[i].cross(ring[(i + 1) % n])
	var sg := 1.0 if area > 0.0 else -1.0   # out is to the right of each wall going round
	var y := Streets.KERB_H + 0.025
	var one := Vector2(foot, 0)
	var zero := Vector2.ZERO
	var up := Vector3.UP
	var foot3 := PackedVector3Array()
	foot3.resize(n)
	for i in range(n):
		foot3[i] = g._g3(ring[i], y)
	var carry := Vector3.INF     # the next wall's outer start, made by the corner before it
	for i in range(n):
		var i1 := (i + 1) % n
		var a := ring[i]
		var b := ring[i1]
		var L := a.distance_to(b)
		if L < 0.05:
			carry = Vector3.INF
			continue
		var d := (b - a) / L
		var o := Vector2(d.y, -d.x) * sg
		# the strip, in pieces short enough to follow the ground on a hill
		var k := maxi(1, int(L / 8.0))
		var f0 := foot3[i]
		var r0 := carry if carry != Vector3.INF else g._g3(a + o * w, y)
		for j in range(1, k + 1):
			var p1 := a.lerp(b, float(j) / k)
			var f1 := foot3[i1] if j == k else g._g3(p1, y)
			var r1 := g._g3(p1 + o * w, y)
			_ao.tri(f0, f1, r1, up, col, one, one, zero)
			_ao.tri(f0, r1, r0, up, col, one, zero, zero)
			f0 = f1
			r0 = r1
		carry = Vector3.INF
		# an outside corner at b: a fan from the last wall's strip round to the next one's
		var c := ring[(i + 2) % n]
		if c.distance_to(b) < 0.05:
			continue
		var d2 := (c - b).normalized()
		if d.cross(d2) * sg * signf(w) > 0.0:   # (turning towards the inside: the outside opens up)
			var o2 := Vector2(d2.y, -d2.x) * sg
			var turn := o.angle_to(o2)
			var steps := clampi(int(ceil(absf(turn) / 1.6)), 1, 3)   # (a right angle: one; the soft ramp hides the chamfer)
			for st in range(1, steps + 1):
				var nx := g._g3(b + o.rotated(turn * float(st) / steps) * w, y)
				_ao.tri(foot3[i1], r0, nx, up, col, one, zero, zero)
				r0 = nx
			carry = r0   # (b + o2 * w: where the next wall's strip starts)

## a soft round patch on the ground round c (a tree's trunk): dark in the middle, gone at r
func _ao_disc(c: Vector2, r: float, k: float) -> void:
	if _ao == null:
		return
	var col := Color(k, 0, 0)
	var mid := g._g3(c, Streets.KERB_H + 0.025)   # (one height: a metre across, the ground is level enough)
	var one := Vector2(1, 0)
	var last := mid + Vector3(r, 0, 0)
	for i in range(1, 7):
		var a := TAU * i / 6.0
		var q := mid + Vector3(cos(a) * r, 0, sin(a) * r)
		_ao.tri(mid, last, q, Vector3.UP, col, one, Vector2.ZERO, Vector2.ZERO)
		last = q

var _ao_cars: Array = []      ## [middle, nose] of the first cars given a patch (for tests)

## under a parked car (middle c, nose along fwd): dark under it, softening out past its sides
func _ao_car(c: Vector2, fwd: Vector2, lift: float) -> void:
	if _ao == null:
		return
	if _ao_cars.size() < 400:
		_ao_cars.append([c, fwd])
	var sd := Vector2(fwd.y, -fwd.x)
	var col := Color(1.0, 0, 0)
	var inner: Array = []
	var outer: Array = []
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		inner.append(c + sd * q.x * 0.75 + fwd * q.y * 1.95)
		outer.append(c + sd * q.x * 1.7 + fwd * q.y * 3.1)
	var one := Vector2(1, 0)
	var I: Array = []
	var O: Array = []
	for i in range(4):
		I.append(g._g3(inner[i], lift))
		O.append(g._g3(outer[i], lift))
	_ao.tri(I[0], I[1], I[2], Vector3.UP, col, one, one, one)
	_ao.tri(I[0], I[2], I[3], Vector3.UP, col, one, one, one)
	for i in range(4):
		var j := (i + 1) % 4
		_ao.tri(I[i], I[j], O[j], Vector3.UP, col, one, one, Vector2.ZERO)
		_ao.tri(I[i], O[j], O[i], Vector3.UP, col, one, Vector2.ZERO, Vector2.ZERO)
