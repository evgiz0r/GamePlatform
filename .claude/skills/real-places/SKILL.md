---
name: real-places
description: 'Building a game on a real town baked from OpenStreetMap (tools/osm_city.py) or a made-up one (tools/fake_city.py): the traps in the data -- guessed widths, divided roads as two roads, one junction as several points, roundabouts, car parks mapped only by their lanes, buildings standing in the road -- and what worked for each; people, kerbs, AI drivers, the map edge, privacy. Use before and while building a driving or walking game on a baked city.'
---

# Real places: what OSM data does to a game

A baked city looks finished on the minimap and is full of traps up close. Each section
below was a round of the user's bug reports in a driving game built on baked towns. The
data format is at the top of `tools/osm_city.py`; this is about living with it.

## The rule under a quarter of the bugs: the whole body, not its middle

Anything long -- a car, a bus, a wall, a hedge, a fence piece, a kerb corner -- judged at
its middle point is the most repeated bug in a driving game on real streets. In one day
five fixes out of twenty were this one mistake, each found and fixed on its own: a bus
stopping for a red with its middle at the line (its front 4 m into the junction), the AI
keeping its distance from a bus's middle (inside its back), a car waiting crossways seen
by its middle (its nose in the turn, hit), garden walls and hedges checked at their middle
(their ends on the next road). It is written down below five times, in the section where
each was met; this is the one rule behind all of them. **Every check of where something is
uses its outline**: a vehicle is a box its own length and width (its front at the stop
line, its back for the gap), a wall is a box its length and thickness checked along all of
it, a post a circle. A bus is 12 m: half its length is the error, and that is a car's width
of road. The tests can lean on the same shapes (in a game with scene tests, a helper like
`bodies.gd` beside them), and the scored run checks bodies every tick, so a new place this
goes wrong shows up the first time it runs.

## Getting a city

- `tools/osm_city.py` needs Overpass. From a cloud session that cannot reach it, start the
  "bake a real city" workflow (`.github/workflows/bake_city.yml`, inputs `place`, `out`,
  and for an odd shape `margin` and `include` -- extra named areas to pull in). It commits
  the file to the branch it was run on (`main` by default; run it on your own branch to
  check the city before it goes out); fetch and merge before your next push. Overpass is
  sometimes down: a failed run is worth one retry later, and a run stuck "queued" for an
  hour can be abandoned and started again.
- **The mirrors can be behind.** When the main Overpass server fails, the baker falls back
  to mirrors, and one answered a city centre with older data: 261 fewer footways of 1222,
  23 fewer areas, a few more of other roads, the same day. Re-baking only to change how the
  file is made (`bare_ground`, a margin)? Compare the counts with the last bake (the log
  says which server answered); if the data moved, keep the main server's bake and redo only
  what changed -- the ground grid is the same tiles and the same code whatever answered.
- **Allowing `overpass-api.de` in a cloud environment is not enough**: the proxy lets the
  connection through and the server resets it during the TLS handshake (it turns some
  networks away; its mirrors are other hosts). Go straight to the workflow.
- **A big city whole is too much.** Givatayim (3 km^2) builds in ~6 s on a cloud
  container, a 47 km^2 town in ~15 s, and a city centre is denser than either. For a few
  neighbourhoods of one, give the workflow `bbox` (south,west,north,east in degrees,
  `place` then only its name) -- e.g. read off a screenshot of a map with two landmarks of
  known position for the scale. A box has no boundary: no "welcome to" at the limits, and
  the striped barrier at the map edge is the whole border.
