# streets

Drive a real city. The player's words:

> I want to drive (1st person / 3rd person) in a city, literally from reality. Starting
> with my own, Givatayim.

> Lets try to make a small one. Just with driving. With the real buildings (!?), at least
> the structure or locations maybe. And I want to think about all of it as a repeatable
> process for other locations and cities. And maybe later even not just driving.

> The gameplay of picking up in a taxi is meh. Lets focus on the free driving (maybe later
> other cars and actual proper driving signs, lights and so on). Lets start with "chase"
> cam. I want it to be closer to a simulation than a game at first, but we can add some
> game features just to be aligned with the platform.

## What is it called?

streets

## Who are you?

Someone driving an ordinary car through their own town, on a sunny day, seen from just
behind and above the car (a chase cam that swings out a little on the turns and pulls in
rather than sit inside a wall) -- or from the driver's seat (the "seat" button, or C):
the dashboard, a steering wheel that turns with the front wheels, a speedometer and rev
counter seen through the top of it, the pillars and the mirror, the eyes leading a little
into the turns.

> First-person / bonnet camera.

**On foot.** Stop, and the "walk" button (or F) lets the driver out of the door to walk the
same city: arrows or the stick to walk and turn, space to run, over the shoulder or (the
"seat" button) from the eyes. The car idles where it was left and traffic goes round it;
traffic stops for you on the road; walls, trees and passing cars push you aside; the
minimap marks the car. Back at it, "drive" gets you in.

> Walk mode: get out of the car and walk the same city.

## What do you do?

Drive, freely. The car behaves like a car rather than a toy: about 4 m/s² off the line,
150 km/h flat out, firm brakes, steering that gets gentler with speed, tyres that let go
if you take a corner too fast (it runs wide), body roll and nose dive. Hold the brake when
stopped and it goes into reverse, like an automatic.

The car's switches, on screen (top right) and on the keyboard: indicators (Q and E) that
tick and go off by themselves after the turn, the horn (H: people on a crossing hurry, a
car stuck in a standoff ahead goes), headlights (L; on by themselves at night), and
reverse lights when backing. Autodrive signals its own turns.

> Indicators, horn, headlights, speedometer.

Keys: up = gas, down = brake (and reverse), left/right = steer. Space switches on
**autodrive**, which drives the streets by itself in the right-hand lane, slows for
corners and keeps the speed limit (50 in town, side streets included; 60-70 on Bedford's
main roads outside it; 80-90 on the highways).
Shift takes the wheel back. On a phone there is one circle, fixed in the lower right:
hold it and drag -- up is gas, down is brake (and reverse once stopped), sideways steers,
and the further from the centre the more you get. Let go and it centres. Grabbing it
takes the wheel back from autodrive; tap "autodrive" to hand it over.

> The controls on mobile are a bit annoying. Especially the whole wheel, brake, gas.
> Maybe one circle control for mobile.

> The circle keeps moving. Can't drive like that. Make it a static circle, somewhere on
> the right side.

**Driving assist** (on by default, the "assist" button): while you roughly follow a street
it eases the car toward the street's direction and the middle of your lane, letting go
the moment you steer harder than a nudge, and it brakes for something solid right in
front at speed.

> The driving is a bit hard if I'm driving alone. I'm wondering how to make the feeling
> smoother. Some of it is a skill issue but I want to help a bit. We get stuck in
> buildings and trees a lot.

**Getting unstuck.** Scrape along a wall at an angle and the car slides on, losing speed
in proportion to how hard it hit; head-on stops it. Nose against something, hold brake
and it goes straight into reverse. And if a pedal is down against something and the car
gets nowhere for over a second (wedged on a tree, rocking between two parked cars) it is
put back in the nearest lane, clear of parked cars: "back on the road". Assist or not.

> Sometimes I get stuck too hard, and it's hard to unstick from walls or trees.

**Choosing the way.** While autodrive is driving (and not to an address), each real
crossing ahead -- two or more proper streets on, not driveways -- puts its choices at the
top of the screen about five seconds before it: an arrow per way with the street's name
and a bar running down. Tap one (or press left / up / right). Leave it and autodrive takes
its own pick, mostly straight on and preferring streets you have not driven yet.

> I want another mode of driving, where an option appears at every crossing a few seconds
> before, and I can pick the action. If I don't choose, a random one or it just keeps
> driving.

**Going somewhere.** "go to…" opens a list of the city's streets (type in the box to
filter, in Hebrew or English, or scroll), then that street's house numbers, or "anywhere"
on it. Autodrive takes the shortest legal way there (one-way streets respected), a beacon
stands over the address, the minimap shows the route and the line above the buttons
counts down the distance. It stops at the kerb in front: "arrived". Steer yourself and the
destination stays; autodrive picks the route up again from wherever you are.

