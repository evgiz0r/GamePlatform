"""A playground climbing dome: a half-globe of bars, 1.9 m high, 3.6 m across -- rings at
four heights and ribs from the ground to the top, every bar a round rod."""
import math

import kit

R = 1.9
RIBS = 10
LEVELS = 4
rings = []
for li in range(LEVELS + 1):
    a = (math.pi / 2) * li / LEVELS          # 0 at the ground, up to the top
    r = R * math.cos(a)
    z = R * math.sin(a)
    rings.append([(r * math.cos(2 * math.pi * k / RIBS), r * math.sin(2 * math.pi * k / RIBS), z) for k in range(RIBS)])
for li in range(1, LEVELS):                   # the rings (not the ground's, not the point at the top)
    pts = rings[li]
    for k in range(RIBS):
        kit.rod(pts[k], pts[(k + 1) % RIBS], 0.03, "paint" if li % 2 else "paint3", sides=5)
for k in range(RIBS):                         # the ribs, ground to top
    for li in range(LEVELS):
        kit.rod(rings[li][k], rings[li + 1][k], 0.035, "paint2", sides=5)
kit.ball(0.09, (0, 0, R), "paint")            # the cap at the top
