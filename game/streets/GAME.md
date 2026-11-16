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
rather than sit inside a wall).

## What do you do?

Drive, freely. The car behaves like a car rather than a toy: about 4 m/s² off the line,
150 km/h flat out, firm brakes, steering that gets gentler with speed, tyres that let go
if you take a corner too fast (it runs wide), body roll and nose dive. Hold the brake when
stopped and it goes into reverse, like an automatic.

Keys: up = gas, down = brake (and reverse), left/right = steer. Space switches on
**autodrive**, which drives the streets by itself in the right-hand lane, slows for
corners and keeps the speed limit (50 on through roads, 40 on residential streets).
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

**Places.** Entering the game asks where: Givatayim, or Bedford, Nova Scotia. Each place
is one entry in `LEVELS` at the top of `streets.gd` (name, city file, starting corner).

> Lets make a menu where I pick a place we have. Starting with Givatayim. Can we add
> Bedford, Nova Scotia.

The minimap (bottom left) shows the real streets and buildings round you, heading up, with
the city limits in pink. The name of the street you are on is at the top, in Hebrew with
the English name under it when OSM has one.

## What is trying to stop you?

Nothing yet, on purpose: this is a driving sim first. Buildings, trees, parked cars and
traffic-light poles are solid, and hitting them hurts the way it should (a thud, a shake,
speed gone).

## Smooth on a laptop and a phone

> It's pretty choppy and laggy now. I'm trying on a laptop browser.

A browser draws through WebGL, much slower than a desktop game, so the city is cut into
squares that are only drawn when on screen and near enough (kerbs and road markings to
about 260 m, trees 550 m, buildings 1100 m, people 90 m), shadows cover only the street
round the car, and the car and camera are drawn between physics ticks so they glide
however fast the screen redraws. In a browser the game also watches its own frame rate:
under 50 frames a second for a few seconds and it steps down a level -- first smoother
edges (MSAA) off and shorter shadows, then no shadows and a lower 3D resolution. It never
steps back up during a drive.

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
- **Not there yet**: bridges and tunnels as such (tunnels are dropped), other traffic.

To make your own street more accurate, fix it on openstreetmap.org (building heights are
the most useful thing to add) and bake again.

## Later (said, not built)

- First-person / hood camera.
- Other cars, and real driving rules: lights that mean something, signs, give way.
- Not just driving: the same baked city could be walked, or used by another game.
- Engine sound.