> I also want that I will be able to pick an address of destination and it will drive
> there.

Only addresses OpenStreetMap knows are listed: in Givatayim that is about one building in
six (plus address points), in Bedford almost all of them.

**Jumping there.** The button at the top left of the list switches it between "drive
there" and "jump there". Jumping puts the car down on the street at the address, in its
lane, stopped, facing the way that has the address on the kerb side.

> Besides go to, I want also jump to. It teleports there, instead of driving.

**Places.** Entering the game asks where: Givatayim; Bedford, Nova Scotia; or Ashdod
(starting at Sderot Herzl and HeHalutzim, its busiest corner for shops). Each place is one
entry in `LEVELS` at the top of `streets.gd` (name, city file, starting corner). Ashdod is
three times Givatayim's size and takes longer to load (about 10 s here).

> Lets make a menu where I pick a place we have. Starting with Givatayim. Can we add
> Bedford, Nova Scotia.

> Ashdod.

The minimap (bottom left) shows the real streets and buildings round you, heading up, with
the city limits in pink. The name of the street you are on is at the top, in Hebrew with
the English name under it when OSM has one.

## What is trying to stop you?

Nothing yet, on purpose: this is a driving sim first. Buildings, trees, parked cars and
traffic-light poles are solid. Crashes are a bit more game than real: a thud and a shake,
the car bounces back off what it hit and spins if it was hit off-centre, and a hard one
throws it into a little hop. Too fast over a crest or off a ramp and it leaves the ground
for a moment and lands with a bump.

> I want the car to be able to "jump" a bit if I drive too fast on slopes. Maybe making
> the crashes more bouncy as well... slightly less realistic, more "game"-like.

**Traffic.** About twenty cars drive the real streets round you, in their lane, mostly on
the main roads: they slow for corners, keep their distance (brake lights on), stop at red
lights (and on amber when there is room), come to a full stop at stop signs and slow for
give-way signs. At a junction without lights the rules are the real ones, roughly: on a
roundabout's ring you go and coming onto it you give way; the main road goes before the
side street; between equals whoever gets there first, and a car turning across gives way
to one going straight on. You always have the right of way. A car kept waiting too long
creeps through, so a jam cannot lock for good. Hitting one is a crash like any other.
They are not a physics simulation: each follows its lane at its own speed (`traffic.gd`).

Not just cars: a couple of city buses (in the blue and green of Givatayim's companies,
white in Bedford) keep to the main roads and pull in to the kerb at each bus stop on their
side to stand a while; taxis carry the lit roof sign; scooters with their riders squeeze
between two lanes past a queue. On a road with more than one lane each way, cars pick a
lane, pull out to pass a slower car when the lane beside is clear, drift back right, and
get into the right lane for the turn ahead (right lane to turn right, left to turn left).

People wait at the zebra crossings and step out once whatever is coming can still stop;
traffic and autodrive stop for anyone on a crossing. Drive at someone crossing and they
hurry back to the kerb, and the game says so, like a red light.

> More kinds of traffic (buses that stop at the stops, taxis, motorbikes weaving); people
> crossing at zebras; multi-lane traffic that changes lanes and turns from the right lane.

> Cars get really stuck at crossroads, they are struggling giving way and hitting each
> other, as well in roundabouts.

**Lights and signs mean something.** Autodrive stops at red lights and stop signs and
keeps behind the car in front. Drive through a red light, or a stop sign without
stopping, and it says so. The stop and give-way signs are OSM's (Givatayim has a few
dozen mapped, Bedford more); the lights run their own cycle, east-west streets then
north-south. OSM often maps a light on one approach of a junction only; the game gives
that junction lights on every way in.

**Signs and paint.** A stop line across the lane at every light and stop sign, STOP
painted before a stop sign (עצור in Givatayim), SLOW (האט) before a crossing near a
school, speed limit signs a little after each junction on the main roads (round and
red-rimmed in Givatayim, a white MAXIMUM board in Bedford). Bedford's centre lines are
yellow, as in Nova Scotia: a solid double line on main roads, dashed on side streets,
with white edge lines.

Every street has the signs a real one has: a green name plate at the corners (רח' and the
Hebrew name over the English in Givatayim, the name alone in Bedford), a blue roundabout
sign on every way into one, a blue crossing sign on both sides of each zebra (and in
Givatayim on the traffic-light poles too), a P at car parks, no entry at the wrong end of
a one-way street and the blue one-way arrow at its corner, "turn this way" where only one
way out is allowed, and "keep right" where a street splits round an island. Givatayim's
stop sign is the Israeli one, the red octagon with the white hand; Bedford's says STOP.
Painted arrows in the lanes before the junctions of the main roads show the ways out.

