#!/usr/bin/env python3
"""A traced drive (tests/route_set.gd with TRACE=path) as rows for a chart: one object a
tenth of a second -- t, kmh, limit_kmh, why, street, accel, light, light_m, lead_m,
lead_kmh, lead_why, give_m, give_kmh -- under "rows", with "meta" on where it came from.

    TRACE=/tmp/t2.json ROUTE=2 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . \\
        -s res://game/streets/tests/route_set.gd
    python3 game/streets/tests/drive_trace.py /tmp/t2.json out.json

Without an output path it prints what held the car, the stops of 1.5 s or more and the
hardest braking (a knock -- over 8 km/h lost in a tenth of a second -- is a collision).
"""
import json
import sys
from collections import Counter


def rows_of(trace):
    ix = {c: i for i, c in enumerate(trace["columns"])}
    out = []
    for r in trace["rows"]:
        lead = r[ix["lead_m"]] >= 0
        give = r[ix["give_m"]] >= 0
        out.append({"t": r[ix["t"]], "kmh": r[ix["kmh"]], "limit_kmh": r[ix["limit_kmh"]], "why": r[ix["why"]] or "limit",
                    "street": r[ix["street"]], "accel": r[ix["accel"]], "light": r[ix["light"]],
                    "light_m": r[ix["light_m"]] if r[ix["light"]] else None,
                    "lead_m": r[ix["lead_m"]] if lead else None, "lead_kmh": r[ix["lead_kmh"]] if lead else None,
                    "lead_why": r[ix["lead_why"]] or None,
                    "give_m": r[ix["give_m"]] if give else None, "give_kmh": r[ix["give_kmh"]] if give else None})
    return out


def report(rows):
    n = len(rows)
    print("%.1f min; held by: %s" % (rows[-1]["t"] / 60, ", ".join("%s %d%%" % (k, v * 100 // n) for k, v in Counter(r["why"] for r in rows).most_common())))
    i = 0
    while i < n:
        if rows[i]["kmh"] >= 1:
            i += 1
            continue
        j = i
        while j < n and rows[j]["kmh"] < 1:
            j += 1
        secs = rows[j - 1]["t"] - rows[i]["t"] + 0.1
        if secs >= 1.5:
            mid = rows[i + (j - i) // 3]
            print("  stood %.1f s at %d:%02d, %s; car ahead %s (%s), light %s %s" % (secs, rows[i]["t"] // 60, rows[i]["t"] % 60, mid["why"], mid["lead_m"], mid["lead_why"], mid["light"], mid["light_m"]))
        i = j
    last = -10.0
    for i in range(5, n):
        a = (rows[i - 5]["kmh"] - rows[i]["kmh"]) / 3.6 / 0.5
        drop = rows[i - 1]["kmh"] - rows[i]["kmh"]
        if (a > 5.0 or drop > 8) and rows[i]["t"] - last > 2.0:
            last = rows[i]["t"]
            print("  %s %.1f m/s^2 at %d:%02d (%s, car ahead %s m at %s km/h, %s)" % ("knock" if drop > 8 else "brake", a, rows[i]["t"] // 60, rows[i]["t"] % 60, rows[i]["why"], rows[i]["lead_m"], rows[i]["lead_kmh"], rows[i]["lead_why"]))


if __name__ == "__main__":
    trace = json.load(open(sys.argv[1]))
    rows = rows_of(trace)
    if len(sys.argv) > 2:
        rt = trace["route"]
        meta = [{"label": "Recorded by", "value": "game/streets/tests/route_set.gd with TRACE (a row every 0.1 s of game time)"},
                {"label": "Route", "value": "%d: %s -> %s (%s)" % (rt["id"], rt["from"], rt["to"], rt["city"])}]
        json.dump({"rows": rows, "meta": meta}, open(sys.argv[2], "w"), ensure_ascii=False, separators=(",", ":"))
    else:
        report(rows)
