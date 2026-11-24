# Build a realistic human (MakeHuman CC0 base mesh + targets) shaped and dressed like Evgeni,
# rigged with the CMU-mocap-named skeleton (MPFB rig/weights data), saved to me.blend.
# Data only: reads .obj/.target/.json files, runs no add-on code.
import bpy, bmesh, gzip, json, math, os, sys
from mathutils import Vector, Matrix

MH = os.environ.get("MH_DATA", "work/mh/makehuman/data")
MP = os.environ.get("MPFB_DATA", "work/mpfb2/src/mpfb/data")
OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "work/me.blend"

# ---- body shape (MakeHuman modifier values) ------------------------------------------
# macro: male, about 35, average muscle, a little soft, average height; then a face nudged
# toward the photos: long oval face, narrow chin, a high forehead, slightly long nose.
TARGETS = {
    "macrodetails/universal-male-young-averagemuscle-averageweight": 0.8,
    "macrodetails/universal-male-young-averagemuscle-maxweight": 0.2,
    "macrodetails/caucasian-male-young": 1.0,
    "head/head-oval": 0.6,
    "head/head-scale-vert-incr": 0.25,
    "head/head-scale-horiz-decr": 0.15,
    "chin/chin-width-decr": 0.3,
    "chin/chin-prominent-incr": 0.2,
    "forehead/forehead-scale-vert-incr": 0.4,
    "nose/nose-scale-vert-incr": 0.25,
    "nose/nose-width1-decr": 0.15,
    "cheek/l-cheek-bones-decr": 0.2, "cheek/r-cheek-bones-decr": 0.2,
    "neck/neck-scale-depth-decr": 0.1,
    "stomach/stomach-pregnant-incr": 0.05,
    # he said: "some boobs" -- flatter chest
    "torso/torso-muscle-pectoral-decr": 0.9,
    "breast/breast-point-decr": 0.8,
    "breast/breast-volume-vert-down": 0.6,
    "torso/torso-scale-depth-decr": 0.15,
}

def read_obj(path):
    vs, vts, faces, groups = [], [], [], []
    g = "body"
    for line in open(path):
        if line.startswith("v "):
            _, x, y, z = line.split()[:4]
            vs.append((float(x), float(y), float(z)))
        elif line.startswith("vt "):
            p = line.split()
            vts.append((float(p[1]), float(p[2])))
        elif line.startswith("g "):
            g = line.split()[1]
        elif line.startswith("f "):
            idx = [w.split("/") for w in line.split()[1:]]
            faces.append(([int(a[0]) - 1 for a in idx], [int(a[1]) - 1 if len(a) > 1 and a[1] else -1 for a in idx]))
            groups.append(g)
    return vs, vts, faces, groups

def read_target(name):
    p = os.path.join(MH, "targets", name + ".target")
    if not os.path.exists(p):
        print("MISSING TARGET", name)
        return {}
    d = {}
    for line in open(p):
        if line.startswith("#") or not line.strip():
            continue
        a = line.split()
        d[int(a[0])] = (float(a[1]), float(a[2]), float(a[3]))
    return d

vs, vts, faces, fgroups = read_obj(os.path.join(MH, "3dobjs/base.obj"))
co = [list(v) for v in vs]
for name, w in TARGETS.items():
    for i, d in read_target(name).items():
        co[i][0] += d[0] * w; co[i][1] += d[1] * w; co[i][2] += d[2] * w

# MakeHuman: decimetres, Y up, facing +Z.  Blender: metres, Z up, facing -Y.
def mh2b(p):
    return Vector((p[0] * 0.1, -p[2] * 0.1, p[1] * 0.1))
bco = [mh2b(p) for p in co]

# joint positions: the mean of each joint cube's vertices
vgroups = json.load(open(os.path.join(MP, "mesh_metadata/basemesh_vertex_groups.json")))
def group_verts(name):
    out = []
    for a, b in vgroups[name]:
        out.extend(range(a, b + 1))
    return out
def joint(name):
    ids = group_verts(name)
    return sum((bco[i] for i in ids), Vector()) / len(ids)

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene

