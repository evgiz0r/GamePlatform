#!/usr/bin/env python3
"""How a walk's camera moves, frame by frame over the whole walk, from its video alone: which
way it faces (the head's turns), how far up or down it looks, and how fast it walks. For
setting a filmed walk's looks and pace beside its film -- measured on the film and on the
replay's recording the same way, then drawn one over the other.

  film_motion.py film <clip> <seconds> <out.csv>             # the phone's film (hflip, 406x720)
  film_motion.py frames <frames dir> <seconds> <out.csv>     # a replay's recording (10 a second)
  film_motion.py log <camera log> <out.csv>                  # the replay's camera as logged
                                                             # (filmed_walk CAMERA_LOG=1): exact
  film_motion.py chart <film.csv> <game.csv> <out.png> [from to]   # the two drawn together

Every frame of the film (30 a second: a turn is a few pixels a frame, which phase correlation
follows; one frame a second loses it). Each pair of frames gives three shifts:
  * the far band (rows above the horizon to just under it: fronts and roofs, tens of metres
    off) across -- the head turning (yaw) -- and up and down (pitch);
  * the ground band (the frame's bottom quarter, ~40 degrees down) up and down. Walking
    forward slides the ground down the frame; turning the phone up or down slides everything
    alike, so the ground's slide less the far band's (scaled for where each band sits in a
    pinhole's frame) is the walking: a metre forward moves a ground point at depression theta
    by f sin^2(theta) / (h cos^2(alpha)) pixels (h the phone's height, alpha the row's angle
    off the frame's middle).
The far band's shifts summed give the facing relative to the start (it drifts a little over a
minute: compare stretches, or line the two up on a straight stretch, as `chart` does on the
passage, 36-52 s). The speed is rough (the walker's own shadow and feet slide with the
camera and pull the ground's shift toward nothing): read it as a profile -- where the walk
slows and hurries -- and scale it to the landmarks' times.

Measure the replay by its CAMERA_LOG rather than its recording: at 10 frames a second its
pavers' pattern repeats within a frame's slide and the ground's shift locks onto the wrong
repeat (it read 0.2 m/s for 1.4). And the film's far band is ground, not fronts, while the
phone looks down (the walk's `looks` with a pitch): walking then reads as looking down
(its pitch trace drifts there), and the speed's scale is off -- read those stretches by eye.

The frame is the phone's shape at half size, 203 x 360: 70 degrees down it, 43.1 across, its
horizon 0.30 of the way down (streets.gd FILM_TILT). Needs numpy, ffmpeg and (for the chart)
PIL. Keep the film, its frames and its numbers out of the repo.
"""
import csv
import math
import subprocess
import sys

import numpy as np


def film_look_seq(frames):
    """ffmpeg's input args for a folder of recorded frames (film_look.py's seq: no glob on Windows)"""
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from film_look import seq
    return seq(frames)

W, H = 203, 360
F = (H / 2) / math.tan(math.radians(35.0))   # focal length, pixels
TILT = 15.6                                    # degrees the phone looks down (FILM_TILT)
EYE = 1.45                                     # metres: the phone's height
FAR = (0, 216)                                 # rows: the far band (the frame's top 60%)
GROUND = (250, 350)                            # rows: the ground band
COLS = 3                                       # each band read as this many tiles across, two
                                               # rows of them up the far band: the median of
                                               # their shifts (a car passing fills a tile or two,
                                               # and alone would drag the reading with it)


def grab(args):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error"] + args + ["-f", "rawvideo", "-pix_fmt", "gray", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, H, W).astype(np.float32)


