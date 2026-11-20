#!/usr/bin/env python3
"""How a camera shakes in a stretch of video: the image's shift from frame to frame (phase
correlation over the whole frame), summed into an angle across and an angle up and down, with
the walk's own slow turns taken out (a 1 s running mean). Prints each one's wobble (rms and
5-95% peak to peak, degrees), the rates it is strongest at (Hz) and how fast it moves.

For setting a filmed walk's hand-held phone against its film: run it on the film and on the
replay's recording over the same straight stretch (a corner turns the image too far between
frames to lock on, and the numbers there read tens of degrees of nonsense).

  film_shake.py <video> <from s> <to s> <deg per px across> <deg per px down> [ffmpeg filters first]
  # a phone film stored on its side, mirrored (the walk's clip): 43.1 deg across, 70 down
  film_shake.py clip.mp4 36 52 0.2694 0.35 hflip
  # the replay's frames, made into a video and cropped to the phone's shape
  ffmpeg -framerate 10 -pattern_type glob -i 'frames/*.jpg' -vf crop=406:720:437:0 game.mp4
  film_shake.py game.mp4 36 52 0.2694 0.35

The angles per pixel are for the frame scaled to 160 x 200 here: the field of view across and
down divided by 160 and 200. Needs numpy and ffmpeg. Keep the film out of the repo.
"""
import subprocess
import sys

import numpy as np

W, H = 160, 200
FPS = 30.0


def frames(vid, t0, t1, pre):
    vf = (pre + "," if pre else "") + f"fps={FPS:g},trim={t0}:{t1},setpts=PTS-STARTPTS,scale={W}:{H},format=gray"
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", vid, "-vf", vf, "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, H, W).astype(np.float32)


def shift(a, b, win):
    A = np.fft.fft2((a - a.mean()) * win)
    B = np.fft.fft2((b - b.mean()) * win)
    R = A * np.conj(B)
    R /= np.abs(R) + 1e-6
    r = np.fft.ifft2(R).real
    y, x = np.unravel_index(np.argmax(r), r.shape)

    def sub(c, m, p):   # sub-pixel: a parabola through the peak and its neighbours
        d = m - 2 * c + p
        return 0.0 if d == 0 else 0.5 * (m - p) / d
    fy = y + sub(r[y, x], r[(y - 1) % H, x], r[(y + 1) % H, x])
    fx = x + sub(r[y, x], r[y, (x - 1) % W], r[y, (x + 1) % W])
    return (fx - W if fx > W / 2 else fx), (fy - H if fy > H / 2 else fy)


def report(name, v):
    ang = np.cumsum(v)
    k = int(FPS)
    wob = (ang - np.convolve(ang, np.ones(k) / k, mode="same"))[k:-k]
    f = np.fft.rfftfreq(len(wob), 1 / FPS)
    P = np.abs(np.fft.rfft(wob * np.hanning(len(wob))))
    band = (f > 0.4) & (f < 4.0)
    top = np.argsort(P[band])[::-1][:3]
    print("%-6s wobble rms %.2f deg, peak to peak %.2f deg, strongest at %s Hz, speed rms %.1f deg/s" % (
        name, wob.std(), np.percentile(wob, 95) - np.percentile(wob, 5),
        ", ".join("%.2f" % x for x in f[band][top]), (v * FPS).std()))


def main():
    vid, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    dx, dy = float(sys.argv[4]), float(sys.argv[5])
    pre = sys.argv[6] if len(sys.argv) > 6 else ""
    fr = frames(vid, t0, t1, pre)
    win = np.outer(np.hanning(H), np.hanning(W))
    s = np.array([shift(fr[i + 1], fr[i], win) for i in range(len(fr) - 1)])
    print("%d frames, %.1f to %.1f s" % (len(fr), t0, t1))
    report("across", s[:, 0] * dx)
    report("down", s[:, 1] * dy)


if __name__ == "__main__":
    main()
