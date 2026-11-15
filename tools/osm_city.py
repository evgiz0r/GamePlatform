#!/usr/bin/env python3
"""Bake a real place from OpenStreetMap into a compact city file a game can build from.

    python3 tools/osm_city.py --place "Givatayim" --out game/<game>/cities/<city>.json
    python3 tools/osm_city.py --relation 1382494 --out ...        # exact OSM relation id
    python3 tools/osm_city.py --bbox 32.06,34.80,32.08,34.83 --name "corner" --out ...

Two steps, so the second can be re-run without the network:
  1. fetch   ask the Overpass API for the place's boundary and everything inside its
             bounding box (plus --margin metres), cache the raw answer in tools/.cache/
  2. bake    project lat/lon to metres around the centre, clean the shapes, guess what
             OSM leaves out (building heights, road widths) and write the city file
Pass --offline to skip step 1 and bake from the cache.

No network here? Anyone with a browser can do step 1: open an Overpass API link that asks
for the same things (print one with --print-query), save the JSON it answers with, and
pass it as --from-file. It is cached like a download, so --offline works afterwards.

The city file is plain JSON, every coordinate an integer in decimetres (`scale`: 10) on
the ground plane: +x is east, +z is SOUTH (so north is -z, which is "up the screen" in a
Godot top view and keeps the map from coming out mirrored). Format, version 1:

  name, source, fetched, origin [lat, lon], scale, bounds [x0, z0, x1, z1] (metres)
  boundary   [[x, z, x, z, ...], ...]   the place's outline rings (empty for --bbox)
  nodes      [x, z, x, z, ...]           road graph vertices, shared where roads meet
  roads      [{n: [node indices], k: kind, w: width m, l: lanes, o: 1/-1/0 oneway,
               name, name_en, br: 1 bridge, tu: 1 tunnel}]
  buildings  [{p: [x, z, ...] counter-clockwise ring, h: height m, b: base height m,
               g: 1 if the height is a guess, name, addr}]
  areas      [{p: ring, k: park|grass|wood|water|parking|pitch|plaza}]
  trees      [x, z, ...]
  signals    [node indices]   traffic lights that sit on the road graph
  crossings  [node indices]

Road kinds keep OSM's highway values (primary, residential, footway ...); a game decides
which are drivable. Everything here is (c) OpenStreetMap contributors, ODbL: a game that
shows it must say so somewhere visible.

Stdlib only. Network goes through HTTPS_PROXY if set (urllib reads it).
"""
import argparse
import datetime
import json
import math
import os
import re
import sys
import time
import urllib.parse
import urllib.request

# Public Overpass servers, tried in order: the main one turns some clients away (a 406 for
# a link opened in a browser, resets from some networks), the others are full mirrors.
SERVERS = ["https://overpass-api.de/api/interpreter",
           "https://overpass.private.coffee/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter"]
if os.environ.get("OVERPASS_URL"):
    SERVERS = [os.environ["OVERPASS_URL"]]
OVERPASS = SERVERS[0]
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, ".cache")
SCALE = 10  # integers in the file are decimetres