def shift(a, b):
    """(x, y) b moved by to give a, sub-pixel, by phase correlation"""
    h, w = a.shape
    win = np.outer(np.hanning(h), np.hanning(w))
    A = np.fft.fft2((a - a.mean()) * win)
    B = np.fft.fft2((b - b.mean()) * win)
    R = A * np.conj(B)
    R /= np.abs(R) + 1e-6
    r = np.fft.ifft2(R).real
    y, x = np.unravel_index(np.argmax(r), r.shape)

    def sub(c, m, p):
        d = m - 2 * c + p
        return 0.0 if d == 0 else 0.5 * (m - p) / d
    fy = y + sub(r[y, x], r[(y - 1) % h, x], r[(y + 1) % h, x])
    fx = x + sub(r[y, x], r[y, (x - 1) % w], r[y, (x + 1) % w])
    return (fx - w if fx > w / 2 else fx), (fy - h if fy > h / 2 else fy)


def measure(fr, fps):
    a_far = math.atan(((FAR[0] + FAR[1]) / 2 - H / 2) / F)
    a_gr = math.atan(((GROUND[0] + GROUND[1]) / 2 - H / 2) / F)
    theta = math.radians(TILT) + a_gr
    px_per_m = F * math.sin(theta) ** 2 / (EYE * math.cos(a_gr) ** 2)
    pitch_scale = math.cos(a_far) ** 2 / math.cos(a_gr) ** 2
    rows = []
    cw = W // COLS
    fh = (FAR[1] - FAR[0]) // 2
    far_tiles = [(FAR[0] + k * fh, FAR[0] + (k + 1) * fh, c * cw, (c + 1) * cw) for k in range(2) for c in range(COLS)]
    gr_tiles = [(GROUND[0], GROUND[1], c * cw, (c + 1) * cw) for c in range(COLS)]
    for i in range(len(fr) - 1):
        a, b = fr[i + 1], fr[i]
        fs = np.array([shift(a[r0:r1, c0:c1], b[r0:r1, c0:c1]) for r0, r1, c0, c1 in far_tiles])
        gs = np.array([shift(a[r0:r1, c0:c1], b[r0:r1, c0:c1]) for r0, r1, c0, c1 in gr_tiles])
        fx, fy = np.median(fs[:, 0]), np.median(fs[:, 1])
        gy = np.median(gs[:, 1])
        yaw = -math.degrees(math.atan(fx / F))           # + right
        pitch = -math.degrees(math.atan(fy / F)) * math.cos(a_far) ** 2   # + up
        walk = (gy - fy * pitch_scale) / px_per_m         # metres forward this frame
        rows.append(((i + 1) / fps, yaw, pitch, walk * fps))
    return rows


def write(rows, out):
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t", "yaw_rate", "pitch_rate", "speed"])
        for t, y, p, s in rows:
            w.writerow([f"{t:.3f}", f"{y:.4f}", f"{p:.4f}", f"{s:.4f}"])
    yaw = np.cumsum([r[1] for r in rows])
    sp = np.array([r[3] for r in rows])
    print(f"{len(rows)} frame pairs; facing at the end {yaw[-1]:.0f} deg from the start; speed median {np.median(sp):.2f} m/s")


def load(path):
    with open(path) as f:
        r = list(csv.DictReader(f))
    t = np.array([float(x["t"]) for x in r])
    dt = np.diff(np.concatenate([[0.0], t]))
    yaw = np.cumsum([float(x["yaw_rate"]) for x in r])
    pitch = np.cumsum([float(x["pitch_rate"]) for x in r])
    sp = np.array([float(x["speed"]) for x in r])
    return t, yaw, pitch, sp, dt


def smooth(t, v, win):
    out = np.empty_like(v)
    for i, x in enumerate(t):
        m = np.abs(t - x) <= win / 2
        out[i] = np.median(v[m])
    return out


