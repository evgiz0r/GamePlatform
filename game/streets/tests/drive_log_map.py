#!/usr/bin/env python3
"""Draw a saved drive log (the "save log" button on the drive map page) over the city.

    python3 game/streets/tests/drive_log_map.py drive-givatayim-....json [out.png]
        [--from SECONDS] [--to SECONDS] [--size 1600]

The streets (each as wide as the game draws it) and the buildings from the city file the
log names; the car's track coloured by speed (red standing, yellow, green at 50 km/h) with
a tick and the second every 5 s; autodrive's lane ahead every 2 s as a thin blue line (the
plan it was following); the other cars' tracks in grey; hits (red X), rescues (orange
ring), junction choices (blue dot), standstills of 3 s or more (orange dot and the
seconds, with what held it). A strip along the bottom: speed against time, coloured by what
held autodrive back (limit, curve, light, car, people...).

Reads only the two JSON files; needs Pillow.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
WHY_COL = {"limit": (90, 200, 120), "curve": (60, 160, 230), "light": (230, 60, 60), "sign": (230, 140, 40),
           "zebra": (240, 220, 60), "people": (240, 220, 60), "car": (170, 100, 230), "blocked": (240, 90, 160),
           "choice": (120, 200, 240), "backing": (255, 255, 255), "turning": (160, 160, 170),
           "pushing": (150, 40, 40), "": (150, 150, 150)}
WHY_NAME = {"limit": "nothing (the speed limit)", "curve": "a bend or a turn", "light": "a traffic light",
            "sign": "a stop / give-way sign", "zebra": "people on a crossing", "car": "the car ahead",
            "blocked": "something in front", "choice": "a junction (which way?)",
            "backing": "backing off", "turning": "turning round", "pushing": "pushing, not moving (stuck)"}


def _font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


FONT = _font(14)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    opts = {}
    for i, a in enumerate(argv):
        if a.startswith("--") and i + 1 < len(argv):
            opts[a[2:]] = argv[i + 1]
    if not args:
        print(__doc__)
        return 1
    log = json.load(open(args[0]))
    out = args[1] if len(args) > 1 and args[1].endswith(".png") else os.path.splitext(args[0])[0] + ".png"
    t0 = float(opts.get("from", -1e9))
    t1 = float(opts.get("to", 1e9))
    size = int(opts.get("size", 1600))
    samples = [s for s in log["samples"] if t0 <= s["t"] <= t1]
    if not samples:
        print("no samples in that time")
        return 1
    city = json.load(open(os.path.join(HERE, "..", "cities", log["city"] + ".json")))
    k = 1.0 / float(city.get("scale", 10))
    nodes = city["nodes"]

    xs = [s["x"] for s in samples]
    zs = [s["z"] for s in samples]
    x0, x1, z0, z1 = min(xs) - 40, max(xs) + 40, min(zs) - 40, max(zs) + 40
    span = max(x1 - x0, z1 - z0, 120)
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    x0, z0 = cx - span / 2, cz - span / 2
    strip = 262
    W, H = size, size + strip
    sc = size / span
    img = Image.new("RGB", (W, H), (24, 26, 34))
    d = ImageDraw.Draw(img)

    def P(x, z):
        return ((x - x0) * sc, (z - z0) * sc)

    def inside(x, z, m=30):
        return x0 - m <= x <= x0 + span + m and z0 - m <= z <= z0 + span + m

    for b in city["buildings"]:
        ring = b["p"]
        pts = [(ring[i] * k, ring[i + 1] * k) for i in range(0, len(ring), 2)]
        if not any(inside(x, z) for x, z in pts):
            continue
        d.polygon([P(x, z) for x, z in pts], fill=(48, 52, 66), outline=(70, 76, 94))
    for r in city["roads"]:
        pts = [(nodes[2 * n] * k, nodes[2 * n + 1] * k) for n in r["n"]]
        if not any(inside(x, z) for x, z in pts):
            continue
        col = (90, 94, 108) if r.get("k") not in ("footway", "path", "cycleway", "steps", "pedestrian") else (60, 70, 60)
        d.line([P(x, z) for x, z in pts], fill=col, width=max(1, int(float(r.get("w", 6)) * sc)))
        if r.get("o", 0):
            a, b = pts[len(pts) // 2 - 1 if len(pts) > 1 else 0], pts[len(pts) // 2]
            if a != b:
                dx, dz = (b[0] - a[0]) * r["o"], (b[1] - a[1]) * r["o"]
                L = math.hypot(dx, dz)
                m = P((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
                d.line([m, (m[0] + dx / L * 8, m[1] + dz / L * 8)], fill=(130, 136, 150), width=1)

    # other cars
    tracks = {}
    for s in samples:
        for c in s["cars"]:
            tracks.setdefault(c[0], []).append(P(c[2], c[3]))
    for tr in tracks.values():
        for a, b in zip(tr, tr[1:]):
            if math.dist(a, b) < 25 * sc:   # (a car sent elsewhere jumps: no line across the map)
                d.line([a, b], fill=(120, 120, 130), width=1)
    # plans every 2 s
    for i, s in enumerate(samples):
        if i % 20 == 0 and len(s["plan"]) > 1:
            d.line([P(x, z) for x, z in s["plan"]], fill=(80, 150, 255), width=1)
    # the track by speed, ticks every 5 s
    def speed_col(v):
        f = max(0.0, min(1.0, abs(v) / 14.0))
        return (int(230 - 170 * f), int(60 + 170 * f), 70) if f > 0.5 else (230, int(60 + 340 * f), 60)
    for a, b in zip(samples, samples[1:]):
        pa, pb = P(a["x"], a["z"]), P(b["x"], b["z"])
        if math.dist(pa, pb) < 60:
            d.line([pa, pb], fill=speed_col(b["v"]), width=3)
    for s in samples:
        if abs((s["t"] % 5.0)) < 0.05:
            p = P(s["x"], s["z"])
            d.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=(255, 255, 255))
            d.text((p[0] + 4, p[1] - 10), "%d" % s["t"], fill=(220, 220, 220))
    # standstills
    still, start = 0.0, None
    for s in samples + [{"v": 99, "why": "", "t": 1e9, "x": 0, "z": 0}]:
        if abs(s["v"]) < 0.3 and s.get("why") != "light":
            if still == 0.0:
                start = s
            still += 1.0 / float(log.get("hz", 10))
        else:
            if still >= 3.0 and start:
                p = P(start["x"], start["z"])
                d.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], fill=(240, 160, 40))
                d.text((p[0] + 7, p[1] + 2), "%ds %s" % (still, start.get("why", "")), fill=(240, 180, 80))
            still = 0.0
    # events
    for ev in log["events"]:
        if not (t0 <= ev[0] <= t1):
            continue
        at = min(samples, key=lambda s: abs(s["t"] - ev[0]))
        p = P(at["x"], at["z"])
        if ev[1] == "hit":
            d.line([p[0] - 7, p[1] - 7, p[0] + 7, p[1] + 7], fill=(255, 60, 60), width=3)
            d.line([p[0] - 7, p[1] + 7, p[0] + 7, p[1] - 7], fill=(255, 60, 60), width=3)
            d.text((p[0] + 9, p[1] - 14), "%ds hit %s" % (ev[0], ev[2]), fill=(255, 120, 120))
        elif ev[1] in ("rescue", "unstuck"):
            d.ellipse([p[0] - 9, p[1] - 9, p[0] + 9, p[1] + 9], outline=(240, 160, 40), width=2)
            d.text((p[0] + 10, p[1]), "%ds %s" % (ev[0], ev[1]), fill=(240, 180, 80))
        else:
            d.ellipse([p[0] - 3, p[1] - 3, p[0] + 3, p[1] + 3], fill=(90, 170, 255))
            d.text((p[0] + 5, p[1] + 3), "%ds %s %s" % (ev[0], ev[1], ev[2] if ev[2] != "" else ""), fill=(140, 190, 255))
    # the strip: speed by time, coloured by what held it
    y0, hh, lx = size + 34, 130, 64          # top of the plot, its height, left margin
    ta, tb = samples[0]["t"], samples[-1]["t"]
    top_v = 60.0 / 3.6                        # the plot's top: 60 km/h
    d.rectangle([0, size, W, H], fill=(16, 18, 24))
    d.text((10, size + 8), "speed (km/h) against time -- the line's colour says what autodrive was slowing down for",
           fill=(230, 230, 230), font=FONT)

    def TX(t):
        return lx + (t - ta) / max(tb - ta, 1) * (W - lx - 20)

    def VY(v):
        return y0 + hh - min(abs(v) / top_v, 1) * hh
    for kmh in (0, 20, 40, 60):
        y = VY(kmh / 3.6)
        d.line([lx, y, W - 20, y], fill=(44, 48, 60), width=1)
        d.text((10, y - 8), "%d" % kmh, fill=(150, 150, 160), font=FONT)
    step = 30 if tb - ta > 90 else 10
    t = math.ceil(ta / step) * step
    while t <= tb:
        d.line([TX(t), y0 + hh, TX(t), y0 + hh + 5], fill=(150, 150, 160), width=1)
        d.text((TX(t) - 12, y0 + hh + 6), "%d s" % t, fill=(150, 150, 160), font=FONT)
        t += step
    for a, b in zip(samples, samples[1:]):
        d.line([TX(a["t"]), VY(a["v"]), TX(b["t"]), VY(b["v"])],
               fill=WHY_COL.get(b.get("why", ""), (200, 200, 200)), width=2)
    x, ly = 10, y0 + hh + 30
    for why, col in WHY_COL.items():
        if why and why != "people":
            name = WHY_NAME.get(why, why)
            wide = 30 + int(d.textlength(name, font=FONT))
            if x + wide > W:
                x, ly = 10, ly + 20
            d.rectangle([x, ly + 2, x + 12, ly + 14], fill=col)
            d.text((x + 17, ly), name, fill=(220, 220, 220), font=FONT)
            x += wide
    d.text((10, 6), "%s  %s  %.0f-%.0f s  (grid: the streets as drawn; blue: autodrive's plan every 2 s)" % (
        log.get("name", log["city"]), log.get("made", ""), ta, tb), fill=(230, 230, 230))
    img.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