# metres of asphalt when OSM has no width tag. Israeli residential streets carry a row of
# parked cars on each side, hence wider than the lane count alone suggests.
ROAD_WIDTH = {
    "motorway": 14.0, "trunk": 13.0, "primary": 12.0, "secondary": 10.0,
    "tertiary": 9.0, "unclassified": 7.0, "residential": 8.0, "living_street": 6.0,
    "service": 4.5, "motorway_link": 6.0, "trunk_link": 6.0, "primary_link": 6.0,
    "secondary_link": 6.0, "tertiary_link": 6.0, "road": 7.0, "track": 3.0,
    "pedestrian": 6.0, "footway": 2.2, "path": 2.0, "cycleway": 2.0, "steps": 2.5,
    "corridor": 0, "proposed": 0, "construction": 0, "platform": 0, "bus_stop": 0,
    "elevator": 0, "raceway": 8.0, "busway": 7.0, "bridleway": 2.0,
}
LANE = 3.2
LEVEL_H = 3.0          # metres per storey
DEFAULT_LEVELS = {     # storeys when OSM has neither height nor building:levels
    "house": 2, "detached": 2, "semidetached_house": 2, "terrace": 2, "bungalow": 1,
    "garage": 1, "garages": 1, "shed": 1, "kiosk": 1, "hut": 1, "carport": 1,
    "roof": 1, "service": 1, "transformer_tower": 1, "toilets": 1, "cabin": 1,
    "commercial": 3, "retail": 2, "office": 5, "industrial": 2, "warehouse": 2,
    "school": 3, "kindergarten": 1, "synagogue": 2, "church": 2, "mosque": 2,
    "public": 3, "civic": 3, "hospital": 5, "university": 4, "college": 4,
    "parking": 3, "hotel": 6, "stadium": 2, "sports_hall": 2, "construction": 1,
    "ruins": 1, "greenhouse": 1, "stable": 1, "farm_auxiliary": 1,
}
AREA_KINDS = [
    ("leisure", {"park": "park", "garden": "park", "playground": "park", "dog_park": "park",
                 "pitch": "pitch", "sports_centre": "pitch", "track": "pitch"}),
    ("landuse", {"grass": "grass", "recreation_ground": "park", "village_green": "grass",
                 "meadow": "grass", "cemetery": "grass", "forest": "wood", "orchard": "wood",
                 "flowerbed": "grass", "allotments": "grass"}),
    ("natural", {"wood": "wood", "scrub": "wood", "grassland": "grass", "water": "water"}),
    ("amenity", {"parking": "parking"}),
    ("place", {"square": "plaza"}),
    ("highway", {"pedestrian": "plaza"}),   # a closed pedestrian way tagged area=yes
]


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---- fetch ---------------------------------------------------------------------------

