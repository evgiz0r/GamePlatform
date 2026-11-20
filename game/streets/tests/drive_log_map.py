#!/usr/bin/env python3
"""Draw a saved drive log (the "save log" button on the drive map page) over the city.

    python3 game/streets/tests/drive_log_map.py drive-givatayim-....json [out.png]
        [--from SECONDS] [--to SECONDS] [--size 1600] [--at X,Z --span METRES]

The streets (each as wide as the game draws it) and the buildings from the city file the
log names; the car's track coloured by speed (red standing, yellow, green at 50 km/h) with
a tick and the second every 5 s; autodrive's lane ahead every 2 s as a thin blue line (the
plan it was following); the other cars' tracks in grey; hits (red X), rescues (orange
ring), junction choices (blue dot), standstills of 3 s or more (orange dot and the
seconds, with what held it); traffic cars standing 5 s or more not at a light (violet ring,
seconds and what held them, a line to the car holding them up). Street names: the streets
the car drove along in bold white, the main roads in view in grey; the start and the end
ringed. A strip along the bottom: speed against time, coloured by what
held autodrive back (limit, curve, light, car, people...).

Reads only the two JSON files; needs Pillow.
"""
import json
import math
import os
import re
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


def _font(size, bold=False):
    b = "-Bold" if bold else ""
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % b, "/usr/share/fonts/TTF/DejaVuSans%s.ttf" % b):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


FONT = _font(14)
FONT_S = _font(11)
FONT_B = _font(16, bold=True)


MAIN_KINDS = ("motorway", "trunk", "primary", "secondary", "tertiary")
DRIVE_KINDS = MAIN_KINDS + ("unclassified", "residential", "living_street", "service", "road",
                            "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link")


def road_name(r):
    """English name if the map has one, else the local one (Hebrew drawn letter by letter
    comes out backwards without a text shaper: reverse it)"""
    en = r.get("name_en", "")
    if en:
        return en
    nm = r.get("name", "")
    return nm[::-1] if any("\u0590" <= ch <= "\u05ff" for ch in nm) else nm


def _seg_dist(p, a, b):
    ax, az = a
    dx, dz = b[0] - ax, b[1] - az
    L = dx * dx + dz * dz
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / L))
    return math.hypot(p[0] - ax - dx * t, p[1] - az - dz * t)