def make_obj(name, keep_groups, mat_by_group):
    used = [k for k, g in enumerate(fgroups) if g in keep_groups]
    vmap = {}
    for k in used:
        for vi in faces[k][0]:
            if vi not in vmap:
                vmap[vi] = len(vmap)
    inv = sorted(vmap, key=vmap.get)
    me = bpy.data.meshes.new(name)
    me.from_pydata([bco[i] for i in inv], [], [[vmap[v] for v in faces[k][0]] for k in used])
    uv = me.uv_layers.new(name="UVMap")
    li = 0
    for k in used:
        for t in faces[k][1]:
            uv.data[li].uv = vts[t] if t >= 0 else (0, 0)
            li += 1
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    scn.collection.objects.link(ob)
    ob["src_index"] = inv   # basemesh vertex index of each vertex (for weights)
    names = sorted(set(mat_by_group.values()))
    for n in names:
        me.materials.append(bpy.data.materials.get(n) or bpy.data.materials.new(n))
    for p, k in zip(me.polygons, used):
        p.material_index = names.index(mat_by_group[fgroups[k]])
    return ob

body = make_obj("Body", {"body", "helper-upper-teeth", "helper-lower-teeth", "helper-tongue"},
                {"body": "skin", "helper-l-eye": "eye", "helper-r-eye": "eye",
                 "helper-l-eyelashes-1": "lash", "helper-r-eyelashes-1": "lash",
                 "helper-l-eyelashes-2": "lash", "helper-r-eyelashes-2": "lash",
                 "helper-upper-teeth": "teeth", "helper-lower-teeth": "teeth", "helper-tongue": "mouth"})
eyes = [make_obj("EyeL", {"helper-l-eye"}, {"helper-l-eye": "eye"}), make_obj("EyeR", {"helper-r-eye"}, {"helper-r-eye": "eye"})]
tights = make_obj("Tights", {"body"}, {"body": "cloth"})   # clothes cut from his own skin surface
hairshell = make_obj("HairShell", {"helper-hair"}, {"helper-hair": "hairscalp"})

# feet on the ground
zmin = min(v.co.z for v in body.data.vertices)
for ob in (body, tights, hairshell, *eyes):
    for v in ob.data.vertices:
        v.co.z -= zmin
GROUND = zmin
print("height", max(v.co.z for v in body.data.vertices))

# ---- rig --------------------------------------------------------------------------------
rig = json.load(open(os.path.join(MP, "rigs/standard/rig.cmu_mb.json")))
def place(spec):
    if spec["strategy"] == "CUBE":
        p = joint(spec["cube_name"])
    else:
        ids = spec["vertex_indices"]
        p = sum((bco[i] for i in ids), Vector()) / len(ids)
    return p - Vector((0, 0, GROUND))
arm = bpy.data.armatures.new("Rig")
rob = bpy.data.objects.new("Rig", arm)
scn.collection.objects.link(rob)
bpy.context.view_layer.objects.active = rob
bpy.ops.object.mode_set(mode="EDIT")
order = []
def visit(n):
    order.append(n)
    for k, v in rig.items():
        if v["parent"] == n:
            visit(k)
for k, v in rig.items():
    if v["parent"] == "":
        visit(k)
for n in order:
    spec = rig[n]
    eb = arm.edit_bones.new(n)
    eb.head = place(spec["head"])
    eb.tail = place(spec["tail"])
    if (eb.tail - eb.head).length < 1e-4:
        eb.tail = eb.head + Vector((0, 0, 0.02))
    eb.roll = spec["roll"]
    if spec["parent"]:
        eb.parent = arm.edit_bones[spec["parent"]]
        eb.use_connect = spec.get("use_connect", False)
bpy.ops.object.mode_set(mode="OBJECT")

weights = json.load(open(os.path.join(MP, "rigs/standard/weights.cmu_mb.json")))["weights"]
def skin(ob):
    src = list(ob["src_index"])
    back = {s: i for i, s in enumerate(src)}
    for bone, pairs in weights.items():
        vg = ob.vertex_groups.new(name=bone)
        for vi, w in pairs:
            if vi in back:
                vg.add([back[vi]], w, "REPLACE")
    ob.parent = rob
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rob
for ob in (body, tights):
    skin(ob)

