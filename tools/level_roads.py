#!/usr/bin/env python3
"""Level a baked city's roads side to side, by reshaping its ground-height grid.

The ground comes from terrain tiles on a grid (`height`: a point every 8-46 m), and a road
laid on it takes the slope of the hillside it crosses: in one hilly town 28% of the roads'
length leaned more than 6% side to side, the worst over 30%, where a real street leans 2%
(its crown) and the hillside is cut and filled at its edges instead. This does that cut and
fill on the grid: each grid point near a road takes the height of the road's centre line at
the point nearest it (so a road keeps its climb along its length and is level across), fully
out to a grid cell's diagonal past the pavement (every triangle of the grid that reaches the
asphalt then has all three corners on the road's level), then blending back to the hillside
over one more cell. A point near several roads follows the nearest asphalt edge. Roads off
the ground (`y`, bridges, tunnels, embankments, cuttings) are left out: they have their own
heights.

The bakers (osm_city.py, fake_city.py) call level() before writing; run it on a city file
baked before that to level it in place (once: a second run evens out more, it is not a no-op):

    python3 tools/level_roads.py city.json [more.json ...]      (--check: measure, write nothing)
"""
import argparse
import json
import math

# the roads that are levelled: what a car drives and a street people walk down
KINDS = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
         "living_street", "service", "road", "motorway_link", "trunk_link", "primary_link",
         "secondary_link", "tertiary_link", "busway", "pedestrian"}
OFF_GROUND = ("y", "br", "tu", "em", "cu")
PAVE = 3.0       # metres beside the asphalt kept level with it: kerb and pavement


class Grid:
    def __init__(self, hg, scale):
        self.x0, self.z0, self.step = float(hg["x0"]), float(hg["z0"]), float(hg["step"])
        self.nx, self.nz = int(hg["nx"]), int(hg["nz"])
        self.h = [float(v) / scale for v in hg["h"]]   # metres above `base`
        self.scale = scale

    def at(self, x, z, h=None):
        """the ground's height at (x, z): the same two triangles a cell as the game draws"""
        h = h or self.h
        fx = min(max((x - self.x0) / self.step, 0.0), self.nx - 1.001)
        fz = min(max((z - self.z0) / self.step, 0.0), self.nz - 1.001)
        i, j = int(fx), int(fz)
        ax, az = fx - i, fz - j
        r = j * self.nx + i
        if ax + az <= 1.0:
            return h[r] + (h[r + 1] - h[r]) * ax + (h[r + self.nx] - h[r]) * az
        h11 = h[r + self.nx + 1]
        return h11 + (h[r + self.nx] - h11) * (1.0 - ax) + (h[r + 1] - h11) * (1.0 - az)


def _roads(city):
    """[(points in metres, width)] of the roads to level"""
    k = 1.0 / float(city.get("scale", 10))
    nd = city["nodes"]
    out = []
    for rd in city.get("roads", []):
        if rd.get("k") not in KINDS or any(f in rd for f in OFF_GROUND):
            continue
        pts = [(nd[2 * n] * k, nd[2 * n + 1] * k) for n in rd["n"]]
        out.append((pts, float(rd.get("w", 6.0)), list(rd["n"])))
    return out


def lean(city, grid, h=None, step=4.0):
    """the share of the roads' length leaning more than 3%, 6%, 10% side to side, and the worst"""
    total, over, worst = 0.0, [0.0, 0.0, 0.0], 0.0
    for pts, w, _ids in _roads(city):
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            L = math.hypot(bx - ax, bz - az)
            if L < 0.5:
                continue
            dx, dz = (bx - ax) / L, (bz - az) / L
            nx, nz = -dz * w * 0.5, dx * w * 0.5
            s = step * 0.5
            while s < L:
                px, pz = ax + dx * s, az + dz * s
                t = abs(grid.at(px + nx, pz + nz, h) - grid.at(px - nx, pz - nz, h)) / w
                total += step
                for i, lim in enumerate((0.03, 0.06, 0.10)):
                    if t > lim:
                        over[i] += step
                worst = max(worst, t)
                s += step
    return total, [o / max(total, 1.0) for o in over], worst


SMOOTH = 12.0     # m: how far along a road its height is evened out (a Gaussian's sigma)
JUNCTION = 2.0   # m past the widest road's half width: a junction's disc, one height at its middle


