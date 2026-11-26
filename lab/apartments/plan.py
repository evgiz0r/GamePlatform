#!/usr/bin/env python3
"""Apartment floor plans, made up from a seed: one Israeli-style flat (Givatayim / Tel Aviv
block of the 2000s), its rooms, walls, doors, windows and a first crude set of furniture.

    python3 lab/apartments/plan.py --seed 7              # one plan -> out/plan_7.png + .json
    python3 lab/apartments/plan.py --sheet 1-6           # six seeds on one picture

Not part of any game yet: a lab bench to iterate the layouts on in pictures first. The JSON
is meant to be what a later 3D builder reads (everything in metres, x right, y away from
the stairwell towards the balcony).

How a plan is made (crude on purpose, see README.md):
  * the flat is a W x D rectangle with the stairwell behind it (y = 0) and the balcony
    (mirpeset) hung off the front;
  * three strips: a back strip of small rooms (entrance, toilet, bathroom, mamad,
    bedrooms), a hall running the whole width, and a front strip of kitchen, salon and the
    parents' room (with its own shower room carved out of a corner);
  * everything is painted into a 10 cm grid of room ids; a wall is wherever two
    neighbouring cells differ, unless the two rooms are open to each other;
  * doors are cut into the longest shared wall run near a corner, windows centred in each
    room's longest outside wall;
  * furniture is placed by trying every spot along every wall and keeping the best scoring
    one that is inside the room, backed by a real wall and clear of the door swings.
"""
import argparse
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

DM = 0.1  # one grid cell, metres

# wall thickness by kind, decimetres (cells)
THICK = {"ext": 2.5, "mamad": 3.0, "wall": 1.0, "window": 2.5, "rail": 0.6}
SOLID = {"ext", "mamad", "wall", "window"}

NAMES = {
    "entrance": "entrance", "hall": "hall", "salon": "salon", "kitchen": "kitchen",
    "mamad": "mamad", "bedroom": "bedroom", "parents": "parents' room", "ensuite": "shower",
    "bath": "bathroom", "toilet": "toilet", "mirpeset": "mirpeset",
}
FLOOR = {  # plan fill per room kind
    "entrance": (236, 230, 220), "hall": (240, 236, 228), "salon": (247, 236, 214),
    "kitchen": (232, 240, 230), "mamad": (222, 224, 230), "bedroom": (236, 228, 244),
    "parents": (240, 226, 236), "ensuite": (222, 236, 244), "bath": (222, 236, 244),
    "toilet": (222, 236, 244), "mirpeset": (232, 238, 224),
}
WET = {"bath", "ensuite", "toilet"}


