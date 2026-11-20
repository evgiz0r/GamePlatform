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
               name, name_en, br: 1 bridge, tu: 1 tunnel, em: 1 on an embankment,
               cu: 1 in a cutting, ly: OSM's layer when not 0, pv: 1 private (driveways),
               rb: 1 part of a roundabout, sv: a service road's kind -- parking_aisle,
               driveway, alley,
               bf / bb: the bus lanes going the way's own way (forward, node order) / the
                  other way: a letter a lane, left to right as a driver going that way sees
                  them, "b" a bus (public transport) lane, "-" any other -- from OSM's
                  bus:lanes / psv:lanes, lanes:bus / lanes:psv (a count: the rightmost) or
                  busway=lane (the rightmost); left out when OSM marks none. A way that is
                  all bus (highway=busway) is its kind, not these,
               y: [height per node]  the road's surface off the ground (a "deck"), in
                  decimetres above `height.base` like the ground grid; the bake leaves it out
                  (OSM has no such heights: tools/fake_city.py writes it for its own bridges
                  and tunnels), and a game draws a road without it on the ground}]
  buildings  [{p: [x, z, ...] counter-clockwise ring, h: height m, b: base height m,
               g: 1 if the height is a guess, name, addr}]
  areas      [{p: ring, k: park|grass|wood|water|parking|pitch|plaza|school, y: level}]
             (school: the grounds of a school or kindergarten; y: water that lies at its
             own level, decimetres above `height.base` -- a river held by weirs -- else it
             lies at its shore's lowest point)
  barriers   [[[x, z, x, z, ...], "fence"|"hedge"], ...]   fences and hedges as lines
  trees      [x, z, ...]
  addrs      [[x, z, street, number], ...]   address points not on a building outline
  stops      [[x, z, name], ...]   bus stops
  pois       [[x, z, kind, name, name_en], ...]   shops, restaurants, schools... (kind:
             the amenity/tourism value, or "shop:<type>" e.g. "shop:supermarket")
  height     {x0, z0, step, nx, nz, base, h: [...]}  ground height on a grid, decimetres above
             `base` (metres above sea level), row by row from (x0, z0); absent = flat
  signals    [node indices]   traffic lights that sit on the road graph
  crossings  [node indices]
  signs      [[node index, "stop"|"give_way", dx, dz], ...]   stop and give-way signs on
             the road graph; (dx, dz) x100 is the way of travel they face (from the sign's
             direction=forward/backward along its road), (0, 0) when OSM does not say
  rails      [{p: [x, z, ...] a track's line, k: rail|light_rail|tram|subway|narrow_gauge,
               name, tu: 1 tunnel, br: 1 bridge, ly: layer, sv: siding|yard|spur|crossover}]
             each track its own line (a double track is two); tracks that join share an end
             point exactly
  platforms  [{p: [x, z, ...], a: 1 when an outline (else a line along a track's edge), name}]
  stations   [[x, z, name, name_en, kind], ...]   kind: OSM's station= (train, light_rail,
             subway...), "train" when it does not say
             (rails, platforms and stations are absent from files baked before they were kept)
  made_up    1 in a town tools/fake_city.py made up (no OSM data, no credit owed); absent here

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
import zlib

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
RAIL_KINDS = {"rail", "light_rail", "tram", "subway", "narrow_gauge"}
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
    ("amenity", {"parking": "parking", "school": "school", "kindergarten": "school"}),
    ("place", {"square": "plaza"}),
    ("highway", {"pedestrian": "plaza"}),   # a closed pedestrian way tagged area=yes
]


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---- fetch ---------------------------------------------------------------------------

def overpass(query, tries=3):
    body = urllib.parse.urlencode({"data": query}).encode()
    for attempt in range(tries):
        for url in SERVERS:
            try:
                req = urllib.request.Request(url, data=body, headers={
                    "User-Agent": "osm-city-bake/1 (a game kit's map baker)",
                    "Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=240) as r:
                    answer = json.loads(r.read().decode("utf-8"))
                # a timed-out or failed query still answers 200, with a remark and no data
                remark = answer.get("remark", "")
                if "error" in remark.lower() or "timed out" in remark.lower():
                    raise RuntimeError(remark.strip())
                # (a mirror can serve older data: one answered a city centre with a fifth of
                # its footways missing -- say which, so a re-bake can be compared)
                log(f"  answered by {urllib.parse.urlparse(url).netloc}")
                return answer
            except Exception as e:  # rate limits and timeouts are routine on public servers
                log(f"  {urllib.parse.urlparse(url).netloc}: {e}")
        if attempt + 1 < tries:
            wait = 30 * 3 ** attempt   # busy public servers: give them a minute or two
            log(f"  every server refused; trying again in {wait}s")
            time.sleep(wait)
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


def split_place(place):
    """'Bedford, Nova Scotia' -> ('Bedford', 'Nova Scotia'); a bare name has no region."""
    name, _, region = place.partition(",")
    return name.strip(), region.strip()


def find_boundary(args):
    """The place's administrative boundary relation. 'Name, Region' only looks inside that
    region (there are Bedfords on three continents). With no boundary mapped, falls back to
    the place's centre point (a town, suburb or neighbourhood node) and a --radius box."""
    region_q = within = ""
    if args.relation:
        sel = f"rel({args.relation});"
        name = str(args.relation)
    else:
        name, region = split_place(args.place)
        rx = name_regex(name).replace('"', '\\"')
        if region:
            # by exact name: a pattern over every boundary on Earth times out
            rn = region.replace('"', '\\"')
            region_q = (f'(area["boundary"="administrative"]["name"="{rn}"];'
                        f'area["boundary"="administrative"]["name:en"="{rn}"];)->.region;')
            within = "(area.region)"
        sel = (f'{region_q}rel["boundary"="administrative"][~"^name(:[a-z]+)?$"~"{rx}",i]'
               f"{within};")
    data = overpass(f"[out:json][timeout:180];{sel}out geom;")
    rels = [e for e in data["elements"] if e["type"] == "relation"]
    if not rels and not args.relation:
        found = overpass(f"[out:json][timeout:180];{region_q}"
                         f'node["place"][~"^name(:[a-z]+)?$"~"{rx}",i]{within};out;')
        rank = ["city", "town", "suburb", "village", "quarter", "neighbourhood", "hamlet"]
        pts = sorted([e for e in found["elements"] if e["type"] == "node"],
                     key=lambda e: rank.index(e.get("tags", {}).get("place"))
                     if e.get("tags", {}).get("place") in rank else 99)
        if pts:
            n = pts[0]
            dlat = args.radius / 111320.0
            dlon = args.radius / (111320.0 * math.cos(math.radians(n["lat"])))
            log(f"no boundary mapped; using the {n['tags'].get('place')} point "
                f"node {n['id']} and {args.radius:.0f} m round it")
            return {"type": "relation", "id": None, "tags": n.get("tags", {}), "members": [],
                    "bounds": {"minlat": n["lat"] - dlat, "maxlat": n["lat"] + dlat,
                               "minlon": n["lon"] - dlon, "maxlon": n["lon"] + dlon}}
    if not rels:
        sys.exit(f"nothing named '{args.place}' found. Try 'Name, Region', --relation <id> "
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


def take_in(names, box):
    """Grow the box to cover other places by name -- a park, a lake, a street -- each the
    match nearest the box's centre (Nova Scotia alone has dozens of Sandy Lakes)."""
    s, w, n, e = box
    cy, cx = (s + n) / 2, (w + e) / 2
    kx = math.cos(math.radians(cy))

    def km(lat, lon):
        return math.hypot((lat - cy) * 111.32, (lon - cx) * 111.32 * kx)

    wanted = [x.strip() for x in names.split(";") if x.strip()]
    # every exact name in ONE request (tag values are indexed, so it answers at once; the
    # public servers throttle many small requests from shared CI addresses)
    union = "".join(f'nwr["{key}"="{w.replace(chr(34), "")}"](around:20000,{cy},{cx});'
                    for w in wanted for key in ("name", "name:en"))
    exact = overpass(f"[out:json][timeout:180];({union});out bb;")["elements"]
    for name in wanted:
        hits = [el for el in exact if name in (el.get("tags", {}).get("name"),
                                                el.get("tags", {}).get("name:en"))]
        data = {"elements": hits}
        if not hits:   # a spelling or case slip: a pattern on the name key, nearer in
            rx = name_regex(name).replace('"', '\\"')
            data = overpass(f"[out:json][timeout:180];"
                            f'nwr["name"~"{rx}",i](around:12000,{cy},{cx});out bb;')
        found = []
        for el in data["elements"]:
            if el["type"] == "node":
                b = (el["lat"], el["lon"], el["lat"], el["lon"])
            elif "bounds" in el:
                bb = el["bounds"]
                b = (bb["minlat"], bb["minlon"], bb["maxlat"], bb["maxlon"])
            else:
                continue
            found.append((km((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), b, el))
        if not found:
            log(f"  include '{name}': nothing by that name within 30 km -- skipped")
            continue
        found.sort(key=lambda f: f[0])
        best = found[0]
        bc = ((best[1][0] + best[1][2]) / 2, (best[1][1] + best[1][3]) / 2)
        # a street is many ways, a park a way and a relation: take every piece near the best
        for d, b, el in found:
            if math.hypot((b[0] + b[2]) / 2 - bc[0], ((b[1] + b[3]) / 2 - bc[1]) * kx) * 111.32 < 2.5:
                s, w, n, e = min(s, b[0]), min(w, b[1]), max(n, b[2]), max(e, b[3])
        t = best[2].get("tags", {})
        kind = next((f"{k}={t[k]}" for k in ("leisure", "natural", "highway", "place", "landuse")
                     if k in t), best[2]["type"])
        log(f"  include '{name}': {kind} {best[2]['type']} {best[2]['id']}, {best[0]:.1f} km "
            "from the centre")
    return s, w, n, e


DATA_FILTERS = (
    'way["highway"];'
    'way["building"];'
    'rel["building"]["type"="multipolygon"];'
    'way["leisure"~"^(park|garden|playground|dog_park|pitch|sports_centre|track)$"];'
    'way["landuse"~"^(grass|recreation_ground|village_green|meadow|cemetery|forest|orchard|flowerbed|allotments)$"];'
    'way["natural"~"^(wood|scrub|grassland|water)$"];'
    'way["amenity"="parking"];'
    'way["barrier"~"^(fence|hedge)$"];'
    'way["place"="square"];'
    'way["natural"="coastline"];'
    'node["addr:housenumber"]["addr:street"];'
    'node["highway"="bus_stop"];'
    # places people go: food, shops, health, services, schools, culture, worship
    'node["shop"];way["shop"];'
    'node["amenity"~"^(restaurant|cafe|fast_food|bar|pub|ice_cream|pharmacy|bank|post_office|clinic|doctors|dentist|fuel|school|kindergarten|library|place_of_worship|cinema|theatre|community_centre)$"];'
    'way["amenity"~"^(restaurant|cafe|fast_food|pharmacy|bank|post_office|clinic|fuel|school|kindergarten|library|place_of_worship|cinema|theatre|community_centre)$"];'
    'node["tourism"~"^(hotel|museum|attraction)$"];way["tourism"~"^(hotel|museum)$"];'
    'node["natural"="tree"];'
    'node["highway"~"^(traffic_signals|crossing|stop|give_way)$"];'
    # railways: the lines (not the disused and the planned), the platforms, the stations
    'way["railway"~"^(rail|light_rail|tram|subway|narrow_gauge)$"];'
    'way["railway"="platform"];'
    'node["railway"~"^(station|halt)$"];'
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
    if args.include:
        s, w, n, e = take_in(args.include, (s, w, n, e))
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


# ---- ground height ----------------------------------------------------------------------
# AWS's open terrain tiles ("terrarium" PNGs: height = R*256 + G + B/256 - 32768 metres),
# mostly SRTM: ~30 m detail, a surface model (it sees some rooftops), free, no key.
TERRAIN = os.environ.get("TERRAIN_URL",
                         "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png")


def png_pixels(data):
    """Minimal PNG reader for 8-bit RGB/RGBA, non-interlaced: (w, h, bytes/pixel, bytes)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, w, h, ctype = 8, b"", 0, 0, 2
    while pos < len(data):
        n = int.from_bytes(data[pos:pos + 4], "big")
        kind, body = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            w, h = int.from_bytes(body[0:4], "big"), int.from_bytes(body[4:8], "big")
            if body[8] != 8 or body[12] != 0:
                raise ValueError("only 8-bit, non-interlaced PNGs")
            ctype = body[9]
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    bpp = {2: 3, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * bpp
    out = bytearray(h * stride)
    prev = bytearray(stride)
    i = 0
    for y in range(h):
        f = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        if f == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, bpp, out


BARE_R = 90.0   # metres: --bare-ground takes out bumps narrower than twice this


def _square(g, nx, nz, k, f):
    """f (min, max or the mean) over the square of radius k cells round each cell, in two
    passes (rows, then columns)."""
    a = [0.0] * len(g)
    for j in range(nz):
        row = g[j * nx:(j + 1) * nx]
        for i in range(nx):
            a[j * nx + i] = f(row[max(0, i - k):i + k + 1])
    b = [0.0] * len(g)
    for i in range(nx):
        col = a[i::nx]
        for j in range(nz):
            b[j * nx + i] = f(col[max(0, j - k):j + k + 1])
    return b


def bare_ground(grid, nx, nz, step):
    """The tiles are a surface model: in a city centre they see the roofs, and a cluster of
    towers comes out as a hill (Azrieli's stood 146 m over the Ayalon, slopes of 300%).
    Each point becomes the highest of the lowest round it (a grey opening over BARE_R): any
    bump narrower than ~2 * BARE_R goes, broad hills and valleys stay; then a mean over half
    that, as the opening leaves flat steps. Over Givatayim it took the hill's crest 86 -> 72 m
    and its steepest slope 48% -> 16%, so it is asked for (--bare-ground), not the default."""
    k = max(1, round(BARE_R / step))
    opened = _square(_square(grid, nx, nz, k, min), nx, nz, k, max)
    return _square(opened, nx, nz, max(1, k // 2), lambda v: sum(v) / len(v))


def terrain_grid(P, box, bounds, step, zoom=13, bare=False):
    """Ground height on a regular grid over the bounds, in metres above its lowest point."""
    x0, z0, x1, z1 = bounds
    nx, nz = int(math.ceil((x1 - x0) / step)) + 1, int(math.ceil((z1 - z0) / step)) + 1
    n = 2 ** zoom
    tiles = {}

    def tile(tx, ty):
        if (tx, ty) not in tiles:
            url = TERRAIN.format(z=zoom, x=tx, y=ty)
            req = urllib.request.Request(url, headers={"User-Agent": "osm-city-bake/1"})
            with urllib.request.urlopen(req, timeout=60) as r:
                tiles[(tx, ty)] = png_pixels(r.read())
        return tiles[(tx, ty)]

    def px_height(gx, gy):  # global pixel coordinates at this zoom
        tx, ty = int(gx // 256), int(gy // 256)
        w, h, bpp, pix = tile(tx, ty)
        x, y = int(gx - tx * 256), int(gy - ty * 256)
        o = (y * w + x) * bpp
        return pix[o] * 256 + pix[o + 1] + pix[o + 2] / 256.0 - 32768.0

    def height(lat, lon):
        gx = (lon + 180.0) / 360.0 * n * 256
        gy = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n * 256
        fx, fy = gx - 0.5, gy - 0.5
        ix, iy = int(math.floor(fx)), int(math.floor(fy))
        ax, ay = fx - ix, fy - iy
        h00, h10 = px_height(ix, iy), px_height(ix + 1, iy)
        h01, h11 = px_height(ix, iy + 1), px_height(ix + 1, iy + 1)
        return (h00 * (1 - ax) + h10 * ax) * (1 - ay) + (h01 * (1 - ax) + h11 * ax) * ay

    grid = []
    for j in range(nz):
        for i in range(nx):
            x, z = x0 + i * step, z0 + j * step
            grid.append(height(P.lat0 - z / P.my, P.lon0 + x / P.mx))
    if bare:
        raw_top = max(grid)
        grid = bare_ground(grid, nx, nz, step)
        log(f"ground: roofs taken out (--bare-ground), the top {raw_top:.0f} -> {max(grid):.0f} m")
    # one light blur: the data is a surface model, rooftops make bumps
    blur = grid[:]
    for j in range(nz):
        for i in range(nx):
            acc, cnt = 0.0, 0
            for dj in (-1, 0, 1):
                for di in (-1, 0, 1):
                    ii, jj = i + di, j + dj
                    if 0 <= ii < nx and 0 <= jj < nz:
                        acc += grid[jj * nx + ii]
                        cnt += 1
            blur[j * nx + i] = acc / cnt
    base = min(blur)
    log(f"ground: {nx} x {nz} grid every {step:.0f} m from {len(tiles)} tiles, "
        f"{base:.0f} to {max(blur):.0f} m above sea level")
    return {"x0": round(x0, 1), "z0": round(z0, 1), "step": step, "nx": nx, "nz": nz,
            "base": round(base, 1), "h": [int(round((v - base) * SCALE)) for v in blur]}


def join_chains(segments):
    """Coastline ways end to end, keeping their direction (it says which side is land)."""
    chains = [list(s) for s in segments if len(s) >= 2]
    merged = True
    while merged:
        merged = False
        for i in range(len(chains)):
            for j in range(len(chains)):
                if i != j and chains[i] and chains[j] and chains[i][-1] == chains[j][0]:
                    chains[i] = chains[i] + chains[j][1:]
                    chains[j] = []
                    merged = True
        chains = [c for c in chains if c]
    return chains


def sea_polygons(coast, box):
    """Turn coastline (land on the left, sea on the right) into sea polygons inside the
    box, closed along the box edge; closed coast rings inside the box are islands."""
    x0, z0, x1, z1 = box
    W, H = x1 - x0, z1 - z0
    per = 2 * (W + H)

    def inside(p):
        return x0 <= p[0] <= x1 and z0 <= p[1] <= z1

    def t_of(p):  # position along the box edge, clockwise as seen on a north-up map
        x, z = p
        edge = min(((abs(z - z0), 0), (abs(x - x1), 1), (abs(z - z1), 2), (abs(x - x0), 3)))[1]
        return (x - x0, W + (z - z0), W + H + (x1 - x), 2 * W + H + (z1 - z))[edge]

    def clip(a, b):  # Liang-Barsky: the part of a->b inside the box as (t0, t1), or None
        t0, t1 = 0.0, 1.0
        dx, dz = b[0] - a[0], b[1] - a[1]
        for pp, qq in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dz, a[1] - z0), (dz, z1 - a[1])):
            if pp == 0:
                if qq < 0:
                    return None
            else:
                r = qq / pp
                if pp < 0:
                    t0 = max(t0, r)
                else:
                    t1 = min(t1, r)
        return (t0, t1) if t0 <= t1 else None

    def lerp(a, b, t):
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)

    pieces, islands = [], []
    for ch in join_chains(coast):
        if ch[0] == ch[-1] and all(inside(p) for p in ch):
            # land is on the left: drawn anticlockwise on a north-up map (a negative
            # shoelace in x/z, where z points south) the ring is an island
            if signed_area(ch[:-1]) < 0:
                islands.append(ch[:-1])
            continue
        cur, started = None, False
        for i in range(1, len(ch)):
            a, b = ch[i - 1], ch[i]
            c = clip(a, b)
            if c is None:
                cur = None
                continue
            t0, t1 = c
            if t0 > 0.0:                 # comes in across the edge
                cur, started = [lerp(a, b, t0)], True
            elif cur is None:            # the coast begins inside the box: cannot close it
                cur, started = [a], False
            cur.append(lerp(a, b, t1) if t1 < 1.0 else b)
            if t1 < 1.0:                 # goes out across the edge
                if started:
                    pieces.append(cur)
                cur = None
    if not pieces:
        return [], islands
    used, polys = set(), []
    for start in range(len(pieces)):
        if start in used:
            continue
        poly, cur = [], start
        for _ in range(len(pieces) + 1):
            used.add(cur)
            poly += pieces[cur]
            t_out = t_of(pieces[cur][-1])
            nxt = min(range(len(pieces)), key=lambda k: (t_of(pieces[k][0]) - t_out) % per)
            t_in = t_of(pieces[nxt][0])
            # corners passed going clockwise from t_out to t_in
            span = (t_in - t_out) % per
            for ct, corner in sorted(((W, (x1, z0)), (W + H, (x1, z1)), (2 * W + H, (x0, z1)),
                                      (0.0, (x0, z0))), key=lambda c: (c[0] - t_out) % per):
                if 0 < (ct - t_out) % per < span:
                    poly.append(corner)
            if nxt == start:
                break
            cur = nxt
        polys.append(poly)
    return polys, islands


def q(v):
    return int(round(v * SCALE))


def flat(pts):
    out = []
    for x, z in pts:
        out += [q(x), q(z)]
    return out


def bus_lanes(t, lanes, o):
    """the bus lanes a way's tags mark, per way of travel: {"bf": "--b", "bb": "b"} (see the
    format above); {} when there are none"""
    def pattern(v):
        if not v:
            return ""
        parts = [p.strip() for p in v.split("|")]
        if not any(p in ("designated", "only") for p in parts):
            return ""
        return "".join("b" if p in ("designated", "only") else "-" for p in parts)

    def count(v, n):
        k = int(num(v) or 0)
        if k <= 0:
            return ""
        n = int(n) if n and n > k else k
        return "-" * (n - k) + "b" * k

    two_way = o == 0
    lanes = int(lanes or 0)
    each = lanes // 2 if two_way and lanes else lanes
    out = {}
    for way, keys in (("bf", ("forward",) if two_way else ("", "forward")), ("bb", ("backward",) if two_way else ())):
        got = ""
        for sfx in keys:
            tail = (":" + sfx) if sfx else ""
            got = got or pattern(t.get("bus:lanes" + tail)) or pattern(t.get("psv:lanes" + tail)) \
                or count(t.get("lanes:bus" + tail), each) or count(t.get("lanes:psv" + tail), each)
        if got:
            out[way] = got
    # busway=lane / busway:right / busway:left / busway:both: the rightmost lane each way
    side = {"busway": "both", "busway:both": "both", "busway:right": "right", "busway:left": "left"}
    for key, where in side.items():
        if t.get(key) in ("lane", "opposite_lane"):
            if where in ("both", "right") and "bf" not in out and o != -1:
                out["bf"] = "-" * max(each - 1, 0) + "b"
            if (where in ("both", "left") and two_way) or (o == -1 and where != "left"):
                out.setdefault("bb", "-" * max(each - 1, 0) + "b")
    if o == -1 and "bf" in out:   # (the way is drawn against its travel: its lanes are the "other" way's)
        out["bb"] = out.pop("bf")
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
           "trees": [], "signals": [], "crossings": [], "signs": [], "barriers": []}

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
            if t.get("embankment") in ("yes", "1"):
                road["em"] = 1
            if t.get("cutting") in ("yes", "1"):
                road["cu"] = 1
            ly = num(t.get("layer"))
            if ly and -5 <= ly <= 5 and int(ly) == ly:
                road["ly"] = int(ly)
            if t.get("access") in ("no", "private"):
                road["pv"] = 1
            if t.get("junction") in ("roundabout", "circular"):
                road["rb"] = 1
            if kind == "service" and t.get("service") in ("parking_aisle", "driveway", "alley"):
                road["sv"] = t["service"]
            road.update(bus_lanes(t, lanes, o))
            if "bf" in road or "bb" in road:
                stats["bus_lanes"] = stats.get("bus_lanes", 0) + 1
            out["roads"].append(road)
            stats["roads"] += 1
        for i in range(len(ids)):
            nt = point_tags.get(ids[i], {})
            if ids[i] in node_ix:
                if nt.get("highway") == "traffic_signals":
                    out["signals"].append(node_ix[ids[i]])
                elif nt.get("highway") == "crossing":
                    out["crossings"].append(node_ix[ids[i]])
                elif nt.get("highway") in ("stop", "give_way") and pts[i]:
                    # facing: forward = the way's own direction at this node
                    d = (0.0, 0.0)
                    way = nt.get("direction", "")
                    if way in ("forward", "backward"):
                        a = pts[i - 1] if i > 0 and pts[i - 1] else pts[i]
                        b = pts[i + 1] if i + 1 < len(pts) and pts[i + 1] else pts[i]
                        dx, dz = b[0] - a[0], b[1] - a[1]
                        L = math.hypot(dx, dz) or 1.0
                        k = 1.0 if way == "forward" else -1.0
                        d = (dx / L * k, dz / L * k)
                    out["signs"].append([node_ix[ids[i]], nt["highway"], round(d[0] * 100), round(d[1] * 100)])
    out["signals"] = sorted(set(out["signals"]))
    seen_signs = set()
    signs = []
    for sg in out["signs"]:
        if (sg[0], sg[1]) not in seen_signs:
            seen_signs.add((sg[0], sg[1]))
            signs.append(sg)
    out["signs"] = signs
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
            lv = DEFAULT_LEVELS.get(kind)
            if lv is None:
                # a plain "building" with no height: its footprint is the best clue. A
                # suburban house is under ~180 m2, a Givatayim apartment block 300-600.
                fp = abs(signed_area(r))
                lv = 1 if fp < 60 else (2 if fp < 180 else (3 if fp < 280 else args.default_levels))
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

    # fences and hedges, as lines (a closed one is a ring with its first point again last)
    for e in elements:
        t = e.get("tags", {})
        if e["type"] != "way" or "geometry" not in e or t.get("barrier") not in ("fence", "hedge"):
            continue
        line = [P(p["lat"], p["lon"]) for p in e["geometry"] if p]
        if len(line) < 2:
            continue
        cx = sum(p[0] for p in line) / len(line)
        cz = sum(p[1] for p in line) / len(line)
        if inside(cx, cz, 100.0):
            out["barriers"].append([flat(line), t["barrier"]])
    log(f"barriers: {len(out['barriers'])}")

    # the sea: OSM draws it as coastline lines with the land on their left
    coast = [[P(g["lat"], g["lon"]) for g in e["geometry"] if g] for e in elements
             if e["type"] == "way" and e.get("tags", {}).get("natural") == "coastline"
             and "geometry" in e]
    if coast:
        water, islands = sea_polygons(coast, (x0, z0, x1, z1))
        for ring in water:
            r = clean_ring(ring, 0.5)
            if r:
                out["areas"].append({"p": flat(r), "k": "water"})
        for ring in islands:
            r = clean_ring(ring, 0.5)
            if r:
                out["areas"].append({"p": flat(r), "k": "land"})
        log(f"coast: {len(water)} sea areas, {len(islands)} islands")

    # points of interest: [x, z, kind, name, name_en]; kind is the amenity / tourism value or
    # "shop" (the game decides how each looks)
    out["pois"] = []
    for e in elements:
        t = e.get("tags", {})
        # shops keep their type ("shop:bakery"), so a game can tell a supermarket from a kiosk
        kind = t.get("amenity") or t.get("tourism") or (("shop:" + t["shop"]) if "shop" in t else None)
        if not kind or kind in ("parking",) or "highway" in t:
            continue
        if e["type"] == "node":
            x, z = P(e["lat"], e["lon"])
        elif e["type"] == "way" and e.get("geometry") and all(e["geometry"]):
            ring = [P(g["lat"], g["lon"]) for g in e["geometry"]]
            x = sum(p[0] for p in ring) / len(ring)
            z = sum(p[1] for p in ring) / len(ring)
        else:
            continue
        if inside(x, z):
            out["pois"].append([q(x), q(z), kind, t.get("name", ""), t.get("name:en", "")])

    # bus stops: [x, z, name]
    out["stops"] = []
    for e in elements:
        t = e.get("tags", {})
        if e["type"] == "node" and t.get("highway") == "bus_stop":
            x, z = P(e["lat"], e["lon"])
            if inside(x, z):
                out["stops"].append([q(x), q(z), t.get("name", "")])

    # addresses that are points (a door, an entrance) rather than tags on a building
    out["addrs"] = []
    for e in elements:
        t = e.get("tags", {})
        if e["type"] == "node" and t.get("addr:street") and t.get("addr:housenumber"):
            x, z = P(e["lat"], e["lon"])
            if inside(x, z):
                out["addrs"].append([q(x), q(z), t["addr:street"], t["addr:housenumber"]])

    for e in elements:
        if e["type"] == "node" and e.get("tags", {}).get("natural") == "tree":
            x, z = P(e["lat"], e["lon"])
            if inside(x, z):
                out["trees"] += [q(x), q(z)]

    # -- railways: each track a line of its own (OSM maps every track as a way; two that
    # meet share an end point, to the decimetre), the platforms beside them, the stations
    rails, platforms, stations = [], [], []
    for e in elements:
        t = e.get("tags", {})
        kind = t.get("railway")
        if e["type"] == "node" and kind in ("station", "halt"):
            x, z = P(e["lat"], e["lon"])
            if inside(x, z):
                stations.append([q(x), q(z), t.get("name", ""), t.get("name:en", ""),
                                 t.get("station", "train")])
            continue
        if e["type"] != "way" or "geometry" not in e or kind not in RAIL_KINDS | {"platform"}:
            continue
        pts = [P(g["lat"], g["lon"]) if g else None for g in e["geometry"]]
        if kind == "platform":
            if all(p and inside(p[0], p[1], 60.0) for p in pts) and len(pts) >= 2:
                pl = {"p": flat(pts), "name": t.get("name", "")}
                if len(pts) >= 4 and e.get("nodes", [0])[0] == e.get("nodes", [1])[-1]:
                    pl["a"] = 1   # an outline (else a line along the track's edge)
                platforms.append(pl)
            continue
        keep = [i for i, p in enumerate(pts) if p and inside(p[0], p[1], 60.0)]
        runs, cur = [], []
        for i in keep:
            if cur and i != cur[-1] + 1:
                runs.append(cur)
                cur = []
            cur.append(i)
        runs.append(cur)
        for run in runs:
            if len(run) < 2:
                continue
            rail = {"p": flat([pts[i] for i in run]), "k": kind}
            if t.get("name"):
                rail["name"] = t["name"]
            if t.get("tunnel") and t["tunnel"] != "no":
                rail["tu"] = 1
            if t.get("bridge") and t["bridge"] != "no":
                rail["br"] = 1
            ly = num(t.get("layer"))
            if ly and -5 <= ly <= 5 and int(ly) == ly:
                rail["ly"] = int(ly)
            if t.get("service"):
                rail["sv"] = t["service"]   # siding, yard, spur, crossover
            rails.append(rail)
    if rails or stations:
        out["rails"], out["platforms"], out["stations"] = rails, platforms, stations

    if not args.no_terrain:
        try:
            span = max(x1 - x0, z1 - z0)
            out["height"] = terrain_grid(P, box, (x0, z0, x1, z1), max(12.0, round(span / 300.0)),
                                         bare=args.bare_ground)
        except Exception as e:   # flat is better than no city
            log(f"ground: no height data ({e}); the city stays flat")

    log(f"baked: {stats['roads']} road pieces, {len(out['nodes']) // 2} road nodes, "
        f"{stats['buildings']} buildings ({stats['guessed']} with guessed heights), "
        f"{stats['areas']} areas, {len(out['trees']) // 2} trees, {len(out['signals'])} "
        f"traffic lights, {len(out.get('rails', []))} rail tracks, {len(out.get('stations', []))} "
        f"stations, {stats.get('bus_lanes', 0)} road pieces with bus lanes; {x1 - x0:.0f} x {z1 - z0:.0f} m")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--place", help="administrative area name as on OSM (any language)")
    ap.add_argument("--relation", type=int, help="exact OSM relation id of the boundary")
    ap.add_argument("--bbox", help="south,west,north,east instead of a named place")
    ap.add_argument("--name", help="display name (defaults to --place)")
    ap.add_argument("--include", help="more places to take in, ';'-separated, e.g. "
                    "\"Hemlock Ravine Park; Kearney Lake\" (each the match nearest the place)")
    ap.add_argument("--radius", type=float, default=2000.0,
                    help="metres round the centre when the place has no boundary mapped")
    ap.add_argument("--margin", type=float, default=250.0,
                    help="metres of neighbouring city kept around the boundary box")
    ap.add_argument("--default-levels", type=int, default=4,
                    help="storeys for a building OSM gives no height for")
    ap.add_argument("--out", help="where to write the city file")
    ap.add_argument("--offline", action="store_true", help="bake from tools/.cache only")
    ap.add_argument("--from-file", help="a raw Overpass JSON answer you saved yourself")
    ap.add_argument("--no-terrain", action="store_true", help="skip the ground heights")
    ap.add_argument("--bare-ground", action="store_true",
                    help="take buildings out of the ground heights (a city of towers comes "
                         "out of the terrain tiles as hills)")
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
    name = args.name or (split_place(args.place)[0] if args.place else None) or (f"relation {args.relation}" if args.relation else "area")
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
