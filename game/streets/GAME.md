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

**On foot.** The "walk" button (or F) lets the driver out of the door to walk the same city:
arrows or the stick to walk (a brisk 2.1 m/s) and turn, space to run (6 m/s), over the
shoulder or (the "seat" button) from the eyes. Out of a moving car you jump: you tumble
out of the door with the car's speed, roll and get up, and the empty car rolls on by
itself, slowing, until it stops or hits something. Traffic goes round the car; traffic
stops for you on the road; walls, fences, trees and passing cars push you aside; the
minimap marks the car. Back at it, "drive" gets you in (still rolling, it rolls on with
you).

> Walk mode: get out of the car and walk the same city.

> I want to walk a bit faster when I'm out of the car, now it's too slow. I want to be able
> to start walking also when I'm driving. The car will just continue and I'll pop off.

## What do you do?

Drive, freely. The car behaves like a car rather than a toy: about 4 m/s² off the line,
150 km/h flat out, firm brakes, steering that gets gentler with speed, tyres that let go
if you take a corner too fast (it runs wide), body roll and nose dive. Hold the brake when
stopped and it goes into reverse, like an automatic.

The car's switches: headlights (on screen, top right, and L; on by themselves at night),
and on the keyboard only, indicators (Q and E) that tick and go off by themselves after the
turn and the horn (H: people on a crossing hurry, a car stuck in a standoff ahead goes);
reverse lights when backing. Autodrive signals its own turns, an arrow blinking by the
speed.

> Indicators, horn, headlights, speedometer.

> Remove the honk and turn lights UI, it's not needed.

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
its own pick, mostly straight on and preferring streets you have not driven yet. A big
junction mapped as several points -- a divided road meets a street at one point per half,
two divided roads at four -- asks once, with every way out of the whole junction, and
drives across it without asking again.

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
three times Givatayim's size; it takes longer to build in full, but you are driving in
about 3 s here, the same as anywhere (see "Loading near-first").

> Lets make a menu where I pick a place we have. Starting with Givatayim. Can we add
> Bedford, Nova Scotia.

> Ashdod.

**The test town.** The last place, Kiryat Dimyon, is made up (`cities/dimyon.json`, from
`tools/fake_city.py`): one neighbourhood about 1.3 x 1 km, a fifth of Givatayim's buildings,
so it loads in about a second and a half. It is for looking at a change quickly, so it has
one of everything a real town has: a divided boulevard with a big signalled junction, a main
street and a shopping street lined with shops and cafes, a grid of side streets with a
one-way pair, a hill whose streets climb at 10-12% round and up to a water tower, two
roundabouts, a living street, cul-de-sacs, car parks, bus stops, zebras and signs; a strip
mall, a glass office tower, a hotel, the town hall on its square, a cinema, a school, a
sports centre, a park with a pond, villas and woods in the foothills. Mountains ring it, and
past the foothills they are too steep to drive up (see below), so it is a valley you cannot
leave -- except by the one road that climbs the western mountainside to a lookout terrace
with a car park and a cafe. The car starts on HaNasi just past HaShuk, in the middle.

> I want to make a new fake city in streets, where we would do quicker simulation and
> validations. Yes it would not stress as the big cities on latency, but would give a quick
> look if something got prettier as we are trying to make things more realistic slowly.

> Lets also make that fake city surrounded by some unpassable terrain like a mountain. It
> shouldn't be too small, like a regular neighborhood where you have most of the features
> and variety (cars, buses, buildings, types of cars, slopes, landmark and so on).

The minimap (bottom left) shows the real streets and buildings round you, heading up, with
the city limits in pink. The name of the street you are on is at the top, in Hebrew with
the English name under it when OSM has one.

## What is trying to stop you?