class Plan:
    def __init__(self, seed, W=None, ent_w=None, mirror=None, party=()):
        """W, ent_w (dm) and mirror can be forced so a building can line flats up on its
        stairwell; left None they come from the seed."""
        self.force = {"W": W, "ent_w": ent_w, "mirror": mirror}
        self.party = set(party)   ## "x0" / "x1": a side wall shared with the next flat (no windows)
        self.seed = seed
        self.rng = random.Random(seed)
        self.rooms = []      # {"id", "kind", "rect": [x0, y0, x1, y1] dm}
        self.grid = None
        self.open = set()    # frozenset pairs of room ids with no wall between
        self.edges = {}      # ("v"|"h", x, y) -> kind
        self.doors = []
        self.windows = []
        self.items = []
        self.occupied = set()
        self.keep_clear = set()
        self.notes = []

    # ---------------------------------------------------------------- layout
    def room(self, kind, x0, y0, x1, y1):
        r = {"id": len(self.rooms), "kind": kind, "rect": [x0, y0, x1, y1]}
        self.rooms.append(r)
        return r

    def layout(self):
        g = self.rng
        W = g.randint(105, 130)
        if self.force["W"]:
            W = self.force["W"]
        back = g.randint(36, 42)
        hall_d = g.randint(11, 13)
        front = g.randint(40, 48)
        D = back + hall_d + front
        bal_d = g.randint(18, 24)
        self.W, self.D, self.H = W, D, D + bal_d

        # back strip, from the stairwell side: entrance, then the small rooms shuffled
        ent_w = g.randint(17, 21)
        if self.force["ent_w"]:
            ent_w = self.force["ent_w"]
        smalls = [("toilet", g.randint(11, 13)), ("bath", g.randint(19, 22)),
                  ("mamad", g.randint(27, 31))]
        g.shuffle(smalls)
        x = ent_w
        back_rooms = [("entrance", 0, ent_w)]
        for kind, w in smalls:
            back_rooms.append((kind, x, x + w))
            x += w
        rest = W - x
        if rest < 28:
            # no space for a decent bedroom: drop the guest toilet (plenty of flats have none)
            back_rooms = [("entrance", 0, ent_w)]
            x = ent_w
            for kind, w in smalls:
                if kind == "toilet":
                    continue
                back_rooms.append((kind, x, x + w))
                x += w
            rest = W - x
        if rest >= 58:
            half = rest // 2
            back_rooms.append(("bedroom", x, x + half))
            back_rooms.append(("bedroom", x + half, W))
        else:
            back_rooms.append(("bedroom", x, W))
            if rest < 26:
                self.notes.append("back bedroom only %.1f m wide" % (rest / 10))

        # front strip: kitchen by the entrance side, salon, parents' room
        kit_w = g.randint(26, 32)
        sal_w = g.randint(45, 55)
        par_w = W - kit_w - sal_w
        if par_w > 45:
            sal_w += par_w - 40
            par_w = 40
        if par_w < 36:
            # the parents' room needs a double bed beside its shower room: take it from
            # the salon (down to 4 m) and then the kitchen (down to 2.4 m)
            need = 36 - par_w
            take = min(need, max(0, sal_w - 40))
            sal_w -= take
            need -= take
            take = min(need, max(0, kit_w - 24))
            kit_w -= take
            par_w = W - kit_w - sal_w
        fy = back + hall_d
        front_rooms = [("kitchen", 0, kit_w), ("salon", kit_w, kit_w + sal_w),
                       ("parents", kit_w + sal_w, W)]

        mirror = g.random() < 0.5
        if self.force["mirror"] is not None:
            mirror = self.force["mirror"]
        self.mirror = mirror

        def mx(a, b):
            return (W - b, W - a) if mirror else (a, b)

        ids = {}
        for kind, a, b in back_rooms:
            a, b = mx(a, b)
            r = self.room(kind, a, 0, b, back)
            ids.setdefault(kind, []).append(r["id"])
        hall = self.room("hall", 0, back, W, fy)
        for kind, a, b in front_rooms:
            a, b = mx(a, b)
            r = self.room(kind, a, fy, b, D)
            ids.setdefault(kind, []).append(r["id"])
        # the parents' shower room, carved out of the hall-side corner away from the salon
        par = self.rooms[ids["parents"][0]]
        ew, ed = g.randint(16, 19), g.randint(19, 23)
        px0, _, px1, _ = par["rect"]
        if mirror:
            ens = self.room("ensuite", px0, fy, px0 + ew, fy + ed)
        else:
            ens = self.room("ensuite", px1 - ew, fy, px1, fy + ed)
        # balcony in front of the salon (and the kitchen too, sometimes)
        sal = self.rooms[ids["salon"][0]]
        bx0, _, bx1, _ = sal["rect"]
        if g.random() < 0.35:
            kit = self.rooms[ids["kitchen"][0]]
            bx0, bx1 = min(bx0, kit["rect"][0]), max(bx1, kit["rect"][2])
        bal = self.room("mirpeset", bx0, D, bx1, D + bal_d)

        self.ids = ids
        self.hall, self.sal, self.par, self.ens, self.bal = hall, sal, par, ens, bal
        kit = self.rooms[ids["kitchen"][0]]
        ent = self.rooms[ids["entrance"][0]]
        self.ent, self.kit = ent, kit
        for a, b in [(hall, sal), (hall, kit), (kit, sal), (hall, ent)]:
            self.open.add(frozenset((a["id"], b["id"])))

        # paint the grid: later rooms win (the ensuite over the parents' room)
        self.grid = [[-1] * W for _ in range(self.H)]
        for r in self.rooms:
            x0, y0, x1, y1 = r["rect"]
            for yy in range(y0, y1):
                row = self.grid[yy]
                for xx in range(x0, x1):
                    row[xx] = r["id"]

    def at(self, x, y):
        if 0 <= x < self.W and 0 <= y < self.H:
            return self.grid[y][x]
        return -1

    def kind_of(self, rid):
        return self.rooms[rid]["kind"] if rid >= 0 else "out"

    # ----------------------------------------------------------------- walls
    def walls(self):
        bal = self.bal["id"]
        for y in range(self.H + 1):
            for x in range(self.W + 1):
                for o in ("v", "h"):
                    if o == "v" and y == self.H:
                        continue
                    if o == "h" and x == self.W:
                        continue
                    a, b = self.sides(o, x, y)
                    if a == b:
                        continue
                    if frozenset((a, b)) in self.open:
                        continue
                    if -1 in (a, b) and bal in (a, b):
                        k = "rail"
                    elif -1 in (a, b) or bal in (a, b):
                        k = "ext"
                    elif "mamad" in (self.kind_of(a), self.kind_of(b)):
                        k = "mamad"
                    else:
                        k = "wall"
                    self.edges[(o, x, y)] = k

    def sides(self, o, x, y):
        """The two cells an edge parts: v edge at line x between (x-1,y) and (x,y)."""
        if o == "v":
            return self.at(x - 1, y), self.at(x, y)
        return self.at(x, y - 1), self.at(x, y)

    def runs_between(self, a, b):
        """Straight runs of edges between rooms a and b: [(o, line, s, e)]."""
        want = frozenset((a, b))
        by_line = {}
        for (o, x, y), k in self.edges.items():
            if frozenset(self.sides(o, x, y)) == want:
                line, pos = (x, y) if o == "v" else (y, x)
                by_line.setdefault((o, line), []).append(pos)
        runs = []
        for (o, line), ps in by_line.items():
            ps.sort()
            s = prev = ps[0]
            for p in ps[1:] + [None]:
                if p is None or p != prev + 1:
                    runs.append((o, line, s, prev + 1))
                    if p is not None:
                        s = p
                if p is not None:
                    prev = p
        return runs

    def edge_key(self, o, line, pos):
        return (o, line, pos) if o == "v" else (o, pos, line)

    def door(self, a, b, width, style="swing", into=None):
        """Cut a door between rooms a and b in their longest shared run, near a corner."""
        runs = self.runs_between(a["id"], b["id"])
        if not runs:
            self.notes.append("no wall between %s and %s for a door" % (a["kind"], b["kind"]))
            return
        o, line, s, e = max(runs, key=lambda r: r[3] - r[2])
        L = e - s
        margin = 2
        if L < width + 2 * margin:
            width = min(width, L - 2)
            if width < 6:
                self.notes.append("%s-%s wall too short for a door" % (a["kind"], b["kind"]))
                return
            p0 = s + (L - width) // 2
        elif style == "slider":
            p0 = s + (L - width) // 2
        else:
            near_start = self.rng.random() < 0.5
            p0 = s + margin if near_start else e - margin - width
        for p in range(p0, p0 + width):
            self.edges[self.edge_key(o, line, p)] = "door"
        into = into or b
        # which side of the line is the room the door swings into
        probe = (line, p0) if o == "v" else (p0, line)
        side = 1 if self.at(*probe) == into["id"] else -1
        hinge = p0 if (p0 - s) <= (e - (p0 + width)) else p0 + width
        d = {"o": o, "line": line, "a": p0, "b": p0 + width, "style": style,
             "rooms": [a["id"], b["id"]], "into": into["id"], "side": side, "hinge": hinge}
        self.doors.append(d)
        # keep the swing (and a step on the other side) clear of furniture
        depth = 6 if style == "slider" else width
        for p in range(p0 - 1, p0 + width + 1):
            for k in range(-depth, depth):
                cx, cy = (line + k, p) if o == "v" else (p, line + k)
                self.keep_clear.add((cx, cy))

    def cut_doors(self):
        g = self.rng
        hall = self.hall
        for r in self.rooms:
            k = r["kind"]
            if k in ("bedroom", "mamad", "bath", "toilet"):
                w = {"bath": 7, "toilet": 7, "mamad": 8}.get(k, 8)
                self.door(hall, r, w)
            elif k == "parents":
                self.door(hall, r, 8)
        self.door(self.par, self.ens, 7)
        bw = g.randint(22, 30)
        self.door(self.sal, self.bal, bw, style="slider", into=self.bal)
        # the front door, in the entrance's back wall (onto the stairwell)
        ex0, _, ex1, _ = self.ent["rect"]
        w = 9
        p0 = ex0 + (ex1 - ex0 - w) // 2
        for p in range(p0, p0 + w):
            self.edges[("h", p, 0)] = "door"
        self.doors.append({"o": "h", "line": 0, "a": p0, "b": p0 + w, "style": "front",
                           "rooms": [-1, self.ent["id"]], "into": self.ent["id"], "side": 1,
                           "hinge": p0})
        for p in range(p0 - 1, p0 + w + 1):
            for k in range(0, w):
                self.keep_clear.add((p, k))

    def cut_windows(self):
        want = {"salon": 18, "kitchen": 12, "bedroom": 14, "parents": 16, "mamad": 10,
                "bath": 6, "toilet": 5, "ensuite": 6}
        for r in self.rooms:
            w = want.get(r["kind"])
            if not w:
                continue
            runs = [rr for rr in self.runs_between(r["id"], -1)]
            runs = [rr for rr in runs if not (r is self.ent)]
            # no windows in a wall shared with the neighbours
            runs = [rr for rr in runs if not (rr[0] == "v" and (
                (rr[1] == 0 and "x0" in self.party) or (rr[1] == self.W and "x1" in self.party)))]
            # windows look out of the flat, not onto the stairwell (y = 0 behind the entrance
            # is the stairwell, but the back rooms face a light well/the yard: allowed)
            runs = [rr for rr in runs
                    if all(self.edges.get(self.edge_key(rr[0], rr[1], p)) == "ext"
                           for p in range(rr[2], rr[3]))]
            if not runs:
                continue
            o, line, s, e = max(runs, key=lambda q: q[3] - q[2])
            L = e - s
            w = min(w, L - 6)
            if w < 4:
                continue
            p0 = s + (L - w) // 2
            for p in range(p0, p0 + w):
                self.edges[self.edge_key(o, line, p)] = "window"
            self.windows.append({"o": o, "line": line, "a": p0, "b": p0 + w,
                                 "room": r["id"], "shutter": r["kind"] == "mamad"})

    # ------------------------------------------------------------- furniture
    def cells(self, rid):
        x0, y0, x1, y1 = self.rooms[rid]["rect"]
        return [(x, y) for y in range(y0, y1) for x in range(x0, x1) if self.grid[y][x] == rid]

    def fits(self, rid, x0, y0, w, d, clear=True):
        for y in range(y0, y0 + d):
            for x in range(x0, x0 + w):
                if self.at(x, y) != rid or (x, y) in self.occupied:
                    return False
                if clear and (x, y) in self.keep_clear:
                    return False
        return True

    def backed(self, x0, y0, w, d, face):
        """Is the item's back (opposite to where it faces) against a solid wall?"""
        if face == "S":   # faces +y, back on its top edge
            keys = [("h", x, y0) for x in range(x0, x0 + w)]
        elif face == "N":
            keys = [("h", x, y0 + d) for x in range(x0, x0 + w)]
        elif face == "E":  # faces +x, back on its left edge
            keys = [("v", x0, y) for y in range(y0, y0 + d)]
        else:
            keys = [("v", x0 + w, y) for y in range(y0, y0 + d)]
        return all(self.edges.get(k) in SOLID for k in keys)

    def side_walls(self, x0, y0, w, d, face):
        """How many of the item's two flanks touch a solid wall (for corner-loving things)."""
        if face in ("S", "N"):
            a = [("v", x0, y) for y in range(y0, y0 + d)]
            b = [("v", x0 + w, y) for y in range(y0, y0 + d)]
        else:
            a = [("h", x, y0) for x in range(x0, x0 + w)]
            b = [("h", x, y0 + d) for x in range(x0, x0 + w)]
        return sum(1 for s in (a, b) if all(self.edges.get(k) in SOLID for k in s))

    def place(self, rid, name, w, d, pref="any", front=0, clear=True, score_fn=None, quiet=False):
        """Put an item with its back to a wall. w along the wall, d out from it (dm)."""
        best = None
        rect = self.rooms[rid]["rect"]
        cx = (rect[0] + rect[2]) / 2
        cy = (rect[1] + rect[3]) / 2
        door_pts = [self.door_mid(dd) for dd in self.doors if rid in dd["rooms"]]
        for face in ("S", "N", "E", "W"):
            fw, fd = (w, d) if face in ("S", "N") else (d, w)
            for (x, y) in self.cells(rid):
                if not self.fits(rid, x, y, fw, fd, clear):
                    continue
                if not self.backed(x, y, fw, fd, face):
                    continue
                if front and not self.front_free(rid, x, y, fw, fd, face, front):
                    continue
                s = self.rng.random() * 0.5
                mx_, my_ = x + fw / 2, y + fd / 2
                corners = self.side_walls(x, y, fw, fd, face)
                if pref == "corner":
                    s += 2.0 * corners
                elif pref == "center":
                    along = abs(mx_ - cx) if face in ("S", "N") else abs(my_ - cy)
                    s -= along / 10.0
                    s -= 1.0 * corners
                if door_pts:
                    dist = min(math.hypot(mx_ - px, my_ - py) for px, py in door_pts)
                    s += dist / 30.0 if pref != "near_door" else -dist / 10.0
                if score_fn:
                    s += score_fn(x, y, fw, fd, face)
                if best is None or s > best[0]:
                    best = (s, x, y, fw, fd, face)
        if best is None:
            if quiet:
                return None
            self.notes.append("no room for %s in %s" % (name, self.rooms[rid]["kind"]))
            return None
        _, x, y, fw, fd, face = best
        return self.put(rid, name, x, y, fw, fd, face)

    def put(self, rid, name, x, y, fw, fd, face):
        for yy in range(y, y + fd):
            for xx in range(x, x + fw):
                self.occupied.add((xx, yy))
        it = {"name": name, "room": rid, "rect": [x, y, x + fw, y + fd], "face": face}
        self.items.append(it)
        return it

    def front_free(self, rid, x, y, fw, fd, face, n):
        if face == "S":
            zone = [(xx, yy) for yy in range(y + fd, y + fd + n) for xx in range(x, x + fw)]
        elif face == "N":
            zone = [(xx, yy) for yy in range(y - n, y) for xx in range(x, x + fw)]
        elif face == "E":
            zone = [(xx, yy) for yy in range(y, y + fd) for xx in range(x + fw, x + fw + n)]
        else:
            zone = [(xx, yy) for yy in range(y, y + fd) for xx in range(x - n, x)]
        return all(self.at(*c) == rid and c not in self.occupied for c in zone)

    def door_mid(self, d):
        m = (d["a"] + d["b"]) / 2
        return (d["line"], m) if d["o"] == "v" else (m, d["line"])

    def free_spot(self, region, w, d, margin, near=None):
        """A free-standing item (a table): fully inside `region` cells with a margin."""
        best = None
        cand = sorted(region)
        for (x, y) in cand:
            ok = True
            for yy in range(y - margin, y + d + margin):
                for xx in range(x - margin, x + w + margin):
                    c = (xx, yy)
                    if c not in region or c in self.occupied:
                        ok = False
                        break
                    inner = x <= xx < x + w and y <= yy < y + d
                    if inner and c in self.keep_clear:
                        ok = False
                        break
                if not ok:
                    break
            if not ok:
                continue
            s = self.rng.random() * 0.3
            if near:
                s -= math.hypot(x + w / 2 - near[0], y + d / 2 - near[1]) / 10.0
            if best is None or s > best[0]:
                best = (s, x, y)
        return best

    def furnish(self):
        g = self.rng
        for r in list(self.rooms):
            rid, k = r["id"], r["kind"]
            if k == "parents":
                self.place(rid, "bed_double", 16, 20, pref="center", front=6)
                for L in (24, 20, 16, 12):
                    if self.place(rid, "wardrobe", L, 6, pref="corner", front=6, quiet=L > 12):
                        break
                self.place(rid, "nightstand", 4, 4, pref="any")
            elif k == "bedroom":
                self.place(rid, "bed_single", 9, 19, pref="corner", front=5)
                self.place(rid, "wardrobe", 14, 6, pref="corner", front=6)
                self.place(rid, "desk", 12, 6, pref="any", front=6)
            elif k == "mamad":
                # the safe room doubles as a study / guest room
                self.place(rid, "sofa_bed", 18, 8, pref="corner", front=5)
                self.place(rid, "desk", 12, 6, pref="any", front=6)
                self.place(rid, "shelves", 10, 4, pref="corner")
            elif k in ("bath", "ensuite"):
                rect = r["rect"]
                small = min(rect[2] - rect[0], rect[3] - rect[1])
                if k == "bath" and small >= 17 and g.random() < 0.6:
                    self.place(rid, "bathtub", 17, 7, pref="corner")
                else:
                    self.place(rid, "shower", 9, 9, pref="corner")
                self.place(rid, "toilet", 4, 7, pref="any")
                self.place(rid, "sink", 6, 5, pref="near_door")
                if k == "bath":
                    self.place(rid, "washer", 6, 6, pref="corner")
            elif k == "toilet":
                self.place(rid, "toilet", 4, 7, pref="any", clear=False)
                self.place(rid, "sink_small", 4, 3, pref="any", clear=False)
            elif k == "entrance":
                self.place(rid, "shoe_cabinet", 10, 4, pref="any")
            elif k == "mirpeset":
                self.place(rid, "plant", 4, 4, pref="corner")
                self.place(rid, "plant", 4, 4, pref="corner")
                self.place(rid, "lounger", 7, 18, pref="any")
        self.furnish_kitchen()
        self.furnish_salon()
        # balcony table, free standing
        reg = set(self.cells(self.bal["id"]))
        spot = self.free_spot(reg, 7, 7, 4)
        if spot:
            _, x, y = spot
            self.put(self.bal["id"], "table_round", x, y, 7, 7, "S")
            self.chairs(self.bal["id"], x, y, 7, 7, 2)

    def furnish_kitchen(self):
        kid = self.kit["id"]
        # the longest counter that fits along a wall, then an L on another wall, the fridge
        for L in range(34, 13, -2):
            it = self.place(kid, "counter", L, 6, pref="corner", front=8, quiet=L > 14)
            if it:
                it["parts"] = ["sink", "stove"]
                break
        for L in range(22, 9, -2):
            if self.place(kid, "counter", L, 6, pref="corner", front=8, quiet=True):
                break
        self.place(kid, "fridge", 7, 7, pref="corner", front=7)

    def furnish_salon(self):
        """TV on the salon's best solid wall, the sofa facing it 2.4-3.2 m away (free
        standing if it has to be: open-plan salons usually float the sofa), a coffee table
        between. Falls back to a sofa against a wall when nothing faces the TV."""
        sid = self.sal["id"]
        tv = self.place(sid, "tv_unit", 16, 4, pref="center", front=20)
        sofa = None
        if tv:
            x0, y0, x1, y1 = tv["rect"]
            f = tv["face"]
            mx_, my_ = (x0 + x1) // 2, (y0 + y1) // 2
            sw, sd = 22, 9
            for gap in range(30, 19, -2):
                if f == "S":
                    sx, sy, fw, fd = mx_ - sw // 2, y1 + gap, sw, sd
                elif f == "N":
                    sx, sy, fw, fd = mx_ - sw // 2, y0 - gap - sd, sw, sd
                elif f == "E":
                    sx, sy, fw, fd = x1 + gap, my_ - sw // 2, sd, sw
                else:
                    sx, sy, fw, fd = x0 - gap - sd, my_ - sw // 2, sd, sw
                opp = {"S": "N", "N": "S", "E": "W", "W": "E"}[f]
                if self.fits(sid, sx, sy, fw, fd):
                    sofa = self.put(sid, "sofa", sx, sy, fw, fd, opp)
                    break
        if not sofa:
            sofa = self.place(sid, "sofa", 22, 9, pref="center", front=12)
        if sofa:
            x0, y0, x1, y1 = sofa["rect"]
            f = sofa["face"]
            cw, cd = (10, 6) if f in ("S", "N") else (6, 10)
            mx_, my_ = (x0 + x1) // 2, (y0 + y1) // 2
            if f == "S":
                tx, ty = mx_ - cw // 2, y1 + 4
            elif f == "N":
                tx, ty = mx_ - cw // 2, y0 - 4 - cd
            elif f == "E":
                tx, ty = x1 + 4, my_ - cd // 2
            else:
                tx, ty = x0 - 4 - cw, my_ - cd // 2
            if self.fits(sid, tx, ty, cw, cd):
                self.put(sid, "coffee_table", tx, ty, cw, cd, f)
            # keep a walkway behind and in front of the sofa group for the table search
            for yy in range(y0 - 6, y1 + 6):
                for xx in range(x0 - 6, x1 + 6):
                    self.keep_clear.add((xx, yy))
        # the dining table between the kitchen and the salon
        region = set(self.cells(sid)) | set(self.cells(self.kit["id"])) | set(self.cells(self.hall["id"]))
        kr = self.kit["rect"]
        near = ((kr[0] + kr[2]) / 2, (kr[1] + kr[3]) / 2)
        sr = self.sal["rect"]
        near = ((near[0] + (sr[0] + sr[2]) / 2) / 2, near[1])
        spot = self.free_spot(region, 16, 9, 6, near=near)
        if not spot:
            spot = self.free_spot(region, 12, 8, 6, near=near)
            w, d = 12, 8
        else:
            w, d = 16, 9
        if spot:
            _, x, y = spot
            rid = self.grid[y][x]
            self.put(rid, "dining_table", x, y, w, d, "S")
            self.chairs(rid, x, y, w, d, 6 if w >= 16 else 4)
        else:
            self.notes.append("no room for the dining table")

    def chairs(self, rid, x, y, w, d, n):
        cs = 4
        spots = []
        if n >= 4:
            for fx in (0.25, 0.75) if n >= 6 or w >= 12 else (0.5,):
                spots.append((int(x + w * fx - cs / 2), y - cs - 1, "S"))
                spots.append((int(x + w * fx - cs / 2), y + d + 1, "N"))
        if n == 2 or n >= 6:
            spots.append((x - cs - 1, int(y + d / 2 - cs / 2), "E"))
            spots.append((x + w + 1, int(y + d / 2 - cs / 2), "W"))
        for cx, cy, f in spots[:n]:
            self.put(self.grid[cy][cx] if self.at(cx, cy) >= 0 else rid, "chair", cx, cy, cs, cs, f)

    # ---------------------------------------------------------------- output
    def build(self):
        self.layout()
        self.walls()
        self.cut_doors()
        self.cut_windows()
        self.furnish()
        return self

    def label_spot(self, rid, w, h):
        """Centre (dm) of a w x h box inside room rid, off the furniture, nearest the
        room's middle; the middle itself if nothing is free."""
        cells = self.cells(rid)
        if not cells:
            return None
        sx = sum(c[0] for c in cells) / len(cells)
        sy = sum(c[1] for c in cells) / len(cells)
        best = None
        cs = set(cells)
        for (x, y) in cells:
            d = math.hypot(x + w / 2 - sx, y + h / 2 - sy)
            if best is not None and d >= best[0]:
                continue
            ok = all((xx, yy) in cs and (xx, yy) not in self.occupied
                     for yy in range(y, y + h) for xx in range(x, x + w))
            if ok:
                best = (d, x + w / 2, y + h / 2)
        return (best[1], best[2]) if best else (sx, sy)

    def area(self, rid):
        return len(self.cells(rid)) * DM * DM

    def to_json(self):
        m = lambda v: round(v * DM, 2)
        rooms = []
        for r in self.rooms:
            rooms.append({"id": r["id"], "kind": r["kind"], "name": NAMES[r["kind"]],
                          "rect": [m(v) for v in r["rect"]], "area": round(self.area(r["id"]), 1)})
        walls = []
        for (o, x, y), k in sorted(self.edges.items()):
            walls.append([o, m(x), m(y), k])
        return {
            "seed": self.seed, "size": [m(self.W), m(self.D)], "balcony_depth": m(self.H - self.D),
            "rooms": rooms,
            "doors": [{**d, "line": m(d["line"]), "a": m(d["a"]), "b": m(d["b"]),
                       "hinge": m(d["hinge"])} for d in self.doors],
            "windows": [{**w, "line": m(w["line"]), "a": m(w["a"]), "b": m(w["b"])}
                        for w in self.windows],
            "items": [{**i, "rect": [m(v) for v in i["rect"]]} for i in self.items],
            "edges_10cm": walls,
            "notes": self.notes,
        }

    def summary(self):
        rooms = [r for r in self.rooms if r["kind"] in ("bedroom", "parents", "mamad", "salon")]
        inner = sum(self.area(r["id"]) for r in self.rooms if r["kind"] != "mirpeset")
        return "%d rooms, %d m2 + %d m2 mirpeset" % (len(rooms), round(inner),
                                                    round(self.area(self.bal["id"])))


