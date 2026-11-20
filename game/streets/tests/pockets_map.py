#!/usr/bin/env python3
"""Draw a city's pockets (tests/pockets.gd writes them): the streets in red have no way back
to the town's main network but against a one-way, those in orange no way to them from it --
both cut off at the map's edge by the bake. Everything else in grey; main roads named.

    python3 game/streets/tests/pockets_map.py pockets_<city>.json out.png [--size 1600]

Reads the city file named in the pockets file; needs Pillow.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from drive_log_map import DRIVE_KINDS, FONT, FONT_B, draw_names  # noqa: E402

TRAP = (235, 70, 70)
CUT = (245, 160, 50)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    size = int(argv[argv.index("--size") + 1]) if "--size" in argv else 1600
    pk = json.load(open(argv[0]))
    city = json.load(open(os.path.join(HERE, "..", "cities", pk["city"] + ".json")))
    k = 1.0 / float(city.get("scale", 10))
    N = city["nodes"]
    trap = {(round(x, 1), round(z, 1)) for x, z in pk["trap"]}
    cut = {(round(x, 1), round(z, 1)) for x, z in pk["cut_off"]}
    xs = [N[i] * k for i in range(0, len(N), 2)]
    zs = [N[i] * k for i in range(1, len(N), 2)]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    sc = (size - 80) / max(x1 - x0, z1 - z0)
    W, H = int((x1 - x0) * sc) + 80, int((z1 - z0) * sc) + 130
    img = Image.new("RGB", (W, H), (16, 18, 24))
    d = ImageDraw.Draw(img)

    def P(x, z):
        return (40 + (x - x0) * sc, 90 + (z - z0) * sc)

    def inside(x, z, m=30):
        return x0 - m <= x <= x1 + m and z0 - m <= z <= z1 + m

    def at(n):
        # (the game's points are the file's, scaled; matched at a decimetre)
        return (round(N[2 * n] * k, 1), round(N[2 * n + 1] * k, 1))
    km = {"trap": 0.0, "cut": 0.0}
    for layer in (0, 1):
        for r in city["roads"]:
            if r.get("k") not in DRIVE_KINDS:
                continue
            w = max(1.5, float(r.get("w", 6)) * sc * 0.9) if layer else max(1.0, float(r.get("w", 6)) * sc * 0.6)
            for a, b in zip(r["n"], r["n"][1:]):
                pa, pb = at(a), at(b)
                col = None
                if pa in trap and pb in trap:
                    col = TRAP
                elif pa in cut and pb in cut:
                    col = CUT
                if layer == 0 and col is None:
                    d.line([P(*pa), P(*pb)], fill=(70, 76, 90), width=int(w))
                elif layer == 1 and col is not None:
                    d.line([P(*pa), P(*pb)], fill=col, width=int(w) + 2)
                    if r.get("k") != "service" and "pv" not in r:
                        L = ((pa[0] - pb[0]) ** 2 + (pa[1] - pb[1]) ** 2) ** 0.5
                        km["trap" if col == TRAP else "cut"] += L
    draw_names(d, city, N, k, [], P, inside, sc, ends=False)
    d.text((40, 14), "%s: streets cut off by the map's edge" % pk["city"], font=FONT_B, fill=(235, 235, 240))
    d.rectangle([40, 48, 58, 60], fill=TRAP)
    d.text((64, 44), "no way out but against a one-way (%.1f km of street)" % (km["trap"] / 1000), font=FONT, fill=(220, 220, 225))
    d.rectangle([520, 48, 538, 60], fill=CUT)
    d.text((544, 44), "no way in from the town (%.1f km)" % (km["cut"] / 1000), font=FONT, fill=(220, 220, 225))
    img.save(argv[1])
    print(argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
