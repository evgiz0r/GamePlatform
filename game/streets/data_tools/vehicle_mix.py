#!/usr/bin/env python3
"""The mix of vehicles on Israel's roads, from the Ministry of Transport's register of
licensed private and commercial vehicles on data.gov.il (dataset private-and-commercial-
vehicles, ~4.2 million rows). Its CSV files sit behind a CDN that refuses scripts, so this
reads an evenly spread sample through the official CKAN datastore API and writes only
shares: makes (and the top models of each), colours, year bands, fuel. No plate numbers or
anything else about a vehicle is kept.

    python3 game/streets/data_tools/vehicle_mix.py game/streets/cities/data/vehicle_mix.json
"""
import json, sys, time, urllib.parse, urllib.request
from collections import Counter, defaultdict

API = "https://data.gov.il/api/3/action/datastore_search"
RES = "053cea08-09bc-40ec-8f7a-156f0677aff3"
FIELDS = "tozeret_nm,kinuy_mishari,tzeva_rechev,shnat_yitzur,sug_degem,tokef_dt,sug_delek_nm"
PAGES, PER = 60, 5000
VALID_FROM = "2025-11-20"   # licence still valid in the last year: on the road now


def get(params):
    url = API + "?" + urllib.parse.urlencode(params)
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (vehicle mix summary)"})
            with urllib.request.urlopen(req, timeout=300) as r:
                return json.load(r)["result"]
        except Exception as e:
            print("retry", i, e, file=sys.stderr)
            time.sleep(10 * (i + 1))
    raise RuntimeError("datastore unreachable")


def shares(c, n, top=None):
    tot = sum(c.values())
    return [[k, round(v / tot, 4)] for k, v in c.most_common(top)] if tot else []


def main(out):
    total = get({"resource_id": RES, "limit": 0})["total"]
    make, colour, year, fuel, kind = Counter(), Counter(), Counter(), Counter(), Counter()
    models = defaultdict(Counter)
    seen = kept = 0
    for i in range(PAGES):
        off = int(i * (total - PER) / (PAGES - 1))
        rows = get({"resource_id": RES, "fields": FIELDS, "offset": off, "limit": PER})["records"]
        for r in rows:
            seen += 1
            if (r.get("tokef_dt") or "") < VALID_FROM:
                continue
            kept += 1
            m = (r.get("tozeret_nm") or "?").strip()
            make[m] += 1
            models[m][(r.get("kinuy_mishari") or "?").strip()] += 1
            colour[(r.get("tzeva_rechev") or "?").strip()] += 1
            y = r.get("shnat_yitzur") or 0
            year["-1999" if y < 2000 else "%d-%d" % (y - y % 5, y - y % 5 + 4)] += 1
            fuel[(r.get("sug_delek_nm") or "?").strip()] += 1
            kind[{"P": "private", "M": "commercial"}.get(r.get("sug_degem"), r.get("sug_degem") or "?")] += 1
        print(f"page {i + 1}/{PAGES} at {off}: {kept}/{seen}", file=sys.stderr)
        time.sleep(1)
    res = {
        "source": "Israel Ministry of Transport, licensed private and commercial vehicles "
                  "(data.gov.il dataset private-and-commercial-vehicles, resource " + RES + "), "
                  f"a sample of {seen} of {total} rows read through the CKAN datastore API in "
                  f"{PAGES} evenly spaced pages; only the {kept} whose licence runs to {VALID_FROM} "
                  "or later (on the road now) are counted",
        "licence": "data.gov.il open data (Other (Open)): free use with credit to the source",
        "credit": "vehicle mix: Israel Ministry of Transport, data.gov.il",
        "fetched": time.strftime("%Y-%m-%d"),
        "sample": kept,
        "kind": shares(kind, kept),
        "fuel": shares(fuel, kept),
        "colour": shares(colour, kept, 25),
        "year": sorted(shares(year, kept)),
        "make": [[m, s, shares(models[m], 0, 6)] for m, s in shares(make, kept, 40)],
    }
    with open(out, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, indent=1)
    print("wrote", out, file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
