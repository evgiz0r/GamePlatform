#!/usr/bin/env python3
"""Walks that were never filmed: a route along real streets, on the pavement, timed at a
person's pace, waiting at each kerb and looking both ways before crossing -- written into
cities/details/<city>.json as a walk the game replays in first person, the same as a filmed
one (streets.gd "a filmed walk, replayed"; the "Walks" list in LEVELS opens them).

  python make_walks.py              # (re)write every walk in WALKS below into its city's details file
  python make_walks.py --list CITY STREET    # STREET's junctions in order, with the metres between
                                             # (to pick a leg's ends by the cross street's name)

A walk is legs: [street, from the junction with this street, to the junction with that one],
each leg along one street between two junctions (the next leg starts where the last ended),
and which pavement: "right" or "left" of the way it walks. The route is the street's own
centre line set off to the pavement (half its width and PAVE metres more, `pave` per walk);
where it crosses a street (a turn across one, a side street's mouth) it stops at the kerb,
looks left and right, and crosses with the cars held for it (the walk's `zebras`).

What it does not know: what stands on the pavement (trees, poles, bins, café tables, bus
shelters). The walks it writes carry `dodge`: the game steps them round every post as it
loads (streets.gd _film_dodge), so a tree OSM maps, or a bin another session puts on the
pavement later, is walked round, not through. Run the scan (`SCAN=1 tests/run.sh
filmed_walk <level>`) after a change all the same: it should print only "scan done". Points it writes carry `"src": "make_walks"`: rewritten on the next
run; everything else in the details file is kept.
"""
import heapq
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CITIES = os.path.join(HERE, "..", "cities")
PACE = 1.35     # m/s: an unhurried walk (the filmed walks average 1.3)
PAVE = 2.05     # metres from the road's edge to the walk's line: behind the row of street trees the
                # game plants (streets.gd: half the width + 1.3, r 0.3) and 0.55 m short of the
                # pavement's back (kerb 0.2 + pavement 2.4). At 1.9 the walks went through the trees
CROSS_PACE = 1.45
WALKABLE = {"primary", "secondary", "tertiary", "residential", "living_street", "unclassified",
            "primary_link", "secondary_link", "tertiary_link", "road"}
CARS = WALKABLE | {"service", "trunk", "trunk_link"}

# id: city, the name the list shows, legs [street, from junction with, to junction with], side,
# and optional pave (metres from the road's edge) and promenade (a divided boulevard walked
# down its middle, not along its outer pavements: each carriageway's inner side)
WALKS = {
    "tel_aviv_rothschild": {
        "city": "tel_aviv", "name": "Tel Aviv: along Rothschild",
        "legs": [["שדרות רוטשילד", "נחלת בנימין", "שד\"ל"]], "promenade": True,
    },
    "ashdod_halutzim": {
        "city": "ashdod", "name": "Ashdod: HeHalutzim to Herzl",
        "legs": [["החלוצים", "העצמאות", "שדרות הרצל"]], "side": "right",
    },
    "bedford_shore": {
        "city": "bedford", "name": "Bedford: Shore Drive by the water",
        "legs": [["Shore Drive", "Bedford Harbourwalk", "Shipyard Road"]], "side": "left",
    },
    "dimyon_market": {
        "city": "dimyon", "name": "Test town: through the market street",
        "legs": [["השוק", "הגפן", "הנשיא"]], "side": "left",   # (the right pavement is the stalls' and a shop front 1.5 m apart)
    },
}


