"""A dragon's body, without its wings (dragon_wing.glb, put on and flapped by the game): a
long torso, an S of a neck up to a horned head with an open jaw, a long tail ending in a
spade, four legs drawn up under it as it flies, spikes down its back. About 22 m nose to
tail, facing +X; its origin is the middle of the torso (a flyer: no ground under it). The
shoulders, where the wings go, are at (1.2, +-1.1, 1.0) in Blender's axes.
Roles: paint (scales), paint2 (belly), dark (horns, claws, spikes), paint3 (eyes)."""
import math

import kit

# the torso, and its paler belly a little below
kit.ball(1.0, (0, 0, 0), "paint", scale=(2.6, 1.25, 1.2), rings=8, sides=12)
kit.ball(1.0, (0.2, 0, -0.35), "paint2", scale=(2.3, 1.0, 0.95), rings=6, sides=10)

# the neck: up and forward in an S, thinner toward the head
neck = [(2.2, 0, 0.4), (3.6, 0, 1.4), (4.8, 0, 2.6), (6.0, 0, 3.2), (7.0, 0, 3.4)]
for k in range(len(neck) - 1):
    r = 0.85 - 0.12 * k
    kit.rod(neck[k], neck[k + 1], r, "paint", sides=10)
    kit.ball(r, neck[k + 1], "paint", rings=5, sides=10)

# the head: skull, snout, open jaw, horns, eyes
hx, hz = 7.6, 3.5
kit.ball(0.75, (hx, 0, hz), "paint", scale=(1.3, 0.9, 0.85), rings=6, sides=10)
kit.box((1.6, 0.7, 0.45), (hx + 1.3, 0, hz + 0.05), "paint", rot=(0, math.radians(-6), 0))        # snout
kit.box((1.5, 0.6, 0.25), (hx + 1.2, 0, hz - 0.55), "paint2", rot=(0, math.radians(18), 0))       # lower jaw, open
for sy in (-1, 1):
    kit.cyl(0.18, 1.4, (hx - 0.6, sy * 0.4, hz + 0.8), "dark", rot=(sy * math.radians(20), math.radians(-55), 0), radius2=0.02)
    kit.ball(0.13, (hx + 0.5, sy * 0.42, hz + 0.3), "paint3")
    for k in range(3):   # teeth
        kit.cyl(0.05, 0.2, (hx + 1.6 + k * 0.25, sy * 0.25, hz - 0.25), "dark", radius2=0.01)

# the tail: long, swinging a little, thinning to a spade
tail = []
for k in range(9):
    t = k / 8
    tail.append((-2.4 - t * 12.0, math.sin(t * math.pi * 1.2) * 1.1, -0.3 - t * 1.2))
for k in range(len(tail) - 1):
    r = 0.95 * (1 - k / 9) + 0.12
    kit.rod(tail[k], tail[k + 1], r, "paint", sides=8)
    kit.ball(r, tail[k + 1], "paint", rings=4, sides=8)
ex, ey, ez = tail[-1]
kit.poly([(ex, ey, ez), (ex - 0.6, ey + 0.9, ez), (ex - 2.2, ey, ez), (ex - 0.6, ey - 0.9, ez)], "dark", thick=0.08)

# spikes down the back and the tail
for k in range(10):
    x = 2.0 - k * 1.5
    z = 1.15 if x > -2.4 else -0.3 - (-2.4 - x) / 12.0 * 1.2 + 0.6
    kit.cyl(0.22, 0.7, (x, 0, z), "dark", radius2=0.02)

# legs drawn up under it, claws forward
for sx, sy in ((1.4, 0.9), (1.4, -0.9), (-1.5, 0.8), (-1.5, -0.8)):
    hip = (sx, sy, -0.6)
    knee = (sx - 0.9, sy * 1.1, -1.4)
    foot = (sx + 0.2, sy * 1.1, -1.9)
    kit.rod(hip, knee, 0.32, "paint", sides=8)
    kit.rod(knee, foot, 0.22, "paint", sides=8)
    for c in (-0.15, 0.0, 0.15):
        kit.cyl(0.06, 0.35, (foot[0] + 0.25, foot[1] + c, foot[2] - 0.05), "dark", rot=(0, math.radians(80), 0), radius2=0.01)