> We didn't add the road signs? (slow, turn, roundabout, parking, the street name, turn
> or straight arrows on the road itself, on the lights)

> More road marks and signs (speed, slow, stop...). Cars slightly prettier.

Parked cars and traffic are a mix of sedans, hatchbacks, SUVs and the odd van, with door
seams, handles and wheel arches, in the colours real cars come in: mostly white, silver,
grey and black, with the odd red or blue. Parked cars tilt with the slope they stand on.

**Trees.** A dozen kinds, picked by the place and where they stand: ficus, acacia, olive,
cypress, pine and date and fan palms in Givatayim; maple, oak, birch and spruce in Bedford.
Each tree varies in size, lean and shade, and crowns are clumps, not one ball.

> More variety for the trees? They seem all bland and the same.

> Traffic, lights and signs that mean something, engine sound, night.

**Sound.** The engine is made in the game, not recorded: a four-cylinder's firing pulses
pitched by the revs of a five-speed automatic, a brighter layer with the throttle, and
the nearest car going by.

**Night.** The "night" button: a dark sky and a dim moon, a share of the windows lit (warm
in homes, cooler in offices), street lamps on with a pool of light under each, shop
windows bright, headlights with their beams on the road, tail lights glowing.

> More realistic structure of homes. More realistic structure of landmarks (shops, malls,
> parks).

**Homes.** Givatayim's blocks have a parapet round the flat roof, one or two stacks of
balconies up the street side, AC units on the walls, a canopy over the entrance with the
lit blue house-number plate beside it, and about a third of the mid-rise blocks stand on
columns ("komat amudim"), the ground floor open round a walled-in stairwell. Bedford's
houses have clapboard siding, white-framed windows, a porch on the street side and often a
chimney. Which block gets what is chosen from its outline, so it is the same every time.
A roof OSM puts on stilts (a petrol station canopy, a carport) stands on columns with a
flat roof; it was getting a house's pitched roof, and flew.