- **The ground heights see the roofs.** The terrain tiles the baker reads are a surface
  model (mostly SRTM): in a city centre a cluster of towers comes out as a hill. One
  centre's grid stood 146 m high under three towers, with slopes of 300%, and the buildings
  round it sat on the hill's flanks. Look at the grid (`height.h`: max, steepest step) before
  driving a new city, and bake one with towers or dense blocks with `--bare-ground` (the
  workflow's `bare_ground`): a grey opening over ~90 m takes out bumps narrower than ~180 m
  and keeps broad hills and valleys (that centre: 0-38 m, steepest 13%). It also lowers a
  real hill's crest a little (one town's 86 -> 72 m), so it is not the default.
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
  (only a cockpit view needs it closer). Two pieces at the *same* height are worse: where two
  streets' pavements meet at a corner (or cross, or a corner's paving runs onto a street's),
  each laid whole, each with its own pattern, the corner flickered between brick and slabs.
  Lay paving once: keep what is down while building and cut each later piece where an
  earlier one already paves, in an order every square of the map repeats.
- **Traffic islands are areas, and areas lie flat.** OSM maps the island at a roundabout's
  mouth, a roundabout's middle and the strip where a divided road's halves part as a grass
  (or paved) area; drawn on the ground like a park, with no kerb where no street laid one, it
  lay level with the asphalt -- "grass patches on the road". An area with road nearly all
  round it is an island: raise it to about kerb height with a kerb face, cut back off every
  road's asphalt, the junctions' asphalt and the paths through it.
- **Bare ground must not look like asphalt.** A grey a shade off the road's, with a photo's
  light and dark over it, read as more road: a boulevard's wide middle strip looked like
  lanes and its lawns like grass painted on them ("grass patches on the road"). Give open
  land its own colour -- dusty sand, dry earth -- clearly apart from the asphalt.

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
  a road had green at one half of a divided road and red 10 m on. Only the ways in from
  outside count: the road between two of the site's own points has no light, and its
  direction, counted, forced a split at skewed junctions (55-65 degrees) that gave
  crossing streets one green. A car is in the site from
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
  bollards, a hydrant -- can stand in a junction's mouth. Check the disc too, and the asphalt
  each rounded corner adds out to its kerb (keep those outlines as the corners are laid:
  bollards a few metres from a zebra near a junction stood there, in front of the kerb), and
  check both ends of anything long (a railing panel), not its middle.
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
  straight back" as a route's start; stop short of the end and turn round there; keep
  traffic out unless there is no other way.
- **Turning round takes moves.** A 4.4 m car on 34 degrees of lock needs ~10 m kerb to kerb
  to come round in one sweep; a cul-de-sac is 6-8 m. Stop ~7 m short of the end (room for
  the first move) and turn as a driver does: forward on full lock until the nose nears the
  far kerb or anything solid, back on the other lock, again until it faces out, then plan
  the way out afresh. Let the bumpers go ~0.6 m over the kerb (the wheels are ~0.9 m in
  from them): held to 0.15 m it took five moves in 6.5 m, at 0.6 three. Turn the wheel
  over standing between moves, give the throttle what the slope takes (reversing up a 17%
  street on the flat's throttle crawled), and turn the rest on the spot if two moves in a
  row get nowhere. Spinning on the spot at the very end, the plain fix, swings the corners
  over the kerb and into what stands there. And brake to a standstill at the stop: speed
  allowed from "distance to the plan's last point" grows again once the point is behind,
  so an AI crawling up to it rolls on past.
- **Roads a metre or two long** sit in OSM junctions (a stub between two carriageways, a
  kink split into its own way). Anything read from "the next two points" -- the way a lane
  goes, which way to face -- can point backwards there. Read directions over a distance
  along the path (5 m), never between two points.
- **A car crossing your path is in it by its nose**, not its middle: one waiting crossways
  at a junction's edge pokes into the turn. Check its ends as well as its middle.
- **Queues at a green**: a follower that keeps its gap for the speed the car in front has
  reached waits until that car is well away -- the third car of a queue moved 9 s after
  the green. Size the gap on the slower of the two speeds, and start each driver's
  reaction when the car in front is really moving (0.5 m/s), not when it has rolled a few
  millimetres (then the whole queue goes at once, like a train).
- **At signalled junctions the lights decide**: giving way by road rank as at an
  unsignalled one makes a car with its green wait for a main-road car about to stop at
  its own red.
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
  (autodrive crawled under a hill at 30 km/h, braking for the houses over its head). The
  builders and the tests too: traffic lights for a way in on a bridge's deck were tried at
  the ground's level, found the road below or the deck's wall at every spot, and never put
  up (stand them on the parapet at the deck's height, and no ground-level post under
  them); a test's "off the asphalt" measured a car on a bridge to the road under it.
- **Cut the ground open** over a cutting (clip the terrain mesh's triangles round its
  footprint) and drop any far-off flat ground plane below the deepest deck, or it shows
  through. Inside a cutting's footprint the ground is never a surface, however shallow:
  switching to it where the cut is 5 cm deep was a step a car hopped off.
- **A bridge's end must be off the bank's slope.** A height grid's triangles bend the ground
  a cell beyond where a dug river channel starts; a bridge ending on that slope has a crest
  just past its end. End it a cell further out. And keep its end away from junctions (20 m
  or so): a car turning in clipped the parapet's start. Where OSM's own bridge way starts at
  a junction (its first metres still at street level), leave the parapet and its wall out of
  the junction's mouth until the deck is half a metre or so up: a car turning out of the side
  street ran into it.
- **Junctions in the air** (a slip road meeting a road up on its embankment): draw the
  junction's middle at its height, open the parapet, its wall and the walkway wherever the
  other road comes in, and let a ramp's walkway give way to the street's asphalt where its
  foot runs into one. Leaving walls out of a junction's corner (so a turning car does not
  clip a kerb-high step) is right at street level only: up on an embankment it is a gap to
  drive off.
