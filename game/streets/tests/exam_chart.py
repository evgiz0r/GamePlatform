#!/usr/bin/env python3
"""The driving exam's scorecard as a picture: up to three rounds, per city.

    python3 game/streets/tests/exam_chart.py out.png CITY:round1.txt:round2.txt[:round3.txt] [CITY:...]

Each .txt is the printed output of tests/exam.gd (the "EXAM ..." block). For every count
in any run, a row: the rate a minute in each round (blue, orange, aqua), values printed
at the ends. Each row has its own scale (the counts differ by hundreds of times), so read
the numbers, compare the bars only within a row. Needs Pillow.
"""
import re
import sys

from PIL import Image, ImageDraw, ImageFont

SURFACE = (26, 26, 25)
INK = (240, 239, 236)
INK2 = (195, 194, 183)
GRID = (56, 56, 53)
SERIES = [(57, 135, 229), (217, 89, 38), (25, 158, 112)]   # categorical slots 1-3 (dark)


def parse(path):
    rates, head = {}, ""
    if not path:
        return rates, head
    for line in open(path, encoding="utf-8"):
        if line.startswith("EXAM"):
            head = line.strip()
        m = re.match(r"\s+(\S.*?)\s{2,}(\d+)\s+([\d.]+) a minute", line)
        if m:
            rates[m.group(1)] = float(m.group(3))
    return rates, head


def font(size):
    for f in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf"]:
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    out = argv[0]
    panels = []
    for spec in argv[1:]:
        parts = spec.split(":")
        city, files = parts[0], [f for f in parts[1:4] if f]
        runs = [parse(f) for f in files]
        keys = sorted(set().union(*[set(r[0]) for r in runs]))
        panels.append((city, keys, runs))
    n_runs = max(len(p[2]) for p in panels)
    names = ["round %d" % (i + 1) for i in range(n_runs)] if n_runs > 2 else ["before", "after"][:n_runs]
    bar_h = 11
    row_h, label_w, bar_w, pad = 8 + n_runs * (bar_h + 2) + 6, 330, 420, 24
    height = 90 + sum(70 + len(k) * row_h for _, k, _ in panels)
    W = label_w + bar_w + 150
    img = Image.new("RGB", (W, height), SURFACE)
    d = ImageDraw.Draw(img)
    f_title, f_lab, f_small = font(22), font(15), font(12)
    d.text((pad, 18), "Driving exam: problems a minute, round by round", font=f_title, fill=INK)
    lx = pad
    for name, col in zip(names, SERIES):
        d.rounded_rectangle([lx, 56, lx + 14, 70], radius=3, fill=col)
        d.text((lx + 20, 54), name, font=f_lab, fill=INK2)
        lx += 100
    d.text((lx + 10, 56), "each row is scaled to itself: compare within a row", font=f_small, fill=INK2)
    y = 92
    for city, keys, runs in panels:
        d.text((pad, y), city, font=f_title, fill=INK)
        sub = "   ".join("%s: %s" % (nm, r[1].split(", ")[-1]) for nm, r in zip(names, runs) if r[1])
        d.text((pad, y + 30), sub[:120], font=f_small, fill=INK2)
        y += 56
        for k in keys:
            vals = [r[0].get(k) for r in runs]
            top = max([v or 0 for v in vals] + [1e-6])
            d.text((pad, y + row_h / 2 - 9), k, font=f_lab, fill=INK)
            x0 = label_w
            d.line([x0, y + 2, x0, y + row_h - 4], fill=GRID, width=1)
            for i, (v, col) in enumerate(zip(vals, SERIES)):
                by = y + 4 + i * (bar_h + 2)
                if v is None:
                    d.text((x0 + 6, by - 2), "--", font=f_small, fill=INK2)
                    continue
                w = max(2, int(bar_w * v / top)) if v > 0 else 0
                if w:
                    d.rounded_rectangle([x0, by, x0 + w, by + bar_h], radius=4, fill=col)
                d.text((x0 + w + 6, by - 2), ("%.2f" % v).rstrip("0").rstrip(".") if v else "0", font=f_small, fill=INK)
            y += row_h
        y += 14
    img.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
