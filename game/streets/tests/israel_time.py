#!/usr/bin/env python3
"""Checks the build stamp's Israel clock (streets.gd israel_time, via israel_time.gd) against
zoneinfo's Asia/Jerusalem at times either side of every summer-time change, 2025-2030.
    GODOT=... python3 game/streets/tests/israel_time.py      prints "all match" or each miss"""
import os, subprocess, sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
il = ZoneInfo("Asia/Jerusalem")
times = []
for y in range(2025, 2031):
    t = datetime(y, 1, 1, tzinfo=timezone.utc)
    prev = t.astimezone(il).utcoffset()
    while t.year == y:   # hour by hour: each change, and the minutes round it
        off = t.astimezone(il).utcoffset()
        if off != prev:
            for m in (-61, -1, 0, 1, 59):
                times.append(t + timedelta(minutes=m))
        prev = off
        t += timedelta(hours=1)
    times += [datetime(y, 1, 15, 12, 0, tzinfo=timezone.utc), datetime(y, 7, 15, 22, 30, tzinfo=timezone.utc)]
env = dict(os.environ, TIMES=";".join(t.strftime("%Y-%m-%d %H:%M") for t in times))
out = subprocess.run([os.environ.get("GODOT", "godot"), "--headless", "--path", ".", "-s",
                      "res://game/streets/tests/israel_time.gd"], env=env, capture_output=True, text=True).stdout
got = {l.split(" -> ")[0][3:]: l.split(" -> ")[1] for l in out.splitlines() if l.startswith("IL ")}
bad = 0
for t in times:
    k = t.strftime("%Y-%m-%d %H:%M")
    a = t.astimezone(il)
    want = "%d %s %02d:%02d Israel" % (a.day, a.strftime("%b"), a.hour, a.minute)
    if got.get(k) != want:
        bad += 1
        print("miss: %s UTC -> game %s, zoneinfo %s" % (k, got.get(k), want))
print("all match (%d times)" % len(times) if bad == 0 else "%d of %d differ" % (bad, len(times)))
sys.exit(1 if bad else 0)
