# One continuous performance from several CMU clips plus a procedural ending, baked on his rig.
#   python sequence.py -- in.blend out.blend
# The story (his words): waves at the start, walks to the board, says "now I will teach you
# math", writes on the board while maths falls round him, then raises an arm and flies away.
# Writes the frame where each beat starts into the scene's custom props ("beat_*").
import bpy, sys, math, os, addon_utils
from mathutils import Matrix, Vector, Quaternion

a = sys.argv[sys.argv.index("--") + 1:]
IN, OUT = a[0], a[1]
CMU = os.environ.get("CMU_DATA", "work/cmu/data")
bpy.ops.wm.open_mainfile(filepath=IN)
addon_utils.enable("io_anim_bvh", default_set=True)
scn = bpy.context.scene
tgt = bpy.data.objects["Rig"]
TB = tgt.data.bones
# bones whose rest direction differs a lot between his A-pose and the BVH's T-pose but which
# barely move: copy only their motion, not the BVH's rest direction (that raised his shoulders)
NO_ALIGN = {"LeftShoulder", "RightShoulder", "LHipJoint", "RHipJoint", "Neck", "Neck1", "LowerBack"}
DAMP = {"LeftShoulder": 0.5, "RightShoulder": 0.5}

order = []
def walk_tree(b):
    order.append(b.name)
    for c in b.children:
        walk_tree(c)
for b in TB:
    if b.parent is None:
        walk_tree(b)

def tgt_rest_q(n):
    return (tgt.matrix_world @ TB[n].matrix_local).to_quaternion()
def leglen(arm):
    b = arm.data.bones
    return (b["LeftUpLeg"].head_local - b["LeftFoot"].head_local).length * arm.matrix_world.to_scale().x

def sample(bvh, f0, f1, step=4):
    """-> list of poses {bone: world quat}, hips world pos (z absolute, xy raw)"""
    for o in list(bpy.data.objects):
        o.select_set(False)
    bpy.ops.import_anim.bvh(filepath=bvh, global_scale=0.056444, frame_start=1, use_fps_scale=False,
                            update_scene_fps=False, update_scene_duration=False, rotate_mode="NATIVE",
                            axis_forward="-Z", axis_up="Y")
    src = [o for o in bpy.context.selected_objects if o.type == "ARMATURE"][0]
    SB = src.data.bones
    names = [n for n in order if n in SB]
    srest = {n: (src.matrix_world @ SB[n].matrix_local).to_quaternion() for n in names}
    align = {}
    for n in names:
        if n in NO_ALIGN:
            align[n] = Quaternion()
        else:
            td = tgt_rest_q(n) @ Vector((0, 1, 0)); sd = srest[n] @ Vector((0, 1, 0))
            align[n] = td.rotation_difference(sd)
    ratio = leglen(tgt) / leglen(src)
    out = []
    for f in range(f0, f1 + 1, step):
        scn.frame_set(f)
        q = {}
        for n in names:
            sp = (src.matrix_world @ src.pose.bones[n].matrix).to_quaternion()
            d = sp @ srest[n].inverted()
            if n in DAMP:
                d = Quaternion().slerp(d, DAMP[n])
            q[n] = d @ align[n] @ tgt_rest_q(n)
        hp = (src.matrix_world @ src.pose.bones["Hips"].matrix).translation * ratio
        out.append({"q": q, "p": hp.copy()})
    bpy.data.objects.remove(src)
    return out

def facing(pose):
    q = pose["q"]
    # his left hip minus right hip, from the hips' world rotation applied to his rest offsets
    L = (q["Hips"] @ (TB["LeftUpLeg"].head_local - TB["Hips"].head_local)) - (q["Hips"] @ (TB["RightUpLeg"].head_local - TB["Hips"].head_local))
    L.z = 0
    return L.cross(Vector((0, 0, 1))).normalized()

def yaw_of(v):
    return math.atan2(v.y, v.x)

def place(seg, want_dir, anchor, use_travel=False, pin=None):
    """turn the segment so it faces (or travels) want_dir and starts with its hips over anchor"""
    if use_travel:
        d = seg[-1]["p"] - seg[0]["p"]; d.z = 0
    else:
        d = Vector()
        for p in seg[: min(15, len(seg))]:
            d += facing(p)
    th = yaw_of(want_dir) - yaw_of(d)
    R = Quaternion((0, 0, 1), th)
    p0 = seg[0]["p"].copy()
    for p in seg:
        p["q"] = {n: R @ v for n, v in p["q"].items()}
        rel = p["p"] - p0
        z = p["p"].z
        rel = R @ Vector((rel.x, rel.y, 0))
        if pin is not None and rel.length > pin:   # stands roughly where he is: sway, no wandering
            rel = rel.normalized() * pin
        p["p"] = Vector((anchor.x + rel.x, anchor.y + rel.y, z))
    return seg

def blend(a, b, w):
    q = {n: a["q"][n].slerp(b["q"][n], w) for n in a["q"]}
    return {"q": q, "p": a["p"].lerp(b["p"], w)}

