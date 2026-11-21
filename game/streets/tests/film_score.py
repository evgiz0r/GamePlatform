#!/usr/bin/env python3
"""How alike a filmed walk's replay and its film are, second by second: a score per second
and a chart over the whole walk, so a pass shows where it helped and a merge shows where it
hurt -- and the worst seconds first, side by side, as the next pass's list.

  film_score.py score <film frames> <game frames> <out dir> [walk seconds]
  film_score.py compare <before.csv> <after.csv> [out.png]

<film frames>: the film at 10 a second, the phone's frame upright (406x720 or any size of that
shape), named f00000.jpg from the walk's 0 s:
  ffmpeg -i <film> -vf "trim=0:96.6,setpts=PTS-STARTPTS,fps=10,scale=406:720" -start_number 0 f%05d.jpg
(the user's original film is upright and not mirrored; the emailed clip was mirrored: hflip it).
<game frames>: a recording (filmed_walk RECORD=1, 1280x720, --fixed-fps 10), f<tenths>.jpg;
the middle 406 columns are the phone's frame.

Each frame pair, both at 102x180 and grey unless said:
  * turn  -- degrees the replay faces right of the film (+: the game looks further right),
             from the far band's (top 55%) edges, phase-correlated across. A steady turn over
             seconds is the head or the route's line; a jump is a look the film has and the
             game not.
  * shape -- the edges' directions cell by cell (16 x 9 cells, 6 directions each, each cell
             scaled to itself) once that turn is taken out, correlated: 0 nothing alike, 1 the
             same. What stands where -- a wall the film does not have, a missing row of
             columns, the street's lines running another way. (Plain edge maps correlated
             read 0.07 over walk 1, film against replay: real footage's texture swamps them.)
  * light -- how alike the brightness is laid out over an 8x14 grid (correlation): shade,
             sky, a dark arcade.
  * colour -- the mean colour difference over a 4x6 grid (a rough CIE76 delta E: 0 alike,
             ~10 plainly off, 25+ a different scene): plaster that should be cream, a green
             hedge drawn grey.
  * score -- 100 * mean(shape, light, 1 - colour/40), each clipped to 0..1. What it means,
             measured on walk 1's film against itself: the film half a second on scores 67, a
             second on 55, two seconds on 45, thirty seconds on (a different place) 25. So a
             replay second at 45 is as alike as the film two seconds later; at 25, no more than
             any other street. (Walk 1's replay, 22 Nov 2026, before pass 15: 33.)
  * lag   -- per second (lag.csv): which film moment within 4 s the replay's frame looks most
             like, where that beats the same moment by 4+; runs of two seconds or more are
             printed -- the replay walking ahead of or behind its film there.
Seconds are the mean of their ten frames. The chart draws all four over the walk with the
score beneath; `worst.jpg` puts the eight worst seconds' film and game frames side by side.
Needs numpy and PIL (uv run --with numpy --with pillow python ...). Keep the film's frames
and these numbers out of the repo; the one-line summary is fine in notes.
"""
import csv
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

W, H = 102, 180
F = (H / 2) / math.tan(math.radians(35.0))   # focal length in these pixels (70 deg up and down)


