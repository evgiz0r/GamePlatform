#!/usr/bin/env python3
"""The film's picture against a filmed walk's replay: brightness and colour, one frame a second
over the walk, and the grade that takes the replay's frames to the film's numbers -- the
numbers streets.gd's FILM_CURVE, FILM_WB, FILM_WARM and FILM_SAT hold (`_film_look_layer`).

  film_look.py <film clip> <replay frames dir> [seconds]          # measure both, fit, print
  film_look.py <film clip> <replay frames dir> 96 --check         # measure only (a graded replay)

The clip is the phone's film of the walk (stored on its side and mirrored, as the side-by-side
takes it: hflip, 406x720); the frames are a recording (`RECORD=1 RES=1280x720 GODOT_ARGS=
"--fixed-fps 10" tests/run.sh filmed_walk <level>`), cropped to the phone's shape. Record the
replay to fit with STREETS_FILM_LOOK=0 (the game's own picture): fitting a graded replay fits
the grade on top of itself. Keep the frames whole (1280x720): the meter reads the whole screen. Prints, for each: luminance and channel levels at 1-99%, the share
clipped to white and crushed to black, mean saturation, the near-greys' colour (white
balance), the top sixth (sky, upper walls) and the bottom third (the ground).

The fit: first the phone's auto-exposure -- each frame's whole-screen mean brightness (what
the shader's meter reads off the screen's mipmaps) pulled towards EXPO's target by
(target / mean)^strength, in light; then a tone curve at 17 points mapping the replay's
luminance levels onto the film's, the same on each channel; a fixed warmth on red that fades out over the brightest tones (fitted
freely it went to 16% and grey pavers went mauve; full strength on the pale sky read pink);
saturation scaled to the film's mean. Content differs (the game's materials are not the
street's), so read the numbers with the side-by-side open. Needs numpy and ffmpeg. Keep the
film out of the repo.
"""
import re
import subprocess
import sys

import numpy as np

W, H = 203, 360
X = np.linspace(0, 1, 17)
WARM = 1.0   # (1.06 until 22 Nov: the bare picture is as warm as the film now)
WB = (0.973, 1.0, 1.037)   # the phone's white balance on every tone: streets.gd's FILM_WB
EXPO = (0.45, 0.75, 0.6, 2.0)   # target, strength, least, most: streets.gd's FILM_EXPO
Q = [1, 5, 10, 25, 50, 75, 90, 95, 99]


def grab(args):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error"] + args + ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3).astype(np.float32) / 255.0


def film(clip, secs):
    return grab(["-i", clip, "-vf", f"hflip,scale=406:720,fps=30,trim=0:{secs},setpts=PTS-STARTPTS,fps=1,scale={W}:{H}"])


def seq(frames):
    """ffmpeg's input args for a folder of recorded frames, in name order. (A glob pattern is not
    in Windows' ffmpeg builds: the recording's own numbered names, f00001.jpg on, work everywhere.)"""
    import glob
    import os
    first = os.path.basename(sorted(glob.glob(f"{frames}/*.jpg"))[0])
    m = re.match(r"(\D*)(\d+)\.jpg$", first)
    return ["-start_number", str(int(m.group(2))), "-i", f"{frames}/{m.group(1)}%0{len(m.group(2))}d.jpg"]


def replay(frames, secs):
    return grab(["-framerate", "10"] + seq(frames) + ["-vf",
                 f"crop=406:720:437:0,fps=30,trim=0:{secs},setpts=PTS-STARTPTS,fps=1,scale={W}:{H}"])


def meter(frames, secs):
    """each second's whole-screen mean brightness, as the shader's meter reads it"""
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-framerate", "10"] + seq(frames) + ["-vf", f"fps=30,trim=0:{secs},setpts=PTS-STARTPTS,fps=1,scale=160:90",
                          "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    full = np.frombuffer(raw, np.uint8).reshape(-1, 90, 160, 3).astype(np.float32) / 255.0
    return lum(full).mean((1, 2))


def expose(x, m):
    target, k, lo, hi = EXPO
    gain = np.clip((target / np.maximum(m, 0.02)) ** k, lo, hi)
    return np.clip(((x ** 2.2) * gain[:, None, None, None]) ** (1 / 2.2), 0, 1)


