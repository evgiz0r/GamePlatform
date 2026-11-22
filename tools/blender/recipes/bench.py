"""A park bench: wooden slats on two cast-iron frames, a slatted back leaning a little,
arm rests. 1.7 m long (along X), the seat at 0.44 m, the back to 0.82 m. You sit facing -Y in
Blender, which is +Z in Godot (the game's benches face their local +Z, the back at -Z)."""
import math

import kit

L = 1.7
for k in range(4):                                     # the seat's slats
    kit.box((L, 0.095, 0.035), (0, -0.17 + k * 0.11, 0.44), "wood")
lean = math.radians(12)
for k in range(3):                                     # the back's slats, leaning back
    z = 0.58 + k * 0.11
    y = 0.2 + (z - 0.5) * math.tan(lean)
    kit.box((L, 0.03, 0.08), (0, y, z), "wood", rot=(lean, 0, 0))
for sx in (-1, 1):                                     # the iron frames at each end
    x = sx * (L / 2 - 0.12)
    kit.box((0.05, 0.06, 0.44), (x, -0.18, 0.22), "dark")                  # front leg
    kit.box((0.05, 0.06, 0.8), (x, 0.22, 0.4), "dark", rot=(lean * 0.5, 0, 0))   # back leg up into the back
    kit.box((0.05, 0.46, 0.05), (x, 0.02, 0.41), "dark")                  # under the seat
    kit.box((0.06, 0.4, 0.04), (x, 0.02, 0.64), "dark")                   # the arm rest
    kit.box((0.04, 0.04, 0.2), (x, -0.16, 0.54), "dark")                  # its post