def load(city):
    with open(os.path.join(CITIES, city + ".json"), encoding="utf-8") as fh:
        d = json.load(fh)
    sc = float(d.get("scale", 10))
    n = d["nodes"]
    pts = [(n[2 * i] / sc, n[2 * i + 1] / sc) for i in range(len(n) // 2)]
    return d, pts


def ends_meeting(d, street, cross):
    """the nodes where a way of `street` meets a way of `cross` (a node both use)"""
    a = set()
    for r in d["roads"]:
        if r.get("name") == street:
            a.update(r["n"])
    b = set()
    for r in d["roads"]:
        if r.get("name") == cross:
            b.update(r["n"])
    return sorted(a & b)


def graph(d, pts, street):
    g = {}
    width = {}
    for r in d["roads"]:
        if r.get("name") != street or r.get("k") not in WALKABLE:
            continue
        w = float(r.get("w", 7.0))
        o = int(r.get("o", 0))
        for u, v in zip(r["n"], r["n"][1:]):
            L = math.dist(pts[u], pts[v])
            g.setdefault(u, []).append((v, L))
            g.setdefault(v, []).append((u, L))
            # (width, and for one carriageway of a divided road the side its pavement is on,
            # walking u to v: its traffic's right, the median on its left)
            width[(u, v)] = (w, "right" if o == 1 else "left" if o == -1 else None)
            width[(v, u)] = (w, "left" if o == 1 else "right" if o == -1 else None)
    return g, width


def path(g, a, b):
    dist = {a: 0.0}
    prev = {}
    q = [(0.0, a)]
    while q:
        dd, u = heapq.heappop(q)
        if u == b:
            break
        if dd > dist.get(u, 1e18):
            continue
        for v, L in g.get(u, []):
            if dd + L < dist.get(v, 1e18):
                dist[v] = dd + L
                prev[v] = u
                heapq.heappush(q, (dd + L, v))
    if b not in dist:
        return None
    out = [b]
    while out[-1] != a:
        out.append(prev[out[-1]])
    return out[::-1], dist[b]


def leg_nodes(d, pts, street, frm, to, start=None):
    g, width = graph(d, pts, street)
    A = [start] if start is not None else [n for n in ends_meeting(d, street, frm) if n in g]
    B = [n for n in ends_meeting(d, street, to) if n in g]
    if to == street:   # "to itself": the far end of the street from the start
        B = [n for n in g if len(g[n]) == 1]
    best = None
    for a in A:
        for b in B:
            if a == b:
                continue
            p = path(g, a, b)
            if p and (best is None or (p[1] > best[1] if to == street else p[1] < best[1])):
                best = p
    if best is None:
        sys.exit("no way along %s from %s to %s" % (street, frm, to))
    nodes = best[0]
    ws = [width[(u, v)] for u, v in zip(nodes, nodes[1:])]
    return nodes, ws


def offset_line(line, ws, side, pave, promenade=False):
    """the centre line set off to one side by each segment's half width plus pave (miter joins,
    capped; + side: right of the way it runs, x east and z south)"""
    segs = []
    for (a, b), (w, own) in zip(zip(line, line[1:]), ws):
        # a one-way carriageway's pavement is on its outer side whichever way the walk goes
        # (walking against the traffic, "right" was the median: Ashdod's walk went down the
        # other carriageway)
        s = 1.0 if (own or side) == "right" else -1.0
        if promenade and own:   # (a boulevard's middle: the carriageway's inner side)
            s = -s
        dx, dz = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dz)
        if L < 1e-6:
            continue
        ux, uz = dx / L, dz / L
        nx, nz = -uz * s, ux * s   # right of (ux, uz) with z down the map: (-uz, ux)
        o = w / 2 + pave
        segs.append(((a[0] + nx * o, a[1] + nz * o), (b[0] + nx * o, b[1] + nz * o), (ux, uz)))
    out = [segs[0][0]]
    for (a1, b1, u1), (a2, b2, u2) in zip(segs, segs[1:]):
        den = u1[0] * u2[1] - u1[1] * u2[0]
        if abs(den) < 0.05:   # nearly straight on: the two ends' middle
            out.append(((b1[0] + a2[0]) / 2, (b1[1] + a2[1]) / 2))
            continue
        t = ((a2[0] - a1[0]) * u2[1] - (a2[1] - a1[1]) * u2[0]) / den
        p = (a1[0] + u1[0] * t, a1[1] + u1[1] * t)
        if math.dist(p, b1) > 6.0:   # a sharp corner: cut it (two points, not a spike)
            out += [b1, a2]
        else:
            out.append(p)
    out.append(segs[-1][1])
    return out


def seg_hit(p, q, a, b):
    """where p-q crosses a-b: (fraction along p-q, point) or None"""
    rx, rz = q[0] - p[0], q[1] - p[1]
    sx, sz = b[0] - a[0], b[1] - a[1]
    den = rx * sz - rz * sx
    if abs(den) < 1e-9:
        return None
    t = ((a[0] - p[0]) * sz - (a[1] - p[1]) * sx) / den
    u = ((a[0] - p[0]) * rz - (a[1] - p[1]) * rx) / den
    if 0 <= t <= 1 and 0 <= u <= 1:
        return t, (p[0] + rx * t, p[1] + rz * t)
    return None


def crossings(d, pts, line):
    """every road the walk's line crosses: [distance along the line, the road's width, point]"""
    cum = [0.0]
    for a, b in zip(line, line[1:]):
        cum.append(cum[-1] + math.dist(a, b))
    lo = (min(p[0] for p in line) - 30, min(p[1] for p in line) - 30)
    hi = (max(p[0] for p in line) + 30, max(p[1] for p in line) + 30)
    hits = []
    for r in d["roads"]:
        if r.get("k") not in CARS:
            continue
        w = float(r.get("w", 6.0))
        for u, v in zip(r["n"], r["n"][1:]):
            a, b = pts[u], pts[v]
            if max(a[0], b[0]) < lo[0] or min(a[0], b[0]) > hi[0] or max(a[1], b[1]) < lo[1] or min(a[1], b[1]) > hi[1]:
                continue
            for i, (p, q) in enumerate(zip(line, line[1:])):
                h = seg_hit(p, q, a, b)
                if h:
                    hits.append([cum[i] + h[0] * (cum[i + 1] - cum[i]), w, h[1]])
    hits.sort()
    merged = []
    for h in hits:   # one junction's several ways (a divided road, a junction's points): one crossing
        if merged and h[0] - merged[-1][1] < 4.0:
            merged[-1][1] = max(merged[-1][1], h[0])
            merged[-1][2] = max(merged[-1][2], h[1])
        else:
            merged.append([h[0], h[0], h[1]])
    return merged, cum


def at(line, cum, s):
    s = max(0.0, min(cum[-1], s))
    for i in range(len(cum) - 1):
        if cum[i + 1] >= s:
            f = (s - cum[i]) / max(cum[i + 1] - cum[i], 1e-9)
            a, b = line[i], line[i + 1]
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
    return line[-1]


def build(wid, spec):
    d, pts = load(spec["city"])
    line = []
    ws = []
    start = None
    for street, frm, to in spec["legs"]:
        nodes, w = leg_nodes(d, pts, street, frm, to, start)
        if line:
            nodes = nodes[1:] if nodes[0] == start else nodes
            w = w if len(w) == len(nodes) - 1 else w[1:]
            ws.append(w[0] if w else ws[-1])
        line += [pts[n] for n in nodes]
        ws += w
        start = nodes[-1]
    ws = ws[: len(line) - 1]
    walk = offset_line(line, ws, spec.get("side", "right"), float(spec.get("pave", PAVE)), bool(spec.get("promenade", False)))
    hits, cum = crossings(d, pts, walk)
    total = cum[-1]
    # the timed points: every ~4 m at the pace, a wait at each kerb, the crossing quicker
    out = []
    looks = []
    zebras = []
    t = 0.0
    s = 0.0
    k = 0
    seed = sum(ord(c) for c in wid)
    for h in hits + [[total + 1e9, total + 1e9, 0]]:
        kerb_a = h[0] - (h[2] / 2 + 0.5)
        kerb_b = h[1] + (h[2] / 2 + 0.5)
        stop = min(kerb_a, total)
        while s < stop - 0.01:
            out.append([round(t, 2), *[round(v, 2) for v in at(walk, cum, s)]])
            step = min(4.0, stop - s)
            pace = PACE * (1.0 + 0.06 * math.sin(seed + k * 1.7))
            s += step
            t += step / pace
            k += 1
        if h[0] > total:
            out.append([round(t, 2), *[round(v, 2) for v in at(walk, cum, total)]])
            break
        if kerb_a < 0:   # (a crossing right at the start: start on its far side)
            s = kerb_b
            continue
        p_a = at(walk, cum, kerb_a)
        p_b = at(walk, cum, kerb_b)
        wait = 1.8 + 1.4 * ((seed * 7 + k * 13) % 10) / 10.0
        out.append([round(t, 2), round(p_a[0], 2), round(p_a[1], 2)])
        looks.append([round(t + 0.1, 2), round(t + wait * 0.45, 2), -55])
        looks.append([round(t + wait * 0.5, 2), round(t + wait - 0.1, 2), 50])
        t0 = t
        t += wait
        out.append([round(t, 2), round(p_a[0], 2), round(p_a[1], 2)])
        t += (kerb_b - kerb_a) / CROSS_PACE
        out.append([round(t, 2), round(p_b[0], 2), round(p_b[1], 2)])
        zebras.append([round(t0, 2), round(t, 2), [round(p_a[0], 2), round(p_a[1], 2)], [round(p_b[0], 2), round(p_b[1], 2)]])
        s = kerb_b + 0.01
    return {"name": spec["name"], "src": "make_walks", "dodge": True, "points": out, "looks": looks, "zebras": zebras}, total, len(hits)


def write(city, walks):
    path_ = os.path.join(CITIES, "details", city + ".json")
    d = {}
    if os.path.exists(path_):
        with open(path_, encoding="utf-8") as fh:
            d = json.load(fh)
    w = {k: v for k, v in d.get("walks", {}).items() if v.get("src") != "make_walks"}
    w.update(walks)
    d["walks"] = w
    with open(path_, "w", encoding="utf-8") as fh:
        json.dump(d, fh, ensure_ascii=False, indent=1)
        fh.write("\n")


def list_junctions(city, street):
    d, pts = load(city)
    g, _ = graph(d, pts, street)
    names = {}
    for r in d["roads"]:
        if r.get("name") and r.get("name") != street:
            for n in r["n"]:
                if n in g:
                    names.setdefault(n, set()).add(r["name"])
    ends = [n for n in g if len(g[n]) == 1] or list(g)[:1]
    a = ends[0]
    dist = {a: 0.0}
    q = [(0.0, a)]
    while q:
        dd, u = heapq.heappop(q)
        for v, L in g[u]:
            if dd + L < dist.get(v, 1e18):
                dist[v] = dd + L
                heapq.heappush(q, (dd + L, v))
    for n in sorted(names, key=lambda n: dist.get(n, 1e18)):
        print("%7.0f m  node %d at (%.0f, %.0f): %s" % (dist.get(n, -1), n, pts[n][0], pts[n][1], ", ".join(sorted(names[n]))))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) >= 4 and sys.argv[1] == "--list":
        list_junctions(sys.argv[2], sys.argv[3])
        sys.exit(0)
    by_city = {}
    for wid, spec in WALKS.items():
        walk, total, nx = build(wid, spec)
        by_city.setdefault(spec["city"], {})[wid] = walk
        print("%-22s %5.0f m, %4.0f s, %d crossings, from (%.0f, %.0f)" % (wid, total, walk["points"][-1][0], nx,
              walk["points"][0][1], walk["points"][0][2]))
    for city, walks in by_city.items():
        write(city, walks)
