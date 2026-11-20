#!/usr/bin/env python3
"""A filmed walk's pace and head turns, fitted to its film: reads what film_motion.py measured
on the film and the replay's CAMERA_LOG (filmed_walk.gd), and writes the walk's retimed points
and its head track for the details generator to take in.

  film_fit.py <film.csv> <camera log> <anchors> <from> <out.json>
  # walk 1: the crossing (0-17 s) stays as set from its frames; from the far kerb on
  film_fit.py film.csv camlog.txt 17,25.6,33,64,80,87,91.5,96 17 cities/details/katzenelson_fit.json

The pace: between each two anchors (seconds the walk keeps -- its landmarks), the walk goes
the replay's own way (its path as logged, every 0.1 s) but at the film's pace: where the film
has walked a share of that stretch's distance, the walk has walked the same share of its own
(the replay's streets are not the street's lengths, so the shares, not the metres). The film's
speed is a 1 s median, under 0.15 m/s a stop; points every 0.5 s; where that would take
the walk past VMAX (a stretch the replay has longer than the street), blended towards an even
pace as far as it takes.
The head: the film's facing (summed frame to frame; lined up with the replay's camera on the
passage, 36-52 s, where both walk straight down it) less the body's facing on the new points
-- the body worked out as streets.gd's _film_tick does it (the way to where the walk is 1.6 s
on, eased) -- every 0.25 s, a 0.5 s median, 0.15 s early for the head's easing in.

Needs numpy. The film's numbers stay out of the repo; the fitted walk is the replay's own
path and the film's timing, as the hand-timed points were.
"""
import json
import math
import sys

import numpy as np

VMAX = 2.6   # m/s: the most the walk goes at, however its film hurries


def film_rates(path):
    import csv
    with open(path) as f:
        r = list(csv.DictReader(f))
    t = np.array([float(x["t"]) for x in r])
    return t, np.cumsum([float(x["yaw_rate"]) for x in r]), np.array([float(x["speed"]) for x in r])


def cam_log(path):
    rows = []
    with open(path) as f:
        for line in f:
            if line.startswith("CAM "):
                rows.append([float(v) for v in line.split()[1:8]])
    a = np.array(rows)
    return a[:, 0], a[:, 1], a[:, 3], a[:, 4]   # t, camera yaw (deg), x, z


def median_win(t, v, win):
    return np.array([np.median(v[np.abs(t - x) <= win / 2]) for x in t])


def unwrap_deg(v):
    return np.degrees(np.unwrap(np.radians(v)))


def catmull(pts, t):
    """streets.gd _film_at: Catmull-Rom through [t, x, z] points, holding where two are one"""
    n = len(pts)
    if t <= pts[0][0]:
        return np.array(pts[0][1:])
    if t >= pts[-1][0]:
        return np.array(pts[-1][1:])
    i = 0
    while i < n - 2 and pts[i + 1][0] <= t:
        i += 1
    a, b, c, d = (np.array(pts[max(i - 1, 0)][1:]), np.array(pts[i][1:]), np.array(pts[i + 1][1:]),
                  np.array(pts[min(i + 2, n - 1)][1:]))
    if np.linalg.norm(b - c) < 0.05:
        return b
    if np.linalg.norm(a - b) < 0.05:
        a = b - (c - b)
    if np.linalg.norm(c - d) < 0.05:
        d = c + (c - b)
    u = (t - pts[i][0]) / max(pts[i + 1][0] - pts[i][0], 0.001)
    return 0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u + (-a + 3 * b - 3 * c + d) * u ** 3)


def body_yaw(pts, t_end, dt=1 / 60):
    """_film_tick's body facing over the walk: towards where it is 1.6 s on, eased at 2.2 /s"""
    p0, p15 = catmull(pts, 0.0), catmull(pts, 1.5)
    yaw = math.atan2(p15[1] - p0[1], p15[0] - p0[0])
    out_t, out_y = [], []
    t = 0.0
    while t <= t_end:
        t += dt
        p, ahead = catmull(pts, t), catmull(pts, t + 1.6)
        if np.linalg.norm(ahead - p) > 0.3:
            want = math.atan2(ahead[1] - p[1], ahead[0] - p[0])
            d = (want - yaw + math.pi) % (2 * math.pi) - math.pi
            yaw += d * (1 - math.exp(-dt * 2.2))
        out_t.append(t)
        out_y.append(math.degrees(yaw))
    return np.array(out_t), np.array(out_y)


