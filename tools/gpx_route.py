#!/usr/bin/env python3
"""A GPS track (GPX) laid on a baked city: where it went, how fast, where it stopped, and
the same as a timed route a game can replay beside the film taken with it.

    python3 tools/gpx_route.py report TRACK.gpx CITY.json
    python3 tools/gpx_route.py route  TRACK.gpx CITY.json --video FILM.mp4 \
            --from "Street A" "Street B" --to "Street C" "Street D" > route.json

report   the streets in order with their length, time and speed (mean, top, and the
         speed held most of the way, the 85th percentile), speed by road kind, every stop
         (how long, and the junction it was at, with its lights if it has them), the
         hardest acceleration and braking. For a drive this is what to tune AI drivers
         against; for a walk, the walking speed and the waits at crossings.
route    {"points": [[seconds, x, z], ...]} on the city's ground (metres, +x east, +z
         south), seconds from the film's start when --video (or --offset, the film's start
         in seconds after the track's) is given. A stop is two points at one spot. --from
         / --to cut it at the junction of two named streets (Hebrew or English name, a
         part of it is enough): the first time the track comes within 15 m of the one, the
         last time near the other. --every N keeps a point every N seconds (default 1.5)
         plus every turn.

The track comes off a phone logger with a point a second (Geo Tracker's extended data adds
speed and accuracy per point; they are used when there). Its projection is the bake's own
(tools/osm_city.py), so the points land on the city file as the game draws it. Points
worse than --max-acc metres (default 15) are dropped.

PRIVACY: a filmed walk or drive often starts or ends at someone's door. Keep the GPX, the
film and an untrimmed route out of the repo; only a route cut at public corners the user
named belongs in a game. Stdlib only.
"""
import argparse
import datetime as dt
import json
import math
import subprocess
import sys
from xml.etree import ElementTree as ET

GPX = "{http://www.topografix.com/GPX/1/1}"


class Proj:
    """tools/osm_city.py's flat projection around the city's origin."""

    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        p = math.radians(lat0)
        self.my = 111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p)
        self.mx = 111412.84 * math.cos(p) - 93.5 * math.cos(3 * p)

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.mx, -(lat - self.lat0) * self.my)


def load_track(path, proj, max_acc):
    pts = []
    for t in ET.parse(path).getroot().iter(GPX + "trkpt"):
        x, z = proj(float(t.get("lat")), float(t.get("lon")))
        when = dt.datetime.fromisoformat(t.find(GPX + "time").text.replace("Z", "+00:00"))
        meta = {}
        for e in t.iter():
            if e.tag.endswith("}meta"):
                meta = e.attrib
        acc = float(meta.get("a", 0) or 0)
        if acc and acc > max_acc:
            continue
        pts.append({"when": when, "x": x, "z": z, "s": float(meta["s"]) if "s" in meta else None, "acc": acc})
    if len(pts) < 2:
        sys.exit("fewer than two usable points in the track")
    t0 = pts[0]["when"]
    for p in pts:
        p["t"] = (p["when"] - t0).total_seconds()
    for a, b in zip(pts, pts[1:]):   # speed from the positions where the logger gave none
        if b["s"] is None:
            b["s"] = math.hypot(b["x"] - a["x"], b["z"] - a["z"]) / max(b["t"] - a["t"], 0.5)
    pts[0]["s"] = pts[0]["s"] or 0.0
    return pts


