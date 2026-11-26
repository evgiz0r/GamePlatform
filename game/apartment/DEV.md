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
- The tour finds its way on a 20 cm `AStarGrid2D` of where the walker fits.

## Tests

`tests/run.sh views <level>` (needs `$GODOT`, xvfb): dollhouse + eye-level shots of the
entrance, salon, parents' room, mamad and kitchen into `$OUT`, then the whole tour.
Good: `tour missed: []`, no "stuck", about 65-95 s of tour. Takes ~1 min.

Video: `FPS=15 RES=640x360 xvfb-run -a bash tools/record_video.sh apartment 1 90 out.mp4`
(about a minute; the film starts in the dollhouse, then the tour).