def join(track, seg, n=12):
    """hold the track's last pose and ease into the segment over n frames"""
    last = track[-1]
    for i in range(1, n + 1):
        w = i / n
        w = w * w * (3 - 2 * w)
        track.append(blend(last, seg[min(i - 1, len(seg) - 1)], w))
    track.extend(seg[n:])

D = CMU
wave = sample(f"{D}/141/141_16.bvh", 5, 200)
walkc = sample(f"{D}/016/16_15.bvh", 20, 440)
talk = sample(f"{D}/018/18_08.bvh", 120, 600)
write = sample(f"{D}/079/79_31.bvh", 110, 579)

CAM_DIR = Vector((0, -1, 0))            # the camera looks from -Y
track, beats = [], {}
beats["wave"] = 1
track.extend(place(wave, CAM_DIR, Vector((0, 0, 0))))
end = track[-1]["p"]
beats["walk"] = len(track) + 1
join(track, place(walkc, Vector((1, 0, 0)), Vector((end.x, end.y, 0)), use_travel=True), 14)
end = track[-1]["p"]
beats["say"] = len(track) + 1
join(track, place(talk, Vector((0.25, -1, 0)).normalized(), Vector((end.x, end.y, 0)), pin=0.12), 16)
end = track[-1]["p"]
beats["write"] = len(track) + 1
wseg = place(write, Vector((0, 1, 0)), Vector((end.x, end.y, 0)), pin=0.35)
join(track, wseg, 18)
# the board stands in front of where he writes: his mean position plus a forearm and a half
mid = sum((p["p"] for p in wseg), Vector()) / len(wseg)
BOARD = Vector((mid.x, mid.y + 0.62, 0))
end = track[-1]["p"]

# ---- the ending: turn to the camera, right arm straight up, and away -----------------------
def point(pose, bone, direction, w):
    rest = tgt_rest_q(bone)
    d0 = rest @ Vector((0, 1, 0))
    want = d0.rotation_difference(direction.normalized()) @ rest
    pose["q"][bone] = pose["q"][bone].slerp(want, w)

stand = blend(talk[0], talk[0], 0)        # a calm standing pose to turn into
stand = place([stand], CAM_DIR, Vector((end.x, end.y, 0)))[0]
beats["turn"] = len(track) + 1
join(track, [stand] * 18, 18)
beats["fly"] = len(track) + 1
base = track[-1]
FLY = 110
for i in range(FLY):
    t = i / 30.0
    p = {"q": dict(base["q"]), "p": base["p"].copy()}
    w = min(1.0, i / 12.0)
    w = w * w * (3 - 2 * w)
    up = Vector((0.05, -0.15, 1))
    for b in ("RightArm", "RightForeArm", "RightHand", "RightFingerBase", "RightHandFinger1"):
        if b in p["q"]:
            point(p, b, up, w)
    for b in ("LeftArm", "LeftForeArm", "LeftHand"):
        point(p, b, Vector((0.18, 0.05, -1)), w)
    for b in ("LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"):
        point(p, b, Vector((0, 0.12, -1)), w * 0.8)
    # a short dip, then up, faster and faster
    dip = -0.06 * math.sin(min(1.0, t / 0.35) * math.pi) if t < 0.35 else 0.0
    rise = 0.0 if t < 0.3 else 0.5 * 5.0 * (t - 0.3) ** 2
    p["p"].z += dip + rise
    track.append(p)

# ---- write it into an action -----------------------------------------------------------
act = bpy.data.actions.new("performance")
tgt.animation_data_create()
tgt.animation_data.action = act
tw = tgt.matrix_world
tw_inv = tw.inverted()
for k, pose in enumerate(track):
    arm_m = {}
    for n in order:
        b = TB[n]
        q = pose["q"].get(n)
        if q is None:   # (a bone the BVH lacks: keep it at rest relative to its parent)
            pm = arm_m[b.parent.name]
            arm_m[n] = pm @ (b.parent.matrix_local.inverted() @ b.matrix_local)
            continue
        R = (tw_inv.to_quaternion() @ q).to_matrix().to_4x4()
        if b.parent is None:
            t = tw_inv @ pose["p"]
        else:
            t = (arm_m[b.parent.name] @ (b.parent.matrix_local.inverted() @ b.matrix_local)).translation
        M = Matrix.Translation(t) @ R
        arm_m[n] = M
        if b.parent is None:
            basis = b.matrix_local.inverted() @ M
        else:
            basis = (b.parent.matrix_local.inverted() @ b.matrix_local).inverted() @ arm_m[b.parent.name].inverted() @ M
        pb = tgt.pose.bones[n]
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = basis.to_quaternion()
        pb.keyframe_insert("rotation_quaternion", frame=k + 1)
        if b.parent is None:
            pb.location = basis.translation
            pb.keyframe_insert("location", frame=k + 1)
scn.frame_start, scn.frame_end = 1, len(track)
scn.render.fps = 30
for k, v in beats.items():
    scn["beat_" + k] = v
scn["board"] = BOARD
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SEQUENCE", len(track), "frames", beats, "board", tuple(round(x, 2) for x in BOARD))
