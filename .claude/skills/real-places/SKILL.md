---
name: real-places
description: 'Building a game on a real town baked from OpenStreetMap (tools/osm_city.py) or a made-up one (tools/fake_city.py): the traps in the data -- guessed widths, divided roads as two roads, one junction as several points, roundabouts, car parks mapped only by their lanes, buildings standing in the road -- and what worked for each; people, kerbs, AI drivers, the map edge, privacy. Use before and while building a driving or walking game on a baked city.'
---

# Real places: what OSM data does to a game

A baked city looks finished on the minimap and is full of traps up close. Each section
below was a round of the user's bug reports in a driving game built on baked towns. The
data format is at the top of `tools/osm_city.py`; this is about living with it.

## Getting a city

- `tools/osm_city.py` needs Overpass. From a cloud session that cannot reach it, start the
  "bake a real city" workflow (`.github/workflows/bake_city.yml`, inputs `place`, `out`,
  and for an odd shape `margin` and `include` -- extra named areas to pull in). It commits
  the file to `main` itself; fetch and merge before your next push. Overpass is sometimes
  down: a failed run is worth one retry later, and a run stuck "queued" for an hour can be
  abandoned and started again.
- `tools/fake_city.py` makes up a small town with one of every awkward thing (divided
  boulevard, big signalled junction, roundabouts, a one-way pair, a steep hill, car parks)
  in a second, no network. Use it to check a change quickly; check real towns before
  publishing, because real data is messier than anything made up.
- Re-bake when the baker learns a new field (it keeps nothing it was not told to): the
  game should treat a missing field as "not known" so old files still load.

## Roads

- **Width is a guess.** OSM rarely has `width`; the baker guesses by class (8 m for a
  residential street). Old narrow streets come out wider than the gap between their
  buildings, and the road runs under the houses. Fit it: sample the room each side along
  the road (step the half-width in until a probe 0.9 m beyond the asphalt clears every
  building), take about the 30th percentile of those (most of its length, not one
  corner), never below two lanes.
- **The rest of the buildings are cut, not the road.** After the fit, a building still
  within the asphalt plus 1.5 m (kerb and pavement) has that part clipped off its footprint
  (`Geometry2D.clip_polygons` against a capsule round each road segment -- a rectangle
  leaves the outside of every bend and every junction's middle uncut). Skip one that would
  lose more than half (a road passing under it: OSM maps the passage, not a gap) and one
  raised on columns (`min_height`), and keep the outline's winding.
- **A divided road is two one-way roads**, each guessed at the full class width, so the
  halves overlap and each one's kerb and pavement run down the other's lanes. Find each
  half's partner (one-way the other way, on its left, within ~40 m along most of its
  length), size each half to its lanes (3.3 m a lane), remember the median between them.
  Its inner side gets a kerb and half the median, not a pavement; people walk only on the
  outer sides; a zebra on one half is crossed kerb to kerb across both.
- **Lanes**: `lanes` counts both directions on a two-way road. Cap any count by what the
  width holds (a "two-lane" road narrowed to 4 m has one). On a one-way road of several,
  drive the middle of the right-hand lane -- the middle of the road is astride two.
- **The ground's thin layers z-fight on phones.** Grass, paths, asphalt and paint a few
  millimetres apart showed grass through the road in green patches on a phone's coarser
  depth buffer. Keep them centimetres apart and the camera's near plane at 0.3 m or more
  (only a cockpit view needs it closer).

## Junctions and roundabouts

- **One junction is often several points.** A divided road meets a street at one node per
  half, 10-30 m apart; two divided roads cross at four. Anything that acts "at a junction"
  -- asking the player which way, signalling, giving way -- acts at each point in turn.
  Treat a knot as one: from the junction point, follow short legs (under ~35 m) that end at
  another real junction, up to three deep, and offer the ways out of the whole knot (each
  with the legs that reach it, driven without asking again). Leave out ways that loop back
  into the knot, and merge two routes to the same exit.
- **Turn through the junction, not to the next point.** The next street's first mapped
  point can be 30-100 m away; a straight line from the junction to it runs down the wrong
  side of the new street, into oncoming traffic. Curve from just short of the junction in
  the current lane to just past it in the right lane of the new street.
- **Roundabouts** are closed one-way ways (or tagged junction=roundabout). An AI that plans
  to the end of the way drives the whole circle, then picks "straight on" -- round again.
  Plan only to the next exit, and make staying on less likely with every piece driven.
- **Kerbs at corners**: cut kerb runs only where three or more kerbed ways meet (two OSM
  pieces of one street join at a node too), round the corners, and check a corner kerb
  against other roads' asphalt along its whole length -- checked at its middle only, a
  straight kerb across a road's mouth went in whole and laid a strip of pavement across the
  junction. A fine grid (8 m) of road segments makes those checks cheap while building.

## Car parks

