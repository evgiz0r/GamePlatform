# Stage and render the whole performance (sequence.py's seq.blend).
#   python scene2.py -- seq.blend outdir [--from F] [--to F] [--res 854x480] [--samples 8] [--only 1,50]
import bpy, sys, os, math, random
from mathutils import Vector, Euler

a = sys.argv[sys.argv.index("--") + 1:]
IN, OUTD = a[0], a[1]
def opt(k, d):
    return a[a.index(k) + 1] if k in a else d
bpy.ops.wm.open_mainfile(filepath=IN)
scn = bpy.context.scene
F0, F1 = int(opt("--from", scn.frame_start)), int(opt("--to", scn.frame_end))
scn.render.engine = "BLENDER_EEVEE"
scn.eevee.taa_render_samples = int(opt("--samples", "8"))
w, h = opt("--res", "854x480").split("x")
scn.render.resolution_x, scn.render.resolution_y = int(w), int(h)
rig = bpy.data.objects["Rig"]
cam = scn.camera
cam.data.lens = 30
cam.data.clip_end = 200
B = {k[5:]: v for k, v in scn.items() if k.startswith("beat_")}
BOARD = Vector(scn["board"])
END = scn.frame_end

def mat(name, col, rough=0.6, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*col, 1)
    p.inputs["Roughness"].default_value = rough
    if emit:
        p.inputs["Emission Color"].default_value = (*col, 1)
        p.inputs["Emission Strength"].default_value = emit
    return m
