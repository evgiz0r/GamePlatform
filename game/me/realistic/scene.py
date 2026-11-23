# Stage one clip and render it to frames.
#   python scene.py -- clip.blend outdir --scene walk|wave|dance|teach --from F --to F [--res 960x540] [--samples 16] [--only 1,50]
import bpy, sys, os, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
IN, OUTD = a[0], a[1]
def opt(k, d):
    return a[a.index(k) + 1] if k in a else d
SCENE = opt("--scene", "wave")
F0, F1 = int(opt("--from", "1")), int(opt("--to", "60"))
bpy.ops.wm.open_mainfile(filepath=IN)
scn = bpy.context.scene
scn.render.engine = "BLENDER_EEVEE"
scn.eevee.taa_render_samples = int(opt("--samples", "16"))
try:
    scn.eevee.use_shadows = True
    scn.eevee.use_raytracing = False
except Exception:
    pass
w, h = opt("--res", "960x540").split("x")
scn.render.resolution_x, scn.render.resolution_y = int(w), int(h)
scn.render.image_settings.file_format = "PNG"
rig = bpy.data.objects["Rig"]
cam = scn.camera
cam.data.lens = 32

def mat(name, col, rough=0.6, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*col, 1)
    p.inputs["Roughness"].default_value = rough
    if emit:
        p.inputs["Emission Color"].default_value = (*col, 1)
        p.inputs["Emission Strength"].default_value = emit
    return m

def box(name, size, loc, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = size
    o.data.materials.append(m)
    return o

def hips(f):
    scn.frame_set(f)
    return rig.matrix_world @ rig.pose.bones["Hips"].head

# a back wall so the studio has depth
box("Wall", (90, 0.2, 8), (0, 6, 4), mat("wall", (0.06, 0.065, 0.08), 0.9))
start = hips(F0)

if SCENE == "teach":
    # a whiteboard behind his left shoulder, with the lesson on it
    fwd = Vector()
    for f in range(F0, F1 + 1, 5):
        scn.frame_set(f)
        Lv = (rig.matrix_world @ rig.pose.bones["LeftUpLeg"].head) - (rig.matrix_world @ rig.pose.bones["RightUpLeg"].head); Lv.z = 0
        fwd += Lv.cross(Vector((0, 0, 1))).normalized()
    fwd.z = 0; fwd.normalize()
    left = Vector((-fwd.y, fwd.x, 0))
    bc = Vector((start.x, start.y, 1.45)) - fwd * 0.7 + left * 1.75
    # everything for the board is built facing -Y round its centre, then turned to face him
    yaw = math.atan2(fwd.x, -fwd.y)
    bpy.ops.object.empty_add(location=bc); piv = bpy.context.active_object; piv.name = "BoardPivot"
    parts = [box("Board", (1.9, 0.03, 1.1), Vector((0, 0, 0)), mat("board", (0.9, 0.9, 0.88), 0.25)),
             box("Frame", (1.98, 0.02, 1.18), Vector((0, 0.02, 0)), mat("frame", (0.5, 0.5, 0.52), 0.4))]
    for sx in (-0.75, 0.75):
        parts.append(box("Leg", (0.04, 0.04, 0.95), Vector((sx, 0.04, 0.47 - bc.z)), mat("frame2", (0.5, 0.5, 0.52), 0.4)))
    lines = [("how a city moves:", (0.08, 0.1, 0.35)), ("roads + cars + people", (0.08, 0.1, 0.35)), ("= streets", (0.7, 0.08, 0.06))]
    for i, (t, col) in enumerate(lines):
        cu = bpy.data.curves.new("L%d" % i, "FONT"); cu.body = t; cu.size = 0.13
        o = bpy.data.objects.new("L%d" % i, cu); scn.collection.objects.link(o)
        o.location = Vector((-0.82, -0.02, 0.3 - i * 0.24))
        o.rotation_euler = (math.radians(90), 0, 0)
        o.data.materials.append(mat("ink%d" % i, col, 0.5))
        parts.append(o)
    for p in parts:
        p.parent = piv
    piv.rotation_euler = (0, 0, yaw)
if SCENE == "dance":
    # coloured party lights
    for i, col in enumerate([(1, 0.2, 0.6), (0.2, 0.6, 1), (0.9, 0.7, 0.2)]):
        d = bpy.data.lights.new("P%d" % i, "SPOT"); d.energy = 900; d.color = col; d.spot_size = 0.9
        o = bpy.data.objects.new("P%d" % i, d); scn.collection.objects.link(o)
        ang = i * 2.1
        o.location = Vector((start.x + 3 * math.cos(ang), start.y + 3 * math.sin(ang), 3.5))
        c = o.constraints.new("TRACK_TO"); c.target = rig; c.track_axis = "TRACK_NEGATIVE_Z"
        o.data.keyframe_insert("energy", frame=F0)
        for f in range(F0, F1 + 1, 8):
            d.energy = 500 + 900 * (0.5 + 0.5 * math.sin(f * 0.35 + i * 2))
            d.keyframe_insert("energy", frame=f)
    bpy.data.objects["Key"].data.energy *= 0.6

# camera: follows his hips and stays in front of where he faces (smoothed), slowly drifting
pts, fwds = {}, {}
for f in range(F0, F1 + 1):
    scn.frame_set(f)
    pts[f] = rig.matrix_world @ rig.pose.bones["Hips"].head
    L = (rig.matrix_world @ rig.pose.bones["LeftUpLeg"].head) - (rig.matrix_world @ rig.pose.bones["RightUpLeg"].head)
    L.z = 0
    fwds[f] = L.cross(Vector((0, 0, 1))).normalized()
def smooth(d, f, k):
    s = Vector(); n = 0
    for g in range(f - k, f + k + 1):
        if g in d:
            s += d[g]; n += 1
    return s / n
DIST = {"walk": 4.2, "wave": 3.6, "dance": 4.0, "teach": 4.2}[SCENE]
for f in range(F0, F1 + 1):
    c = smooth(pts, f, 12)
    fw = smooth(fwds, f, 45); fw.z = 0; fw.normalize()
    t = (f - F0) / max(1, F1 - F0)
    ang = {"walk": 0.55, "wave": 0.25 - 0.3 * t, "dance": -0.5 + 1.0 * t, "teach": 0.35}[SCENE]
    side = Vector((fw.y, -fw.x, 0))
    d = (fw * math.cos(ang) + side * math.sin(ang)).normalized()
    if SCENE == "teach":
        c = smooth(pts, F0 + (F1 - F0) // 2, 400)
    tgt = Vector((c.x, c.y, 1.0))
    cam.location = tgt + d * DIST + Vector((0, 0, 0.3))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.keyframe_insert("location", frame=f)
    cam.keyframe_insert("rotation_euler", frame=f)
# lights ride with him on long walks
for n in ("Key", "Fill", "Rim"):
    L = bpy.data.objects[n]
    base = L.location.copy()
    for f in range(F0, F1 + 1, 6):
        c = smooth(pts, f, 12)
        L.location = base + Vector((c.x, c.y, 0))
        L.keyframe_insert("location", frame=f)

os.makedirs(OUTD, exist_ok=True)
only = opt("--only", "")
frames = [int(x) for x in only.split(",")] if only else range(F0, F1 + 1)
for f in frames:
    scn.frame_set(f)
    scn.render.filepath = os.path.join(OUTD, "f%04d.png" % (f - F0))
    if os.path.exists(scn.render.filepath) and not only:
        continue
    bpy.ops.render.render(write_still=True)
print("DONE", SCENE)
