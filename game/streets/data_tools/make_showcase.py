#!/usr/bin/env python3
"""Two made-up places that are not towns, to show the walks and the test drives need no real
city (the user, 22 Nov 2026: "a small scene with many of the objects, and i am just walking
around looking at the models; a small trick road where the car has ramps tunnels jumps
falls"). Both are city files in the format tools/osm_city.py documents, marked "made_up": 1
(no OSM credit), and loaded as any city is.

    python game/streets/data_tools/make_showcase.py            # writes both
    python game/streets/data_tools/make_showcase.py showroom   # or one: showroom | trick_road

showroom    cities/showroom.json + cities/details/showroom.json: a paved square ringed by a
            quiet street and a few blocks, its middle laid out in five rows of exhibits with
            four aisles between -- the trees of every form (north edge), the details file's
            street props, furniture.gd's kits, the CC0 models (playground, benches, lamps,
            the odd giant fork), the car kit's vehicles (south edge) -- and people standing
            about. Its walk (`showroom_walk`) goes up and down the aisles, stopping at each
            row's middle to look both ways and glancing to the sides between.
trick_road  cities/trick_road.json: a figure-of-eight circuit, one way, on open grass: a ramp
            up onto a bridge over its own other leg, a steep ramp down off the bridge (the
            car leaves it and lands on the slope), a kicker and a ditch across the road it
            jumps (the road goes down into the ditch and up: a car too slow drives through),
            a hill it tunnels through between two cuttings. The route set's drive for it is
            in routes.json (the last id), started by its level.

Everything here is metres on the city's ground, +x east, +z south; the file stores decimetres.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CITIES = os.path.join(HERE, "..", "cities")
S = 10   # decimetres


def rect(x0, z0, x1, z1):
    # counter-clockwise as the format keeps them (x east, z south)
    return [round(v * S) for v in (x0, z0, x1, z0, x1, z1, x0, z1)]


def r2(v):
    return round(v, 2)


# ---- the showroom ------------------------------------------------------------------------------

# (the rows 5 m from the aisles: at 11 m, the first layout, a hydrant was a speck across an
# empty square)
ROWS = {"trees": -24.0, "props": -11.0, "kits": -1.0, "models": 9.0, "cars": 21.0}   # z of each row
AISLES = [-16.0, -6.0, 4.0, 14.0]   # z of each aisle (the walk's line), between the rows
AISLE_X = 40.0     # the aisles run x -AISLE_X..AISLE_X (even: the 2 m steps land on the stops); the rows within +-37
PLAZA = (-46.0, -30.0, 46.0, 26.0)   # the paved square
RING = (54.0, -38.0, 34.0)   # the street round it: its middle line at x +-[0], z [1] and [2]
PACE = 1.3         # m/s: a stroll, a little slower than a street walk's 1.35


def showroom():
    nodes = []

    def node(x, z):
        nodes.extend([round(x * S), round(z * S)])
        return len(nodes) // 2 - 1

    RX, RN, RS = RING
    c = [node(-RX, RN), node(RX, RN), node(RX, RS), node(-RX, RS)]
    names = [("רחוב התצוגה", "Display Street"), ("רחוב הדגם", "Model Street"),
             ("רחוב המוצג", "Exhibit Street"), ("רחוב הגלריה", "Gallery Street")]
    roads = []
    for i in range(4):
        a, b = c[i], c[(i + 1) % 4]
        # a point in the middle of each side, so the side is not one long segment
        ax, az = nodes[2 * a] / S, nodes[2 * a + 1] / S
        bx, bz = nodes[2 * b] / S, nodes[2 * b + 1] / S
        m = node((ax + bx) / 2, (az + bz) / 2)
        roads.append({"n": [a, m, b], "k": "residential", "w": 8.0, "l": 2, "name": names[i][0],
                      "name_en": names[i][1], "sw": "both", "ms": 30})
    # a street out, east, so the traffic has somewhere to come from
    e1 = node(RX + 45.0, (RN + RS) / 2)
    mid_e = roads[1]["n"][1]
    roads.append({"n": [mid_e, e1], "k": "residential", "w": 8.0, "l": 2, "name": "רחוב היציאה",
                  "name_en": "Way Out Street", "sw": "both", "ms": 30})

    buildings = []
    years = [1958, 1966, 1972, 1985, 1998, 2008, 1962, 1978, 2015, 1955, 1990, 2003]
    i = 0
    for side in range(4):
        along = ((-50.0, -20.0), (-14.0, 14.0), (20.0, 50.0)) if side in (0, 2) else ((-36.0, -16.0), (-8.0, 6.0), (14.0, 32.0))
        for k, (a0, a1) in enumerate(along):
            if side == 1 and k == 1:
                continue   # (the street out goes there)
            h = [12.0, 15.0, 18.0, 21.0][(i * 3) % 4]
            if side == 0:
                p = rect(a0, RN - 22.0, a1, RN - 7.0)
            elif side == 2:
                p = rect(a0, RS + 7.0, a1, RS + 22.0)
            elif side == 1:
                p = rect(RX + 7.0, a0, RX + 22.0, a1)
            else:
                p = rect(-RX - 22.0, a0, -RX - 7.0, a1)
            buildings.append({"p": p, "h": h, "k": "apartments", "lv": int(h // 3), "yr": years[i % len(years)]})
            i += 1

    # the trees' row: one of each form the game draws, its crown as wide as a grown one
    forms = ["ficus", "fan", "date", "acacia", "round", "olive", "pine", "cypress", "eucalyptus"]
    crowns = [45, 25, 30, 40, 35, 30, 35, 12, 40]   # decimetres
    trees, tree_info = [], []
    for k, f in enumerate(forms):
        x = -34.0 + k * 8.5
        trees.extend([round(x * S), round(ROWS["trees"] * S)])
        tree_info.extend([k, crowns[k]])
    # and a few round the street's corners, in the gardens (no street trees are made up:
    # the file says it maps every tree)
    for x, z in ((-66, -50), (66, -50), (66, 46), (-66, 46)):
        trees.extend([x * S, z * S])
        tree_info.extend([0, 40])

    areas = [{"p": rect(*PLAZA), "k": "plaza"}]
    pois = [[round(-30.0 * S), round((RN - 7.5) * S), "cafe", "קפה התצוגה", "Showroom Cafe"],
            [round(30.0 * S), round((RS + 7.5) * S), "convenience", "מכולת", "Makolet"]]
    city = {
        "version": 1, "name": "The showroom", "source": "made up (data_tools/make_showcase.py)", "made_up": 1,
        "fetched": "", "origin": [0.0, 0.0], "scale": S, "bounds": [-100.0, -90.0, 100.0, 85.0],
        "boundary": [], "nodes": nodes, "roads": roads, "buildings": buildings, "areas": areas,
        "trees": trees, "tree_info": tree_info, "tree_forms": forms,
        "tree_surveys": [{"id": "showroom", "all": 1, "from": 0, "to": len(trees) // 2}],
        "signals": [], "crossings": [], "signs": [], "barriers": [], "pois": pois, "stops": [], "addrs": [],
    }

    # -- the rows -------------------------------------------------------------------------------
    props, show, people = [], [], []

    def row_x(n, span=72.0):
        return [-span / 2 + span * k / max(n - 1, 1) for k in range(n)]

    # street props (details.gd's kinds), facing south (the aisle they are looked at from first
    # is north of them, the walk comes back along the south side)
    z = ROWS["props"]
    P = [{"kind": "bin"}, {"kind": "hydrant"}, {"kind": "bollard"}, {"kind": "bollard", "top": "grey"},
         {"kind": "hoop_railing", "dir": [1, 0]}, {"kind": "twin_poles", "dir": [1, 0]},
         {"kind": "barrier", "dir": [1, 0], "len": 3.0}, {"kind": "globe_lamp", "h": 2.7},
         {"kind": "lamp_pole", "bin": True}, {"kind": "gatepost", "heart": True}, {"kind": "booth"},
         {"kind": "cabinet"}, {"kind": "sign_board"}, {"kind": "motorbike", "dir": [1, 0]},
         {"kind": "motorbike", "dir": [1, 0], "box": True}, {"kind": "scooter", "dir": [1, 0]},
         {"kind": "zone30_sign"}, {"kind": "no_uturn_sign"}, {"kind": "manhole"}]
    for x, p in zip(row_x(len(P)), P):
        q = {"dir": [0, -1]}
        q.update(p)
        q["at"] = [r2(x - (1.5 if q["kind"] == "barrier" else 0.0)), z]
        q["src"] = "showcase"
        props.append(q)

    # furniture.gd's kits (details.gd SHOW_KITS), facing north
    z = ROWS["kits"]
    K = [("paper_bin", None), ("cage", None), ("glass_bell", None), ("rack", None), ("bike", "signblue"),
         ("delivery", "signred"), ("dock", None), ("taxi_sign", None), ("notice", None), ("zone30", None),
         ("parking_sign", None), ("ornate", None), ("ornate_double", None), ("column", None),
         ("art0", None), ("art1", None), ("art2", None), ("cat_sit", None), ("cat_loaf", None),
         ("dog", None), ("pram", None), ("ac", None), ("pit", None), ("grate", None), ("board", None)]
    for x, (name, paint) in zip(row_x(len(K)), K):
        it = {"kind": "kit", "name": name, "at": [r2(x), z], "dir": [0, -1]}
        if paint:
            it["paint"] = paint
        if name in ("pit", "grate", "cat_sit", "cat_loaf", "dog", "pram"):
            it["r"] = 0.0 if name in ("pit", "grate") else 0.35
        show.append(it)

    # the CC0 models (assets/INDEX.md): the playground, benches, lamps, some fun
    z = ROWS["models"]
    M = [("slide", 4.9, 2.2), ("swings", 4.7, 2.0), ("seesaw", 3.4, 1.4), ("climber", 3.8, 1.9),
         ("spring_rider", 1.6, 0.7), ("bench", 1.7, 0.6), ("picnic", 1.8, 1.0), ("planter", 1.4, 0.6),
         ("fence-1x4", 3.0, 0.0), ("light-square", 4.5, 0.25), ("light-curved", 4.5, 0.25),
         ("tree-small", 3.0, 0.5), ("tree-large", 5.0, 0.7), ("craft_racer", 3.5, 1.4),
         ("craft_speederA", 3.0, 1.2), ("utensil-fork", 3.0, 0.4), ("plate", 1.6, 0.8), ("item-banana", 2.0, 0.6)]
    xs = []
    total = sum(m[1] for m in M) + 1.0 * (len(M) - 1)
    x = -total / 2
    for name, size, r in M:
        xs.append(x + size / 2)
        x += size + 1.0
    for x, (name, size, r) in zip(xs, M):
        show.append({"kind": "model", "name": name, "size": size, "at": [r2(x), z], "dir": [0, 1], "r": r})

    # the car kit's vehicles, side on to the aisle north of them
    z = ROWS["cars"]
    C = [("sedan", 4.5), ("taxi", 4.5), ("police", 4.7), ("suv", 4.8), ("van", 5.0), ("ambulance", 5.6),
         ("delivery", 5.5), ("truck", 7.0), ("firetruck", 8.0), ("garbage-truck", 7.5)]
    total = sum(cc[1] for cc in C) + 1.5 * (len(C) - 1)
    x = -total / 2
    for name, size in C:
        # (the car kit's models are long along their own z, so facing east they lie along the
        # aisle; scaled to their length they are wide -- the fire truck 3.5 m -- hence the row's
        # 7 m from the aisle)
        show.append({"kind": "model", "name": name, "size": size, "at": [r2(x + size / 2), z],
                     "dir": [1, 0], "car": True})
        x += size + 1.5

    # people standing about, off the aisles: in twos and threes talking, one or two looking
    def person(x, z, fx, fz, who, talk=False, tall=1.70):
        people.append({"at": [r2(x), r2(z)], "face": [fx, fz], "who": who, "talk": talk, "tall": tall})

    person(-26.0, -19.0, 1, 0, 0, True, 1.78)        # (by the trees)
    person(-24.9, -19.0, -1, 0, 1, True, 1.64)
    person(13.4, -3.4, 1, 0.3, 2, True, 1.74)         # (by the kits)
    person(14.6, -2.8, -0.6, -0.8, 3, True, 1.62)
    person(14.6, -4.0, -0.6, 0.8, 4, True, 1.69)
    person(-21.0, 16.8, 0, 1, 1, False, 1.66)        # (looking at the police car)
    person(-6.0, -20.0, 0, -1, 2, False, 1.80)       # (at the trees)
    person(29.5, 6.9, 0, -1, 4, True, 1.60)          # (by the models)
    person(29.5, 5.9, 0, 1, 0, True, 1.72)
    person(-31.0, 11.8, 0, -1, 3, False, 1.67)       # (at the slide)

    # -- the walk ------------------------------------------------------------------------------
    # up and down the aisles: east along the first, west along the second, ...; the turn at each
    # end a half circle round the rows' ends
    pts = []   # [t, x, z]
    looks = []
    faces = []
    t = 0.0
    last = None

    def go(x, z):
        nonlocal t, last
        if last is not None:
            t += math.hypot(x - last[0], z - last[1]) / PACE
        pts.append([r2(t), r2(x), r2(z)])
        last = (x, z)

    def wait(secs):
        nonlocal t
        t += secs
        pts.append([r2(t), r2(last[0]), r2(last[1])])

    stops = (-18.0, 18.0)
    for k, za in enumerate(AISLES):
        east = k % 2 == 0
        sgn = 1.0 if east else -1.0
        x0 = -AISLE_X * sgn
        if k == 0:
            go(x0, za)
        xs_walk = []
        x = x0
        while (x - AISLE_X * sgn) * sgn < 0:
            x += 2.0 * sgn
            xs_walk.append(min(x, AISLE_X) if east else max(x, -AISLE_X))
        # which row is on the left and the right: heading east, left is north (-z)
        glance_side = 1
        next_glance = t + 3.0
        for x in xs_walk:
            go(x, za)
            for sx in stops:
                if abs(x - sx) < 0.01:
                    # stop: the camera held on the row to the left, then the one to the right
                    # (`face`, bearings round the map: 0 east, 90 south; heading east the left is
                    # north). Held, not a head's turn: a body standing still keeps whatever facing
                    # it had, and a still taken after a jump in the clock faced anywhere
                    t0 = t
                    left = -90 if east else 90
                    faces.append([r2(t0 + 0.2), r2(t0 + 2.4), left])
                    faces.append([r2(t0 + 2.6), r2(t0 + 4.8), -left])
                    wait(5.0)
                    next_glance = t + 3.5
            if t >= next_glance and abs(x) < 36.0:
                looks.append([r2(t), r2(t + 2.2), 48 * glance_side])
                glance_side = -glance_side
                next_glance = t + 5.5
        if k + 1 < len(AISLES):
            # the turn: a half circle from this aisle to the next
            zb = AISLES[k + 1]
            cz = (za + zb) / 2
            rr = (zb - za) / 2
            for j in range(1, 12):
                a = math.pi * j / 12
                go(AISLE_X * sgn + math.sin(a) * rr * 0.8 * sgn, cz - math.cos(a) * rr)
            go(AISLE_X * sgn, zb)

    # someone strolling the third aisle the other way, 1.6 m to the side, timed to meet the walk
    # (the walk heads east along it: it walks west)
    za = AISLES[2] + 1.4
    tm = [p[0] for p in pts if abs(p[2] - AISLES[2]) < 0.01]
    if tm:
        t_from, t_to = tm[0] - 5.0, tm[0] + 72.0 / PACE * 0.9
        people.append({"at": [38.0, za], "to": [-38.0, za], "t": [r2(t_from), r2(t_to)], "who": 1, "tall": 1.68})

    walk = {"name": "The showroom: a walk among the models", "src": "showcase", "dodge": True,
            "points": pts, "looks": looks, "face": faces, "zebras": [], "people": people}
    details = {"walks": {"showroom_walk": walk}, "props": props, "show": show}
    _write(os.path.join(CITIES, "showroom.json"), city)
    _write(os.path.join(CITIES, "details", "showroom.json"), details, indent=1)
    print("showroom: walk %.0f m, %.0f s, %d stops; %d props, %d kits and models, %d people"
          % (sum(math.hypot(pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]) for i in range(len(pts) - 1)),
             pts[-1][0], 2 * len(AISLES), len(props), len(show), len(people)))


# ---- the trick road ----------------------------------------------------------------------------

A, B = 230.0, 180.0     # the figure of eight (a lemniscate of Gerono): x = A sin t, z = B sin t cos t
BASE = 0.0
GROUND = 10.0           # the open ground's height (m above BASE): room below it for the ditch
STEP = 2.0              # the height grid's step: the ditch and the kicker want it fine
X0, Z0, X1, Z1 = -300.0, -150.0, 300.0, 150.0
ROAD_W = 9.0
CLEAR = 7.4             # the bridge's deck over the road under it (6.4 m clear + the slab)
UP_GRADE = 0.07         # the ramp up to the bridge
LEDGE, LEDGE_L = 0.9, 1.5   # the bridge ends in a ledge: down this much in this far (the car leaves it)
DROP_GRADE = 0.15       # then the ramp down, the slope it lands on (a ramp alone, even at 32%, the
                        # springs' smoothing rides down without leaving it: tests/trick_road.gd)
HILL = (A, 0.0)         # the hill over the east loop's end
HILL_TOP = 28.0         # m above BASE (18 over the ground)
HILL_R0, HILL_R1 = 22.0, 55.0   # its flat top's radius, and how far its slopes run out beyond
COVER = 6.5             # ground this far over the road: a tunnel, not a cutting
# the jump (u: metres along the road from where the kicker starts): sized with a model of the
# car's air (streets.gd _fly: AIR_G 7.5, a take-off's lift x1.1 + 0.6, a landing over 5 m/s
# hard) so it lands on the far slope from 47 to 68 km/h -- see DEV.md
KICK_L, KICK_H = 24.0, 1.8      # the kicker: rising this long, this high, steepening to its lip
GAP, DITCH = 8.0, 2.5           # lip to the landing slope's top; the ditch this deep below GROUND
WALL = 3.0                      # its walls this long (more than a grid step: shorter came out in shards)
LAND_H, LAND_G = 1.4, 0.16      # the landing slope's top over GROUND, and its grade down
FLOOR = -2.0                    # it runs down to this under GROUND, then back up
BACK_G = 0.05                   # climbing back to the ground
ROUTE_ID, TRICK_LEVEL = 12, 36  # its drive's number in routes.json, and its level in LEVELS
JUMP_SPEED = 65                 # km/h: autodrive's limit along the jump's stretch
DROP_SPEED = 50                 # and over the bridge to the drop


def lemniscate(n=6000):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        pts.append((A * math.sin(t), B * math.sin(t) * math.cos(t), t))
    return pts


def jump_profile(u):
    """the ground's height (over GROUND) along the jump, u metres from the kicker's start"""
    if u < 0.0:
        return 0.0
    if u <= KICK_L:
        return KICK_H * (u / KICK_L) ** 2
    u1 = KICK_L + WALL
    if u <= u1:
        return KICK_H + (-DITCH - KICK_H) * (u - KICK_L) / WALL
    u2 = KICK_L + GAP - WALL
    if u <= u2:
        return -DITCH
    u3 = KICK_L + GAP
    if u <= u3:
        return -DITCH + (LAND_H + DITCH) * (u - u2) / WALL
    down = LAND_H - LAND_G * (u - u3)
    if down > FLOOR:
        return down
    u4 = u3 + (LAND_H - FLOOR) / LAND_G
    flat = u4 + 6.0
    if u <= flat:
        return FLOOR
    return min(0.0, FLOOR + BACK_G * (u - flat))


def jump_length():
    u4 = KICK_L + GAP + (LAND_H - FLOOR) / LAND_G
    return u4 + 6.0 + (-FLOOR) / BACK_G


def trick_road():
    import numpy as np
    raw = lemniscate()
    # resample at 1 m along its length, from t = 0 (the crossing, heading south-east)
    P = np.array([(p[0], p[1]) for p in raw] + [(raw[0][0], raw[0][1])])
    seg = np.hypot(*(P[1:] - P[:-1]).T)
    s_raw = np.concatenate([[0.0], np.cumsum(seg)])
    L = s_raw[-1]
    s = np.arange(0.0, L, 1.0)
    X = np.interp(s, s_raw, P[:, 0])
    Z = np.interp(s, s_raw, P[:, 1])
    n = len(s)
    # turned so the jump runs due east at its lip: along the height grid's rows, so the ditch's
    # walls lie along grid lines (across them at 28 degrees the ground came out in jagged shards)
    s_jump = 100.0
    li = int(s_jump + KICK_L)
    rot = -math.atan2(Z[li + 1] - Z[li - 1], X[li + 1] - X[li - 1])
    c, sn_ = math.cos(rot), math.sin(rot)
    X, Z = X * c - Z * sn_, X * sn_ + Z * c
    global X0, Z0, X1, Z1
    X0 = math.floor((X.min() - 70.0) / 10.0) * 10.0
    X1 = math.ceil((X.max() + 70.0) / 10.0) * 10.0
    Z0 = math.floor((Z.min() - 70.0) / 10.0) * 10.0
    Z1 = math.ceil((Z.max() + 70.0) / 10.0) * 10.0
    # the second time through the crossing (t = pi): where it is nearest the middle, half way round
    half = np.argmin(np.hypot(X[n // 4: 3 * n // 4], Z[n // 4: 3 * n // 4])) + n // 4
    s_cross2 = s[half]
    dirs = np.stack([np.roll(X, -1) - np.roll(X, 1), np.roll(Z, -1) - np.roll(Z, 1)], 1)
    dirs /= np.linalg.norm(dirs, axis=1)[:, None]

    def at(sv):
        i = int(round(sv)) % n
        return X[i], Z[i], dirs[i]

    # the road's surface, m over BASE, along s; and what each stretch is built as
    y = np.full(n, GROUND)
    kind = ["ground"] * n
    # the bridge over the first leg at the second crossing: up at UP_GRADE, a span of 50 m, then
    # down at DROP_GRADE -- the drop
    span = 25.0
    up_len = CLEAR / UP_GRADE
    drop_len = LEDGE_L + (CLEAR - LEDGE) / DROP_GRADE
    for i in range(n):
        d = s[i] - s_cross2
        if -span - up_len <= d < -span:
            y[i] = GROUND + CLEAR * (d + span + up_len) / up_len
            kind[i] = "em"
        elif -span <= d <= span:
            y[i] = GROUND + CLEAR
            kind[i] = "br"
        elif span < d <= span + LEDGE_L:
            y[i] = GROUND + CLEAR - LEDGE * (d - span) / LEDGE_L
            kind[i] = "em"
        elif span < d <= span + drop_len:
            y[i] = GROUND + CLEAR - LEDGE - DROP_GRADE * (d - span - LEDGE_L)
            kind[i] = "em"
    # the hill: where its ground stands over the road, a cutting, then the tunnel
    hx, hz = HILL[0] * c - HILL[1] * sn_, HILL[0] * sn_ + HILL[1] * c

    def hill_h(x, z):
        r = math.hypot(x - hx, z - hz)
        k = min(max((r - HILL_R0) / HILL_R1, 0.0), 1.0)
        k = k * k * (3 - 2 * k)
        return GROUND + (HILL_TOP - GROUND) * (1.0 - k)

    for i in range(n):
        if kind[i] != "ground":
            continue
        e = hill_h(X[i], Z[i]) - GROUND
        if e >= COVER:
            kind[i] = "tu"
        elif e > 0.4:
            kind[i] = "cu"
    # the jump: on the straight after the first crossing, well clear of the bridge's foot
    jl = jump_length()
    jx, jz, jd = at(s_jump)
    for i in range(n):
        if s_jump <= s[i] <= s_jump + jl:
            kind[i] = "jump"

    # -- the height grid --------------------------------------------------------------------------
    nx = int((X1 - X0) / STEP) + 1
    nz = int((Z1 - Z0) / STEP) + 1
    gx = X0 + STEP * np.arange(nx)
    gz = Z0 + STEP * np.arange(nz)
    GX, GZ = np.meshgrid(gx, gz)
    Hgr = np.full(GX.shape, GROUND)
    R = np.hypot(GX - hx, GZ - hz)
    k = np.clip((R - HILL_R0) / HILL_R1, 0.0, 1.0)
    k = k * k * (3 - 2 * k)
    Hgr = GROUND + (HILL_TOP - GROUND) * (1.0 - k)
    # the jump's ground: its profile across a band as wide as the road and its verges, fading out
    # beyond (a dug-out slope, not a cliff)
    nrm = np.array([-jd[1], jd[0]])
    U = (GX - jx) * jd[0] + (GZ - jz) * jd[1]
    V = (GX - jx) * nrm[0] + (GZ - jz) * nrm[1]
    prof = np.vectorize(jump_profile)(U)
    band = np.clip((np.abs(V) - 8.0) / 10.0, 0.0, 1.0)
    band = band * band * (3 - 2 * band)
    inside = (U > -5) & (U < jl + 5)
    Hgr = np.where(inside, Hgr + prof * (1.0 - band), Hgr)
    # the road's own corridor on the ground, held at the road's height side to side (the jump's
    # ground is the road's): the ground pieces are on the ground, so nothing to do but the
    # flat verge where the hill's foot meets them
    gi = [i for i in range(n) if kind[i] == "ground"]
    from_pts = np.stack([X[gi], Z[gi]], 1)
    # nearest ground road point to every grid point within 9 m: hold the ground to GROUND there
    flat = np.zeros(GX.shape, bool)
    for (px, pz) in from_pts[::2]:
        i0 = int((px - 9 - X0) / STEP)
        i1 = int((px + 9 - X0) / STEP) + 1
        j0 = int((pz - 9 - Z0) / STEP)
        j1 = int((pz + 9 - Z0) / STEP) + 1
        i0, j0 = max(i0, 0), max(j0, 0)
        sub = (GX[j0:j1, i0:i1] - px) ** 2 + (GZ[j0:j1, i0:i1] - pz) ** 2 < 81.0
        flat[j0:j1, i0:i1] |= sub
    Hgr = np.where(flat & ~inside, np.minimum(Hgr, GROUND + 0.0) + 0.0 * Hgr, Hgr)
    hgrid = [int(round((v - BASE) * S)) for v in Hgr.flatten()]
    # the jump's road must follow its ground exactly: the road's own points over it
    for i in range(n):
        if kind[i] == "jump":
            u = s[i] - s_jump
            y[i] = GROUND + jump_profile(u)

    # -- the roads: the loop cut where what it is built as changes, nodes every 6 m on the
    # ground, 2 m on the decks, 1 m on the jump ---------------------------------------------------
    nodes = []
    node_of = {}

    def node(i):
        i %= n
        if i in node_of:
            return node_of[i]
        nodes.extend([round(X[i] * S), round(Z[i] * S)])
        node_of[i] = len(nodes) // 2 - 1
        return node_of[i]

    # pieces: runs of one kind
    runs = []
    i = 0
    while i < n:
        j = i
        while j + 1 < n and kind[j + 1] == kind[i]:
            j += 1
        runs.append([kind[i], i, j + 1])   # [kind, first, one past the last]
        i = j + 1
    # the loop closes: the last run joins the first (both ground)
    roads = []
    step_of = {"ground": 6, "em": 1, "br": 2, "cu": 2, "tu": 3, "jump": 1}
    piece_names = {"ground": ("מסלול הפעלולים", "Trick Road"), "em": ("עליית הגשר", "Bridge Ramp"),
                   "br": ("גשר הקפיצה", "Jump Bridge"), "cu": ("חפירת הגבעה", "Hill Cutting"),
                   "tu": ("מנהרת הגבעה", "Hill Tunnel"), "jump": ("הקפיצה", "The Jump")}
    for kd, a, b in runs:
        st = step_of[kd]
        idx = list(range(a, b, st))
        idx.append(b)   # (shared with the next run's first point)
        ns = [node(i) for i in idx]
        r = {"n": ns, "k": "trunk", "w": ROAD_W, "l": 2, "o": 1, "name": piece_names[kd][0],
             "name_en": piece_names[kd][1], "ms": 70}
        if kd in ("em", "br", "cu", "tu"):
            r[kd] = 1
            r["y"] = [int(round((y[i % n] - BASE) * S)) for i in idx]
            r["ly"] = {"br": 1, "em": 1, "tu": -1, "cu": -1}[kd]
        if kd == "jump":
            r["ms"] = JUMP_SPEED
            r["sf"] = "asphalt"
        if kd in ("br",) or (kd == "em" and y[a] > y[min(b, n - 1)] + 0.5):
            r["ms"] = DROP_SPEED
        roads.append(r)

    # buildings: a pit garage and a stand by the start, a hut on the hill
    sx, sz, sd = at(s_cross2 - span - up_len - 90.0)
    sn = np.array([-sd[1], sd[0]])
    buildings = []
    for off, (w, d, h, k_) in ((18.0, (30, 12, 6.0, "garage")), (-20.0, (40, 8, 4.5, "grandstand"))):
        cx, cz = sx + sn[0] * off, sz + sn[1] * off
        buildings.append({"p": rect(cx - w / 2, cz - d / 2, cx + w / 2, cz + d / 2), "h": h, "k": k_})
    trees, tree_info = [], []
    import random
    rng = random.Random(7)
    for _ in range(260):
        x, z = rng.uniform(X0 + 10, X1 - 10), rng.uniform(Z0 + 10, Z1 - 10)
        d = np.min(np.hypot(X - x, Z - z))
        if d > 16.0 and math.hypot(x - jx, z - jz) > 60.0:
            trees.extend([round(x * S), round(z * S)])
            tree_info.extend([rng.choice([4, 6, 8]), rng.choice([30, 35, 40])])
    areas = [{"p": rect(X0 + 1, Z0 + 1, X1 - 1, Z1 - 1), "k": "grass"}]
    city = {
        "version": 1, "name": "The trick road", "source": "made up (data_tools/make_showcase.py)", "made_up": 1,
        "fetched": "", "origin": [0.0, 0.0], "scale": S, "bounds": [X0 + 20, Z0 + 20, X1 - 20, Z1 - 20],
        "boundary": [], "nodes": nodes, "roads": roads, "buildings": buildings, "areas": areas,
        "trees": trees, "tree_info": tree_info,
        "tree_forms": ["ficus", "fan", "date", "acacia", "round", "olive", "pine", "cypress", "eucalyptus"],
        "tree_surveys": [{"id": "trick_road", "all": 1, "from": 0, "to": len(trees) // 2}],
        "signals": [], "crossings": [], "signs": [], "barriers": [], "pois": [], "stops": [], "addrs": [],
        "height": {"x0": X0, "z0": Z0, "step": STEP, "nx": nx, "nz": nz, "base": BASE, "h": hgrid},
    }
    _write(os.path.join(CITIES, "trick_road.json"), city)
    # where things are, for the tests and the route (printed: tests/README.md, routes.json)
    def p(sv):
        x, z, d = at(sv)
        return "(%.1f, %.1f) heading %.0f" % (x, z, math.degrees(math.atan2(d[1], d[0])))
    s_start = s_cross2 - span - up_len - 60.0
    # its drive in the route set (ROUTE_ID): from before the ramp up, once round to 45 m short of
    # where it began (one way, so autodrive's way there is the whole loop)
    rp = os.path.join(HERE, "..", "routes.json")
    rs = json.load(open(rp, encoding="utf-8"))
    fx, fz, _d = at(s_start)
    tx, tz, _d = at(s_start - 45.0)
    entry = {"id": ROUTE_ID, "level": TRICK_LEVEL, "city": "trick_road", "place": "trick road",
             "from": "the start, before the ramp", "from_at": [r2(fx), r2(fz)], "to": "once round",
             "to_at": [r2(tx), r2(tz)], "crow_m": 45}
    rs["routes"] = [r for r in rs["routes"] if r["id"] != ROUTE_ID] + [entry]
    rs["routes"].sort(key=lambda r: r["id"])
    with open(rp, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(rs, ensure_ascii=False, indent=1))   # (as tests/pick_routes.py leaves it)
    print("trick road: %.0f m round, %d pieces; route %d in routes.json" % (L, len(roads), ROUTE_ID))
    for kd, a, b in runs:
        print("  %-6s s %6.0f-%6.0f  %s" % (kd, a, b, p(a)))
    print("  start  s %6.0f  %s" % (s_start % L, p(s_start)))
    print("  to     s %6.0f  %s" % ((s_start - 45.0) % L, p(s_start - 45.0)))
    print("  jump lip s %.0f %s; drop top s %.0f %s; tunnel" % (s_jump + KICK_L, p(s_jump + KICK_L),
                                                                  s_cross2 + span, p(s_cross2 + span)))
    # the curve's tightest radius on the jump and the drop (a car in the air flies straight)
    for name, s0, s1 in (("jump", s_jump, s_jump + 60), ("drop", s_cross2 + span, s_cross2 + span + 50)):
        hd = [math.atan2(*at(v)[2][::-1]) for v in range(int(s0), int(s1))]
        turn = max(abs((hd[i + 1] - hd[i] + math.pi) % (2 * math.pi) - math.pi) for i in range(len(hd) - 1))
        print("  %s: tightest radius %.0f m" % (name, 1.0 / max(turn, 1e-6)))


def _write(path, obj, indent=None):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, ensure_ascii=False, indent=indent, separators=None if indent else (",", ":"))
    print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    which = sys.argv[1:] or ["showroom", "trick_road"]
    if "showroom" in which:
        showroom()
    if "trick_road" in which:
        trick_road()
