#!/usr/bin/env python3
"""A made-up block of flats from a seed: a typical floor (the stairwell and lift in the
middle, two or four flats around it, light wells between back-to-back flats) and the front
of the whole building (the entrance floor on columns, the floors, the penthouse, the roof).

    python3 lab/apartments/building.py --seed 3      # out/building_3_floor.png, _front.png
    python3 lab/apartments/building.py --sheet 1-4   # floors of four buildings on one picture

The flats come from plan.py, forced to line their entrances up on the stairwell: each front
door opens onto the landing. With four flats a floor, the back pair is the front pair turned
round, and the strip between them that the stairwell does not fill is an open light well
(the back rooms' windows look into it).
"""
import argparse
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

import plan as P_
from plan import DM, FONT, FONT_B, INK, Plan, draw_labels, render

OUT = P_.OUT
ENT = 20          # every flat's entrance is 2 m wide, so the stairwell is 4 m wide
LANDING = 12      # the landing the front doors open onto
STAIR_RUN = 37    # a flight of steps (2.5 m) and the half-landing (1.2 m)
CONCRETE = (120, 116, 112)
WELL = (214, 218, 214)


class Building:
    def __init__(self, seed):
        self.seed = seed
        g = self.rng = random.Random(seed * 7919 + 1)
        self.per_floor = g.choice([2, 4, 4])
        self.floors = g.randint(4, 8)          # typical floors over the entrance floor
        self.penthouse = g.random() < 0.75
        wa, wb = g.randint(105, 125), g.randint(105, 125)
        self.wa, self.wb = wa, wb
        self.core_x = (wa - ENT, wa + ENT)
        two = self.per_floor == 2
        self.G = LANDING + STAIR_RUN if two else LANDING + STAIR_RUN + LANDING
        # flats: (plan, origin (dm), turned round?)
        self.flats = []
        s = seed * 100
        a = Plan(s + 1, W=wa, ent_w=ENT, mirror=True, party=("x1",)).build()
        b = Plan(s + 2, W=wb, ent_w=ENT, mirror=False, party=("x0",)).build()
        self.flats.append((a, (0, 0), False))
        self.flats.append((b, (wa, 0), False))
        if not two:
            # turned round: local (x, y) -> (ox - x, oy - y)
            c = Plan(s + 3, W=wa, ent_w=ENT, mirror=False, party=("x0",)).build()
            d = Plan(s + 4, W=wb, ent_w=ENT, mirror=True, party=("x1",)).build()
            self.flats.append((c, (wa, -self.G), True))
            self.flats.append((d, (wa + wb, -self.G), True))

    def xf(self, f):
        p, (ox, oy), turned = f
        if turned:
            return lambda x, y: (ox - x, oy - y)
        return lambda x, y: (ox + x, oy + y)

    def bounds(self):
        xs, ys = [], []
        for f in self.flats:
            p = f[0]
            t = self.xf(f)
            for (x, y) in ((0, 0), (p.W, p.H)):
                gx, gy = t(x, y)
                xs.append(gx)
                ys.append(gy)
        ys.append(-self.G)
        return min(xs), min(ys), max(xs), max(ys)

    def flat_count(self):
        return self.per_floor * self.floors + (2 if self.penthouse else 0)

    def title(self):
        return "building %d  ·  %d flats a floor  ·  %d floors%s over columns  ·  %d flats" % (
            self.seed, self.per_floor, self.floors, " + penthouses" if self.penthouse else "",
            self.flat_count())


