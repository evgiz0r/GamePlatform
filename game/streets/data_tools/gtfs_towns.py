#!/usr/bin/env python3
"""Buses (and trains, light rail) on their real lines, for each level's box, from the
Ministry of Transport's national GTFS feed (gtfs.mot.gov.il/gtfsfiles/
israel-public-transportation.zip, ~140 MB; save it to tools/.cache/gtfs/ first -- it is
not committed). Writes one compact JSON per town:

  stops   [[stop_code, name, lon, lat], ...]          the stops in the box
  routes  [{id, line, operator, name, type, dir, headsign, shape}]   one per route and
          direction that stops in the box on the day; type is GTFS's (3 bus, 2 rail, 0 tram)
  shapes  {shape: [[[lon, lat], ...], ...]}           its line inside the box (plus a margin),
          as one or more runs, simplified to ~3 m
  trips   [[route index, [[stop index, minute of day], ...]], ...]   every trip that day,
          only its stops in the box; minutes can pass 1440 (after midnight)

    python3 game/streets/data_tools/gtfs_towns.py tools/.cache/gtfs/israel-public-transportation.zip \
        game/streets/cities/data 2026-11-24
"""
import csv, io, json, math, os, sys, zipfile
from collections import defaultdict
from datetime import date

BOXES = {   # (S, W, N, E), the city files' boxes
    "givatayim": (32.0561, 34.7952, 32.0842, 34.8234),
    "ashdod": (31.7507, 34.6061, 31.8752, 34.7130),
}
MARGIN = 0.003   # degrees (~300 m) of a line's shape kept past the box


def rows(z, name):
    with z.open(name) as f:
        yield from csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))


def inbox(box, lat, lon, m=0.0):
    return box[0] - m <= lat <= box[2] + m and box[1] - m <= lon <= box[3] + m


def simplify(pts, eps):
    """Douglas-Peucker on [lon, lat] with eps in metres."""
    if len(pts) < 3:
        return pts
    kx, ky = 111320 * math.cos(math.radians(pts[0][1])), 110574
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    st = [(0, len(pts) - 1)]
    while st:
        a, b = st.pop()
        ax, ay, bx, by = pts[a][0] * kx, pts[a][1] * ky, pts[b][0] * kx, pts[b][1] * ky
        L = math.hypot(bx - ax, by - ay)
        md, mi = -1.0, -1
        for i in range(a + 1, b):
            px, py = pts[i][0] * kx, pts[i][1] * ky
            d = math.hypot(px - ax, py - ay) if L < 1e-9 else abs((by - ay) * (px - ax) - (bx - ax) * (py - ay)) / L
            if d > md:
                md, mi = d, i
        if md > eps:
            keep[mi] = True
            st += [(a, mi), (mi, b)]
    return [p for p, k in zip(pts, keep) if k]


def main(zpath, outdir, day):
    z = zipfile.ZipFile(zpath)
    d = date.fromisoformat(day)
    ds, wd = d.strftime("%Y%m%d"), ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"][d.weekday()]
    services = {r["service_id"] for r in rows(z, "calendar.txt")
                if r[wd] == "1" and r["start_date"] <= ds <= r["end_date"]}
    agency = {r["agency_id"]: r["agency_name"] for r in rows(z, "agency.txt")}
    stops = {}
    for r in rows(z, "stops.txt"):
        lat, lon = float(r["stop_lat"]), float(r["stop_lon"])
        towns = [t for t, b in BOXES.items() if inbox(b, lat, lon)]
        if towns:
            stops[r["stop_id"]] = (r["stop_code"], r["stop_name"], round(lon, 6), round(lat, 6), towns)
    trips = {}
    for r in rows(z, "trips.txt"):
        if r["service_id"] in services:
            trips[r["trip_id"]] = (r["route_id"], r["direction_id"], r["trip_headsign"], r["shape_id"])
    print(f"{day} ({wd}): {len(services)} services, {len(trips)} trips; stops in boxes: "
          f"{sum(1 for s in stops.values())}", file=sys.stderr)
    # stop_times: the big one, streamed
    hits = defaultdict(list)   # trip -> [(seq, stop, minute)]
    for r in rows(z, "stop_times.txt"):
        if r["stop_id"] in stops and r["trip_id"] in trips:
            h, m, _ = r["departure_time"].split(":")
            hits[r["trip_id"]].append((int(r["stop_sequence"]), r["stop_id"], int(h) * 60 + int(m)))
    routes_all = {r["route_id"]: r for r in rows(z, "routes.txt")}
    out = {t: {"stops": [], "routes": [], "shapes": {}, "trips": []} for t in BOXES}
    sidx = {t: {} for t in BOXES}
    ridx = {t: {} for t in BOXES}
    want_shapes = defaultdict(set)
    for tid, st in hits.items():
        rid, dr, head, shp = trips[tid]
        st.sort()
        for town in BOXES:
            mine = [s for s in st if town in stops[s[1]][4]]
            if not mine:
                continue
            o = out[town]
            key = (rid, dr, shp)
            if key not in ridx[town]:
                rt = routes_all.get(rid, {})
                ridx[town][key] = len(o["routes"])
                o["routes"].append({"id": rid, "line": rt.get("route_short_name"),
                                    "operator": agency.get(rt.get("agency_id"), rt.get("agency_id")),
                                    "name": rt.get("route_long_name"), "type": int(rt.get("route_type") or 3),
                                    "dir": int(dr or 0), "headsign": head, "shape": shp})
                want_shapes[shp].add(town)
            seq = []
            for _, sid, minute in mine:
                if sid not in sidx[town]:
                    sidx[town][sid] = len(o["stops"])
                    c, n, lon, lat, _ = stops[sid]
                    o["stops"].append([c, n, lon, lat])
                seq.append([sidx[town][sid], minute])
            o["trips"].append([ridx[town][key], seq])
    pts = defaultdict(list)
    for r in rows(z, "shapes.txt"):
        if r["shape_id"] in want_shapes:
            pts[r["shape_id"]].append((int(r["shape_pt_sequence"]), float(r["shape_pt_lon"]), float(r["shape_pt_lat"])))
    for shp, towns in want_shapes.items():
        line = [(lon, lat) for _, lon, lat in sorted(pts.get(shp, []))]
        for town in towns:
            runs, cur = [], []
            for lon, lat in line:
                if inbox(BOXES[town], lat, lon, MARGIN):
                    cur.append([lon, lat])
                elif cur:
                    runs.append(cur)
                    cur = []
            if cur:
                runs.append(cur)
            out[town]["shapes"][shp] = [[[round(x, 6), round(y, 6)] for x, y in simplify(r, 3.0)] for r in runs if len(r) > 1]
    for town, o in out.items():
        o["trips"].sort(key=lambda t: (t[0], t[1][0][1]))
        res = {"source": "Israel Ministry of Transport GTFS feed (gtfs.mot.gov.il, israel-public-transportation.zip), "
                         f"the trips of {day} ({wd}) that stop in this box",
               "credit": "public transport: Israel Ministry of Transport",
               "day": day, "box": BOXES[town],
               "counts": {"stops": len(o["stops"]), "routes": len(o["routes"]), "lines": len({r["line"] + "/" + r["operator"] for r in o["routes"]}),
                          "trips": len(o["trips"]), "shapes": len(o["shapes"])}}
        res.update(o)
        path = os.path.join(outdir, f"transit_{town}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False, separators=(",", ":"))
        print(town, res["counts"], f"{os.path.getsize(path) / 1e6:.2f} MB", file=sys.stderr)


if __name__ == "__main__":
    main(*sys.argv[1:4])
