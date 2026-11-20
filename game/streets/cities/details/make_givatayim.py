"""Writes cities/details/givatayim.json: what a walk filmed in Givatayim showed along the
Ha-Meri passage that OpenStreetMap does not (see details.gd for the format, DEV.md "The filmed
walk" for how it was measured). Run it from anywhere: python3 make_givatayim.py

Everything is placed along the passage's own line: P(s, off) is `s` metres from its end on
Katzenelson towards Sheinkin and `off` to the south-east (negative: north-west). Walking it
south-west, the south-east side is on the left."""
import json, math, os
S0 = (667.9, -653.0)          # the passage's end on Katzenelson (a baked node)
S1 = (611.3, -588.2)          # its end on Sheinkin (a baked node)
L = math.dist(S0, S1)
u = ((S1[0] - S0[0]) / L, (S1[1] - S0[1]) / L)
left = (u[1], -u[0])          # the south-east side
assert left[0] > 0 and left[1] > 0, left
def P(s, off=0.0):
    return [round(S0[0] + u[0] * s + left[0] * off, 2), round(S0[1] + u[1] * s + left[1] * off, 2)]
SPLIT = 58.0
# the arcade along Katzenelson: the block's street face, and its shops 3 m back behind it
ARC_A, ARC_E, ARC_DEPTH = (646.9, -664.0), (657.7, -655.6), 3.0
_ad = ((ARC_E[0] - ARC_A[0]) / math.dist(ARC_A, ARC_E), (ARC_E[1] - ARC_A[1]) / math.dist(ARC_A, ARC_E))
ARC_IN = (-_ad[1], _ad[0])
if (P(15, -15)[0] - ARC_A[0]) * ARC_IN[0] + (P(15, -15)[1] - ARC_A[1]) * ARC_IN[1] < 0:
    ARC_IN = (-ARC_IN[0], -ARC_IN[1])
SHOPS = [[round(c[0] + ARC_IN[0] * (ARC_DEPTH - 0.03), 2), round(c[1] + ARC_IN[1] * (ARC_DEPTH - 0.03), 2)] for c in (ARC_A, ARC_E)]
SE = [round(left[0], 4), round(left[1], 4)]        # the way the passage's south-east side lies
NW = [-SE[0], -SE[1]]
r2 = lambda p: [round(p[0], 2), round(p[1], 2)]

# the walk: landmarks timed to the film, the points between timed by distance
# Katzenelson by the film, half a second a frame: at the north kerb 1.6-4.5 s watching the
# traffic from the left (a white SUV goes by), over the near half, on the median 8.7-13.3 s
# watching the far half's from the right (cars stop at the zebra, one drives on), over it,
# the far kerb at 17 s. Its halves are set to 7 m (two lanes each, see "roads" below): the
# kerbs at -13.8 and 3.1, the median from -6.8 to -3.9; about 2.1-2.3 m/s over each half.
KERB_N, MEDIAN, KERB_S = P(-14.1, -17.4), P(-5.35, -17.35), tuple(P(3.3, -17.3))
lm = [
    (0.0, tuple(P(-16.0, -17.4))), (1.6, tuple(KERB_N)), (4.5, tuple(KERB_N)),   # to the north kerb, waiting
    (8.7, tuple(MEDIAN)), (13.3, tuple(MEDIAN)),                            # over the near half; waiting
    (17.0, KERB_S), (18.4, tuple(P(6.4, -17.6))),                           # over the far half, up the kerb,
                                                                            # in past the arcade's middle column
    (21.0, tuple(P(6.6, -11.3))), (None, tuple(P(6.9, -5.4))),              # along it under the arcade (the
                                                                            # middle of it: the columns are at 5.2-5.8),
                                                                            # clear of the sign post at the corner
    (25.6, tuple(P(7.5))), (33.0, tuple(P(17))),               # the forecourt, into the passage
                                                               # (the game's zebra is a few metres further
                                                               # up the street than the film's: brisk to here)
    (None, tuple(P(30))), (None, tuple(P(45))),
    (64.0, tuple(P(SPLIT))),                                   # out of it at the railings
    (None, tuple(P(60.5, -2.0))), (None, tuple(P(63, -4.4))),  # onto the little street's pavement, the road on the left
    (80.0, tuple(P(80.5, -4.4))), (81.5, tuple(P(82.0, -4.2))),  # the corner, at the kerb (between
    (82.4, tuple(P(82.0, -4.2))),                                 # its bollards); a look each way first
    (87.0, tuple(P(90.4, -4.2))),                                 # over Sheinkin (the film's asphalt
                                                                  # ends at 86.5 s: the raised crossing)
    (87.9, tuple(P(91.7, -3.3))),                                 # onto Ha-Meri's raised crossing,
    (91.5, tuple(P(91.6, 3.6))), (92.4, tuple(P(91.6, 5.0))),     # over it looking down the street, up
    (93.8, tuple(P(93.6, 6.0))), (96.0, tuple(P(96.4, 6.0))),     # its far kerb between the corner's sign
                                                                  # pole and the first bollard, then a few
                                                                  # steps in, behind the hydrant and the
                                                                  # trees in their pits (POSTS_NEAR)
]
# fill the untimed points by distance between the timed ones
pts = [list(p) for _, p in lm]
times = [t for t, _ in lm]
i = 0
while i < len(lm):
    if times[i] is None:
        j = i
        while times[j] is None:
            j += 1
        a = i - 1
        seg = [math.dist(pts[k], pts[k + 1]) for k in range(a, j)]
        tot = sum(seg)
        acc = 0.0
        for k in range(i, j):
            acc += seg[k - a - 1]
            times[k] = times[a] + (times[j] - times[a]) * acc / tot
        i = j
    i += 1
