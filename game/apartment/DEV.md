# apartment -- developer notes

- The plans come from `lab/apartments/plan.py --export 1-8 --out game/apartment/plans`
  (Python, Pillow). That prints the `LEVELS` lines to paste into apartment.gd. The plan
  JSON's x is the world's X, its y the world's +Z; the flat is centred on the origin.
- Every item and wall is boxes merged into one mesh per colour (`_box`, `_commit`): the
  flat is ~25 draws. Ceilings are a mesh of their own (hidden in the dollhouse).
- Collision is the walker as a circle pushed out of rects (`_solid`: walls, windows,
  rails, furniture except chairs and plants). Doors are gaps in the wall runs.
- A wall run reaches half its thickness past its ends to close corners, but not into a
  door opening: it did, and the mamad's 30 cm walls left its door 50 cm wide (the tour
  could not get in).
- The tour finds its way on a 20 cm `AStarGrid2D` of where the walker fits. In each room it
  walks to a metre in front of its one or two best pieces (`INTEREST`, `_stand_by`) and
  looks at them (`look_at` steps); the head (`_head`) is separate from the body: it glances
  at pieces it passes (in sight, ahead, not seen in 8 s) and aims at each piece's middle
  height (`MID_H`). A step bob of 2 cm.

- Furniture: each item is its own MeshInstance3D built round its centre (`_make_item`,
  `_org`), with its rect in `items`; `_blocks()` is walls + solid items, for walking and
  the tour's grid (dropped whenever a piece moves). Decorating is `_deco_press/_drag/
  _release` (taps, drag by the finger's delta) and `_deco_keys` (arrows, space), all through
  `_try`/`_fits`.

- Furniture models are Kenney's Furniture Kit (CC0, `assets/models/furniture/`). They face
  +Z and are about half real size, so `_furnish_model` fits each one to its item's rect
  (non-uniform scale); kitchen runs are tiled.
- Outside (`_build_outside`): the flat sits `FLOOR_UP` storeys up (3, or a level's
  `"floor"`), `STOREY` m each; the storeys above are their own mesh (`_above`) so the
  dollhouse can hide them. Stairwell and lift (`_build_core`): walking is level-aware,
  `_blocks()` picks the solids of the level you are on and `_height()` the nearest floor.
- Garden flats (`"floor": 0`): `_build_garden` puts a `GARDEN_D` m lawn in front of the
  mirpeset with hedge/fence solids and a gate gap; the rail becomes a kerb, no columns. The
  film starts at the gate (`_start_tour(false, true)`).

## Tests

`tests/run.sh views <level>` (needs `$GODOT`, xvfb): dollhouse + eye-level shots of the
entrance, salon, parents' room, mamad and kitchen into `$OUT`, then the whole tour.
Good: `tour missed: []`, no "stuck", about 65-95 s of tour. Takes ~1 min.

`tests/run.sh decorate <level>`: picks up the sofa, drags it into a wall (must go back),
to free floor (must stay), rotates it; shots before/after. Good: "decorate: ok".

`$GODOT --headless --path . -s res://game/apartment/tests/doors.gd`: every door's clear
opening in all 8 flats, walls alone and with furniture. Good: "doors: ok" (70 cm or more).
About 30 s.

Video: `FPS=15 RES=640x360 timeout 590 xvfb-run -a -s "-screen 0 1280x720x24" bash
tools/record_video.sh apartment <level> 200 out.mp4` (about 8 min; the film starts on the
street, or at the garden gate for a garden flat, then the tour). Garden flat (level 9):
`views 9` reached every room, 172 s of tour.