def on_head(ob):
    hb = rob.data.bones["Head"]
    ob.parent = rob; ob.parent_type = "BONE"; ob.parent_bone = "Head"
    ob.matrix_parent_inverse = (rob.matrix_world @ Matrix.Translation(hb.tail_local) @ hb.matrix_local.to_3x3().to_4x4()).inverted()
for e in eyes:
    c = sum((v.co for v in e.data.vertices), Vector()) / len(e.data.vertices)
    for v in e.data.vertices:
        v.co -= c
    e.location = c
    on_head(e)

# ---- clothes from the tights shell ---------------------------------------------------------
# shirt: torso + upper arms (short sleeves end mid upper arm); trousers: waist to ankle.
ARMB = {"LeftArm", "LeftForeArm", "LeftHand", "LeftFingerBase", "LeftHandFinger1", "LThumb",
        "RightArm", "RightForeArm", "RightHand", "RightFingerBase", "RightHandFinger1", "RThumb"}
arm_src = set()
for bn in ARMB:
    for vi, w in weights.get(bn, []):
        if w > 0.05:
            arm_src.add(vi)
def is_arm(ob, f):
    src = ob["src_index"]
    return any(src[v.index] in arm_src for v in f.verts)
def zone_split(ob):
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    pelvis = joint("joint-pelvis").z - GROUND
    shoulder_l = joint("joint-l-shoulder") - Vector((0, 0, GROUND))
    elbow_l = joint("joint-l-elbow") - Vector((0, 0, GROUND))
    sleeve_x = shoulder_l.x + (elbow_l.x - shoulder_l.x) * 0.55
    ankle = joint("joint-l-ankle").z - GROUND + 0.03
    shirt_faces, pants_faces = [], []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.z >= pelvis + 0.025 and abs(c.x) <= abs(sleeve_x) and c.z <= shoulder_l.z + 0.25:
            shirt_faces.append(f.index)       # down over the hips, like a tee worn out
        if ankle < c.z <= pelvis + 0.09 and not is_arm(ob, f):
            pants_faces.append(f.index)       # up to the waist, under the shirt's hem
    bm.free()
    return set(shirt_faces), set(pants_faces), pelvis

shirt_f, pants_f, WAIST = zone_split(tights)
def piece(name, keep, matname, push):
    ob = tights.copy(); ob.data = tights.data.copy(); ob.name = name
    scn.collection.objects.link(ob)
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bm.to_mesh(ob.data); bm.free()
    ob.data.materials.clear(); ob.data.materials.append(bpy.data.materials.get(matname) or bpy.data.materials.new(matname))
    for p in ob.data.polygons: p.material_index = 0
    d = ob.modifiers.new("Push", "DISPLACE"); d.strength = push; d.mid_level = 0.0
    ob.modifiers.move(len(ob.modifiers) - 1, 0)
    sm = ob.modifiers.new("Relax", "SMOOTH"); sm.factor = 0.5; sm.iterations = 5
    ob.modifiers.move(len(ob.modifiers) - 1, 1)
    s = ob.modifiers.new("Thick", "SOLIDIFY"); s.thickness = 0.004; s.offset = 1.0
    sub = ob.modifiers.new("Smooth", "SUBSURF"); sub.levels = 1; sub.render_levels = 1
    return ob
shirt = piece("Shirt", shirt_f, "shirt", 0.009)
pants = piece("Trousers", pants_f, "trousers", 0.011)
bpy.data.objects.remove(tights)

# the neckline: a V cut into the shirt's front
bm = bmesh.new(); bm.from_mesh(shirt.data)
neck = joint("joint-neck") - Vector((0, 0, GROUND))
vtip = neck.z - 0.13
kill = [f for f in bm.faces if (lambda c: c.y < neck.y - 0.02 and c.z > vtip + abs(c.x) * 2.4 and abs(c.x) < 0.08)(f.calc_center_median())]
bmesh.ops.delete(bm, geom=kill, context="FACES")
bm.to_mesh(shirt.data); bm.free()

ank = joint("joint-l-ankle").z - GROUND + 0.035
if "shoes" not in body.data.materials:
    body.data.materials.append(bpy.data.materials.new("shoes"))
shoe_i = list(body.data.materials.keys()).index("shoes")
skin_i0 = list(body.data.materials.keys()).index("skin")
for p in body.data.polygons:
    if p.material_index == skin_i0 and p.center.z < ank:
        p.material_index = shoe_i

