#!/usr/bin/env python3
"""The film's picture against a filmed walk's replay: brightness and colour, one frame a second
over the walk, and the grade that takes the replay's frames to the film's numbers -- the
numbers streets.gd's FILM_CURVE, FILM_WARM and FILM_SAT hold (`_film_look_layer`).

  film_look.py <film clip> <replay frames dir> [seconds]          # measure both, fit, print
  film_look.py <film clip> <replay frames dir> 96 --check         # measure only (a graded replay)

The clip is the phone's film of the walk (stored on its side and mirrored, as the side-by-side
takes it: hflip, 406x720); the frames are a recording (`RECORD=1 RES=1280x720 GODOT_ARGS=
"--fixed-fps 10" tests/run.sh filmed_walk <level>`), cropped to the phone's shape. Record the
replay to fit with STREETS_FILM_LOOK=0 (the game's own picture): fitting a graded replay fits
the grade on top of itself. Prints, for each: luminance and channel levels at 1-99%, the share
clipped to white and crushed to black, mean saturation, the near-greys' colour (white
balance), the top sixth (sky, upper walls) and the bottom third (the ground).

The fit: a tone curve at 17 points mapping the replay's luminance levels onto the film's, the
same on each channel; a fixed warmth on red that fades out over the brightest tones (fitted
freely it went to 16% and grey pavers went mauve; full strength on the pale sky read pink);
saturation scaled to the film's mean. Content differs (the game's materials are not the
street's), so read the numbers with the side-by-side open. Needs numpy and ffmpeg. Keep the
film out of the repo.
"""
import subprocess
import sys

import numpy as np

W, H = 203, 360
X = np.linspace(0, 1, 17)
WARM = 1.06
Q = [1, 5, 10, 25, 50, 75, 90, 95, 99]


def grab(args):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error"] + args + ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, H, W, 3).astype(np.float32) / 255.0


def film(clip, secs):
    return grab(["-i", clip, "-vf", f"hflip,scale=406:720,fps=30,trim=0:{secs},setpts=PTS-STARTPTS,fps=1,scale={W}:{H}"])


def replay(frames, secs):
    return grab(["-framerate", "10", "-pattern_type", "glob", "-i", f"{frames}/*.jpg", "-vf",
                 f"crop=406:720:437:0,fps=30,trim=0:{secs},setpts=PTS-STARTPTS,fps=1,scale={W}:{H}"])


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
    y = x * (1.0 + (np.array([WARM, 1.0, 1.0]) - 1.0) * (1.0 - t * t * (3 - 2 * t)))
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
    if "--check" in sys.argv:
        return
    curve, s = fit(f, g)
    print("FILM_CURVE := [" + ", ".join(f"{v:.3f}" for v in curve) + "]")
    print(f"FILM_WARM := {WARM}   FILM_SAT := {s:.3f}")
    stats("replay graded", grade(g, curve, s))


if __name__ == "__main__":
    main()