- **Working the heights out from OSM** (what worked for one Canadian town's interchanges):
  each bridge must clear what it crosses (a road by ~6.4 m, a path by ~4.4); spread that
  lift along the drivable roads at a ramp's grade, as an absolute height (the ground under
  a ramp can fall away as steeply as the ramp does), through junctions but never onto the
  roads crossed; then cap every lift by what a ramp from the nearest road held on the ground
  can climb, so a short slip road is steep instead of a cliff. Cut roads where their ramp
  meets the ground, never lift footpaths, densify the lifted pieces and round their crests
  (a ramp up meeting a ramp down at the crossing is a crest a car takes off from), and
  treat bridges shorter than ~8 m as culverts. A coarse elevation model (36 m) is smooth
  under an overpass: all the lift has to come from the ramps.
- **Embankments are banks, not walls**, where there is room: a slope ~1.5 out for each
  metre down with a guardrail on top, a retaining wall only where the bank's foot would land
  on another road or in a building. Give the bank's foot a collision line too (a car on the
  ground drove into the slope).
- **Tunnels mirror bridges**: a drivable tunnel way under something lies a full clearance
  down along all of it, cuttings rising back to street level along the roads either side,
  never through a junction; one too short for its cuttings, or under nothing mapped (a
  passage through a building), goes back on the ground. Skip roads that only share an end
  point with it (its own next piece "crossed" it), and hold only what is near a crossing:
  holding whole roads, or searching from every junction in town, is slow and over-holds.
- **A divided road is two decks overlapping at the median** at slightly different heights:
  decide what is under a body by the carriageway it is on first, the nearest height next,
  or it drifts onto the other and falls off its end.
- **A tunnel under a street, and a street over a cutting.** Anything that picks "what is
  under a body" must not take a tunnel's road under a street for what a car on the street
  stands on: ranked by carriageway first (for the divided roads above), the tunnel 7 m down
  won and cars dropped into it. A deck well under ground the body can reach is not what it
  is on (inside the tunnel that ground is out of reach). And where the ground is cut open
  (a cutting), a street at grade crossing it -- across an underpass's mouth, over a
  cutting's shallow top -- must still carry a car: its asphalt counts as ground. Test it
  by sampling every street's asphalt for "what would a car here stand on", not by driving
  the tunnels: the tunnels drove clean while a thousand street points were holes. Sample
  for walls the same way: a cutting's wall where it starts at a street's kerb stopped cars
  on the street, and a bridge's piers -- checked against the lanes below at their middle
  only, while each spans the deck's width -- stood in a motorway's lanes where the bridge
  crossed it at a slant.
