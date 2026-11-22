# Adding a city: the process

How a new city goes into streets, step by step. Each city should leave the next one
cheaper. Keep this file current: when a city teaches something, its lesson goes here (or in
the `real-places` skill, if it holds for every game), not only in that city's notes.

The rule behind every step: **prefer a source that covers the whole country over one
that covers one town.** A national source gets wired into the baker once, and every later
town in that country gets it free. Israel had to go town by town (Tel Aviv's survey,
Givatayim's storeys, Ramat Gan's layer, Ashdod's 316 heights), and each town cost a
session. The Netherlands' 3D BAG or France's BD TOPO is one entry in `SURVEYS` for the
whole country.

## The steps

1. **Pick the city: fill in a card (below) and score it.** Before baking anything, spend
   about 15 minutes checking what data exists, and write the card down with each answer
   marked *checked* (you opened the source) or *believed* (from memory or a search
   snippet).
2. **Choose the box.** The size we aim for is Givatayim or Bedford: 2-5 km² baked, a
   2-3.5 MB city file. A whole big city is too much, so take a bbox of a few
   neighbourhoods. Keep `--margin` (250 m) so the world does not stop at the edge. Use
   `bare_ground` for a town of towers.
3. **Bake** with the "bake a real city" workflow (`.github/workflows/bake_city.yml`; GAME.md,
   "Where the city comes from"), then record its inputs in DEV.md's "Cities" table.
4. **Add the official layers** the card found, in this order of value:
   1. building heights or floors (`SURVEYS` in `tools/osm_city.py`);
   2. street trees;
   3. transit (GTFS);
   4. street furniture such as lamps and hydrants (`TOWN_LAYERS`);
   5. businesses.

   Save each extract in `cities/data/`. Keep its fetch script in `data_tools/` and
   write its licence and on-screen credit line down. A national source goes in once,
   for every town it covers.

   **Write a credit as "what © who"**, e.g. "building heights © 3DBAG by tudelft3d and
   3DGI, CC BY 4.0". The on-screen line (`_credit_line` in streets.gd) folds "... ©
   X Municipality" credits into one line, and shows any other "... © ..." whole. A
   credit with no " © " in it lost its owner on screen: Delft's first build showed
   "building heights, trees ©" and nothing after it.
5. **Country pack.** This step only applies to a country the game has not had before.
   See "What is Israeli in the code today" below.
6. **Add the level line** to `LEVELS` in `streets.gd`:
   - `city`, `look` and `decks: "infer"`, and no `group`: the start screen's "Cities: pick
     one" lists every city by itself (a `group` would put it on the start screen as well);
     add the line at the end of `LEVELS`, so no other level's number changes;
   - `start`: a *public* corner, by street names as OSM spells them, never an address
     the user has mentioned as theirs.
7. **A walk and a drive.** Every city has both (the user, 22 Nov: "in any case we do a new
   city we put a new walk and drive from those cities"):
   - a walk: a line in `data_tools/make_walks.py`'s `WALKS` (`--list <city> <street>` gives a
     street's junctions; legs, or a footway's `path`; `promenade` for a boulevard's middle or a
     canal's quay) and its level at the end of `LEVELS` (`walk`: its id); run the tool, then
     `SCAN=1 tests/run.sh filmed_walk <level>` until it prints no INSIDE, EYE IN or ON ROAD;
   - a drive: a line in `tests/pick_routes.py`'s `CITIES`, then `pick_routes.py --add <city>`
     (appends its route, the others' numbers kept).
8. **Check it:**
   - `tests/city_check.gd` on the new level, which runs every user-reported family
     across the city as built;
   - the playtest (smart + idle);
   - the exam (`tests/validate.sh`);
   - a few screenshots at the start corner.

   Add the town to `validate.sh`. Set its `city_check` limits from its first run, and
   write down why any limit is not 0.
8. **Write it down:**
   - the card's outcome and what was hard go in DEV.md's "Cities" section;
   - anything that would have saved time goes into this file.

## What a city can have, and where it comes from

| Layer | Used for | Without it (OSM only) | Better source | Where it plugs in |
|---|---|---|---|---|
| Roads, buildings, parks, water, lights, crossings, rail | everything | -- | OSM is the base everywhere | `osm_city.py` |
| Building heights / floors | skyline, block look | guessed by kind and size (most buildings, in most towns) | national 3D or height data, or a town survey | `SURVEYS` |
| Roof shapes | skyline | flat roofs | LoD2 (NL 3D BAG, German states) | not wired yet |
| Ground heights | hills, slopes | -- | AWS terrain tiles already; national lidar is finer | baked |
| Kerbs, pavements, road surfaces | kerbs, paving | worked out from guessed widths (the source of many bugs) | NL BGT (every road part drawn: carriageway, cycle path, footway) | not wired yet |
| Street trees | streets' look | made-up trees | town tree inventories, NYC census | `cities/data/<town>_trees.json` |
| Lamp posts, hydrants, benches | street furniture | made-up | town GIS | `TOWN_LAYERS` |
| Shops, businesses | shop fronts and signs | OSM's POIs | town business licences | `TOWN_LAYERS` |
| Bus routes and stops | buses | OSM stops | GTFS (national feeds in NL, FR, DE, UK; per agency in the US) | `data_tools/gtfs_towns.py` |
| Car makes and colours | traffic look | -- | the national vehicle register | `data_tools/car_mix.py` (Israel only) |
| Speed limits | AI drivers | 50 in town | OSM `maxspeed` where tagged | baked |

## What is Israeli in the code today (the country pack)

A city in a new country needs a decision on each of these:

- **Which side of the road.** All the driving code assumes the right (lanes,
  roundabouts, overtaking, AI drivers). The UK and Ireland mean the one big job. Until
  then, left-hand-driving towns are walk-only, or not done.
- **`look`.** Today there are only `"med"` (palms, solar heaters) and `"north"`
  (conifers). A new region can mean a new look, with tiled pitched roofs, brick and
  other street-light types (`streets.gd`, wherever `look ==` appears).
- **Signs and lettering.**
  - Street-name plates are Hebrew and English, with Hebrew fonts and right-to-left
    text handling.
  - A Latin-script country needs its plate style: Dutch blue, French blue enamel, US
    green.
  - The US also needs yellow centre lines and lights hung over the far side of the
    junction.
- **Car mix.** It comes from Israel's register (`cities/data/vehicle_mix.json`). Use a
  national register where one is open (the Netherlands' RDW is), or otherwise a
  hand-set mix: pickups for the US, small hatchbacks for Europe.
- **The build stamp's clock** (`israel_time`). Leave it as it is: it shows the
  developer's time, not the city's.
- **Local rules.** Trams sharing the road (Delft, Heidelberg), right turn on red and
  4-way stops (US), bikes everywhere (NL).

Write each choice down here once it is made, so the second town in that country takes
it as given.

### Countries done

**The Netherlands (Delft, level 14, 22 Nov 2026).** For the next Dutch town, run two
commands with its box (the bake's box plus the margin, as the bake prints it:
"fetching S,W .. N,E"), then bake. Nothing else changes:

```
python game/streets/data_tools/nl_3dbag.py S,W,N,E   # heights, storeys, roof type, year: ~30 s for 15k buildings
python game/streets/data_tools/nl_bgt.py S,W,N,E     # trees and lamp posts: ~90 s
python tools/osm_city.py --place "<Town>" --bbox ... --out game/streets/cities/<town>.json
```

- **What was found.** All three national sources answer from this computer, with no key
  and no login:
  - 3DBAG: the WFS at `data.3dbag.nl/api/BAG3D/wfs`, layer `BAG3D:lod12`, WGS84 GeoJSON.
  - BGT: PDOK's OGC API at `api.pdok.nl/lv/bgt/ogc/v1`.
  - GTFS: `gtfs.ovapi.nl`.

  The cloud has not been tried yet.
- **OSM's buildings here are the national register (BAG) imported.** So 3DBAG's shapes
  match OSM's one to one: a shift of 0.0 m, and heights for 14,626 of 15,288 buildings.
  Guessed heights fell from 8,614 to 454. OSM also has the year built on 99% of them.
- **The BGT keeps every old version of an object.** About 1 in 6 rows has
  `eind_registratie` set: skip those, or every tree comes twice.
- **Extracts.** They are national files that only grow, merged by id:
  - `nl_3dbag.geojson`: 5.0 MB for Delft's 15k buildings. Its size grows with every
    Dutch town, so past a few towns, split it per town.
  - `nl_bgt_trees.json` and `nl_bgt_lamps.json`.
- **First run (22 Nov):**
  - loaded in 4.9 s headless, 13.4 s drawn beside other sessions' Godot runs;
  - `city_check`: all 0 except 39 m² of islands on asphalt (DEV.md, "Open problems");
  - playtest: no errors.

  The first screenshot (Oude Delft) shows real shop names and measured heights. The
  buildings still wear the Israeli facades (plaster, white window bars, flat roofs), not
  brick and gables.
- **The Dutch look (22 Nov, later): the level's `"build": "nl"`.** It is a key of its
  own, not a third `look`, because `look` is compared in ~30 places (trees, signals, kerbs,
  plates) that should stay `"north"`. Only the buildings read it (`_dutch()` in streets.gd).
  - **The bake** carries 3DBAG's ridge (`rr`, m above the ground) onto every building
    whose roof type is "slanted": 6,978 of Delft's 15,288. The survey entry gets
    `"ridge"` and `"pitched"` (SURVEYS).
  - **Do not use 3DBAG's lowest roof point as the eaves.** It is the back extension's:
    3-4 m under a 13 m ridge on a three-storey canal house. The game works out the eaves
    instead. Rise = 0.6 of the footprint's span (about 50 degrees), at most half the
    ridge; eaves = ridge - rise; the walls stop there and the roof rises to the measured
    ridge (`_dutch_pitch`).
  - **Only mostly rectangular footprints are roofed** (72% of their tightest rectangle or
    more, under 2,500 m²). An L or a block round a yard would have a roof floating past
    its walls. 5,892 houses got a measured roof (`roofs_measured` in the city event); the
    rest keep a flat roof at 3DBAG's height.
  - **Brick** is a `brick` switch in WALL_SHADER: red-brown 45%, dark 25%, yellow 15%,
    mixed 8%, painted 7%. Stretcher bond, 22 x 5 cm, fading to its average past a few
    metres. White-framed windows (the `siding` house windows, without the clapboard
    grooves), no security bars. Gable ends are brick in the walls' own mesh, with no
    windows. Tiles are orange clay or dark glazed, about half each.
  - **Colour:** the palette's red is a pink. On screen the first brick read 193/129/127
    (salmon) and the tiles 240/132/134. Mixing them about half toward the palette's
    yellow gives brick and terracotta.
- **Choices made.**
  - The look is `"north"`; the buildings `"build": "nl"`.
  - Street plates are still the Israeli style.
  - The car mix is still Israel's.
  - Not done yet:
    - Dutch blue street plates, bikes, trams, the RDW register for the car mix;
    - the canal houses' stepped and bell gables;
    - roofs on L-shaped footprints (each wing its own rectangle).
- **What the BGT has that the game does not use yet:**
  - road parts as polygons (`wegdeel`: carriageway, footway, cycle path, with their
    paving), the real kerbs;
  - bike racks, benches, bollards (`straatmeubilair`);
  - sign and signal poles (`paal`);
  - bridges (`overbruggingsdeel`), water (`waterdeel`).

## The city card (fill in one per candidate)

```
City:                    Country:            Box: (S, W, N, E)   ~km²:
Why it is interesting:   (what it adds that no city in the game has)
Drives on:               right / left
OSM completeness:        (are buildings, kerbs, trees, lights mapped? look at osm.org)
Heights:      source / licence / national or town / checked or believed
Roofs:        ...
Kerbs/paving: ...
Trees:        ...
Furniture:    ...
Transit GTFS: ...
Car mix:      ...
Reachable from the cloud? (or does it need a session on the user's computer)
Credits line on screen:
Country pack needed: (new look / signs / rules; anything already done for that country)
Score: data __/10, country cost: none / small / big
```

## Candidates scored (22 Nov 2026)

Each answer is marked *checked* (a search or page found the dataset) or *believed* (known
from general knowledge, not yet opened). None has been fetched yet.

| City | Box | Heights | Roofs | Kerbs | Trees | GTFS | Country cost | Data |
|---|---|---|---|---|---|---|---|---|
| **Delft, NL: BAKED, level 14** (old town, canals, trams) | 52.0010,4.3440,52.0190,4.3700 | 3DBAG lod12 (checked, used) | 3DBAG LoD2 (checked: roof type on every building; shapes not used) | BGT `wegdeel` (checked; not used yet) | BGT, 11,178 in the box (checked, used) | OVapi (checked: answers) | small: Dutch signs, trams, bikes | 9 |
| **Annecy, FR** (old town, canals, lake, mountains) | town | BD TOPO, national, Licence Ouverte (believed) | no | no | none found (checked: nothing for Annecy on data.gouv.fr) | national portal transport.data.gouv.fr (believed) | small: French signs | 6 |
| **Heidelberg, DE** (old town, river bridges, castle hill) | Altstadt bbox | from LoD2 | BW LoD2, freed in 2024 per the state, but its record still says copyright (checked: licence unclear) | no | none found | national (believed) | small: German signs, trams | 6 |
| **Burlington, VT, US** (hill down to the lake) | downtown | Vermont statewide lidar (believed) | no | no | only sample plots (UVM i-Tree, CC BY-SA), not every tree (checked) | GMT (believed) | medium: the US look | 5 |
| **Savannah, GA, US** (grid of 22 squares) | historic district | SAGIS portal, not confirmed (checked: no footprint layer found) | no | no | an inventory under way, not published (checked) | CAT (believed) | medium: the US look | 4 |
| **Greenwich Village, NYC** | ~1.5 km² | NYC footprints with heights (believed) | no | NYC planimetrics (believed) | NYC tree census (believed) | MTA (believed) | medium: the US look; very dense | 9 |
| **Bath / York, UK** | town | OS Building Height is licensed, not open (checked); lidar is open, so heights could be worked out (believed) | no | no | not looked at | national BODS (believed) | **big: driving on the left** | 4 |

**Recommended first: Delft.** It has the best data in Europe and needs only a small country
pack. Its national sources (3D BAG, BGT, GTFS) then make every later Dutch town (Haarlem,
Leiden, Utrecht's centre) nearly free.

BGT is worth checking first. Kerbs and paving worked out from guessed widths are
where many of the user's bug reports came from, and BGT draws every carriageway, footway
and cycle path as it is.

Second: Annecy, for the mountains and the lake, and to put BD TOPO in for all of France.
