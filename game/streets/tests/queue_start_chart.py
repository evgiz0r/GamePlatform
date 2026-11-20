#!/usr/bin/env python3
"""A queue pulling away at a green light, drawn: tests/queue_start.gd's queue_start.json.

    python3 game/streets/tests/queue_start_chart.py queue_start.json out.png [run number]

Speed against time from the moment the light went green, one line per car in the queue,
the front car first (darkest blue) to the back (lightest): a queue that pulls away car
after car fans out; one that moves off all at once is a single line. Picks the run with
the longest queue unless told which. Needs Pillow.
"""
import json
import sys

from PIL import Image, ImageDraw, ImageFont

SURFACE = (26, 26, 25)
INK = (240, 239, 236)
INK2 = (195, 194, 183)
GRID = (56, 56, 53)
# one hue, light to dark (sequential): the queue's order
RAMP = [(31, 79, 145), (40, 102, 184), (57, 135, 229), (98, 160, 235), (140, 186, 241), (180, 210, 247), (210, 228, 250)]


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    data = json.load(open(argv[0]))
    runs = data["runs"]
    if not runs:
        print("no queues recorded")
        return 1
    run = runs[int(argv[2]) - 1] if len(argv) > 2 else max(runs, key=lambda r: len(r["cars"]))
    W, H, L, B, T = 900, 520, 70, 60, 70
    img = Image.new("RGB", (W, H), SURFACE)
    d = ImageDraw.Draw(img)
    f_t, f, f_s = font(22), font(15), font(13)
    d.text((20, 16), "A queue pulling away at a green light (%s)" % data.get("city", ""), font=f_t, fill=INK)
    d.text((20, 44), "speed of each car in the queue, from the moment the light turned green", font=f_s, fill=INK2)
    pw, ph = W - L - 160, H - T - B
    top_v = 50.0

    def X(t):
        return L + t / 12.0 * pw

    def Y(v):
        return T + ph - min(v, top_v) / top_v * ph
    for v in (0, 10, 20, 30, 40, 50):
        d.line([L, Y(v), L + pw, Y(v)], fill=GRID)
        d.text((L - 34, Y(v) - 8), "%d" % v, font=f_s, fill=INK2)
    for t in range(0, 13, 2):
        d.text((X(t) - 8, T + ph + 8), "%d s" % t, font=f_s, fill=INK2)
    d.text((10, T - 22), "km/h", font=f_s, fill=INK2)
    cars = run["cars"]
    for n, (pos, kind, sp) in enumerate(cars):
        col = RAMP[min(n, len(RAMP) - 1)]
        pts = [(X(k * 0.1), Y(v)) for k, v in enumerate(sp) if v >= 0 and k * 0.1 <= 12.0]
        if len(pts) > 1:
            d.line(pts, fill=col, width=3)
            d.text((pts[-1][0] + 8, pts[-1][1] - 8), "%d. %s" % (pos, kind), font=f, fill=INK)
    img.save(argv[1])
    print(argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
