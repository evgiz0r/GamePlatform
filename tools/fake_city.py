#!/usr/bin/env python3
"""Make up a town -- no map, no network -- as a city file in the format tools/osm_city.py
bakes from OpenStreetMap, so whatever drives a real city drives this one too.

    python3 tools/fake_city.py --out game/<game>/cities/<name>.json
    python3 tools/fake_city.py --out ... --seed 3 --preview /tmp/plan.png

What it is for: a test bench. A real city is thousands of buildings and takes seconds to
load; this is one neighbourhood (about 1.3 x 1 km of streets, about a thousand buildings)
with one of each thing a real town has, so a change can be looked at in a moment:

  roads    a divided boulevard with a big signalled junction, a main street, a shopping
           street, a ring road round the town, a grid of side streets (two of them a one-way
           pair), contour streets curling round a hill and steep ones straight up it, two
           roundabouts, a living street, a car park's lane, cul-de-sacs into the foothills,
           and a mountain road that climbs to a lookout
  places   a strip mall and its car parks, an office tower, a hotel, the town hall on its
           square, a cinema, a museum, a school with its pitch, a kindergarten, a sports
           centre, a synagogue, a library, a petrol station, shops and cafes along the main
           streets, a park with a pond, a water tower on the hill, villas in the foothills,
           woods, bus stops, traffic lights, zebras, stop and give-way signs
  ground   a hill (its streets climb at 10-12%), a knoll, a hollow for the pond, and
           mountains all round. Past the foothills the slopes are steeper than 1 in 1, so a
           game that will not drive up ground steeper than WALL (below) has a town nobody can
           drive out of. The bake proves it: it flood-fills the height grid from the middle of
           town with that rule and stops if the edge of the map can be reached.

Nothing in it is real. The names are made up, in Hebrew with English beside them (it is a
Mediterranean town; a game picks its own regional look), and the file says "made_up": 1 so
a game does not credit OpenStreetMap for it. The same seed always makes the same town.

Stdlib only; --preview (a plan of the town as a PNG, for a quick look) needs Pillow.
"""
import argparse
import datetime
import json
import math
import os
import random
import sys

SCALE = 10                     # integers in the file are decimetres, as in tools/osm_city.py
WALL = 0.62                    # ground rising more than this per metre cannot be driven up
STEP = 8.0                     # metres between ground height samples
VA, VB = 720.0, 560.0          # the town's limits: a rounded rectangle, these half-axes
RA, RB = 650.0, 490.0          # the ring road round the town, inside them
SE_P = 4.0                     # the rounded rectangle's power (2 would be an ellipse)
X0, Z0, NX, NZ = -1150.0, -1000.0, 288, 251     # the height grid: ground well past the crests
HILL = (380.0, -250.0)         # the hill's top, north-east of the middle
PAVE = 2.4                     # pavement width a game draws behind the kerb
DUAL = 7.0                     # a divided road's halves are this far either side of its middle


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# ---- small geometry, on (x, z) tuples: +x east, +z SOUTH, as in the city file -------------