def overpass(query, tries=2):
    body = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(tries):
        for url in SERVERS:
            try:
                req = urllib.request.Request(url, data=body, headers={
                    "User-Agent": "osm-city-bake/1 (a game kit's map baker)",
                    "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=300) as r:
                    return json.loads(r.read().decode("utf-8"))
            except Exception as e:  # rate limits and timeouts are routine on public servers
                log(f"  {urllib.parse.urlparse(url).netloc}: {e}")
        if attempt + 1 < tries:
            log("  every server refused; trying again in 20s")
            time.sleep(20)
    sys.exit("overpass: giving up (are the servers reachable from this network?)")


def name_regex(place):
    """'Givatayim' should also find "Giv'atayim": punctuation between Latin letters is
    optional. Other scripts (Hebrew, Arabic...) are matched as written."""
    letters = [c for c in place if c.isalnum() or c == " "]
    out = ""
    for i, c in enumerate(letters):
        if i and c.isascii() and letters[i - 1].isascii():
            out += "['`.-]?"
        out += re.escape(c)
    return "^" + out + "$"


def find_boundary(args):
    if args.relation:
        sel = f"rel({args.relation});"
    else:
        rx = name_regex(args.place).replace('"', '\\"')
        sel = (f'rel["boundary"="administrative"][~"^name(:[a-z]+)?$"~"{rx}",i];')
    data = overpass(f"[out:json][timeout:90];{sel}out geom;")
    rels = [e for e in data["elements"] if e["type"] == "relation"]
    if not rels:
        sys.exit(f"no administrative boundary named '{args.place}'. Try --relation <id> "
                 "(look the place up on openstreetmap.org) or --bbox.")
    if len(rels) > 1:
        log("several matches, taking the most local one (highest admin_level):")
        for r in rels:
            t = r.get("tags", {})
            log(f"  relation {r['id']}  admin_level={t.get('admin_level')}  {t.get('name')}"
                f" / {t.get('name:en')}")
        rels.sort(key=lambda r: -int(r.get("tags", {}).get("admin_level", "0") or 0))
    rel = rels[0]
    t = rel.get("tags", {})
    log(f"boundary: relation {rel['id']}  {t.get('name')} / {t.get('name:en')}")
    return rel


DATA_FILTERS = (
    'way["highway"];'
    'way["building"];'
    'rel["building"]["type"="multipolygon"];'
    'way["leisure"~"^(park|garden|playground|dog_park|pitch|sports_centre|track)$"];'
    'way["landuse"~"^(grass|recreation_ground|village_green|meadow|cemetery|forest|orchard|flowerbed|allotments)$"];'
    'way["natural"~"^(wood|scrub|grassland|water)$"];'
    'way["amenity"="parking"];'
    'way["place"="square"];'
    'node["natural"="tree"];'
    'node["highway"~"^(traffic_signals|crossing|stop|give_way)$"];'
)


def one_query(args):
    """Boundary and everything within --margin of it in ONE request, so it can be pasted
    into a browser (--print-query). Follows the city's own outline, not a rectangle."""
    if args.relation:
        sel = f"rel({args.relation})"
    else:
        rx = name_regex(args.place).replace('"', '\\"')
        sel = f'rel["boundary"="administrative"][~"^name(:[a-z]+)?$"~"{rx}",i]'
    m = int(args.margin)
    filters = (DATA_FILTERS.replace('way[', 'way.w[').replace('node[', 'node.n[')
               .replace('rel["building"]', 'rel(bw.w)["building"]'))
    return (f"[out:json][timeout:300][maxsize:536870912];{sel}->.city;.city out geom;"
            f"way(r.city)->.edge;.city map_to_area->.inside;"
            f"(way(area.inside);way(around.edge:{m});)->.w;"
            f"(node(area.inside);node(around.edge:{m});)->.n;"
            f"({filters});out geom;")


def from_file(args, path):
    """A raw Overpass answer saved by hand -> the same shape fetch() caches."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if "elements" not in data:
        sys.exit(f"{path} is not an Overpass JSON answer (no 'elements')")
    rel = None
    want = re.compile(name_regex(args.place), re.I) if args.place else None
    for e in data["elements"]:
        t = e.get("tags", {})
        if e["type"] == "relation" and t.get("boundary") == "administrative":
            names = [v for k, v in t.items() if k == "name" or k.startswith("name:")]
            if want is None or any(want.match(v) for v in names):
                rel = e
                break
    if args.bbox:
        s, w, n, e = [float(v) for v in args.bbox.split(",")]
    elif rel and "bounds" in rel:
        b = rel["bounds"]
        s, w, n, e = b["minlat"], b["minlon"], b["maxlat"], b["maxlon"]
    else:
        lats = [g["lat"] for el in data["elements"] if el["type"] == "way"
                for g in el.get("geometry", []) if g]
        lons = [g["lon"] for el in data["elements"] if el["type"] == "way"
                for g in el.get("geometry", []) if g]
        s, w, n, e = min(lats), min(lons), max(lats), max(lons)
        args.margin = 0.0
    log(f"boundary: {'relation ' + str(rel['id']) if rel else 'none found, using the data extent'}")
    dlat = args.margin / 111320.0
    dlon = args.margin / (111320.0 * math.cos(math.radians((s + n) / 2)))
    box = (s - dlat, w - dlon, n + dlat, e + dlon)
    return {"box": box, "boundary": rel, "data": data,
            "fetched": datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat()}


def fetch(args, slug):
    os.makedirs(CACHE, exist_ok=True)
    gd = os.path.join(CACHE, ".gdignore")   # keep Godot from scanning the raw downloads
    if not os.path.exists(gd):
        open(gd, "w").close()
    raw_path = os.path.join(CACHE, slug + ".raw.json")
    if args.from_file:
        raw = from_file(args, args.from_file)
        with open(raw_path, "w", encoding="utf-8") as f:
            json.dump(raw, f)
        log(f"  cached as {os.path.relpath(raw_path)}")
        return raw
    if args.offline:
        if not os.path.exists(raw_path):
            sys.exit(f"--offline but no cache at {raw_path}")
        with open(raw_path, encoding="utf-8") as f:
            return json.load(f)

    rel = None
    if args.bbox:
        s, w, n, e = [float(v) for v in args.bbox.split(",")]
    else:
        rel = find_boundary(args)
        b = rel["bounds"]
        s, w, n, e = b["minlat"], b["minlon"], b["maxlat"], b["maxlon"]
    dlat = args.margin / 111320.0
    dlon = args.margin / (111320.0 * math.cos(math.radians((s + n) / 2)))
    box = (s - dlat, w - dlon, n + dlat, e + dlon)
    log(f"fetching {box[0]:.5f},{box[1]:.5f} .. {box[2]:.5f},{box[3]:.5f} "
        f"(boundary box + {args.margin:.0f} m) ...")
    q = (f"[out:json][timeout:240][maxsize:536870912][bbox:{box[0]},{box[1]},{box[2]},{box[3]}];"
         "(" + DATA_FILTERS + ");out geom;")
    t0 = time.time()
    data = overpass(q)
    log(f"  {len(data['elements'])} elements in {time.time() - t0:.0f}s")
    raw = {"box": box, "boundary": rel, "data": data,
           "fetched": datetime.date.today().isoformat()}
    with open(raw_path, "w", encoding="utf-8") as f:
        json.dump(raw, f)
    log(f"  cached raw answer in {os.path.relpath(raw_path)}")
    return raw


# ---- geometry helpers ------------------------------------------------------------------

class Proj:
    """Local flat projection around (lat0, lon0) in metres; good to a few cm over a city."""

    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        p = math.radians(lat0)
        self.my = 111132.92 - 559.82 * math.cos(2 * p) + 1.175 * math.cos(4 * p)
        self.mx = 111412.84 * math.cos(p) - 93.5 * math.cos(3 * p)

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.mx, -(lat - self.lat0) * self.my)


def signed_area(pts):
    a = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % len(pts)]
        a += x1 * z2 - x2 * z1
    return a * 0.5


def clean_ring(pts, min_step=0.3):
    out = []
    for p in pts:
        if not out or math.dist(out[-1], p) >= min_step:
            out.append(p)
    if len(out) > 1 and math.dist(out[0], out[-1]) < min_step:
        out.pop()
    # drop points on a straight line (they only add wall quads)
    i = 0
    while len(out) > 3 and i < len(out):
        a, b, c = out[i - 1], out[i], out[(i + 1) % len(out)]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cross) < 0.02 * max(1e-6, math.dist(a, c)):
            out.pop(i)
        else:
            i += 1
    if len(out) < 3:
        return None
    if signed_area(out) < 0:  # counter-clockwise in (x, z): positive shoelace
        out.reverse()
    return out


def join_rings(segments):
    """Join way geometries (lists of points) end to end into closed rings."""
    segs = [list(s) for s in segments if len(s) >= 2]
    rings = []
    while segs:
        ring = segs.pop(0)
        changed = True
        while changed and ring[0] != ring[-1]:
            changed = False
            for i, s in enumerate(segs):
                if s[0] == ring[-1]:
                    ring += s[1:]
                elif s[-1] == ring[-1]:
                    ring += s[::-1][1:]
                elif s[-1] == ring[0]:
                    ring = s[:-1] + ring
                elif s[0] == ring[0]:
                    ring = s[::-1][:-1] + ring
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        if len(ring) >= 4:
            rings.append(ring)
    return rings


def q(v):
    return int(round(v * SCALE))


def flat(pts):
    out = []
    for x, z in pts:
        out += [q(x), q(z)]
    return out


def num(s):
    """'12', '12.5 m', '12;14' -> 12.0; anything else -> None."""
    if s is None:
        return None
    m = re.match(r"\s*(-?\d+(?:\.\d+)?)", str(s).replace(",", "."))
    return float(m.group(1)) if m else None


# ---- bake ------------------------------------------------------------------------------

def bake(raw, name, args):
    box = raw["box"]
    lat0, lon0 = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    P = Proj(lat0, lon0)
    x0, z1 = P(box[0], box[1])
    x1, z0 = P(box[2], box[3])
    inside = lambda x, z, pad=0.0: x0 - pad <= x <= x1 + pad and z0 - pad <= z <= z1 + pad

    elements = raw["data"]["elements"]
    out = {"version": 1, "name": name,
           "source": "© OpenStreetMap contributors, ODbL (openstreetmap.org/copyright)",
           "fetched": raw.get("fetched", ""), "origin": [round(lat0, 7), round(lon0, 7)],
           "scale": SCALE, "bounds": [round(x0, 1), round(z0, 1), round(x1, 1), round(z1, 1)],
           "boundary": [], "nodes": [], "roads": [], "buildings": [], "areas": [],
           "trees": [], "signals": [], "crossings": []}

    rel = raw.get("boundary")
    if rel:
        outer = [[P(g["lat"], g["lon"]) for g in m.get("geometry", []) if g]
                 for m in rel.get("members", []) if m.get("role") == "outer" and m["type"] == "way"]
        for ring in join_rings([[(round(x, 2), round(z, 2)) for x, z in s] for s in outer]):
            r = clean_ring(ring, 1.0)
            if r:
                out["boundary"].append(flat(r))

    # -- road graph: OSM node id -> index, shared wherever two ways share a node --------
    node_ix = {}
    def node(nid, x, z):
        if nid not in node_ix:
            node_ix[nid] = len(out["nodes"]) // 2
            out["nodes"] += [q(x), q(z)]
        return node_ix[nid]

    point_tags = {}
    for e in elements:
        if e["type"] == "node":
            point_tags[e["id"]] = e.get("tags", {})

    stats = {"roads": 0, "buildings": 0, "guessed": 0, "areas": 0, "skipped": 0}
    for e in elements:
        t = e.get("tags", {})
        if e["type"] != "way" or "highway" not in t or "geometry" not in e:
            continue
        kind = t["highway"]
        if t.get("area") == "yes" or kind not in ROAD_WIDTH or ROAD_WIDTH[kind] == 0:
            continue
        if t.get("access") in ("no", "private") and kind == "service":
            continue
        pts = [P(g["lat"], g["lon"]) if g else None for g in e["geometry"]]
        ids = e.get("nodes", [])
        if len(ids) != len(pts):
            continue
        # keep the stretch inside the box (+ a little), cut where it leaves for good
        keep = [i for i, p in enumerate(pts) if p and inside(p[0], p[1], 60.0)]
        if len(keep) < 2:
            continue
        runs, cur = [], [keep[0]]
        for i in keep[1:]:
            if i == cur[-1] + 1:
                cur.append(i)
            else:
                runs.append(cur)
                cur = [i]
        runs.append(cur)
        lanes = num(t.get("lanes"))
        width = num(t.get("width")) or num(t.get("est_width"))
        if not width:
            width = max(ROAD_WIDTH[kind], lanes * LANE) if lanes else ROAD_WIDTH[kind]
        oneway = t.get("oneway", "")
        o = 1 if oneway in ("yes", "1", "true") or t.get("junction") in ("roundabout", "circular") \
            else (-1 if oneway == "-1" else 0)
        for run in runs:
            if len(run) < 2:
                continue
            road = {"n": [node(ids[i], *pts[i]) for i in run], "k": kind,
                    "w": round(min(width, 30.0), 1)}
            if lanes:
                road["l"] = int(lanes)
            if o:
                road["o"] = o
            if t.get("name"):
                road["name"] = t["name"]
            if t.get("name:en"):
                road["name_en"] = t["name:en"]
            if t.get("bridge") and t["bridge"] != "no":
                road["br"] = 1
            if t.get("tunnel") and t["tunnel"] != "no":
                road["tu"] = 1
            out["roads"].append(road)
            stats["roads"] += 1
        for i in range(len(ids)):
            nt = point_tags.get(ids[i], {})
            if ids[i] in node_ix:
                if nt.get("highway") == "traffic_signals":
                    out["signals"].append(node_ix[ids[i]])
                elif nt.get("highway") == "crossing":
                    out["crossings"].append(node_ix[ids[i]])
    out["signals"] = sorted(set(out["signals"]))
    out["crossings"] = sorted(set(out["crossings"]))

    # -- buildings ------------------------------------------------------------------------
    def add_building(ring, t):
        r = clean_ring(ring)
        if not r:
            return
        cx = sum(p[0] for p in r) / len(r)
        cz = sum(p[1] for p in r) / len(r)
        if not inside(cx, cz):
            return
        if abs(signed_area(r)) < 4.0:   # a kiosk or a mapping slip
            stats["skipped"] += 1
            return
        kind = t.get("building", "yes")
        h = num(t.get("height"))
        levels = num(t.get("building:levels"))
        roof_levels = num(t.get("roof:levels")) or 0
        guessed = False
        if h is None and levels is not None:
            h = (levels + roof_levels) * LEVEL_H + 1.0
        if h is None:
            guessed = True
            lv = DEFAULT_LEVELS.get(kind, args.default_levels)
            h = lv * LEVEL_H + 1.0
        base = num(t.get("min_height"))
        if base is None and num(t.get("building:min_level")) is not None:
            base = num(t.get("building:min_level")) * LEVEL_H
        b = {"p": flat(r), "h": round(max(2.5, min(h, 400.0)), 1)}
        if base:
            b["b"] = round(base, 1)
        if guessed:
            b["g"] = 1
            stats["guessed"] += 1
        if t.get("name"):
            b["name"] = t["name"]
        if t.get("addr:street") and t.get("addr:housenumber"):
            b["addr"] = f"{t['addr:street']} {t['addr:housenumber']}"
        out["buildings"].append(b)
        stats["buildings"] += 1

    for e in elements:
        t = e.get("tags", {})
        if "building" not in t or t.get("building") in ("no", "demolished", "proposed"):
            continue
        if e["type"] == "way" and "geometry" in e:
            if all(e["geometry"]):
                add_building([P(g["lat"], g["lon"]) for g in e["geometry"]], t)
        elif e["type"] == "relation":
            outer = [[(round(x, 2), round(z, 2)) for x, z in
                      (P(g["lat"], g["lon"]) for g in m.get("geometry", []) if g)]
                     for m in e.get("members", []) if m.get("role") == "outer"]
            for ring in join_rings(outer):
                add_building(ring, t)

    # -- areas (ground cover) -------------------------------------------------------------
    for e in elements:
        t = e.get("tags", {})
        if e["type"] != "way" or "geometry" not in e or "building" in t:
            continue
        kind = None
        for key, kinds in AREA_KINDS:
            if t.get(key) in kinds:
                if key == "highway" and t.get("area") != "yes":
                    continue
                kind = kinds[t[key]]
                break
        if not kind:
            continue
        g = e["geometry"]
        if len(g) < 4 or not all(g) or (g[0]["lat"], g[0]["lon"]) != (g[-1]["lat"], g[-1]["lon"]):
            continue
        r = clean_ring([P(p["lat"], p["lon"]) for p in g], 0.5)
        if not r:
            continue
        cx = sum(p[0] for p in r) / len(r)
        cz = sum(p[1] for p in r) / len(r)
        if inside(cx, cz, 100.0):
            out["areas"].append({"p": flat(r), "k": kind})
            stats["areas"] += 1

    for e in elements:
        if e["type"] == "node" and e.get("tags", {}).get("natural") == "tree":
            x, z = P(e["lat"], e["lon"])
            if inside(x, z):
                out["trees"] += [q(x), q(z)]

    log(f"baked: {stats['roads']} road pieces, {len(out['nodes']) // 2} road nodes, "
        f"{stats['buildings']} buildings ({stats['guessed']} with guessed heights), "
        f"{stats['areas']} areas, {len(out['trees']) // 2} trees, {len(out['signals'])} "
        f"traffic lights; {x1 - x0:.0f} x {z1 - z0:.0f} m")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--place", help="administrative area name as on OSM (any language)")
    ap.add_argument("--relation", type=int, help="exact OSM relation id of the boundary")
    ap.add_argument("--bbox", help="south,west,north,east instead of a named place")
    ap.add_argument("--name", help="display name (defaults to --place)")
    ap.add_argument("--margin", type=float, default=250.0,
                    help="metres of neighbouring city kept around the boundary box")
    ap.add_argument("--default-levels", type=int, default=4,
                    help="storeys for a building OSM gives no height for")
    ap.add_argument("--out", help="where to write the city file")
    ap.add_argument("--offline", action="store_true", help="bake from tools/.cache only")
    ap.add_argument("--from-file", help="a raw Overpass JSON answer you saved yourself")
    ap.add_argument("--print-query", action="store_true",
                    help="print a browser link that downloads the raw data, for --from-file")
    args = ap.parse_args()
    if not (args.place or args.relation or args.bbox or args.from_file):
        ap.error("give --place, --relation, --bbox or --from-file")
    if args.print_query:
        if not (args.place or args.relation):
            ap.error("--print-query needs --place or --relation")
        q = one_query(args)
        log(q)
        print(OVERPASS + "?data=" + urllib.parse.quote(q, safe=""))
        return
    if not args.out:
        ap.error("--out is required")
    name = args.name or args.place or (f"relation {args.relation}" if args.relation else "area")
    slug = re.sub(r"[^a-z0-9]+", "_", (args.name or args.place or
                                       (str(args.relation) if args.relation else args.bbox)
                                       ).lower()).strip("_") or "city"
    raw = fetch(args, slug)
    city = bake(raw, name, args)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(city, f, ensure_ascii=False, separators=(",", ":"))
    log(f"wrote {args.out} ({os.path.getsize(args.out) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
