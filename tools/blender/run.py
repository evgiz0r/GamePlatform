"""Run inside Blender by tools/blender_model.sh: empties the scene, runs a recipe (which
builds its model with kit.py's helpers), and exports everything as one .glb.

    blender -b --factory-startup --python tools/blender/run.py -- <recipe.py> <out.glb>
"""
import os
import runpy
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
recipe, out = args[0], args[1]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402  (tools/blender/kit.py, beside this file)

kit.clear()
print(f"RECIPE {recipe}")
runpy.run_path(recipe, run_name="__main__")
kit.finish()
bpy.ops.export_scene.gltf(filepath=os.path.abspath(out), export_format="GLB",
                          export_apply=True, export_yup=True, use_selection=False)
n = sum(1 for o in bpy.data.objects if o.type == "MESH")
tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
print(f"MADE {out}: {n} meshes, {tris} faces")
