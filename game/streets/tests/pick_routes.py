#!/usr/bin/env python3
"""Pick the route set: random drives from one address to another, kept in routes.json so the
same drives can be run again and again (tests/route_set.gd) and their results compared.

    python3 game/streets/tests/pick_routes.py [seed]

Per city a share of the ten (Givatayim 4, Ashdod 3, Tel Aviv, Bedford and the test town one
each); the two ends real addresses (a building's or an address point's) within 40 m of a
public drivable road, on different streets, a real drive apart (0.8-2.5 km as the crow
flies; less in the small test town). Run it again only to start a new set -- results are
tracked against the routes' numbers.

PRIVACY (see DEV.md): the web build is public. Nothing within 800 m of the corner of Ha-Meri
and Sheinkin in Givatayim, and nothing on HaAtzmaut in Ashdod -- places the user has named
as theirs or their family's.
"""
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CITIES = [  # level (1-based, as in LEVELS), city file, how many, crow-fly range (m)
    (1, "givatayim", 4, (800, 2500)),
    (3, "ashdod", 3, (800, 2500)),
    (7, "tel_aviv", 1, (700, 2200)),
    (2, "bedford", 1, (800, 2500)),
    (4, "dimyon", 1, (250, 900)),
]
DRIVE = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
         "living_street", "road", "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
AVOID_STREETS = {"ashdod": ["העצמאות"]}
AVOID_CORNERS = {"givatayim": [("HaMeri", "Sheinkin")]}   # (by the English names: the Hebrew is spelled more than one way)


def seg_dist(p, a, b):
    dx, dz = b[0] - a[0], b[1] - a[1]
    L = dx * dx + dz * dz
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / L))
    return math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dz * t)


def main(argv):
    seed = int(argv[0]) if argv else 2026
    rng = random.Random(seed)
    routes = []
    for level, cid, count, (lo, hi) in CITIES:
        path = os.path.join(HERE, "..", "cities", cid + ".json")
        if not os.path.exists(path):
            continue
        c = json.load(open(path))
        k = 1.0 / float(c.get("scale", 10))
        N = c["nodes"]
        roads = []
        for r in c["roads"]:
            if r.get("k") in DRIVE and "pv" not in r:
                roads.append([(N[2 * n] * k, N[2 * n + 1] * k) for n in r["n"]])
        # a coarse grid of the roads, to find the nearest one quickly
        grid = {}
        for ri, pts in enumerate(roads):
            for a, b in zip(pts, pts[1:]):
                for x in range(int(min(a[0], b[0]) // 50), int(max(a[0], b[0]) // 50) + 1):
                    for z in range(int(min(a[1], b[1]) // 50), int(max(a[1], b[1]) // 50) + 1):
                        grid.setdefault((x, z), []).append((a, b))

        def near_road(p):
            best = 1e9
            for dx in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for a, b in grid.get((int(p[0] // 50) + dx, int(p[1] // 50) + dz), []):
                        best = min(best, seg_dist(p, a, b))
            return best
        # corners to keep away from
        avoid_at = []
        for s1, s2 in AVOID_CORNERS.get(cid, []):
            n1 = {n for r in c["roads"] if r.get("name_en") == s1 for n in r["n"]}
            n2 = {n for r in c["roads"] if r.get("name_en") == s2 for n in r["n"]}
            for n in n1 & n2:
                avoid_at.append((N[2 * n] * k, N[2 * n + 1] * k))
        if AVOID_CORNERS.get(cid) and not avoid_at:
            print("could not find the corner to avoid in %s: not picking there" % cid)
            continue
        addrs = []
        for b in c["buildings"]:
            a = b.get("addr", "")
            if not a or " " not in a:
                continue
            ring = b["p"]
            xs = [ring[i] * k for i in range(0, len(ring), 2)]
            zs = [ring[i + 1] * k for i in range(0, len(ring), 2)]
            addrs.append((a, ((min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2)))
        for a in c.get("addrs", []):
            addrs.append(("%s %s" % (a[2], a[3]), (a[0] * k, a[1] * k)))
        ok = []
        for label, p in addrs:
            street = label.rsplit(" ", 1)[0]
            if any(s in street for s in AVOID_STREETS.get(cid, [])):
                continue
            if "רכבת" in street or "rail" in street.lower():
                continue   # (an address point on the light rail is not a place to drive to)
            if any(math.dist(p, q) < 800 for q in avoid_at):
                continue
            if near_road(p) > 40:
                continue
            ok.append((label, p))
        ok.sort()
        picked = 0
        tries = 0
        while picked < count and tries < 20000 and len(ok) > 1:
            tries += 1
            a = rng.choice(ok)
            b = rng.choice(ok)
            d = math.dist(a[1], b[1])
            if a[0].rsplit(" ", 1)[0] == b[0].rsplit(" ", 1)[0] or not (lo <= d <= hi):
                continue
            routes.append({"id": len(routes) + 1, "level": level, "city": cid, "from": a[0],
                           "from_at": [round(a[1][0], 1), round(a[1][1], 1)], "to": b[0],
                           "to_at": [round(b[1][0], 1), round(b[1][1], 1)], "crow_m": int(d)})
            picked += 1
    out = os.path.join(HERE, "routes.json")
    json.dump({"seed": seed, "routes": routes}, open(out, "w"), ensure_ascii=False, indent=1)
    for r in routes:
        print("%2d  %-10s %s -> %s  (%d m)" % (r["id"], r["city"], r["from"], r["to"], r["crow_m"]))
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
