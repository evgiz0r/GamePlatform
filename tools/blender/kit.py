"""Helpers for tools/blender/recipes/*.py: build a low-poly model out of a few shapes in
metres, Z up in Blender (the export turns it to Godot's Y up), the ground at z = 0 and the
model's middle at x = y = 0.

Materials are named by ROLE, not colour -- "paint", "paint2", "metal", "plastic", "rubber",
"wood", "dark" -- and given a plain colour here. A game reads the material's name for each
surface and may colour it its own way (streets.gd's stamp_model does: real colours from its
tones, or the palette), so one model reads right in any look.

    import kit
    kit.box((2, 1, 0.1), (0, 0, 1.2), "paint")              # size, centre, material
    kit.cyl(0.05, 1.2, (0.9, 0.4, 0.6), "metal")              # radius, height, centre
    kit.tube([(0, 0, 1.2), (1, 0, 0.6), (2, 0, 0.1)], 0.3, "plastic", flat=True)

Every part is joined into one object at the end (finish), one surface per material.
"""
import math

import bpy
import bmesh

COLOURS = {
    "paint": (0.85, 0.2, 0.15), "paint2": (0.15, 0.45, 0.85), "paint3": (0.95, 0.75, 0.1),
    "metal": (0.55, 0.57, 0.6), "plastic": (0.2, 0.65, 0.3), "rubber": (0.12, 0.12, 0.12),
    "wood": (0.55, 0.38, 0.22), "dark": (0.18, 0.18, 0.2), "white": (0.92, 0.92, 0.9),
    "concrete": (0.7, 0.68, 0.64),
}
_mats = {}
_parts = []


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    _parts.clear()


def mat(role):
    if role not in _mats:
        m = bpy.data.materials.new(role)
        rgb = COLOURS.get(role, (0.8, 0.8, 0.8))
        m.diffuse_color = (*rgb, 1.0)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.6 if role != "metal" else 0.35
            bsdf.inputs["Metallic"].default_value = 0.8 if role == "metal" else 0.0
        _mats[role] = m
    return _mats[role]


def _obj(bm, role, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat(role))
    _parts.append(ob)
    return ob


def box(size, centre, role, rot=(0, 0, 0)):
    """a box size (x, y, z) at centre, turned by rot (radians about x, y, z)"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    ob = _obj(bm, role, "box")
    ob.rotation_euler = rot
    ob.location = centre
    return ob


def cyl(radius, height, centre, role, rot=(0, 0, 0), sides=10, radius2=None):
    """an upright cylinder (or cone, radius2 at the top) height tall, its middle at centre"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius,
                          radius2=radius if radius2 is None else radius2, depth=height)
    ob = _obj(bm, role, "cyl")
    ob.rotation_euler = rot
    ob.location = centre
    return ob


def ball(radius, centre, role, scale=(1, 1, 1), rings=6, sides=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=sides, v_segments=rings, radius=radius)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    ob = _obj(bm, role, "ball")
    ob.location = centre
    return ob


def rod(a, b, radius, role, sides=6):
    """a round bar from point a to point b"""
    ax, ay, az = a
    bx, by, bz = b
    d = (bx - ax, by - ay, bz - az)
    L = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2)
    ob = cyl(radius, L, ((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), role, sides=sides)
    # turn +Z onto d
    yaw = math.atan2(d[1], d[0])
    pitch = math.acos(max(-1.0, min(1.0, d[2] / L)))
    ob.rotation_euler = (0.0, pitch, yaw)
    return ob


def tube(points, width, role, flat=False, depth=0.06, steps=8):
    """a chute or rail along a smooth line through points: a flat trough `width` wide
    (flat=True: a slide's chute, its sides raised) or a round bar `width` across"""
    cu = bpy.data.curves.new("line", "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    cu.resolution_u = steps
    if flat:
        prof = bpy.data.curves.new("profile", "CURVE")
        ps = prof.splines.new("POLY")
        h = width / 2
        shape = [(-h, 0.18), (-h, 0), (h, 0), (h, 0.18)]
        ps.points.add(len(shape) - 1)
        for q, (x, y) in zip(ps.points, shape):
            q.co = (x, y, 0, 1)
        pob = bpy.data.objects.new("profile", prof)
        bpy.context.collection.objects.link(pob)
        cu.bevel_mode = "OBJECT"
        cu.bevel_object = pob
        cu.use_fill_caps = False
    else:
        cu.bevel_depth = width / 2
        cu.bevel_resolution = 2
    ob = bpy.data.objects.new("tube", cu)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.view_layer.objects.active
    if flat:
        sol = ob.modifiers.new("thick", "SOLIDIFY")
        sol.thickness = depth
        bpy.ops.object.modifier_apply(modifier=sol.name)
        bpy.data.objects.remove(bpy.data.objects["profile"])
    ob.data.materials.clear()
    ob.data.materials.append(mat(role))
    _parts.append(ob)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    return ob


def finish():
    """all the parts joined into one object (one surface per material), flat shaded"""
    parts = [p for p in _parts if p.name in bpy.data.objects]
    if not parts:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    ob.name = "model"
