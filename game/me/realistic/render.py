# Render frames of a baked clip.  python render.py -- in.blend outdir frames(1,20,40|all) [--engine eevee|cycles]
#   [--res 640x360] [--samples 24] [--cam side|front|three] [--dist 3.2] [--follow]
import bpy, sys, os
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
IN, OUTD, FR = a[0], a[1], a[2]
def opt(k, d):
    return a[a.index(k) + 1] if k in a else d
bpy.ops.wm.open_mainfile(filepath=IN)
scn = bpy.context.scene
eng = opt("--engine", "cycles")
if eng == "workbench":
    scn.render.engine = "BLENDER_WORKBENCH"
elif eng == "eevee":
    scn.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE_NEXT"
    scn.eevee.taa_render_samples = int(opt("--samples", "32"))
else:
    scn.render.engine = "CYCLES"
    scn.cycles.samples = int(opt("--samples", "24"))
    scn.cycles.use_denoising = True
w, h = opt("--res", "640x360").split("x")
scn.render.resolution_x, scn.render.resolution_y = int(w), int(h)
rig = bpy.data.objects["Rig"]
cam = scn.camera
view = opt("--cam", "three")
dist = float(opt("--dist", "3.4"))
dirs = {"side": Vector((1, 0, 0)), "front": Vector((0, -1, 0)), "three": Vector((0.7, -0.7, 0)).normalized()}
frames = range(scn.frame_start, scn.frame_end + 1) if FR == "all" else [int(x) for x in FR.split(",")]
os.makedirs(OUTD, exist_ok=True)
for f in frames:
    scn.frame_set(f)
    hips = rig.matrix_world @ rig.pose.bones["Hips"].head
    tgt = Vector((hips.x, hips.y, 1.0))
    if "--static" in a:
        tgt = Vector((2.2, 0, 1.1)); dirs[view] = Vector((0, -1, 0))
    cam.location = tgt + dirs[view] * dist + Vector((0, 0, 0.35))
    cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.render.filepath = os.path.join(OUTD, "f%04d.png" % f)
    bpy.ops.render.render(write_still=True)
print("DONE")
