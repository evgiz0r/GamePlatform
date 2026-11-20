"""Radiance .hdr (RLE RGBE) -> the upper half as a tonemapped sRGB JPG, plus where its sun is
and the average colours of the zenith and the horizon (stored sRGB 0-1).
Usage: hdr_sky.py <in.hdr> <out.jpg> <width> [exposure scale]"""
import sys
import numpy as np
from PIL import Image

src, out, width = sys.argv[1], sys.argv[2], int(sys.argv[3])
# a 4th argument scales the exposure (the evening sky: 0.5, so it keeps its glow instead of
# being brought up to a day's brightness)
expo_k = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
data = open(src, 'rb').read()
pos = data.index(b'\n\n') + 2
line_end = data.index(b'\n', pos)
dims = data[pos:line_end].decode().split()
H, W = int(dims[1]), int(dims[3])
pos = line_end + 1
img = np.zeros((H, W, 4), dtype=np.uint8)
buf = memoryview(data)
for y in range(H):
    assert buf[pos] == 2 and buf[pos + 1] == 2, 'only new-style RLE'
    pos += 4
    for c in range(4):
        x = 0
        row = img[y, :, c]
        while x < W:
            n = buf[pos]; pos += 1
            if n > 128:
                n -= 128
                row[x:x + n] = buf[pos]; pos += 1
            else:
                row[x:x + n] = np.frombuffer(buf[pos:pos + n], dtype=np.uint8); pos += n
            x += n
e = img[:, :, 3].astype(np.int32)
scale = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)
rgb = img[:, :, :3].astype(np.float64) * scale[:, :, None]
lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
sy, sx = np.unravel_index(np.argmax(lum), lum.shape)
print('sun at u=%.4f v=%.4f (elevation %.1f deg)' % (sx / W, sy / H, 90 - sy / H * 180))
top = rgb[: H // 2]
tl = lum[: H // 2]
med = np.median(tl[tl < np.percentile(tl, 99)])
exposure = 0.32 / med * expo_k
x = top * exposure
aces = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)
aces = np.clip(aces, 0, 1)
srgb = np.where(aces <= 0.0031308, aces * 12.92, 1.055 * np.power(aces, 1 / 2.4) - 0.055)
out8 = (np.clip(srgb, 0, 1) * 255 + 0.5).astype(np.uint8)
im = Image.fromarray(out8, 'RGB').resize((width, width // 4), Image.LANCZOS)
im.save(out, quality=88)
a = np.asarray(im).astype(np.float64) / 255
h4 = a.shape[0]
print('zenith %s' % np.round(a[: h4 // 6].reshape(-1, 3).mean(0), 3))
print('horizon %s' % np.round(a[h4 - h4 // 12:].reshape(-1, 3).mean(0), 3))
print('mean %s' % np.round(a.reshape(-1, 3).mean(0), 3))