def lum(x):
    return x[..., 0] * 0.2126 + x[..., 1] * 0.7152 + x[..., 2] * 0.0722


def sat(x):
    mx = x.max(-1)
    return np.where(mx > 1e-4, (mx - x.min(-1)) / np.maximum(mx, 1e-4), 0)


def greys(x):
    m = (sat(x) < 0.15) & (lum(x) > 0.25) & (lum(x) < 0.85)
    q = x[m]
    return q[:, 0].mean() / q[:, 1].mean(), q[:, 2].mean() / q[:, 1].mean(), m.mean()


def stats(name, x):
    L = lum(x).ravel()
    print(f"{name}: {len(x)} frames")
    print("  luminance " + " ".join(f"p{q}={np.percentile(L, q):.2f}" for q in Q))
    for c, n in enumerate("RGB"):
        print(f"  {n}         " + " ".join(f"p{q}={np.percentile(x[..., c].ravel(), q):.2f}" for q in Q))
    rg, bg, share = greys(x)
    print(f"  saturation {sat(x).mean():.3f}; clipped {np.mean(L > 0.97) * 100:.1f}%, black {np.mean(L < 0.04) * 100:.1f}%;"
          f" near-greys ({share * 100:.0f}%) R/G {rg:.3f} B/G {bg:.3f}")
    top, bot = x[:, : H // 6], x[:, 2 * H // 3:]
    print(f"  top sixth lum {lum(top).mean():.2f} sat {sat(top).mean():.3f};"
          f" bottom third lum {lum(bot).mean():.2f} p5 {np.percentile(lum(bot), 5):.2f} sat {sat(bot).mean():.3f}")


def grade(x, curve, s):
    """what the shader does, on the same 8-bit sRGB values it reads"""
    L0 = lum(x)[..., None]
    t = np.clip((L0 - 0.6) / 0.3, 0, 1)
    y = x * np.array(WB) * (1.0 + (np.array([WARM, 1.0, 1.0]) - 1.0) * (1.0 - t * t * (3 - 2 * t)))
    y = np.interp(np.clip(y, 0, 1), X, curve)
    L = lum(y)[..., None]
    return np.clip(L + (y - L) * s, 0, 1)


def fit(f, g):
    qs = np.linspace(0.5, 99.5, 60)
    curve, s = X.copy(), 1.0
    for _ in range(6):
        gq = np.concatenate([[0], np.percentile(lum(grade(g, X, 1.0)).ravel(), qs), [1]])
        fq = np.percentile(lum(f).ravel(), qs)
        fq = np.concatenate([[min(fq[0], 0.04)], fq, [max(fq[-1], 0.92)]])
        curve = np.maximum.accumulate(np.interp(X, gq, fq))
        curve = np.convolve(np.pad(curve, 1, mode="edge"), [0.25, 0.5, 0.25], mode="valid")
        s *= sat(f).mean() / sat(grade(g, curve, s)).mean()
    return curve, s


def main():
    clip, frames = sys.argv[1], sys.argv[2]
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 96
    f, g = film(clip, secs), replay(frames, secs)
    stats("film", f)
    stats("replay", g)
    mf, mg = lum(f).mean((1, 2)), lum(g).mean((1, 2))
    print(f"  each second's mean: film {mf.mean():.3f} +- {mf.std():.3f}, replay {mg.mean():.3f} +- {mg.std():.3f}"
          " (the phone's exposure holds it steady)")
    if "--check" in sys.argv:
        return
    g = expose(g, meter(frames, secs))
    curve, s = fit(f, g)
    print("FILM_CURVE := [" + ", ".join(f"{v:.3f}" for v in curve) + "]")
    print(f"FILM_WARM := {WARM}   FILM_SAT := {s:.3f}")
    out = grade(g, curve, s)
    stats("replay graded", out)
    mo = lum(out).mean((1, 2))
    print(f"  each second's mean graded: {mo.mean():.3f} +- {mo.std():.3f}")


if __name__ == "__main__":
    main()