def sm(t):
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    return t * t * (3.0 - 2.0 * t)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def mul(a, k):
    return (a[0] * k, a[1] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def crs(a, b):
    return a[0] * b[1] - a[1] * b[0]


def ln(a):
    return math.hypot(a[0], a[1])


def unit(a):
    n = ln(a)
    return (a[0] / n, a[1] / n) if n > 1e-9 else (0.0, 0.0)


def right(d):
    """the right-hand side of travel along d (x east, z south)"""
    return (-d[1], d[0])


def lerp2(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def closest(p, a, b):
    ab = sub(b, a)
    l2 = dot(ab, ab)
    t = 0.0 if l2 < 1e-12 else max(0.0, min(1.0, dot(sub(p, a), ab) / l2))
    return lerp2(a, b, t), t


def pdist(p, a, b):
    return ln(sub(p, closest(p, a, b)[0]))


def seg_x(a, b, c, d):
    """where segments ab and cd cross, as (t along ab, u along cd), or None"""
    r = sub(b, a)
    s = sub(d, c)
    den = crs(r, s)
    if abs(den) < 1e-12:
        return None
    t = crs(sub(c, a), s) / den
    u = crs(sub(c, a), r) / den
    e = 1e-9
    if -e <= t <= 1 + e and -e <= u <= 1 + e:
        return min(1.0, max(0.0, t)), min(1.0, max(0.0, u))
    return None


def seg_seg(a, b, c, d):
    if seg_x(a, b, c, d):
        return 0.0
    return min(pdist(a, c, d), pdist(b, c, d), pdist(c, a, b), pdist(d, a, b))


def pip(p, poly):
    x, z = p
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
            inside = not inside
        j = i
    return inside


def poly_seg_dist(poly, a, b):
    if pip(a, poly) or pip(b, poly):
        return 0.0
    n = len(poly)
    return min(seg_seg(poly[i], poly[(i + 1) % n], a, b) for i in range(n))


def poly_dist(P, Q):
    """0 when they overlap"""
    if any(pip(p, Q) for p in P) or any(pip(q, P) for q in Q):
        return 0.0
    best = 1e9
    for i in range(len(P)):
        a, b = P[i], P[(i + 1) % len(P)]
        for j in range(len(Q)):
            best = min(best, seg_seg(a, b, Q[j], Q[(j + 1) % len(Q)]))
    return best


def area(poly):
    a = 0.0
    for i in range(len(poly)):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % len(poly)]
        a += x1 * z2 - x2 * z1
    return a * 0.5


def ccw(poly):
    """counter-clockwise in (x, z): a positive shoelace, as the baker writes them"""
    return list(poly) if area(poly) > 0 else list(reversed(poly))


def length(pts):
    return sum(ln(sub(pts[i + 1], pts[i])) for i in range(len(pts) - 1))


def at_s(pts, s):
    """the point s metres along the line, and the way it runs there"""
    for i in range(len(pts) - 1):
        L = ln(sub(pts[i + 1], pts[i]))
        if s <= L or i == len(pts) - 2:
            d = unit(sub(pts[i + 1], pts[i]))
            return lerp2(pts[i], pts[i + 1], max(0.0, min(1.0, s / L if L > 0 else 0.0))), d
        s -= L
    return pts[-1], (1.0, 0.0)


def offset(pts, off):
    """the line moved `off` metres to the right of travel (left when negative)"""
    out = []
    for i, p in enumerate(pts):
        d_in = unit(sub(p, pts[i - 1])) if i > 0 else (0.0, 0.0)
        d_out = unit(sub(pts[i + 1], p)) if i < len(pts) - 1 else (0.0, 0.0)
        d = unit(add(d_in, d_out))
        if d == (0.0, 0.0):
            d = d_out if d_out != (0.0, 0.0) else d_in
        m = 1.0
        if 0 < i < len(pts) - 1:
            m = 1.0 / max(dot(right(d), right(d_out)), 0.5)
        out.append(add(p, mul(right(d), off * m)))
    return out


def rect(c, d, w, depth):
    """a rectangle centred on c, `w` along the unit direction d and `depth` across it"""
    n = right(d)
    hw, hd = w * 0.5, depth * 0.5
    return ccw([add(add(c, mul(d, -hw)), mul(n, -hd)), add(add(c, mul(d, hw)), mul(n, -hd)),
                add(add(c, mul(d, hw)), mul(n, hd)), add(add(c, mul(d, -hw)), mul(n, hd))])


def box(x0, z0, x1, z1):
    return ccw([(x0, z0), (x1, z0), (x1, z1), (x0, z1)])


def circle(c, r, n, start=0.0):
    return [(c[0] + r * math.cos(start + 2 * math.pi * i / n), c[1] + r * math.sin(start + 2 * math.pi * i / n))
            for i in range(n)]


def bbox(pts, grow=0.0):
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    return (min(xs) - grow, min(zs) - grow, max(xs) + grow, max(zs) + grow)


class Hash:
    """items by the grid cells their boxes touch"""

    def __init__(self, cell=40.0):
        self.cell = cell
        self.cells = {}

    def add(self, b, item):
        c = self.cell
        for i in range(int(math.floor(b[0] / c)), int(math.floor(b[2] / c)) + 1):
            for j in range(int(math.floor(b[1] / c)), int(math.floor(b[3] / c)) + 1):
                self.cells.setdefault((i, j), []).append(item)

    def near(self, b):
        c = self.cell
        seen = []
        got = set()
        for i in range(int(math.floor(b[0] / c)), int(math.floor(b[2] / c)) + 1):
            for j in range(int(math.floor(b[1] / c)), int(math.floor(b[3] / c)) + 1):
                for it in self.cells.get((i, j), ()):
                    if id(it) not in got:
                        got.add(id(it))
                        seen.append(it)
        return seen


# ---- noise and the lie of the land ---------------------------------------------------------

class Noise:
    def __init__(self, seed):
        self.seed = seed & 0xffff

    def h(self, i, j):
        n = (i * 374761393 + j * 668265263 + self.seed * 982451653) & 0xffffffff
        n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
        return ((n ^ (n >> 16)) & 0xffffffff) / 4294967295.0

    def v(self, x, z):
        i, j = math.floor(x), math.floor(z)
        fx, fz = x - i, z - j
        u, w = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
        a, b = self.h(i, j), self.h(i + 1, j)
        c, d = self.h(i, j + 1), self.h(i + 1, j + 1)
        return a + (b - a) * u + (c - a) * w + (a - b - c + d) * u * w


def se_rho(x, z, a, b):
    return (abs(x / a) ** SE_P + abs(z / b) ** SE_P) ** (1.0 / SE_P)


def se_point(phi, a, b, out=0.0):
    """the point on the rounded rectangle (a, b) straight out from the middle at angle phi,
    `out` metres further along the same ray"""
    c, s = math.cos(phi), math.sin(phi)
    r = 1.0 / se_rho(c, s, a, b) + out
    return (c * r, s * r)


def beyond(p):
    """metres past the town's limits, along the ray from the middle (negative inside)"""
    r = math.hypot(p[0], p[1])
    if r < 1e-6:
        return -min(VA, VB)
    return r - r / se_rho(p[0], p[1], VA, VB)


class Ground:
    """The height of the land, before roads are cut into it. Inside the town: a tilt to the
    east, a hill, a knoll, a hollow. Outside: foothills for 40 m or so, then a mountainside
    rising 150-250 m over 180 m (steeper than 1 in 1 through its middle), then down a little."""

    def __init__(self, noise):
        self.N = noise
        self.cuts = []   # [polyline, heights, flat half-width, blend] roads cut into the slope
        self.pads = []   # [ring, height, blend] flat terraces

    def crest(self, p):
        r = math.hypot(p[0], p[1]) or 1.0
        c, s = p[0] / r, p[1] / r
        return 150.0 + 70.0 * self.N.v(c * 1.6 + 10.0, s * 1.6 + 10.0) + 35.0 * self.N.v(c * 4.0 + 30.0, s * 4.0 + 30.0)

    def mountain(self, p):
        d = beyond(p)
        if d < -40.0:
            return 0.0
        if d < 40.0:
            m = 7.0 * sm((d + 40.0) / 80.0)
        else:
            hc = self.crest(p)
            if d < 220.0:
                m = 7.0 + (hc - 7.0) * sm((d - 40.0) / 180.0)
            else:
                m = hc - 0.45 * hc * sm((d - 220.0) / 260.0)
        # ridges and gullies, kept gentle enough that no gully is a way out
        rough = max(0.0, min(1.0, (d - 50.0) / 60.0))
        m += rough * 18.0 * (self.N.v(p[0] / 140.0 + 50.0, p[1] / 140.0) - 0.5)
        m += rough * 6.0 * (self.N.v(p[0] / 45.0 + 7.0, p[1] / 45.0 + 7.0) - 0.5)
        return m

    def inner(self, p):
        x, z = p
        h = 4.0 + 0.006 * x
        h += 30.0 * math.exp(-((x - HILL[0]) ** 2 + (z - HILL[1]) ** 2) / (2 * 150.0 ** 2))
        h += 11.0 * math.exp(-((x + 430.0) ** 2 + (z - 300.0) ** 2) / (2 * 110.0 ** 2))
        h -= 2.5 * math.exp(-((x + 205.0) ** 2 + (z - 235.0) ** 2) / (2 * 55.0 ** 2))
        h += 1.6 * (self.N.v(x / 110.0 + 3.0, z / 110.0 + 3.0) - 0.5)
        return h

    def natural(self, p):
        return self.inner(p) + self.mountain(p)

    def at(self, p):
        """the natural height with the roads and terraces cut in"""
        h = self.natural(p)
        best_w, best_t = 0.0, h
        for pts, hs, flat, blend, bb in self.cuts:
            if not (bb[0] <= p[0] <= bb[2] and bb[1] <= p[1] <= bb[3]):
                continue
            dd, t = 1e9, 0.0
            for i in range(len(pts) - 1):
                q, u = closest(p, pts[i], pts[i + 1])
                e = ln(sub(p, q))
                if e < dd:
                    dd, t = e, hs[i] + (hs[i + 1] - hs[i]) * u
            w = 1.0 if dd <= flat else 1.0 - sm((dd - flat) / blend)
            if w > best_w:
                best_w, best_t = w, t
        for ring, ht, blend, bb in self.pads:
            if not (bb[0] <= p[0] <= bb[2] and bb[1] <= p[1] <= bb[3]):
                continue
            if pip(p, ring):
                dd = 0.0
            else:
                dd = min(pdist(p, ring[i], ring[(i + 1) % len(ring)]) for i in range(len(ring)))
            w = 1.0 - sm(dd / blend)
            if w > best_w:
                best_w, best_t = w, ht
        return h + (best_t - h) * best_w

    def cut(self, pts, hs, flat, blend):
        self.cuts.append([pts, hs, flat, blend, bbox(pts, flat + blend)])

    def pad(self, ring, h, blend):
        self.pads.append([ring, h, blend, bbox(ring, blend)])


# ---- street names: made up, Hebrew first (what the signs say), English beside --------------

N_RING = ("דרך ההרים", "Derekh HaHarim")
N_BLVD = ("שדרות העמק", "Sderot HaEmek")
N_NASI = ("הנשיא", "HaNasi")
N_SHUK = ("השוק", "HaShuk")
N_LOOK = ("דרך המצפה", "Derekh HaMitzpe")
WEST_NS = [(-545, ("הזית", "HaZayit")), (-435, ("התאנה", "HaTe'ena")), (-325, ("הרימון", "HaRimon")),
           (-215, ("הגפן", "HaGefen")), (-105, ("התמר", "HaTamar"))]
WEST_EW = [(-335, ("הדרור", "HaDror")), (-225, ("הנרקיס", "HaNarkis")), (115, ("הרקפת", "HaRakefet")),
           (225, ("הכלנית", "HaKalanit")), (340, ("האירוס", "HaIrus"))]
N_GALIL = ("הגליל", "HaGalil")
N_TAVOR = ("התבור", "HaTavor")
N_ORANIM = ("האורנים", "HaOranim")
N_BROSHIM = ("הברושים", "HaBroshim")
N_MAALE = ("מעלה הגבעה", "Ma'ale HaGiv'a")
N_KARMEL = ("הכרמל", "HaKarmel")
N_GILBOA = ("הגלבוע", "HaGilboa")
N_HERMON = ("החרמון", "HaHermon")
N_WEIZ = ("ויצמן", "Weizmann")
N_JABO = ("ז'בוטינסקי", "Jabotinsky")
N_ROTH = ("רוטשילד", "Rothschild")
N_BENY = ("בן יהודה", "Ben Yehuda")
N_KIKAR_W = ("כיכר ההרים", "Kikar HaHarim")
N_KIKAR_E = ("כיכר המייסדים", "Kikar HaMeyasdim")
CULS = [("החצב", "HaHatzav"), ("הדולב", "HaDolev"), ("האלה", "HaEla"), ("הצבר", "HaTzabar"),
        ("הלוטם", "HaLotem"), ("הערבה", "HaArava"), ("הרותם", "HaRotem")]

# shops and the like, by OSM kind: [(Hebrew name, English name), ...]
SHOPS = {
    "shop:supermarket": [("סופר העמק", "Super HaEmek"), ("שוק הגבעה", "Shuk HaGiv'a")],
    "shop:convenience": [("מכולת שלום", "Makolet Shalom"), ("מיני מרקט 24", "Mini Market 24"), ("המכולת של דני", "Danny's Grocery")],
    "shop:bakery": [("מאפיית הכיכר", "HaKikar Bakery"), ("לחם הבית", "Lechem HaBayit")],
    "shop:greengrocer": [("פירות וירקות אבי", "Avi Fruit & Veg"), ("הירקן", "HaYarkan")],
    "shop:butcher": [("אטליז הגליל", "HaGalil Butcher")],
    "shop:clothes": [("אופנת רונית", "Ronit Fashion"), ("בגדי העמק", "Valley Clothing"), ("סטייל", "Style")],
    "shop:shoes": [("נעלי צעד", "Tza'ad Shoes")],
    "shop:hairdresser": [("מספרת שי", "Shai Hair"), ("סלון אורית", "Salon Orit")],
    "shop:beauty": [("קוסמטיקה ליה", "Lia Beauty")],
    "shop:optician": [("אופטיקה רואים", "Ro'im Optics")],
    "shop:mobile_phone": [("סלולר פלוס", "Cellular Plus")],
    "shop:florist": [("פרחי השקד", "HaShaked Flowers")],
    "shop:laundry": [("מכבסת הנקי", "HaNaki Laundry")],
    "shop:hardware": [("כלי בית ובניין", "Home & Build")],
    "shop:books": [("ספרי העמק", "Valley Books")],
    "shop:toys": [("צעצועי דובי", "Dubi Toys")],
    "shop:jewelry": [("תכשיטי פנינה", "Pnina Jewels")],
    "shop:alcohol": [("יין ועוד", "Wine & More")],
    "shop:confectionery": [("ממתקי סבתא", "Grandma's Sweets")],
    "shop:pet": [("חיות ועוד", "Pets & More")],
    "shop:electronics": [("אלקטרו העמק", "Electro Valley")],
    "shop:kiosk": [("קיוסק הפינה", "Corner Kiosk")],
    "shop:car_repair": [("מוסך יוסי", "Yossi's Garage"), ("פנצ'ריית העמק", "Valley Tyres")],
    "shop:furniture": [("רהיטי הבית", "HaBayit Furniture")],
    "cafe": [("קפה לימון", "Cafe Limon"), ("קפה הנשיא", "Cafe HaNasi"), ("אספרסו בר", "Espresso Bar"),
             ("בית הקפה של רותי", "Ruti's Cafe"), ("קפה גבעה", "Cafe Giv'a")],
    "restaurant": [("מסעדת הזית", "HaZayit Restaurant"), ("חומוס אליהו", "Hummus Eliyahu"),
                   ("פיצה רומא", "Pizza Roma"), ("סושי העמק", "Valley Sushi"), ("המטבח של סבתא", "Grandma's Kitchen")],
    "fast_food": [("שווארמה העמק", "Valley Shawarma"), ("פלאפל הנשיא", "HaNasi Falafel"), ("בורגר בר", "Burger Bar")],
    "ice_cream": [("גלידה הגבעה", "Giv'a Ice Cream")],
    "bar": [("הבר השכונתי", "The Local Bar")],
    "pub": [("פאב ההרים", "Harim Pub")],
    "pharmacy": [("בית מרקחת העמק", "Valley Pharmacy"), ("פארם הנשיא", "HaNasi Pharm")],
    "bank": [("בנק העמק", "Valley Bank"), ("בנק ההרים", "Harim Bank")],
    "clinic": [("קופת חולים העמק", "Valley Health Clinic")],
    "dentist": [("מרפאת שיניים חיוך", "Smile Dental")],
    "doctors": [("ד\"ר לוי", "Dr. Levi")],
    "post_office": [("דואר העמק", "Valley Post Office")],
}
MAIN_SHOPS = [("cafe", 10), ("restaurant", 7), ("fast_food", 6), ("shop:clothes", 6), ("shop:convenience", 5),
              ("shop:bakery", 4), ("shop:hairdresser", 4), ("shop:mobile_phone", 3), ("shop:shoes", 3),
              ("shop:optician", 2), ("shop:florist", 2), ("shop:books", 2), ("shop:jewelry", 2), ("pharmacy", 3),
              ("bank", 2), ("shop:greengrocer", 3), ("shop:butcher", 1), ("shop:beauty", 2), ("shop:toys", 1),
              ("shop:alcohol", 1), ("shop:confectionery", 1), ("shop:pet", 1), ("shop:electronics", 2),
              ("ice_cream", 1), ("bar", 1), ("pub", 1), ("clinic", 1), ("dentist", 1), ("doctors", 1),
              ("shop:supermarket", 2), ("shop:laundry", 1), ("shop:kiosk", 2)]
CORNER_SHOPS = [("shop:convenience", 4), ("shop:kiosk", 3), ("shop:hairdresser", 2), ("cafe", 2), ("shop:laundry", 1)]
WORKSHOPS = [("shop:car_repair", 4), ("shop:hardware", 2), ("shop:furniture", 2), ("shop:supermarket", 1)]

# how the buildings along a street go, by the kind of place it is
STYLES = {
    # setback beyond the pavement, frontage width, depth, gap between, storeys by weight,
    # share turned end-on to the street, share with a block behind, share with shops
    "grid": dict(setback=(1.5, 4.0), width=(14, 22), depth=(11, 15), gap=(4, 8),
                 floors=[(2, 8), (3, 30), (4, 40), (5, 10), (6, 7), (8, 5)], perp=0.25, second=0.6, shop=0.03),
    "main": dict(setback=(0.4, 1.2), width=(16, 26), depth=(12, 16), gap=(2, 5),
                 floors=[(4, 20), (5, 30), (6, 25), (8, 17), (10, 8)], perp=0.0, second=0.4, shop=0.8),
    "shuk": dict(setback=(0.3, 0.8), width=(12, 20), depth=(11, 15), gap=(1.5, 3),
                 floors=[(3, 30), (4, 40), (5, 20), (6, 10)], perp=0.0, second=0.5, shop=0.97),
    "hill": dict(setback=(2.5, 6.0), width=(10, 16), depth=(9, 13), gap=(4, 8),
                 floors=[(2, 50), (3, 30), (4, 20)], perp=0.15, second=0.3, shop=0.01),
    "villa": dict(setback=(4.0, 8.0), width=(10, 14), depth=(9, 12), gap=(6, 12),
                  floors=[(1, 20), (2, 80)], perp=0.0, second=0.0, shop=0.0),
    "modern": dict(setback=(2.0, 5.0), width=(22, 28), depth=(15, 19), gap=(10, 16),
                   floors=[(7, 20), (9, 20), (12, 20), (15, 25), (18, 15)], perp=0.15, second=0.3, shop=0.15),
    "works": dict(setback=(3.0, 7.0), width=(24, 40), depth=(15, 22), gap=(5, 10),
                  floors=[(1, 45), (2, 55)], perp=0.0, second=0.2, shop=0.35),
}


def pick(rng, weighted):
    tot = sum(w for _, w in weighted)
    r = rng.random() * tot
    for v, w in weighted:
        r -= w
        if r <= 0:
            return v
    return weighted[-1][0]


# ---- the town -------------------------------------------------------------------------------

class Town:
    def __init__(self, seed):
        self.rng = random.Random(seed)
        self.G = Ground(Noise(seed))
        self.streets = []      # {pts, k, name, en, w, l, o, rb, sv, pv}
        self.areas = []        # [kind, ring]
        self.blds = []         # {p: ring, h, b, g, name, addr}
        self.pois = []         # [x, z, kind, name, name_en]
        self.stops = []        # [x, z, name]
        self.trees = []        # (x, z)
        self.barriers = []     # [[points], kind]
        self.addrs = []        # [x, z, street, number]
        self.signal_at = []    # points: the junctions with lights
        self.sign_at = []      # [point, kind]
        self.zebra_near = []   # junction points that get zebras on every way in
        self.keep_clear = []   # rings no building may touch (forecourts, terraces)
        self.shop_names = {}
        self.numbers = {}      # (street, side) -> next house number

    # -- roads --

    def street(self, pts, k, nm=("", ""), w=None, lanes=0, o=0, **tags):
        st = {"pts": list(pts), "k": k, "name": nm[0], "en": nm[1], "w": w if w else 8.0,
              "l": lanes, "o": o}
        st.update(tags)
        self.streets.append(st)
        return st

    # -- geometry checks for placing things --

    def index(self):
        """spatial lookups over the finished roads, for placing buildings beside them"""
        self.road_hash = Hash(40.0)
        for st in self.streets:
            drive = st["k"] not in ("footway", "path", "steps", "pedestrian")
            hw = st["w"] * 0.5
            p = st["pts"]
            for j in range(len(p) - 1):
                seg = (p[j], p[j + 1], hw, drive, st)
                self.road_hash.add(bbox([p[j], p[j + 1]], hw + 4.0), seg)
        self.bld_hash = Hash(40.0)
        self.area_hash = Hash(60.0)
        for kind, ring in self.areas:
            self.area_hash.add(bbox(ring), (kind, ring))
        for ring in self.keep_clear:
            self.area_hash.add(bbox(ring), ("keep", ring))
        for b in self.blds:
            self.bld_hash.add(bbox(b["p"]), b["p"])

    def road_room(self, poly, extra=0.0):
        """True when poly keeps clear of every road, its pavement and a little more"""
        bb = bbox(poly, 14.0)
        for a, b, hw, drive, st in self.road_hash.near(bb):
            need = hw + (PAVE + 0.8 if drive and st["k"] != "service" else 0.8) + extra
            if poly_seg_dist(poly, a, b) < need:
                return False
        return True

    def fits(self, poly, gap=3.0, outside_ok=False, areas_ok=(), road_extra=0.0):
        for p in poly:
            d = beyond(p)
            if d > (30.0 if outside_ok else -4.0):
                return False
        hs = [self.G.natural(p) for p in poly]
        if max(hs) - min(hs) > (4.0 if outside_ok else 3.2):
            return False
        if not self.road_room(poly, road_extra):
            return False
        bb = bbox(poly, gap + 1.0)
        for q in self.bld_hash.near(bb):
            if poly_dist(poly, q) < gap:
                return False
        for kind, ring in self.area_hash.near(bbox(poly, 1.5)):
            if kind in areas_ok:
                continue
            if poly_dist(poly, ring) < 1.0:
                return False
        return True

    def building(self, ring, h, name="", addr="", base=0.0, guess=False, register=True):
        b = {"p": ccw(ring), "h": round(h, 1)}
        if base > 0:
            b["b"] = base
        if guess:
            b["g"] = 1
        if name:
            b["name"] = name
        if addr:
            b["addr"] = addr
        self.blds.append(b)
        if register and hasattr(self, "bld_hash"):
            self.bld_hash.add(bbox(b["p"]), b["p"])
        return b

    def number(self, street, side):
        key = (street, side)
        n = self.numbers.get(key, 1 if side < 0 else 2)
        self.numbers[key] = n + 2
        return n

    def shop(self, at, kind, name=None):
        if name is None:
            names = SHOPS.get(kind, [("", "")])
            i = self.shop_names.get(kind, 0)
            self.shop_names[kind] = i + 1
            name = names[i % len(names)]
        self.pois.append([at[0], at[1], kind, name[0], name[1]])


# ---- laying out the streets ---------------------------------------------------------------

def zc(x):
    """the boulevard's middle line: a gentle S through the town"""
    return 12.0 * math.sin(math.pi * x / 650.0)


def cuts(pts, poly):
    """the line cut wherever it crosses the closed line `poly`"""
    pieces, cur = [], [pts[0]]
    n = len(poly)
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        hits = []
        for j in range(n):
            x = seg_x(a, b, poly[j], poly[(j + 1) % n])
            if x and 1e-7 < x[0] < 1 - 1e-7:
                hits.append(x[0])
        for t in sorted(hits):
            q = lerp2(a, b, t)
            cur.append(q)
            pieces.append(cur)
            cur = [q]
        cur.append(b)
    pieces.append(cur)
    return [p for p in pieces if length(p) > 0.5]


def clip(pts, poly, inside=True):
    out = []
    for pc in cuts(pts, poly):
        mid = at_s(pc, length(pc) * 0.5)[0]
        if pip(mid, poly) == inside:
            out.append(pc)
    return out


def longest(pieces):
    return max(pieces, key=length) if pieces else []


def trim_from(pts, other):
    """the line from where it first meets `other` on"""
    for i in range(len(pts) - 1):
        best = None
        for j in range(len(other) - 1):
            x = seg_x(pts[i], pts[i + 1], other[j], other[j + 1])
            if x and (best is None or x[0] < best):
                best = x[0]
        if best is not None:
            return [lerp2(pts[i], pts[i + 1], best)] + pts[i + 1:]
    return pts


def line(a, b, step=20.0):
    n = max(1, int(math.ceil(ln(sub(b, a)) / step)))
    return [lerp2(a, b, i / n) for i in range(n + 1)]


def roundabout(c, r, n):
    """a roundabout's ring, in the way traffic goes round it: anticlockwise on the map
    (north up), as on the right-hand side of the road. Closed: the last point is the first."""
    pts = [(c[0] + r * math.cos(2 * math.pi * i / n), c[1] - r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return pts + [pts[0]]


def lay_streets(T):
    ring = [se_point(math.pi + 2 * math.pi * i / 240, RA, RB) for i in range(240)]
    ring.append(ring[0])
    T.ring = ring
    kw = (RA * -1.0, 0.0)                                   # the west roundabout, on the ring
    kw_ring = roundabout(kw, 18.0, 24)
    ke = (180.0, 115.0)                                     # the east one, Rothschild x Weizmann
    ke_ring = roundabout(ke, 15.0, 20)
    T.kikars = [(kw, 18.0), (ke, 15.0)]
    rb_w = kw_ring[:-1]
    rb_e = ke_ring[:-1]

    def inside(pts):
        return clip(pts, ring, True)

    # the ring road round the town, cut where the west roundabout is
    T.street(longest(clip(ring, rb_w, False)), "secondary", N_RING, 10.0, 2)
    T.street(kw_ring, "secondary", N_KIKAR_W, 8.0, 1, 1, rb=1)
    T.street(ke_ring, "tertiary", N_KIKAR_E, 7.0, 1, 1, rb=1)

    # the boulevard: two one-way halves, eastbound on the south side
    mid = [(x, zc(x)) for x in range(-650, 721, 20)]
    T.blvd_mid = mid
    east = offset(mid, DUAL)
    west = offset(list(reversed(mid)), DUAL)
    halves = []
    for half in (east, west):
        pc = longest([q for p in clip(half, rb_w, False) for q in inside(p)])
        halves.append(T.street(pc, "primary", N_BLVD, 7.0, 2, 1))
    T.blvd_e, T.blvd_w = halves[0]["pts"], halves[1]["pts"]

    # the main street north-south, and the shopping street
    T.street(longest(inside(line((0, -600), (0, 600)))), "secondary", N_NASI, 12.0, 2)
    T.street(longest(inside(line((-800, -115), (230, -115)))), "tertiary", N_SHUK, 10.0, 2)

    # the old grid in the west; HaGefen stops either side of the park, HaTe'ena and HaRimon
    # are a one-way pair
    for x, nm in WEST_NS:
        if x == -215:
            for a, b in (((x, -600), (x, 115)), ((x, 340), (x, 600))):
                T.street(longest(inside(line(a, b))), "residential", nm)
        elif x == -435:
            T.street(longest(inside(line((x, 600), (x, -600)))), "residential", nm, 6.5, 1, 1)
        elif x == -325:
            T.street(longest(inside(line((x, -600), (x, 600)))), "residential", nm, 6.5, 1, 1)
        else:
            T.street(longest(inside(line((x, -600), (x, 600)))), "residential", nm)
    for z, nm in WEST_EW:
        if z == -225:
            T.street(longest(inside(line((-800, z), (0, z)))), "residential", nm, 6.5, 1, 1)
        elif z == 225:
            T.street(longest(inside(line((-800, z), (-325, z)))), "residential", nm)
            T.street(line((-105, z), (0, z)), "residential", nm)
        elif z == 340:
            T.street(longest(inside(line((-800, z), (-325, z)))), "residential", nm)
            T.street(line((-325, z), (-105, z)), "living_street", nm, 6.0)
            T.street(line((-105, z), (0, z)), "residential", nm)
        else:
            T.street(longest(inside(line((-800, z), (0, z)))), "residential", nm)

    # north of the shopping street, toward the hill
    T.street(longest(inside(line((100, -115), (100, -700)))), "residential", N_GALIL)
    top_r = 95.0
    to_h = lambda p: add(HILL, mul(unit(sub(p, HILL)), top_r))
    T.street(line((0, -300), to_h((0, -300))), "residential", N_TAVOR)

    # the hill: a street round it half-way up, another round the top, and four straight up
    T.street(circle(HILL, 190.0, 64) + [circle(HILL, 190.0, 64)[0]], "residential", N_ORANIM)
    T.street(circle(HILL, top_r, 40) + [circle(HILL, top_r, 40)[0]], "residential", N_BROSHIM, 7.0)
    T.street(line((230, -115), to_h((230, -115))), "residential", N_MAALE)
    T.street(trim_from(line((380, zc(380)), (380, HILL[1] + top_r)), T.blvd_w), "residential", N_KARMEL)
    T.street(longest(inside(line((380, -700), (380, HILL[1] - top_r)))), "residential", N_GILBOA)
    T.street(longest(inside(line((800, -250), (HILL[0] + top_r, -250)))), "residential", N_HERMON)

    # the south-east: newer, bigger
    for pc in clip(longest(inside(line((0, 115), (800, 115)))), rb_e, False):   # either side of the roundabout
        T.street(pc, "tertiary", N_WEIZ, 9.0, 2)
    T.street(longest(inside(line((0, 330), (800, 330)))), "residential", N_JABO)
    roth = trim_from(line((180, zc(180)), (180, 700)), T.blvd_e)
    for pc in clip(longest(inside(roth)), rb_e, False):
        T.street(pc, "tertiary", N_ROTH, 9.0, 2)
    T.street(longest(inside(trim_from(line((460, zc(460)), (460, 700)), T.blvd_e))), "residential", N_BENY)

    # the mall's car park: a lane down the middle with bays each side, in from Jabotinsky,
    # and a service road behind the strip mall
    T.street(line((320, 330), (320, 222)), "service", w=6.0, sv="parking_aisle")
    T.street(line((180, 214), (460, 214)), "service", w=6.0)
    T.street(line((320, 222), (320, 214)), "service", w=6.0)

    # a block's own car park in the old grid, behind the houses: a lane with bays
    T.street(line((-435, -280), (-325, -280)), "service", w=5.5, sv="parking_aisle")
    # an alley behind the shops of HaShuk
    T.street(line((-325, -150), (-105, -150)), "service", w=4.5, sv="alley")

    # cul-de-sacs from the ring road out into the foothills
    T.culs = []
    for i, phi in enumerate([2.35, 2.75, 3.9, 4.35, 5.25, 5.95, 0.55]):
        a = se_point(phi, RA, RB)
        b = se_point(phi, VA, VB, 22.0)
        st = T.street(trim_from(line(mul(a, 0.97), b, 12.0), ring), "residential", CULS[i], 6.5)
        T.culs.append((phi, st))


def lookout_road(T):
    """The road up the western mountainside: from the west roundabout out to the foot of the
    slope, then round the valley northward, each step as far up the slope as makes the road
    climb 8.5% (a real mountain road's grade) on the natural ground, so little has to be cut.
    It ends on a terrace with a car park and a cafe, looking over the town. The slope is cut
    level across the road and a shoulder either side; above and below, the cut and the bank
    are as steep as the mountain, so the road is the only way up."""
    G = T.G
    grade = 0.085
    start = (-668.0, 0.0)              # the roundabout's west way out
    pts = [start, (-684.0, 0.0), (-700.0, 0.0)]
    hs = [G.natural(p) for p in pts]
    d_was = beyond(pts[-1])
    phi = math.pi
    while hs[-1] < 58.0 and phi < math.pi + 1.3:
        phi += 0.01
        prev, h = pts[-1], hs[-1]

        def miss(dd):
            q = se_point(phi, VA, VB, dd)
            return G.natural(q) - h - grade * ln(sub(q, prev))

        lo, hi = max(d_was - 6.0, -30.0), d_was + 40.0
        if miss(lo) >= 0.0:
            dd = lo
        elif miss(hi) <= 0.0:
            dd = hi
        else:
            for _ in range(30):
                m = (lo + hi) * 0.5
                if miss(m) < 0.0:
                    lo = m
                else:
                    hi = m
            dd = (lo + hi) * 0.5
        q = se_point(phi, VA, VB, dd)
        hs.append(h + grade * ln(sub(q, prev)))
        pts.append(q)
        d_was = dd
    # smooth the line and its heights together, then keep every other point
    for _ in range(4):
        pts = [pts[0]] + [mul(add(add(pts[i - 1], pts[i + 1]), mul(pts[i], 2.0)), 0.25)
                          for i in range(1, len(pts) - 1)] + [pts[-1]]
        hs = [hs[0]] + [(hs[i - 1] + hs[i + 1] + 2.0 * hs[i]) * 0.25 for i in range(1, len(hs) - 1)] + [hs[-1]]
    keep = list(range(0, len(pts), 2))
    if keep[-1] != len(pts) - 1:
        keep.append(len(pts) - 1)
    pts = [pts[i] for i in keep]
    hs = [hs[i] for i in keep]
    road = T.street(pts, "unclassified", N_LOOK, 7.0, 2)
    G.cut(pts, hs, 3.5 + 6.5, 14.0)
    # the terrace at the top, level with the road's end
    end, hd = pts[-1], unit(sub(pts[-1], pts[-2]))
    c = add(end, mul(hd, 19.0))
    lot = rect(c, hd, 36.0, 28.0)
    G.pad(rect(c, hd, 46.0, 38.0), hs[-1], 14.0)
    T.areas.append(["parking", lot])
    T.keep_clear.append(lot)
    side = right(hd)
    # which side looks over the town: the cafe goes on the other, with its back to the slope
    look = 1.0 if dot(side, mul(c, -1.0)) > 0 else -1.0
    cafe_c = add(add(c, mul(side, -look * 22.0)), mul(hd, 4.0))
    G.pad(rect(cafe_c, hd, 22.0, 14.0), hs[-1], 12.0)
    cafe = rect(cafe_c, hd, 14.0, 8.0)
    T.building(cafe, 4.5, "", N_LOOK[0] + " 1", register=False)
    T.shop(add(cafe_c, mul(side, look * 3.2)), "cafe", ("קפה המצפה", "Cafe HaMitzpe"))
    view = add(c, mul(side, look * 15.0))
    T.pois.append([view[0], view[1], "attraction", "מצפה העמק", "Valley Lookout"])
    for k in range(5):
        q = add(add(c, mul(side, look * 16.5)), mul(hd, -14.0 + k * 7.0))
        T.trees.append(q)
    T.barriers.append([[add(add(c, mul(side, look * 17.5)), mul(hd, -18.0)),
                        add(add(c, mul(side, look * 17.5)), mul(hd, 18.0))], "fence"])
    T.lookout = (pts, hs, c)
    return road


# ---- joining the streets into a road graph -------------------------------------------------

class Canon:
    """one point for every place two lines meet (within 5 cm)"""

    def __init__(self):
        self.cells = {}

    def __call__(self, p):
        k = (int(math.floor(p[0] / 0.2)), int(math.floor(p[1] / 0.2)))
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                for q in self.cells.get((k[0] + i, k[1] + j), ()):
                    if abs(q[0] - p[0]) < 0.05 and abs(q[1] - p[1]) < 0.05:
                        return q
        self.cells.setdefault(k, []).append(p)
        return p


def join(T):
    """Every place two streets cross or one ends on another becomes a point both share."""
    segs = []
    h = Hash(40.0)
    for si, st in enumerate(T.streets):
        p = st["pts"]
        for j in range(len(p) - 1):
            idx = len(segs)
            segs.append((si, j, p[j], p[j + 1]))
            h.add(bbox([p[j], p[j + 1]], 1.0), idx)
    ins = [[] for _ in T.streets]
    done = set()
    for lst in h.cells.values():
        for x in range(len(lst)):
            for y in range(x + 1, len(lst)):
                i1, i2 = lst[x], lst[y]
                key = (i1, i2) if i1 < i2 else (i2, i1)
                if key in done:
                    continue
                done.add(key)
                A, B = segs[i1], segs[i2]
                if A[0] == B[0] and abs(A[1] - B[1]) <= 1:
                    continue
                r = seg_x(A[2], A[3], B[2], B[3])
                if r:
                    q = lerp2(A[2], A[3], r[0])
                    ins[A[0]].append((A[1], r[0], q))
                    ins[B[0]].append((B[1], r[1], q))
                    continue
                # a street that ends a hair short of another: joined to it
                for S, O in ((A, B), (B, A)):
                    pts = T.streets[S[0]]["pts"]
                    for e, j, t in ((pts[0], 0, 0.0), (pts[-1], len(pts) - 2, 1.0)):
                        if S[1] != j:
                            continue
                        q, u = closest(e, O[2], O[3])
                        if ln(sub(q, e)) < 1.2:
                            ins[O[0]].append((O[1], u, q))
                            ins[S[0]].append((S[1], t, q))
    canon = Canon()
    for si, st in enumerate(T.streets):
        p = st["pts"]
        add_at = {}
        for j, t, q in ins[si]:
            add_at.setdefault(j, []).append((t, q))
        out = []
        for j in range(len(p)):
            if j > 0:
                for t, q in sorted(add_at.get(j - 1, [])):
                    out.append((canon(q), True))
            out.append((canon(p[j]), False))
        # an inserted meeting point replaces a shape point it lands on
        merged = []
        for q, is_x in out:
            if merged and ln(sub(merged[-1][0], q)) < 0.25:
                if is_x and not merged[-1][1]:
                    merged[-1] = (q, True)
                continue
            merged.append((q, is_x))
        st["pts"] = [q for q, _ in merged]


def junctions(T):
    """point -> [(street index, point index)] for every point on two or more streets"""
    seen = {}
    for si, st in enumerate(T.streets):
        for j, p in enumerate(st["pts"]):
            seen.setdefault(p, []).append((si, j))
    out = {}
    for p, lst in seen.items():
        streets = {si for si, _ in lst}
        closed = any(T.streets[si]["pts"][0] == T.streets[si]["pts"][-1] and j in (0, len(T.streets[si]["pts"]) - 1)
                     for si, j in lst)
        if len(streets) >= 2 or (len(lst) >= 2 and not closed):
            out[p] = lst
    return out


DRIVE = {"primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "service"}
RANK = {"primary": 5, "secondary": 4, "tertiary": 3, "unclassified": 2, "residential": 1, "living_street": 0, "service": -1}


def zebras(T, J):
    """Zebra crossings a few metres up each way into the chosen junctions (OSM maps them as a
    point on the road where the footway crosses, not at the junction itself)."""
    adds = {}
    for jp in T.zebra_near:
        best = min(J, key=lambda q: ln(sub(q, jp)))
        if ln(sub(best, jp)) > 2.0:
            continue
        lst = J[best]
        r = max(T.streets[si]["w"] * 0.5 for si, _ in lst if T.streets[si]["k"] in DRIVE)
        for si, j in lst:
            st = T.streets[si]
            if st["k"] not in DRIVE or st["k"] == "service" or st.get("rb"):
                continue
            pts = st["pts"]
            for step in (-1, 1):
                want = r + 3.2
                k, s = j, 0.0
                while 0 <= k + step < len(pts):
                    L = ln(sub(pts[k + step], pts[k]))
                    if s + L >= want:
                        a, b = pts[k], pts[k + step]
                        q = lerp2(a, b, (want - s) / L)
                        if pts[k + step] in J and s + L - want < 6.0:
                            break   # too near the next junction
                        seg = min(k, k + step)
                        t = ln(sub(q, pts[seg])) / max(ln(sub(pts[seg + 1], pts[seg])), 1e-9)
                        adds.setdefault(si, []).append((seg, t, q))
                        break
                    if pts[k + step] in J:
                        break
                    s += L
                    k += step
    T.zebra_pts = []
    for si, lst in adds.items():
        pts = T.streets[si]["pts"]
        out = []
        by = {}
        for seg, t, q in lst:
            by.setdefault(seg, []).append((t, q))
        for j in range(len(pts)):
            out.append(pts[j])
            for t, q in sorted(by.get(j, [])):
                if 0.02 < t < 0.98:
                    out.append(q)
                    T.zebra_pts.append(q)
        T.streets[si]["pts"] = out


# ---- what stands along the streets ---------------------------------------------------------

def style_at(T, st, p):
    if beyond(p) > -60.0:
        return "villa"
    if ln(sub(p, HILL)) < 215.0 and p[1] < -40.0:
        return "hill"
    name = st["name"]
    if name == N_SHUK[0]:
        return "shuk"
    if p[0] > 160.0 and p[1] > 330.0:
        return "works"
    if p[0] > 0.0 and 15.0 < p[1] < 330.0:
        return "modern"
    if name in (N_BLVD[0], N_NASI[0], N_WEIZ[0]) and abs(p[0]) < 420.0 and abs(p[1]) < 380.0:
        return "main"
    return "grid"


def frontage(T):
    """Buildings along both sides of every street, facing it: each street's own kind of
    building (the shopping street's shopfronts, the hill's houses, villas outside the ring),
    with a block behind some of them, numbered odd on the left and even on the right."""
    rng = T.rng
    order = sorted(range(len(T.streets)), key=lambda i: -RANK.get(T.streets[i]["k"], -9))
    placed = []
    for si in order:
        st = T.streets[si]
        if st["k"] not in DRIVE or st["k"] == "service" or st.get("rb") or not st["name"]:
            continue
        pts = st["pts"]
        L = length(pts)
        hw = st["w"] * 0.5
        for side in (1, -1):
            s = rng.uniform(6.0, 14.0)
            while s < L - 8.0:
                p, d = at_s(pts, s)
                sty = STYLES[style_at(T, st, add(p, mul(right(d), side * (hw + 12.0))))]
                w = rng.uniform(*sty["width"])
                dep = rng.uniform(*sty["depth"])
                perp = rng.random() < sty["perp"]
                if perp:
                    w, dep = min(dep, w), max(dep, w) * 1.25
                back = rng.uniform(*sty["setback"])
                p, d = at_s(pts, s + w * 0.5)
                n = mul(right(d), side)
                c = add(p, mul(n, hw + PAVE + back + dep * 0.5))
                ring = rect(c, d, w, dep)
                if rng.random() < 0.18 and w > 13 and dep > 11 and not perp:
                    ring = l_shape(c, d, n, w, dep, rng)
                outside = style_at(T, st, c) == "villa"
                if not T.fits(ring, outside_ok=outside):
                    s += 3.0
                    continue
                floors = pick(rng, sty["floors"])
                kind = style_at(T, st, c)
                h = floors * (4.5 if kind == "works" else 3.0) + (0.6 if floors >= 2 else 0.3)
                num = T.number(st["name"], side)
                b = T.building(ring, h, addr="%s %d" % (st["name"], num),
                               guess=kind in ("grid", "hill") and rng.random() < 0.4)
                placed.append((b, st, side, c, d, n, w, dep, sty, num, kind))
                # shops on the ground floor, facing the street
                front = add(p, mul(n, hw + PAVE + back + 0.8))
                if rng.random() < sty["shop"]:
                    table = WORKSHOPS if kind == "works" else (CORNER_SHOPS if sty["shop"] < 0.1 else MAIN_SHOPS)
                    T.shop(front, pick(rng, table))
                    if w > 21 and kind != "works" and rng.random() < 0.6:
                        T.shop(add(front, mul(d, w * 0.3)), pick(rng, table))
                s += w + rng.uniform(*sty["gap"])
    # a second block behind some, the lane between them a little wider than the gap
    for b, st, side, c, d, n, w, dep, sty, num, kind in placed:
        if rng.random() >= sty["second"]:
            continue
        w2 = w * rng.uniform(0.8, 1.05)
        dep2 = rng.uniform(*sty["depth"])
        c2 = add(c, mul(n, dep * 0.5 + rng.uniform(6.0, 10.0) + dep2 * 0.5))
        ring = rect(c2, d, w2, dep2)
        if not T.fits(ring, outside_ok=kind == "villa"):
            continue
        floors = pick(rng, sty["floors"])
        h = floors * (4.5 if kind == "works" else 3.0) + 0.6
        T.building(ring, h, addr="%s %dא" % (st["name"], num), guess=rng.random() < 0.4)


def l_shape(c, d, n, w, dep, rng):
    """an L: the full frontage, one wing going back the full depth"""
    cut_w = w * rng.uniform(0.4, 0.55)
    cut_d = dep * rng.uniform(0.35, 0.5)
    hw, hd = w * 0.5, dep * 0.5
    P = lambda a, b: add(add(c, mul(d, a)), mul(n, b))
    if rng.random() < 0.5:
        pts = [P(-hw, -hd), P(hw, -hd), P(hw, hd), P(hw - cut_w, hd), P(hw - cut_w, hd - cut_d), P(-hw, hd - cut_d)]
    else:
        pts = [P(-hw, -hd), P(hw, -hd), P(hw, hd - cut_d), P(-hw + cut_w, hd - cut_d), P(-hw + cut_w, hd), P(-hw, hd)]
    return ccw(pts)


# ---- the places a town is remembered by ------------------------------------------------------

def landmarks(T):
    """Placed by hand before the streets fill in, so the rest keeps clear of them."""
    B = T.building
    # the town hall on its square, north-west of the big junction
    B(box(-78, -101, -26, -64), 18.6, "בית העירייה", N_NASI[0] + " 20")
    T.areas.append(["plaza", box(-92, -56, -14, -20)])
    T.pois.append([-52, -40, "townhall", "כיכר העירייה", "Town Hall Square"])
    # a museum across the main street from it
    B(box(22, -100, 66, -70), 11.0, "מוזיאון ההרים", N_NASI[0] + " 19")
    T.pois.append([24, -85, "museum", "מוזיאון ההרים", "Harim Museum"])
    # the office tower and the hotel south-east of the junction: glass, the tallest things
    B(box(20, 28, 50, 58), 72.0, "מגדל העמק", N_BLVD[0] + " 2")
    T.pois.append([35, 27, "bank", "בנק העמק", "Valley Bank"])
    B(box(84, 34, 150, 56), 42.0, "מלון ההרים", N_BLVD[0] + " 6")
    T.pois.append([117, 33, "hotel", "מלון ההרים", "Harim Hotel"])
    # the cinema, with a cafe
    B(box(18, 138, 70, 176), 15.0, "סינמה העמק", N_WEIZ[0] + " 3")
    T.pois.append([44, 137, "cinema", "סינמה העמק", "Cinema HaEmek"])
    T.pois.append([62, 137, "cafe", "קפה סינמה", "Cafe Cinema"])
    # the strip mall: long and shallow on Weizmann, its car parks behind
    B(box(212, 126, 368, 152), 12.0, "קניון ההרים", N_WEIZ[0] + " 20")
    for x, kind in ((235, "shop:supermarket"), (265, "shop:clothes"), (300, "cafe"), (330, "shop:shoes"), (355, "pharmacy")):
        T.shop((x, 127), kind)
    T.areas.append(["parking", box(196, 222, 312, 300)])
    T.areas.append(["parking", box(328, 222, 444, 300)])
    B(box(384, 124, 444, 170), 9.5, "", N_BENY[0] + " 5")
    T.shop((443, 140), "shop:electronics")
    # the sports centre
    T.areas.append(["pitch", box(492, 140, 582, 200)])
    T.areas.append(["pitch", box(490, 222, 518, 238)])
    T.areas.append(["pitch", box(528, 222, 556, 238)])
    B(box(482, 258, 532, 294), 11.0, "היכל הספורט", N_JABO[0] + " 30")
    T.areas.append(["parking", box(544, 258, 590, 300)])
    T.pois.append([507, 257, "sports_centre", "היכל הספורט", "Sports Hall"])
    for r in (box(486, 134, 588, 206), box(486, 216, 562, 244)):
        T.barriers.append([r + [r[0]], "fence"])
    # a petrol station on the boulevard, its forecourt kept clear for the canopy
    B(box(574, 40, 592, 52), 4.2, "", N_BLVD[0] + " 40")
    T.pois.append([583, 41, "fuel", "תחנת דלק ההרים", "Harim Fuel"])
    T.keep_clear.append(box(548, 18, 618, 40))
    # the school, its yard, its pitch and its fence, on the shopping street
    yard = box(-537, -219, -441, -121)
    T.areas.append(["school", yard])
    T.barriers.append([yard + [yard[0]], "fence"])
    B([(-530, -127), (-470, -127), (-470, -142), (-515, -142), (-515, -205), (-530, -205)], 12.6,
      "בית ספר אלון", N_SHUK[0] + " 4")
    T.pois.append([-500, -128, "school", "בית ספר אלון", "Alon School"])
    T.areas.append(["pitch", box(-505, -205, -450, -172)])
    for q in ((-460, -150), (-448, -150), (-448, -138), (-500, -160)):
        T.trees.append(q)
    # a kindergarten, small, in its own fenced yard
    kg = box(-420, 128, -380, 160)
    T.areas.append(["school", kg])
    T.barriers.append([kg + [kg[0]], "fence"])
    B(box(-412, 134, -390, 146), 4.0, "", "הרקפת" + " 9")
    T.pois.append([-401, 133, "kindergarten", "גן הרקפת", "Rakefet Kindergarten"])
    # the synagogue, a library, the community centre by the park
    B(box(-392, -200, -366, -176), 12.0, "בית הכנסת הגדול", "הנרקיס" + " 14")
    T.pois.append([-379, -201, "place_of_worship", "בית הכנסת הגדול", "Great Synagogue"])
    B(box(-92, 128, -54, 156), 9.0, "ספריית העמק", "הרקפת" + " 30")
    T.pois.append([-73, 127, "library", "ספריית העמק", "Valley Library"])
    B(box(-92, 248, -50, 280), 10.0, "מתנ\"ס העמק", "הכלנית" + " 31")
    T.pois.append([-71, 247, "community_centre", "מתנ\"ס העמק", "Valley Community Centre"])
    # a post office and a clinic on the main street
    B(box(-50, 128, -20, 154), 10.0, "", N_NASI[0] + " 31")
    T.pois.append([-21, 141, "post_office", "דואר העמק", "Valley Post Office"])


def park(T):
    """The town park in the old grid's south: a pond, paths, trees; and the hilltop park round
    the water tower, with steps up from the street below."""
    rng = T.rng
    P = box(-317, 123, -113, 332)
    T.areas.append(["park", P])
    pond = [(-205 + 34 * math.cos(a) * (1 + 0.18 * math.sin(3 * a)), 235 + 20 * math.sin(a) * (1 + 0.12 * math.cos(2 * a)))
            for a in [2 * math.pi * i / 22 for i in range(22)]]
    T.areas.append(["water", ccw(pond)])
    # paths: one round the pond, two across the park, one along each long side
    loop = [(-205 + 48 * math.cos(a), 235 + 32 * math.sin(a)) for a in [2 * math.pi * i / 28 for i in range(29)]]
    T.street(loop, "footway", ("", ""), 2.4)
    T.street([(-312, 160), (-280, 175), (-250, 210), (-251, 218)], "footway", ("", ""), 2.4)
    T.street([(-160, 255), (-140, 290), (-118, 318)], "footway", ("", ""), 2.4)
    T.street([(-312, 300), (-260, 275), (-245, 262)], "footway", ("", ""), 2.4)
    T.street([(-165, 213), (-140, 170), (-118, 130)], "footway", ("", ""), 2.4)
    for _ in range(70):
        q = (rng.uniform(-312, -118), rng.uniform(128, 327))
        if pip(q, pond) or ln(sub(q, (-205, 235))) < 58:
            continue
        T.trees.append(q)
    T.barriers.append([[(-317, 332), (-113, 332)], "hedge"])

    # the hill top: the water tower (a tank on legs), a path round it, steps down
    top = circle(HILL, 84.0, 32)
    T.areas.append(["park", ccw(top)])
    T.areas.append(["plaza", ccw(circle(HILL, 16.0, 16))])
    T.building(circle(HILL, 7.0, 12), 29.0, "מגדל המים", base=21.0)
    path = circle(HILL, 48.0, 32)
    T.street(path + [path[0]], "footway", ("", ""), 2.4)
    for i, a in enumerate((0.4, 1.95, 3.5, 5.05)):
        u = (math.cos(a), math.sin(a))
        T.street([add(HILL, mul(u, 16.5)), add(HILL, mul(u, 48.0))], "footway", ("", ""), 3.0)
        T.street([add(HILL, mul(u, 48.0)), add(HILL, mul(u, 82.0))], "steps" if i % 2 else "footway", ("", ""), 2.5)
    for _ in range(45):
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(20, 80)
        if abs(r - 48) < 4:
            continue
        T.trees.append(add(HILL, (r * math.cos(a), r * math.sin(a))))
    T.pois.append([HILL[0] + 17, HILL[1], "attraction", "תצפית הגבעה", "Hill Viewpoint"])

    # palms down the boulevard's middle, on a strip of grass
    mid = T.blvd_mid
    pts = [p for p in mid if -615 < p[0] < 640]
    T.areas.append(["grass", ccw(offset(pts, 2.8) + list(reversed(offset(pts, -2.8))))])
    s = 8.0
    L = length(pts)
    while s < L:
        T.trees.append(at_s(pts, s)[0])
        s += 12.0


def woods(T):
    """Woods on the foothills between the cul-de-sacs, from just outside the ring road's
    houses to where the mountain starts climbing."""
    taken = [phi for phi, _ in T.culs]
    phis = [math.pi + 2 * math.pi * i / 72 for i in range(72)]
    run = []
    out = []
    for phi in phis + [phis[0] + 2 * math.pi]:
        a = math.atan2(math.sin(phi), math.cos(phi))
        busy = any(abs(math.atan2(math.sin(a - t), math.cos(a - t))) < 0.16 for t in taken)
        busy = busy or abs(math.atan2(math.sin(a - math.pi), math.cos(a - math.pi))) < 0.05   # the lookout road's foot
        if busy:
            if len(run) >= 3:
                out.append(run)
            run = []
        else:
            run.append(phi)
    if len(run) >= 3:
        out.append(run)
    for run in out:
        for k in range(0, len(run) - 1, 4):
            part = run[k:k + 5]
            if len(part) < 2:
                continue
            inner = [se_point(p, VA, VB, -22.0) for p in part]
            outer = [se_point(p, VA, VB, 36.0) for p in reversed(part)]
            T.areas.append(["wood", ccw(inner + outer)])


def stops(T, J):
    """Bus stops on the right-hand kerb of the boulevard, the main streets and the ring road,
    every 300 m or so and clear of the junctions, named for the nearest cross street."""
    names = {}
    for p, lst in J.items():
        names[p] = [T.streets[si]["name"] for si, _ in lst if T.streets[si]["name"]]
    for st in T.streets:
        if st["name"] not in (N_BLVD[0], N_NASI[0], N_RING[0], N_WEIZ[0], N_SHUK[0]):
            continue
        pts = st["pts"]
        L = length(pts)
        every = 420.0 if st["name"] == N_RING[0] else 300.0
        for dirn in ((1,) if st["o"] else (1, -1)):
            line_ = pts if dirn == 1 else list(reversed(pts))
            s = 90.0 if dirn == 1 else 230.0
            while s < L - 40.0:
                p, d = at_s(line_, s)
                if any(ln(sub(p, q)) < 35.0 for q in J):
                    s += 15.0
                    continue
                q = add(p, mul(right(d), st["w"] * 0.5 + 1.5))
                cross = min(J, key=lambda j: ln(sub(j, p)))
                other = [n for n in names.get(cross, []) if n != st["name"]]
                T.stops.append([q[0], q[1], st["name"] + ("/" + other[0] if other else "")])
                s += every


def controls(T, J):
    """Lights at the big junctions, zebras round the busy ones, stop and give-way signs where
    side streets meet the main roads."""
    big = [(0.0, zc(0.0)), (0.0, -115.0), (180.0, zc(180.0)), (-325.0, zc(-325.0)), (460.0, zc(460.0))]
    for jp in J:
        lst = J[jp]
        names = {T.streets[si]["name"] for si, _ in lst}
        if any(ln(sub(jp, b)) < 12.0 for b in big):
            T.signal_at.append(jp)
            T.zebra_near.append(jp)
        elif N_BLVD[0] in names and N_RING[0] in names:
            T.signal_at.append(jp)
    rng = T.rng
    for jp, lst in J.items():
        kinds = [T.streets[si]["k"] for si, _ in lst if T.streets[si]["k"] in DRIVE]
        if len(kinds) < 2 or jp in T.signal_at:
            continue
        if any(T.streets[si].get("rb") for si, _ in lst):
            continue
        ranks = [RANK[k] for k in kinds]
        names = {T.streets[si]["name"] for si, _ in lst}
        if N_SHUK[0] in names or (jp[0] < 0 and rng.random() < 0.3) or (jp[0] > 0 and rng.random() < 0.15):
            T.zebra_near.append(jp)
        if max(ranks) > min(ranks) and min(ranks) >= 0:
            T.sign_at.append([jp, "stop" if rng.random() < 0.4 else "give_way"])


# ---- the ground grid, and proof there is no way out -----------------------------------------

def heights(T):
    g = []
    for j in range(NZ):
        z = Z0 + j * STEP
        for i in range(NX):
            g.append(T.G.at((X0 + i * STEP, z)))
    return g


def tri_grades(g, i, j):
    """the two triangles of grid cell (i, j), as the game draws the ground: their slopes"""
    r = j * NX + i
    h00, h10, h01, h11 = g[r], g[r + 1], g[r + NX], g[r + NX + 1]
    a = math.hypot(h10 - h00, h01 - h00) / STEP
    b = math.hypot(h11 - h01, h11 - h10) / STEP
    return a, b


def no_way_out(T, g):
    """Flood the grid cells a car can reach from the middle of town: a cell is open when
    both its triangles are gentler than WALL, or a drivable road runs through it. Fails
    when the flood reaches the edge of the map."""
    road_cells = set()
    for st in T.streets:
        if st["k"] not in DRIVE:
            continue
        pts = st["pts"]
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            n = max(1, int(ln(sub(b, a)) / 2.0))
            for m in range(n + 1):
                q = lerp2(a, b, m / n)
                road_cells.add((int((q[0] - X0) // STEP), int((q[1] - Z0) // STEP)))
    seen = set()
    start = (int((0 - X0) // STEP), int((40 - Z0) // STEP))
    todo = [start]
    seen.add(start)
    worst = -1e9
    while todo:
        i, j = todo.pop()
        worst = max(worst, beyond((X0 + (i + 0.5) * STEP, Z0 + (j + 0.5) * STEP)))
        if i <= 0 or j <= 0 or i >= NX - 2 or j >= NZ - 2:
            return False, worst
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c = (i + di, j + dj)
            if c in seen:
                continue
            a, b = tri_grades(g, c[0], c[1])
            if max(a, b) < WALL or c in road_cells:
                seen.add(c)
                todo.append(c)
    return True, worst


def connected(T):
    """how many separate drivable networks there are (should be one)"""
    adj = {}
    for st in T.streets:
        if st["k"] not in DRIVE:
            continue
        p = st["pts"]
        for k in range(len(p) - 1):
            adj.setdefault(p[k], set()).add(p[k + 1])
            adj.setdefault(p[k + 1], set()).add(p[k])
    left = set(adj)
    parts = []
    while left:
        s = left.pop()
        todo, comp = [s], {s}
        while todo:
            for q in adj[todo.pop()]:
                if q in left:
                    left.discard(q)
                    comp.add(q)
                    todo.append(q)
        parts.append(len(comp))
    return parts


# ---- writing it out --------------------------------------------------------------------------

def q(v):
    return int(round(v * SCALE))


def flat(pts):
    out = []
    for p in pts:
        out += [q(p[0]), q(p[1])]
    return out


def write(T, g, name, seed):
    nodes, index = [], {}

    def node(p):
        if p not in index:
            index[p] = len(nodes) // 2
            nodes.extend([q(p[0]), q(p[1])])
        return index[p]

    # OSM splits a street into ways at its junctions, and a game may only choose where to go
    # where one way ends: so does this (a roundabout's ring stays whole, as one way)
    used = {}
    for st in T.streets:
        if st["k"] in DRIVE:
            for p in set(st["pts"]):
                used[p] = used.get(p, 0) + 1
    pieces = []
    for st in T.streets:
        pts = st["pts"]
        if st["k"] not in DRIVE or st.get("rb"):
            pieces.append((st, pts))
            continue
        cur = [pts[0]]
        for p in pts[1:]:
            cur.append(p)
            if used.get(p, 0) >= 2 and len(cur) >= 2 and p != pts[-1]:
                pieces.append((st, cur))
                cur = [p]
        if len(cur) >= 2:
            pieces.append((st, cur))

    roads = []
    for st, pts in pieces:
        ids = [node(p) for p in pts]
        if len(ids) < 2:
            continue
        rd = {"n": ids, "k": st["k"], "w": round(st["w"], 1)}
        if st["l"]:
            rd["l"] = st["l"]
        if st["o"]:
            rd["o"] = st["o"]
        if st["name"]:
            rd["name"] = st["name"]
            rd["name_en"] = st["en"]
        for tag in ("rb", "sv", "pv"):
            if st.get(tag):
                rd[tag] = st[tag]
        roads.append(rd)

    def nearest_node(p, within=2.0):
        best, bd = None, within
        for k, i in index.items():
            d = ln(sub(k, p))
            if d < bd:
                best, bd = i, d
        return best

    signals = sorted({nearest_node(p) for p in T.signal_at} - {None})
    crossings = sorted({index[p] for p in getattr(T, "zebra_pts", []) if p in index})
    signs = []
    for p, kind in T.sign_at:
        i = nearest_node(p)
        if i is not None:
            signs.append([i, kind, 0, 0])
    lo = min(g)
    x1, z1 = X0 + (NX - 1) * STEP, Z0 + (NZ - 1) * STEP
    out = {
        "version": 1,
        "name": name,
        "source": "made up by tools/fake_city.py (seed %d): not a real place" % seed,
        "made_up": 1,
        "fetched": datetime.date.today().isoformat(),
        "origin": [0.0, 0.0],
        "scale": SCALE,
        "bounds": [X0, Z0, x1, z1],
        "boundary": [flat(se_point(math.pi + 2 * math.pi * i / 120, VA, VB) for i in range(120))],
        "nodes": nodes,
        "roads": roads,
        "buildings": [dict({"p": flat(b["p"])}, **{k: v for k, v in b.items() if k != "p"}) for b in T.blds],
        "areas": [{"p": flat(ccw(r)), "k": k} for k, r in T.areas],
        "trees": flat(T.trees),
        "signals": signals,
        "crossings": crossings,
        "signs": signs,
        "barriers": [[flat(pts), kind] for pts, kind in T.barriers],
        "pois": [[q(p[0]), q(p[1]), p[2], p[3], p[4]] for p in T.pois],
        "stops": [[q(s[0]), q(s[1]), s[2]] for s in T.stops],
        "addrs": [[q(a[0]), q(a[1]), a[2], a[3]] for a in T.addrs],
        "height": {"x0": X0, "z0": Z0, "step": STEP, "nx": NX, "nz": NZ, "base": round(120.0 + lo, 1),
                   "h": [q(v - lo) for v in g]},
    }
    return out


def preview(T, g, path):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        log("--preview needs Pillow (pip install pillow); skipped")
        return
    k = 0.5   # pixels per metre
    W, H = int((NX - 1) * STEP * k), int((NZ - 1) * STEP * k)
    img = Image.new("RGB", (W, H))
    px = img.load()
    hi = max(g)
    lo = min(g)
    for y in range(H):
        j = min(NZ - 2, int(y / k / STEP))
        for x in range(W):
            i = min(NX - 2, int(x / k / STEP))
            a, b = tri_grades(g, i, j)
            v = (g[j * NX + i] - lo) / max(hi - lo, 1.0)
            c = int(70 + 150 * v)
            px[x, y] = (c + 40, c - 20, c - 50) if max(a, b) >= WALL else (c - 30, c, c - 40)
    d = ImageDraw.Draw(img)
    P = lambda p: ((p[0] - X0) * k, (p[1] - Z0) * k)
    col = {"park": (60, 150, 60), "grass": (80, 170, 80), "wood": (30, 100, 40), "water": (60, 110, 220),
           "parking": (120, 120, 130), "pitch": (40, 190, 90), "plaza": (200, 190, 160), "school": (210, 180, 120)}
    for kind, ring in T.areas:
        d.polygon([P(p) for p in ring], fill=col.get(kind, (255, 0, 255)))
    for st in T.streets:
        w = max(1, int(st["w"] * k)) if st["k"] in DRIVE else 1
        c = (250, 250, 250) if st["k"] in DRIVE else (240, 200, 120)
        if st["o"]:
            c = (250, 220, 160)
        d.line([P(p) for p in st["pts"]], fill=c, width=w)
    for b in T.blds:
        d.polygon([P(p) for p in b["p"]], fill=(90, 60, 200) if b["h"] < 20 else (40, 20, 140), outline=(20, 10, 60))
    for p in T.signal_at:
        x, y = P(p)
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 0, 0))
    for p in getattr(T, "zebra_pts", []):
        x, y = P(p)
        d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=(255, 255, 0))
    for s in T.stops:
        x, y = P(s)
        d.rectangle([x - 2, y - 2, x + 2, y + 2], fill=(0, 200, 255))
    for p in T.pois:
        x, y = P(p)
        d.point((x, y), fill=(255, 120, 0))
    img.save(path)
    log("plan written to %s" % path)


def make(seed, name):
    T = Town(seed)
    lay_streets(T)
    lookout_road(T)
    park(T)
    join(T)
    J = junctions(T)
    controls(T, J)
    zebras(T, J)
    J = junctions(T)
    landmarks(T)
    woods(T)
    T.index()
    frontage(T)
    stops(T, J)
    g = heights(T)
    return T, g


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", required=True, help="where to write the city file")
    ap.add_argument("--name", default="Kiryat Dimyon", help="the town's name (default: Kiryat Dimyon)")
    ap.add_argument("--seed", type=int, default=7, help="the same seed makes the same town")
    ap.add_argument("--preview", help="also draw a plan of it to this PNG (needs Pillow)")
    args = ap.parse_args()
    T, g = make(args.seed, args.name)
    shut, reach = no_way_out(T, g)
    if not shut:
        sys.exit("the mountains have a way through (reached %.0f m past the town's edge): "
                 "try another --seed" % reach)
    parts = connected(T)
    city = write(T, g, args.name, args.seed)
    if args.preview:
        preview(T, g, args.preview)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(city, f, ensure_ascii=False, separators=(",", ":"))
    pts, hs, _ = T.lookout
    log("made %s: %d roads, %d road nodes, %d buildings, %d areas, %d trees, %d shops and places, "
        "%d bus stops, %d lights, %d zebras, %d signs" % (
            args.name, len(city["roads"]), len(city["nodes"]) // 2, len(city["buildings"]), len(city["areas"]),
            len(city["trees"]) // 2, len(city["pois"]), len(city["stops"]), len(city["signals"]),
            len(city["crossings"]), len(city["signs"])))
    log("ground: %.0f m from the valley floor to the highest crest; the lookout road climbs %.0f m "
        "over %.0f m; a car gets at most %.0f m past the town's edge" % (
            max(g) - min(g), hs[-1] - hs[0], length(pts), reach))
    if len(parts) > 1:
        log("warning: the roads fall into %d separate networks (%s nodes)" % (len(parts), sorted(parts, reverse=True)))
    log("wrote %s (%.1f MB)" % (args.out, os.path.getsize(args.out) / 1e6))


if __name__ == "__main__":
    main()