# --------------------------------------------------------------------- floor
def render_floor(b, scale=40, title=True):
    pad = 40
    top = 64 if title else pad
    x0, y0, x1, y1 = b.bounds()
    Wpx = int((x1 - x0) * DM * scale) + 2 * pad
    Hpx = int((y1 - y0) * DM * scale) + top + pad
    img = Image.new("RGBA", (Wpx, Hpx), (250, 250, 247, 255))
    dr = ImageDraw.Draw(img)
    f_room = ImageFont.truetype(FONT_B, max(9, int(scale * 0.24)))
    f_small = ImageFont.truetype(FONT, 11)
    f_title = ImageFont.truetype(FONT_B, 16)

    def P(x, y):
        return (pad + (x - x0) * DM * scale, top + (y - y0) * DM * scale)

    def R(ax, ay, bx, by, **kw):
        p0, p1 = P(min(ax, bx), min(ay, by)), P(max(ax, bx), max(ay, by))
        dr.rectangle([p0, p1], **kw)

    cx0, cx1 = b.core_x
    G = b.G
    four = b.per_floor == 4
    # light wells (four a floor) / back yard strip
    if four:
        for (a_, c_) in ((0, cx0), (cx1, b.wa + b.wb)):
            R(a_, -G, c_, 0, fill=WELL)
            for gx in range(int(a_) + 3, int(c_), 6):
                for gy in range(-G + 3, 0, 6):
                    q = P(gx, gy)
                    dr.point(q, fill=(170, 178, 170))
            m = P((a_ + c_) / 2, -G / 2)
            dr.text((m[0] - 24, m[1] - 6), "light well", font=f_small, fill=(110, 120, 110))

    # the flats, each drawn on its own and pasted in (turned round when it is)
    PADF = 12
    for f in b.flats:
        p, (ox, oy), turned = f
        im = render(p, scale=scale, title=False, labels=False, stair_hint=False, pad=PADF, bg=None)
        if turned:
            im = im.rotate(180)
            at = P(ox, oy)
            pos = (round(at[0] - (im.width - PADF)), round(at[1] - (im.height - PADF)))
        else:
            at = P(ox, oy)
            pos = (round(at[0] - PADF), round(at[1] - PADF))
        img.alpha_composite(im, dest=(max(0, pos[0]), max(0, pos[1])),
                            source=(max(0, -pos[0]), max(0, -pos[1])))

    # the stairwell: landings, two flights, the lift
    R(cx0, -G, cx1, 0, fill=(236, 234, 230))
    sx0 = cx0 + 1
    sx1 = sx0 + 23
    ey = -LANDING
    fl0, fl1 = ey - 25, ey     # flights between the landing and the half-landing
    # treads
    for k in range(12):
        yy = fl1 - (k + 1) * 25 / 12
        dr.line([P(sx0, yy), P(sx0 + 11, yy)], fill=(150, 146, 140))
        dr.line([P(sx0 + 12, yy), P(sx1, yy)], fill=(150, 146, 140))
    R(sx0 + 11, fl0, sx0 + 12, fl1, fill=CONCRETE)  # the wall between the flights
    # up-arrow on the first flight
    a0, a1 = P(sx0 + 5.5, fl1 - 2), P(sx0 + 5.5, fl0 + 2)
    dr.line([a0, a1], fill=INK, width=2)
    dr.polygon([(a1[0] - 4, a1[1] + 6), (a1[0] + 4, a1[1] + 6), (a1[0], a1[1])], fill=INK)
    dr.text((P(sx0 + 1, fl1 - 4)[0], P(sx0 + 1, fl1 - 4)[1]), "up", font=f_small, fill=INK)
    # the lift: a shaft by the landing, its doors onto it
    lx0, lx1 = sx1 + 1, cx1 - 1
    ly0, ly1 = ey - 16, ey
    R(lx0, ly0, lx1, ly1, fill=(255, 255, 255), outline=CONCRETE, width=3)
    dr.line([P(lx0 + 1, ly0 + 1), P(lx1 - 1, ly1 - 1)], fill=(170, 170, 170))
    dr.line([P(lx0 + 1, ly1 - 1), P(lx1 - 1, ly0 + 1)], fill=(170, 170, 170))
    R(lx0 + 4, ly1 - 0.6, lx1 - 4, ly1 + 0.6, fill=(80, 140, 200))
    m = P((lx0 + lx1) / 2, (ly0 + ly1) / 2)
    dr.text((m[0] - 10, m[1] - 6), "lift", font=f_small, fill=INK)
    m = P((cx0 + cx1) / 2, -LANDING / 2)
    dr.text((m[0] - 22, m[1] - 6), "landing", font=f_small, fill=(110, 110, 110))
    if four:
        # a second landing for the back pair, the lift opening onto both
        m = P((cx0 + cx1) / 2, -G + LANDING / 2)
        dr.text((m[0] - 22, m[1] - 6), "landing", font=f_small, fill=(110, 110, 110))
        R(lx0, -G + LANDING, lx1, ly0, fill=(255, 255, 255), outline=CONCRETE, width=3)
        R(lx0 + 4, -G + LANDING - 0.6, lx1 - 4, -G + LANDING + 0.6, fill=(80, 140, 200))
    # the stairwell's own walls, except where the flats' front doors are (theirs already)
    t = 1.25
    if not four:
        R(cx0 - t, -G - t, cx1 + t, -G + t, fill=CONCRETE)
    R(cx0 - t, -G, cx0 + t, 0, fill=CONCRETE)
    R(cx1 - t, -G, cx1 + t, 0, fill=CONCRETE)
    # the building's front door: in the 2-flat floor it is the stairwell's back; with four
    # it is in a side wall of the light well. Drawn on the entrance floor, noted here.

    for f in b.flats:
        draw_labels(dr, P, f[0], f_room, scale, xf=b.xf(f))

    if title:
        dr.text((pad, 12), b.title() + "  ·  typical floor", font=f_title, fill=INK)
        x, y = Wpx - pad - scale * 2, Hpx - 24
        dr.line([(x, y), (x + scale * 2, y)], fill=INK, width=2)
        dr.text((x + scale - 8, y + 3), "2 m", font=f_small, fill=INK)
    return img


