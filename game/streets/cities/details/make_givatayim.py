"""Writes cities/details/givatayim.json: what a walk filmed in Givatayim showed along the
Ha-Meri passage that OpenStreetMap does not (see details.gd for the format, DEV.md "The filmed
walk" for how it was measured). Run it from anywhere: python3 make_givatayim.py

The file is shared: this script owns the items it writes (marked "src": "make_givatayim")
and the walk katzenelson_hameri, and keeps everything else in it as it is (another filmed
walk placed from its GPS track, its streets' kerb paint).

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
NW_U = [round(-u[0], 4), round(-u[1], 4)]          # back up the passage's line, towards Katzenelson
r2 = lambda p: [round(p[0], 2), round(p[1], 2)]

# the walk: landmarks timed to the film, the points between timed by distance
# Katzenelson by the film, half a second a frame: at the north kerb 1.6-4.5 s watching the
# traffic from the left (a white SUV goes by), over the near half, on the median 8.7-13.3 s
# watching the far half's from the right (cars stop at the zebra, one drives on), over it,
# the far kerb at 17 s. Its halves are set to 7 m (two lanes each, see "roads" below): the
# kerbs at -13.8 and 3.1, the median from -6.8 to -3.9; about 2.1-2.3 m/s over each half.
KERB_N, MEDIAN, KERB_S = P(-14.1, -17.4), P(-5.35, -16.6), tuple(P(3.3, -17.3))   # (in the median's cut, near its south-east side: film 7.7-9 s)
lm = [
    # (pass 12, the film a quarter second at a time: it stands 2 m back from the kerb facing
    # across till 2.7 s, a black bollard 2 m ahead at the zebra's north-west edge, then steps up
    # to the kerb beside it)
    (0.0, tuple(P(-16.4, -18.4))), (1.0, tuple(P(-16.0, -18.5))), (2.7, tuple(P(-16.0, -18.5))),
    (3.7, tuple(P(-14.25, -18.2))), (4.9, tuple(P(-14.25, -18.2))),   # at the north kerb, waiting
                                                                     # (the film steps off at 5.3 s)
    (8.7, tuple(MEDIAN)), (13.3, tuple(MEDIAN)),                            # over the near half; waiting
    (17.0, KERB_S), (18.4, tuple(P(6.4, -17.6))),                           # over the far half, up the kerb,
                                                                            # in past the arcade's middle column
    (21.0, tuple(P(6.6, -14.2))), (25.0, tuple(P(6.9, -9.0))),              # along it under the arcade (the
                                                                            # middle of it: the columns are at 5.2-5.8)
                                                                            # to its end, the block's corner (-9.4):
                                                                            # 1.3 m/s, the film's pace (pass 14)
    # (pass 14, measured on the film's frames: it comes out from under the arcade at the block's
    # corner, not by the passage's line -- the two women 6.4 m ahead at 26 s, the transformer's
    # poles 16 degrees left of them -- and crosses the forecourt on a slant at 2 m/s, between
    # the bollards, past the transformer's plinth close on its right into the passage)
    (26.0, tuple(P(7.6, -8.3))), (None, tuple(P(10.2, -6.6))), (None, tuple(P(12.4, -4.2))),
    (None, tuple(P(13.6, -2.4))), (None, tuple(P(15.0, -1.4))),
    (33.0, tuple(P(16.6, -0.6))), (None, tuple(P(19.0, -0.1))),
    (None, tuple(P(30))), (None, tuple(P(45))),
    (64.0, tuple(P(57.6, -0.95))),                             # out of it right of the railings
    # (pass 14: the film walks straight on out of the passage along the hedge, the railings and
    # the man in blue on its left -- the little street's pavement is the passage's line, 65-80 s)
    (None, tuple(P(61.0, -0.9))), (None, tuple(P(77.0, -0.9))),
    (80.0, tuple(P(80.0, -2.4))), (81.5, tuple(P(82.0, -4.2))),  # the corner, at the kerb (between
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

# from the far kerb on (17 s), the walk at the film's own pace and the head turned as the
# film's is, both measured off the film frame by frame (tests/film_motion.py, fitted by
# tests/film_fit.py onto the replay's own path: the same streets, the film's timing) -- in
# katzenelson_fit.json beside this. Re-fit it after moving any point above past 17 s: it
# follows the path the replay walked when it was measured.
FIT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "katzenelson_fit.json")
head = []
if os.path.exists(FIT):
    fit = json.load(open(FIT))
    t0 = fit["points"][0][0]
    walk = [w for w in walk if w[0] < t0] + fit["points"]
    head = fit["head"]
    # under the arcade the film's facing reads only half its turn (the columns, the ceiling
    # and the motorbikes a metre or two off drag the far band's slide): its frames look along
    # the arcade from 19.5 s, the motorbikes on the left, the shops on the right -- so the head
    # stays with the body there, eased in and out over half a second (pass 14: the fitted head
    # had the camera half a metre from the shop windows, 18-24 s)
    # -- and that way is a little left of straight along it, towards the motorbikes (19.5-23 s:
    # the motorbikes in the middle of its frame, the shops at its right edge)
    # Likewise across the forecourt (28-32 s) its facing reads 20 degrees right of what the
    # frames show: the barrier's post left of the middle, the lamp right of it, the
    # transformer's poles at the right edge -- added there ("add"), the rest replaced.
    for a, e, deg, how in ((17.6, 18.9, 0.0, "set"), (18.9, 24.2, -20.0, "set"), (27.6, 32.2, -20.0, "add")):
        for h in head:
            w = min(1.0, max(0.0, (h[0] - (a - 0.5)) / 0.5), max(0.0, ((e + 0.5) - h[0]) / 0.5))
            h[1] = round(h[1] + deg * w if how == "add" else h[1] * (1.0 - w) + deg * w, 1)
    # the walk leaves the passage's line only past its hedge's end (its body reaches a metre
    # out from its line: the fitted path stepped right two seconds early and brushed it)
    for w in walk:
        if w[0] > 50.0:
            ds, do = w[1] - S0[0], w[2] - S0[1]
            s_, o_ = ds * u[0] + do * u[1], ds * left[0] + do * left[1]
            if 40.0 < s_ < 58.6 and o_ < -0.45:
                w[1], w[2] = round(S0[0] + u[0] * s_ - left[0] * 0.45, 2), round(S0[1] + u[1] * s_ - left[1] * 0.45, 2)

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
            # (its own paving grey pavers in rows, as the passage's area under it: the city's
            # paving drawn along it stood over the area, beige and pink bricks where the film
            # walks on grey, 33-64 s)
            {"pts": [list(S0), P(SPLIT)], "k": "footway", "w": 2.6, "name": "המרי", "name_en": "HaMeri", "pave": [0, 1]},
            # (left of the passage's line, not on it: the film walks straight on out of the
            # passage onto the pavement along the hedge, the road beyond the railings, 64-80 s;
            # the blocks either side stand 11 m apart, so a narrow street with cars parked by
            # the south-east blocks)
            {"pts": [P(SPLIT, 2.4), P(79.5, 2.4), list(S1)], "k": "residential", "w": 4.0, "name": "המרי", "name_en": "HaMeri"},
        ],
    },
    "crossings": [[661.6, -672.2], [655.1, -664.7]],
    # the bollards round Sheinkin's corner with Ha-Meri are white (film 76-86 s)
    "white_bollards": [{"near": P(86.0, -2.0), "r": 12.0}],
    # Sirkin, where the Sheinkin-Sirkin walk waits and looks left to the shops (its 70-74 s):
    # no car parked beside it, nor across the way in the line to the shops
    "no_parking": [{"near": [485.5, -737.5], "r": 8.0}, {"near": [478.5, -742.0], "r": 8.0},
                   # (walk 2, 28-32 s: the city parked a car half up on its pavement there)
                   {"near": [484.6, -686.6], "r": 4.0},
                   # the little street (pass 14): the city parked one half up on the pavement the
                   # walk goes along; the film's cars there are the details' own, by the far side
                   *[{"near": P(s0, 0.0), "r": 4.0} for s0 in (59.0, 64.0, 69.0, 74.0, 78.5)],
                   # Ha-Meri's far kerb past the crossing: the film's silver hatchback is there
                   # (a prop), in the road; the game parked one half up on the pavement
                   {"near": P(96.0, 4.6), "r": 2.5}],
    # bare where the film is bare: the little street's pavement by the graffiti gatepost (film
    # 71-76 s) had a front garden's bougainvillea hung across it at eye height
    # (and the kerbside furniture off the pavement the walk now goes along, 64-80 s: pass 14)
    "clear": [{"near": [616.0, -601.3], "r": 3.0}, *[{"near": P(s0, -0.6), "r": 2.6} for s0 in (60.0, 64.5, 69.0, 73.5, 78.0)],
              {"near": P(95.0, 5.4), "r": 3.0}],   # and Ha-Meri's far pavement where it steps up
    # the block at the passage's north-west corner stands on columns along Katzenelson: shops
    # 3 m back under the upper floors, the walk goes between them and the columns (film 18-23 s)
    "buildings": [{"near": P(15, -15), "arcade": [list(ARC_A), list(ARC_E)], "depth": ARC_DEPTH, "h": 3.4}],
    # paving level with the pavement (film 17-33 s): charcoal herringbone from the kerb in
    # under the arcade, then the forecourt's pale poured slabs, laid square to the passage, out
    # to the two blocks either side and round into the drive past the barrier
    "surfaces": [
        {"k": "pavers_dark", "lift": 0.14, "p": [P(3.35, -23.6), P(3.35, -6.0), P(8.4, -6.0), P(8.4, -23.6)]},
        # Katzenelson's crossing (film 1-9 s): buff domed slabs along the north kerb across the
        # zebra and filling the cut through the median, the median's ends either side of the cut
        # raised blocks -- a grey concrete kerb round red pavers -- sloping down to the median
        # further off (the zebra 3 m wide: off -18.87 to -15.87)
        {"k": "tactile", "lift": 0.14, "lay": SE, "p": [P(-14.6, -19.3), P(-14.0, -19.3), P(-14.0, -15.45), P(-14.6, -15.45)]},
        {"k": "tactile", "lift": 0.15, "lay": SE, "p": [P(-6.6, -18.9), P(-4.1, -18.9), P(-4.1, -15.85), P(-6.6, -15.85)]},
        *[{"k": k, "lift": lift, "lay": SE, "ramps": [[P(-5.35, far), P(-5.35, far + (1.4 if far < -17 else -1.4))]],
           "p": [P(-6.65 + i, a), P(-4.05 - i, a), P(-4.05 - i, e), P(-6.65 + i, e)]}
          for (a, e, far) in ((-24.0 + 0.0, -18.9, -24.0), (-15.85, -10.0, -10.0))
          for (k, lift, i) in (("kerb", 0.3, 0.0), ("pavers_red", 0.31, 0.15))],
        {"k": "slabs", "lift": 0.14, "lay": [round(u[0], 4), round(u[1], 4)],
         "p": [P(3.35, -6.0), P(8.4, -6.0), P(8.4, -9.0), P(17.1, -8.6), P(17.1, 1.35), P(17.1, 5.0),
               P(22.0, 5.0), P(22.0, 10.5), P(16.3, 10.5), P(16.3, 5.4), P(3.35, 5.4)]},
        # the passage itself (film 33-64 s): small grey pavers in rows across it, each row half
        # a paver on, level with the forecourt, fence to fence
        {"k": "pavers_grey", "lift": 0.14, "lay": [round(left[0], 4), round(left[1], 4)],
         "p": [P(17.1, -1.35), P(57.8, -1.35), P(57.8, 1.35), P(17.1, 1.35)]},
        # the little street's pavement the walk is on (film 64-80 s): the same grey pavers in rows,
        # on from the passage's end along the hedge
        # (6 cm over the usual: the city's pavement there stood over it, its red pavers showing)
        {"k": "pavers_grey", "lift": 0.2, "lay": [round(left[0], 4), round(left[1], 4)],
         "p": [P(57.8, 0.3), P(79.5, 0.3), P(79.5, -1.85), P(57.8, -1.85)]},
        # Ha-Meri's mouth past Sheinkin (film 86.5-92.5 s): a raised crossing, the road paved in
        # charcoal herringbone up to the pavements' height, a metre's ramp either end
        {"k": "pavers_dark", "lift": 0.14,
         "p": [P(89.6, -4.0), P(96.0, -4.0), P(96.0, 4.0), P(89.6, 4.0)],
         "ramps": [[P(89.6, 0), P(90.6, 0)], [P(96.0, 0), P(95.0, 0)]]},
    ],
    "lines": [
        {"kind": "stone_wall", "pts": [P(17, -1.35), P(38, -1.35)], "h": 0.8},
        {"kind": "wood_fence", "pts": [P(17, -1.35), P(38, -1.35)], "base": 0.75, "h": 1.15},
        {"kind": "hedge", "pts": [P(38, -1.5), P(57.6, -1.5)]},
        # (on past the passage's end along the pavement, half a metre back: pass 14)
        {"kind": "hedge", "pts": [P(57.9, -2.0), P(65.6, -2.0)]},
        {"kind": "hedge", "pts": [P(69.4, -2.0), P(76.6, -2.0)]},        # (past the gate)
        {"kind": "loop_fence", "pts": [P(17, 1.35), P(56, 1.35)], "h": 0.9},
        {"kind": "loop_fence", "pts": [P(17.2, 5.0), P(17.2, 1.35)], "h": 0.9},   # round the planted bed's front
        # the planted bed behind the white fence, and its strip on along the next block
        {"kind": "hedge", "pts": [P(17.8, 2.4), P(25.8, 2.4)]},
        {"kind": "hedge", "pts": [P(18.2, 4.1), P(21.5, 4.1)]},
        {"kind": "hedge", "pts": [P(26.2, 2.1), P(38.5, 2.1)]},
        # and above them what the film shows walking down it: tall planting 2.5-3 m on both
        # sides (shrubs, bamboo, palms) that closes it in, the blocks behind barely seen
        {"kind": "shrubs", "pts": [P(17.8, 2.7), P(21.0, 2.7)], "h": 1.0},   # (low at the front: the film sees
        {"kind": "shrubs", "pts": [P(21.4, 2.7), P(25.4, 2.7)], "h": 2.6},   # the barrier over it, 29-32 s)
        {"kind": "shrubs", "pts": [P(26.0, 2.2), P(39.0, 2.2)], "h": 2.4},
        {"kind": "shrubs", "pts": [P(39.5, 2.4), P(44.5, 2.4)], "h": 2.8},
        {"kind": "shrubs", "pts": [P(45.0, 2.0), P(56.0, 2.0)], "h": 2.4},
        {"kind": "shrubs", "pts": [P(18.0, -2.7), P(37.8, -2.7)], "h": 2.4},   # over the wooden fence
        {"kind": "shrubs", "pts": [P(38.2, -2.0), P(57.6, -2.0)], "h": 3.0},   # the tall hedge on the low wall
        {"kind": "shrubs", "pts": [P(57.9, -2.5), P(65.6, -2.5)], "h": 3.0},
        # the shops under the arcade (film 15-23 s): lit glass in light frames, each its own
        # sign; the confectionery's, dark brown, faces the zebra
        {"kind": "shopfront", "pts": SHOPS, "h": 2.75, "face": [round(-ARC_IN[0], 4), round(-ARC_IN[1], 4)],
         "signs": ["", "קונדיטוריה", "", ""], "panels": [1]},   # (only the film's shop is named)
        # the little street to Sheinkin (film 64-78 s): the passage's tall hedge on along the
        # back of the pavement the walk is on, a gate in it (66-69)
        {"kind": "shrubs", "pts": [P(69.4, -2.5), P(76.6, -2.5)], "h": 2.4},
        # the forecourt's yard (film 25-27 s): a low wall of dark boards on stone behind the two
        # women, from the passage's fence across to the block on the right
        {"kind": "stone_wall", "pts": [P(17.1, -1.35), P(17.1, -6.2)], "h": 0.5},
        {"kind": "wood_fence", "pts": [P(17.1, -1.35), P(17.1, -6.2)], "base": 0.45, "h": 0.85},
    ],
    "props": [
        {"kind": "bin", "at": P(41, -0.95)},
        # the railings across the passage's end, its left two thirds (film 61-66 s: the walk goes
        # by the right one's post, the hedge on its right)
        {"kind": "hoop_railing", "at": P(57.75, 0.55), "dir": SE},
        # the forecourt (film 24-33 s): a loose row of bollards across it with a gap to walk
        # through, one more at the passage's mouth; the transformer's twin poles on their plinth
        # just right of the mouth; a garden lamp at the bed's corner; a manhole in the slabs;
        # the barrier across the drive to the next block's car park
        *[{"kind": "bollard", "at": P(13.6, o)} for o in (-6.6, -5.0, -3.4, -1.0, 1.0, 2.6, 4.2)],
        {"kind": "bollard", "at": P(15.3, 0.2)},
        {"kind": "twin_poles", "at": P(16.6, -2.25), "dir": [round(left[0], 4), round(left[1], 4)]},
        # (pass 14: the lamp between the barrier's post and the poles as the film sees them, 29-32 s;
        # the manhole 4 m ahead of the walk out of the arcade, a little right, 26 s; a grey cabinet
        # at the yard wall's end by the block, behind the man in white)
        {"kind": "globe_lamp", "at": P(19.3, 1.7), "h": 2.7},
        {"kind": "manhole", "at": P(12.0, -7.3)},
        {"kind": "cabinet", "at": P(16.9, -6.9), "dir": NW_U},
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
        # (the north kerb's north-west one a metre further off: the film waits beside the zebra
        # with nothing between it and the road, 1-4.5 s)
        *[{"kind": "hoop_railing", "at": P(sk, -17.35 + o - (1.2 if sk < 0 and o < 0 else 0.0)), "dir": SE}
          for sk in (3.45, -14.15) for o in (-2.4, 2.4)],
        # the north kerb bare grey across the zebra (the city painted it blue and white there)
        {"kind": "kerb_paint", "at": P(-14.0, -17.37), "len": 3.6, "pat": "plain"},
        # a black bollard with a steel top on the domed slabs at the zebra's north-west edge
        # (film 1-3 s), and the round "no U-turn" sign on the median's raised end by the cut,
        # facing the near half's drivers (film 7.6-8.6 s)
        {"kind": "bollard", "top": "grey", "at": P(-14.15, -18.95)},
        {"kind": "no_uturn_sign", "at": P(-6.25, -15.5), "dir": SE},
        *[{"kind": "kerb_paint", "at": P(sk, -17.35 + o), "len": 10.0, "pat": "red_white"}
          for sk in (3.3, -14.0) for o in (-6.6, 6.6)],
        # Ha-Meri's entrance: the zebra on its raised crossing, a 30 painted in a red ring in
        # the lane in, and the zone 30 sign on the drivers' right as they turn in
        {"kind": "zebra", "at": P(92.4, 0), "dir": [round(u[0], 4), round(u[1], 4)], "w": 3.0, "len": 8.0},
        {"kind": "ring30", "at": P(99.5, 0.0), "dir": [round(u[0], 4), round(u[1], 4)]},
        {"kind": "zone30_sign", "at": P(95.6, -4.7), "dir": [round(-u[0], 4), round(-u[1], 4)]},
        # Ha-Meri's far kerb where the walk steps up (film 91-95 s): a silver hatchback parked
        # just past the raised crossing, its kerb blue and white (the game painted it red and
        # white as a corner's, and stood a front yard's car on the pavement there: `clear`)
        {"kind": "parked_car", "at": P(97.8, 3.05), "dir": [round(u[0], 4), round(u[1], 4)], "body": "hatch", "paint": "silver"},
        {"kind": "kerb_paint", "at": P(97.5, 4.0), "len": 13.0, "pat": "blue_white"},
        # the little street (film 64-76 s): cars parked along its far side, in the road (the
        # corner block stands too near for the game to park them up on that kerb), and a
        # second transformer on twin poles at Sheinkin's corner
        *[{"kind": "parked_car", "at": P(s0, 3.45), "dir": [round(u[0], 4), round(u[1], 4)], "body": kd}
          for s0, kd in ((64.5, "suv"), (69.6, "hatch"), (74.6, "sedan"))],
        {"kind": "twin_poles", "at": P(78.4, -3.0), "dir": SE},   # (close on the walk's right, film 78 s)
        # the little street's gate (film 66-70 s): two concrete posts, a heart sprayed on one
        {"kind": "gatepost", "at": P(65.9, -2.2), "dir": SE, "heart": True},
        {"kind": "gatepost", "at": P(69.1, -2.2), "dir": SE},
        # over Sheinkin, on its far corner by Ha-Meri (film 82-86 s): the blue pay booth, a
        # yellow parking board, scooters by it (between the zebra's bollards and a sign pole)
        {"kind": "booth", "at": P(92.1, -7.4), "dir": [round(-u[0], 4), round(-u[1], 4)]},
        {"kind": "sign_board", "at": P(91.4, -8.0), "dir": [round(-u[0], 4), round(-u[1], 4)]},
        {"kind": "scooter", "at": P(91.6, -6.4), "dir": [round(-u[0], 4), round(-u[1], 4)]},
        {"kind": "scooter", "box": True, "at": P(92.3, -8.4), "dir": [round(-u[0], 4), round(-u[1], 4)]},
        {"kind": "scooter", "at": P(13.7, -5.3), "dir": SE},   # (side on, left of the women: film 25-26 s)
    ],
    # the trees over the passage's mouth: in the planted bed, and in the yard behind the fence
    "trees": [P(19.6, 3.3), P(23.6, 3.8), P(21.5, -4.2), P(28.5, -4.8), P(35.5, -4.2),
              P(42.0, 3.6), P(42.5, -4.2), P(49.0, -4.5), P(55.0, -4.0)],   # and down the passage
    "walks": {
        "katzenelson_hameri": {
            "name": "Katzenelson to Ha-Meri, on foot",
            "points": walk,
            # [second, degrees right of the body] every quarter second, as the film's head
            # turned (katzenelson_fit.json): where it runs, the looks below only tip the phone
            # up and down
            "head": head,
            # the head turned from the way the walk goes: [from, to, degrees, + right] and, if
            # given, degrees up (the phone already tilts 15.6 down: streets.gd's FILM_TILT)
            # (pass 14, read off the zebra's stripes and the bollard in the film's own frames --
            # an ffmpeg seek before the input lands on a frozen frame for the clip's first 8 s,
            # which pass 12's "faces straight across, 1-2.5 s" was read from: it faces a little
            # left of across, the bollard at its frame's right edge (1 s), then left at the near
            # half's cars coming, the zebra in the right of its frame (3-5 s); on the median it
            # faces across a touch left, the zebra right of the middle (11-13.5 s); and it looks
            # up at the confectionery's front as it reaches the far kerb (15.5 s))
            "looks": [[0.0, 1.6, -28],
                      [3.0, 5.1, -25],
                      [5.4, 8.8, 0, -30],                       # then down at the stripes, a foot in shot (6.5 s)
                      [8.9, 12.6, -12], [12.6, 13.4, -16],
                      [15.1, 15.9, 0, 20],
                      [79.3, 81.0, 60], [81.0, 82.3, -45],      # Sheinkin's from the right; and the other way
                      [84.4, 86.0, 40],                         # half way over, along Sheinkin again
                      [87.6, 88.6, -55], [89.0, 92.5, 55],      # back at the corner; then down Ha-Meri,
                                                                # the hatchback ahead by the kerb (to 92.3)
                      [92.5, 95.6, -10, -22]],                  # down at the far kerb's blue and white
                                                                # as it steps up beside a parked car (not
                                                                # right: a tree pit stands there, 0.6 m off)
            # on a crossing, or waiting at its kerb about to go: cars stop for it
            # [from, to, kerb, kerb]
            "zebras": [[4.4, 8.9, P(-13.8, -17.4), P(-6.8, -17.4)],
                       [9.2, 17.0, P(-3.9, -17.35), P(3.1, -17.3)],
                       [81.0, 87.0, P(82.4, -4.2), P(90.4, -4.2)],
                       [87.2, 92.4, P(92.3, -4.0), P(92.3, 4.0)]],
            # cars sent down a street at a second, to meet the walk there: [second, at, heading]
            # (both halves of Katzenelson are one-way: the near one towards the north-west,
            # the far one towards the south-east; Sheinkin towards the south-east too)
            # who the film shows (people last, as asked): a man by the railing at the far kerb,
            # two women talking in the forecourt by the scooter, a man at the passage's end
            # (pass 13, the film two frames a second: the man by the far kerb's railing walks there
            # along the confectionery's front, 13.5-16.5 s, and stands; a third in white stands
            # with the two women, all three talking -- turning to each other and back, the
            # characters have no clip for it; a woman in black crosses the passage's end in front
            # of the man in blue, 59.5-62 s)
            "people": [{"at": P(6.5, -12.5), "to": P(4.6, -20.6), "t": [12.6, 16.6], "stay": True, "who": 0},
                       # (pass 14: 6.4 m ahead of the walk as it comes out of the arcade at 26 s, the
                       # scooter just left of them, the man in white further right by the cabinet)
                       # (both women's fronts to the camera, the man in white turned to them)
                       {"at": P(14.0, -6.1), "face": [round(-u[0] - 0.1 * left[0], 4), round(-u[1] - 0.1 * left[1], 4)], "who": 1, "talk": True},
                       {"at": P(14.2, -6.8), "face": [round(-u[0] + 0.15 * left[0], 4), round(-u[1] + 0.15 * left[1], 4)], "who": 3, "talk": True},
                       {"at": P(15.9, -7.4), "face": [round(-u[0] + 0.5 * left[0], 4), round(-u[1] + 0.5 * left[1], 4)], "who": 2,
                        "talk": True, "tall": 1.78},
                       # (walking up to the passage's end as the walk comes out of it, then standing)
                       # (pass 14: just past the railings, by the pavement's kerb -- the walk goes by
                       # him close on its left at 66 s)
                       {"at": P(61.4, 0.5), "to": P(59.8, -0.1), "t": [59.0, 61.0], "stay": True, "who": 2},
                       {"at": P(61.0, -0.7), "to": P(60.0, 3.6), "t": [59.4, 62.6], "who": 4}],
            # [second, at, heading] and what the film shows of it: "lane" kerb or median,
            # "through" (it drives on past the walk at the zebra), "kind"
            # the near half's (film 1-4.5 s): a black hatchback by in the lane by the median
            # (about 2 s), a white SUV close past the kerb (3-4 s); then one that stops
            "cars": [[0.0, P(-10.2, 3.6), NW, {"lane": "median", "kind": "hatch", "paint": "black"}],
                     # (sent from past a junction 32 m up, where a car sent further off was held 2 s)
                     [0.5, P(-10.2, 10.0), NW, {"lane": "kerb", "through": True, "kind": "suv", "paint": "white"}],
                     [1.5, P(-10.2, 40), NW, {"kind": "sedan"}],
                     # the far half's: a white hatchback by in the lane by the median as the walk
                     # reaches it (film 8.5-9 s), a white sedan stopped in the kerb lane (9.5-12 s),
                     # then a grey SUV driving on in the median lane past the walk waiting there
                     # (12-13 s). Each is sent 28 m off at 70% of the street's pace: 2.5 s.
                     [6.4, P(-0.3, -45), SE, {"lane": "median", "through": True, "kind": "hatch", "paint": "white"}],
                     [6.5, P(-0.3, -62), SE, {"lane": "kerb", "kind": "sedan", "paint": "white"}],
                     [7.5, P(-0.3, -70), SE, {"lane": "kerb"}],
                     # (sent half a second early: the street's other traffic slows it on its way, 0-1.5 s run to run)
                     [9.5, P(-0.3, -45), SE, {"lane": "median", "through": True, "kind": "suv", "paint": "grey"}],
                     [78.0, P(91.15, -55), SE]],
        }
    },
}
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "givatayim.json")
# The file is shared: another filmed walk (placed from its GPS track) and its streets' kerb
# paint were put in by hand. This script owns only what it writes, each item marked
# "src": SRC; on a re-run its old items go and everyone else's are kept: walks it does not
# write, unmarked items in every list (the first run after marking also drops an unmarked
# item equal to one of its own), [x, z] pairs it does not write, keys it does not use.
SRC = "make_givatayim"
def _mark(sec):
    for item in sec:
        if isinstance(item, dict):
            item["src"] = SRC
for sec in ("drop", "set", "add"):
    _mark(d["roads"].get(sec, []))
for sec in ("buildings", "surfaces", "lines", "props", "areas", "white_bollards", "no_parking", "clear"):
    _mark(d.get(sec, []))
def _bare(item):
    return {k: v for k, v in item.items() if k != "src"} if isinstance(item, dict) else item
def _keep(old_list, new_list):
    mine = [_bare(i) for i in new_list]
    kept = []
    for item in old_list:
        if isinstance(item, dict):
            if item.get("src") == SRC or _bare(item) in mine:
                continue
        elif item in new_list:
            continue
        kept.append(item)
    return new_list + kept
if os.path.exists(out):
    with open(out, encoding="utf-8") as f:
        old = json.load(f)
    for key, val in old.items():
        if key == "walks":
            for wid, w in val.items():
                d["walks"].setdefault(wid, w)
        elif key == "roads":
            for sec, lst in val.items():
                d["roads"][sec] = _keep(lst, d["roads"].get(sec, []))
        elif key not in d:
            d[key] = val
        elif isinstance(val, list) and isinstance(d[key], list):
            d[key] = _keep(val, d[key])
with open(out, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=1)
print("wrote", out, len(walk), "walk points, last t", walk[-1][0])
print("speeds:", [round(math.dist(walk[k][1:], walk[k+1][1:]) / max(walk[k+1][0]-walk[k][0], 1e-3), 2) for k in range(len(walk)-1)])