pel = joint("joint-pelvis").z - GROUND
shl = joint("joint-l-shoulder") - Vector((0, 0, GROUND))
elb = joint("joint-l-elbow") - Vector((0, 0, GROUND))
slx = abs(shl.x + (elb.x - shl.x) * 0.55) - 0.04
ankz = joint("joint-l-ankle").z - GROUND + 0.07
bm = bmesh.new(); bm.from_mesh(body.data); bm.faces.ensure_lookup_table()
sk_i = list(body.data.materials.keys()).index("skin")
def covered(c, f):
    if pel + 0.06 < c.z < neck.z - 0.07 and abs(c.x) < slx and not (c.y < neck.y - 0.0 and c.z > vtip - 0.03 + abs(c.x) * 2.4 and abs(c.x) < 0.1):
        return True
    return ankz < c.z < pel + 0.05 and not is_arm(body, f)
gone = [f for f in bm.faces if f.material_index == sk_i and covered(f.calc_center_median(), f)]
bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
bm.to_mesh(body.data); bm.free()

# stubble: a per-vertex mask baked at rest (jaw, chin, upper lip), read by the skin shader
hz = joint("joint-head").z - GROUND
nk = joint("joint-neck") - Vector((0, 0, GROUND))
mouthz = joint("joint-jaw").z - GROUND
att = body.data.color_attributes.new("stubble", "FLOAT_COLOR", "POINT")
hy = sum(v.co.y for v in body.data.vertices if v.co.z > hz) / max(1, sum(1 for v in body.data.vertices if v.co.z > hz))
for v in body.data.vertices:
    c = v.co
    m = 0.0
    if nk.z + 0.03 < c.z < hz + 0.07 and c.y < hy - 0.02:
        m = 1.0
        m *= min(1.0, max(0.0, (hz + 0.07 - c.z) / 0.025))      # fades out under the cheekbones
        m *= min(1.0, max(0.0, (c.z - nk.z - 0.03) / 0.02))      # and down the neck
        m *= min(1.0, max(0.0, (hy - 0.02 - c.y) / 0.03))
    att.data[v.index].color = (m, m, m, 1)

# ---- subdivide the body for close-ups ---------------------------------------------------
sub = body.modifiers.new("Smooth", "SUBSURF"); sub.levels = 1; sub.render_levels = 1

# ---- hair: particle hair on the scalp shell ----------------------------------------------
# scalp: by direction from the skull's centre -- a hairline high at the front, receding a
# little at the temples, just above the ears at the sides, low at the nape
bm = bmesh.new(); bm.from_mesh(body.data)
head = joint("joint-head") - Vector((0, 0, GROUND))
eyez = joint("joint-l-eye").z - GROUND
skin_i = list(body.data.materials.keys()).index("skin")
hv = [v.co for v in body.data.vertices if v.co.z > eyez]
lo = Vector((min(c.x for c in hv), min(c.y for c in hv), min(c.z for c in hv)))
hi = Vector((max(c.x for c in hv), max(c.y for c in hv), max(c.z for c in hv)))
C = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, eyez + 0.01))
top, cy = hi.z, C.y
HL = [(0.0, 0.42), (0.35, 0.48), (0.6, 0.45), (0.95, 0.36), (1.35, 0.30), (1.75, 0.22), (2.2, -0.15), (2.6, -0.55), (math.pi, -0.6)]
def hair_level(c, jitter=0.0):
    d = (c - C)
    phi = abs(math.atan2(d.x, -d.y))
    for (p0, t0), (p1, t1) in zip(HL, HL[1:]):
        if phi <= p1:
            th = t0 + (t1 - t0) * (phi - p0) / (p1 - p0)
            break
    return d.normalized().z - th - jitter
def hairline_ok(c, margin=0.0):
    return hair_level(c) > margin
scalp = bpy.data.meshes.new("Scalp")
cand = [f for f in bm.faces if f.material_index == skin_i and f.calc_center_median().z > eyez - 0.06]
def mesh_of(faces):
    sbm = bmesh.new(); vmap = {}
    for f in faces:
        vv = []
        for v in f.verts:
            if v.index not in vmap:
                vmap[v.index] = sbm.verts.new(v.co)
            vv.append(vmap[v.index])
        sbm.faces.new(vv)
    sbm.normal_update()
    m = bpy.data.meshes.new("m"); sbm.to_mesh(m); sbm.free()
    return m
