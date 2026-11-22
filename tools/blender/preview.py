"""A quick look at a made model: imports a .glb into an empty scene and renders it from
three-quarters above with the Workbench engine (fast, flat colours) to a .png.

    blender -b --factory-startup --python tools/blender/preview.py -- <model.glb> <out.png>
    (tools/blender_model.sh --preview <model.glb> [out.png] does this)
"""
import math
import os
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(src))
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in objs:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
        hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
mid = (lo + hi) / 2
size = max((hi - lo).length, 0.5)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.collection.objects.link(cam)
cam.location = mid + Vector((size * 0.9, -size * 1.1, size * 0.75))
cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
bpy.context.scene.camera = cam
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_shadows = True
sc.render.resolution_x = 640
sc.render.resolution_y = 480
sc.render.filepath = os.path.abspath(out)
bpy.ops.render.render(write_still=True)
print(f"PREVIEW {out}: {size:.2f} m across, {hi.z - lo.z:.2f} m high")