# --------------------------------------------------------------------- front
SKY = (232, 238, 244)
FACADE = (238, 232, 220)
FACADE_DK = (214, 206, 192)
GLASS = (150, 184, 210)
RAIL = (90, 96, 104)


def render_front(b, scale=20, title=True):
    """The street side: the front pair's front walls, floor over floor."""
    g = random.Random(b.seed * 31 + 5)
    pad = 40
    top = 64 if title else pad
    FH = 30            # a floor, dm
    GH = 40            # the entrance floor on columns
    W = b.wa + b.wb
    roof_h = 30
    H = GH + FH * b.floors + (FH if b.penthouse else 0) + roof_h
    Wpx = max(int(W * DM * scale) + 2 * pad + 120, 900)
    Hpx = int(H * DM * scale) + top + pad + 20
    img = Image.new("RGB", (Wpx, Hpx), SKY)
    dr = ImageDraw.Draw(img)
    f_small = ImageFont.truetype(FONT, 11)
    f_title = ImageFont.truetype(FONT_B, 16)
    base = top + H * DM * scale

    def P(x, h):  # x in dm along the front, h in dm up from the street
        return (pad + 60 + x * DM * scale, base - h * DM * scale)

    def R(ax, ah, bx, bh, **kw):
        p0, p1 = P(min(ax, bx), max(ah, bh)), P(max(ax, bx), min(ah, bh))
        dr.rectangle([p0, p1], **kw)

    # street and pavement
    dr.rectangle([0, base, Wpx, Hpx], fill=(180, 180, 182))
    dr.rectangle([0, base, Wpx, base + 6], fill=(205, 205, 205))

    # the front pair, as the street sees them (a's front windows and balcony, then b's)
    fronts = []
    for f in b.flats[:2]:
        p, (ox, oy), _ = f
        wins = [(ox + w["a"], ox + w["b"], p.rooms[w["room"]]["kind"]) for w in p.windows
                if w["o"] == "h" and w["line"] == p.D]
        sl = [d for d in p.doors if d["style"] == "slider"][0]
        br = p.bal["rect"]
        fronts.append({"wins": wins, "slider": (ox + sl["a"], ox + sl["b"]),
                       "bal": (ox + br[0], ox + br[2])})

    # entrance floor: columns, parking, the lobby glass under the stairwell
    R(0, 0, W, GH, fill=(206, 202, 196))
    R(0, GH - 4, W, GH, fill=FACADE_DK)
    for k in range(7):
        x = k * W / 6
        R(x - 1.5, 0, x + 1.5, GH - 4, fill=FACADE_DK, outline=(160, 156, 150))
    cx0, cx1 = b.core_x
    R(cx0, 0, cx1, GH - 6, fill=GLASS, outline=RAIL)
    m = P((cx0 + cx1) / 2, GH / 2)
    dr.text((m[0] - 16, m[1] - 6), "lobby", font=f_small, fill=INK)
    # parked cars under the building
    for k in range(5):
        x = k * W / 5 + 6
        if cx0 - 30 < x < cx1:
            continue
        R(x, 2, x + 20, 13, fill=g.choice([(190, 60, 60), (80, 90, 110), (230, 230, 230),
                                           (60, 60, 64), (170, 170, 176)]), outline=INK)
    dr.text((P(2, GH - 8)[0], P(2, GH - 8)[1]), "parking on columns", font=f_small, fill=INK)

    def floor(h, x_from, x_to, setback=False):
        R(x_from, h, x_to, h + FH, fill=FACADE, outline=FACADE_DK)
        R(x_from, h, x_to, h + 2, fill=FACADE_DK)
        for fr in fronts:
            for (a, c, kind) in fr["wins"]:
                if c <= x_from or a >= x_to:
                    continue
                low = 9 if kind in ("bath", "ensuite", "toilet") else 7
                R(a, h + low, c, h + 23, fill=GLASS, outline=RAIL)
                # an aircon unit beside most windows
                if kind in ("bedroom", "parents", "mamad", "salon") and g.random() < 0.7:
                    ax = c + 1.5 if c + 9 < x_to else a - 8.5
                    R(ax, h + 8, ax + 7, h + 13, fill=(244, 244, 244), outline=(150, 150, 150))
                if kind == "mamad":
                    R(a, h + 23, c, h + 25, fill=(120, 100, 100))
            a, c = fr["slider"]
            if a < x_to and c > x_from:
                R(a, h + 2, c, h + 24, fill=GLASS, outline=RAIL)
            a, c = fr["bal"]
            if a < x_to and c > x_from and not setback:
                # the balcony slab and its railing, sticking out towards the street
                R(a - 1, h, c + 1, h + 2.5, fill=(200, 194, 184), outline=FACADE_DK)
                R(a - 1, h + 2.5, c + 1, h + 11, fill=(200, 210, 214), outline=RAIL)
                for k in range(int(a), int(c), 4):
                    dr.line([P(k, h + 2.5), P(k, h + 11)], fill=RAIL)

    for i in range(b.floors):
        floor(GH + i * FH, 0, W)
    h = GH + b.floors * FH
    if b.penthouse:
        # set back from the front: the roof of the floor below is its terrace
        R(0, h, W, h + 11, fill=(200, 210, 214), outline=RAIL)
        for k in range(0, int(W), 4):
            dr.line([P(k, h), P(k, h + 11)], fill=RAIL)
        floor(h, 6, W - 6, setback=True)
        h += FH
    # roof: parapet, the lift's machine room over the stairwell, solar water heaters
    R(0, h, W, h + 4, fill=FACADE_DK)
    R(cx0 - 2, h, cx1 + 2, h + 22, fill=FACADE, outline=FACADE_DK)
    n = b.flat_count()
    k = 0
    x = 4
    while k < n and x < W - 10:
        if cx0 - 4 < x < cx1 + 6:
            x = cx1 + 6
            continue
        # a tank on legs, a panel leaning behind it
        R(x, h + 4, x + 6, h + 11, fill=(236, 236, 236), outline=RAIL)
        dr.polygon([P(x + 6.5, h + 4), P(x + 13, h + 4), P(x + 9, h + 15)], fill=(70, 90, 130))
        x += 15
        k += 1
    dr.text((P(cx1 + 4, h + 20)[0], P(cx1 + 4, h + 20)[1]),
            "%d solar water heaters" % min(n, k), font=f_small, fill=INK)

    # floor numbers down the left
    for i in range(b.floors + (1 if b.penthouse else 0)):
        y = P(0, GH + i * FH + FH / 2)[1]
        dr.text((pad - 10, y - 6), str(i + 1), font=f_small, fill=INK)
    dr.text((pad - 10, P(0, GH / 2)[1] - 6), "0", font=f_small, fill=INK)

    if title:
        dr.text((pad, 12), b.title() + "  ·  street side", font=f_title, fill=INK)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--sheet", help="seeds, e.g. 1-4: typical floors side by side")
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    if a.sheet:
        seeds = P_.parse_range(a.sheet)
        ims = []
        for s in seeds:
            bl = Building(s)
            fl = render_floor(bl, scale=26).convert("RGB")
            fr = render_front(bl, scale=13).convert("RGB")
            col = Image.new("RGB", (max(fl.width, fr.width), fl.height + fr.height), (250, 250, 247))
            col.paste(fl, (0, 0))
            col.paste(fr, (0, fl.height))
            ims.append(col)
        w = sum(i.width for i in ims)
        h = max(i.height for i in ims)
        sheet = Image.new("RGB", (w, h), (250, 250, 247))
        x = 0
        for im in ims:
            sheet.paste(im, (x, 0))
            x += im.width
        path = os.path.join(a.out, "buildings_%s.png" % a.sheet)
        sheet.save(path)
        print(path)
        return
    bl = Building(a.seed)
    p1 = os.path.join(a.out, "building_%d_floor.png" % a.seed)
    p2 = os.path.join(a.out, "building_%d_front.png" % a.seed)
    render_floor(bl).convert("RGB").save(p1)
    render_front(bl).convert("RGB").save(p2)
    for f in bl.flats:
        for n in f[0].notes:
            print("flat %d: %s" % (f[0].seed, n))
    print(p1)
    print(p2)


if __name__ == "__main__":
    main()