- Many car parks are mapped only by their lanes (`service=parking_aisle`), no area: the
  baker drops service lanes unless told to keep them. Keep the kind (`sv`), and lay bays
  down each side of each aisle. Mapped areas get rows of bays. Cap the cars per lot and per
  city (thousands of parked cars is a phone's frame rate).
- Keep the AI out of service lanes and car-park aisles unless there is no other way.

## People

- Walk them along a line on the back half of the pavement (parked cars stand on the front
  of it), and cut that line wherever it would cross another road's asphalt -- a service
  lane alongside, the next street at a corner -- forgiving a few metres (a driveway's
  mouth). Measured: before, 29% of walkers in one town stood on asphalt.
- **Feet on the surface, not the ground height.** A pavement is a kerb's height (plus any
  terrain lift) above the bare ground; people placed at the ground height waded knee-deep
  into the slabs.
- People who stand on the AI's lane must stop it, not only people on zebras.

## AI drivers in a real town

- **Off the road** (handed over in a yard, knocked onto a lawn), heading straight for the
  nearest road goes through the wall in between, backs off and does it again. Search
  outward over 2 m squares the car fits through to the nearest asphalt and drive that.
  With no way out in reach, or after a few wall hits in quick succession, put it back on
  the street.
- **A car on your lane is a car whose body would touch yours**, not one whose middle is
  near your line: a fixed 1.5 m from the middle let the player's AI run in between two cars
  in the lanes either side.
- **Standoffs in narrow streets.** Traffic that waits for the player and a player's AI that
  waits for traffic wait for ever. Give one side a way out: after a few seconds face to
  face, the traffic car edges past if there is nearly room, else turns off (once out of
  sight, or after a while regardless).
- **Give up gracefully**: an AI that has got nowhere for 40 s (not at a light) is lifted
  onto a street a little way toward the middle of town.

## The edge of the map

The baked area ends; don't let it end in an invisible wall. A striped barrier along it
(following the ground), a soft glow over it that shows when near, a line on the minimap,
a banner on contact -- and keep the car's own collision circles off exactly that line.

## Filmed walks and drives

The map says where things are; a film of the street says what they look like. The useful
recording is a phone video **and** a GPS track taken at the same time, so every frame has
a place and a heading on the baked ground.

- **Recording.** Phone video at 1080p30 on the main 1x lens (the wide lens warps). A GPS
  logger that exports GPX at a point a second with its extended data -- speed, accuracy,
  satellites (Geo Tracker on Android did: min distance at its lowest, compass off, battery
  optimisation off or Android stops it mid-drive). It saves nothing while you stand still,
  so a gap in the track is a stop and its length the wait. On foot its points were good to
  ~4 m: the side of the street, not the spot on the pavement. Its `c` attribute is not the
  heading (it sat at ~5 for a whole walk): take the heading from the positions, +-3 s.
- **Lining up.** Both come off the phone's clock. The video's file name is its start in
  local time; the mp4's `creation_time` is (on that phone) the *end*, in UTC: start =
  creation_time - duration. The two agreed to ~3 s. GPX times are UTC.
- **Getting the video into a cloud session.** The Google Drive connector downloads only
  files under 10 MB: fine for the GPX, never for a video (a few minutes is 300-400 MB).
  Allow `drive.usercontent.google.com` in the session's environment, ask the user to set
  the file to "Anyone with the link" in Drive (a session changing a file's sharing itself
  was refused by the safety check: it is the user's step), fetch it with
  `curl -L "https://drive.usercontent.google.com/download?id=<id>&export=download&confirm=t"`,
  then tell them to set it back to Restricted (check with the connector's permissions call).
- **Comparing.** Project the GPX with the bake's own flat projection (`Proj` in
  `tools/osm_city.py`, origin from the city file), cut stills with `ffmpeg -ss <t> -i v.mp4
  -frames:v 1` every ~10 s and at the stops, label each with the nearest street, then stand
  the game's camera on the same spots and heading (a scene test with the dev camera at
  chest height, ~1.35 m; a 70 degree vertical field is about a phone's main lens held
  upright, so crop the middle 9:16 of a landscape shot) and set the pairs side by side.
  What differs, biggest first, is the work list.
- **Putting the camera on the pavement.** On a narrow street the raw GPS point is the
  middle of the road. Put each spot on the pavement of the side the film shows (left or
  right of the way the walker faces) at half the road's width + ~1.6 m. Mid-walk that moved
  the spots 0-2 m; in the first half-minute of the track and next to a big junction 6-12 m,
  and there the nearest street can be the wrong one (the cross street) -- check those
  pairs by eye, or name the street. The film's heading can differ from the walking
  direction: a walker who turns to look at a shop is not looking where they go.

## Privacy

A web build is public. Never use an address the user mentions privately -- their home,
their family's -- as a start point, a test location, or in any committed file, commit
message or doc. Test against it in a scratch script if asked, and leave it there.

A filmed walk or drive very often starts or ends at the user's door, and a GPS track
recorded "just to test" at home is their address to a few metres. Keep the video, the GPX,
the stills and the projected route in the scratch directory; commit what was learned (a
fence, a kerb colour, a walking speed), and trim any route that goes into the game back to
public corners. Ask where it started if it is not obvious.
