#!/usr/bin/env python3
"""Building heights for any French town from IGN's BD TOPO (Licence Ouverte / Etalab 2.0), via
the Géoplateforme's WFS (data.geopf.fr, layer BDTOPO_V3:batiment, WGS84 GeoJSON, no key):
each building's height, its roof's top above the ground (the ridge), its storeys and the year
it appeared. Written to cities/data/fr_bdtopo_<town>.geojson, one file a town, which the
baker reads as the survey "fr_bdtopo" (SURVEYS in tools/osm_city.py) -- so another French
town needs only this command, with its box and name, before its bake.

    python game/streets/data_tools/fr_bdtopo.py S,W,N,E <town>

The fields, as IGN defines them: `hauteur` the height from the foot of the building to the
top of its outline (about the eaves); `altitude_maximale_toit` the roof's highest point and
`altitude_minimale_sol` / `altitude_maximale_sol` the ground round it, all metres above sea.
A roof whose top is more than a metre over the eaves is taken as pitched, its ridge kept.
"""
import json, os, sys, time, urllib.parse, urllib.request

WFS = "https://data.geopf.fr/wfs/ows"
PAGE = 1000


def fetch(box):
    s, w, n, e = box
    feats, start = [], 0
    while True:
        q = {"SERVICE": "WFS", "VERSION": "2.0.0", "REQUEST": "GetFeature", "TYPENAMES": "BDTOPO_V3:batiment",
             "outputFormat": "application/json", "srsName": "EPSG:4326", "COUNT": PAGE, "STARTINDEX": start,
             "SORTBY": "cleabs", "BBOX": "%f,%f,%f,%f,EPSG:4326" % (w, s, e, n)}
        req = urllib.request.Request(WFS + "?" + urllib.parse.urlencode(q),
                                     headers={"User-Agent": "osm-city-bake/1 (a game kit's map baker)"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    page = json.load(r)
                break
            except Exception as ex:
                if attempt == 3:
                    raise
                print("  retry after", ex, file=sys.stderr)
                time.sleep(5 * (attempt + 1))
        got = page.get("features", [])
        feats += got
        start += len(got)
        print(f"  {start} of {page.get('numberMatched', '?')}", file=sys.stderr)
        time.sleep(1)
        if len(got) < PAGE:
            return feats


def slim(f):
    p, g = f["properties"], f["geometry"]
    if p.get("etat_de_l_objet") not in (None, "En service") or p.get("construction_legere"):
        return None
    h = p.get("hauteur")
    if not h or h < 2.0:
        return None
    lo, hi = p.get("altitude_minimale_sol"), p.get("altitude_maximale_sol")
    ground = (lo + hi) / 2.0 if lo is not None and hi is not None else lo
    top = p.get("altitude_maximale_toit")
    prop = {"id": p["cleabs"], "h": round(h, 1)}
    if ground is not None and top is not None:
        ridge = top - ground
        if ridge > h + 1.0:
            prop["ridge"] = round(ridge, 1)
            prop["roof"] = "pitched"
    if p.get("nombre_d_etages"):
        prop["fl"] = p["nombre_d_etages"]
    yr = str(p.get("date_d_apparition") or "")[:4]
    if yr.isdigit():
        prop["yr"] = int(yr)

    def r(c):
        return [round(c[0], 6), round(c[1], 6)]
    if g["type"] == "Polygon":
        coords = [[r(c) for c in ring] for ring in g["coordinates"]]
    else:
        coords = [[[r(c) for c in ring] for ring in poly] for poly in g["coordinates"]]
    return {"type": "Feature", "properties": prop, "geometry": {"type": g["type"], "coordinates": coords}}


def main():
    box = tuple(float(v) for v in sys.argv[1].split(","))
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "cities", "data",
                       "fr_bdtopo_%s.geojson" % sys.argv[2])
    have = {}
    if os.path.exists(out):
        with open(out, encoding="utf-8") as fh:
            for f in json.load(fh)["features"]:
                have[f["properties"]["id"]] = f
    before = len(have)
    for f in fetch(box):
        s = slim(f)
        if s:
            have[s["properties"]["id"]] = s
    doc = {"type": "FeatureCollection",
           "source": "IGN BD TOPO (BDTOPO_V3:batiment, data.geopf.fr WFS), Licence Ouverte / Etalab 2.0",
           "features": list(have.values())}
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    print(f"{len(have)} buildings in {out} ({len(have) - before} new), "
          f"{os.path.getsize(out) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
