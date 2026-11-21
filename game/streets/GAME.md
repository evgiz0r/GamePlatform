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

**The driver looks around.** First in line at a junction, a stop or a give-way sign and
about to go (at a light, once it is green), the driver looks left, right and left again
(once a junction; not from behind a queue at a red); into a turn as the wheel goes
over; at people on the crossing ahead; over the right shoulder reversing. From the seat the
view turns with the head; from behind, the camera swings a little to where the driver
looks and the driver's head in the car turns. Autodrive's driver always does it; when you
drive yourself, the "look" button (or G, for glance) switches it on and off.

> I want the driver to look left and right in the turns, like a real driver with the head.
> And I want that to be an option for the non-autodrive. For both chase and seat mode there
> will be some effect of looking. That happens generally on every stop and give way.

> It looks left right on red lights, when it's behind many cars. It should do a look only
> when it's the first car and it's ready to drive.

**Test routes.** The last place in the list, "Test routes: watch a drive", is a list of ten
drives, each from one real address to another (four in Givatayim, three in Ashdod, one each
in Tel Aviv, Bedford and the test town). Pick one: its city loads, the car is set down at
the first address and autodrive drives to the second while you watch; once there, back to
the list. The same ten are driven by the tests and their results kept, to see the driving
get better.

> Lets find some random 10 from-to paths for driving, we would choose randomly and keep
> track, to cover a bit more driving options. Can you add to the menu "test routes", where
> I would be able to pick one of the routes and just watch.

**Routes of your own.** The list has two pages: "the ten" and "yours". On "yours", "+ a new
one, in" a city: the city loads, the address picker asks "from where?" and then "to
where?", and autodrive drives it at once. It is kept on "yours" to watch again (up to nine,
newest first, ✕ to remove one). They are kept in your own browser or phone only, never in
the game's files: the web build is public.

> Maybe later in the same menu I would be able to enter my own.

**Giving way.** Autodrive comes out of a side street onto a bigger road the way a driver does:
up to the corner slowly enough to stop, and if a car is coming that it could not get in
front of with room to spare, it waits at the edge -- looking at that car as it goes by --
and then goes. Turning left across oncoming traffic at a green, the same. A divided road's
crossing: it waits while someone is on its half of the road, not while they finish the far
half. Crossing a divided road where the middle is deep enough for the car, it crosses the near
side when that is clear and waits in the middle for the far one (most medians where a side
street crosses are too narrow for that, and it waits at the kerb for both).

**Turns.** Autodrive turns as a driver does: from its lane, round, into the right-hand lane of
the street it turns into, no tighter than the car can steer and slowly enough to stay in lane.

> the car is turning pretty badly, waaaay too wide. its radius of turning is like double of
> what it should be, it hits the oposing or the next lane a lot

> Real give-way and left-turn decisions (picked from the list of next steps: "1 2 6 7").

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

**Jumping there.** At the top left of the list are two choices side by side, "jump to"
and "drive to", the one in force filled in; "jump to" is chosen when the game starts.
Jumping puts the car down on the street at the address, in its lane, stopped, facing the
way that has the address on the kerb side; driving hands the way there to autodrive.

> in the goto option, make it by default jump to. the menu is not so clear so just show two
> choices. drive to and jump to. where one of them is selected

> Besides go to, I want also jump to. It teleports there, instead of driving.

