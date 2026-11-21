#!/usr/bin/env python3
"""Street trees and lamp posts for any Dutch town from the BGT (Basisregistratie Grootschalige
Topografie, the national large-scale map every municipality keeps; served by PDOK as an OGC
API, CC0). They are merged into two national extracts that only grow:

    cities/data/nl_bgt_trees.json   {"rows": [[lon, lat, ""], ...]}      (TREE_SURVEYS "nl_bgt_trees")
    cities/data/nl_bgt_lamps.json   {"rows": [[lon, lat, "lichtmast", 1], ...]}  (TOWN_LAYERS "nl_bgt")

    python game/streets/data_tools/nl_bgt.py S,W,N,E

The BGT keeps every past version of an object, so only those with no end of registration
(`eind_registratie`) are taken: about 1 in 6 rows of a page is an old version. Rows are keyed
by the object's lokaal_id, so re-running a box replaces rather than doubles.

The BGT has more that the game could use later, in the same API: road parts as polygons
(wegdeel: carriageway, footway, cycle path, with their paving), kerb-side furniture
(straatmeubilair: bike racks, benches, bollards), poles (paal: sign and signal poles), signs
(bord), water (waterdeel), bridges (overbruggingsdeel).
"""
import json, os, sys, time, urllib.parse, urllib.request

API = "https://api.pdok.nl/lv/bgt/ogc/v1/collections/%s/items"
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "cities", "data")


def fetch(collection, box):
    s, w, n, e = box
    url = API % collection + "?" + urllib.parse.urlencode(
        {"f": "json", "limit": 1000, "bbox": "%f,%f,%f,%f" % (w, s, e, n)})
    rows = []
    while url:
        req = urllib.request.Request(url, headers={"User-Agent": "osm-city-bake/1 (a game kit's map baker)"})
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
        rows += page.get("features", [])
        url = next((l["href"] for l in page.get("links", []) if l.get("rel") == "next"), None)
        print(f"  {collection}: {len(rows)}", file=sys.stderr)
        time.sleep(0.5)
    return [f for f in rows if not f["properties"].get("eind_registratie")]


def point(f):
    g = f["geometry"]
    c = g["coordinates"] if g["type"] == "Point" else g["coordinates"][0]
    return round(c[0], 6), round(c[1], 6)


def merge(name, meta, new_rows):
    path = os.path.join(DATA, name)
    have = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            old = json.load(fh)
        have = dict(zip(old.get("ids", []), old["rows"]))
    before = len(have)
    have.update(new_rows)
    doc = dict(meta, ids=list(have.keys()), rows=list(have.values()))
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    print(f"{name}: {len(have)} ({len(have) - before} new)")


def main():
    box = tuple(float(v) for v in sys.argv[1].split(","))
    day = time.strftime("%Y-%m-%d")
    src = "BGT via PDOK (api.pdok.nl/lv/bgt/ogc/v1), CC0; current objects only; fetched " + day
    trees = {f["properties"]["lokaal_id"]: [*point(f), ""]
             for f in fetch("vegetatieobject_punt", box) if f["properties"].get("plus_type") == "boom"}
    merge("nl_bgt_trees.json", {"source": src, "licence": "CC0", "credit": "trees, lamp posts © BGT via PDOK",
                                "fields": ["lon", "lat", "species"]}, trees)
    lamps = {f["properties"]["lokaal_id"]: [*point(f), "lichtmast", 1]
             for f in fetch("paal", box) if f["properties"].get("plus_type") == "lichtmast"}
    merge("nl_bgt_lamps.json", {"source": src, "licence": "CC0", "credit": "trees, lamp posts © BGT via PDOK",
                                "fields": ["lon", "lat", "type", "lamps"]}, lamps)


if __name__ == "__main__":
    main()