def main():
    fcsv, clog, anchors, t_from, out = sys.argv[1], sys.argv[2], [float(a) for a in sys.argv[3].split(",")], float(sys.argv[4]), sys.argv[5]
    ft, fyaw, fsp = film_rates(fcsv)
    gt, gyaw, gx, gz = cam_log(clog)
    gyaw = unwrap_deg(gyaw)
    # the replay's path by distance
    seg = np.hypot(np.diff(gx), np.diff(gz))
    gs = np.concatenate([[0.0], np.cumsum(seg)])
    v = np.clip(median_win(ft, fsp, 1.0), 0.0, 3.0)
    v[v < 0.15] = 0.0
    pts = []
    for a, b in zip(anchors, anchors[1:]):
        ts = np.arange(a, b, 0.5)
        m = (ft >= a) & (ft <= b)
        dist_f = np.concatenate([[0.0], np.cumsum(v[m][:-1] * np.diff(ft[m]))]) if m.sum() > 1 else None
        sa, sb = np.interp(a, gt, gs), np.interp(b, gt, gs)
        # the film's shares, blended towards an even pace as far as needed to keep the walk
        # under VMAX (where the replay's stretch is longer than the street's, the film's
        # quick moments would read as a run)
        film_share = (lambda t: (t - a) / (b - a)) if dist_f is None or dist_f[-1] < 0.5 else \
            (lambda t: np.interp(t, ft[m], dist_f) / dist_f[-1])
        fine = np.linspace(a, b, int((b - a) * 20) + 1)
        lam = 1.0
        while lam > 0:
            sh = lam * np.array([film_share(t) for t in fine]) + (1 - lam) * (fine - a) / (b - a)
            if (np.diff(sh) * (sb - sa) / np.diff(fine)).max() <= max(VMAX, 1.1 * (sb - sa) / (b - a)):
                break
            lam -= 0.05
        for t in ts:
            share = lam * film_share(t) + (1 - lam) * (t - a) / (b - a)
            s = sa + (sb - sa) * share
            t_old = np.interp(s, gs, gt) if sb > sa else a
            pts.append([round(float(t), 2), round(float(np.interp(t_old, gt, gx)), 2), round(float(np.interp(t_old, gt, gz)), 2)])
    pts.append([anchors[-1], round(float(np.interp(anchors[-1], gt, gx)), 2), round(float(np.interp(anchors[-1], gt, gz)), 2)])
    # stops: points within 3 cm of the last are the same point (a wait, as _film_at reads it)
    for i in range(1, len(pts)):
        if math.dist(pts[i][1:], pts[i - 1][1:]) < 0.03:
            pts[i][1:] = pts[i - 1][1:]
    # the head: the film's facing, lined up on the passage, less the body's on these points
    # (the walk before t_from as the replay has it: its own logged path)
    m_f = (ft > 36) & (ft < 52)
    m_g = (gt > 36) & (gt < 52)
    fyaw_al = fyaw - np.median(fyaw[m_f]) + np.median(gyaw[m_g])
    before = [[round(float(t), 2), float(x), float(z)] for t, x, z in zip(gt, gx, gz) if t < t_from - 0.05][::5]
    bt, by = body_yaw(before + pts, anchors[-1])
    head = []
    for t in np.arange(t_from, anchors[-1] + 0.01, 0.25):
        w = (ft > t + 0.15 - 0.25) & (ft < t + 0.15 + 0.25)
        if not w.any():
            continue
        h = float(np.median(fyaw_al[w])) - float(np.interp(t, bt, by))
        h = (h + 180.0) % 360.0 - 180.0
        head.append([round(float(t), 2), round(max(-100.0, min(100.0, h)), 1)])
    json.dump({"points": pts, "head": head}, open(out, "w"), indent=0)
    print(f"{len(pts)} points from {pts[0][0]} to {pts[-1][0]} s, {len(head)} head samples, the head "
          f"{min(h[1] for h in head):.0f} to {max(h[1] for h in head):.0f} deg; wrote {out}")


if __name__ == "__main__":
    main()