walk = [[round(t, 2), round(p[0], 2), round(p[1], 2)] for t, p in zip(times, pts)]

d = {
    "about": "Givatayim as a walk filmed along it showed it, where OpenStreetMap does not: the "
             "short street at the south end of the Ha-Meri passage (the map draws it all as one "
             "footpath), the zebra across Katzenelson by the passage (unmarked), the paved "
             "forecourt at the passage's north end, the walls, fences and hedge down the passage, "
             "the bin in it and the railings at its end. Metres on the city file's ground.",
    "roads": {
        "drop": [{"k": "footway", "name": "המרי", "near": P(40)}],
        # Katzenelson's halves, junction to junction: two lanes each, about 7 m (the film's
        # pace over them, one car stopped in one lane while the next drove on in the other),
        # not the 9 m the baker guesses for a two-lane tertiary
        "set": [{"k": "tertiary", "name": "כצנלסון", "near": P(-10.3, -17.4), "w": 7.0},
                {"k": "tertiary", "name": "כצנלסון", "near": P(-0.4, -17.3), "w": 7.0},
                # Ha-Meri's kerbs are painted blue and white all along (paid parking)
                {"k": "residential", "name": "המרי", "near": P(110, 0), "kerb": "blue_white"}],
        "add": [
            {"pts": [list(S0), P(SPLIT)], "k": "footway", "w": 2.6, "name": "המרי", "name_en": "HaMeri"},
            {"pts": [P(SPLIT), list(S1)], "k": "residential", "w": 5.5, "name": "המרי", "name_en": "HaMeri"},
        ],
    },
    "crossings": [[661.6, -672.2], [655.1, -664.7]],
    # the block at the passage's north-west corner stands on columns along Katzenelson: shops
    # 3 m back under the upper floors, the walk goes between them and the columns (film 18-23 s)
    "buildings": [{"near": P(15, -15), "arcade": [list(ARC_A), list(ARC_E)], "depth": ARC_DEPTH, "h": 3.4}],
    # paving level with the pavement (film 17-33 s): charcoal herringbone from the kerb in
    # under the arcade, then the forecourt's pale poured slabs, laid square to the passage, out
    # to the two blocks either side and round into the drive past the barrier
    "surfaces": [
        {"k": "pavers_dark", "lift": 0.14, "p": [P(3.35, -23.6), P(3.35, -6.0), P(8.4, -6.0), P(8.4, -23.6)]},
        {"k": "slabs", "lift": 0.14, "lay": [round(u[0], 4), round(u[1], 4)],
         "p": [P(3.35, -6.0), P(8.4, -6.0), P(8.4, -7.9), P(17.1, -7.9), P(17.1, 1.35), P(17.1, 5.0),
               P(22.0, 5.0), P(22.0, 10.5), P(16.3, 10.5), P(16.3, 5.4), P(3.35, 5.4)]},
        # the passage itself (film 33-64 s): small grey pavers in rows across it, each row half
        # a paver on, level with the forecourt, fence to fence
        {"k": "pavers_grey", "lift": 0.14, "lay": [round(left[0], 4), round(left[1], 4)],
         "p": [P(17.1, -1.35), P(57.8, -1.35), P(57.8, 1.35), P(17.1, 1.35)]},
        # Ha-Meri's mouth past Sheinkin (film 86.5-92.5 s): a raised crossing, the road paved in
        # charcoal herringbone up to the pavements' height, a metre's ramp either end
        {"k": "pavers_dark", "lift": 0.14,
         "p": [P(89.6, -4.0), P(96.0, -4.0), P(96.0, 4.0), P(89.6, 4.0)],
         "ramps": [[P(89.6, 0), P(90.6, 0)], [P(96.0, 0), P(95.0, 0)]]},
    ],
    "lines": [
        {"kind": "stone_wall", "pts": [P(17, -1.35), P(38, -1.35)], "h": 0.8},
        {"kind": "wood_fence", "pts": [P(17, -1.35), P(38, -1.35)], "base": 0.75, "h": 1.15},
        {"kind": "hedge", "pts": [P(38, -1.5), P(57, -1.5)]},
        {"kind": "loop_fence", "pts": [P(17, 1.35), P(56, 1.35)], "h": 0.9},
        {"kind": "loop_fence", "pts": [P(17.2, 5.0), P(17.2, 1.35)], "h": 0.9},   # round the planted bed's front
        # the planted bed behind the white fence, and its strip on along the next block
        {"kind": "hedge", "pts": [P(17.8, 2.4), P(25.8, 2.4)]},
        {"kind": "hedge", "pts": [P(18.2, 4.1), P(21.5, 4.1)]},
        {"kind": "hedge", "pts": [P(26.2, 2.1), P(38.5, 2.1)]},
        # and above them what the film shows walking down it: tall planting 2.5-3 m on both
        # sides (shrubs, bamboo, palms) that closes it in, the blocks behind barely seen
        {"kind": "shrubs", "pts": [P(17.8, 2.7), P(25.4, 2.7)], "h": 2.6},
        {"kind": "shrubs", "pts": [P(26.0, 2.2), P(39.0, 2.2)], "h": 2.4},
        {"kind": "shrubs", "pts": [P(39.5, 2.4), P(44.5, 2.4)], "h": 2.8},
        {"kind": "shrubs", "pts": [P(45.0, 2.0), P(56.0, 2.0)], "h": 2.4},
        {"kind": "shrubs", "pts": [P(18.0, -2.7), P(37.8, -2.7)], "h": 2.4},   # over the wooden fence
        {"kind": "shrubs", "pts": [P(38.2, -2.0), P(56.8, -2.0)], "h": 3.0},   # the tall hedge on the low wall
        # the shops under the arcade (film 15-23 s): lit glass in light frames, each its own
        # sign; the confectionery's, dark brown, faces the zebra
        {"kind": "shopfront", "pts": SHOPS, "h": 3.25, "face": [round(-ARC_IN[0], 4), round(-ARC_IN[1], 4)],
         "signs": ["", "קונדיטוריה", "", ""], "panels": [1]},   # (only the film's shop is named)
        # the little street to Sheinkin (film 64-72 s): a tall hedge on the back of the
        # pavement the walk is on
        {"kind": "shrubs", "pts": [P(59.0, -6.3), P(71.5, -6.3)], "h": 2.3},
    ],
    "props": [
        {"kind": "bin", "at": P(41, -0.95)},
        {"kind": "hoop_railing", "at": P(56.6, -0.85), "dir": [round(u[0], 4), round(u[1], 4)]},
        {"kind": "hoop_railing", "at": P(56.6, 0.85), "dir": [round(u[0], 4), round(u[1], 4)]},
        # the forecourt (film 24-33 s): a loose row of bollards across it with a gap to walk
        # through, one more at the passage's mouth; the transformer's twin poles on their plinth
        # just right of the mouth; a garden lamp at the bed's corner; a manhole in the slabs;
        # the barrier across the drive to the next block's car park
        *[{"kind": "bollard", "at": P(13.6, o)} for o in (-6.6, -5.0, -3.4, -1.0, 1.0, 2.6, 4.2)],
        {"kind": "bollard", "at": P(15.7, -0.8)},
        {"kind": "twin_poles", "at": P(16.6, -2.25), "dir": [round(left[0], 4), round(left[1], 4)]},
        {"kind": "globe_lamp", "at": P(18.0, 2.3), "h": 2.7},
        {"kind": "manhole", "at": P(10.6, -0.6)},
        {"kind": "barrier", "at": P(21.6, 5.3), "dir": [round(left[0], 4), round(left[1], 4)], "len": 4.0},
        # motorbikes and scooters nose to the kerb all along the arcade (film 17-24 s), a gap
        # where the walk comes up off the road; two more parked out in the forecourt
        *[{"kind": "scooter" if i % 3 == 1 else "motorbike", "box": i % 4 == 2,
           "at": P((4.75 if abs(o + 17.3) < 3.6 else 4.3) + (0.15 if i % 2 else 0.0), o),   # (behind the railings)
           "dir": [round(-u[0], 4), round(-u[1], 4)]}
          for i, o in enumerate((-22.2, -21.2, -20.2, -19.2, -15.8, -14.8, -13.8, -12.8, -11.8, -10.6,
                                 -9.4, -8.2, -6.6, -5.5, -4.4, -3.2, -2.0))],
        {"kind": "scooter", "box": True, "at": P(8.2, -3.6), "dir": [round(left[0], 4), round(left[1], 4)]},
        # the zebra over Katzenelson (film 0-1 s and 15-17.5 s): a white hoop railing either
        # side of it on both kerbs, and the kerbs painted red and white 10 m each way
        *[{"kind": "hoop_railing", "at": P(sk, -17.35 + o), "dir": SE} for sk in (3.45, -14.15) for o in (-2.4, 2.4)],
        *[{"kind": "kerb_paint", "at": P(sk, -17.35 + o), "len": 10.0, "pat": "red_white"}
          for sk in (3.3, -14.0) for o in (-6.6, 6.6)],
        # Ha-Meri's entrance: the zebra on its raised crossing, a 30 painted in a red ring in
        # the lane in, and the zone 30 sign on the drivers' right as they turn in
        {"kind": "zebra", "at": P(92.4, 0), "dir": [round(u[0], 4), round(u[1], 4)], "w": 3.0, "len": 8.0},
        {"kind": "ring30", "at": P(99.5, 0.0), "dir": [round(u[0], 4), round(u[1], 4)]},
        {"kind": "zone30_sign", "at": P(95.6, -4.7), "dir": [round(-u[0], 4), round(-u[1], 4)]},
        # the little street (film 64-76 s): cars parked along its far side, in the road (the
        # corner block stands too near for the game to park them up on that kerb), and a
        # second transformer on twin poles at Sheinkin's corner
        *[{"kind": "parked_car", "at": P(s0, 1.75), "dir": [round(u[0], 4), round(u[1], 4)], "body": kd}
          for s0, kd in ((63.0, "suv"), (68.4, "hatch"), (73.8, "sedan"))],
        {"kind": "twin_poles", "at": P(78.4, -6.5), "dir": SE},
        {"kind": "scooter", "at": P(15.2, -5.2), "dir": [round(-u[0], 4), round(-u[1], 4)]},
    ],
    # the trees over the passage's mouth: in the planted bed, and in the yard behind the fence
    "trees": [P(19.6, 3.3), P(23.6, 3.8), P(21.5, -4.2), P(28.5, -4.8), P(35.5, -4.2),
              P(42.0, 3.6), P(42.5, -4.2), P(49.0, -4.5), P(55.0, -4.0)],   # and down the passage
    "walks": {
        "katzenelson_hameri": {
            "name": "Katzenelson to Ha-Meri, on foot",
            "points": walk,
            # the head turned from the way the walk goes: [from, to, degrees, + right]
            "looks": [[1.4, 3.9, -70], [3.9, 4.7, 30],          # the near half's traffic comes from the left
                      [8.9, 12.6, 70], [12.6, 13.4, 20],        # the far half's from the right
                      [79.3, 81.0, 60], [81.0, 82.3, -45],      # Sheinkin's from the right; and the other way
                      [84.4, 86.0, 40],                         # half way over, along Sheinkin again
                      [87.6, 88.6, -55], [89.0, 91.2, 55]],     # back at the corner; then down Ha-Meri
            # on a crossing, or waiting at its kerb about to go: cars stop for it
            # [from, to, kerb, kerb]
            "zebras": [[4.0, 8.9, P(-13.8, -17.4), P(-6.8, -17.4)],
                       [9.2, 17.0, P(-3.9, -17.35), P(3.1, -17.3)],
                       [81.0, 87.0, P(82.4, -4.2), P(90.4, -4.2)],
                       [87.2, 92.4, P(92.3, -4.0), P(92.3, 4.0)]],
            # cars sent down a street at a second, to meet the walk there: [second, at, heading]
            # (both halves of Katzenelson are one-way: the near one towards the north-west,
            # the far one towards the south-east; Sheinkin towards the south-east too)
            "cars": [[0.0, P(-10.2, 22), NW], [1.5, P(-10.2, 40), NW],              # one by, one stops
                     [5.0, P(-0.3, -45), SE], [6.5, P(-0.3, -62), SE], [7.5, P(-0.3, -70), SE],
                     [78.0, P(91.15, -55), SE]],
        }
    },
}
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "givatayim.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=1)
print("wrote", out, len(walk), "walk points, last t", walk[-1][0])
print("speeds:", [round(math.dist(walk[k][1:], walk[k+1][1:]) / max(walk[k+1][0]-walk[k][0], 1e-3), 2) for k in range(len(walk)-1)])
