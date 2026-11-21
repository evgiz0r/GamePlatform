#!/usr/bin/env python3
"""A tiny made-up street for trying looks quickly (tests/look_bench.gd): one street with a
side street crossing it, blocks of three to five storeys from the 1950s to the 2010s along
both (so sand, cream, white and stone plaster, balconies, shutters), a cafe and a grocery on
the corners, a bus stop, a zebra, a few trees. The game adds the rest as anywhere: kerbs and
pavements, parked cars, street trees, people, traffic. Loads in seconds where a real town takes
minutes. Not a level: only a test points the game at it (STREETS_CITY_FILE).

    python3 game/streets/tests/make_look_bench.py   # writes game/streets/cities/look_bench.json
"""
import json
import os

S = 10  # decimetres

nodes = []
def node(x, z):
    nodes.extend([round(x * S), round(z * S)])
    return len(nodes) // 2 - 1

# the main street, west to east, a node at the junction and at each zebra; the side street,
# north to south through the same junction
mw = [node(x, 0.0) for x in (-120.0, -60.0, -9.0, 0.0, 9.0, 60.0, 120.0)]
junction = mw[3]
sn = [node(0.0, z) for z in (-110.0, -50.0)] + [junction] + [node(0.0, z) for z in (50.0, 110.0)]
roads = [
    {"n": mw, "k": "tertiary", "w": 11.0, "l": 2, "name": "רחוב הניסיון", "name_en": "Nisayon Street", "sw": "both"},
    {"n": sn, "k": "residential", "w": 8.0, "l": 2, "name": "רחוב הדוגמה", "name_en": "Dugma Street", "sw": "both"},
]

def rect(x0, z0, x1, z1):
    # counter-clockwise as the format keeps them (x east, z south)
    return [round(v * S) for v in (x0, z0, x1, z0, x1, z1, x0, z1)]

buildings = []
years = [1955, 1962, 1968, 1972, 1985, 1998, 2008, 1965, 1958, 1978, 2015, 1950, 1960, 1970, 1990, 1966]
heights = [13.5, 16.5, 10.5, 13.5, 16.5, 13.5, 19.5, 10.5, 13.5, 16.5, 13.5, 10.5, 13.5, 16.5, 10.5, 13.5]
i = 0
# along the main street, both sides: a garden's depth back from the pavement
for side in (-1.0, 1.0):
    for x0 in (-100.0, -72.0, -44.0, 16.0, 44.0, 72.0):
        z_front = side * 11.5
        z_back = side * 25.0
        b = {"p": rect(x0, min(z_front, z_back), x0 + 18.0, max(z_front, z_back)), "h": heights[i],
             "k": "apartments", "lv": int(heights[i] // 3), "yr": years[i]}
        if i == 4:
            b["col"] = "#f5deb3"   # (one with OSM's own colour: wheat)
        buildings.append(b)
        i += 1
# along the side street, north and south of the junction
for zs in (-1.0, 1.0):
    for xs in (-1.0, 1.0):
        x_front = xs * 10.0
        x_back = xs * 23.0
        z0 = zs * 40.0
        buildings.append({"p": rect(min(x_front, x_back), min(z0, z0 + zs * 16.0), max(x_front, x_back), max(z0, z0 + zs * 16.0)),
                          "h": heights[i], "k": "apartments", "lv": int(heights[i] // 3), "yr": years[i]})
        i += 1

trees = []
for x in (-76.0, -48.0, -20.0, 40.0, 68.0, 96.0):   # (in the gaps between the blocks: none in front of a facade)
    for side in (-1.0, 1.0):
        trees.extend([round(x * S), round(side * 6.6 * S)])

# and along the side street, in its gaps; the trees given as a map of every tree (as a town's
# own survey from the air), so the game makes up no street trees of its own -- they stood in
# front of the very facades the bench looks at
for z in (-30.0, -64.0, 30.0, 64.0):
    for side in (-1.0, 1.0):
        trees.extend([round(side * 5.6 * S), round(z * S)])
for x, z in ((-120.0, -110.0), (120.0, -110.0), (-120.0, 110.0), (120.0, 110.0), (-60.0, -60.0), (60.0, 60.0), (-60.0, 60.0), (60.0, -60.0)):
    trees.extend([round(x * S), round(z * S)])
tree_info = []
for _t in range(len(trees) // 2):
    tree_info.extend([0, 25])   # (a ficus, its crown 2.5 m)

pois = [
    [round(-35.0 * S), round(-12.0 * S), "cafe", "קפה הפינה", "Cafe HaPina"],
    [round(25.0 * S), round(12.0 * S), "convenience", "מכולת", "Makolet"],
]
stops = [[round(52.0 * S), round(8.6 * S), "הניסיון/הדוגמה"]]

city = {
    "version": 1, "name": "Look bench", "source": "made up (tests/make_look_bench.py)", "made_up": 1,
    "fetched": "", "origin": [0.0, 0.0], "scale": S, "bounds": [-140.0, -130.0, 140.0, 130.0],
    "boundary": [], "nodes": nodes, "roads": roads, "buildings": buildings, "areas": [],
    "trees": trees, "tree_info": tree_info, "tree_forms": ["ficus"], "tree_surveys": [{"id": "bench", "all": 1, "from": 0, "to": len(trees) // 2}],
    "signals": [], "crossings": [mw[2], mw[4]], "signs": [], "barriers": [],
    "pois": pois, "stops": stops, "addrs": [],
}
out = os.path.join(os.path.dirname(__file__), "..", "cities", "look_bench.json")
with open(out, "w") as f:
    json.dump(city, f, ensure_ascii=False, separators=(",", ":"))
print("wrote", os.path.normpath(out), len(buildings), "buildings")
