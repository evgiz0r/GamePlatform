"""Build the streets game's leaf atlas: 2x2 cells of 512 px, each a cluster of leaves on
transparency, to be drawn on camera-facing cards. Cells: 0 broad leaves, 1 small narrow
leaves, 2 feathery (bipinnate) fronds, 3 needle sprays. Leaves are cut from Poly Haven
(CC0) photos on black; the needles are drawn. Prints each cell's mean colour (stored sRGB,
0-1, over the leaf pixels) for the shader."""
import sys, math, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

broad_src, frond_src, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
rnd = random.Random(7)

def keyed(path, lo=16, hi=40):
    im = Image.open(path).convert('RGB')
    r, g, b = im.split()
    mx = ImageChops.lighter(ImageChops.lighter(r, g), b)
    a = mx.point(lambda v: 0 if v <= lo else (255 if v >= hi else int((v - lo) * 255 / (hi - lo))))
    out = im.copy(); out.putalpha(a)
    return out

def components(rgba, min_px=300):
    """bounding boxes of the separate shapes (labelled on a 256 px mask)"""
    W, H = rgba.size
    small = rgba.getchannel('A').resize((256, 256), Image.BILINEAR)
    px = small.load()
    seen = [[False] * 256 for _ in range(256)]
    boxes = []
    for y in range(256):
        for x in range(256):
            if seen[y][x] or px[x, y] < 100:
                continue
            stack = [(x, y)]; seen[y][x] = True
            x0 = x1 = x; y0 = y1 = y; n = 0
            while stack:
                cx, cy = stack.pop(); n += 1
                x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < 256 and 0 <= ny < 256 and not seen[ny][nx] and px[nx, ny] >= 100:
                        seen[ny][nx] = True; stack.append((nx, ny))
            if n * (W / 256) * (H / 256) >= min_px:
                s = W / 256
                boxes.append((max(0, int(x0 * s) - 6), max(0, int(y0 * s) - 6), min(W, int((x1 + 1) * s) + 6), min(H, int((y1 + 1) * s) + 6)))
    return boxes

def sprites(path, keep=None):
    rgba = keyed(path)
    boxes = components(rgba)
    if keep:   # only the biggest shapes (whole fronds, not leaflets that broke off)
        boxes = sorted(boxes, key=lambda b: (b[2] - b[0]) * (b[3] - b[1]), reverse=True)[:keep]
    return [rgba.crop(b) for b in boxes]

def needle_spray(L=420, seed=0):
    """a twig with needles both sides, pointing up the image, drawn 2x and halved"""
    r = random.Random(seed)
    S = 2
    im = Image.new('RGBA', (int(L * 0.7) * S, L * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = im.width // 2
    base = (cx, im.height - 4)
    tip = (cx + r.randint(-20, 20) * S, 10 * S)
    def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    steps = 60
    for i in range(steps):
        t = i / steps
        p = lerp(base, tip, t)
        nl = (44 + 30 * math.sin(math.pi * min(1, t * 1.3))) * S * (1 - 0.45 * t)
        for side in (-1, 1):
            ang = math.radians(90 - side * (48 + r.uniform(-10, 10)))
            q = (p[0] + side * abs(math.cos(ang)) * nl, p[1] - math.sin(ang) * nl * 0.75)
            g = r.uniform(0.75, 1.1)
            col = (int(52 * g), int(84 * g), int(40 * g), 255)
            d.line([p, q], fill=col, width=4 * S)
    d.line([base, tip], fill=(92, 74, 50, 255), width=4 * S)
    return im.resize((im.width // S, im.height // S), Image.LANCZOS)

def cluster(cell, srcs, count, size, squeeze=1.0, radial=True, twigs=False, tint=(1, 1, 1), seed=1):
    r = random.Random(seed)
    canvas = Image.new('RGBA', (cell, cell), (0, 0, 0, 0))
    c = cell / 2
    R = cell * 0.44
    if twigs:   # thin branchlets from the middle out, under the leaves
        d = ImageDraw.Draw(canvas)
        for _ in range(6):
            a = r.uniform(0, math.tau)
            d.line([(c, c), (c + math.cos(a) * R * 0.5, c + math.sin(a) * R * 0.5)], fill=(70, 58, 42, 255), width=3)
    items = []
    for _ in range(count):
        # more of them toward the middle, but reaching the edge
        rr = max(0.0, R - size * 0.45) * math.sqrt(r.random())
        th = r.uniform(0, math.tau)
        x, y = c + math.cos(th) * rr, c + math.sin(th) * rr
        src = r.choice(srcs)
        sc = size / max(src.size) * r.uniform(0.75, 1.2)
        w, h = max(2, int(src.width * sc * squeeze)), max(2, int(src.height * sc))
        im = src.resize((w, h), Image.LANCZOS)
        # point the leaf outward (its tip is up in the source), with some scatter
        ang = (math.degrees(-th) - 90 if radial else r.uniform(0, 360)) + r.uniform(-35, 35)
        im = im.rotate(ang, resample=Image.BICUBIC, expand=True)
        bright = r.uniform(0.62, 1.12)
        warm = r.uniform(-0.06, 0.08)
        items.append((bright, im, x, y, warm))
    items.sort(key=lambda t: t[0])   # the darker (further in) first, the brighter on top
    for bright, im, x, y, warm in items:
        rch, gch, bch, ach = im.split()
        f = lambda k: (lambda v: min(255, int(v * k)))
        im = Image.merge('RGBA', (rch.point(f(bright * tint[0] * (1 + warm))), gch.point(f(bright * tint[1])),
                                  bch.point(f(bright * tint[2] * (1 - warm))), ach))
        canvas.alpha_composite(im, (int(x - im.width / 2), int(y - im.height / 2)))
    # a soft round edge well inside the cell: nothing is cut off square, and the mipmaps
    # of neighbouring cells never meet
    mask = Image.new('L', (cell, cell), 0)
    md = ImageDraw.Draw(mask)
    for k in range(24):
        rad = cell * 0.49 - k
        md.ellipse([c - rad, c - rad, c + rad, c + rad], fill=min(255, int(255 * k / 23)))
    a = ImageChops.multiply(canvas.getchannel('A'), mask)
    canvas.putalpha(a)
    return canvas

broad = sprites(broad_src)
fronds = sprites(frond_src, keep=3)
needles = [needle_spray(seed=s) for s in range(5)]
print('sprites', len(broad), len(fronds), file=sys.stderr)
cell = 512
atlas = Image.new('RGBA', (cell * 2, cell * 2), (0, 0, 0, 0))
cells = [
    cluster(cell, broad, 170, 56, twigs=True, seed=11),
    cluster(cell, broad, 300, 42, squeeze=0.42, twigs=True, seed=12),
    cluster(cell, fronds, 30, 190, seed=13),
    cluster(cell, needles, 64, 175, seed=14),
]
for i, im in enumerate(cells):
    atlas.alpha_composite(im, ((i % 2) * cell, (i // 2) * cell))
atlas.save(out_path)
for i, im in enumerate(cells):
    px = [p for p in im.get_flattened_data() if p[3] > 128]
    n = max(1, len(px))
    print('cell %d: Vector3(%.3f, %.3f, %.3f) cover %.2f' % (i, sum(p[0] for p in px) / n / 255, sum(p[1] for p in px) / n / 255,
          sum(p[2] for p in px) / n / 255, len(px) / (cell * cell)))