- **More tunnel traps, from one city centre**: the other half of a divided road crossing
  the tunnel's line by a metre where the halves close in at a mouth is not "a road over
  it" (it held an underpass up); a short tunnel way under nothing but joining a tunnel
  underground is a branch of it, not a passage (put on the ground, it made the junction a
  street's and held the tunnel up); OSM's ids come out of JSON as floats (see the godot-2d
  skill), so a membership test against your own ints silently never matches.
- **Crests launch cars.** A ramp or cutting that meets the flat at full grade in one point,
  or a hump where a branch climbs out of a tunnel, is a crest a car takes off from at
  30-50 km/h. Ease into the slope over ~30 m (a vertical curve: depth G s^2 / 2L, then
  G (s - L/2)) and round humps. And in the car: a rise under it faster than any slope could
  give at its speed is a step (two decks overlapping at a junction in the air, 0.2-0.3 m
  apart), not a climb -- taken as vertical speed, it threw a car 3 m into the air.
- **Hold the road a bridge crosses along the road, not as the crow flies.** The road under
  a bridge is held at street level for some distance either side of the crossing; measure
  that distance along it. A cloverleaf's link bridge lands on its own loop, which turns
  and passes back under it: by straight-line distance the loop's start (beside the
  crossing, hundreds of metres along the loop) was held down, and the bridge's end with it
  -- 0.5-4 m clear over the roads it crossed.
- **Footbridges and footpath tunnels are a second network.** Work their heights out the same
  way but along the paths only (footway, path, steps, cycleway...), steep (a ramp ~25%,
  stairs ~60% where OSM maps `highway=steps`), and keep the two networks apart both ways: a
  sidewalk or a crossing way shares nodes with the street, so a road bridge's or a
  tunnel's lift leaks onto it (a 6 m dip in a sidewalk, a pavement rising 5 m in 2 m off a
  ramp) unless a path's point that a street has keeps the street's level, and a path's lift
  must never spread onto a street's point (it comes down to the pavement there). A
  footpath tunnel can end under the ground in OSM (the mapper stopped): leave it out. Two
  traps when people walk it: footbridges branch at sharp angles, so a railing checked
  against "another deck comes in here" at its middle alone ran across the way onto the
  next piece -- check walls of narrow decks in short pieces; and OSM fences cross paths
  right at a footbridge's foot -- a body on a deck off the ground should not meet the
  fences and posts down on the ground. A road bridge's piers must keep off paths and off
  any deck below their top (a footbridge alongside, lower, walked into them). A bridge's
  sidewalk mapped as its own way can stop dead on the span: bring a path's dead end down to
  the ground (a stair) rather than leave a ledge. A spiral stair is often one steps way
  lying on itself: keep a way that comes within ~0.8 m of itself on the ground (not
  1.5 m: an access ramp's hairpin legs are about a path's width apart). Walk every
  footbridge and tunnel end to end in a test, steered along the path: the counts of a
  push-back label lie (placing people relabels "last hit" every tick), so measure the
  displacement that was not the walker's own step.
- **Water held at its own level** (a river between weirs) is drawn at that level and is too
  deep to drive into; gentle banks otherwise let a car down to drive along the bed under
  the water. Leave lakes that lie at their shore's lowest point alone: a road over an
  inlet runs on ground below their level.

## Railways

