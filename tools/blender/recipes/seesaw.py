"""A playground see-saw: a plank 3.2 m long on a pivot, tipped a little, a handle and a seat
at each end, rubber stops under the ends. Along +X."""
import math

import kit

TIP = math.radians(9)
kit.box((0.5, 0.3, 0.5), (0, 0, 0.25), "paint2")                       # the pivot's block
kit.cyl(0.07, 0.36, (0, 0, 0.52), "metal", rot=(math.pi / 2, 0, 0))     # its axle
kit.box((3.2, 0.26, 0.06), (0, 0, 0.58), "paint", rot=(0, TIP, 0))      # the plank
for sx in (-1, 1):
    x = sx * 1.35
    z = 0.58 - math.sin(TIP) * x
    kit.box((0.32, 0.3, 0.06), (x, 0, z + 0.05), "rubber", rot=(0, TIP, 0))          # the seat
    kit.rod((x + sx * -0.28, -0.12, z + 0.05), (x + sx * -0.28, -0.12, z + 0.38), 0.02, "metal")
    kit.rod((x + sx * -0.28, 0.12, z + 0.05), (x + sx * -0.28, 0.12, z + 0.38), 0.02, "metal")
    kit.rod((x + sx * -0.28, -0.14, z + 0.38), (x + sx * -0.28, 0.14, z + 0.38), 0.022, "paint3")   # handle
    kit.cyl(0.12, 0.1, (sx * 1.45, 0, 0.05), "rubber")                                # the stop under it
