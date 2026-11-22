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
        # down the boulevard's middle, over Allenby: the carriageways' inner side ran along its
        # sand strip, not the walk
        "path": [[-1795.0, 1298.4], [-1720.0, 1275.7], [-1670.0, 1259.5], [-1612.0, 1237.2]],   # (the midline between its two carriageways, 20 m apart: OSM's footway there lay inside the game's asphalt past Allenby)
    },
    "ashdod_halutzim": {
        "city": "ashdod", "name": "Ashdod: HeHalutzim to Herzl",
        "legs": [["החלוצים", "העצמאות", "שדרות הרצל"]], "side": "right",
    },
    "bedford_shore": {
        "city": "bedford", "name": "Bedford: Shore Drive by the water",
        "legs": [["Shore Drive", "Bedford Harbourwalk", "Shipyard Road"]], "side": "left",
    },
    "delft_oude_delft": {
        "city": "delft", "name": "Delft: along the Oude Delft canal",
        # along the canal's quay, not the house side (its fronts stand at a narrow pavement's
        # back): Oude Delft is a one-way street each side of the canal, so the quay is a
        # carriageway's inner side, as a boulevard's middle is
        "legs": [["Oude Delft", "Peperstraat", "Breestraat"]], "promenade": True, "pave": 1.4,
    },
    # down Nahalat Binyamin's pedestrian street at night: its bars and cafes lit, tables out,
    # people standing about and passing (the scene)
    "tel_aviv_night_out": {
        "city": "tel_aviv", "name": "Tel Aviv: a night out on Nahalat Binyamin", "time": "night",
        "ways": {"kinds": ["pedestrian"], "name": "נחלת בנימין", "via": [[-1918.0, 554.0], [-1937.0, 900.0]]},
        "scene": {"groups": [18, 2.0, 3.2], "passers": 26, "lights": 22.0},
    },
    # through the park by Sarona along its own footpaths
    "tel_aviv_park": {
        "city": "tel_aviv", "name": "Tel Aviv: through the park",
        "ways": {"kinds": ["footway", "path", "pedestrian"], "via": [[-520.0, 160.0], [-402.0, 224.0], [-310.0, 290.0]]},
        "scene": {"groups": [6, 3.0, 7.0], "passers": 8},
        "dress": [["bin", 60], ["bollards", 25], ["globe_lamp", 15]],
    },
    # along the beach, on the sand above the wet line: the town's beach people walk, jog and
    # wade there already (crowds.gd); and a few of the walk's own
    "tel_aviv_beach": {
        "city": "tel_aviv", "name": "Tel Aviv: along the beach",
        # (8 m inland of the water's edge, read off the sand and sea areas every 100 m: in the
        # middle of the sand the sea was out of sight)
        "path": [[-2551.0, 150.0], [-2578.0, 250.0], [-2600.0, 350.0], [-2629.0, 450.0], [-2632.0, 550.0], [-2690.0, 640.0], [-2718.0, 720.0]],
        "scene": {"groups": [5, 3.0, 8.0], "passers": 6, "look": [65, 28.0, 5.0]},   # (the sea on the right)
        "dress": [],
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
    # a street mapped as two carriageways (one-way ways both ways): each one's pavement is its
    # traffic's right; a plain one-way street (a canal street) has pavements on both sides
    dirs = {int(r.get("o", 0)) for r in d["roads"] if r.get("name") == street and r.get("k") in WALKABLE}
    divided = 1 in dirs and len([r for r in d["roads"] if r.get("name") == street and int(r.get("o", 0)) == 1]) >= 2         and two_ways(d, pts, street)
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
            if not divided:
                o = 0
            width[(u, v)] = (w, "right" if o == 1 else "left" if o == -1 else None)
            width[(v, u)] = (w, "left" if o == 1 else "right" if o == -1 else None)
    return g, width


def two_ways(d, pts, street):
    """the street's one-way ways run both ways somewhere side by side (within 40 m, opposite
    headings): a divided road, not a one-way street"""
    segs = []
    for r in d["roads"]:
        if r.get("name") == street and int(r.get("o", 0)) == 1:
            for u, v in zip(r["n"], r["n"][1:]):
                segs.append((pts[u], pts[v]))
    for a, b in segs[:400]:
        ha = math.atan2(b[1] - a[1], b[0] - a[0])
        for c, e in segs[:400]:
            if math.dist(a, c) < 40 and math.dist(a, c) > 4:
                hc = math.atan2(e[1] - c[1], e[0] - c[0])
                if abs(abs((ha - hc + math.pi) % (2 * math.pi) - math.pi) - math.pi) < 0.5:
                    return True
    return False


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
    if "path" in spec:   # a footway's own points: walked down its middle
        walk = [tuple(p) for p in spec["path"]]
        return timed(wid, spec, d, pts, walk, 1.0, None)
    if "ways" in spec:   # along ways of these kinds through these points, down their middle
        walk = route_ways(d, pts, spec["ways"])
        return timed(wid, spec, d, pts, walk, 1.0, None)
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
    pave = float(spec.get("pave", PAVE))
    walk = offset_line(line, ws, spec.get("side", "right"), pave, bool(spec.get("promenade", False)))
    end_w = max([float(r.get("w", 6.0)) for r in d["roads"] if r.get("k") in CARS and start in r["n"]] or [6.0])
    # the kerb side of each stretch: where its street things stand (dress)
    kerb = offset_line(line, ws, spec.get("side", "right"), 0.6, bool(spec.get("promenade", False)))
    return timed(wid, spec, d, pts, walk, end_w / 2 + 2.5, kerb)


def timed(wid, spec, d, pts, walk, short, kerb):
    hits, cum = crossings(d, pts, walk)
    # (it stops on the pavement short of the street its last leg ends at: half the widest road
    # there and 2.5 m more -- Ashdod's ran on into Herzl's carriageway, past a corner's six poles)
    total = cum[-1] - short
    hits = [h for h in hits if h[0] < total]
    # the timed points: every ~4 m at the pace, a wait at each kerb, the crossing quicker
    out = []
    looks = []
    zebras = []
    along = []   # how far along the line each point is (the scene's people meet the walker by it)
    t = 0.0
    s = 2.5 if kerb else 0.0   # (a leg's walk starts 2.5 m in from its first junction: a bridge's parapet stood there in Delft)
    k = 0
    seed = sum(ord(c) for c in wid)
    for h in hits + [[total + 1e9, total + 1e9, 0]]:
        # (the kerbs a little further out than half the road: a junction's corners round the
        # asphalt out, and a walk waited on it -- the scan's road check)
        kerb_a = h[0] - (h[2] / 2 + 1.5)
        kerb_b = h[1] + (h[2] / 2 + 1.5)
        stop = min(kerb_a, total)
        while s < stop - 0.01:
            out.append([round(t, 2), *[round(v, 2) for v in at(walk, cum, s)]])
            along.append(s)
            step = min(4.0, stop - s)
            pace = PACE * (1.0 + 0.06 * math.sin(seed + k * 1.7))
            s += step
            t += step / pace
            k += 1
        if h[0] > total:
            out.append([round(t, 2), *[round(v, 2) for v in at(walk, cum, total)]])
            along.append(total)
            break
        if kerb_a < 0:   # (a crossing right at the start: start on its far side)
            s = kerb_b
            continue
        p_a = at(walk, cum, kerb_a)
        p_b = at(walk, cum, kerb_b)
        wait = 1.8 + 1.4 * ((seed * 7 + k * 13) % 10) / 10.0
        out.append([round(t, 2), round(p_a[0], 2), round(p_a[1], 2)])
        along.append(kerb_a)
        looks.append([round(t + 0.1, 2), round(t + wait * 0.45, 2), -55])
        looks.append([round(t + wait * 0.5, 2), round(t + wait - 0.1, 2), 50])
        t0 = t
        t += wait
        out.append([round(t, 2), round(p_a[0], 2), round(p_a[1], 2)])
        along.append(kerb_a)
        t += (kerb_b - kerb_a) / CROSS_PACE
        out.append([round(t, 2), round(p_b[0], 2), round(p_b[1], 2)])
        along.append(kerb_b)
        zebras.append([round(t0, 2), round(t, 2), [round(p_a[0], 2), round(p_a[1], 2)], [round(p_b[0], 2), round(p_b[1], 2)]])
        s = kerb_b + 0.01
    props = dress(wid, spec, walk, cum, total, hits, kerb)
    people, shops = scene(wid, spec, d, walk, cum, total, out, along)
    # `look`: [degrees, every, for] -- the head turned that way (+ right) now and then (the sea)
    lk = spec.get("scene", {}).get("look")
    if lk:
        tt = float(lk[1]) * 0.5
        while tt + float(lk[2]) < out[-1][0] - 2.0:
            if not any(z[0] - 1.0 < tt < z[1] + 1.0 for z in zebras):
                looks.append([round(tt, 2), round(tt + float(lk[2]), 2), float(lk[0])])
            tt += float(lk[1])
    w = {"name": spec["name"], "src": "make_walks", "dodge": True, "points": out, "looks": looks, "zebras": zebras}
    if people:
        w["people"] = people
    if shops:
        w["shops"] = shops
    return w, total, len(hits), props


# Street things along a walk (the user, 22 Nov: "add more items near the walks"): every 9-16 m
# one, on the kerb side 0.6 m in from the road's edge (the street trees stand at 1.3, the walk at
# 2.05), none within 6 m of a crossing or the walk's ends; on a path (no kerb), 1.6 m to either
# side by turns. What kinds by the town's look: an Israeli street's bins, scooters, motorbikes,
# cabinets, hydrants, yellow parking boards and pairs of bollards; a Nova Scotia street's
# hydrants, bins, cabinets, bollards. The game steps the walk round them (`dodge`).
DRESS = {
    "med": [("bin", 25), ("scooter", 18), ("motorbike", 14), ("cabinet", 10), ("hydrant", 8), ("sign_board", 7), ("bollards", 10)],
    "north": [("hydrant", 30), ("bin", 30), ("cabinet", 20), ("bollards", 15)],
    # a Dutch town's: rows of short bollards (no cars on the canal's edge), bins, scooters,
    # cabinets; no fire hydrants above the ground
    "dutch": [("bollards", 40), ("bin", 25), ("scooter", 20), ("cabinet", 15)],
}
GAP = {"med": (9.0, 16.0), "north": (22.0, 38.0), "dutch": (10.0, 18.0)}   # (a suburb's pavement is emptier)
LOOK = {"tel_aviv": "med", "ashdod": "med", "dimyon": "med", "givatayim": "med", "bedford": "north", "delft": "dutch"}


def dress(wid, spec, walk, cum, total, hits, kerb):
    import random
    rng = random.Random(sum(ord(c) * (i + 1) for i, c in enumerate(wid)))
    kinds = spec.get("dress", DRESS[LOOK.get(spec["city"], "med")])   # (a walk's own: [] for none -- the sand)
    if not kinds:
        return []
    bag = [k for k, n in kinds for _ in range(n)]
    kc = None
    if kerb:
        kc = [0.0]
        for a, b in zip(kerb, kerb[1:]):
            kc.append(kc[-1] + math.dist(a, b))
    props = []
    s = 5.0 + rng.uniform(0, 6)
    side = 1
    while s < total - 5.0:
        if any(h[0] - 6.0 < s < h[1] + 6.0 for h in hits):
            s += 4.0
            continue
        p = at(walk, cum, s)
        q = at(walk, cum, min(s + 0.5, cum[-1]))
        f = ((q[0] - p[0]), (q[1] - p[1]))
        L = math.hypot(*f) or 1.0
        f = (f[0] / L, f[1] / L)
        if kc:
            k = at(kerb, kc, s * kc[-1] / cum[-1])
            to_road = (k[0] - p[0], k[1] - p[1])
            n = math.hypot(*to_road) or 1.0
            to_road = (to_road[0] / n, to_road[1] / n)
        else:
            to_road = (-f[1] * side, f[0] * side)
            k = (p[0] + to_road[0] * 1.6, p[1] + to_road[1] * 1.6)
            side = -side
        kind = rng.choice(bag)
        here = [round(k[0], 2), round(k[1], 2)]
        along = [round(f[0], 4), round(f[1], 4)]
        if kind in ("scooter", "motorbike"):   # nose to the kerb
            props.append({"kind": kind, "at": here, "dir": [round(-to_road[0], 4), round(-to_road[1], 4)], "box": rng.random() < 0.4})
        elif kind == "bollards":
            for o in (-0.8, 0.8):
                props.append({"kind": "bollard", "at": [round(k[0] + f[0] * o, 2), round(k[1] + f[1] * o, 2)]})
        elif kind in ("cabinet", "sign_board"):
            props.append({"kind": kind, "at": here, "dir": [round(-to_road[0], 4), round(-to_road[1], 4)]})
        elif kind == "globe_lamp":
            props.append({"kind": kind, "at": here, "h": 2.7})
        else:
            props.append({"kind": kind, "at": here, "dir": along})
        s += rng.uniform(*GAP[LOOK.get(spec["city"], "med")])
    for pr in props:
        pr["src"] = "make_walks"
        pr["walk"] = wid
    return props


def route_ways(d, pts, ways):
    """the shortest way along roads of `kinds` (and `name`, if given) from each of `via` to the
    next, each point to its nearest node on them: a park's footpaths, a pedestrian street"""
    kinds = set(ways["kinds"])
    g = {}
    for r in d["roads"]:
        if r.get("k") not in kinds or ("name" in ways and r.get("name") != ways["name"]):
            continue
        for u, v in zip(r["n"], r["n"][1:]):
            L = math.dist(pts[u], pts[v])
            g.setdefault(u, []).append((v, L))
            g.setdefault(v, []).append((u, L))
    def nearest(p):
        return min(g, key=lambda n: math.dist(pts[n], p))
    line = []
    via = [nearest(tuple(p)) for p in ways["via"]]
    for a, b in zip(via, via[1:]):
        found = path(g, a, b)
        if not found:
            sys.exit("no way along %s from %s to %s" % (sorted(kinds), pts[a], pts[b]))
        nodes = found[0]
        if line:
            nodes = nodes[1:]
        line += [pts[n] for n in nodes]
    return line


# A walk's own scene (the user, 22 Nov: "you should be able to change things we want (people,
# some other object maybe). Not only getting stuck in the actual city"): on top of what the
# map has and the city's own walkers --
#   "groups": [n, near, far]  n groups of 2-4 standing talking, near..far metres to either side
#             of the line (a pedestrian street, a park's lawn, the sand -- not a pavement's width)
#   "passers": n              people walking the line the other way, timed to pass the walker,
#             a metre or so to one side
#   "look": [deg, every, for] the head turned that way now and then (the beach's sea)
#   "lights": metres          the bars, pubs, cafes and restaurants within that of the line lit
#             with string lights, their tables out (details' "shops")
# Walk "people" (streets.gd _film_begin): standing with `talk`, or walking `at` to `to` between
# two of the walk's seconds, there only then.
def scene(wid, spec, d, walk, cum, total, out, along):
    import random
    sc = spec.get("scene", {})
    if not sc:
        return [], []
    rng = random.Random(sum(ord(c) * 7 for c in wid))
    people = []

    def side_at(s_, off):
        p = at(walk, cum, s_)
        q = at(walk, cum, min(s_ + 0.5, cum[-1]))
        f = (q[0] - p[0], q[1] - p[1])
        L = math.hypot(*f) or 1.0
        n = (-f[1] / L, f[0] / L)
        return (p[0] + n[0] * off, p[1] + n[1] * off), (f[0] / L, f[1] / L)

    def time_at(s_):   # the walk's clock when it is s_ along
        for i in range(len(along) - 1):
            if along[i] <= s_ <= along[i + 1] and along[i + 1] > along[i]:
                return out[i][0] + (out[i + 1][0] - out[i][0]) * (s_ - along[i]) / (along[i + 1] - along[i])
        return out[-1][0]

    who = 0
    groups = sc.get("groups", [0, 2.5, 5.0])
    for _ in range(int(groups[0])):
        s_ = rng.uniform(8.0, total - 8.0)
        sgn = rng.choice([-1, 1])
        c, f = side_at(s_, sgn * rng.uniform(groups[1], groups[2]))
        n = rng.choice([2, 2, 3, 3, 4])
        for k in range(n):
            a = 2 * math.pi * k / n + rng.uniform(-0.3, 0.3)
            p = (c[0] + math.cos(a) * 0.65, c[1] + math.sin(a) * 0.65)
            face = (c[0] - p[0], c[1] - p[1])
            L = math.hypot(*face) or 1.0
            people.append({"at": [round(p[0], 2), round(p[1], 2)], "face": [round(face[0] / L, 3), round(face[1] / L, 3)],
                           "who": who, "talk": True, "tall": round(rng.uniform(1.58, 1.86), 2)})
            who += 1
    for _ in range(int(sc.get("passers", 0))):
        s_meet = rng.uniform(15.0, total - 5.0)
        t_meet = time_at(s_meet)
        sgn = rng.choice([-1, 1])
        lat = sgn * rng.uniform(0.9, 1.6)
        span = rng.uniform(14.0, 22.0)   # metres either side of where they pass
        pace = rng.uniform(1.15, 1.5)
        # (the walker moves on meanwhile: they meet where the two have walked toward each other)
        a, _ = side_at(min(total, s_meet + span), lat)
        b, _ = side_at(max(0.0, s_meet - span), lat)
        t0 = t_meet - span / pace
        t1 = t_meet + span / pace
        if t0 < 0.5:
            continue
        people.append({"at": [round(a[0], 2), round(a[1], 2)], "to": [round(b[0], 2), round(b[1], 2)],
                       "t": [round(t0, 2), round(t1, 2)], "who": who, "tall": round(rng.uniform(1.58, 1.86), 2)})
        who += 1
    shops = []
    reach = float(sc.get("lights", 0.0))
    if reach > 0.0:
        sc_ = float(d.get("scale", 10))
        for poi in d.get("pois", []):
            if poi[2] not in ("bar", "pub", "cafe", "restaurant", "nightclub", "fast_food", "ice_cream"):
                continue
            p = (poi[0] / sc_, poi[1] / sc_)
            dist = min(math.dist(p, at(walk, cum, x)) for x in [i * 2.0 for i in range(int(cum[-1] / 2) + 1)])
            if dist <= reach:
                shops.append({"near": [round(p[0], 1), round(p[1], 1)], "lights": True,
                              "seats": "tables" if poi[2] in ("cafe", "restaurant", "bar", "pub") else "none"})
    return people, shops


def write(city, walks, props):
    path_ = os.path.join(CITIES, "details", city + ".json")
    d = {}
    if os.path.exists(path_):
        with open(path_, encoding="utf-8") as fh:
            d = json.load(fh)
    w = {k: v for k, v in d.get("walks", {}).items() if v.get("src") != "make_walks"}
    w.update(walks)
    d["walks"] = w
    # the walks' lit bars and cafes (details' "shops"), theirs: rewritten each run
    shops = [x for x in d.get("shops", []) if x.get("src") != "make_walks"]
    for wid, wk in walks.items():
        for x in wk.pop("shops", []):
            x["src"] = "make_walks"
            shops.append(x)
    if shops:
        d["shops"] = shops
    d["props"] = [p for p in d.get("props", []) if p.get("src") != "make_walks"] + props
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
    dressed = {}
    for wid, spec in WALKS.items():
        walk, total, nx, props = build(wid, spec)
        by_city.setdefault(spec["city"], {})[wid] = walk
        dressed.setdefault(spec["city"], []).extend(props)
        print("%-22s %5.0f m, %4.0f s, %d crossings, %d things along it, from (%.0f, %.0f)" % (wid, total, walk["points"][-1][0], nx,
              len(props), walk["points"][0][1], walk["points"][0][2]))
    for city, walks in by_city.items():
        write(city, walks, dressed[city])
