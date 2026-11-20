#!/usr/bin/env python3
"""The driving exam's scorecard as a picture: before and after, per city.

    python3 game/streets/tests/exam_chart.py out.png CITY:before.txt:after.txt [CITY:...]

Each .txt is the printed output of tests/exam.gd (the "EXAM ..." block). For every count
in either run, a row: the rate a minute before (blue) and after (orange), values printed
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
BEFORE = (57, 135, 229)   # series 1 (dark)
AFTER = (217, 89, 38)     # series 2 (dark)


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
        city, before, after = parts[0], parts[1], parts[2] if len(parts) > 2 else ""
        b, hb = parse(before)
        a, ha = parse(after)
        keys = sorted(set(b) | set(a))
        panels.append((city, keys, b, a, hb, ha))
    row_h, label_w, bar_w, pad = 34, 330, 420, 24
    height = 90 + sum(70 + len(k) * row_h for _, k, *_ in panels)
    W = label_w + bar_w + 150
    img = Image.new("RGB", (W, height), SURFACE)
    d = ImageDraw.Draw(img)
    f_title, f_lab, f_small = font(22), font(15), font(12)
    d.text((pad, 18), "Driving exam: problems a minute, before and after", font=f_title, fill=INK)
    # legend
    lx = pad
    for name, col in (("before", BEFORE), ("after", AFTER)):
        d.rounded_rectangle([lx, 56, lx + 14, 70], radius=3, fill=col)
        d.text((lx + 20, 54), name, font=f_lab, fill=INK2)
        lx += 100
    d.text((lx + 10, 56), "each row is scaled to itself: compare within a row", font=f_small, fill=INK2)
    y = 92
    for city, keys, b, a, hb, ha in panels:
        d.text((pad, y), city, font=f_title, fill=INK)
        sub = "  ".join(x for x in (hb.replace("EXAM ", "before: "), ha.replace("EXAM ", "after: ")) if x.strip() not in ("before:", "after:"))
        d.text((pad, y + 30), sub[:110], font=f_small, fill=INK2)
        y += 56
        for k in keys:
            vb, va = b.get(k), a.get(k)
            top = max(vb or 0, va or 0, 1e-6)
            d.text((pad, y + 8), k, font=f_lab, fill=INK)
            x0 = label_w
            d.line([x0, y + 2, x0, y + row_h - 4], fill=GRID, width=1)
            for i, (v, col) in enumerate(((vb, BEFORE), (va, AFTER))):
                by = y + 4 + i * 13
                if v is None:
                    d.text((x0 + 6, by - 2), "--", font=f_small, fill=INK2)
                    continue
                w = max(2, int(bar_w * v / top)) if v > 0 else 0
                if w:
                    d.rounded_rectangle([x0, by, x0 + w, by + 11], radius=4, fill=col)
                d.text((x0 + w + 6, by - 2), ("%.2f" % v).rstrip("0").rstrip(".") if v else "0", font=f_small, fill=INK)
            y += row_h
        y += 14
    img.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
