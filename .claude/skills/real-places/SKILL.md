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
  onto a street a little way toward the middle of town. Count a push that goes nowhere
  (foot down, not moving, too slow to register as a hit) toward that too, or the AI noses a
  bollard, backs off and noses it again for minutes.
- **Dead ends are everywhere** (cul-de-sacs, streets that end in a footpath), and houses
  stand at them. Three traps: a route planner that charges nothing for turning round plans
  "on to the closed end and back" from a house there; a U-turn planned as a lane out and a
  lane back is a corner a few metres across, which a car takes wide -- onto the footpath
  that continues past the end; and AI traffic that picks streets at random drives into
  them and turns round in a queue of its own. Never take "to the end of this street and
  straight back" as a route's start; stop at the end and turn round there; keep traffic
  out unless there is no other way.
- **Start a plan in the lane**, not at the nearest point of the road's centre line: the
  line from there to the next point (often far down the street) runs diagonally, and the
  car drives left of the middle for the length of the street.
- **Score the driving, don't eyeball it**: a scripted exam that drives the AI from several
  places in town and counts per minute (stuck, hits, off the road, wrong side, red lights,
  harsh braking per occasion, and traffic's own stalls, overlaps and reds) finds in one run
  what an afternoon of watching does not. Count a signalled junction as one, by the way the
  car came in: a divided road's junction is several signalled points, and judging each by
  the heading mid-turn reads a car that went in on green as running the cross street's red.

## The edge of the map

The baked area ends; don't let it end in an invisible wall. A striped barrier along it
(following the ground), a soft glow over it that shows when near, a line on the minimap,
a banner on contact -- and keep the car's own collision circles off exactly that line.

## Checking a street against a filmed walk

The fastest way to see what is wrong with a street is the user filming it on a phone and
the game walking the same route in first person beside it.

- **Getting footage in.** The connectors cap downloads at about 10-12 MB, OneDrive's will
  not hand over a video at all, and a phone's 3-minute video is ~350 MB (emailed, it turns
  into a Drive link, which is not the file). Two ways that work: frames, with VLC's scene
  filter writing a JPG every few seconds into a synced folder (images come through the
  OneDrive connector one by one: a helper agent can read and describe all of them without
  filling the main conversation), or a short clip under 10 MB (VLC
  `--sout=#transcode{vcodec=h264,vb=600,scale=0.3}`, `--stop-time`), sent as a real email
  attachment, which the Gmail download tool saves to disk.
- **Orientation.** VLC's scene filter ignores the phone's rotation flag (frames come out
  sideways), and its transcode of a portrait video can come out **mirrored**: check a shop
  sign's text before believing which side anything is on, and flip with ffmpeg `hflip`.
  Reading sides off a mirrored clip put a fence on the wrong side for a whole pass.
- **Matching the two.** A contact sheet at one frame a second gives the landmarks' times;
  walking time gives distances (people walk 1.2-1.3 m/s): a road that takes 15 s to cross
  is ~17 m, whatever OSM's guessed width says. Time the game's walk to the same landmarks,
  so the two pass each place together. A phone held upright sees about 70 degrees
  vertically: render 16:9 at that and crop the middle 9:16.
- **What footage showed the map gets wrong**: a passage drawn as one footpath that is
  really a forecourt, the passage and a short street with parked cars; a footpath's end
  joined to the nearest junction point rather than where it meets the street; a crossing
  mapped as a footpath between the two kerbs with no crossing tag, so no zebra; widths by
  class. Fixing it in OSM is best; until the user does, a hand-placed layer over the baked
  file (road edits, zebras, walls, fences, railings) survives a re-bake, where editing the
  baked file would not.

## Privacy

A web build is public. Never use an address the user mentions privately -- their home,
their family's -- as a start point, a test location, or in any committed file, commit
message or doc. Test against it in a scratch script if asked, and leave it there. A walk
the user filmed is published only as far as the public corner they name; the film, its
frames and the rest of the route stay out of the repo, and so does any word of where the
walk ended (a quote saying "to my house" beside a route that stops at a named street gives
the street away).
