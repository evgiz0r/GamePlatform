#!/usr/bin/env python3
"""Sum the game's [hitch] lines in a test's log, phase by phase (the test prints "PHASE x"):
how many, and the milliseconds each part took over all of them -- "rest" is the engine
(drawing, new meshes going up to the GPU, shaders compiling).
    python3 game/streets/tests/hitch_parts.py run.log [min_ms]"""
import re, sys, collections
log = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
least = float(sys.argv[2]) if len(sys.argv) > 2 else 250
phase = "load"
n = collections.Counter(); total = collections.Counter(); parts = collections.defaultdict(collections.Counter)
for line in log:
    if line.startswith("PHASE "):
        phase = line.split()[1]
        continue
    m = re.match(r"\[hitch\] [\d.]+ s\s+(\d+) ms \(usual (\d+)\)\s+(.*)", line)
    if not m or float(m.group(1)) < least:
        continue
    n[phase] += 1
    total[phase] += int(m.group(1))
    for w in m.group(3).split(" · "):
        k, _, v = w.rpartition(" ")
        if k and v.isdigit():
            parts[phase][k] += int(v)
for ph in n:
    top = ", ".join(f"{k} {v / 1000:.1f} s" for k, v in parts[ph].most_common(7))
    print(f"{ph:6s} {n[ph]:4d} hitches over {least:.0f} ms, {total[ph] / 1000:.1f} s in all: {top}")
