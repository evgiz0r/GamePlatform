#!/usr/bin/env python3
"""Building heights for any Dutch town from 3DBAG (tudelft3d and 3DGI, CC BY 4.0): one shape
per BAG building (its lod12 layer) with the roof's height above the ground, the ridge, the
storeys, the roof type and the year built. All of these are measured from AHN laser scans.
The result goes in cities/data/nl_3dbag.geojson, which holds every Dutch town baked so far:
a new town's buildings are merged in by their BAG id, so the file only grows. The baker reads
it as the survey "nl_3dbag" (SURVEYS in tools/osm_city.py), so a second Dutch town needs only
this command, run with its own box, before its bake.

    python game/streets/data_tools/nl_3dbag.py S,W,N,E [game/streets/cities/data/nl_3dbag.geojson]

The server answers from anywhere (data.3dbag.nl, WFS 2.0, WGS84 GeoJSON out). Pages of 1000
buildings, a second apart.
"""
import json, os, sys, time, urllib.parse, urllib.request

WFS = "https://data.3dbag.nl/api/BAG3D/wfs"
PAGE = 1000


def fetch(box):
    s, w, n, e = box
    feats, start = [], 0
    while True:
        q = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": "BAG3D:lod12",
             "outputFormat": "application/json", "srsName": "EPSG:4326", "sortBy": "fid",
             "count": PAGE, "startIndex": start,
             "bbox": "%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % (s, w, n, e)}
        req = urllib.request.Request(WFS + "?" + urllib.parse.urlencode(q),
                                     headers={"User-Agent": "osm-city-bake/1 (a game kit's map baker)"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    page = json.load(r)
                break
            except Exception as ex:   # (a busy server: wait and ask again)
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
    """Only what the baker uses; coordinates to 1e-6 degrees (~0.1 m)."""
    p, g = f["properties"], f["geometry"]
    if p.get("status") not in (None, "Pand in gebruik", "Pand in gebruik (niet ingemeten)",
                               "Verbouwing pand"):
        return None   # (planned, being built, demolished: OSM's shape and a guess are better)
    ground = p.get("b3_h_maaiveld")
    top = p.get("b3_h_70p")
    if ground is None or top is None:
        return None

    def r(c):
        return [round(c[0], 6), round(c[1], 6)]
    if g["type"] == "Polygon":
        coords = [[r(c) for c in ring] for ring in g["coordinates"]]
    else:
        coords = [[[r(c) for c in ring] for ring in poly] for poly in g["coordinates"]]
    prop = {"id": p["identificatie"].rsplit(".", 1)[-1], "h": round(top - ground, 1)}
    if p.get("b3_h_nok") is not None:
        prop["ridge"] = round(p["b3_h_nok"] - ground, 1)
    if p.get("b3_bouwlagen"):
        prop["fl"] = p["b3_bouwlagen"]
    if p.get("oorspronkelijkbouwjaar"):
        prop["yr"] = p["oorspronkelijkbouwjaar"]
    if p.get("b3_dak_type"):
        prop["roof"] = p["b3_dak_type"]   # slanted, horizontal, multiple horizontal, ...
    return {"type": "Feature", "properties": prop, "geometry": {"type": g["type"], "coordinates": coords}}


def main():
    box = tuple(float(v) for v in sys.argv[1].split(","))
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(__file__), "..", "cities", "data", "nl_3dbag.geojson")
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
           "source": "3DBAG (3dbag.nl) by tudelft3d and 3DGI, CC BY 4.0; lod12, heights above ground",
           "features": list(have.values())}
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    print(f"{len(have)} buildings in {out} ({len(have) - before} new), "
          f"{os.path.getsize(out) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
