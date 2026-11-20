#!/usr/bin/env python3
"""A bus going round a corner, seen from above: tests/traffic_motion.gd's bus_turn.json.

    python3 game/streets/tests/bus_turn_chart.py bus_turn.json out.png ["title"]

The streets and buildings round the turn, and the bus's outline every half second, light
to dark as time goes on, its front marked. A bus that pivots on its middle swings its back
out across the lane; one whose rear follows its front cuts the corner a little, as a real
one does. Needs Pillow.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAMP = [(210, 228, 250), (180, 210, 247), (140, 186, 241), (98, 160, 235), (57, 135, 229), (40, 102, 184), (31, 79, 145)]


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    data = json.load(open(argv[0]))
    title = argv[2] if len(argv) > 2 else "A bus going round a corner"
    city = json.load(open(os.path.join(HERE, "..", "cities", data["city"] + ".json")))
    k = 1.0 / float(city.get("scale", 10))
    nodes = city["nodes"]
    S = data["samples"][::2]   # every half second
    xs = [s[1] for s in S]
    zs = [s[2] for s in S]
    cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
    span = max(max(xs) - min(xs), max(zs) - min(zs)) + 40
    size = 900
    sc = size / span
    x0, z0 = cx - span / 2, cz - span / 2
    img = Image.new("RGB", (size, size + 60), (24, 26, 34))
    d = ImageDraw.Draw(img)

    def P(x, z):
        return ((x - x0) * sc, (z - z0) * sc + 60)

    def near(pts):
        return any(x0 - 30 <= x <= x0 + span + 30 and z0 - 30 <= z <= z0 + span + 30 for x, z in pts)
    for b in city["buildings"]:
        ring = b["p"]
        pts = [(ring[i] * k, ring[i + 1] * k) for i in range(0, len(ring), 2)]
        if near(pts):
            d.polygon([P(x, z) for x, z in pts], fill=(48, 52, 66), outline=(70, 76, 94))
    for r in city["roads"]:
        pts = [(nodes[2 * n] * k, nodes[2 * n + 1] * k) for n in r["n"]]
        if near(pts) and r.get("k") not in ("footway", "path", "cycleway", "steps", "pedestrian"):
            d.line([P(x, z) for x, z in pts], fill=(90, 94, 108), width=max(1, int(float(r.get("w", 6)) * sc)))
    for n, (t, x, z, yaw, length) in enumerate(S):
        fx, fz = math.sin(yaw), math.cos(yaw)       # forward
        rx, rz = fz, -fx                            # right
        hl, hw = length / 2, 1.25
        corners = [(x + fx * hl + rx * hw, z + fz * hl + rz * hw), (x + fx * hl - rx * hw, z + fz * hl - rz * hw),
                   (x - fx * hl - rx * hw, z - fz * hl - rz * hw), (x - fx * hl + rx * hw, z - fz * hl + rz * hw)]
        col = RAMP[min(len(RAMP) - 1, n * len(RAMP) // max(len(S), 1))]
        d.polygon([P(a, b) for a, b in corners], outline=col)
        f1, f2 = P(*corners[0]), P(*corners[1])
        d.line([f1, f2], fill=(255, 255, 255), width=2)   # its front
    d.text((14, 12), title, font=font(20), fill=(240, 239, 236))
    d.text((14, 38), "the bus every half second, light to dark; white edge: its front", font=font(13), fill=(195, 194, 183))
    img.save(argv[1])
    print(argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
