"""A picnic table: a plank top and a bench along each side on A-shaped legs, 1.8 m long
(along X), the top at 0.74 m, 1.5 m across with its benches."""
import math

import kit

L = 1.8
for k in range(4):                                         # the top's planks
    kit.box((L, 0.17, 0.04), (0, -0.27 + k * 0.18, 0.74), "wood")
for sy in (-1, 1):                                         # the benches
    for k in range(2):
        kit.box((L, 0.13, 0.035), (0, sy * (0.6 + k * 0.14 - 0.07), 0.44), "wood")
for sx in (-1, 1):                                         # the legs: an A each end, and the bearers
    x = sx * (L / 2 - 0.2)
    for sy in (-1, 1):
        kit.box((0.07, 0.07, 0.78), (x, sy * 0.33, 0.35), "wood", rot=(sy * math.radians(27), 0, 0))
    kit.box((0.07, 1.48, 0.07), (x, 0, 0.4), "wood")       # under the benches
    kit.box((0.07, 0.72, 0.06), (x, 0, 0.7), "wood")       # under the top