def load(path, game):
    im = Image.open(path).convert("RGB")
    if game:   # the middle of a 16:9 recording: the phone's upright frame
        w, h = im.size
        cw = round(h * 406 / 720)
        im = im.crop(((w - cw) // 2, 0, (w - cw) // 2 + cw, h))
    return np.asarray(im.resize((W, H), Image.BILINEAR), dtype=np.float32) / 255.0


def grey(a):
    return a @ np.array([0.299, 0.587, 0.114], np.float32)


def lab(a):
    """a rough CIE Lab of sRGB values 0..1 (D65)"""
    c = np.where(a > 0.04045, ((a + 0.055) / 1.055) ** 2.4, a / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], np.float32)
    xyz = c @ m.T / np.array([0.9505, 1.0, 1.089], np.float32)
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def edges(g):
    gx = np.zeros_like(g)
    gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    gy[1:-1, :] = g[2:, :] - g[:-2, :]
    return np.hypot(gx, gy)


def blur(a, n=1):
    for _ in range(n):
        a = (np.roll(a, 1, 0) + a * 2 + np.roll(a, -1, 0)) / 4
        a = (np.roll(a, 1, 1) + a * 2 + np.roll(a, -1, 1)) / 4
    return a


def corr(a, b):
    a = a - a.mean()
    b = b - b.mean()
    d = math.sqrt(float((a * a).sum() * (b * b).sum()))
    return float((a * b).sum() / d) if d > 1e-9 else 0.0


def shift_across(a, b):
    """columns b sits right of a (phase correlation, rows averaged out to a 1D profile per row
    band and the bands' cross powers summed: robust to the two scenes' different detail)"""
    win = np.hanning(a.shape[1])[None, :]
    A = np.fft.fft(a * win, axis=1)
    B = np.fft.fft(b * win, axis=1)
    R = (A * np.conj(B)).sum(0)
    R /= np.abs(R) + 1e-9
    r = np.real(np.fft.ifft(R))
    k = int(np.argmax(r))
    if k > a.shape[1] // 2:
        k -= a.shape[1]
    return -k   # + : b's content is further left, i.e. b's camera looks further right


def roll_cols(a, k):
    out = np.zeros_like(a)
    if k > 0:
        out[:, :-k] = a[:, k:]
    elif k < 0:
        out[:, -k:] = a[:, :k]
    else:
        out = a.copy()
    return out


def grid_mean(a, gy, gx):
    h, w = a.shape[:2]
    return a[: h - h % gy, : w - w % gx].reshape(gy, h // gy, gx, w // gx, *a.shape[2:]).mean((1, 3))


def hog(g, cy=16, cx=9, bins=6):
    """edge directions per cell: how much edge runs each way in each of cy x cx cells, each
    cell scaled to its own total (so a sunlit wall and a shaded one with the same lines agree)"""
    gx = np.zeros_like(g)
    gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    gy[1:-1, :] = g[2:, :] - g[:-2, :]
    mag = np.hypot(gx, gy)
    ang = (np.arctan2(gy, gx) % math.pi) / math.pi * bins
    out = np.zeros((cy, cx, bins), np.float32)
    h, w = g.shape
    b = np.minimum(ang.astype(int), bins - 1)
    for k in range(bins):
        m = np.where(b == k, mag, 0.0)
        out[:, :, k] = m[: h - h % cy, : w - w % cx].reshape(cy, h // cy, cx, w // cx).sum((1, 3))
    return out / (np.linalg.norm(out, axis=-1, keepdims=True) + 0.02)


def pair(fa, ga):
    fg, gg = grey(fa), grey(ga)
    fe, ge = blur(edges(fg)), blur(edges(gg))
    band = slice(0, int(H * 0.55))
    k = shift_across(fe[band], ge[band])
    k = max(-30, min(30, k))
    turn = math.degrees(math.atan(k / F))
    ge2 = roll_cols(ge, k)   # the game's frame turned back onto the film's
    lo, hi = (0, W - k) if k > 0 else (-k, W)
    gg2 = roll_cols(gg, k)
    shape = max(0.0, corr(hog(fg[:, lo:hi]), hog(gg2[:, lo:hi])))
    light = max(0.0, corr(grid_mean(fg, 14, 8), grid_mean(gg, 14, 8)))
    colour = float(np.linalg.norm(grid_mean(lab(fa), 6, 4) - grid_mean(lab(ga), 6, 4), axis=-1).mean())
    score = 100 * (shape + light + max(0.0, 1 - colour / 40)) / 3
    return turn, shape, light, colour, score


def score(film_dir, game_dir, out, secs=None):
    os.makedirs(out, exist_ok=True)
    films = sorted(f for f in os.listdir(film_dir) if f.startswith("f") and f.endswith(".jpg"))
    rows = []
    for f in films:
        i = int(f[1:6])
        t = i / 10
        if secs and t > secs:
            break
        gp = os.path.join(game_dir, "f%05d.jpg" % i)
        if not os.path.exists(gp):
            continue
        rows.append((t,) + pair(load(os.path.join(film_dir, f), False), load(gp, True)))
    with open(os.path.join(out, "frames.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["t", "turn", "shape", "light", "colour", "score"])
        for r in rows:
            w.writerow([f"{r[0]:.1f}"] + [f"{v:.3f}" for v in r[1:]])
    per = {}
    for r in rows:
        per.setdefault(int(r[0]), []).append(r[1:])
    secrows = []
    for s in sorted(per):
        a = np.array(per[s])
        # the turn as the median (a frame's correlation can lock onto the wrong repeat)
        secrows.append((s, float(np.median(a[:, 0])), *[float(v) for v in a[:, 1:].mean(0)]))
    with open(os.path.join(out, "seconds.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["s", "turn", "shape", "light", "colour", "score"])
        for r in secrows:
            w.writerow([r[0]] + [f"{v:.3f}" for v in r[1:]])
    a = np.array([r[1:] for r in secrows])
    print("frames %d, seconds %d" % (len(rows), len(secrows)))
    print("walk: score %.1f  shape %.3f  light %.3f  colour %.1f  |turn| median %.1f deg, over 10 deg in %d s"
          % (a[:, 4].mean(), a[:, 1].mean(), a[:, 2].mean(), a[:, 3].mean(), np.median(np.abs(a[:, 0])),
             int((np.abs(a[:, 0]) > 10).sum())))
    # stretches of ten seconds: where to look first
    for s0 in range(0, int(secrows[-1][0]) + 1, 10):
        b = np.array([r[1:] for r in secrows if s0 <= r[0] < s0 + 10])
        if len(b):
            print("  %3d-%3d s: score %5.1f  shape %.2f  light %.2f  colour %4.1f  turn %+5.1f"
                  % (s0, s0 + 9, b[:, 4].mean(), b[:, 1].mean(), b[:, 2].mean(), b[:, 3].mean(), np.median(b[:, 0])))
    # the lag: which film moment each second of the replay looks most like, within 4 s either
    # way (its middle frame against the film's every half second) -- a stretch the replay walks
    # ahead of or behind its film. Only kept where it beats the same moment clearly.
    lags = []
    for r in secrows:
        i = int(r[0] * 10 + 5)
        gp = os.path.join(game_dir, "f%05d.jpg" % i)
        if not os.path.exists(gp):
            continue
        g = load(gp, True)
        best = (-1.0, 0.0)
        at0 = None
        for k in range(-8, 9):
            fp = os.path.join(film_dir, "f%05d.jpg" % (i + k * 5))
            if not os.path.exists(fp):
                continue
            sc = pair(load(fp, False), g)[4]
            if k == 0:
                at0 = sc
            best = max(best, (sc, k * 0.5))
        lags.append((r[0], best[1] if at0 is not None and best[0] > at0 + 4 else 0.0, best[0]))
    with open(os.path.join(out, "lag.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["s", "lag", "best score"])
        for r in lags:
            w.writerow([r[0], r[1], f"{r[2]:.1f}"])
    run = []
    for s_, lg, _ in lags + [(None, 0.0, 0)]:
        if run and (lg == 0.0 or (lg > 0) != (run[0][1] > 0)):
            if len(run) >= 2:
                print("  the replay looks like the film %+.1f s on (%s) at %d-%d s" % (np.median([x[1] for x in run]),
                      "the film is ahead: the replay is late there" if np.median([x[1] for x in run]) > 0 else
                      "the film is behind: the replay is early there", run[0][0], run[-1][0]))
            run = []
        if lg != 0.0:
            run.append((s_, lg))
    worst = sorted(secrows, key=lambda r: r[5])[:8]
    print("worst seconds:", ", ".join("%d (%.0f)" % (r[0], r[5]) for r in sorted(worst)))
    chart([secrows], ["this run"], os.path.join(out, "chart.png"))
    sheet(film_dir, game_dir, [r[0] for r in sorted(worst)], os.path.join(out, "worst.jpg"))


def read(path):
    with open(path) as fh:
        return [tuple(float(v) for v in r) for r in list(csv.reader(fh))[1:]]


def chart(runs, names, path):
    Wd, Hp = 1200, 150
    names_y = ["turn (deg)", "shape", "light", "colour (dE)", "score"]
    ranges = [(-30, 30), (0, 1), (0, 1), (0, 40), (0, 100)]
    im = Image.new("RGB", (Wd, Hp * 5 + 30), (18, 18, 24))
    d = ImageDraw.Draw(im)
    end = max(r[-1][0] for r in runs) + 1
    cols = [(90, 200, 255), (255, 120, 160), (140, 255, 140)]
    for p in range(5):
        y0 = p * Hp + 10
        lo, hi = ranges[p]
        d.rectangle([50, y0, Wd - 10, y0 + Hp - 20], outline=(70, 70, 90))
        d.text((4, y0 + 2), names_y[p], fill=(200, 200, 200))
        d.text((4, y0 + Hp - 32), str(lo), fill=(120, 120, 120))
        d.text((4, y0 + 14), str(hi), fill=(120, 120, 120))
        if lo < 0:
            yz = y0 + (Hp - 20) * hi / (hi - lo)
            d.line([50, yz, Wd - 10, yz], fill=(60, 60, 70))
        for s in range(0, int(end) + 1, 10):
            x = 50 + (Wd - 60) * s / end
            d.line([x, y0, x, y0 + Hp - 20], fill=(45, 45, 55))
            if p == 4:
                d.text((x - 6, y0 + Hp - 18), "%d s" % s, fill=(150, 150, 150))
        for k, run in enumerate(runs):
            pts = []
            for r in run:
                v = min(hi, max(lo, r[p + 1]))
                pts.append((50 + (Wd - 60) * (r[0] + 0.5) / end, y0 + (Hp - 20) * (hi - v) / (hi - lo)))
            d.line(pts, fill=cols[k % 3], width=2)
    for k, n in enumerate(names):
        d.text((Wd - 260 + k * 120, 2), n, fill=cols[k % 3])
    im.save(path)


def sheet(film_dir, game_dir, secs, path):
    tiles = []
    for s in secs:
        i = int(s * 10 + 5)
        fp = os.path.join(film_dir, "f%05d.jpg" % i)
        gp = os.path.join(game_dir, "f%05d.jpg" % i)
        if not (os.path.exists(fp) and os.path.exists(gp)):
            continue
        a = Image.open(fp).convert("RGB").resize((203, 360))
        g = Image.open(gp).convert("RGB")
        w, h = g.size
        cw = round(h * 406 / 720)
        g = g.crop(((w - cw) // 2, 0, (w - cw) // 2 + cw, h)).resize((203, 360))
        t = Image.new("RGB", (410, 378), (0, 0, 0))
        t.paste(a, (0, 18))
        t.paste(g, (207, 18))
        ImageDraw.Draw(t).text((4, 3), "%.1f s   film | game" % (i / 10), fill=(255, 255, 255))
        tiles.append(t)
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    out = Image.new("RGB", (410 * cols, 378 * rows), (0, 0, 0))
    for k, t in enumerate(tiles):
        out.paste(t, ((k % cols) * 410, (k // cols) * 378))
    out.save(path, quality=88)


def compare(a, b, path=None):
    ra, rb = read(a), read(b)
    da = {int(r[0]): r for r in ra}
    db = {int(r[0]): r for r in rb}
    both = sorted(set(da) & set(db))
    d = np.array([[db[s][5] - da[s][5], abs(db[s][1]) - abs(da[s][1])] for s in both])
    print("score %.1f -> %.1f (%+.1f); |turn| median %.1f -> %.1f deg"
          % (np.mean([da[s][5] for s in both]), np.mean([db[s][5] for s in both]), d[:, 0].mean(),
             np.median([abs(da[s][1]) for s in both]), np.median([abs(db[s][1]) for s in both])))
    worse = [(s, db[s][5] - da[s][5]) for s in both if db[s][5] - da[s][5] < -5]
    better = [(s, db[s][5] - da[s][5]) for s in both if db[s][5] - da[s][5] > 5]
    print("worse by 5+:", ", ".join("%d (%+.0f)" % w for w in worse) or "none")
    print("better by 5+:", ", ".join("%d (%+.0f)" % w for w in better) or "none")
    if path:
        chart([ra, rb], ["before", "after"], path)


if __name__ == "__main__":
    if len(sys.argv) >= 5 and sys.argv[1] == "score":
        score(sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5]) if len(sys.argv) > 5 else None)
    elif len(sys.argv) >= 4 and sys.argv[1] == "compare":
        compare(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    else:
        print(__doc__)
        sys.exit(2)