Walls are mostly white, cream and beige stone, with some blocks in yellow, peach, a pastel
or grey render (Bedford's clapboard comes in more colours); glass towers are blue, green
or silver. A third of Givatayim's balconies are closed in the Israeli way, glass above the
parapet and a roller shutter part-way down it. Shops vary: dark, white, cream or coloured
sign boards, an awning or none, now and then one shut behind its shutter.

> More varied buildings: plaster colours, glass towers, shopfront variety, shutters on
> balconies.

**Landmarks.** A big named building (a mall, a tower, the cinema, a school) has its name
in large letters along the top of its street side; a mall has glass shopfronts all along
the ground floor and a canopy on columns over the way in. Parks have benches along their
paths, low park lamps, trees where OSM has few, and a playground (slide tower, swings,
sandpit, soft floor) in the bigger ones. Sports pitches have their lines and goals or
basketball hoops. Bedford's woods are filled with trees, mostly conifers.

**Open ground and people.** Bare land is patched with grass, earth and scrub (a shader,
nothing more to draw), with copses and lone trees where it is green, mostly in Bedford.
People turn up in proportion to the life round them -- homes, shops, cafes -- so a town
street is busy and a verge out by the highway is nearly empty.

> Some places feel empty, let's make it a bit more lively without the cost being too
> harsh. The density of people should be somewhat correlated to the houses and
> landmarks; in the middle of nowhere, probably less people.

**Street furniture** (`furniture.gd`).
- **Power lines** run down one side of about half of Givatayim's streets and most of
  Bedford's, three wires sagging from pole to pole with a transformer every so often.
  Givatayim's poles are concrete. Bedford's are wood, with a phone cable lower down and
  the street lamps on arms off them.
- **Lamps.** Givatayim's main roads have ornate dark-green lamps, a curved arm and a
  lantern. Where a main road is split into two carriageways there is a double one down
  the middle, and each lamp has an Israeli flag on a staff.
- **Flags.** Flags hang off balconies here and there, and every school has a flagpole
  (Israel's or Canada's). All the flags wave.
- **Bus stops** have a curved blue roof (grey in Bedford), a lit ad panel at the end and
  the yellow bus sign on its pole.
- **Ads.** The main roads have lit ad columns on the pavement, and the faster roads have
  big billboards where there is room. The ads are made up, and they glow at night.
- **Fences and hedges.** Sports pitches (and schoolyards, once the bake has them) are
  fenced with tall green mesh. Park edges along a street get a hedge or, in Givatayim, a
  low white railing. The fences and hedges OSM maps go in too, once the city is
  re-baked.
- **Outside shops, cafes and schools** there are bike racks, often with bikes in them,
  and in Givatayim a few scooters parked nose to the kerb.

> Some more photos for ideas: flags, power lines, better street lamps, bus stops,
> billboards, fences and hedges, bike racks, cafe tables, scooters.

**Kerbs and corners.** Pavements run unbroken along a street and are cut only at real
junctions, where each corner gets a rounded kerb (red and white in Givatayim: no stopping
there) with its pavement behind it and the asphalt filled out to it; across the mouth of a
T the far kerb runs straight. A divided road (OSM: two one-way roads side by side) has
each half as wide as its lanes, not the class's guessed width, so the halves no longer
overlap, and between them a kerbed median instead of two pavements. No kerb or pavement
is laid where it would lie on another road's asphalt, which also leaves a driveway its gap.

> There are a lot of broken roads and random sidewalks in the middle. And in general very
> badly looking crossroads.

**Roads that fit.** A road's width is mostly a guess (OSM rarely says), so where a street's
buildings stand closer than the guess it is narrowed (to no less than two lanes) instead of
running under them. The ground's thin layers -- grass, paths, asphalt, paint -- sit a few
centimetres apart and the camera's near plane is a little way out, so a phone's coarser
depth buffer no longer shows grass through the road in green patches.

**Turning, lanes, roundabouts.** A turn starts just short of the junction in the lane the car
is in and comes out just past it in the right lane of the new street (the plan used to run
straight from the junction to the new street's next point, down its wrong side). Cars keep
a little further from the centre line; parked cars stand mostly up on the pavement. On a
roundabout a car decides at each exit and is ever less likely to stay on, so nobody
circles and the cars waiting to come on are let in.

**Autodrive** stops for anyone standing on its lane, keeps out of alleys and car-park lanes
unless there is no other way, prefers turnings back into town at its edge, and if it has
got nowhere for 40 s (not at a light) it is lifted onto a street a little way toward the
middle of town and drives on.

**Car parks.** OSM's parking areas (up to a block's size) are laid out in rows of painted
bays with most of them taken; a car park mapped only by its lanes (OSM: a parking aisle,
as most blocks' own lots are) gets a row of bays down each side of each lane.

**Surfaces.** The merged ground isn't one flat colour: grass is mottled with drier patches,
asphalt has a grain and worn patches, pavements and plazas are laid in slabs -- all worked
out per pixel from where it is, nothing to load, the fine part fading out with distance.

> Green patches on the road; buildings halfway into the streets; turning too deep into
> the opposite lane; cars too close to the centre; parked cars too far into the road;
> parking lots for blocks of buildings; autodrive stuck at the edge or driving into
> buildings; roundabouts where cars get stuck or circle; autodrive not stopping for
> people; some non-flat texture on big empty grey or green areas.

**Real textures.** Up close the surfaces are photographs (free CC0 ones from Poly Haven, in
`textures/`): the asphalt has grit and fine cracks, with a second photo of tyre marks,
patches and long cracks laid over it at 30 m so it doesn't visibly repeat; Givatayim's and Ashdod's
pavements are rows of concrete pavers, Bedford's poured concrete slabs; grass and open
ground are a real lawn; walls are painted render. Each has its bumps, so the low sun picks
out the cracks and the joints between pavers. The palette still decides every colour: a
photo only adds the variation round its own average, so `/look` reskins it as before.
Walls are a little darker at the foot, and a faint streak of grime runs down from each
window sill.

> What would it take to make it more realistic, closer to Unreal and Unity quality of
> details and resolution?

> Let's start with the textures.

## Smooth on a laptop and a phone

> It's pretty choppy and laggy now. I'm trying on a laptop browser.

A browser draws through WebGL, much slower than a desktop game, so the city is cut into
squares that are only drawn when on screen and near enough (kerbs and road markings to
about 260 m, trees 550 m, buildings 1100 m, people 90 m), shadows cover only the street
round the car, and the car and camera are drawn between physics ticks so they glide
however fast the screen redraws. In a browser the game also watches its own frame rate:
under 55 frames a second, or stuttering (more than one frame in twelve slower than 25 ms),
for a few seconds and it steps down a level -- first smoother edges (MSAA) off and
shorter shadows, then no shadows and a lower 3D resolution and the photo textures off
(back to the drawn grain). It never steps back up during
a drive. The frame rate and the level are shown small under the speed. Parked cars and
traffic are one mesh per car shape (a batch of them costs one draw, not six); every kind
of shader is drawn once while the city loads, so none of them stalls the first time it
comes into view; the browser's shadow map is smaller and its filter cheaper.

The small things a street is made of -- sign plates and their poles, lamp and power
poles, racks, benches, balconies -- and the flat layers under them (asphalt, paint, paths,
grass, pavement) are merged, while the city loads, into one mesh per 400 m square and draw
range, all with one material: a vertex carries its colour, or the number of a palette tone
looked up in a table the material holds (so `/look` still reskins them). That took a
view from about 425 draw calls to 290 in Givatayim and from 515 to 385 in Ashdod. What
changes at night or moves stays separate (lamps, lit glass, flags, ads, cars, people), and
so do the trees, which are too many to copy.

> Performance pass: fewer draw calls, faster loading of big cities.

## How do you win?

There is no winning. The one game hook: every street of the city you drive down for the
first time (30 m along it) scores a point. "streets 12 / 143" in the corner counts how
much of the city you have seen.

## What should it look like?

The real place, recognisably: the street layout, building footprints and heights, parks,
trees and traffic lights where they really are. Daylight, cream apartment blocks with a
window per storey, tree-lined streets, white dashed lines, zebra crossings. Every colour
is a palette role mixed for daylight, so `/look` still reskins it.

## Where the city comes from: a repeatable process

Nothing about a city is in the code. A city is one JSON file in `cities/`, baked from
OpenStreetMap by `tools/osm_city.py`. The easy way to add one needs no network of your
own: on GitHub, Actions -> "bake a real city" -> Run workflow, with the place
(`Ramat Gan`, `רמת גן`...) and `out` = `game/streets/cities/ramat_gan.json`. It bakes on
GitHub's machines and commits the file (and, run on main, re-publishes the web build).
Givatayim was made that way. Or locally:

```bash
python3 tools/osm_city.py --place "Ramat Gan" --out game/streets/cities/ramat_gan.json
```

Then add a line for it to `LEVELS` at the top of `streets.gd`. `--place` takes the name of an administrative area as OSM
spells it (any language; "Givatayim" finds "Giv'atayim"); `--relation <id>` pins an exact
one, `--bbox s,w,n,e` takes any rectangle. It keeps `--margin` metres (250 by default) of
the neighbouring towns round the edge so the world does not stop at the city limits. The
raw download is cached in `tools/.cache/` (not committed), and `--offline` re-bakes from
it, so changing the bake does not hit the server again.

If a place's city file is not there yet, the game drives whichever city file is.

Locally, the network needs to reach an Overpass server (the tool tries
`overpass-api.de`, then two mirrors); without that, `--print-query` prints a link to
open in a browser and `--from-file` bakes what it saved. Everything baked is © OpenStreetMap
contributors under the ODbL, which is why the credit sits on screen.

### What is real and what is guessed

- **Real**: every road's path, kind, width (or lanes), one-way direction and name; every
  building outline; heights and floors where OSM has them; parks, grass, water, car
  parks; mapped trees; traffic lights and zebra crossings; the city boundary. The hills:
  the ground follows an open elevation model (AWS terrain tiles), baked in with the city.
  Shops, cafes and bus stops stand where OSM puts them, under their real names.
- **Guessed**: a building with no height gets 4 storeys (by type: houses 2, garages 1,
  offices 5...), varied a storey up or down so a street is not one flat wall. A road with
  no width tag gets one by kind (residential 8 m, room for a parked row each side).
  The rows of street trees along residential streets are added, not mapped. The window
  grid is a pattern, not the real facade. The traffic lights run their own simple cycle.
  What a shop looks like (awning, tables, the bus shelter) is generic. The parked cars
  (about a quarter of the kerb), the people walking and sitting at cafe tables, rooftop
  solar heaters and rooms (Givatayim), pitched roofs on small houses (Bedford).
- **Not there yet**: bridges and tunnels as such: roads at different levels are drawn
  on the ground, and tunnels are dropped (an interchange is flat; motorways and their slip
  roads at least have no pavements or people along them). People crossing anywhere but a
  zebra.

To make your own street more accurate, fix it on openstreetmap.org (building heights are
the most useful thing to add) and bake again.

## Later (said, not built)

- Bridges and tunnels: roads at different levels, an interchange you drive over and
  under.
- Faster loading of a big city (Ashdod takes about 10 s here, mostly roads, kerbs and
  trees), e.g. by building the far parts after the drive starts.
- Not just driving: the same baked city could be walked, or used by another game.