class City:
    def __init__(self, path):
        d = json.load(open(path))
        self.data = d
        k = 1.0 / d.get("scale", 10)
        n = d["nodes"]
        self.nodes = [(n[i] * k, n[i + 1] * k) for i in range(0, len(n), 2)]
        self.roads = d["roads"]
        self.signals = set(d.get("signals", []))
        self.segs = []
        self.node_names = {}   # node -> one name per street through it (for saying where)
        self.node_all = {}     # node -> every name of them, both scripts (for --from / --to)
        for ri, r in enumerate(self.roads):
            nm = r.get("name_en") or r.get("name") or ""
            for i, j in zip(r["n"], r["n"][1:]):
                self.segs.append((self.nodes[i], self.nodes[j], ri))
            for i in r["n"]:
                self.node_names.setdefault(i, set())
                self.node_all.setdefault(i, set()).update(x for x in (r.get("name"), r.get("name_en")) if x)
                if nm:
                    self.node_names[i].add(nm)
        self.grid = {}
        for si, (a, b, ri) in enumerate(self.segs):
            for cx in range(int(min(a[0], b[0]) // 40) - 1, int(max(a[0], b[0]) // 40) + 2):
                for cz in range(int(min(a[1], b[1]) // 40) - 1, int(max(a[1], b[1]) // 40) + 2):
                    self.grid.setdefault((cx, cz), []).append(si)

    def name(self, ri):
        r = self.roads[ri]
        return r.get("name_en") or r.get("name") or "(%s)" % r["k"]

    def nearest(self, x, z, named=True):
        best = (1e9, None)
        for si in self.grid.get((int(x // 40), int(z // 40)), []):
            (ax, az), (bx, bz), ri = self.segs[si]
            if named and not (self.roads[ri].get("name") or self.roads[ri].get("name_en")):
                continue
            dx, dz = bx - ax, bz - az
            L = dx * dx + dz * dz or 1e-9
            u = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / L))
            d = math.hypot(x - ax - u * dx, z - az - u * dz)
            if d < best[0]:
                best = (d, ri)
        if best[1] is None and named:
            return self.nearest(x, z, False)
        return best

    def junction_near(self, x, z, within=40.0):
        """the nearest node where two or more named streets meet: (distance, names, lights)"""
        best = (1e9, None)
        for i, names in self.node_names.items():
            if len(names) < 2:
                continue
            nx, nz = self.nodes[i]
            d = math.hypot(nx - x, nz - z)
            if d < best[0]:
                best = (d, i)
        if best[1] is None or best[0] > within:
            return None
        i = best[1]
        return best[0], sorted(self.node_names[i]), i in self.signals

    def corner(self, a, b):
        """the nodes where streets matching a and b meet (a part of either name will do)"""
        def match(names, q):
            return any(q.lower() in nm.lower() for nm in names)
        out = [self.nodes[i] for i, ns in self.node_all.items() if match(ns, a) and match(ns, b)]
        if not out:
            sys.exit("no junction of %r and %r in the city file" % (a, b))
        return out

def stops_of(pts, slow=0.5, min_len=2.5):
    """[(t_start, t_end, x, z)] where it stood: slow points, or the logger's silence (it saves
    nothing until it has moved its minimum distance)"""
    out = []
    i = 0
    while i < len(pts) - 1:
        a, b = pts[i], pts[i + 1]
        if b["t"] - a["t"] >= min_len:
            out.append([a["t"], b["t"], a["x"], a["z"]])
            i += 1
            continue
        if a["s"] < slow:
            j = i
            while j + 1 < len(pts) and pts[j + 1]["s"] < slow and pts[j + 1]["t"] - pts[j]["t"] < min_len:
                j += 1
            if pts[j]["t"] - a["t"] >= min_len:
                out.append([a["t"], pts[j]["t"], a["x"], a["z"]])
            i = j + 1
            continue
        i += 1
    merged = []
    for s in out:
        if merged and s[0] - merged[-1][1] < 1.5:
            merged[-1][1] = max(merged[-1][1], s[1])
        else:
            merged.append(s)
    return merged


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * q))] if xs else 0.0


def report(pts, city):
    kmh = 3.6
    dur = pts[-1]["t"] - pts[0]["t"]
    dist = sum(math.hypot(b["x"] - a["x"], b["z"] - a["z"]) for a, b in zip(pts, pts[1:]))
    print("track: %d points, %.0f s, %.0f m, %.1f km/h on average" % (len(pts), dur, dist, dist / max(dur, 1) * kmh))
    accs = [p["acc"] for p in pts if p["acc"]]
    if accs:
        print("accuracy: median %.1f m, worst %.1f m" % (pct(accs, 0.5), max(accs)))
    # streets in order
    runs = []
    for a, b in zip(pts, pts[1:]):
        d, ri = city.nearest(a["x"], a["z"])
        nm = city.name(ri) if ri is not None else "?"
        kind = city.roads[ri]["k"] if ri is not None else "?"
        seg = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        if runs and runs[-1]["name"] == nm:
            r = runs[-1]
        else:
            r = {"name": nm, "kind": kind, "t0": a["t"], "dist": 0.0, "time": 0.0, "speeds": []}
            runs.append(r)
        r["dist"] += seg
        r["time"] += b["t"] - a["t"]
        r["speeds"].append(b["s"])
    print("\nstreets in order:")
    print("  %6s  %-28s %-12s %6s %6s %7s %7s %7s" % ("from s", "street", "kind", "m", "s", "mean", "p85", "top"))
    for r in runs:
        if r["dist"] < 5:
            continue
        print("  %6.0f  %-28s %-12s %6.0f %6.0f %7.1f %7.1f %7.1f" % (r["t0"], r["name"][:28], r["kind"][:12], r["dist"], r["time"],
              r["dist"] / max(r["time"], 0.1) * kmh, pct(r["speeds"], 0.85) * kmh, max(r["speeds"]) * kmh))
    print("  (km/h; p85: the speed it was at or under 85% of the time)")
    by_kind = {}
    for r in runs:
        k = by_kind.setdefault(r["kind"], {"dist": 0.0, "time": 0.0, "speeds": []})
        k["dist"] += r["dist"]
        k["time"] += r["time"]
        k["speeds"] += r["speeds"]
    print("\nby road kind:")
    for k, v in sorted(by_kind.items(), key=lambda kv: -kv[1]["dist"]):
        moving = [s for s in v["speeds"] if s > 1.0]
        print("  %-14s %6.0f m  mean %5.1f km/h, moving p50 %5.1f p85 %5.1f" % (k, v["dist"], v["dist"] / max(v["time"], 0.1) * kmh,
              pct(moving, 0.5) * kmh, pct(moving, 0.85) * kmh))
    st = stops_of(pts)
    print("\nstops (%d, %.0f s in all):" % (len(st), sum(b - a for a, b, _, _ in st)))
    for a, b, x, z in st:
        j = city.junction_near(x, z)
        where = "%.0f m from %s%s" % (j[0], " / ".join(j[1]), " (lights)" if j[2] else "") if j else "not at a junction"
        print("  at %5.0f s for %4.0f s, %s" % (a, b - a, where))
    # acceleration from the speed, over 2 s
    acc = []
    for i in range(len(pts)):
        j = i
        while j + 1 < len(pts) and pts[j + 1]["t"] - pts[i]["t"] <= 2.0:
            j += 1
        if j > i and pts[j]["t"] - pts[i]["t"] >= 1.0:
            acc.append(((pts[j]["s"] - pts[i]["s"]) / (pts[j]["t"] - pts[i]["t"]), pts[i]["t"]))
    if acc:
        up = max(acc)
        down = min(acc)
        print("\nhardest: speeding up %.1f m/s2 at %.0f s, braking %.1f m/s2 at %.0f s" % (up[0], up[1], -down[0], down[1]))


def video_offset(video, track_start):
    """the film's start in seconds after the track's: a phone writes the mp4's creation_time
    at the end of the recording (UTC), so start = creation_time - duration"""
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:format_tags=creation_time",
                          "-of", "json", video], capture_output=True, text=True, check=True).stdout
    f = json.loads(out)["format"]
    end = dt.datetime.fromisoformat(f["tags"]["creation_time"].replace("Z", "+00:00"))
    start = end - dt.timedelta(seconds=float(f["duration"]))
    return (start - track_start).total_seconds()