**Places.** Entering the game asks where, in two lists side by side: **Cities** (Givatayim,
Bedford, Ashdod, Tel Aviv, and the made-up test town last) and **Auto Experiments** (the
filmed walks and the test routes' drives). Each level's `"group"` puts it in one.

> lets rearrange the menu items instead street. 2 categories: Cities, Auto Experiments (walks
> + test-drives). no extra button for walks, just split in the menu.

Givatayim starts on Katznelson just past Weizmann, the town's central junction; Ashdod at
Sderot Herzl and HeHalutzim, its busiest corner for shops. Each place is one
entry in `LEVELS` at the top of `streets.gd` (name, city file, starting corner). Ashdod is
three times Givatayim's size; it takes longer to build in full, but you are driving in
about 3 s here, the same as anywhere (see "Loading near-first").

> Lets make a menu where I pick a place we have. Starting with Givatayim. Can we add
> Bedford, Nova Scotia.

> Ashdod.

**Tel Aviv** is a box of the city centre, not the whole city (all of it would be far too
much to build and drive smoothly): about 4.3 by 3.3 km, from Ichilov and the Savidor
station down past the Carmel market, and from the sea across the Ayalon to Nahalat
Yitshak -- the beaches and the promenade (Herbert Samuel), Allenby, the Carmel market,
Rothschild, Dizengoff's south end, HaKirya, Azrieli and Sarona, Montefiore, Bitsaron. It
began as 2.4 by 2.7 km, Ibn Gabirol to the Ayalon, and was grown to the sea (November
2026); the places in the first box kept where they were. It starts on Kaplan
just past Leonardo da Vinci, heading east, HaKirya on the left and the Azrieli towers
ahead. The towers stand at their real heights (OSM has them for the tall ones: Azrieli's
round tower 187 m, the Spiral 350 m). The map ends at the box's edge (the striped barrier).

The Ayalon runs through it on the ground, and every street over it is a bridge about 6.5 m
up, on ramps from the streets either side: Arvei Nahal, Moses, Givat HaTahmoshet (the
HaShalom bridge), Modai, Begin's and Yitzhak Sadeh. The tunnels are dug: Begin dips under
the Kaplan junction in an underpass both ways, the Lova Eliav tunnel runs under HaKirya and
Sarona with its links meeting Begin's underpass underground, and Uzi Hitman and the
Carlebach tunnel go under, each about 6 m down with cuttings up to the street at either
end. Berkowitz's short tunnel, some car park ramps and two short branch ramps out of
Lova Eliav stay on the ground (too short to get under the street at a car's grade).

The railway runs down the middle of the Ayalon, between its carriageways and under its
bridges: three tracks most of the way, more at the stations, on ballast with concrete
sleepers, under the overhead wires on their masts, and Tel Aviv Savidor and Tel Aviv
HaShalom with their platforms, canopies and names. Double-deck trains run along it, each
line in turn one way then the other, a minute or so apart: they slow for each station,
stand half a minute at the platform and pull out with a blast of the horn. Their headlights
are on and, at night, their windows lit; near the line you hear them go by. The Red Line
light rail is underground here, so it is not shown. On the minimap the tracks are a light
line on a dark one.

> Trains that act like trains: a front with headlights, lit at night, stopping at the
> stations; the overhead electric wires; the sound of a train going by.

Its landmarks: the three Azrieli towers -- round, triangular and square -- in one dark,
glossy blue glass with a band of metal round each top that lights up at night; in HaKirya
the Matcal tower with its mast and the Marganit tower with its concrete shaft, antenna
platforms and red-and-white mast up to 138 m; and Sarona's restored Templer houses, two
storeys under red tile roofs among the lawns and trees, with the towers all round. At night
every tower over 90 m has red aircraft-warning lights on its roof, slowly pulsing.

> Landmarks: Azrieli round/triangle/square towers in proper glass, lit at night, Sarona,
> the Kirya (Matcal) tower.

The beach: warm sand along the sea, rows of umbrellas in blue, orange, red, green and
yellow, each with a pair of white plastic chairs facing the water and people sitting in
some, and a lifeguard's hut on stilts every couple of hundred metres, white with a blue
band and a red flag. The Carmel market: stalls down both sides of HaCarmel with a walkway
between, counters of tomatoes, oranges, greens and peppers in crates, racks of goods behind
and canvas awnings over them. The Shalom Meir tower with the antenna on its roof, and the
Opera tower's stepped stone floors by the sea.

> 1. The Carmel market (stalls, awnings, crowds) 2. The beach (warmer sand, umbrellas,
> lifeguard towers, people) 3. Landmarks in the new part: the Shalom Meir tower and the
> Opera tower -- "1,2,3"

Bus lanes where OpenStreetMap marks them: Kaplan's westbound right-hand lane from Begin out
to the box's edge, and the Ayalon's public transport lane on the right going south. A wide
solid line keeps the lane apart, "אוטובוס" is painted down it every 45 m, buses (and about
half the taxis) drive in it, other cars keep out of it but for the last 40 m before turning
right, and the autopilot keeps out of it too. OSM marks few of Tel Aviv's bus lanes in this
box (none on Begin or Ibn Gabirol), so the rest are not there.

> use the OSM bus lanes

> game streets -- lets add/start working on adding Tel Aviv. Somewhat the area I mentioned.
> (with a map: Ichilov, Savidor, Azrieli, HaKirya, TLV Mall, Montefiore, Bitsaron,
> Nahalat Yitshak)

> lets do the bridges and tunnels over the Ayalon

> do 1 and 2, then the railway

> what would it cost extending tel aviv to the sea and down including like carmel market
> and alenbi, how much more is that

> what next options. lets try to make it bigger

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

> Lets work on adding tunnels/bridges, and maybe more complicated roads. Work in the test
> town. Change the town if needed (adding river or whatever needed for bridges).

**Off the ground** (the test town first). A river, Nahal Dimyon, crosses the south of the
town in a valley of its own, from a spring at the foot of the eastern hills to a lake in
the south-west; its banks are low in the middle of town and steep where it cuts through
the knoll, and every street that crosses it goes over on a bridge -- concrete parapets, a
pavement each side, piers standing in the water -- the ring road's on a long skewed one,
with a footbridge between HaNasi and Rothschild. Derekh HaMinhara goes from HaNasi past
HaGalil down a cutting into the hill and through it in a 440 m tunnel (under HaOranim,
HaBroshim and the water tower), lit by two rows of lamps, up a cutting on the far side to
the ring road. Two of the old grid's streets no longer meet the boulevard: HaTamar dips
under it (a cutting, a short cut-and-cover tunnel, a cutting back up), HaZayit climbs over
it on embankments and a bridge -- and from HaZayit's flyover two slip roads come down to the
boulevard and up from it, a half-diamond interchange: the junctions where they meet HaZayit
are up on its embankments, 7 m over the street, the slip roads merging into and leaving the
boulevard just short of HaTe'ena. Driving, walking and the traffic all keep to their own
level: under a bridge you are under it, in the tunnel the hill's houses are not in your
way, cars overhead do not stop for you.

**Streets are level side to side on a hillside**, as real ones are: the hill is cut into on
the uphill side and filled on the downhill one, and the street keeps only its climb along
its length. (The ground comes from terrain data on a grid, and laid straight on it a street
across a hillside leaned with it -- HaOranim 13%, the lookout road 37%; in every town.)

> I want to make a new fake city in streets, where we would do quicker simulation and
> validations. Yes it would not stress as the big cities on latency, but would give a quick
> look if something got prettier as we are trying to make things more realistic slowly.

> Lets also make that fake city surrounded by some unpassable terrain like a mountain. It
> shouldn't be too small, like a regular neighborhood where you have most of the features
> and variety (cars, buses, buildings, types of cars, slopes, landmark and so on).

**A filmed walk.** "A walk in Givatayim: Katzenelson to Ha-Meri" replays, in first person,
a walk filmed on a phone: off the north kerb of Katzenelson by the Ha-Meri passage, over
both halves on the zebra, along the south pavement and over the paved forecourt, down the
passage between its wooden fence and its low white fence, out along the little street at
its end, over Sheinkin at the corner and into Ha-Meri, where it stops. It walks on its own,
from the eyes of someone holding a phone at the chest, about a minute and a half, timed so
it passes each place when the film did: the two can be watched side by side, which is how
the street is being made more like the real one, a pass at a time, the big things first.
No controls, no driving HUD; exit leaves. The route and what the film showed that the map
lacks are in `cities/details/givatayim.json` (see below).

> Can we create a video, 1st person view like my phone, side by side with video from the
> phone, up until Ha-Meri.

It crosses like a person: it waits two metres back from Katzenelson's kerb facing across,
steps up beside the bollard, glances right, crosses to the gap in the median, waits there
watching the far half, then crosses; at Sheinkin it looks right,
then left. Cars come down the street to meet it there: one goes by before it steps off, the
next stops at the zebra for it, and drives on once it is across. The head looks where the
walk is going and turns into a corner a moment before the feet do.

From the far kerb on, it walks at the film's own pace and turns its head as the film's did --
both measured off every frame of the film, not set by eye: it slows where the film slows (the
corner of the forecourt, the end of the passage), does not stop at Sheinkin's corner but looks
right along it and turns left into Ha-Meri bit by bit, and ends facing Ha-Meri's far pavement,
its white wall and the e-scooter, as the film does. The people the film shows move as they
did: a man walks along the confectionery to the far kerb's railing and stands there, three
people talk by the scooter in the forecourt (turning to each other and back), and a woman
crosses the passage's end in front of the man in blue standing there.

The phone is held as a hand holds one: tipped down at the pavement ahead as the film is
(about 16 degrees, read off where the film's horizon sits), never quite still -- a slow sway
and a little roll, as small and as slow as the film's own, measured from it -- and it looks
down as well as round: straight down at Katzenelson's stripes on the way over, and at
Ha-Meri's kerb as it steps up. Both walks hold it this way. And the picture is the phone's:
its bright end squeezed rather than burnt to white, its shade lifted, warm and a little less
colourful than the game drives in -- measured from the film, frame against frame. It sets
its exposure for what it looks at, as a phone does, so the shade under the arcade is no
darker than the film's and the sunny forecourt no brighter.

On Katzenelson the traffic is the film's: a black hatchback and then a white SUV go by in
the near half while the walk waits at the kerb; a white hatchback goes by as the walk
reaches the median, a white car waits in the kerb lane, and a grey SUV does not give way --
it drives on past, close, in the lane by the median, while the walk waits.

Over the passes since, the walk's street has been dressed, a stretch at a time, from the
film: Katzenelson two lanes each way with railings and red-white kerbs at its zebra, the
dotted slabs for blind walkers at its kerb and through the median's gap, the median's ends
raised blocks of red pavers with a no-U-turn sign, a black bollard with a steel top; the
passage paved in grey pavers in rows, its rough stone wall, and tall planting and trees
closing it in; past Sheinkin the walk crosses Ha-Meri on its raised crossing to the far
kerb, as the film does, the street's kerbs blue and white, a 30 painted in its lane and the
zone 30 sign at its mouth; lit shop fronts under the arcade.

> During the walk we collide into a house, the pavement there is not matching in the middle.
> Let's also add cars, and we look left, right, and they stop for us. Usually we look where
> we want to walk, and look before turning.

> Let's try to enhance that specific walk, very realistic, in depth, slow, iteratively
> (people a bit less interesting, but the other items, from bigger details we already have
> to smaller details). And add in the menu an option to view that walk, just till reaching
> Ha-Meri street. That's all it will do, no other controls.

**A second filmed walk.** "A walk in Givatayim: Sheinkin and Sirkin" replays another walk
the same way, about a minute and a half: along Sheinkin's pavement to the corner by the
Roladin cafe, a glance at the traffic, over Sheinkin on the zebra, a look back across at
the cafe, then up Sirkin's east pavement past its shops toward the lights at Katznelson,
where it stops. This one was filmed with a GPS track running, so its route and timing come
from the track rather than by hand: it is 1:42 to 3:08 of its film. On a street this narrow
the GPS wandered into the road, so each point was moved onto the pavement it was walked on.

Asked whether to add it as a level, from the cafe corner to Katznelson (and whether to
move Givatayim's start to a busier corner):

> yes to both

Sirkin, as the film showed it on a second pass: its ground floors are shops -- rows of lit
glass bays with their sign bands down both sides of the filmed stretch, Roladin's name over
its side on Sirkin -- and the pavement runs up to them, where the game had laid low garden
walls and hedges (OSM calls Sirkin residential). The one real front garden between them,
behind its low white fence, stays. Everywhere else too, no garden is laid in front of a
shop OSM knows. Cars and scooters come in a car paint's red and a dark blue, not pink and
teal.

> can we iterate a bit more [...] what can we itertate there to improve realism. i did also
> photo some of the shops around

> the shops are from the video, i rotated and you could see ( sabih, fruit shop ), maybe
> roladin somewhere too

Each of those shops looks as filmed: Roladin under a black awning with white umbrellas over
its tables; the sabich stand's black awning and a red umbrella over a table at its window;
the green corner greengrocer with crates of fruit and vegetables out front and no awning,
and another across Sirkin by the sabich, under a green awning; Kira Sushi's black front with
a ledge and a row of tall bar stools; white awnings along the block by the computer shop.
Everywhere, awnings and cafe umbrellas come in a canvas's colours (black, white, muted) rather
than glowing neon. Sheinkin is paved in grey bricks laid in rows, Sirkin in reds and browns,
and black bollards with a yellow band stand along Sirkin's kerb toward Katznelson.

> go with all for that area, and create each time a video for me if possible

Kira Sushi's front has its string lights, two strands of warm bulbs looping under the
awning and lit by day as in the film; Sirkin's paving has light grey setts laid in a half-
circle round each street tree and in a band between them. Road signs, crossing barriers,
hydrants and red-and-white kerbs are a real red, not the palette's pink.

> 3,5

The minimap (bottom left) shows the real streets and buildings round you, heading up, with
the city limits in pink. The name of the street you are on is at the top, in Hebrew with
the English name under it when OSM has one.

Over the minimap, small, is which build this is: "build 21 Nov 10:05 UTC · 79f2bc6", when
it was published and the commit it came from, so a screenshot says whether a fix is in it
("dev build" when run from the project). Under the map, small and wrapped so it stays
clear of the buttons, the credits: OpenStreetMap's, and the towns' own surveys.

**Zooming out.** "zoom" (on the right, under "walk"; Z, or the mouse wheel down, or two
fingers pinching together) lifts the view off the car -- or off you, on foot -- up over the
city, centred on where you are, the way you were facing at the top of the screen, and
pauses the city: the car, traffic, people and lights hold still where they are, and the
engine goes quiet. A ring marks you (an arrow on the screen's edge points back if you have
looked away), and on foot a square marks the car. Up there you look round: drag (or the
arrows) to move over the town, the wheel or a pinch (or - and =) to go higher or lower --
from just over the rooftops to about a kilometre of town across the screen -- and Q / E or
two fingers turning to turn it. The view looks down at a slant (about 50 degrees at the
highest), not straight down, so the town reads as streets and buildings rather than a plan.
Zooming in stops at the rooftops; keep zooming in there for about a second (a bar fills
under "keep zooming in to get back in the car") and it flies back down to the car. "back"
or Z go straight down. Either way the city goes on. From the driver's seat it rises via the
chase cam and lands back in the seat. While you are up there the minimap follows the view:
centred where you are looking, turned the way the screen is, with the part of town on the
screen outlined, and an arrow for you (on its edge if you are off it). Trees, pavements and
the rest are drawn all the way across the view while it is up, so nothing pops in as you
move it.

**Pause.** "pause" (K) holds the city still with the view where it is; "resume" lets it go
on. Resumed while zoomed out, the city runs under you and the view follows the car, which
still drives (keys or the stick). The shell's own pause (its menu) is still there too.

> If I would want a zoom out feature, that zooms out from where I am. Maybe it pauses the
> city (maybe we can add a pause feature anyway), and we can zoom back in (or check around).

> It goes back into my car too quickly if I am zoomed in. Maybe if I am fully zoomed and I
> still zoom in for a second. I do want to be able to zoom it. I want the map to represent my
> zoomed view if possible (so it's clearer what I am looking at). Maybe the angle slightly
> more tilted so it's less from above. When I move while zoomed some buildings just pop in
> the view, not naturally.

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
signs are OSM's where it maps them (Givatayim a few dozen, Bedford more), and everywhere
else a side street meeting a bigger street without lights gets one, as real towns do: a
stop before a main road in the Israeli towns, a give-way otherwise (and in Bedford). Two
streets of the same size meeting have none (first come, as before), nor roundabouts, nor
driveways; the lights run their own
cycle. In the Israeli towns they go as they do there: green, three flashes of green, amber,
red, red and amber together, green. In Bedford: green, amber, red. The main road's green is
the longer, 18 s against the side streets' 13. Between one way's amber
and the other's green, 3-3.5 s for the junction to clear. A car that can still stop on amber
stops; one too close goes (traffic used to cruise on until it could not stop, often late in
the amber, and cross on red). Autodrive, at the end of a green (the flashing green or the
amber), goes on only if it will be over the line before the red at the pace it is going --
slowing for a turn just past the line counts -- and otherwise stops, firmly if it has to.
Stopping, it stops at the line, however far off it was when the green began to end ("the car
weirdly stops in the middle of the run": a green ending 80 m ahead stopped it 60 m short, by
a side street, and it stood there all through the red).

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
is time to be over before the cars across get their green, and not in front of a car already
in the junction waiting to get out over their crossing (one after another they kept it
standing in a big junction for 25 s, the cars across going round it).

> The whole logic of lights and how cars and autodrive go, something is fishy. Let's make
> the colours clear: red on the top (no go), yellow, green. Maybe add those for people too,
> matching the lights -- that's how it usually works here, so they don't just cross randomly.

> Buses get stuck in the middle of roads when it's red for them.

> Some crossroads I think are wrong in how they work: the colours, the switching, the AI and
> autodrive, maybe also not matching the pedestrian lights sometimes. Something not moving
> properly.

**Signs and paint.** A stop line across the lane at every light and stop sign, STOP
painted before a stop sign (עצור in Givatayim), a dashed line at a give-way (with האט
before it in the Israeli towns), SLOW (האט) before a crossing near a school, speed limit signs a little after each junction on the main roads (round and
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

**Kerbs and parking, as filmed.** In Givatayim and Ashdod the kerb's paint goes by where on
the street you are, as a walk filmed down two of Givatayim's streets showed it: blue and
white along a residential street's parking, red and white for the last few metres before
every junction and along many main roads, yellow and black in front of a bus stop. The
parked cars keep to the paint: a nearly unbroken row down a blue-and-white street, half up
on the pavement, fewer along a plain kerb, none on the red-and-white corners or at a stop.
In about a third of the gaps between them a motorbike or scooter stands up on the pavement,
along the kerb or at a slant, leaning on its stand; people walk past on the back half. Many
of the low stone garden walls carry a fence of dark wooden boards to about head height.

> ill film myself driving to work and back or whatever. and somehow give you the info back.
> to make it more nad more realistic ( for the specific path and more general )

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

**Sound.** The engine is made, not recorded, pitched by the revs of a five-speed
automatic, with a brighter layer under the throttle. Over it, what speed sounds like from
inside a car: the tyres' roar on the asphalt, louder and brighter the faster you go, and
the wind once you are moving quickly; the nearest car going by as the whoosh of its tyres,
its pitch falling as it passes; and the city far off, always, soft. (See "Sound you do not
switch off" below for why it changed.)

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
Where two streets' pavements meet, each is laid once: a corner flickered between two pavings
laid over each other at one height. Nothing stands on a rounded corner's asphalt -- bollards,
sign and light poles were placed out on it, in front of the kerb.

**Traffic islands.** A lawn or paved patch with road nearly all round it -- the island at a
roundabout's mouth, a roundabout's middle, where a boulevard's halves part -- stands a kerb's
height above the road with a kerb round it, and the car goes over it with a jolt, as over a
median. It lay flat, level with the asphalt:

> some wierd grass patches on the road

Open ground between streets is dusty sand; it was a grey like the asphalt's, and an empty
strip read as more road.

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

**Autodrive at a dead end** stops a few car lengths short of the end and turns round the
way a driver does in a narrow street: indicator on, forward on full lock to the far kerb,
reverse lights and back on the other lock, forward again -- three moves in a cul-de-sac,
more in a narrower one -- waiting if a car comes up the street, and drives back out. It
used to try to swing round in one go and ran into the trees and garden walls at the end.

> Autodrive misbehaves at the end of a dead-end street: the car tries to turn round there
> and drives into a tree or post beside the road.

**From above, point and go.** Zoomed out over the city, hold a finger (or the mouse) on a
street for half a second: a ring fills under it, then the view comes down to the car and
autodrive drives there, as "go to" does. A quick press still drags the view.

> When I'm zoomed out, I want to be able to click on some ground and that will become the
> destination, maybe a long tap, and it will go back to the car and start driving like "go to".

**Medians** are a kerb's height, and the car goes over them -- with a jolt for each axle, the
faster the harder, riding up on it -- rather than stopping dead at an invisible wall.

> The border is too low for my car not to pass. Either a higher border, or I can tackle it
> and pass it.

**The edge of the map** is a striped barrier with a glowing curtain over it that shows as
you come near, and a line on the minimap; the car stops against it, nose to the stripes.
Autodrive keeps away from it: at a junction it looks a few hundred metres down each way on,
and a way that only leads off the map is taken only when there is nothing else; on a street
with no way back short of the edge it turns round where it is, not at the barrier.

> Mark somehow the border of the map, I just hit air and those walls are invisible.

> The autodrive sometimes goes into a road that hits the border of the city where it
> obviously cannot go. It then turns and does some tricks to go back, but that's weird in
> the first place.

**The test town's mountains.** The made-up town is ringed by mountains, and they are meant
to be looked at: limestone in beds (a ledge every few metres of height, a dark seam under it,
so the slopes read as rock from the streets), red-brown soil in the hollows, dark scrub in
the folds and low down, pine woods with cypress and olive in clumps up the slopes, and the
shadows of clouds drifting over. On the highest stretch of the crest a row of five wind
turbines faces the town, the blades turning, red lights on top blinking together. The valley
has half the haze of the real towns (no horizon to hide), or the mountains were a white wall.

> Let's make the mountain in the test town a bit more interesting to watch.

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
footways and plazas are 20 x 10 cm concrete pavers in herringbone, a mix of greys, charcoal and
red-browns (drawn by `textures/herringbone.py`, after a walk filmed in Givatayim: no photo
had them; the pavements along the streets are laid square to the kerb in each street's own
pattern, see "As it looks on foot"), Bedford's poured concrete slabs; grass and open
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

**As it looks on foot.** Set beside frames of a phone video of a walk down these streets,
the city now has what the walk had underfoot and at eye height:
- Pavements of concrete pavers: herringbone at 45 degrees, rows of bricks, or square slabs,
  each street its own, in mixed reds and browns, greys, sand, or all of them mixed, with a
  row on end along the kerb. Leaves on them under the trees (and the odd bougainvillea
  petal), grime in wide soft stains. Bedford keeps its poured concrete slabs.
- Blocks' ground floors as they are: flats behind white security bars, the way in a glazed
  door in the middle bay, lit at night (they used to be dark hollows, a row of black boxes
  along every street). A stone plinth to knee height on most blocks, Jerusalem stone in
  courses on the stone-clad ones, small square mosaic tiles on some of the white ones.
- The lobby under a block on columns light, its glass door lit, the ceiling over the
  parking pale (it read as a black box from the pavement).
- Tired roads: patches of newer, darker asphalt with their sealed seams; stretches crazed
  into small plates; the mix's light stones showing close up; the paint, zebras too, worn
  half away and cracked with the road. Manhole covers grey cast iron, not black.
- At the kerb: a pair of bollards either side of every zebra on both pavements, black with a
  yellow reflective band (now and then white); on the main roads a white railing instead,
  4 m either side of the crossing; a red fire hydrant every 130 m or so; grey utility
  cabinets at the back of the pavement; black bins on the main and shopping streets; an iron
  grate round every street tree's trunk. All solid to the car, and never on the road: a
  railing or a bollard by a zebra near a corner stood out on the junction's asphalt (it was
  checked against the roads' edges, and a junction's round middle and corners are neither).
  Columns under a building over a road (a passage) stand beside the lanes, not in them.
- Front gardens plot by plot (14-22 m each, a gap for the gate): a low wall of rough stones in
  mortar, with a clipped hedge behind it, white bars or green chain-link on top, or bare;
  bougainvillea spilling over one in six; the garden shrubs leafy, not smooth balls.
- The ground darker where things stand on it, as the sky's light reaches less of it there:
  a soft band out from the foot of every building, darker still in its inside corners; the
  parking under a block on columns in the shade; a dark patch under every parked car,
  softening out past its sides. Without it the houses and cars looked as if they hovered a
  hair above the street. It is one faint layer laid out with the city, so it costs almost
  nothing while you drive.
- Shadows all the way out. The real shadows only reach 45-75 m from the camera (and the
  lowest quality has none), so past them the whole city used to stand on evenly sunlit
  ground. Now every building's shadow, and every tree's, lies on the ground as far as you
  can see, as dark as the real ones and meeting them without a seam; at the lowest quality
  they are the only shadows there are. The sun never moves, so they are worked out once
  as the city loads.

> ok lets start as you say

> ok go next

> go next

**Golden hour.** The time-of-day button steps through day, evening and night. The evening is
the hour before sunset: a sky photographed then, clouds lit gold from below and a glow
along the horizon where the sun is going down (in the west-south-west, as it sets over
Givatayim in the autumn); the sun low and orange, so the fronts that face it glow and the
streets lie in long blue shade; the haze warm towards the sun. Every shadow, the painted
far ones too, is as long as a low sun makes it. The first switch to the evening takes a
moment (its far shadows are drawn then), after that it is instant.

> continue?

> lets improve sound a bit. its just annoying noise i have to turn off now

**Sound you do not switch off.** The engine used to be the only sound: a buzz of sharp
pulses, almost all of it lower than a laptop's or a phone's speaker can play, so what came
out was a rough flutter, droning even standing still, with a second buzz beating against it
whenever a car went by, and a coin's jingle every block. Now the engine is a smooth hum under
the tyres' roar, nearly silent at idle; speed is the road and the wind; a passing car is a
whoosh; the coin for a new street is a quiet tick, the indicator a relay's soft click.

> go next

**After rain.** The "wet" button (beside the time of day; "dry" turns it back) soaks the
streets over a second and a half: asphalt, paint and pavers go dark, puddles lie in the
dips holding the sky (and, low down, the buildings across the street), the sun's glare
runs along the wet road when you drive towards it, grass and earth go a little darker. The
tyres hiss on it. It goes with any time of day; the evening after rain is the best of it.

> some of the stuff we did really causes latency and loading issue i think. other session is
> fixing something i believe. go 3,7
> dont want to touch weather yet

**Street cats and flags on cars.** Givatayim's strays: sitting on the garden walls or curled
up on them, by the bins, on the pavement at a parked car's nose -- ginger, grey, black, cream
and brown tabbies, holding still as street cats do. About one parked car in fourteen flies
an Israeli flag on a stick from a back window. And the ground darker where more things meet
it: a soft patch at the foot of every street tree, the pavement darker along the foot of the
garden walls. All of it built with each square of the city in a few tens of milliseconds,
and nothing to do while you drive.

> Night that feels like night ... Grass blades near the camera ... lets start with these too.
> and then go the video from today for more ideas

**A night that feels like night.** The night is dark and only a little blue now (it was a
teal "day for night" over everything), with the city's own glow low on the horizon. Every
street lamp has a halo round its head and a warm pool of light under it on the pavement as
well as the road (the pools used to lie under the pavement, and showed only on the road;
and a little brighter and wider since, out to 8.5 m from the lamp: on a main road, where the
lamps take turns a side, it went dark between them);
headlights, yours and the traffic's, glow, and their beams light the road ahead; a lit
shop window throws its light onto the pavement in front of it. No glow effect over the
whole picture -- that costs a laptop's browser a millisecond or two every frame -- the
halos are drawn with the pools, as part of what was drawn already.

**Grass you can see the blades of.** Near you -- on foot most of all -- the lawns, parks and
front gardens have blades standing up out of them, swaying, a few drier and paler among
them, thinning out by 18 m. Only at the two top qualities (fewer at the second).

> people dont have collision and just wonder around, lets add that to the list as well.
> when some things just pop and have no collision its wierd

**Front gardens as a walk finds them** (from a second walk's video, "1-5"):
- The garden walls are each plot's own: rough stones in mortar, or rendered and capped with
  a slab of pale stone, from knee height to over a metre where nothing stands on them.
- Where a building's door faces the street the wall opens: a gate between two rendered
  piers, now and then a metal arch with bougainvillea grown over it, and a path of pale
  slabs with a border of white stones through the garden to the door. Before a deep yard
  the opening is wider and a car is parked in the yard, nose to the building.
- Greenery spills out over the pavement from some of the hedges and bare walls, and over
  the board fences at head height; the walkers step round it.
- Set into the paving every few dozen metres: a round iron lid in a square frame, or a
  square iron plate. Four street trees in ten stand in a square of bare earth with a low
  concrete edge, dead leaves and a drip hose, instead of an iron grate.
- By one junction in four of the residential streets: a big blue bin for paper, often an
  orange cage for packaging beside it, now and then a purple bell for glass.

> 1-4, 8, 10. people who react not needed yet, maybe later.

**More of the street, and things that break:**
- Bikes locked to the bollards, leaning on them; now and then one dropped on the pavement
  by a garden wall; a delivery rider's e-bike with its big blue or orange box outside the
  restaurants and cafes (the motorbikes parked up on the pavement came earlier).
- Where a residential street leaves a main road, the slow zone's 30 sign on the right a
  few metres in; along the blue-and-white kerbs now and then the blue P of paid parking
  with its yellow plate of hours.
- Passages between blocks walled on both sides: rendered and capped, or rough stone,
  sometimes boards along the top of one side, sometimes a row of bike hoops.
- Tags and stickers: scribbled tags and bubble letters low on the rendered garden walls,
  gate piers and grey cabinets, stickers on the poles.
- Knock a bin or a recycling bin and it goes flying and tumbles; hit a bollard and it bends
  over at its foot (the driving assist still brakes for bollards, not for bins). Hitting
  anything solid throws sparks, and so does scraping along a wall; a hard knock leaves
  glass and bits of plastic on the road and dents in your car where it hit. What you knock
  over stays down while you are near and is back once you have driven out of sight.

> 1, 3, 6, 8 (check what was not seen yet; AC units and washing; background sounds; people
> in one piece)

**On the walls, in the air, and lighter to draw:**
- AC units that look like AC units -- an off-white box on two arms, the fan's round grille
  and the vents, the pipes into the wall, a drip hose and the grey streak the drips leave --
  under the windows, any side but the street's the most; up on the back wall of some
  balconies over the parapet. Most blocks show a few (it was three plain boxes at most).
- A rack of washing under a window now and then: towels, shirts, trousers, socks, a sheet;
  a towel hung over a balcony's parapet.
- What a street sounds like besides the traffic: birds in the trees by day (sparrows, a
  bulbul), louder where there are more trees and in the evening; crickets in the gardens
  at night; people talking at the cafe, shop or school you pass, from where they are; a dog
  barking a street or two away now and then. Quieter in the car, the more the faster.
- Dents you can see: a hard knock pushes the panel in, buckles it, and scrapes the paint
  round it.
- Each person drawn in one go (they were six pieces each): fewer things for the browser to
  draw every frame, nothing different to see.

> 5, 3, 2 (front gardens out of the wait; traffic doing street things; more kinds of people)

**Sooner to the street, and more going on in it:**
- Loading is about half a second shorter: the front gardens you see first are there when the
  car appears, the rest of the starting area's follow within a second or two.
- Now and then a delivery van or a truck stops in the street, half in its lane, hazards
  flashing, for half a minute or so. Cars behind it go round over the centre line when
  nothing is coming (on a wider road they change lanes), and so does autodrive.
- Now and then a car parked at the kerb ahead of you signals as you come up and pulls out in
  front of you.
- Someone walking a dog on a lead, a parent pushing a pushchair, a few people sitting on the
  park benches and a few waiting at the bus stops, facing the road.

**People who keep clear.** The walkers step round the trees, posts, benches and cabinets on
the pavement, keep to one side of anyone coming the other way, and step round people standing
talking and round you on foot; you and the car can no longer go through them (the car stops
at a person with a soft knock, never a crash). They no longer pop in at 90 m: they come in
over the last 15. Cats on the pavement are solid too.

> i look at the latest video of the walk in sirkin, people are popping randomly and moving
> aimlessly on my path, and no collision between them and the parked cars.

**People round you on foot.** Nobody appears or is moved where you can see it, wherever
your head turns on a walk (a person at a cafe table used to jump to the next table in view
as you glanced at the shops). The people coming at you make room from a few steps off, to
whichever side has space, rather than jumping a metre aside as if you were a car. At the
end of a block they walk on over the side street or round the corner, rather than turning
back and pacing the same block. And parked cars are solid along their whole length: people
no longer walk through the middle of one.

> 3,4,6,7,8 (shops that look open, a faster start, the leftovers, more that breaks, walk 2's route)

**Shops that look open, and the rest.** A shopkeeper stands in the doorway of a few open
shops near you; sandwich boards stand out in front of many, and corner shops put their crates
out. Hitting a wall leaves rubber and paint streaks on it; driving into a hedge is soft --
leaves fly and the car is held, nothing breaks. People, dogs and pushchairs keep clear of a
parked car's corners too, a dog stays on its walker's side of a railing, grass no longer
grows through garden paths, and someone with no room to step aside stops to let you pass.
The walk along Sirkin keeps a step further from the parked cars, as filmed. Loading compiles
about a tenth fewer graphics programs (most noticeable on a phone or a Windows laptop).

> lets add real driver plates, that would improve the look a lot. lets think about the cars a
> bit more how to make even more real. besides lets do - 1,2(i think we added db of stores so
> we have many of them now!?) , 6

**Plates and shop windows.** Every car carries an Israeli plate -- yellow, black digits in a
black rim, the blue IL strip -- each a made-up number of its own (never a real one), readable
up close and from the chase view. Shop windows show the shop inside, in depth as you pass:
shelves of goods, racks of clothes, or a cafe's counter and menu board, dim by day and
glowing at night. (There is no store database yet: the shops are OpenStreetMap's and the
filmed ones; Tel Aviv's council lists 3,387 licensed businesses, which could fill its streets.)

> 1,2,4,5,6,7 (car shapes like the cars here, wheels, Israeli touches, wear, the colour mix,
> small details)

**Cars like the ones here.** Small city cars, hatchbacks, family sedans, compact SUVs, the
odd estate and tall boxy small van among them; each car's own wheels (five spokes, fine
spokes, a steel wheel's cap, now and then dark alloys) with the brake disc behind; dust on
the cars that have stood a while, sun-faded paint on the older ones, scuffed bumpers; folded
silver sunshades in parked cars' windscreens and parking permits on many; now and then a
learner's roof sign or a new driver's sign; wiper arms, shark-fin aerials, roof rails on the
SUVs and estates; mostly white, silver and grey, as the streets are.

> 1,2,5,9 (car lights, car movement, the taxi's sign, the blocks' fronts as filmed)

**Lights, wheels, doors, and the blocks' plaster.** Cars' headlights have a black housing
with lenses and a running-light strip lit while they drive (older cars a chrome
reflector); tail lights glow red with their own shape, brighter on the brake, with a white
reversing light and an amber indicator; the indicators blink in the lamps themselves and on
the mirrors, and a third brake light shows at the top of the rear window. Front wheels
turn as cars steer, and a parked car is sometimes left with its wheels turned. Now and then
the car parked ahead that pulls out first has someone getting in beside the driver: the
door open over the pavement, them stepping in, the door shutting, a little back with its
reversing lights, then out. Your car knocks over manhole covers and drain grates; cars
near you dip their noses over them. Taxis carry a yellow מונית sign, lit at night. The
blocks take their colour from their age (from the city's records): the 1950s-70s ones in
sand plaster, older ones cream, new ones white or clad in stone; many balconies closed in
with aluminium windows and shutters, white balcony bands on some blocks, grime under the
old ones' windows. (Speed humps: the map data the game is built from has none yet.)

> I took a video on my phone, walking in Givatayim.

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
with the parts that took their time. Playtests report hitches the same way. Its last lines
are the loading: how long it took, the slowest stages, and how long each of the four views of
the warm-up took (the graphics getting ready -- see below).

The warm-up: before the car is shown the city is drawn four times from above the start, one
look each way, so the browser compiles every kind of material's shader then and not as each
first comes into view while you drive (each one a stall). Every new kind of surface adds to
it. While it runs the loading text says "getting the graphics ready" (it showed the last
square, "8 of 8", until the warm-up was over, and looked stuck).

> how can we optimize the bringup, to as 0 up time as possible as the game starts. those
> steps where i dont know how long i have to wait and its sometimes 3 seconds sometimes 20
> is annoying

(Of the options offered, picked: start on the build already on the phone, drive sooner, a
bar that says how long.)

**The build on the phone starts at once.** The wait swung so much mostly because of
publishing: every push made a new build, and the app downloaded all of it again (78 MB)
before starting -- after reloading itself once. Now the build already on the phone starts
straight away and the new one downloads in the background while you play; when all of it
is there, "new version ready — tap to restart" appears at the top (the next launch is the
new build anyway). Only the games' file is fetched (39 MB); the engine, as big again,
changes only with Godot and is kept. Only a very first visit waits for a download.

**Driving after one square, not six.** Before the car is shown: the square the start is in,
any within 60 m of it, and those the street ahead crosses within 160 m -- what the first
view looks at. The rest within 320 m goes up right after, in a hurry (16 ms of each frame
instead of 6, so the first few seconds run a little slower), then at the usual pace. Car on
the road here: Givatayim 4.4 -> 3.0 s, Tel Aviv 10.1 -> 6.3, Ashdod 8.3 -> 5.9; the rest
round the car 3-6 s later. A filmed walk and a test route still build all 320 m first: their
pictures and drives are compared run to run.

**A bar, and "about N s".** Under the loading text: how far it has got, and how long is left,
from this phone's own last load of that city -- the city file, the setting up, a square, the
graphics getting ready. That last one is kept twice: as it was on the same build (the
browser kept the compiled shaders: quick) and on the first load of a new build (it compiles
them again: the slow case), so the estimate knows which one this is. A city never loaded on
this phone yet is estimated from another one's; the very first load says "timing it, for
next time". Slower or quicker than last time so far, the rest is taken to be so too.

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
  building outline; heights and floors where OSM has them; in Tel Aviv (the level, and the
  strip of it at Givatayim's west edge) the city's own measured heights for most of its
  buildings, from the municipality's 2019 survey (credited on screen); parks, grass, water, car
  parks; mapped trees; traffic lights and zebra crossings; the speed limit where OSM tags
  it (every driver keeps to it, and the signs show it); the city boundary. The hills:
  the ground follows an open elevation model (AWS terrain tiles), baked in with the city.
  Shops, cafes and bus stops stand where OSM puts them, under their real names.
- **Guessed**: a building with no height gets 4 storeys (by type: houses 2, garages 1,
  offices 5...), varied a storey up or down so a street is not one flat wall. A road with
  no width tag gets one by kind (residential 8 m, room for a parked row each side).
  A road with no speed limit takes the one most of its town's mapped streets of the same
  kind have, where enough are mapped and agree (residential streets: 30 in Givatayim and
  Tel Aviv), else one by kind (50 km/h in town, faster on main roads in the north, 90 on
  a motorway).
  The rows of street trees along residential streets are added, not mapped. The window
  grid is a pattern, not the real facade. The traffic lights run their own simple cycle.
  What a shop looks like (awning, tables, the bus shelter) is generic. The parked cars
  (about a quarter of the kerb), the people walking and sitting at cafe tables, rooftop
  solar heaters and rooms (Givatayim), pitched roofs on small houses (Bedford).
- **Guessed, in Givatayim, Bedford, Ashdod and Tel Aviv: how high the bridges are, how deep
  the tunnels.** OSM says which ways are bridges and tunnels but not how high or deep, so
  the game works it out as the town loads: each overpass rises to clear what it crosses, on
  ramps up the roads leading to it, an interchange's junctions up on them and its slip
  roads coming down; each road tunnel runs about 6 m under what runs over it, cuttings
  sloping down to its mouths. Highway 102's overpasses, the Bedford Bypass, the MacKay
  Bridge's approach (Bedford has no tunnel); in Ashdod Highway 4's interchanges and Sderot
  Menachem Begin's underpass, down a cutting under the road it crosses. Givatayim and Tel
  Aviv share a stretch of the Ayalon: Menachem Begin's and Arvey Nahal's bridges over it,
  Uzi Hitman's tunnel and the City tunnel; Tel Aviv adds the Moda'i bridge, the Begin
  underpass and the Lova Eliav tunnel. The ramps are grass banks with a guardrail along the
  top where there is room for them, retaining walls where there is not; the cuttings are
  walled.
- **Footbridges and footpath tunnels, guessed the same way.** A footbridge clears the street
  under it by 5.8 m (3.4 m over another path), paved, with a steel railing; its ramps rise
  along the footpaths only, steep (25%), and as stairs where OSM maps steps or where a path
  meets a street before its ramp is down. A footpath tunnel goes 3.6 m under the road, a
  low tiled tube with one row of lamps, ramps or stairs down to it. Trail bridges over
  creeks (Bedford's greenway) span from bank to bank.
- **Not there yet**: a few road tunnels too short for their cuttings (the Rabin Underpass):
  left out. People crossing anywhere but a zebra.

To make your own street more accurate, fix it on openstreetmap.org (building heights are
the most useful thing to add) and bake again.

**What a walk showed.** `cities/details/<city>.json`, when there is one, is laid over the
baked city as it loads (`details.gd` has the format): road edits (drop a baked road, add
one), zebras the map leaves unmarked, extra areas, and what stands along a street that OSM
does not map -- stone walls, wooden fences, low white fences, hedges, bins, the white hoop
railings at a passage's end -- placed by hand from a walk filmed along it. Givatayim's has
the Ha-Meri passage: OSM draws it as one footpath from Katzenelson to Sheinkin, where the
film shows a paved forecourt, the passage itself between its fences, and a short street
with parked cars down to Sheinkin. The second pass dressed the passage's north end as the
film shows it: the corner block stands on columns along Katzenelson, shops back under the
upper floors and a row of motorbikes nose to the kerb; charcoal pavers under the arcade,
the forecourt's pale poured slabs with a manhole; black bollards banded yellow across it,
the transformer on twin poles at the passage's mouth, a garden lamp, the barrier across the
next block's drive, and the planted bed and trees where the passage begins. It also holds
walks, routes timed to their film, that a place in `LEVELS` can replay. A footpath in town (not in a park) is paved like the
pavements everywhere, not only here.

**Sizes as in life.** Cars, the bus, lanes, kerbs and storeys were already life-size; the
people were a little tall (now 1.55-1.85 m, about 1.70 on average) and the views far wider
than the eye's (now about 85-95 degrees across a wide screen, not 96-113), which made the
near loom and the street look small and far. The filmed walks keep a phone's view.

> My sister tells me the scales of the game feel off.

## Later (said, not built)

- Bridges and tunnels in the real towns: working out each deck's heights from OSM's tags
  and the ground (the test town has them already), then an interchange you drive over and
  under.
- Not just driving: the same baked city could be walked, or used by another game.
- Crashes, what is still to come: a sign post bent, a fence panel or a hedge pushed in, a
  scrape mark on the wall the car rubbed.
- Speed humps to bump over: OSM marks them (traffic_calming), but the baker does not keep
  them yet -- it needs that and a re-bake (Overpass, or the bake workflow).
- People who react ("not needed yet, maybe later"): jumping back, or falling, when a car
  comes at them; glancing at you; stopping at the kerb before they step out.
- A "green wave": "any crossroads i approach switches to green for my car" -- a switch for
  the player's car (driving or autodrive) that turns each light it comes up to green its
  way, through the usual change for the cross street (amber, red) so the traffic there stops
  as it would.