def profiles(city, grid, roads):
    """Each road's surface height along it, evened out: the ground grid comes from a surface
    model (it sees rooftops) on a grid 8-46 m a point, and a road laid on it climbed in facets
    -- its slope changing by 20-35% from one 6 m to the next in places (a crest or a dip a car
    pitches over), and a junction's arms meeting at different heights. Here every road's centre
    line is sampled every 2 m, all of them one network (a junction's node one sample that its
    arms share), and the heights are evened out over the network -- each sample moved half way
    to its neighbours' mean, again and again (about a Gaussian of SMOOTH metres): through a
    junction as along a street, so the town's roads stay one surface and every junction's arms
    meet at one height. (Evened out road by road and pinned at the junctions to the ground
    there, the pins put the bumps back: a junction every 40-80 m.) Returns per road (distance
    along it of each sample, heights, the samples' points, {sample index: node})."""
    key_of = {}    # ("n", node) -> sample id
    xs, hs, nbr = [], [], []

    def sample(p, key=None):
        if key is not None and key in key_of:
            return key_of[key]
        i = len(hs)
        xs.append(p)
        hs.append(grid.at(*p))
        nbr.append([])
        if key is not None:
            key_of[key] = i
        return i

    per_road = []
    for pts, w, ids in roads:
        ss, sid, node_at, xy = [0.0], [sample(pts[0], ("n", ids[0]))], {0: ids[0]}, [pts[0]]
        for i in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[i], pts[i + 1]
            L = math.hypot(bx - ax, bz - az)
            m = max(1, int(math.ceil(L / 2.0)))
            for q in range(1, m + 1):
                t = q / m
                p = (ax + (bx - ax) * t, az + (bz - az) * t)
                j = sample(p, ("n", ids[i + 1]) if q == m else None)
                nbr[j].append(sid[-1])
                nbr[sid[-1]].append(j)
                ss.append(ss[-1] + L / m)
                sid.append(j)
                xy.append(p)
            node_at[len(ss) - 1] = ids[i + 1]
        per_road.append((ss, sid, xy, node_at))
    # half way to the neighbours' mean, n times: a spread of about sqrt(n / 2) samples
    h = hs[:]
    n_it = int(round(2.0 * (SMOOTH / 2.0) ** 2))
    for _ in range(n_it):
        nh = h[:]
        for i, nb in enumerate(nbr):
            if nb:
                nh[i] = 0.5 * h[i] + 0.5 * sum(h[j] for j in nb) / len(nb)
        h = nh
    out = []
    for ss, sid, xy, node_at in per_road:
        out.append((ss, [h[i] for i in sid], xy, node_at))
    return out, key_of


def _along(prof, s):
    """a road's evened-out height s metres along it"""
    ss, sm = prof[0], prof[1]
    lo, hi = 0, len(ss) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if ss[mid] <= s:
            lo = mid
        else:
            hi = mid
    if ss[hi] - ss[lo] < 1e-6:
        return sm[lo]
    f = min(1.0, max(0.0, (s - ss[lo]) / (ss[hi] - ss[lo])))
    return sm[lo] + (sm[hi] - sm[lo]) * f


def kinks(city, grid, h=None, over=0.06):
    """the share of the roads' length whose slope along changes by more than `over` from the
    last 6 m to the next 6 m (a crest or a dip), sampled every 2 m"""
    total = bad = 0
    for pts, w, _ids in _roads(city):
        prof = []
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            L = math.hypot(bx - ax, bz - az)
            m = max(1, int(L / 2.0))
            for q in range(m):
                prof.append(grid.at(ax + (bx - ax) * q / m, az + (bz - az) * q / m, h))
        for i in range(3, len(prof) - 3):
            total += 1
            if abs((prof[i + 3] - prof[i]) - (prof[i] - prof[i - 3])) / 6.0 > over:
                bad += 1
    return bad / max(total, 1)


