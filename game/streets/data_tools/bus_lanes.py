#!/usr/bin/env python3
"""Public-transport priority lanes (נתיבי העדפה קיימים) from the Ministry of Transport on
data.gov.il (dataset nataz_kayam, CC BY), for each level's box: one record per stretch with
its start and end point (the CSV has no line between them; snap to the city's roads by
street name), direction, hours and who may use it.

    python3 game/streets/data_tools/bus_lanes.py game/streets/cities/data/bus_lanes.json
"""
import json, os, sys, time, urllib.parse, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
import itm

API = "https://data.gov.il/api/3/action/datastore_search"
RES = "a853e465-b435-445c-b38b-26fadd795df5"
BOXES = {   # (S, W, N, E), the city files' boxes
    "givatayim": (32.0561, 34.7952, 32.0842, 34.8234),
    "ashdod": (31.7507, 34.6061, 31.8752, 34.7130),
    "tel_aviv": (32.0576, 34.7579, 32.0872, 34.8037),
}
YES = {"כן": 1, "לא": 0}


def main(out):
    rows, off = [], 0
    while True:
        q = {"resource_id": RES, "offset": off, "limit": 500}
        req = urllib.request.Request(API + "?" + urllib.parse.urlencode(q), headers={"User-Agent": "Mozilla/5.0 (bus lanes extract)"})
        with urllib.request.urlopen(req, timeout=120) as r:
            res = json.load(r)["result"]
        rows += res["records"]
        off += len(res["records"])
        if not res["records"] or off >= res["total"]:
            break
        time.sleep(1)
    towns = {k: [] for k in BOXES}
    for r in rows:
        if not r.get("LON_START") or not r.get("LAT_START"):
            continue
        a = itm.to_lonlat(r["LON_START"], r["LAT_START"])   # (the CSV's LON/LAT are ITM x/y)
        b = itm.to_lonlat(r["LON_END"], r["LAT_END"]) if r.get("LON_END") else a
        for town, (s, w, n, e) in BOXES.items():
            if any(s <= p[1] <= n and w <= p[0] <= e for p in (a, b)):
                hours = {k: [r.get("FRHR_" + k), r.get("TOHR_" + k)] for k in ("WK", "WK_2", "FRI", "FRI_2", "SAT")
                         if r.get("FRHR_" + k)}
                towns[town].append({
                    "name": r.get("PTLNAME"), "street": r.get("STREETNAME") or r.get("ROADNAME"),
                    "from": r.get("START_"), "to": r.get("FINISH"), "dir": r.get("PTLDIR"),
                    "a": [round(a[0], 6), round(a[1], 6)], "b": [round(b[0], 6), round(b[1], 6)],
                    "len_m": r.get("LENGT"), "lanes": r.get("NUMLANES"), "type": r.get("PTLTYPE"),
                    "status": r.get("STATUS"), "hours": hours or "always",
                    "taxi": YES.get(r.get("TAXI")), "brt": YES.get(r.get("BRT")),
                    "paint": r.get("PAINT"), "division": r.get("DIVISION"),
                })
    res = {"source": "Israel Ministry of Transport, existing public-transport priority lanes "
                     "(data.gov.il dataset nataz_kayam, resource " + RES + "), via the CKAN datastore API; "
                     "points converted from ITM (EPSG:2039), within ~1 m",
           "licence": "Creative Commons Attribution (CC BY)",
           "credit": "bus lanes: Israel Ministry of Transport (CC BY)",
           "fetched": time.strftime("%Y-%m-%d"), "rows": len(rows),
           "counts": {k: len(v) for k, v in towns.items()}, "towns": towns}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(res, f, ensure_ascii=False, separators=(",", ":"))
    print(res["counts"], len(rows))


if __name__ == "__main__":
    main(sys.argv[1])
