#!/usr/bin/env python3
"""Find frames with a thin bright line straight across them (tests/horizon_line.gd saves the
frames). For every row, the columns where the row is brighter than the rows K px above AND
below by more than DIFF -- K 2 for a line a pixel or two high (as a phone showed it), up to 24
for a band (as DROP= makes it here) -- never an edge between two areas; a row where that holds
across more than SHARE of the width, with an unbroken piece a tenth of the width long (leaves'
highlights pass the first test in short bits), is a line. The top eighth (the HUD's buttons) is left out.
Prints each frame's worst row.
    python3 game/streets/tests/horizon_line.py /tmp/line [DIFF=14] [SHARE=0.12]"""
import sys, glob, os
import numpy as np
from PIL import Image

d = sys.argv[1]
DIFF = float(sys.argv[2]) if len(sys.argv) > 2 else 14.0
SHARE = float(sys.argv[3]) if len(sys.argv) > 3 else 0.12
hits = 0
files = sorted(glob.glob(os.path.join(d, "l*.png")))
for f in files:
    im = np.asarray(Image.open(f).convert("L"), dtype=np.float32)
    h, w = im.shape
    best = (-1.0, 0, None)
    for k in (2, 6, 12, 24):
        a = im[k:-k]
        bright = (a - np.maximum(im[:-2 * k], im[2 * k:])) > DIFF
        share = bright.mean(axis=1)
        share[: max(0, h // 8 - k)] = 0.0   # (the HUD's buttons and score)
        i = int(np.argmax(share))
        if share[i] > best[0]:
            best = (float(share[i]), i + k, bright[i])
    s, y, row = best
    # how far across it runs, in one piece or several: the longest run of bright columns
    runs, cur = [], 0
    for v in row:
        cur = cur + 1 if v else 0
        runs.append(cur)
    tag = "LINE" if s > SHARE and max(runs) > w * 0.1 else ""
    if tag:
        hits += 1
    print("%s  row %4d of %d: %4.1f%% of the width, longest run %4d px %s" % (os.path.basename(f), y, h, s * 100, max(runs), tag))
print("%d of %d frames with a line" % (hits, len(files)))
