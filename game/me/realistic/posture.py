# workbench stills of chosen frames of seq.blend, from his front and his side, to judge the pose
#   python posture.py -- seq.blend out.png 30,120,200
import bpy, sys
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.open_mainfile(filepath=a[0])
scn = bpy.context.scene
scn.render.engine = "BLENDER_WORKBENCH"
sh = scn.display.shading; sh.light = "STUDIO"; sh.color_type = "MATERIAL"; sh.show_specular_highlight = False
for m in bpy.data.materials:
    if m.name in ("hair", "hairscalp"):
        m.diffuse_color = (0.09, 0.06, 0.04, 1)
    elif m.use_nodes and "Principled BSDF" in m.node_tree.nodes:
        bc = m.node_tree.nodes["Principled BSDF"].inputs["Base Color"]
        m.diffuse_color = bc.default_value[:] if not bc.is_linked else (0.72, 0.5, 0.4, 1)
scn.render.resolution_x, scn.render.resolution_y = 300, 450
cam = bpy.data.objects.new("C", bpy.data.cameras.new("C")); scn.collection.objects.link(cam); scn.camera = cam
cam.data.lens = 50
rig = bpy.data.objects["Rig"]
for f in [int(x) for x in a[2].split(",")]:
    scn.frame_set(f)
    hb = rig.pose.bones["Hips"]
    hp = rig.matrix_world @ hb.head
    L = (rig.matrix_world @ rig.pose.bones["LeftUpLeg"].head) - (rig.matrix_world @ rig.pose.bones["RightUpLeg"].head)
    L.z = 0; L.normalize()
    fwd = L.cross(Vector((0, 0, 1)))
    tgt = Vector((hp.x, hp.y, hp.z * 0.95))
    for i, d in enumerate((fwd, L)):
        loc = tgt + d * 5.0
        cam.location = loc
        cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = a[1].replace(".png", "_%04d_%d.png" % (f, i))
        bpy.ops.render.render(write_still=True)
