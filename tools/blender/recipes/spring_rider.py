"""A playground spring rider: a stout coil on a base plate and a rounded animal on top (a
plump horse, more or less), handles at its neck, foot pegs. About 0.9 m long, 0.9 m high.
+X is the way it faces."""
import math

import kit

kit.cyl(0.25, 0.04, (0, 0, 0.02), "dark", sides=12)                        # base plate
# the coil: rings stacked up (round bars), as a spring reads from a few metres
for k in range(5):
    z = 0.08 + k * 0.07
    for i in range(8):
        a0 = 2 * math.pi * i / 8
        a1 = 2 * math.pi * (i + 1) / 8
        r = 0.12
        kit.rod((r * math.cos(a0), r * math.sin(a0), z + 0.0087 * i), (r * math.cos(a1), r * math.sin(a1), z + 0.0087 * (i + 1)), 0.018, "metal", sides=4)
# the body, the neck and head, ears, a tail
kit.ball(0.3, (0, 0, 0.6), "paint2", scale=(1.25, 0.6, 0.55), rings=5, sides=8)
kit.ball(0.14, (0.33, 0, 0.82), "paint2", scale=(0.9, 0.75, 1.3))         # neck
kit.ball(0.13, (0.45, 0, 0.95), "paint2", scale=(1.4, 0.8, 0.8))          # head
for sy in (-1, 1):
    kit.cyl(0.03, 0.09, (0.4, sy * 0.06, 1.06), "paint2", sides=5, radius2=0.005)   # ears
    kit.ball(0.025, (0.55, sy * 0.07, 0.98), "dark")                                 # eyes
kit.ball(0.06, (-0.38, 0, 0.66), "paint3", scale=(1.8, 0.6, 0.8))                   # tail
# handles through the neck and foot pegs
kit.rod((0.3, -0.16, 0.86), (0.3, 0.16, 0.86), 0.022, "paint")
kit.rod((0.05, -0.22, 0.42), (0.05, 0.22, 0.42), 0.022, "paint")
# a seat
kit.ball(0.12, (-0.08, 0, 0.78), "paint", scale=(1.3, 1.1, 0.35))
