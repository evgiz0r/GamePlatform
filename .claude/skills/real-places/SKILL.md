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
- **Traffic lights at a knot.** Make the knot one signalled junction (a "site"): the lit
  points a short road apart (~35 m; join the shortest first and cap the site at ~50 m
  across, or a chain of them swallows the next junction), plus the unlit other half of a
  divided road. Group its ways in by direction across the whole site -- along the main
  road, then across it -- never per point and never by street name: a street that changes
  its name at the junction landed in the same group as the street across it, and per point
  a road had green at one half of a divided road and red 10 m on. A car is in the site from
  its nose crossing the stop line and goes through all of it (a fixed "the next 45 m" rule
  both missed big knots and swallowed separate junctions). Lights and stop lines only on the
  ways in from outside. A light OSM maps 30 m out on one approach belongs to the junction:
  stopping at the mapped point stopped cars 30 m short. A zebra mapped a few metres out puts
  the stop line behind it. Two sites close together: give the road between them the same
  group. OSM cuts one street into several ways: walk across those joins (a point with two
  ways) when looking along an approach. Audit every junction in a scene test -- crossing ways
  sharing a group, a road whose group changes inside a site, ways in with no pole, zebras
  whose road has green one way -- before driving one: in one town it found 12, 48, 66 and 26.
- **Roundabouts** are closed one-way ways (or tagged junction=roundabout). An AI that plans
  to the end of the way drives the whole circle, then picks "straight on" -- round again.
  Plan only to the next exit, and make staying on less likely with every piece driven.
- **A junction's asphalt is more than its roads.** Laid as a disc at the junction's point (as
  wide as its widest road) and rounded at the corners, it is covered by no single road's
  width. Anything placed "off the road" by distance to the roads' centre lines -- railings,
  bollards, a hydrant -- can stand in a junction's mouth. Check the disc too, and check both
  ends of anything long (a railing panel), not its middle.
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

## Bridges, tunnels: roads at different levels

OSM tags which ways are bridges (`bridge=yes`, `layer=1`), tunnels (`tunnel=yes`,
`layer=-1`) and sometimes the ramps (`embankment=yes`, `cutting=yes`), but not how high
anything is; a bridge way is usually only the span, its ramps ordinary ways. Until the
heights are worked out, a baked town's bridges lie on the ground and its tunnels are best
left out. A made-up town can give each such way its surface's height at every point (the
city format's `y`), and that is enough for a game to do the rest. What a driving game on
one needed:

- **One height per point is the whole problem.** Everything that asked "how high is the
  ground here" -- the car, its pitch, the camera, traffic, people, collisions -- now asks
  "how high is the surface under this, for something at this height": the highest of the
  ground and the decks there that is no more than a step (~1.2 m) above its feet, else the
  lowest. Each mover keeps its own height, and that alone keeps a car under a bridge under
  it and one in a tunnel off the hill above. Start a mover at "the top" (a huge height),
  and put one down on a road at that road's height.
- **Each road's nearest segment, never past its ends.** Several segments of one deck are
  near any point on it; taking the highest of them gave the next one's end height, a
  stepped surface, and the car took off from every joint (half of a tunnel run airborne).
  Then a road's end still counted a few metres past it, at its end height. Nearest segment
  per road first, and drop the road when that is its end and the point lies beyond.
- **Keep the decks away from the ground's builders.** Kerbs, parked cars, lamps, walkers,
  fences, signs placed along a deck stand on the ground under a bridge or on the hill over
  a tunnel. Leave decks out of whatever list those builders walk and draw them separately
  (asphalt and paint can reuse the ground's own code with the height source swapped).
- **Every lookup takes a level.** "Nearest road" (a level-less one skips decks far from the
  ground's level), collisions with buildings, fences and trees (only for a body near the
  ground's level: a car in a tunnel was shoved out of the houses above), traffic's "car
  ahead" and the player-against-traffic push, and every look-ahead probe an AI driver makes
  (autodrive crawled under a hill at 30 km/h, braking for the houses over its head).
- **Cut the ground open** over a cutting (clip the terrain mesh's triangles round its
  footprint) and drop any far-off flat ground plane below the deepest deck, or it shows
  through. Inside a cutting's footprint the ground is never a surface, however shallow:
  switching to it where the cut is 5 cm deep was a step a car hopped off.
- **A bridge's end must be off the bank's slope.** A height grid's triangles bend the ground
  a cell beyond where a dug river channel starts; a bridge ending on that slope has a crest
  just past its end. End it a cell further out. And keep its end away from junctions (20 m
  or so): a car turning in clipped the parapet's start.
- **Water held at its own level** (a river between weirs) is drawn at that level and is too
  deep to drive into; gentle banks otherwise let a car down to drive along the bed under
  the water. Leave lakes that lie at their shore's lowest point alone: a road over an
  inlet runs on ground below their level.

## The edge of the map

The baked area ends; don't let it end in an invisible wall. A striped barrier along it
(following the ground), a soft glow over it that shows when near, a line on the minimap,
a banner on contact -- and keep the car's own collision circles off exactly that line.
An AI that picks its way at junctions must see the edge coming: a street that runs off the
map looks like any other until the barrier. Look a few hundred metres down each way on and
score down one whose every continuation hits the edge (not ordinary dead ends -- exploring
those is fine), and end a planned road a few metres short of the barrier as a dead end.

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
- **Seek by decoding, not with `-ss`.** A phone clip re-encoded at a variable frame rate
  (VLC's transcode is one) can make `ffmpeg -ss <t> -i clip` land seconds off in its first
  stretch, while `-vf trim=<a>:<b>,setpts=PTS-STARTPTS` (decoding from the start) agrees
  with the clip's own clock: a contact sheet cut with `-ss` once put a 14 s road crossing
  in the first 3 s. Cut contact sheets the way the side-by-side is cut.
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
- **A block's outline is its upper floors.** OSM traces buildings from above, so where the
  ground floor stands back under the upper ones (an arcade of shops along a main road, a
  block on columns) the outline runs out over the pavement, and a walk filmed under it goes
  "through" the building: from inside, its walls are not drawn, so a first-person replay
  looks open and nothing seems wrong until a check says the walker is inside a footprint.
  Measure the walk's points against the footprints. What worked: cut the strip off as a
  building of its own raised 3-3.5 m (a raised building stands on columns and is not
  solid), the rest standing back behind it, both outlines starting at the same corner when
  the look comes from a hash of the first corner.
- **A level that starts at a filmed spot must say so before the city builds.** A game that
  builds near its start first builds round wherever its start finder lands; a walk placed
  after that crosses bare ground until the background builder catches up.

## Privacy

A web build is public. Never use an address the user mentions privately -- their home,
their family's -- as a start point, a test location, or in any committed file, commit
message or doc. Test against it in a scratch script if asked, and leave it there. A walk
the user filmed is published only as far as the public corner they name; the film, its
frames and the rest of the route stay out of the repo, and so does any word of where the
walk ended (a quote saying "to my house" beside a route that stops at a named street gives
the street away).