def route(pts, city, args):
    off = args.offset
    if args.video:
        off = video_offset(args.video, pts[0]["when"])
        print("film starts %.1f s into the track" % off, file=sys.stderr)
    i0, i1 = 0, len(pts) - 1
    if args.frm:
        cs = city.corner(*args.frm)
        i0 = next((i for i, p in enumerate(pts) if min(math.hypot(p["x"] - c[0], p["z"] - c[1]) for c in cs) < 15.0), None)
        if i0 is None:
            sys.exit("the track never comes within 15 m of %s / %s" % tuple(args.frm))
    if args.to:
        cs = city.corner(*args.to)
        near = [i for i, p in enumerate(pts) if min(math.hypot(p["x"] - c[0], p["z"] - c[1]) for c in cs) < 15.0]
        if not near:
            sys.exit("the track never comes within 15 m of %s / %s" % tuple(args.to))
        i1 = near[-1]
    if i1 <= i0:
        sys.exit("the end comes before the start")
    sel = pts[i0:i1 + 1]
    keep = [sel[0]]
    for k in range(1, len(sel) - 1):
        a, p, b = keep[-1], sel[k], sel[k + 1]
        turn = 0.0
        v1 = (p["x"] - a["x"], p["z"] - a["z"])
        v2 = (b["x"] - p["x"], b["z"] - p["z"])
        if math.hypot(*v1) > 0.5 and math.hypot(*v2) > 0.5:
            turn = abs(math.degrees(math.atan2(v1[0] * v2[1] - v1[1] * v2[0], v1[0] * v2[0] + v1[1] * v2[1])))
        if p["t"] - a["t"] >= args.every or turn > 25 or b["t"] - p["t"] >= 2.5:
            keep.append(p)
    keep.append(sel[-1])
    out = []
    for p in keep:
        t = p["t"] - (off or 0.0)
        if out and math.hypot(p["x"] - out[-1][1], p["z"] - out[-1][2]) < 0.3:
            out.append([round(t, 2), out[-1][1], out[-1][2]])   # stood still: wait there
        else:
            out.append([round(t, 2), round(p["x"], 2), round(p["z"], 2)])
    json.dump({"points": out}, sys.stdout)
    print(file=sys.stdout)
    print("%d points, %.0f s, from %.0f s to %.0f s of the %s" % (len(out), out[-1][0] - out[0][0], out[0][0], out[-1][0],
          "film" if off is not None else "track"), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("what", choices=["report", "route"])
    ap.add_argument("gpx")
    ap.add_argument("city")
    ap.add_argument("--max-acc", type=float, default=15.0)
    ap.add_argument("--video")
    ap.add_argument("--offset", type=float)
    ap.add_argument("--from", dest="frm", nargs=2, metavar=("STREET", "STREET"))
    ap.add_argument("--to", nargs=2, metavar=("STREET", "STREET"))
    ap.add_argument("--every", type=float, default=1.5)
    args = ap.parse_args()
    city = City(args.city)
    pts = load_track(args.gpx, Proj(*city.data["origin"]), args.max_acc)
    if args.what == "report":
        report(pts, city)
    else:
        route(pts, city, args)


if __name__ == "__main__":
    main()