# ------------------------------------------------------------------- drawing
INK = (40, 40, 48)
WALL = (52, 52, 60)
MAMAD = (95, 70, 70)
FURN = (255, 255, 255)
FURN_LINE = (110, 110, 120)


def render(p, scale=50, title=True, labels=True, stair_hint=True, pad=40, bg=(250, 250, 247)):
    top = 64 if title else pad
    Wpx = int(p.W * DM * scale) + 2 * pad
    Hpx = int(p.H * DM * scale) + top + pad
    img = Image.new("RGBA", (Wpx, Hpx), bg + (255,) if bg else (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    f_room = ImageFont.truetype(FONT_B, 13)
    f_small = ImageFont.truetype(FONT, 11)
    f_title = ImageFont.truetype(FONT_B, 16)

    def P(x, y):  # dm -> px
        return (pad + x * DM * scale, top + y * DM * scale)

    def R(x0, y0, x1, y1, **kw):
        a, b = P(x0, y0), P(x1, y1)
        dr.rectangle([a, b], **kw)

    # floors
    for r in p.rooms:
        col = FLOOR[r["kind"]]
        for (x, y) in p.cells(r["id"]):
            pass
        x0, y0, x1, y1 = r["rect"]
        R(x0, y0, x1, y1, fill=col)
    # the ensuite was painted over the parents' room: repaint it last
    R(*p.ens["rect"], fill=FLOOR["ensuite"])
    # wet room tiles
    for r in p.rooms:
        if r["kind"] in WET:
            x0, y0, x1, y1 = r["rect"]
            for gx in range(x0, x1, 3):
                dr.line([P(gx, y0), P(gx, y1)], fill=(205, 222, 232))
            for gy in range(y0, y1, 3):
                dr.line([P(x0, gy), P(x1, gy)], fill=(205, 222, 232))
    # stairwell hint behind the front door
    if stair_hint:
        fd = [d for d in p.doors if d["style"] == "front"][0]
        a, b = P(fd["a"] - 6, -8), P(fd["b"] + 6, 0)
        dr.rectangle([a, b], fill=(232, 232, 232))
        dr.text((a[0] + 4, a[1] + 1), "stairwell", font=f_small, fill=(130, 130, 130))

    # furniture
    for it in p.items:
        draw_item(dr, P, it, scale)

    # walls: each 10 cm edge as a bar of its thickness, then the joints
    joint = {}
    for (o, x, y), k in p.edges.items():
        if k == "door":
            continue
        t = THICK[k] / 2
        col = MAMAD if k == "mamad" else WALL
        if k == "rail":
            col = (90, 110, 90)
        if o == "v":
            box = (x - t, y, x + t, y + 1)
            ends = [(x, y), (x, y + 1)]
        else:
            box = (x, y - t, x + 1, y + t)
            ends = [(x, y), (x + 1, y)]
        if k == "window":
            R(*box, fill=(255, 255, 255))
            # two glass lines along the middle
            if o == "v":
                dr.line([P(x - t / 3, y), P(x - t / 3, y + 1)], fill=(80, 140, 200), width=1)
                dr.line([P(x + t / 3, y), P(x + t / 3, y + 1)], fill=(80, 140, 200), width=1)
            else:
                dr.line([P(x, y - t / 3), P(x + 1, y - t / 3)], fill=(80, 140, 200), width=1)
                dr.line([P(x, y + t / 3), P(x + 1, y + t / 3)], fill=(80, 140, 200), width=1)
        else:
            R(*box, fill=col)
        if k not in ("window",):
            for e in ends:
                if THICK[k] > joint.get(e, (0, None))[0]:
                    joint[e] = (THICK[k], col)
    for (x, y), (t, col) in joint.items():
        R(x - t / 2, y - t / 2, x + t / 2, y + t / 2, fill=col)
    # window frames over the joints
    for w in p.windows:
        t = THICK["window"] / 2
        if w["o"] == "v":
            box = (w["line"] - t, w["a"], w["line"] + t, w["b"])
        else:
            box = (w["a"], w["line"] - t, w["b"], w["line"] + t)
        R(*box, outline=(80, 140, 200))
        if w["shutter"]:  # the mamad's steel shutter, a dark bar on the outside
            if w["o"] == "v":
                pass
            else:
                R(w["a"], w["line"] - t - 0.8, w["b"], w["line"] - t, fill=MAMAD)

    # doors
    for d in p.doors:
        draw_door(dr, P, p, d, scale)

    if labels:
        draw_labels(dr, P, p, f_room, scale)

    if title:
        dr.text((pad, 12), "seed %d  ·  %s" % (p.seed, p.summary()), font=f_title, fill=INK)
        # 1 m scale bar
        x, y = Wpx - pad - scale, 20
        dr.line([(x, y), (x + scale, y)], fill=INK, width=2)
        dr.text((x + scale / 2 - 8, y + 3), "1 m", font=f_small, fill=INK)
    return img


def label_text(p, r):
    return "%s\n%.1f m²" % (NAMES[r["kind"]], p.area(r["id"]))


def draw_labels(dr, P, p, font, scale, xf=None):
    """Room names and areas, each in a free spot of its room. xf maps a plan point (dm)
    to another plan point first (a building turns some flats round)."""
    for r in p.rooms:
        if r["kind"] == "hall":
            continue
        txt = label_text(p, r)
        bb = dr.multiline_textbbox((0, 0), txt, font=font, align="center")
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        wd = int(math.ceil((tw + 8) / (DM * scale))) + 1
        hd = int(math.ceil((th + 7) / (DM * scale))) + 1
        cxd, cyd = p.label_spot(r["id"], wd, hd)
        if xf:
            cxd, cyd = xf(cxd, cyd)
        cx, cy = P(cxd, cyd)
        dr.rounded_rectangle([cx - tw / 2 - 4, cy - th / 2 - 3, cx + tw / 2 + 4, cy + th / 2 + 4],
                             radius=4, fill=(255, 255, 255))
        dr.multiline_text((cx - tw / 2, cy - th / 2), txt, font=font, fill=INK, align="center")


def draw_door(dr, P, p, d, scale):
    o, line, a, b = d["o"], d["line"], d["a"], d["b"]
    w = b - a
    col = (60, 60, 70)
    if d["style"] == "slider":
        # two glass panes, offset
        if o == "h":
            m = (a + b) / 2
            dr.line([P(a, line - 0.5), P(m + 2, line - 0.5)], fill=(80, 140, 200), width=3)
            dr.line([P(m - 2, line + 0.5), P(b, line + 0.5)], fill=(80, 140, 200), width=3)
        else:
            m = (a + b) / 2
            dr.line([P(line - 0.5, a), P(line - 0.5, m + 2)], fill=(80, 140, 200), width=3)
            dr.line([P(line + 0.5, m - 2), P(line + 0.5, b)], fill=(80, 140, 200), width=3)
        return
    s = d["side"]
    hinge = d["hinge"]
    other = b if hinge == a else a
    steel = d["style"] == "front" or p.kind_of(d["into"]) == "mamad"
    lw = 3 if steel else 2
    leaf_col = MAMAD if p.kind_of(d["into"]) == "mamad" else col
    # leaf: from the hinge, perpendicular into the room; arc from the leaf tip to the jamb
    if o == "h":
        hx, hy = hinge, line
        tip = (hx, hy + s * w)
        dr.line([P(hx, hy), P(*tip)], fill=leaf_col, width=lw)
        c = P(hx, hy)
        r = w * DM * scale
        start = math.degrees(math.atan2(s * 1, 0))
        endv = math.degrees(math.atan2(0, other - hinge))
        a0, a1 = sorted([start, endv])
        if a1 - a0 > 180:
            a0, a1 = a1, a0 + 360
        dr.arc([c[0] - r, c[1] - r, c[0] + r, c[1] + r], a0, a1, fill=(150, 150, 160))
    else:
        hx, hy = line, hinge
        tip = (hx + s * w, hy)
        dr.line([P(hx, hy), P(*tip)], fill=leaf_col, width=lw)
        c = P(hx, hy)
        r = w * DM * scale
        start = math.degrees(math.atan2(0, s * 1))
        endv = math.degrees(math.atan2(other - hinge, 0))
        a0, a1 = sorted([start, endv])
        if a1 - a0 > 180:
            a0, a1 = a1, a0 + 360
        dr.arc([c[0] - r, c[1] - r, c[0] + r, c[1] + r], a0, a1, fill=(150, 150, 160))


def draw_item(dr, P, it, scale):
    x0, y0, x1, y1 = it["rect"]
    n, f = it["name"], it["face"]
    a, b = P(x0, y0), P(x1, y1)
    box = [a, b]
    L = FURN_LINE

    def back_strip(depth):
        # a strip along the item's back (the side against the wall)
        if f == "S":
            return [P(x0, y0), P(x1, y0 + depth)]
        if f == "N":
            return [P(x0, y1 - depth), P(x1, y1)]
        if f == "E":
            return [P(x0, y0), P(x0 + depth, y1)]
        return [P(x1 - depth, y0), P(x1, y1)]

    if n in ("bed_double", "bed_single"):
        dr.rectangle(box, fill=FURN, outline=L, width=2)
        # duvet fold and pillows at the head (the back)
        hs = back_strip(4)
        dr.rectangle(hs, fill=(244, 244, 250), outline=L)
        pillows = 2 if n == "bed_double" else 1
        if f in ("S", "N"):
            pw = (x1 - x0) / pillows
            yy0, yy1 = (y0 + 0.8, y0 + 3.4) if f == "S" else (y1 - 3.4, y1 - 0.8)
            for i in range(pillows):
                dr.rounded_rectangle([P(x0 + i * pw + 1, yy0), P(x0 + (i + 1) * pw - 1, yy1)],
                                     radius=3, fill=FURN, outline=L)
        else:
            pw = (y1 - y0) / pillows
            xx0, xx1 = (x0 + 0.8, x0 + 3.4) if f == "E" else (x1 - 3.4, x1 - 0.8)
            for i in range(pillows):
                dr.rounded_rectangle([P(xx0, y0 + i * pw + 1), P(xx1, y0 + (i + 1) * pw - 1)],
                                     radius=3, fill=FURN, outline=L)
    elif n in ("sofa", "sofa_bed"):
        dr.rounded_rectangle(box, radius=4, fill=(236, 226, 214) if n == "sofa" else FURN,
                             outline=L, width=2)
        dr.rectangle(back_strip(2.5), fill=(214, 200, 186), outline=L)
    elif n == "lounger":
        dr.rounded_rectangle(box, radius=3, fill=FURN, outline=L)
    elif n in ("wardrobe", "shelves", "shoe_cabinet"):
        dr.rectangle(box, fill=(230, 222, 210), outline=L, width=2)
        dr.line([a, b], fill=(200, 190, 178))
        dr.line([(a[0], b[1]), (b[0], a[1])], fill=(200, 190, 178))
    elif n == "counter":
        dr.rectangle(box, fill=(225, 225, 225), outline=L, width=2)
        # sink one third along, stove two thirds (on the main run only)
        if not it.get("parts"):
            pass
        elif f in ("S", "N"):
            L_ = x1 - x0
            sx = x0 + L_ * 0.28
            kx = x0 + L_ * 0.7
            dr.rounded_rectangle([P(sx - 2.5, y0 + 1), P(sx + 2.5, y1 - 1)], radius=3,
                                 outline=(90, 130, 170), width=2)
            for dx in (-1.4, 1.4):
                for dy in (-1.4, 1.4):
                    c = P(kx + dx, (y0 + y1) / 2 + dy)
                    rr = 0.9 * DM * scale
                    dr.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=INK)
        else:
            L_ = y1 - y0
            sy = y0 + L_ * 0.28
            ky = y0 + L_ * 0.7
            dr.rounded_rectangle([P(x0 + 1, sy - 2.5), P(x1 - 1, sy + 2.5)], radius=3,
                                 outline=(90, 130, 170), width=2)
            for dx in (-1.4, 1.4):
                for dy in (-1.4, 1.4):
                    c = P((x0 + x1) / 2 + dx, ky + dy)
                    rr = 0.9 * DM * scale
                    dr.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=INK)
    elif n == "fridge":
        dr.rectangle(box, fill=(245, 245, 250), outline=INK, width=2)
        dr.text((a[0] + 3, a[1] + 3), "F", fill=INK)
    elif n in ("dining_table", "coffee_table", "desk", "nightstand"):
        dr.rectangle(box, fill=(222, 204, 180) if n != "desk" else (230, 220, 205),
                     outline=L, width=2)
    elif n == "table_round":
        dr.ellipse(box, fill=(222, 204, 180), outline=L, width=2)
    elif n == "chair":
        dr.rounded_rectangle(box, radius=3, fill=FURN, outline=L)
        dr.rectangle(back_strip(1), fill=L)
    elif n == "tv_unit":
        dr.rectangle(box, fill=(215, 210, 205), outline=L)
        dr.rectangle(back_strip(1), fill=INK)
    elif n == "bathtub":
        dr.rounded_rectangle(box, radius=4, fill=FURN, outline=L, width=2)
        dr.rounded_rectangle([P(x0 + 1, y0 + 1), P(x1 - 1, y1 - 1)], radius=6, outline=(90, 130, 170))
    elif n == "shower":
        dr.rectangle(box, fill=(236, 244, 250), outline=L, width=2)
        dr.line([a, b], fill=L)
        dr.line([(a[0], b[1]), (b[0], a[1])], fill=L)
    elif n == "toilet":
        dr.rectangle(back_strip(2), fill=FURN, outline=L)
        dr.ellipse(box, outline=L, width=2)
    elif n in ("sink", "sink_small"):
        dr.rectangle(box, fill=FURN, outline=L)
        dr.ellipse([P(x0 + 0.8, y0 + 0.8), P(x1 - 0.8, y1 - 0.8)], outline=(90, 130, 170))
    elif n == "washer":
        dr.rectangle(box, fill=FURN, outline=L, width=2)
        c = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        rr = (b[0] - a[0]) * 0.32
        dr.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], outline=L)
    elif n == "plant":
        dr.ellipse(box, fill=(150, 190, 130), outline=(90, 130, 80))
    else:
        dr.rectangle(box, fill=FURN, outline=L)


