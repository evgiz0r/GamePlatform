#!/usr/bin/env python3
"""Two builds' shader programs, as a browser got them (tests/web_shaders.js DUMP=file.json):
how many of the second build's programs the first already had, byte for byte. A browser
keeps the programs it compiled (its program cache, keyed by the source), so only the
changed ones are compiled again after a publish -- on a phone, the "getting the graphics
ready" steps. For the changed ones, the first lines that differ from the nearest old one.

  python3 game/streets/tests/shader_diff.py old.json new.json
"""
import difflib
import json
import sys

a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
old = {p['text'] for p in a}
new = [p for p in b if p['text'] not in old]
print(f"programs: {len(a)} then {len(b)}; of the second's, {len(b) - len(new)} the same as the first's, {len(new)} new or changed")
by = {}
for p in new:
    by.setdefault(p['names'] or '-', []).append(p)
for k, ps in sorted(by.items(), key=lambda kv: -len(kv[1])):
    print(f"  {len(ps):4d}  {k}   ({', '.join(sorted({p['phase'] for p in ps}))})")
shown = 0
for p in new:
    if shown >= int(sys.argv[3] if len(sys.argv) > 3 else 3):
        break
    near = max(a, key=lambda q: (q['names'] == p['names'], q['defs'] == p['defs'], -abs(q['len'] - p['len'])))
    d = [l for l in difflib.unified_diff(near['text'].split('\n'), p['text'].split('\n'), lineterm='', n=0)
         if not l.startswith(('---', '+++', '@@'))]
    print(f"\n{p['names']} [{p['defs']}]: {len(d)} lines differ from the nearest old one")
    for l in d[:12]:
        print('   ' + l[:160])
    shown += 1
