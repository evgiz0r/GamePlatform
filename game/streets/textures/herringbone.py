"""Draw the streets game's Israeli pavement: 20 x 10 cm concrete pavers laid in herringbone,
a random mix of grey, charcoal, red-brown and mauve as on most of Givatayim's pavements,
with sanded joints, bevelled edges, the aggregate's flecks and the odd dark stain. One tile
covers 2 m and repeats seamlessly. Writes herringbone_pavers_diff.jpg (colour) and
herringbone_pavers_nor.jpg (OpenGL normal map, green up) next to this file, and prints the
colour's mean (stored sRGB, 0-1) for TEX_MEAN in streets.gd. Drawn, not photographed: no
licence to credit. Needs numpy and Pillow.

    python3 game/streets/textures/herringbone.py
"""
import os
import numpy as np
from PIL import Image

PX = 1024                 # pixels a tile
CELLS = 20                # a tile is 20 brick-widths: 2 m of 10 cm
CELL = PX / CELLS         # pixels a brick-width
rng = np.random.default_rng(11)

# brick colours (stored sRGB) and how often each is laid
MIX = [((0.60, 0.595, 0.59), 26), ((0.53, 0.525, 0.52), 34), ((0.45, 0.445, 0.45), 18),
       ((0.53, 0.475, 0.46), 12), ((0.57, 0.545, 0.535), 10)]


def lattice(tx, tz):
    """herringbone of 2x1 bricks: a horizontal brick at T + [0,2]x[0,1] and a vertical one at
    T + [2,3]x[-1,1], for every T = a(1,1) + b(2,-2)"""
    return ((tx + tz) % 2 == 0) & ((tx - tz) % 4 == 0)


def periodic_noise(n, period):
    """smooth value noise on a PX tile that wraps, `n` cells across"""
    g = rng.random((n, n))
    u = np.arange(PX) * n / PX
    i0 = np.floor(u).astype(int)
    f = u - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % n
    i0 %= n
    a = g[np.ix_(i0, i0)]
    b = g[np.ix_(i0, i1)]
    c = g[np.ix_(i1, i0)]
    d = g[np.ix_(i1, i1)]
    fy = f[:, None]
    fx = f[None, :]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def main():
    y, x = np.mgrid[0:PX, 0:PX].astype(np.float64)
    u = (x + 0.5) / CELL       # brick-widths across (+X)
    v = (y + 0.5) / CELL       # and down the image (+Z, south)
    ci = np.floor(u).astype(int)
    cj = np.floor(v).astype(int)
    # which brick each pixel is on: one of four candidates is on the lattice
    kind = np.full(u.shape, -1)
    tx = np.zeros_like(ci)
    tz = np.zeros_like(cj)
    for k, dx, dz in ((0, 0, 0), (0, -1, 0), (1, -2, 0), (1, -2, 1)):
        ok = (kind < 0) & lattice(ci + dx, cj + dz)
        kind[ok] = k
        tx[ok] = ci[ok] + dx
        tz[ok] = cj[ok] + dz
    assert (kind >= 0).all()
    x0 = np.where(kind == 0, tx, tx + 2)
    x1 = np.where(kind == 0, tx + 2, tx + 3)
    z0 = np.where(kind == 0, tz, tz - 1)
    z1 = np.where(kind == 0, tz + 1, tz + 1)
    edge_cm = np.minimum(np.minimum(u - x0, x1 - u), np.minimum(v - z0, z1 - v)) * 10.0

    # each brick its own colour, the same wherever the tile repeats
    key = (kind * 7919 + (tx % CELLS) * 104729 + (tz % CELLS) * 1299709) % 1000003
    ids, inv = np.unique(key, return_inverse=True)
    inv = inv.reshape(key.shape)
    weights = np.array([w for _, w in MIX], float)
    pick = rng.choice(len(MIX), size=len(ids), p=weights / weights.sum())
    cols = np.array([c for c, _ in MIX])[pick] * rng.uniform(0.92, 1.08, (len(ids), 1))
    col = cols[inv]

    # the aggregate: fine flecks, light and dark, and a faint mottle
    grain = rng.random(u.shape)
    col *= (0.96 + 0.08 * periodic_noise(64, 1))[..., None]
    col = np.where((grain > 0.985)[..., None], col * 1.25 + 0.05, col)
    col = np.where((grain < 0.01)[..., None], col * 0.7, col)
    # worn and dirtied in broad patches, darker in a few stains (gum, oil)
    col *= (0.9 + 0.16 * periodic_noise(5, 1))[..., None]
    stain = periodic_noise(40, 1)
    col *= (1.0 - 0.14 * np.clip((stain - 0.9) / 0.06, 0.0, 1.0))[..., None]

    # bevelled edges, sand in the joints
    joint = edge_cm < 0.18
    bevel = np.clip((edge_cm - 0.18) / 0.55, 0.0, 1.0)
    col *= (0.82 + 0.18 * bevel)[..., None]
    sand = np.array([0.42, 0.39, 0.35]) * (0.85 + 0.3 * grain[..., None])
    col = np.where(joint[..., None], sand * 0.75, col)
    col = np.clip(col, 0.0, 1.0)

    # the height: brick tops at 1 with a little texture, down the bevel to the joint
    h = np.where(joint, 0.0, np.sin(bevel * np.pi * 0.5)) + 0.04 * grain * (~joint)
    k = 2.2   # how hard the bevels catch the light
    dhdx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dhdy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    n = np.stack([-dhdx * k, dhdy * k, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)

    here = os.path.dirname(os.path.abspath(__file__))
    Image.fromarray((col * 255 + 0.5).astype(np.uint8)).save(os.path.join(here, "herringbone_pavers_diff.jpg"), quality=90)
    Image.fromarray(((n * 0.5 + 0.5) * 255 + 0.5).astype(np.uint8)).save(os.path.join(here, "herringbone_pavers_nor.jpg"), quality=92)
    m = col.reshape(-1, 3).mean(0)
    print("mean (for TEX_MEAN): Vector3(%.3f, %.3f, %.3f)" % tuple(m))


if __name__ == "__main__":
    main()
