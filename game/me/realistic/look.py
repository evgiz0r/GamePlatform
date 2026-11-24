# Materials and a studio for me.blend; also renders a test still when --still is given.
#   python look.py -- in.blend out.blend [--still out.png] [--samples N] [--res WxH]
import bpy, sys, math, os
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
IN, OUT = args[0], args[1]
STILL = args[args.index("--still") + 1] if "--still" in args else None
SAMPLES = int(args[args.index("--samples") + 1]) if "--samples" in args else 48
RES = args[args.index("--res") + 1] if "--res" in args else "960x540"
MH = os.environ.get("MH_DATA", "work/mh/makehuman/data")
bpy.ops.wm.open_mainfile(filepath=IN)
scn = bpy.context.scene

def nodes(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    return nt, out

def principled(name, color, rough=0.5, sss=0.0, sheen=0.0, bump=0.0, bump_scale=200.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt, out = nodes(mat)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    if sss > 0:
        p.inputs["Subsurface Weight"].default_value = sss
        p.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
        p.inputs["Subsurface Scale"].default_value = 0.012
    if sheen > 0:
        p.inputs["Sheen Weight"].default_value = sheen
    nt.links.new(p.outputs[0], out.inputs[0])
    if bump > 0:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = bump_scale
        tex.inputs["Detail"].default_value = 8
        b = nt.nodes.new("ShaderNodeBump")
        b.inputs["Strength"].default_value = bump
        b.inputs["Distance"].default_value = 0.002
        nt.links.new(tex.outputs["Fac"], b.inputs["Height"])
        nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
    return mat, nt, p

# skin: warm light skin with subsurface; a stubble shadow on the jaw, chin and upper lip
skin, nt, p = principled("skin", (0.66, 0.40, 0.28), rough=0.48, sss=0.2, bump=0.04, bump_scale=900.0)
attr = nt.nodes.new("ShaderNodeAttribute"); attr.attribute_name = "stubble"
mul2 = attr  # (baked per vertex at rest in build_me.py)
dots = nt.nodes.new("ShaderNodeTexNoise"); dots.inputs["Scale"].default_value = 2500.0
dm = nt.nodes.new("ShaderNodeMath"); dm.operation = "MULTIPLY"
nt.links.new(attr.outputs["Fac"], dm.inputs[0]); nt.links.new(dots.outputs["Fac"], dm.inputs[1])
mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
mix.inputs[6].default_value = (0.66, 0.40, 0.28, 1)
mix.inputs[7].default_value = (0.36, 0.26, 0.21, 1)
fac = nt.nodes.new("ShaderNodeMath"); fac.operation = "MULTIPLY"; fac.inputs[1].default_value = 0.75
nt.links.new(dm.outputs[0], fac.inputs[0])
nt.links.new(fac.outputs[0], mix.inputs[0])
nt.links.new(mix.outputs[2], p.inputs["Base Color"])

# eyes: procedural -- white, a brown iris and a black pupil round the eye's forward axis (-Y),
# under a glossy coat. Coordinates are the eye object's own (origin at the eyeball's centre).
eye = bpy.data.materials.get("eye") or bpy.data.materials.new("eye")
nt, out = nodes(eye)
p = nt.nodes.new("ShaderNodeBsdfPrincipled")
p.inputs["Roughness"].default_value = 0.03
p.inputs["Coat Weight"].default_value = 1.0
tc = nt.nodes.new("ShaderNodeTexCoord")
sx = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Object"], sx.inputs[0])
cx = nt.nodes.new("ShaderNodeCombineXYZ"); nt.links.new(sx.outputs["X"], cx.inputs["X"]); nt.links.new(sx.outputs["Z"], cx.inputs["Z"])
ln = nt.nodes.new("ShaderNodeVectorMath"); ln.operation = "LENGTH"; nt.links.new(cx.outputs[0], ln.inputs[0])
front = nt.nodes.new("ShaderNodeMath"); front.operation = "LESS_THAN"; front.inputs[1].default_value = 0.0
nt.links.new(sx.outputs["Y"], front.inputs[0])
cr = nt.nodes.new("ShaderNodeValToRGB")
cr.color_ramp.elements[0].position = 0.0; cr.color_ramp.elements[0].color = (0.005, 0.004, 0.004, 1)
cr.color_ramp.elements[1].position = 1.0; cr.color_ramp.elements[1].color = (0.92, 0.9, 0.88, 1)
e = cr.color_ramp.elements.new(0.22); e.color = (0.005, 0.004, 0.004, 1)
e = cr.color_ramp.elements.new(0.26); e.color = (0.16, 0.08, 0.035, 1)
e = cr.color_ramp.elements.new(0.50); e.color = (0.10, 0.05, 0.02, 1)
e = cr.color_ramp.elements.new(0.55); e.color = (0.03, 0.02, 0.015, 1)
e = cr.color_ramp.elements.new(0.60); e.color = (0.92, 0.9, 0.88, 1)
sc = nt.nodes.new("ShaderNodeMath"); sc.operation = "DIVIDE"; sc.inputs[1].default_value = 0.0105
nt.links.new(ln.outputs["Value"], sc.inputs[0])
# behind the front half: all white
mx = nt.nodes.new("ShaderNodeMath"); mx.operation = "MAXIMUM"
inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
nt.links.new(front.outputs[0], inv.inputs[1])
nt.links.new(sc.outputs[0], mx.inputs[0]); nt.links.new(inv.outputs[0], mx.inputs[1])
nt.links.new(mx.outputs[0], cr.inputs[0])
nt.links.new(cr.outputs[0], p.inputs["Base Color"])
nt.links.new(p.outputs[0], out.inputs[0])
principled("lash", (0.05, 0.035, 0.03), rough=0.6)
principled("teeth", (0.85, 0.82, 0.75), rough=0.3)
principled("mouth", (0.35, 0.08, 0.08), rough=0.4)
# clothes: the brick-red V-neck and dark trousers from the photos
principled("shirt", (0.22, 0.03, 0.02), rough=0.85, sheen=0.4, bump=0.3, bump_scale=1500.0)
principled("trousers", (0.018, 0.018, 0.02), rough=0.8, sheen=0.25, bump=0.2, bump_scale=1200.0)
principled("shoes", (0.03, 0.03, 0.035), rough=0.55)
principled("hairscalp", (0.035, 0.022, 0.015), rough=0.75)
hair = bpy.data.materials.get("hair") or bpy.data.materials.new("hair")
nt, out = nodes(hair)
h = nt.nodes.new("ShaderNodeBsdfHairPrincipled")
h.parametrization = "MELANIN"
h.inputs["Melanin"].default_value = 0.95
h.inputs["Melanin Redness"].default_value = 0.35
h.inputs["Roughness"].default_value = 0.35
nt.links.new(h.outputs[0], out.inputs[0])

# ---- studio --------------------------------------------------------------------------------
if "Floor" not in bpy.data.objects:
    bpy.ops.mesh.primitive_plane_add(size=40)
    fl = bpy.context.active_object; fl.name = "Floor"
    fm, nt, p = principled("floor", (0.18, 0.18, 0.2), rough=0.6)
    fl.data.materials.append(fm)
    def area(name, loc, energy, size, color=(1, 1, 1)):
        d = bpy.data.lights.new(name, "AREA"); d.energy = energy; d.size = size; d.color = color
        o = bpy.data.objects.new(name, d); scn.collection.objects.link(o)
        o.location = loc
        c = o.constraints.new("TRACK_TO"); c.target = bpy.data.objects["Rig"]; c.track_axis = "TRACK_NEGATIVE_Z"
        return o
    area("Key", (-1.6, -2.2, 2.4), 110, 1.6, (1.0, 0.95, 0.9))
    area("Fill", (2.2, -1.6, 1.5), 35, 2.5, (0.85, 0.9, 1.0))
    area("Rim", (0.8, 2.2, 2.6), 90, 1.0, (1.0, 0.9, 0.85))
    w = scn.world or bpy.data.worlds.new("World"); scn.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.065, 1)
    cd = bpy.data.cameras.new("Cam"); cd.lens = 50
    cam = bpy.data.objects.new("Cam", cd); scn.collection.objects.link(cam); scn.camera = cam

scn.render.engine = "CYCLES"
scn.cycles.device = "CPU"
scn.cycles.samples = SAMPLES
scn.cycles.use_denoising = True
scn.render.film_transparent = False
w_, h_ = RES.split("x")
scn.render.resolution_x, scn.render.resolution_y = int(w_), int(h_)
scn.render.resolution_percentage = 100
scn.view_settings.view_transform = "AgX"
scn.view_settings.look = "AgX - Medium High Contrast"

bpy.ops.wm.save_as_mainfile(filepath=OUT)
if STILL:
    cam = scn.camera
    tgt = Vector((0, 0, 1.0)) if "--face" not in args else Vector((0, 0, 1.63))
    cam.location = Vector((2.6, -2.6, 1.3)) if "--face" not in args else Vector((0.25, -0.75, 1.70))
    d = tgt - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scn.render.filepath = STILL
    bpy.ops.render.render(write_still=True)
    print("STILL", STILL)