def level(city):
    """Level the roads of `city` (a baked city dict) in its height grid; returns a few numbers."""
    hg = city.get("height")
    if not hg or not hg.get("h"):
        return {}
    g = Grid(hg, float(city.get("scale", 10)))
    n = g.nx * g.nz
    best = [math.inf] * n          # each grid point's distance past the nearest asphalt edge
    target = list(g.h)
    full = g.step * 1.42           # a cell's diagonal past the pavement: every triangle on the asphalt
    fade = g.step                  # then back to the hillside over one more cell
    roads = _roads(city)
    profs, _pin = profiles(city, g, roads)
    seen = {}     # grid point -> {road: its weight} (the nearest each road comes)
    near_h = {}   # grid point -> {road: its height there}
    for (pts, w, _ids), prof in zip(roads, profs):
        hw = w * 0.5
        reach = hw + PAVE + full + fade
        s0 = 0.0
        for seg, ((ax, az), (bx, bz)) in enumerate(zip(pts, pts[1:])):
            seg_len = math.hypot(bx - ax, bz - az)
            vx, vz = bx - ax, bz - az
            L2 = vx * vx + vz * vz
            i0 = max(0, int(math.floor((min(ax, bx) - reach - g.x0) / g.step)))
            i1 = min(g.nx - 1, int(math.ceil((max(ax, bx) + reach - g.x0) / g.step)))
            j0 = max(0, int(math.floor((min(az, bz) - reach - g.z0) / g.step)))
            j1 = min(g.nz - 1, int(math.ceil((max(az, bz) + reach - g.z0) / g.step)))
            for j in range(j0, j1 + 1):
                pz = g.z0 + j * g.step
                row = j * g.nx
                for i in range(i0, i1 + 1):
                    px = g.x0 + i * g.step
                    t = 0.0 if L2 < 1e-6 else min(1.0, max(0.0, ((px - ax) * vx + (pz - az) * vz) / L2))
                    cx, cz = ax + vx * t, az + vz * t
                    e = math.hypot(px - cx, pz - cz) - hw   # past the asphalt's edge
                    if e < PAVE + full + fade:
                        # (every road near it has a say, the nearer the more: nearest-wins
                        # gave the grid points between a divided road's two halves to one half
                        # and the next to the other, 1.5 m apart on a hillside -- crests and
                        # dips along both, Givatayim's HaShalom)
                        wt = 1.0 / (max(e, 0.0) + 1.0) ** 2
                        if wt > seen.get(row + i, {}).get(id(prof), 0.0):
                            seen.setdefault(row + i, {})[id(prof)] = wt
                            near_h.setdefault(row + i, {})[id(prof)] = _along(prof, s0 + t * seg_len)
                        if e < best[row + i]:
                            best[row + i] = e
            s0 += seg_len
    for r, ws in seen.items():
        tw = sum(ws.values())
        target[r] = sum(near_h[r][q] * wq for q, wq in ws.items()) / tw
    new = list(g.h)
    moved, most = 0, 0.0
    for r in range(n):
        e = best[r]
        if e == math.inf:
            continue
        a = 1.0 if e <= PAVE + full else 1.0 - (e - PAVE - full) / fade
        a = a * a * (3.0 - 2.0 * a)   # (smoothly back to the hillside)
        new[r] = g.h[r] + (target[r] - g.h[r]) * a
        d = abs(new[r] - g.h[r])
        if d > 0.05:
            moved += 1
            most = max(most, d)
    hg["h"] = [int(round(v * g.scale)) for v in new]
    return {"points": n, "moved": moved, "most": most}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="+", help="baked city files, levelled in place")
    ap.add_argument("--check", action="store_true", help="only measure the lean before and after")
    args = ap.parse_args()
    for path in args.files:
        with open(path, encoding="utf-8") as f:
            city = json.load(f)
        if not city.get("height"):
            print("%s: no height grid, nothing to level" % path)
            continue
        g0 = Grid(city["height"], float(city.get("scale", 10)))
        before = lean(city, g0)
        k0 = kinks(city, g0)
        got = level(city)
        g1 = Grid(city["height"], float(city.get("scale", 10)))
        after = lean(city, g1)
        k1 = kinks(city, g1)
        print("%s: %.1f km of road; leaning over 3%% / 6%% / 10%% across: %.1f / %.1f / %.1f%% -> %.1f / %.1f / %.1f%%, "
              "worst %.0f%% -> %.0f%%; crests and dips (slope along changing over 6%% in 6 m) %.2f%% -> %.2f%%; "
              "%d of %d grid points moved, the most %.1f m" % (
                  path, before[0] / 1000.0, *(100 * v for v in before[1]), *(100 * v for v in after[1]),
                  100 * before[2], 100 * after[2], 100 * k0, 100 * k1, got["moved"], got["points"], got["most"]))
        if not args.check:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(city, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
