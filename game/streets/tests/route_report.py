#!/usr/bin/env python3
"""The route set's results: a map of each drive and a line in the results log.

    python3 game/streets/tests/route_report.py results.txt out_dir [logs_dir]

results.txt holds the "ROUTE RESULT {...}" lines route_set.gd printed (any other lines are
ignored). For each route: its drive logs merged and drawn (drive_log_map.py, street names
on) to out_dir/route-<n>.png, titled with where from and to; and a dated block appended to
tests/routes_results.md (the git commit, then per route: arrived or not, minutes, km, hits,
the longest wait and what held it, red lights, rescues, seconds off the road) -- the
record to compare later runs of the same routes against.
"""
import datetime
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LOGS = os.path.expanduser("~/.local/share/godot/app_userdata/GamePlatform/drive_logs")


def merged_log(n, logs_dir):
    files = sorted(f for f in os.listdir(logs_dir) if f.startswith("route-%d-" % n) and f.endswith(".json"))
    if not files:
        return None
    logs = [json.load(open(os.path.join(logs_dir, f), encoding="utf-8")) for f in files]
    out = dict(logs[-1])
    seen, samples, events = set(), [], []
    for L in logs:
        for s in L["samples"]:
            if s["t"] not in seen:
                seen.add(s["t"])
                samples.append(s)
        for e in L["events"]:
            if e not in events:
                events.append(e)
    samples.sort(key=lambda s: s["t"])
    out["samples"], out["events"] = samples, events
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    res_file, out_dir = argv[0], argv[1]
    logs_dir = argv[2] if len(argv) > 2 else LOGS
    os.makedirs(out_dir, exist_ok=True)
    results = []
    for line in open(res_file, encoding="utf-8"):
        if "ROUTE RESULT " in line:
            results.append(json.loads(line.split("ROUTE RESULT ", 1)[1]))
    results.sort(key=lambda r: r["id"])
    commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True, cwd=HERE).stdout.strip()
    rows = []
    for r in results:
        n = r["id"]
        log = merged_log(n, logs_dir)
        if log:
            merged = os.path.join(out_dir, "route-%d.json" % n)
            json.dump(log, open(merged, "w", encoding="utf-8"))
            t0 = min(s["t"] for s in log["samples"])
            subprocess.run([sys.executable, os.path.join(HERE, "drive_log_map.py"), merged,
                            os.path.join(out_dir, "route-%d.png" % n), "--from", str(t0 + 2.5)], check=False,
                           capture_output=True)
        wait = ""
        if r["stills"]:
            w = max(r["stills"], key=lambda s: s[0])
            wait = "%.0f s (%s, %s)" % (w[0], w[1] or "?", w[3] or "a road")
        hits = "; ".join("%s at %d km/h on %s" % (h[0], h[1], h[3] or "a road") for h in r["hits"]) or "0"
        rows.append("| %d | %s | %s -> %s | %s | %.1f min | %.1f km | %s | %s | %d | %s | %.0f s |" % (
            n, r["city"], r["from"], r["to"], "yes" if r["arrived"] else ("**no way found**" if r.get("no_way") else "**no** (%d m left)" % r["left_m"]),
            r["secs"] / 60.0, r["metres"] / 1000.0, hits, wait or "-", r["reds"],
            ", ".join("%s at %d s" % (x[0], x[1]) for x in r["rescues"]) or "0", r["off_road_s"]))
    block = ["", "## %s (commit %s)" % (datetime.date.today().isoformat(), commit), "",
             "| # | city | from -> to | arrived | time | driven | hits | longest wait | reds | rescues | off road |",
             "|---|---|---|---|---|---|---|---|---|---|---|"] + rows
    path = os.path.join(HERE, "routes_results.md")
    if not os.path.exists(path):
        open(path, "w", encoding="utf-8").write("# The route set: results\n\nEach run of `run_routes.sh`, newest last. "
                              "The routes are in routes.json (picked by pick_routes.py).\n")
    open(path, "a", encoding="utf-8").write("\n".join(block) + "\n")
    print("\n".join(block))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
