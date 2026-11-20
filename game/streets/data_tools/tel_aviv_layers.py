#!/usr/bin/env python3
"""Tel Aviv-Yafo's GIS layers (gisn.tel-aviv.gov.il, IView2 MapServer) for the boxes of the
levels that reach Tel Aviv, as one GeoJSON with a `kind` per feature. The municipality's
open-data licence lets anyone copy, publish and process the data with credit to the source.
Only the fields a game can use are kept (no permit holders' or owners' names, and no
business names: a sole trader's is their own). Points as compact lists, one file per kind
that is many (trees, lamps, businesses, hydrants), the rest as GeoJSON with outlines
simplified to 0.5 m:

    python3 game/streets/data_tools/tel_aviv_layers.py game/streets/cities/data
"""
import json, math, os, sys, time, urllib.parse, urllib.request
from collections import Counter

URL = "https://gisn.tel-aviv.gov.il/arcgis/rest/services/IView2/MapServer/%d/query"
BOX = (32.0561, 34.7579, 32.0872, 34.8234)   # S, W, N, E: Tel Aviv's level and Givatayim's west strip
LAYERS = [   # layer, kind, {field: name in the file}
    (628, "tree", {"tree_name": "species", "scientific_name": "latin", "location_type": "where"}),
    (543, "lamp_pole", {"t_sug": "type", "ms_panasim": "lamps"}),
    (964, "business", {"t_hesber_mahut_esek": "what", "ms_koma": "floor", "shem_rechov": "street"}),
    (611, "bus_lane", {"street_name": "street", "type_of_nataz": "type", "from_street": "from", "to_street": "to",
                       "st_oper_hrs_sun_thurs": "start", "end_oper_hrs_sun_thurs": "end"}),
    (544, "parking_zone", {"ms_ezor": "zone", "LABEL": "label"}),
    (499, "construction_site", {"matzav_bniya": "stage", "shimush": "use", "sug_bakasha": "work"}),
    (682, "preserved_building", {"shem_mivne": "name", "hagbalot": "strict"}),
    (673, "hydrant", {"t_sug": "type"}),
    (951, "motorbike_parking", {"ms_mekomot": "places"}),
    (449, "loading_sign", {"traffic_sign_code": "code", "traffic_sign_text": "text"}),
    (691, "taxi_stand", {"shem": "name", "hanayot": "places"}),
    (577, "bike_path", {"width": "width", "direction": "direction", "miflas": "level", "BIKE_FACILITY_CATEGORY": "category"}),
    (835, "bike_share", {"Shem_tachana": "name"}),
    (606, "sculpture", {"shem_pesel": "name", "shem_oman": "artist", "shana": "year", "technika": "technique"}),
    (841, "notice_board", {"mikum": "where"}),
]


def fetch(layer, fields):
    feats, off = [], 0
    while True:
        q = {"where": "1=1", "geometry": "%f,%f,%f,%f" % (BOX[1], BOX[0], BOX[3], BOX[2]),
             "geometryType": "esriGeometryEnvelope", "inSR": "4326", "outSR": "4326",
             "spatialRel": "esriSpatialRelIntersects", "outFields": ",".join(fields), "returnGeometry": "true",
             "resultOffset": off, "resultRecordCount": 2000, "geometryPrecision": 6, "f": "geojson"}
        req = urllib.request.Request(URL % layer + "?" + urllib.parse.urlencode(q), headers={"User-Agent": "osm-city-bake/1"})
        with urllib.request.urlopen(req, timeout=180) as r:
            page = json.loads(r.read().decode("utf-8"))
        if "error" in page:
            raise RuntimeError(page["error"])
        got = page.get("features", [])
        feats += got
        off += len(got)
        time.sleep(1)
        if not got or not (page.get("exceededTransferLimit") or page.get("properties", {}).get("exceededTransferLimit")):
            return feats


def main(out):
    res = []
    for layer, kind, fields in LAYERS:
        try:
            got = fetch(layer, list(fields))
        except Exception as e:
            print(kind, "failed:", e, file=sys.stderr)
            continue
        for f in got:
            p = f.get("properties") or {}
            props = {"kind": kind}
            for src, dst in fields.items():
                v = p.get(src)
                if isinstance(v, str):
                    v = v.strip()
                if v not in (None, ""):
                    props[dst] = v
            res.append({"type": "Feature", "properties": props, "geometry": f["geometry"]})
        print(kind, len(got), file=sys.stderr)
    write(res, out)


def simplify(pts, eps=0.5):
    if len(pts) < 4:
        return pts
    if pts[0] == pts[-1]:   # a ring: split it at its far point so the two ends are not one point
        far = max(range(1, len(pts) - 1), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
        return _dp(pts[:far + 1], eps)[:-1] + _dp(pts[far:], eps)
    return _dp(pts, eps)


def _dp(pts, eps):
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


def geom_small(g):
    t, c = g["type"], g["coordinates"]
    if t == "Polygon":
        c = [simplify(r) for r in c]
    elif t == "MultiPolygon":
        c = [[simplify(r) for r in p] for p in c]
    elif t == "LineString":
        c = simplify(c)
    elif t == "MultiLineString":
        c = [simplify(l) for l in c]
    return {"type": t, "coordinates": c}


COMPACT = {"tree": ["species", "latin", "where"], "lamp_pole": ["type", "lamps"],
           "business": ["what", "floor", "street"], "hydrant": ["type"]}


def write(res, outdir):
    head = {"source": "Tel Aviv-Yafo Municipality GIS (gisn.tel-aviv.gov.il, IView2 MapServer), "
                      f"the box {BOX}; fetched " + time.strftime("%Y-%m-%d"),
            "licence": "Tel Aviv-Yafo open data: copy, publish and process for any lawful purpose, crediting the source",
            "credit": "city data © Tel Aviv-Yafo Municipality"}
    rest = []
    for kind, fields in COMPACT.items():
        rows = [[f["geometry"]["coordinates"][0], f["geometry"]["coordinates"][1]] + [f["properties"].get(k) for k in fields]
                for f in res if f["properties"]["kind"] == kind and f["geometry"] and f["geometry"]["type"] == "Point"]
        doc = dict(head, layer=[l[0] for l in LAYERS if l[1] == kind][0], fields=["lon", "lat"] + fields, rows=rows)
        path = os.path.join(outdir, "tel_aviv_%s.json" % {"tree": "trees", "lamp_pole": "lamp_poles",
                                                            "business": "businesses", "hydrant": "hydrants"}[kind])
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
        print(path, len(rows), f"{os.path.getsize(path) / 1e6:.2f} MB", file=sys.stderr)
    for f in res:
        if f["properties"]["kind"] not in COMPACT and f["geometry"]:
            f["geometry"] = geom_small(f["geometry"])
            rest.append(f)
    fc = dict(head, type="FeatureCollection", counts=dict(Counter(f["properties"]["kind"] for f in rest)), features=rest)
    path = os.path.join(outdir, "places_tel_aviv.geojson")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(fc, f, ensure_ascii=False, separators=(",", ":"))
    print(path, fc["counts"], f"{os.path.getsize(path) / 1e6:.2f} MB", file=sys.stderr)

if __name__ == "__main__":
    main(sys.argv[1])