def chart(fcsv, gcsv, out, t0, t1):
    from PIL import Image, ImageDraw
    ft, fyaw, fp, fs, _ = load(fcsv)
    gt, gyaw, gp, gs, _ = load(gcsv)
    # line the facings up on the passage, where both walk straight down it
    fm = (ft > 36) & (ft < 52)
    gm = (gt > 36) & (gt < 52)
    gyaw = gyaw - np.median(gyaw[gm]) + np.median(fyaw[fm])
    gp = gp - np.median(gp[gm]) + np.median(fp[fm])
    fs, gs = smooth(ft, fs, 1.0), smooth(gt, gs, 1.0)
    Wc, Hp, pad = 1600, 260, 60
    img = Image.new("RGB", (Wc, pad + 3 * (Hp + pad)), "white")
    d = ImageDraw.Draw(img)
    X = lambda t: pad + (t - t0) / (t1 - t0) * (Wc - 2 * pad)
    panels = [("facing (deg, + right)", fyaw, gyaw, None), ("looking up (deg)", fp, gp, None),
              ("walking (m/s, 1 s median)", fs, gs, (0.0, 3.0))]
    for k, (name, fv, gv, rng) in enumerate(panels):
        top = pad + k * (Hp + pad)
        sel_f = (ft >= t0) & (ft <= t1)
        sel_g = (gt >= t0) & (gt <= t1)
        lo, hi = rng if rng else (min(fv[sel_f].min(), gv[sel_g].min()), max(fv[sel_f].max(), gv[sel_g].max()))
        if hi - lo < 1e-6:
            hi = lo + 1
        Y = lambda v: top + Hp - (v - lo) / (hi - lo) * Hp
        d.rectangle([pad, top, Wc - pad, top + Hp], outline=(200, 200, 200))
        d.text((pad + 6, top + 4), name + f"  [{lo:.1f} .. {hi:.1f}]", fill=(0, 0, 0))
        for s in range(int(t0), int(t1) + 1, 5):
            d.line([X(s), top, X(s), top + Hp], fill=(235, 235, 235))
            d.text((X(s) - 6, top + Hp + 4), f"{s}", fill=(90, 90, 90))
        for (tt, vv, col) in ((ft[sel_f], fv[sel_f], (30, 90, 200)), (gt[sel_g], gv[sel_g], (220, 90, 30))):
            pts = [(X(a), Y(b)) for a, b in zip(tt, vv)]
            if len(pts) > 1:
                d.line(pts, fill=col, width=2)
    d.text((Wc - 300, 16), "blue: phone's film   orange: game", fill=(0, 0, 0))
    img.save(out)
    print("wrote", out)


def game_log(path):
    """a CAMERA_LOG from tests/filmed_walk.gd -- the replay's own camera, exact -- as rates
    per row, like a measured film (its pace from where it stands)"""
    rows, prev = [], None
    with open(path) as f:
        for line in f:
            if not line.startswith("CAM "):
                continue
            t, yaw, pitch, x, z = (float(v) for v in line.split()[1:6])
            if prev is not None and t > prev[0]:
                dt = t - prev[0]
                dyaw = (yaw - prev[1] + 180.0) % 360.0 - 180.0
                rows.append((t, dyaw, pitch - prev[2], math.hypot(x - prev[3], z - prev[4]) / dt))
            prev = (t, yaw, pitch, x, z)
    return rows


def main():
    mode = sys.argv[1]
    if mode == "film":
        secs = float(sys.argv[3])
        fr = grab(["-i", sys.argv[2], "-vf", f"hflip,scale=406:720,fps=30,trim=0:{secs},setpts=PTS-STARTPTS,scale={W}:{H}"])
        write(measure(fr, 30.0), sys.argv[4])
    elif mode == "frames":
        secs = float(sys.argv[3])
        fr = grab(["-framerate", "10"] + film_look_seq(sys.argv[2]) + ["-vf",
                   f"crop=406:720:437:0,trim=0:{secs},setpts=PTS-STARTPTS,scale={W}:{H}"])
        write(measure(fr, 10.0), sys.argv[4])
    elif mode == "log":
        write(game_log(sys.argv[2]), sys.argv[3])
    elif mode == "chart":
        t0 = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
        t1 = float(sys.argv[6]) if len(sys.argv) > 6 else 96.0
        chart(sys.argv[2], sys.argv[3], sys.argv[4], t0, t1)


if __name__ == "__main__":
    main()