Nothing yet, on purpose: this is a driving sim first. Buildings, trees, parked cars,
traffic-light poles, fences, railings, hedges, the low garden walls, bus shelters and the
columns under raised buildings and canopies are solid. Crashes are like real ones: the car
stops at what it hit with a jolt of the camera and a bang, rebounds only a little (it
crumples), and turns a little if it was hit off-centre -- no hop, no spinning like a top.
(They were made bouncier and game-like once, and asked back.) Too fast over a crest or off
a ramp and it leaves the ground for a moment and lands with a bump.

**Ground too steep to climb** -- steeper than 62%, about 32 degrees -- is as solid as a
wall, on foot too, and assist brakes for it; a road is always drivable however steep. No
real town here has any (Givatayim's steepest is 52%), so it only matters in the test
town's mountains. Ground that steep is drawn as bare rock, in bands.

> I want the car to be able to "jump" a bit if I drive too fast on slopes. Maybe making
> the crashes more bouncy as well... slightly less realistic, more "game"-like.

> I want the interactions back a bit more realistic (less bouncy, more like real crashes).
> There are also a lot of things without collision, like fences and some parts of buildings.

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

The buses are real buses now -- a rounded box with a band of windows and its pillars, a
big windscreen under the lit route sign, glazed doors on the kerb side, the air
conditioning on the roof; a scooter's rider sits it properly, arms bent to the bars and
knees up, in a helmet with a visor; now and then a delivery truck goes by, a cab with a
tall white box. Every moving car has its driver, and about a third a passenger, seen
through the glass (head and shoulders, as they would be from wherever you look); parked
cars are empty. You can be seen in yours, until you get out.

People wait at the zebra crossings and step out once whatever is coming can still stop;
traffic and autodrive stop for anyone on a crossing. Drive at someone crossing and they
hurry back to the kerb, and the game says so, like a red light. On a divided road they
cross both halves, outer kerb to outer kerb. People walking along the street keep to the
back half of the pavement (the parked cars stand on the front of it), only on the outer
side of a divided road, and off any stretch where the pavement line would run over another
road -- a service lane or car-park lane alongside, the next street at a corner -- though
they step across a driveway's mouth. Their feet are on the pavement's top (on the asphalt
while crossing, on the ground in a park), not the bare ground's height a kerb below it,
where they waded into the slabs.

> People walk a bit inside the ground.

People appear, leave and change places only where nobody would see it: beyond the distance
people are drawn at, or behind you. (They popped up at the kerb in front of the car, and
the ones at cafe tables jumped from table to table as you drove.) They turn over a moment
at the end of a block and round a bend, step up and down kerbs, and step aside from a car
on the pavement rather than leap. At a crossing by a junction with lights they go with
the lights: only while the road's cars have red, and only with time enough left to get
across, so cars through the junction no longer stop in the middle of it for them.

> The movement of the people: they bounce, jump, teleport and so on. They also don't cross
> the roads according to the lights, so in many crossroads we have to stop for them in the
> middle.

The people are grown-ups, not the kit's chunky cartoons: smaller heads, hands and feet,
longer legs and a longer middle (scaled on their skeletons after every animation frame),
at the height asked for. Faces are a deeper shade of the skin, not big white eyes. Skin
runs light to dark; hair is mostly dark and brown, with the odd fair, red or grey head;
shirts and trousers are each picked from a natural range, so no two in a street match.
That goes for you on foot too.

> More kinds of traffic (buses that stop at the stops, taxis, motorbikes weaving); people
> crossing at zebras; multi-lane traffic that changes lanes and turns from the right lane.

> Cars get really stuck at crossroads, they are struggling giving way and hitting each
> other, as well in roundabouts.

**Lights and signs mean something.** Autodrive stops at red lights and stop signs and
keeps behind the car in front. Drive through a red light, or a stop sign without
stopping, and it says so -- judged as the car's nose crosses the stop line, by the way it
came in (a car in on the last of the amber was told it ran the red). The stop and give-way
signs are OSM's (Givatayim has a few dozen mapped, Bedford more); the lights run their own
cycle. In the Israeli towns they go as they do there: green, three flashes of green, amber,
red, red and amber together, green. In Bedford: green, amber, red. Between one way's amber
and the other's green, 3-3.5 s for the junction to clear. A car that can still stop on amber
stops; one too close goes (traffic used to cruise on until it could not stop, often late in
the amber, and cross on red).

A junction is one junction however OSM draws it. Where a divided road meets a street it is
two points 10-30 m apart, where two divided roads cross it is four; the whole knot is one
set of lights, and a car that has come in on its green goes through all of it. Its ways in
take turns in two groups by direction -- along its main road, then across it -- the same at
every point of the knot. (Each point used to choose by street names: a street that changes
its name at the junction had green together with the street across it, and a car given
green at one half of a divided road met red at the other half 10 m on and drove through it,
with the lamps there showing red.) Two junctions a short way apart give the road between
them the same turn, so a green at one is not a red 30 m on. OSM often maps a light on one
approach only, sometimes 30 m out; the junction gets lights on every way in from outside,
and cars stop at its line, not at the mapped point (they stopped 30 m short, where no pole
stood). Where the usual corner is a wall or a driveway, the pole stands further back, or on
a divided road's median. The lamps are real red, amber and green, red at the top, whatever
the palette, and dark when out. Cars stop with their front at the stop line -- a bus stopped
by its middle stood across the junction -- and read the light for the way they come in, not
the way they are turning; autodrive sees the light on a turn too (it looked only where its
lane passed over the junction's point, which a turn curves past, and drove through reds).
Where a zebra crosses the way in by the junction the stop line is
behind it (cars waiting at the red stood on the zebra). A car with the green no longer waits
for one standing at the red across the junction.

At a zebra by a junction with lights there are walk lights on both kerbs, the red man over
the green man, in step: green while the road being crossed is held at red and the other way
has its steady green; the red man comes on with that way's flashing green. Both ways along a
road share a light, so the green man never shows while cars come one way (in Givatayim it
did at one zebra in nine). People there step out on the green man only, when there
is time to be over before the cars across get their green.

> The whole logic of lights and how cars and autodrive go, something is fishy. Let's make
> the colours clear: red on the top (no go), yellow, green. Maybe add those for people too,
> matching the lights -- that's how it usually works here, so they don't just cross randomly.

> Buses get stuck in the middle of roads when it's red for them.

> Some crossroads I think are wrong in how they work: the colours, the switching, the AI and
> autodrive, maybe also not matching the pedestrian lights sometimes. Something not moving
> properly.

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
a one-way street (where its traffic comes out: it stood at the end you may drive in by,
and autodrive drove in under it) and the blue one-way arrow at its corner, "turn this way"
where only one way out is allowed (not at one point of a junction drawn as several), and
"keep right" where a street splits round an island. Givatayim's
stop sign is the Israeli one, the red octagon with the white hand; Bedford's says STOP.
Painted arrows in the lanes before the junctions of the main roads show the ways out.

> We didn't add the road signs? (slow, turn, roundabout, parking, the street name, turn
> or straight arrows on the road itself, on the lights)

> More road marks and signs (speed, slow, stop...). Cars slightly prettier.

Parked cars and traffic are a mix of sedans, hatchbacks, SUVs and the odd van, with door
seams, handles and wheel arches, in the colours real cars come in: mostly white, silver,
grey and black, with the odd red or blue. Parked cars tilt with the slope they stand on.

> Let's move to cars.

Every car -- yours, the traffic, the parked ones -- has a real car's body now, not a
box: rounded at the shoulders, the bonnet and the boot and at its four corners, a cabin
that narrows to the roof with its pillars and roof rail in the car's colour, the light
rolling over it. The paint is glossy and reflects the sky (and the road below the
horizon), more at a glancing look; the glass reflects more. The tyres sit in dark wheel
wells, on five-spoke rims; head and tail lights follow the corners; the number plates
carry their characters (yellow in Israel, white in Bedford); there are bumper lips, a
grille, mirrors and door handles. A car costs about what the box did: the body is built
once per kind of car, its points shared.

**Trees.** A dozen kinds, picked by the place and where they stand: ficus, acacia, olive,
cypress, pine, tall pale eucalyptus (the roadsides' and parks' tree) and date and fan palms
in Givatayim; maple, oak, birch and spruce in Bedford. Each tree varies in size, lean and
shade, and crowns are clumps, not one ball.

> More variety for the trees? They seem all bland and the same.

They are made of leaves now, not coloured shapes. A crown is a cloud of small cards, each a
cluster of real leaves (photos of leaves, cut out and arranged: broad ones for the ficus,
the plane-like street trees, maples and oaks; small narrow ones for olives, birches and
eucalyptus; feathery fronds for the acacias and for about a third of the round street
trees, like the melias and jacarandas; needle sprays for pines, cypresses and spruces).
The cards always face you, so a crown looks full from every side, lit like a soft ball,
darker inside and underneath, with lighter clumps here and there; every tree's outline is
its own, and the crowns sway a little in the wind. Through the gaps you see the branches
fork up from a barked trunk; the shadows on the ground are dappled. Conifers have a dense
dark middle, so a cypress is the narrow column it should be. Palm fronds are cut into
leaflets that dry yellow at the tips, on a ringed palm trunk.

> No, let's do trees, maybe some more texture and variety, then we will try the cars.

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

**Windows with depth.** Up close (within about 150 m) a window is not painted on: the glass
sits back in the wall, so driving past you see the sides of the opening and the shadow
under its top; it has an aluminium frame and the bar down the middle of a sliding window
(Bedford's: white casings with a cross of muntins), a stone sill with a shadow under it,
and the roller shutter, where it is down, is made of slats. Behind the glass is a room --
back wall, side walls, floor and ceiling, in that flat's own colours, with a sofa, a door
through or a picture, sometimes a curtain half drawn -- dim by day, lit by its lamp at
night if the light is on (and through a shutter, light shows between the slats). The
glass reflects the sky, and the street when you look down at it, more at a glancing look.
Balconies are real hollows, their side walls, tiled floor and the slab over them seen
from below, a glass door at the back; a tower's offices show through its tinted glass and
its lobby is lit at night; the open ground floor of a block on columns is a shaded space
you see into. None of it is geometry or costs anything to load: it is all worked out per
pixel by the walls' shader, from where you look. Further off, and at the lowest web
quality level, the windows go back to paint.

> Can we somehow improve the buildings?

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
is laid where it would lie on another road's asphalt, which also leaves a driveway its gap;
a corner is checked along its whole length (checked only at its middle, a kerb could run
straight across a road's mouth and lay a strip of pavement over the junction).

> There are a lot of broken roads and random sidewalks in the middle. And in general very
> badly looking crossroads.

**Roads that fit.** A road's width is mostly a guess (OSM rarely says), so where a street's
buildings stand closer than the guess it is narrowed (to no less than two lanes) instead of
running under them. A building still standing on the road after that, or so close no
pavement is left, has its front cut back to the road's edge plus a kerb and a strip of
pavement (not one a road passes under, nor one up on columns). The ground's thin layers -- grass, paths, asphalt, paint -- sit a few
centimetres apart and the camera's near plane is a little way out, so a phone's coarser
depth buffer no longer shows grass through the road in green patches.

**Turning, lanes, roundabouts.** A turn starts just short of the junction in the lane the car
is in and comes out just past it in the right lane of the new street (the plan used to run
straight from the junction to the new street's next point, down its wrong side). Cars keep
a little further from the centre line; parked cars stand mostly up on the pavement. On a
roundabout a car decides at each exit and is ever less likely to stay on, so nobody
circles and the cars waiting to come on are let in.

**Main streets have a divider.** A wide two-way main road in the Israeli towns (OSM maps
many as one road) has a raised island down the middle, kerbed and paved, solid to the car,
stopping short of each junction and open at each zebra -- they are not open down the
middle there.

> Usually in Israel main streets have a clear border between the sides, it's not open.

**Autodrive** moves into the left lane (or toward the centre line) over the last 45 m
before a left turn, keeps behind a bus by its back, not a car's length behind its middle,
and passes a bus standing at its stop in the next lane when that lane is clear.

> We turn left from the left lane. / Keeps bumping into stopping buses.

**Autodrive** keeps to the right-hand lane of a one-way road of several (it drove down the
middle, astride two, and in between the cars in them), counts a car going its way as in
its lane wherever their bodies would touch, stops for anyone standing on its lane, keeps out of alleys and car-park lanes
unless there is no other way, prefers turnings back into town at its edge, and if it has
got nowhere for 40 s (not at a light) it is lifted onto a street a little way toward the
middle of town and drives on. Switched on (or knocked) off the road -- in a yard, a car park,
between blocks -- it finds its way back round the buildings at a walking pace instead of
heading straight at the nearest bit of road through the wall in between; with no way out
in reach, or after running into walls a few times in quick succession, it is put back on
the nearest street. Face to face with a traffic car in a narrow street, both standing,
the other car edges past if there is nearly room, and if they are nose to nose it turns
off out of the story (gone once out of sight, or after a few seconds regardless) rather
than the two waiting for each other for ever.

> Sometimes the autodrive gets completely stuck in those narrow streets.

**The edge of the map** is a striped barrier with a glowing curtain over it that shows as
you come near, and a line on the minimap; the car stops against it, nose to the stripes.

> Mark somehow the border of the map, I just hit air and those walls are invisible.

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

Down at street level: a manhole cover every 55-95 m down a street, a drain grate at the
kerb every 40-65 m on alternate sides; oil and rubber blotches on the asphalt; road paint
worn through to the asphalt in patches; kerbs of grainy concrete (the paint wearing with
it), dirtier at the foot; the red of a no-stopping kerb red, not the palette's pink; flat
roofs of tar and gravel with dried-puddle stains.

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
under 45 frames a second, or stuttering (more than one frame in ten slower than 33 ms),
for a few seconds and it steps down a level -- first smoother edges (MSAA) off and
shorter shadows, then no shadows and a lower 3D resolution and the photo textures off
(back to the drawn grain). A one-off stall (over a quarter of a second: something loading)
doesn't count -- one half-second stall made a smooth 50 frames a second read as 38. After
8 s at the screen's full rate it tries the level above again; a level that fails again
waits longer before the next try (30 s, then 1, 2, 4 minutes), so it never flickers
between two.

> Sometimes quality drops, even on my PC. It never goes up again, and textures are gone.

**The drive map.** A second tap on the fps text (or P twice) shows the last two minutes as a
map: your track coloured by speed, autodrive's lane ahead and what is holding it back, the
cars round you, a cross where something was hit and a dot where it stood still. "save log"
downloads those two minutes as a file to send, to see exactly what the car and the cars
round it did.

> Maybe we can log the path of our car (and maybe some adjacent cars) on a 2D map to
> reproduce why they were driving badly, and view the path the car took, to fix its
> accuracy. The frame rate, the slowest frame of the last few seconds and the level are shown
small under the speed. Parked cars and
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

**Loading near-first.** The city is built a 400 m square at a time -- the squares its
meshes are merged in anyway, so building it in pieces costs no extra draws. Only the
squares within about 300 m of the start go up behind the loading text (Givatayim's 9 of
71), so the car is on the road in about 2 s here (it was 7), Bedford in 1.2 (was 11.7) and
Ashdod in 2.8 (was 18); a phone takes two or three times as long. The rest goes up while
you drive, the square nearest where the car is heading first, a few milliseconds a frame
(6, or 3 when frames already run slow), so the driving does not stutter; "building the city
40%" under the street count says how far it has got. Givatayim is all up within about 20 s
of driving here, Ashdod within a couple of minutes. Nothing is left out: when it is done the
city is the one the old all-at-once build made, lamp for lamp. Anything laid along a road or
a fence (asphalt, paint, kerbs, garden walls, wires, fences) is worked out by every square
it crosses, each keeping the triangles that start in it, so nothing shows where two squares
meet; a building, a tree, a sign, a shop or a parked car belongs to the one square it
stands in. What only the building needed -- the parsed city file, the outlines, each
square's lists -- is let go of a little a frame once it is all up. Which junctions have
traffic lights is worked out for the whole city before you drive, so traffic stops at them
everywhere at once.

> what would near load gain? latency? im afraid we will start losing a lot of details in a
> city. maybe 400m is ok.

When the browser can't keep up, the game steps its own quality down; at the lowest step
the real shadows are off, and each car gets a soft dark patch under it instead so it still
stands on the road (the street went flat the moment it stepped down). The asphalt's wear and
grain are strong enough to read at the lowest step's lower resolution.

> I start with textures on the street but after I drive a bit they just vanish.

**Seeing what chokes.** Tap the fps text under the speed (or press P) for the perf view: a
graph of the last frames' times (green under 20 ms, red over 40), the average frame split
into the engine's drawing and the game's own parts (traffic, people, autodrive, the
minimap...), and the last few hitches -- frames much slower than the ones round them --
with the parts that took their time. Playtests report hitches the same way.

> We need to think how to improve latency a bit. It does choke every few seconds. Do you
> have some fps counter or something?

What choked, every few seconds: every 60 m driven the minimap went through every street
and building outline within 360 m (now they are sorted into squares while the city loads,
and gathering is joining a few arrays); every car left behind was found a new road in the
same tick, up to 24 tries each, and every walker a new pavement (now one car and one walker
a tick, a few tries at a time); autodrive planned several legs of road at once (now one a
tick while there is plenty ahead); and every car re-decided its speed -- lights, signs,
junctions, the car in front -- every tick (now 20 times a second, a third of them each
tick). Building outlines on the minimap are plain one-pixel lines.

## How do you win?

There is no winning. The one game hook: every street of the city you drive down for the
first time (30 m along it) scores a point. "streets 12 / 143" in the corner counts how
much of the city you have seen.

## What should it look like?

The real place, recognisably: the street layout, building footprints and heights, parks,
trees and traffic lights where they really are. Daylight, cream apartment blocks with a
window per storey, tree-lined streets, white dashed lines, zebra crossings. Every colour
is a palette role mixed for daylight, so `/look` still reskins it.

The kit's palettes are neon on dark, so the daylight mix keeps only part of each colour:
asphalt, pavements, kerbs and concrete come out as real greys with a hint of the palette,
walls as whites, creams and soft pastels, plants as greens (the palette's green leaning
toward its yellow); signs, kerb paint, lights and the cars keep their colour, as real ones
do. The light is a warm sun, the shade a sky blue, through a film-like curve (bright walls
roll off rather than clip). The sky is a photograph -- a sunny day with cumulus -- turned
so its sun stands where the sunlight comes from; the distance fades into its horizon. At
night it gives way to the dark night sky.

> 1 2 4 5 6 7 (colours and lighting; a real sky; street-level detail; the bus, the scooter
> and people in the cars; the people; loading near-first)

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

The test town is made, not baked: `python3 tools/fake_city.py --out
game/streets/cities/dimyon.json` (add `--preview plan.png` for a map of it, `--seed` for
another town). It writes the same format, with `"made_up": 1`, which puts "a made-up town"
on screen instead of the OpenStreetMap credit. Before writing, it proves the mountains hold:
it floods the height grid from the middle of town through everything gentler than 62% or
on a road, and stops if that reaches the edge of the map.

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
- Not just driving: the same baked city could be walked, or used by another game.