def box(name, size, loc, m, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object; o.name = name; o.scale = size
    o.data.materials.append(m)
    if parent: o.parent = parent
    return o
def text(body, size, m, extrude=0.0, align="LEFT"):
    cu = bpy.data.curves.new("T", "FONT"); cu.body = body; cu.size = size; cu.extrude = extrude
    cu.align_x = align
    o = bpy.data.objects.new("T", cu); scn.collection.objects.link(o)
    o.data.materials.append(m)
    return o

def hips(f):
    scn.frame_set(f)
    return rig.matrix_world @ rig.pose.bones["Hips"].head
def head(f):
    scn.frame_set(f)
    return rig.matrix_world @ rig.pose.bones["Head"].tail

# ---- the room ---------------------------------------------------------------------------
box("Wall", (60, 0.2, 14), (2, 5.5, 7), mat("wall", (0.07, 0.075, 0.09), 0.9))
# the board, facing the camera side (-Y); he writes facing +Y
bc = Vector((BOARD.x + 0.25, BOARD.y, 1.5))
box("Board", (2.2, 0.03, 1.15), bc, mat("board", (0.92, 0.92, 0.9), 0.2))
box("Frame", (2.28, 0.02, 1.23), bc + Vector((0, 0.02, 0)), mat("frame", (0.55, 0.55, 0.58), 0.35))
for sx in (-0.85, 0.85):
    box("Leg", (0.04, 0.04, 0.95), Vector((bc.x + sx, bc.y + 0.05, 0.47)), mat("frame2", (0.55, 0.55, 0.58), 0.35))
INK = mat("ink", (0.06, 0.08, 0.3), 0.5)
LINES = ["e^(iπ) + 1 = 0", "a² + b² = c²", "∑ 1/2ⁿ = 1"]
board_txt = []
for i, s in enumerate(LINES):
    o = text("", 0.15, INK)
    o.location = Vector((bc.x - 0.95, bc.y - 0.02, bc.z + 0.3 - i * 0.28))
    o.rotation_euler = (math.radians(90), 0, 0)
    board_txt.append((o, s))
nchars = sum(len(s) for s in LINES)
W0, W1 = B["write"] + 20, B["turn"] - 6

# speech: a caption under him while he says it
CAP = mat("caption", (1, 1, 1), 0.5, emit=2.5)
cap = text("Now I will teach you math!", 0.03, CAP, align="CENTER")
cap.parent = cam
cap.location = Vector((0, -0.135, -0.5))
S0, S1 = B["say"] + 14, B["say"] + 96

# ---- falling maths -----------------------------------------------------------------------
GLYPHS = list("eπ∑√∞+−×÷=0123456789xy∫Δ%") + ["e", "π", "π", "e", "2", "7", "+", "="]
COLS = [(1, 0.35, 0.2), (0.25, 0.6, 1), (1, 0.85, 0.2), (0.4, 0.95, 0.5), (0.9, 0.35, 0.9)]
gm = [mat("g%d" % i, c, 0.35, emit=0.6) for i, c in enumerate(COLS)]
rnd = random.Random(3)
FALL0 = B["write"] + 10
falls = []
center = hips(B["write"] + 30)
for k in range(110):
    t0 = FALL0 + rnd.uniform(0, END - FALL0 - 20)
    ang = rnd.uniform(0, 2 * math.pi)
    r = rnd.uniform(0.7, 3.4)
    x = center.x + r * math.cos(ang); y = center.y - 0.3 + r * math.sin(ang) * 0.8
    if y > BOARD.y - 0.15:   # not through the board
        y = BOARD.y - 0.15 - rnd.uniform(0, 1.0)
    size = rnd.uniform(0.3, 0.6)
    o = text(rnd.choice(GLYPHS), size, rnd.choice(gm), extrude=size * 0.12, align="CENTER")
    o.data.offset_y = -size * 0.35
    # mostly upright and facing the camera, rolling in their own plane as they fall
    spin = Vector((rnd.uniform(-0.6, 0.6), rnd.uniform(-3.5, 3.5), rnd.uniform(-0.8, 0.8)))
    rot0 = Euler((math.radians(90 + rnd.uniform(-25, 25)), rnd.uniform(0, 6.3), math.radians(rnd.uniform(-40, 40))))
    falls.append({"o": o, "t0": t0, "x": x, "y": y, "z0": rnd.uniform(5, 7), "spin": spin, "rot0": rot0,
                  "flat": Euler((math.radians(90 * rnd.choice([1, -1]) + rnd.uniform(-10, 10)) * 0 + math.radians(rnd.choice([0, 180])), 0, rnd.uniform(0, 6.3))),
                  "size": size})
G = 9.8
def place_falls(f):
    for d in falls:
        o = d["o"]
        t = (f - d["t0"]) / 30.0
        if t < 0:
            o.hide_render = True; continue
        o.hide_render = False
        z = d["z0"] - 0.5 * G * t * t
        tl = math.sqrt(2 * d["z0"] / G)          # when it lands
        rest = d["size"] * 0.06
        if t < tl:
            o.location = Vector((d["x"], d["y"], z))
            e = d["rot0"]
            o.rotation_euler = Euler((e.x + d["spin"].x * t, e.y + d["spin"].y * t, e.z + d["spin"].z * t))
        else:
            # one bounce, then lying on the floor
            tb = t - tl
            v = 0.25 * G * tl
            hb = max(0.0, v * tb - 0.5 * G * tb * tb)
            o.location = Vector((d["x"], d["y"], rest + hb))
            k = min(1.0, tb / 0.35)
            e1 = d["rot0"]; e1 = Euler((e1.x + d["spin"].x * tl, e1.y + d["spin"].y * tl, e1.z + d["spin"].z * tl))
            fl = d["flat"]
            o.rotation_euler = Euler(tuple(e1[i] + (fl[i] - e1[i]) * k for i in range(3)))

# ---- the camera ----------------------------------------------------------------------------
P = {f: hips(f) for f in range(1, END + 1)}
def sm(f, k=10):
    s = Vector(); n = 0
    for g in range(f - k, f + k + 1):
        if g in P:
            s += P[g]; n += 1
    return s / n
def lerpv(a_, b_, t):
    t = max(0.0, min(1.0, t)); t = t * t * (3 - 2 * t)
    return a_.lerp(b_, t)
fly_top = None
def cam_at(f):
    c = sm(f)
    c.z = 1.0
    # beats: wave close and front; walk tracking from the front-side; say: front; write: wide
    # three-quarter from behind-left so the board and the falling maths both show; fly: tilt up
    shots = [
        (1, Vector((0.6, -3.0, 1.45)), Vector((0, 0, 1.15)), "abs"),
        (B["walk"] + 10, Vector((1.6, -3.9, 0.45)), Vector((0.6, 0, 0.1)), "rel"),
        (B["say"] + 6, Vector((-0.5, -2.8, 0.5)), Vector((0, 0, 0.35)), "rel"),
        (B["write"] + 10, Vector((-2.6, -4.6, 0.9)), Vector((0.5, 0.2, 0.25)), "rel"),
        (B["fly"], Vector((-1.2, -5.2, 0.4)), Vector((0, 0, 0.5)), "rel"),
    ]
    def eval_shot(s):
        _, off, look, mode = s
        if mode == "abs":
            return off.copy(), look.copy()
        return c + off, c + look
    cur = shots[0]
    nxt = None
    for i, s in enumerate(shots):
        if f >= s[0]:
            cur = s; nxt = shots[i + 1] if i + 1 < len(shots) else None
    loc, look = eval_shot(cur)
    if nxt is not None and f > nxt[0] - 24:
        l2, k2 = eval_shot(nxt)
        t = (f - (nxt[0] - 24)) / 24.0
        loc, look = lerpv(loc, l2, t), lerpv(look, k2, t)
    if f >= B["fly"]:
        # follow him up for a second, then let him go out of the top of the frame
        hz = min(P[f].z, P[min(END, B["fly"] + 70)].z)
        look = look + Vector((0, 0, max(0.0, hz - 1.0) * 0.8))
    return loc, look

# ---- lights ride with him (the studio's key, fill, rim) ---------------------------------------
LB = {n: bpy.data.objects[n].location.copy() for n in ("Key", "Fill", "Rim")}
def lights_at(f):
    c = sm(f, 20)
    for n, base in LB.items():
        L = bpy.data.objects[n]
        L.location = base + Vector((c.x, c.y, min(c.z - 1.0, 3.0)))

os.makedirs(OUTD, exist_ok=True)
only = opt("--only", "")
frames = [int(x) for x in only.split(",")] if only else range(F0, F1 + 1)
for f in frames:
    path = os.path.join(OUTD, "f%04d.png" % f)
    if os.path.exists(path) and not only:
        continue
    scn.frame_set(f)
    loc, look = cam_at(f)
    cam.location = loc
    cam.rotation_euler = (look - loc).to_track_quat("-Z", "Y").to_euler()
    lights_at(f)
    place_falls(f)
    n = int(max(0.0, min(1.0, (f - W0) / max(1, W1 - W0))) * nchars)
    for o, s in board_txt:
        o.data.body = s[:max(0, min(len(s), n))]
        n -= len(s)
    cap.hide_render = not (S0 <= f <= S1)
    scn.frame_set(f)
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
print("DONE")
