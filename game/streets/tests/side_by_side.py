#!/usr/bin/env python3
"""Two pictures side by side, each under a title and a one-line note -- a drive before and
after a fix, for the user to compare at a glance.

    python3 game/streets/tests/side_by_side.py out.png \\
        before.png "First test drive: 390 s" "stuck 2 minutes at the start" \\
        after.png  "Now: 235 s, no hits" "longest wait 16 s, behind a car"

The note under the first title is drawn in a warm colour, under the second in a cool one
(what was wrong, what is right). Each picture is scaled to 900 px wide. Needs Pillow.
"""
import sys

from PIL import Image, ImageDraw, ImageFont


def _font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def main(argv):
    if len(argv) != 7:
        print(__doc__)
        return 1
    out = argv[0]
    panes = [(argv[1], argv[2], argv[3], (240, 160, 140)), (argv[4], argv[5], argv[6], (150, 220, 170))]
    W = 900
    ims = []
    for path, *_ in panes:
        im = Image.open(path)
        ims.append(im.resize((W, int(im.height * W / im.width))))
    H = max(im.height for im in ims) + 90
    img = Image.new("RGB", (W * 2 + 20, H), (26, 26, 25))
    d = ImageDraw.Draw(img)
    f, fs = _font(26), _font(18)
    for i, (im, (_, title, note, col)) in enumerate(zip(ims, panes)):
        x = i * (W + 20)
        img.paste(im, (x, 90))
        d.text((x + 10, 10), title, font=f, fill=(240, 239, 236))
        d.text((x + 10, 46), note, font=fs, fill=col)
    img.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