emit = mesh_of([f for f in cand if hairline_ok(f.calc_center_median(), -0.12)])
scalp = mesh_of([f for f in cand if hairline_ok(f.calc_center_median(), 0.16)])
bm.free()
bpy.data.objects.remove(hairshell)
hairshell = bpy.data.objects.new("Scalp", scalp)
# strands as a Curves object, rigid with the head (short hair barely moves)
import random
rnd = random.Random(7)
me = emit
tris = []
for poly in me.polygons:
    vs_ = [me.vertices[i].co for i in poly.vertices]
    for k in range(1, len(vs_) - 1):
        a_, b_, c_ = vs_[0], vs_[k], vs_[k + 1]
        tris.append((a_, b_, c_, ((b_ - a_).cross(c_ - a_)).length / 2, poly.normal.copy()))
total = sum(t[3] for t in tris)
N = 30000
SEG = 5
cum, acc = [], 0.0
for t in tris:
    acc += t[3]; cum.append(acc)
import bisect
hc = bpy.data.hair_curves.new("Hair")
hc.add_curves([SEG] * N)
pos = hc.attributes["position"].data
crown = head + Vector((0, 0.03, 0.12))
for n in range(N):
    t = tris[min(bisect.bisect(cum, rnd.random() * total), len(tris) - 1)]
    u, v = rnd.random(), rnd.random()
    if u + v > 1: u, v = 1 - u, 1 - v
    root = t[0] + (t[1] - t[0]) * u + (t[2] - t[0]) * v
    lvl = hair_level(root, rnd.gauss(0, 0.035))
    if lvl < 0:
        for k in range(SEG):
            pos[n * SEG + k].vector = C
        continue
    nrm = t[4].normalized()
    # combed: away from the crown, along the scalp, a little forward on top like his
    along = (root - crown); along -= nrm * along.dot(nrm)
    if along.length < 1e-5: along = Vector((0, -1, 0))
    along.normalize()
    if root.y < cy - 0.03:
        along = (Vector((0, 0.5, 1.0)) - nrm * Vector((0, 0.5, 1.0)).dot(nrm)).normalized()   # front: up and back
    L = 0.014 + 0.022 * rnd.random() * (1.0 if root.z > top - 0.06 else 0.4)
    thin = min(1.0, lvl / 0.05)        # short and sparse at the hairline
    L *= 0.5 + 0.5 * thin
    p = root - nrm * 0.002
    for k in range(SEG):
        pos[n * SEG + k].vector = p
        lift = nrm * (0.5 * (1 - k / SEG)) + along
        p = p + lift.normalized() * (L / (SEG - 1)) + Vector((rnd.gauss(0, 0.0012), rnd.gauss(0, 0.0012), rnd.gauss(0, 0.0012)))
rad = hc.attributes.get("radius") or hc.attributes.new("radius", "FLOAT", "POINT")
for k in range(N * SEG):
    rad.data[k].value = 0.0001 * (1.0 - 0.7 * ((k % SEG) / (SEG - 1)))
hob = bpy.data.objects.new("Hair", hc)
scn.collection.objects.link(hob)
hc.materials.append(bpy.data.materials.get("hair") or bpy.data.materials.new("hair"))
# rigid on the Head bone
hob.parent = rob; hob.parent_type = "BONE"; hob.parent_bone = "Head"
hb = rob.data.bones["Head"]
hob.matrix_parent_inverse = (rob.matrix_world @ Matrix.Translation(hb.tail_local) @ hb.matrix_local.to_3x3().to_4x4()).inverted()
# the scalp under it, pushed out a hair's width and coloured dark, so short hair reads dense
for v in hairshell.data.vertices:
    v.co += v.normal * 0.0012
hairshell.data.materials.append(bpy.data.materials.get("hairscalp") or bpy.data.materials.new("hairscalp"))
for p in hairshell.data.polygons: p.use_smooth = True
scn.collection.objects.link(hairshell)
on_head(hairshell)
bpy.data.materials["hairscalp"]  # created above

bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT)
