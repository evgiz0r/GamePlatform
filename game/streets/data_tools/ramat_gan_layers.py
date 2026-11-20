#!/usr/bin/env python3
"""Ramat Gan Municipality's public ArcGIS Online layers (its own account, services8.arcgis.com/
MdnyDq2GlaTWezhQ), the parts inside level 1's box, as one GeoJSON of points and polygons with
a `kind`. No licence is published on the items; the user approved committing them (21 Nov 2026).
The buildings' floors are a separate extract (ramat_gan_muni.geojson, see tools/osm_city.py).

    python3 game/streets/data_tools/ramat_gan_layers.py game/streets/cities/data/places_ramat_gan.geojson
"""
import json, sys, time, urllib.parse, urllib.request
from collections import Counter

BASE = "https://services8.arcgis.com/MdnyDq2GlaTWezhQ/arcgis/rest/services/"
BOX = (32.0561, 34.7952, 32.0842, 34.8234)   # S, W, N, E
LAYERS = [   # service, kind, {field in the layer: name in the file}
    ("all_gani_yeladim", "kindergarten", {"name": "name", "megama": "stream", "age": "age"}),
    ("school2023_לצפייה", "school", {"name1": "name", "סווג": "type"}),
    ("active_site5_11_23_תצוגה", "construction_site", {"Sug_Menage": "type", "status": "status", "Active_Sit": "stage"}),
    ("amudorim_תצוגה", "advert_column", {"light": "lit", "place": "place"}),
    ("heatmapbus2026", "bus_stop_shade", {"STOP_NAME": "name", "Percent_": "shade_pct", "AreaHupot": "canopy_m2", "STATIONID": "stop_code"}),
    ("יעוד_מסחרי", "commercial_plot", {"Ystr": "use", "main_l_use": "main_use"}),
]


def fetch(service):
    url, feats, off = BASE + urllib.parse.quote(service) + "/FeatureServer/0/query", [], 0
    while True:
        q = {"where": "1=1", "geometry": "%f,%f,%f,%f" % (BOX[1], BOX[0], BOX[3], BOX[2]),
             "geometryType": "esriGeometryEnvelope", "inSR": "4326", "outSR": "4326",
             "spatialRel": "esriSpatialRelIntersects", "outFields": "*", "returnGeometry": "true",
             "resultOffset": off, "resultRecordCount": 2000, "geometryPrecision": 6, "f": "geojson"}
        req = urllib.request.Request(url + "?" + urllib.parse.urlencode(q), headers={"User-Agent": "osm-city-bake/1"})
        with urllib.request.urlopen(req, timeout=120) as r:
            page = json.load(r)
        got = page.get("features", [])
        feats += got
        off += len(got)
        time.sleep(1)
        if not got or not (page.get("exceededTransferLimit") or page.get("properties", {}).get("exceededTransferLimit")):
            return feats


def main(out):
    res = []
    for service, kind, fields in LAYERS:
        for f in fetch(service):
            p = f.get("properties") or {}
            props = {"kind": kind}
            for src, dst in fields.items():
                v = p.get(src)
                if isinstance(v, str):
                    v = v.strip()
                if v not in (None, "", " "):
                    props[dst] = v
            res.append({"type": "Feature", "properties": props, "geometry": f["geometry"]})
    cnt = dict(Counter(f["properties"]["kind"] for f in res))
    fc = {"type": "FeatureCollection",
          "source": "Ramat Gan Municipality's public ArcGIS Online layers: " + ", ".join(l[0] for l in LAYERS)
                    + f"; the part in the box {BOX}; fetched " + time.strftime("%Y-%m-%d"),
          "credit": "places © Ramat Gan Municipality", "counts": cnt, "features": res}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(fc, f, ensure_ascii=False, separators=(",", ":"))
    print(cnt)


if __name__ == "__main__":
    main(sys.argv[1])
