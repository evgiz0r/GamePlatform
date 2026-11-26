# Apartments lab

A bench for making up apartments, outside any game: floor plans, then buildings, then what
is inside. Pictures first; a 3D builder can read the JSON later.

```bash
python3 lab/apartments/plan.py --seed 7       # out/plan_7.png + out/plan_7.json
python3 lab/apartments/plan.py --sheet 1-6    # six seeds on one picture
```

Needs only Python 3 and Pillow. `out/` is not committed. `lab/.gdignore` keeps Godot from
importing anything here.

## What a plan is (v1)

A typical Givatayim / Tel Aviv 4-room flat of the 2000s: stairwell behind, mirpeset
(balcony) in front.

- Back strip: entrance (front door onto the stairwell), toilet, bathroom, mamad, one or two
  bedrooms, the small rooms shuffled.
- A hall across the whole width, open to the entrance, kitchen and salon.
- Front strip: kitchen (entrance side), salon with a sliding glass door to the mirpeset,
  parents' room with its own shower room in a corner.
- Mirrored left/right half the time. Sizes vary with the seed.
- The mamad has 30 cm walls, a steel door and a shuttered window.

Built on a 10 cm grid of room ids: a wall is anywhere two neighbouring cells differ unless
the two rooms are open to each other. Doors go in the longest shared wall near a corner,
windows in the middle of each room's longest outside wall. Furniture tries every spot
along every wall, keeps the best scoring one that is inside the room, backed by a solid
wall and clear of door swings. The salon puts the TV on a wall first and floats the sofa
facing it.

## JSON (metres; x right, y from the stairwell towards the mirpeset)

`rooms` (kind, rect, area), `doors` (o = "h"/"v" line, from a to b along it, style swing /
slider / front, which room it swings into), `windows`, `items` (name, room, rect, face =
the way the item faces: S is +y), `edges_10cm` (every 10 cm wall piece and its kind:
ext / wall / mamad / window / door / rail), `notes` (what did not fit).

## Buildings (v1)

```bash
python3 lab/apartments/building.py --seed 4     # out/building_4_floor.png + _front.png
```

A typical floor: the stairwell (landing, two flights, the lift) in the middle, two flats
either side of it, their front doors on the landing (`Plan(W=, ent_w=20, mirror=)` lines
each entrance up on it). With four flats a floor the back pair is a front pair turned round,
and what the stairwell does not fill between them is an open light well. Walls shared with
the next flat get no windows (`Plan(party=("x0",))`). The street side shows the entrance
floor on columns (parking, the lobby), the floors with each front window, balcony and some
aircon units, penthouses set back on top, and the roof with the lift's machine room and a
solar water heater per flat.

## Next steps (said, not built)

More flat types (3 rooms, 5 rooms, garden flat, the penthouse's own plan with its roof
terrace). Service balcony. More items. Ground floor plan (lobby, mailboxes, bike room,
parking). 3D.
