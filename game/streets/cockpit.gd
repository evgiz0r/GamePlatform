extends RefCounted
## The driver's seat (moved out of streets.gd; `g` is the game).
## The view from behind the wheel, like a dashcam a little lower: the bonnet through the
## windscreen (the body's own faces point out, so from inside only the bonnet and the mirrors
## show), and inside, the dashboard, a steering wheel that turns with the front wheels, the
## windscreen pillars, the roof's edge and the mirror. Left-hand drive: the seat is on the
## car's left (+X, the car facing +Z).

const Streets := preload("res://game/streets/streets.gd")

var g: Streets

func _init(game: Streets) -> void:
	g = game

const SEAT := Vector3(0.37, 1.2, -0.32)

func _build_cockpit() -> void:
	g._cockpit_node = Node3D.new()
	g._cockpit_node.visible = false
	g._body.add_child(g._cockpit_node)
	var dark: Color = g._tone["cartrim"]
	var b := Streets.Buf.new()
	var box := func(c: Vector3, sz: Vector3, col: Color) -> void:
		var h := sz * 0.5
		for f: Array in [[Vector3(h.x, 0, 0), Vector3(0, h.y, 0), Vector3(0, 0, h.z)], [Vector3(-h.x, 0, 0), Vector3(0, h.y, 0), Vector3(0, 0, h.z)],
				[Vector3(0, h.y, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z)], [Vector3(0, -h.y, 0), Vector3(h.x, 0, 0), Vector3(0, 0, h.z)],
				[Vector3(0, 0, h.z), Vector3(h.x, 0, 0), Vector3(0, h.y, 0)], [Vector3(0, 0, -h.z), Vector3(h.x, 0, 0), Vector3(0, h.y, 0)]]:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var o: Vector3 = c + n
			b.tri(o - u - v, o + u - v, o + u + v, n.normalized(), col)
			b.tri(o - u - v, o + u + v, o - u + v, n.normalized(), col)
	# the dashboard under the windscreen (down to the footwell), the instrument hood in
	# front of the driver, the centre console, and the doors' insides below the windows
	box.call(Vector3(0, 0.7, 0.78), Vector3(1.7, 0.5, 0.62), dark)
	box.call(Vector3(0.37, 1.0, 0.55), Vector3(0.44, 0.1, 0.16), dark.darkened(0.2))   # the binnacle
	box.call(Vector3(0, 0.5, 0.2), Vector3(0.3, 0.3, 0.6), dark.lightened(0.05))
	for sx: float in [-1.0, 1.0]:
		box.call(Vector3(sx * 0.84, 0.66, 0.05), Vector3(0.05, 0.56, 1.9), dark.lightened(0.08))
	box.call(Vector3(0, 1.36, 0.36), Vector3(0.24, 0.07, 0.03), dark)           # the mirror
	box.call(Vector3(0, 1.4, 0.32), Vector3(0.03, 0.06, 0.03), dark)
	# the pillars beside the windscreen and the roof's edge over it, seen from inside
	var shape: Array = Streets.CAR_SHAPES["sedan"]
	var hw: float = shape[2]
	var c0: Vector2 = shape[1][0]
	var c1: Vector2 = shape[1][1]
	var lo := hw - 0.06
	var up := hw - 0.24
	var quad2 := func(a: Vector3, e: Vector3, f: Vector3, d: Vector3, col: Color) -> void:
		var n := (e - a).cross(d - a).normalized()
		for sg: float in [1.0, -1.0]:
			b.tri(a, e, f, n * sg, col)
			b.tri(a, f, d, n * sg, col)
	for sx: float in [-1.0, 1.0]:
		var foot := Vector3(lo * sx, c0.y, c0.x)
		var top := Vector3(up * sx, c1.y, c1.x)
		var inw := Vector3(-sx * 0.11, 0, 0)
		quad2.call(foot, top, top + inw + Vector3(0, -0.02, -0.03), foot + inw + Vector3(0, 0, -0.04), dark)
	quad2.call(Vector3(-up, c1.y - 0.01, c1.x), Vector3(up, c1.y - 0.01, c1.x), Vector3(up, c1.y + 0.01, c1.x - 0.5),
			Vector3(-up, c1.y + 0.01, c1.x - 0.5), dark.lightened(0.1))
	# the bonnet through the windscreen, in the car's paint (the body itself is hidden here:
	# it is built to be seen from outside, and from inside it showed its backs)
	var low: Array = shape[0]
	var hb := Streets.Buf.new()
	var hood: Array = []
	for q: Vector2 in low:
		if q.x > c0.x - 0.05 and q.y > 0.5:
			hood.append(q)
	hood.sort_custom(func(a: Vector2, e: Vector2): return a.x < e.x)
	for i in range(hood.size() - 1):
		var a: Vector2 = hood[i]
		var e: Vector2 = hood[i + 1]
		var n := Vector3(0, e.x - a.x, -(e.y - a.y)).normalized()
		if n.y < 0.0:
			n = -n
		hb.tri(Vector3(-hw, a.y, a.x), Vector3(hw, a.y, a.x), Vector3(hw, e.y, e.x), n, Color.WHITE)
		hb.tri(Vector3(-hw, a.y, a.x), Vector3(hw, e.y, e.x), Vector3(-hw, e.y, e.x), n, Color.WHITE)
	var hmi := MeshInstance3D.new()
	var ham := ArrayMesh.new()
	ham.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hb.arrays())
	ham.surface_set_material(0, g._car_mat("paint", "paint"))
	hmi.mesh = ham
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g._cockpit_node.add_child(hmi)
	var mi := MeshInstance3D.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	am.surface_set_material(0, m)
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g._cockpit_node.add_child(mi)
	# the wheel: a ring and three spokes, tilted back toward the driver, turned with the
	# front wheels (about 15 turns of it to one of theirs)
	# the speedometer and rev counter in the binnacle, facing the driver, and the green
	# indicator arrows between them
	var face_c: Color = g._tone["tyre"].darkened(0.4)
	var tick_c: Color = g._tone["mark"]
	var dial_at := [Vector3(0.465, 1.03, 0.43), Vector3(0.275, 1.03, 0.43)]
	var dial_b := Basis(Vector3.RIGHT, 0.32)   # tipped back toward the eyes
	var b0: Streets.Buf = b
	b = Streets.Buf.new()   # (the cockpit's own mesh is built already: the dials get one of theirs)
	for di in range(2):
		var c: Vector3 = dial_at[di]
		var R := 0.052
		for i in range(16):
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 1) / 16.0
			var e0 := Vector3(cos(a0), sin(a0), 0)
			var e1 := Vector3(cos(a1), sin(a1), 0)
			b.tri(c, c + dial_b * (e0 * R), c + dial_b * (e1 * R), dial_b * Vector3.FORWARD, face_c)
			# a bright rim round it, so the dial reads in a dark cabin
			var z := Vector3(0, 0, -0.001)
			b.tri(c + dial_b * (e0 * R + z), c + dial_b * (e0 * (R + 0.006) + z), c + dial_b * (e1 * (R + 0.006) + z), dial_b * Vector3.FORWARD, tick_c)
			b.tri(c + dial_b * (e0 * R + z), c + dial_b * (e1 * (R + 0.006) + z), c + dial_b * (e1 * R + z), dial_b * Vector3.FORWARD, tick_c)
		for i in range(9):
			var a := 2.2 - 4.4 * i / 8.0 + PI * 0.5
			var d := Vector3(cos(a), sin(a), 0)
			var nn := Vector3(-d.y, d.x, 0) * 0.003
			var p0 := d * R * 0.78
			var p1 := d * R * 0.95
			b.tri(c + dial_b * (p0 - nn + Vector3(0, 0, -0.002)), c + dial_b * (p1 - nn + Vector3(0, 0, -0.002)), c + dial_b * (p1 + nn + Vector3(0, 0, -0.002)), dial_b * Vector3.FORWARD, tick_c)
			b.tri(c + dial_b * (p0 - nn + Vector3(0, 0, -0.002)), c + dial_b * (p1 + nn + Vector3(0, 0, -0.002)), c + dial_b * (p0 + nn + Vector3(0, 0, -0.002)), dial_b * Vector3.FORWARD, tick_c)
		var pivot := Node3D.new()
		pivot.position = c + dial_b * Vector3(0, 0, -0.004)
		pivot.basis = dial_b
		g._cockpit_node.add_child(pivot)
		var needle := MeshInstance3D.new()
		var nm := BoxMesh.new()
		nm.size = Vector3(0.004, 0.05, 0.002)
		needle.mesh = nm
		needle.position = Vector3(0, 0.022, 0)
		needle.material_override = g.mat("hazard", 1.4)
		pivot.add_child(needle)
		if di == 0:
			g._dial_speed = pivot
		else:
			g._dial_rpm = pivot
	var dmi := MeshInstance3D.new()
	var dam := ArrayMesh.new()
	dam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
	dam.surface_set_material(0, m)
	dmi.mesh = dam
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g._cockpit_node.add_child(dmi)
	b = b0
	for side: int in [-1, 1]:
		var arrow := MeshInstance3D.new()
		var ab := Streets.Buf.new()
		var sx := -float(side)   # the car's right is -X
		var c := Vector3(0.37 + sx * 0.03, 1.03, 0.43)
		ab.tri(c + dial_b * Vector3(sx * 0.018, 0, -0.003), c + dial_b * Vector3(-sx * 0.01, 0.013, -0.003), c + dial_b * Vector3(-sx * 0.01, -0.013, -0.003), dial_b * Vector3.FORWARD, Color.WHITE)
		var aam := ArrayMesh.new()
		aam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ab.arrays())
		arrow.mesh = aam
		arrow.material_override = g.mat("friend", 2.2)
		arrow.visible = false
		g._cockpit_node.add_child(arrow)
		g._dash_arrows[side] = arrow
	g._wheel_node = Node3D.new()
	g._wheel_node.position = Vector3(0.37, 0.94, 0.3)
	g._wheel_node.rotation.x = -0.45
	g._cockpit_node.add_child(g._wheel_node)
	var wb := Streets.Buf.new()
	var rim := dark.darkened(0.3)
	var R := 0.185
	for i in range(14):
		var a0 := TAU * i / 14.0
		var a1 := TAU * (i + 1) / 14.0
		var p0 := Vector3(cos(a0) * R, sin(a0) * R, 0)
		var p1 := Vector3(cos(a1) * R, sin(a1) * R, 0)
		var r0 := p0.normalized() * 0.022
		var r1 := p1.normalized() * 0.022
		for side: float in [1.0, -1.0]:
			var zz := Vector3(0, 0, 0.022 * side)
			wb.tri(p0 + zz - r0, p1 + zz - r1, p1 + zz + r1, Vector3(0, 0, side), rim)
			wb.tri(p0 + zz - r0, p1 + zz + r1, p0 + zz + r0, Vector3(0, 0, side), rim)
			wb.tri(p0 + r0 * side - zz, p1 + r1 * side - zz, p1 + r1 * side + zz, p0.normalized() * side, rim)
			wb.tri(p0 + r0 * side - zz, p1 + r1 * side + zz, p0 + r0 * side + zz, p0.normalized() * side, rim)
	for a: float in [PI * 0.5 + PI, 0.0, PI]:
		var d := Vector3(cos(a), sin(a), 0) * R
		var n := Vector3(-d.y, d.x, 0).normalized() * 0.02
		for side: float in [1.0, -1.0]:
			var zz := Vector3(0, 0, 0.012 * side)
			wb.tri(zz - n, d + zz - n, d + zz + n, Vector3(0, 0, side), rim)
			wb.tri(zz - n, d + zz + n, zz + n, Vector3(0, 0, side), rim)
	var wmi := MeshInstance3D.new()
	var wam := ArrayMesh.new()
	wam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wb.arrays())
	wam.surface_set_material(0, m)
	wmi.mesh = wam
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g._wheel_node.add_child(wmi)