def draw_names(d, city, nodes, k, samples, P, inside, sc, ends=True):
    """Street names for context: the streets the car drove along in bold white at the middle
    of its stretch on each, the main roads in view in grey, the start and the end marked.
    Labels that would overlap one already placed are left out."""
    roads = []
    for r in city["roads"]:
        if r.get("k") not in DRIVE_KINDS or not road_name(r):
            continue
        pts = [(nodes[2 * n] * k, nodes[2 * n + 1] * k) for n in r["n"]]
        if any(inside(x, z, 60) for x, z in pts):
            roads.append((road_name(r), r.get("k"), pts))
    placed = []

    def label(text, at, font, fill):
        w = d.textlength(text, font=font)
        x, y = at[0] - w / 2, at[1] - 9
        box = (x - 4, y - 3, x + w + 4, y + 20)
        if any(not (box[2] < b[0] or box[0] > b[2] or box[3] < b[1] or box[1] > b[3]) for b in placed):
            return False
        placed.append(box)
        d.text((x, y), text, font=font, fill=fill, stroke_width=3, stroke_fill=(16, 18, 24))
        return True
    # the streets driven: each second's sample matched to the nearest named street
    runs = []   # [name, [samples]]
    for smp in samples[::10]:
        best, bd = None, 9.0
        q = (smp["x"], smp["z"])
        for name, kind, pts in roads:
            for a, b in zip(pts, pts[1:]):
                dd = _seg_dist(q, a, b)
                if dd < bd:
                    best, bd = name, dd
        if best and runs and runs[-1][0] == best:
            runs[-1][1].append(smp)
        elif best:
            runs.append([best, [smp]])
    driven = set()
    for name, smps in runs:
        if len(smps) < 4 or name in driven:   # (4 s or more along it)
            continue
        mid = smps[len(smps) // 2]
        if label(name, P(mid["x"], mid["z"]), FONT_B, (255, 255, 255)):
            driven.add(name)
    # the main roads in view, once each, at the middle of their stretch in view
    seen = set()
    for name, kind, pts in sorted(roads, key=lambda r: MAIN_KINDS.index(r[1]) if r[1] in MAIN_KINDS else 9):
        if kind not in MAIN_KINDS or name in seen or name in driven:
            continue
        vis = [p for p in pts if inside(p[0], p[1], -20)]
        if len(vis) < 2:
            continue
        a, b = vis[len(vis) // 2 - 1], vis[len(vis) // 2]
        if label(name, P((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), FONT, (175, 180, 195)):
            seen.add(name)
    # start and end of the path
    for smp, what, col in [] if not ends else ((samples[0], "start", (120, 220, 140)), (samples[-1], "end", (240, 120, 120))):
        p = P(smp["x"], smp["z"])
        d.ellipse([p[0] - 8, p[1] - 8, p[0] + 8, p[1] + 8], outline=col, width=3)
        d.text((p[0] + 11, p[1] - 22), what, font=FONT_B, fill=col, stroke_width=3, stroke_fill=(16, 18, 24))


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
    if "at" in opts:   # framed on a place (a junction watched), not on the player's car
        cx, cz = (float(v) for v in opts["at"].split(","))
        span = float(opts.get("span", 160))
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
    # traffic standstills of 5 s or more (not at a light): a violet ring, the seconds and what
    # held it, and a line to the car holding it up (or to the player's car)
    dt = 1.0 / float(log.get("hz", 10))
    runs = {}   # car id -> [seconds, first sample's car row, sample]
    def close_run(cid):
        r = runs.pop(cid, None)
        if not r or r[0] < 5.0:
            return
        c, smp = r[1], r[2]
        p = P(c[2], c[3])
        d.ellipse([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], outline=(190, 120, 255), width=2)
        why = c[7] if len(c) > 7 else ""
        d.text((p[0] + 8, p[1] - 6), "%ds %s" % (r[0], why), fill=(200, 160, 255), font=FONT_S)
        if c[6] == -1:
            q = P(smp["x"], smp["z"])
        else:
            q = next((P(o[2], o[3]) for o in smp["cars"] if o[0] == c[6]), None)
        if q and c[6] >= -1:
            d.line([p, q], fill=(190, 120, 255), width=1)
    for smp in samples:
        here = set()
        for c in smp["cars"]:
            here.add(c[0])
            why = c[7] if len(c) > 7 else ""
            if c[5] < 0.3 and why != "light":
                r = runs.setdefault(c[0], [0.0, c, smp])
                r[0] += dt
            else:
                close_run(c[0])
        for cid in [k for k in runs if k not in here]:
            close_run(cid)
    for cid in list(runs):
        close_run(cid)
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
        who = re.match(r"car (\d+)", str(ev[2]))
        if who:   # an event about a traffic car: at that car, ringed in red
            row = next((c for c in at["cars"] if c[0] == int(who.group(1))), None)
            if row:
                p = P(row[2], row[3])
                d.ellipse([p[0] - 10, p[1] - 10, p[0] + 10, p[1] + 10], outline=(255, 70, 70), width=3)
                d.text((p[0] + 12, p[1] - 8), "%ds %s (%s)" % (ev[0], ev[1], row[1]), fill=(255, 140, 140),
                       font=FONT_S, stroke_width=2, stroke_fill=(16, 18, 24))
                continue
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
    draw_names(d, city, nodes, k, samples, P, inside, sc, ends="at" not in opts)
    # what the path's colour means: a bar from standing to 50 km/h, on a dark plate
    lx, ly = 10, 26
    d.rectangle([lx - 6, ly - 4, lx + 330, ly + 40], fill=(16, 18, 24))
    d.text((lx, ly), "the car's path, coloured by its speed:", fill=(230, 230, 230), font=FONT)
    for k in range(200):
        d.line([lx + k, ly + 20, lx + k, ly + 30], fill=speed_col(k / 200 * 14.0))
    for kmh in (0, 25, 50):
        x = lx + kmh / 50.4 * 200
        d.text((x - 4, ly + 30), "%d" % kmh, fill=(200, 200, 200), font=FONT_S)
    d.text((lx + 210, ly + 18), "km/h", fill=(200, 200, 200), font=FONT)
    img.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
