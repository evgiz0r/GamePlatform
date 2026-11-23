# Retarget a CMU BVH clip onto the built human's rig (same bone names), baked as an action.
#   python mocap.py -- in.blend out.blend clip.bvh start_frame end_frame [--step 4] [--name walk] [--inplace]
# The BVH runs at 120 fps; every --step'th frame becomes one frame of the action (4 -> 30 fps).
import bpy, sys, math, addon_utils
from mathutils import Matrix, Vector, Quaternion

a = sys.argv[sys.argv.index("--") + 1:]
IN, OUT, BVH, F0, F1 = a[0], a[1], a[2], int(a[3]), int(a[4])
STEP = int(a[a.index("--step") + 1]) if "--step" in a else 4
NAME = a[a.index("--name") + 1] if "--name" in a else "clip"
INPLACE = "--inplace" in a

bpy.ops.wm.open_mainfile(filepath=IN)
addon_utils.enable("io_anim_bvh", default_set=True)
scn = bpy.context.scene
tgt = bpy.data.objects["Rig"]
bpy.ops.import_anim.bvh(filepath=BVH, global_scale=0.056444, frame_start=1, use_fps_scale=False,
                        update_scene_fps=False, update_scene_duration=False, rotate_mode="NATIVE",
                        axis_forward="-Z", axis_up="Y")
src = [o for o in bpy.context.selected_objects if o.type == "ARMATURE" and o != tgt][0]

names = [b.name for b in tgt.data.bones if b.name in src.data.bones]
order = []
def walk(b):
    if b.name in names:
        order.append(b.name)
    for c in b.children:
        walk(c)
for b in tgt.data.bones:
    if b.parent is None:
        walk(b)

def wrest(arm, n):
    return (arm.matrix_world @ arm.data.bones[n].matrix_local)

# per-bone rest alignment: swing that turns the target bone's direction onto the source's
align = {}
for n in order:
    tr, sr = wrest(tgt, n), wrest(src, n)
    td = tr.to_3x3() @ Vector((0, 1, 0)); sd = sr.to_3x3() @ Vector((0, 1, 0))
    align[n] = td.rotation_difference(sd)

# scale for the hips' travel: leg length ratio
def leglen(arm):
    b = arm.data.bones
    return (b["LeftUpLeg"].head_local - b["LeftFoot"].head_local).length * arm.matrix_world.to_scale().x
ratio = leglen(tgt) / leglen(src)
hips_src_rest = wrest(src, "Hips").translation.copy()
hips_tgt_rest = wrest(tgt, "Hips").translation.copy()
print("ratio", ratio, "bones", len(order))

act = bpy.data.actions.new(NAME)
tgt.animation_data_create()
tgt.animation_data.action = act
tw_inv = tgt.matrix_world.inverted()
frames = list(range(F0, F1 + 1, STEP))
first_xy = None
for k, f in enumerate(frames):
    scn.frame_set(f)
    world = {}
    for n in order:
        sp = src.matrix_world @ src.pose.bones[n].matrix
        srest = wrest(src, n)
        rot = (sp.to_quaternion() @ srest.to_quaternion().inverted()) @ align[n] @ wrest(tgt, n).to_quaternion()
        world[n] = rot
    # root position
    hp = (src.matrix_world @ src.pose.bones["Hips"].matrix).translation
    move = (hp - hips_src_rest) * ratio
    move.z = hp.z * ratio - hips_tgt_rest.z       # CMU's floor is z=0: hips height scaled to his legs
    if first_xy is None:
        first_xy = Vector((move.x, move.y, 0))
    move -= first_xy
    if INPLACE:
        move.x = 0; move.y = 0
    # armature-space matrices, parents first, then local bases
    arm_m = {}
    for n in order:
        pb = tgt.pose.bones[n]
        b = tgt.data.bones[n]
        R = (tw_inv.to_quaternion() @ world[n]).to_matrix().to_4x4()
        if b.parent is None or b.parent.name not in arm_m:
            t = b.head_local + tw_inv.to_3x3() @ move if b.parent is None else (arm_m.get(b.parent.name, b.parent.matrix_local) @ (b.parent.matrix_local.inverted() @ b.matrix_local)).translation
        else:
            pm = arm_m[b.parent.name]
            t = (pm @ (b.parent.matrix_local.inverted() @ b.matrix_local)).translation
        M = Matrix.Translation(t) @ R
        arm_m[n] = M
        if b.parent is None:
            basis = b.matrix_local.inverted() @ M
        else:
            pm = arm_m[b.parent.name]
            rel = b.parent.matrix_local.inverted() @ b.matrix_local
            basis = rel.inverted() @ pm.inverted() @ M
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = basis.to_quaternion()
        pb.keyframe_insert("rotation_quaternion", frame=k + 1)
        if b.parent is None:
            pb.location = basis.translation
            pb.keyframe_insert("location", frame=k + 1)

bpy.data.objects.remove(src)
# turn the whole figure: an in-place clip to face the camera (-Y), a walk to travel along +X
import math as _m
fw = Vector(); first = last = None
for k in range(1, len(frames) + 1, 3):
    scn.frame_set(k)
    L = (tgt.matrix_world @ tgt.pose.bones["LeftUpLeg"].head) - (tgt.matrix_world @ tgt.pose.bones["RightUpLeg"].head)
    L.z = 0
    fw += L.cross(Vector((0, 0, 1))).normalized()
    h = tgt.matrix_world @ tgt.pose.bones["Hips"].head
    first = first or h.copy(); last = h.copy()
want = Vector((0, -1, 0))
d = fw
if not INPLACE and (last - first).length > 0.5:
    d = last - first; want = Vector((1, 0, 0))
d.z = 0
ang = _m.atan2(want.y, want.x) - _m.atan2(d.y, d.x)
tgt.rotation_euler.z += ang
bpy.context.view_layer.update()
print("turned", round(_m.degrees(ang)))
scn.frame_start, scn.frame_end = 1, len(frames)
scn.render.fps = round(120 / STEP)
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("BAKED", NAME, len(frames), "frames at", scn.render.fps, "fps")
