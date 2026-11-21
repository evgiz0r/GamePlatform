#!/usr/bin/env python3
"""The share of each body shape and paint on Israel's roads, from the vehicle register's
sample (cities/data/vehicle_mix.json, see vehicle_mix.py): what streets.gd's CAR_MIX and
_car_paints are tuned to. Each make's top models are put into one of the game's shapes by
name (MODELS below; the rest of a make, the models the sample does not list, go by the
shape its listed ones have most); paints are grouped by colour name.

    python3 game/streets/data_tools/car_mix.py        prints both, and a 20-car list each
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
MIX = os.path.join(HERE, "..", "cities", "data", "vehicle_mix.json")

# a word of the model's name -> the game's shape (the first that matches)
MODELS = [
    # vans and pick-ups (the game's "van": a work van)
    (r"PROACE|TRANSPORTER|CARAVELLE|T5|T6|SPRINTER|H1|BERLINGO|DOKKER|KANGOO|PARTNER|DUCATO|TRANSIT|VITO|"
     r"HILUX|PICK|D-MAX|L ?-?200|BT ?-?50|B-2500|NAVARA|RANGER|AMAROK", "van"),
    # people carriers
    (r"VERSO|ORLANDO|C4 PICASSO|SPACETOURER|LODGY|GRANDIS|MATRIX|TOURAN|SHARAN|ZAFIRA|CARENS|SCENIC|5008", "mpv"),
    # SUVs and crossovers
    (r"KONA|VENUE|STONIC|NIRO|SELTOS|SPORTAGE|KODIAQ|KAMIQ|KAROQ|CX-|RAV ?4|LAND CRUISER|CROSS|C-HR|OUTLANDER|"
     r"ASX|PAJERO|ARONA|TUCSON|VITARA|SX4|TIGGO|XV|FORESTER|CROSSTREK|QASHQAI|JUKE|ATTO|SEAL U|SEALION|TIGUAN|"
     r"TRAX|TRAIL|JIMNY|JAECOO|HR-V|CR-V|EHS|ZS|3008|2008|GLA|X1|X2|MODEL Y|DUSTER|NX|UX|BAYON|EV|TERRITORY|"
     r"CACTUS|C4X|XCEED|T-ROC|T-CROSS|KAMIQ|FX|S9|ATECA|LBX", "suv"),
    # estates
    (r"\bTS\b|TOURER|\bST\b|COMBI|ESTATE|WAGON", "wagon"),
    # city cars
    (r"PICANTO|I10|SPARK|SPACE STAR|ATTRAGE|ALTO|MICRA|AYGO|UP|SPLASH|IGNIS|MG3|DOLPHIN|ATTO 2", "mini"),
    # hatchbacks
    (r"I20|I25|I30|RIO|CEED|FABIA|MAZDA ?2|YARIS|IBIZA|SWIFT|JAZZ|NOTE|AURIS|CLIO|208|308|GOLF|FIESTA|FOCUS|"
     r"118I|A180|SANDERO|BALENO|MG4|RUNX|HB|5D|LEON|CUPRA|IONIQ|CT200H|IMPREZA", "hatch"),
    # the rest: saloons
    (r".", "sedan"),
]

PAINTS = [("שנהב|לבן", "white"), ("כסף|כסוף", "silver"), ("שחור", "black"), ("אפור|פלדה", "grey"),
          ("כחול|תכלת", "blue"), ("אדום|בורדו", "red"), ("בז|ברונזה|זהב|שמפניה", "beige"), ("ירוק", "green")]


def shape(model):
    for pat, s in MODELS:
        if re.search(pat, model.upper()):
            return s
    return "sedan"


def main():
    with open(MIX, encoding="utf-8") as f:
        mix = json.load(f)
    shapes = {}
    for make, share, models in mix["make"]:
        listed = sum(m[1] for m in models) or 1.0
        by = {}
        for m, s in models:
            by[shape(m)] = by.get(shape(m), 0.0) + s
        # the make's unlisted models: as its listed ones go
        for s, v in by.items():
            shapes[s] = shapes.get(s, 0.0) + share * v / listed
    tot = sum(shapes.values())
    print("shapes:", {k: round(v / tot, 3) for k, v in sorted(shapes.items(), key=lambda kv: -kv[1])})
    paints = {}
    for name, share in mix["colour"]:
        g = next((p for w, p in PAINTS if re.search(w, name)), "other")
        paints[g] = paints.get(g, 0.0) + share
    tot_p = sum(paints.values())
    print("paints:", {k: round(v / tot_p, 3) for k, v in sorted(paints.items(), key=lambda kv: -kv[1])})
    for label, d, t in (("CAR_MIX", shapes, tot), ("paints", paints, tot_p)):
        n = 20
        want = {k: v / t * n for k, v in d.items()}
        got = {k: int(v) for k, v in want.items()}
        while sum(got.values()) < n:
            k = max(want, key=lambda k: want[k] - got[k])
            got[k] += 1
        print(label, "in 20:", dict(sorted(got.items(), key=lambda kv: -kv[1])))


if __name__ == "__main__":
    main()