def parse_range(s):
    out = []
    for part in s.split(","):
        if "-" in part:
            a, b = part.split("-")
            out += list(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--sheet", help="seeds for a contact sheet, e.g. 1-6")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--scale", type=int, default=50, help="pixels per metre")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    if a.sheet:
        seeds = parse_range(a.sheet)
        imgs = []
        for s in seeds:
            p = Plan(s).build()
            imgs.append(render(p, scale=a.scale).convert("RGB"))
            for n in p.notes:
                print("seed %d: %s" % (s, n))
        cols = 3 if len(imgs) > 4 else 2
        cw = max(i.width for i in imgs)
        ch = max(i.height for i in imgs)
        rows = math.ceil(len(imgs) / cols)
        sheet = Image.new("RGB", (cw * cols, ch * rows), (250, 250, 247))
        for i, im in enumerate(imgs):
            sheet.paste(im, ((i % cols) * cw, (i // cols) * ch))
        path = os.path.join(a.out, "sheet_%s.png" % a.sheet.replace(",", "_"))
        sheet.save(path)
        print(path)
        return
    p = Plan(a.seed).build()
    img = render(p, scale=a.scale).convert("RGB")
    path = os.path.join(a.out, "plan_%d.png" % a.seed)
    img.save(path)
    with open(os.path.join(a.out, "plan_%d.json" % a.seed), "w") as fh:
        json.dump(p.to_json(), fh, indent=1)
    for n in p.notes:
        print("note:", n)
    print(path)


if __name__ == "__main__":
    main()