The baker keeps them (`rails`, `platforms`, `stations`; a file baked before has none).
- **Each track is its own OSM way**: a double track is two lines, a station's throat a
  fan of them with crossovers between. Tracks that join share an OSM node, so their end
  points are equal exactly: join them end to end by that, taking the straightest way on
  (a crossover's leg, sharply off, is not "on"), sidings and yards left out, to get the
  long runs a train can follow.
- **Leave out what is underground**: a city's metro or light rail is often all tunnel
  (its stations too: keep only stations near a surface track).
- **Keep the city's builders off the tracks**: open land's planted trees grew on them
  (add the beds to whatever says "nothing grows here"), a bridge's piers stood on them
  (check a pier against the tracks as against the lanes below), and a bed's slope came up
  through the asphalt of a road running close alongside (pull the bed's foot in there).
- **Give the ballast its own colour**, darker than bare ground: in the pale colour of the
  ground between a motorway's carriageways the bed vanished from beside the line.

## The edge of the map

The baked area ends; don't let it end in an invisible wall. A striped barrier along it
(following the ground), a soft glow over it that shows when near, a line on the minimap,
a banner on contact -- and keep the car's own collision circles off exactly that line.
An AI that picks its way at junctions must see the edge coming: a street that runs off the
map looks like any other until the barrier. Look a few hundred metres down each way on and
score down one whose every continuation hits the edge (not ordinary dead ends -- exploring
those is fine), and end a planned road a few metres short of the barrier as a dead end.

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
- **`tools/gpx_route.py`** does the GPS side: `report` lays the track on the city file and
  gives the streets in order with their speeds (mean, 85th percentile, top), speed by road
  kind, every stop with the junction it was at (and whether it has lights), the hardest
  acceleration and braking -- for a drive, what to tune AI drivers against. `route` gives
  `{"points": [[seconds, x, z]...]}` timed to the film (`--video` reads its clock) and cut
  between two named corners (`--from A B --to C D`), for a replay beside the film.
  A phone's GPS puts a walker in the road on a narrow street: before a route becomes a
  replay, move each point onto the pavement it was walked on (left or right of the way
  walked, along a named street) using the game's own road widths, not OSM's -- a game that
  fits widths to the buildings has narrower roads than the file -- and leave the crossings
  as they are. Mid-street the points moved 0-2.5 m; at a big junction 10-18 m and onto the
  asphalt, so the replay ended 25 m short of it.
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
  `tools/osm_city.py`, origin from the city file), cut stills every ~10 s and at the stops
  (`ffmpeg -ss <t> -i v.mp4 -frames:v 1` was right on the phone's own file; on a re-encoded
  clip decode instead, see below), label each with the nearest street, then stand
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

Without a GPS track, or when the session cannot reach Drive:

The fastest way to see what is wrong with a street is the user filming it on a phone and
the game walking the same route in first person beside it.

- **Getting footage in without opening the network.** The connectors cap downloads at
  about 10-12 MB, OneDrive's will not hand over a video at all, and a phone's 3-minute video is ~350 MB (emailed, it turns
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
- **A street of shops that OSM calls residential.** OSM tags a road by its traffic, not by
  what lines it: a filmed street with shops down both sides was "residential", so the game
  gave it front gardens with walls and hedges where the film had shopfronts on the pavement.
  And OSM knew six of its businesses; panning the camera across the street in the film
  showed a row. Decide gardens piece by piece (a shop behind it, or a hand-placed row of
  shopfronts), not by the road's tag or the whole street: the same street had one real
  garden between its shops.
- **Panning in the film is how the shops get counted.** Ask the walker to turn the phone to
  each side now and then: the shops across the road, which a forward-facing film never
  shows, came only from those pans.
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

A filmed walk or drive very often starts or ends at the user's door, and a GPS track
recorded "just to test" at home is their address to a few metres. Keep the video, the GPX,
the stills and the projected route in the scratch directory; commit what was learned (a
fence, a kerb colour, a walking speed), and trim any route that goes into the game back to
public corners. Ask where it started if it is not obvious.
