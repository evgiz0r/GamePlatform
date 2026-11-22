"""A dragon's left wing (the game mirrors it for the right, and flaps both about the root):
a bony arm out to the wrist, three long fingers spreading back from it, the leathery
membrane stretched between them and back to the flank. The root is the origin (the
shoulder), the wing reaching out along +Y in Blender's axes, its leading edge toward +X.
About 12 m from root to tip. Roles: dark (bones), paint3 (membrane)."""
import kit

root = (0.0, 0.0, 0.0)
wrist = (1.2, 5.5, 0.6)
tips = [(0.0, 12.0, 0.8), (-2.8, 10.2, 0.4), (-4.8, 6.8, 0.2)]
flank = (-3.8, 0.4, 0.0)
kit.rod(root, (0.9, 2.6, 0.4), 0.32, "dark", sides=8)
kit.rod((0.9, 2.6, 0.4), wrist, 0.24, "dark", sides=8)
kit.ball(0.3, wrist, "dark", rings=4, sides=8)
for tip in tips:
    kit.rod(wrist, tip, 0.12, "dark", sides=6)
kit.cyl(0.12, 0.8, (wrist[0] + 0.3, wrist[1], wrist[2] + 0.3), "dark", radius2=0.01)   # the thumb's claw
# the membrane: a panel between each pair of bones, its free edge scalloped in toward the
# wrist halfway between the tips (as a bat's or a dragon's is, not a flat sheet)
def notch(a, b, k=0.3):
    m = [(a[i] + b[i]) / 2 for i in range(3)]
    return tuple(m[i] + (wrist[i] - m[i]) * k for i in range(3))
kit.poly([wrist, tips[0], notch(tips[0], tips[1]), tips[1]], "paint3", thick=0.06)
kit.poly([wrist, tips[1], notch(tips[1], tips[2]), tips[2]], "paint3", thick=0.06)
kit.poly([root, wrist, tips[2], notch(tips[2], flank, 0.25), flank], "paint3", thick=0.06)
