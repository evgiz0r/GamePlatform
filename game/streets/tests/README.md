# streets -- scene tests

Each script loads a city, stages something and prints what it measured; most save
screenshots too. Run one with

```bash
game/streets/tests/run.sh <test> [level]      # 1 Givatayim, 2 Bedford, 3 Ashdod, 4 test town
```

(`OUT=dir` for the screenshots, `FULL=1` to keep full render quality -- the behaviour tests
drop to the lowest, which changes nothing they measure -- `RES=1280x720` for bigger shots.)
On a cloud container each takes one to seven minutes: run them in the background.

The last results (November 2026) are what "good" looks like. A change that moves one of
these numbers the wrong way has broken something.

| Test | Level | What it measures | Last result |
|---|---|---|---|
| `people_on_road` | 1, 3 | walkers / people at crossings standing on asphalt | 0 of ~2150 (was 29%) |
| `people_pops` | 1 | people appearing or jumping in view; crossings started against the light | none; 0 of 16 |
| `junction_choices` | 3 | junction prompts during autodrive; a big junction asking twice | 0 twice; 3 knots asked once |
| `autodrive_lanes` | 3 | autodrive on multi-lane roads: lane accuracy, bumps into cars, hits, buses passed | 0.4 m off the lane's middle, 0 bumps |
| `autodrive_two_way` | 1 | time left of the centre line on two-way streets, hits | 0 s, none |
| `autodrive_offroad` | 1 | dropped in yards and between blocks: back on the road? | 7 of 8 (Katznelson start; spot 4 is stuck 40 s either way -- it used to be lifted at 40 s, now it backs out and the test's 45 s run out) |
| `autodrive_corners` | 1, 3 | leaving the asphalt at corners | 0 in Givatayim, 3 brief in Ashdod |
| `autodrive_narrow` | 1 | standstills in the narrow streets (David Kalai and others) | longest 2 s |
| `standoff` | 1 | autodrive meeting a car head on in a narrow street | passes, 2.2 m apart |
| `roundabouts` | 3 | longest time on a ring, touches, stalls | 5 s, 0, 0 |
| `junction_traffic` | 1 | traffic: crossing collisions, stalls, creeping through | 0, 0, 0 |
| `zebras` | 1 | crossings, people hurried back, time traffic stood for them | 12 started, 0 hurried |
| `lights` | 1, 3 | junctions with lights; crossing cars in one junction together over 90 s; close-ups | 0 / 9 (Ashdod: cars squeezing round autodrive held in a five-point junction by people on its exit zebra) |
| `light_audit` | 1, 3 | every junction with lights: crossing ways with green together, one road's light changing inside a junction, ways in with no light, stop lines on zebras, walk lights green while cars come; then a drive (`DRIVE`, `AT`) counting cars in on red, crossing cars in a junction together, cars creeping in after 6 s (`DYNAMIC_ONLY=1` runs the drive on older code) | crossing pairs green together / a road changing group inside a junction / walk lights green with cars coming / ways in with no pole: Givatayim 0/0/0/7 (were 12/48/26/66), Ashdod 0/1/0/5 (20/100/49/70), Bedford 0/0/0/3 (6/3/20/17). 2 min round Arvey Nahal: over a stop line on red, traffic 0, autodrive 0 (autodrive 1 before) |
| `lights_at` | 1 | one junction (`AT=x,z,dx,dz`, default the Arvey Nahal knot) from a car at its line, a shot per light state; prints its points, groups, lines, walk lights | shots |
| `no_entry` | 1, 3 | no-entry signs facing drivers who may go in | 0 / 1 |
| `buildings_on_roads` | 1 | buildings still standing on a road's asphalt | 3 (passages, on purpose) |
| `corners` | 1 | junction corners the old middle-only check let in whole | 261 (fixed), shots |
| `map_edge` | 3 | the car coasting into the map's edge | stops nose to the barrier |
| `road_blocks` | 4, 1 | things solid to the car on a road's lanes, a junction's middle or a rounded corner's asphalt: a median over another road, walls, posts (bollards, sign poles, railing ends; shots from above) | test town: 0 medians, 0 posts; 16 walls across service lanes. Givatayim: 0 medians, 0 walls, 8 posts (159 before corners' asphalt counted as road: bollards, sign and light poles; the 8 are 3 light poles kept so every way in has one, 4 of the filmed Ha-Meri passage's details, 1 on a service lane) |
| `medians` | 4 | the raised medians from a driver's seat where they end and bend (shots) | |
| `mountains` | 4 | the test town's mountains from the car, the hill, a mountainside, and the turbines (shots) | |
| `go_where` | 4 | zoomed out, a long press on a street: destination set, the view down, the city on, the car there; a quick press does nothing | 9 m from the press, arrived; quick press: none |
| `picker` | 4 | the "go to…" list: jump to chosen at start, drive to chosen, then a street picked: the car jumped there (shots) | jump first; 48 m from the street's first point after the jump (put in its lane) |
| `islands` | 1, 3 | the traffic islands raised and kerbed (lawns and paved patches with road nearly all round): how many, and any 1 m point of one on a road's asphalt or a junction's disc; shots of the biggest from the road | Givatayim 19 pieces 10,957 m2, Ashdod 41 pieces 54,353 m2; 0 points on a road |
| `hitches` | 7 | with `STREETS_BUILD_ALL=0`: autodrive for `DRIVE` s while the rest of the city builds, then up over it dragged round for `UP` s, then down: frames over 250 ms and 1 s per phase; `hitch_parts.py <log>` sums the game's [hitch] lines per phase | Tel Aviv here: every drive frame ~0.8 s (the software renderer), the script's parts ~1 s over 61 frames -- the GPU's stalls need a real browser |
| `pave_overlap` | 7, 1 | pavement laid twice over one spot (two streets', a street's and a corner's) -- which flickers on a phone between the two patterns -- and kerb tops on pavement; the worst places (shots) | Tel Aviv: 19,360 m2 laid twice before; now 5,355 m2, of it two different pavings 30 m2 (the rest a strip's own next piece at a bend, the same paving laid the same way) |
| `top_at` | any | shots of places by map point (`AT`), from above and from a car's height, and the car put down anywhere (`CAR=x,z,dx,dz`, off the road too) and shot from the chase camera: for matching a user's screenshot | shots |
| `street_at` | any | the car put down 25 m before each roundabout (`RINGS_ONLY=0`: each junction) on a street by name (`STREET`), shot from the chase camera | shots |
| `median_cross` | 4 | the car across a median at 10, 30, 50 km/h: over it, riding up, slowed by the jolts | over at 30 and 50 |
| `autodrive_edge` | 1, 3 | autodrive put on streets that run off the map, 120 m short, facing out: touches of the barrier, turn-rounds, time near it | Givatayim: touched the barrier 1 (a one-way motorway with no exit), turned round 5, 31 s near it (were 9, 9, 59 s); Ashdod 1, 6, 31 s (10, 12, 71 s) |
| `feet` | 1 | a walker's feet against the pavement's top | 0.21 = 0.21 |
| `feel` | 1 | a crash at 54 km/h; jumping out at 50 km/h; into a fence | rebound 0-1.3 m/s, no hop; 3.4 m tumble, car rolls 37 m; the fence check picks a fence behind a building (stops 6.5 m short) -- to fix |
| `on_foot` | 1 | getting out, walking, running, a car stopping for you | 2.1 / 6.2 m/s |
| `quality_ladder` | 1 | the frame-rate watcher fed made-up frame times | stays at 2 through stalls; down at 35 fps; back up at 60 |
| `quality_look` | 1 | the street at quality 3 and 0 (shots) | |
| `eye_level` | 1 | the streets at a walker's eye height round a point (`AT="x,z"`, default the start), along, back, across and down, the nearest zebra and the nearest block on columns: for comparing with photos of the real street (shots) | ground floors barred windows, not black; bollards at the zebra |
| `contact_shadows` | 1 | the contact-shadow layer on and off, same view: the nearest building's foot, block on columns, parked car round a point (`AT="x,z"`); how much of each picture got darker (shots `ao_*_on/off`) | wall ~4% darker, by up to 0.5; car ~6% |
| `far_shadows` | 1 | the shadows painted past the real ones: the city's shadow picture (`far_shadow_map.png`), real vs painted over the same block, how much light each leaves, then on/off down the street, a long straight, over the city and from the zoom-out's height at quality 3 and 0 (shots `far_*`); `EVENING=1` in the evening's light | both leave 0.69 of the light (evening: 0.76 and 0.75); ~100 ms of work at load |
| `time_of_day` | 1 | day, evening, night over the same views: an east-west street towards the evening sun and away from it, the start street, the zoom-out height (shots `tod_*`); how long the first switch to the evening takes | ~0.2 s of work (the evening's far shadows), then two frames |
| `wet` | 1 | dry and after rain over the same views (down the start street, back across the zebra, a walker looking down at the pavement), by day and in the evening (shots `wet_*`) | darker ground, puddles with the sky in them, no white flare on sunlit pavers |
| `street_life` | 1 | the cats and the flags on parked cars: how many, and the nearest two of each up close (`AT="x,z"`; shots `life_*`) | ~1 cat a block; a flag on 1 parked car in 14 |
| `night` | 1 | the night up close: from the car with its headlights, by the nearest lamps (pools, halos), in front of the nearest lit shop (shots `night_*`) | pools on the pavement too; halos; the shop's light on the ground |
| `grass` | 1 | the grass blades on and off: a walker by the front gardens, by the nearest park, from the car (shots `grass_*`) | 6-9% of each picture changed; blades only on the lawns |
| `people_clear` | 1 | the walkers on autodrive for 40 s, ten times a second: how many are more than 10 cm into a post or a wall, how many are closer than 0.45 m to someone; run headless | was 7.6% and 47; now 0.1% and 2-9 |
| `sound_drive` | 1 | the game's own mix on autodrive, recorded (AudioEffectRecord on the master bus) to `sound_drive.wav` to listen to, its loudness and brightness second by second (`WET=1`: after rain, the tyres hiss); run headless (`OUT=... $GODOT --headless --path . -s res://game/streets/tests/sound_drive.gd`), not with run.sh | -38 dB standing, -31 to -35 driving |
| `draws`, `frame_cost` | 1 | what is drawn and what it costs per quality level | ~280 draws |
| `divided_zebra` | 3 | people crossing both halves of a divided road (shots) | |
| `load_stages` | 1, 3 | where the build time goes, stage by stage (`STREETS_BUILD_ALL=0`: what a player waits for) | Ashdod near-first: ready in 6.8 s here, 2.5 of it shader warm-up; whole city: kerbs 3.0 s, roads 1.9, trees 1.7 |
| `drive_log` | 3 | the drive recorder: 60 s, the map page, a saved log | ~520 samples |
| `exam` | 1, 3, 4 | the driving exam: autodrive from 4 places for 75 s each, everything that went wrong per minute (see DEV.md); and the **checks**, which should read 0 (CHECKS total): bodies overlapping, a body into a building / wall / post, stopped for a red with the front over the line, autodrive pushing 3 s, standing 10 s+ held by nothing named -- all on bodies (`bodies.gd`), not middles. Headless with `--fixed-fps 60` (see its top): Givatayim in ~25 min here | checks, first rounds (Nov 2026): Givatayim 29 -- buses' bodies into kerb-side trees and poles (13), moving cars overlapping side by side (7), autodrive into a car (6: a hatch stood 20 s "held by the limit" with autodrive pushing into it, then a rescue), autodrive into a post (2), pushing (1); Ashdod 26 -- traffic into posts (21: one a taxi at 39 km/h through the mall column `city_check` finds in Zahal), stopped for a red over the line (2: a scooter 7.1 m past it, a taxi 2.9 m), cars overlapping (3); test town 16 -- traffic into posts (11, mostly buses), held by nothing (3: queues whose front car stands "held by the limit"), cars overlapping (1), autodrive into a car (1) |
| `dead_ends` | 1 | "go to" from 8 dead ends, parked facing the closed end: out of the street in 40 s? hits, time off the road. Then free autodrive driving into each: stops at the end, turns, comes out? (`DEAD_ONLY=n`: just the n-th, driving in) | 8 of 8 out, 1-2 building hits on the "go to" trips (at (401, -84) on every run, before and after the dead-end turns; real-time, so it varies a little); driving in 8 of 8 (stops ~6 m short, turns in moves; was 7 of 8, the one at (522, 356) failing) |
| `dead_end_turns` | 4, 1, 2 | autodrive set down 60 m short of each cul-de-sac's end (`N=` of them, `ONLY=` a street, `VERBOSE=1`; runs headless): hits, how it turned round (moves, seconds, on the spot), nose short of the end, bumpers over the kerb | test town 8 of 8, 0 hits, 3-6 moves in 11-15 s (was 8 hits at 21-29 km/h); Givatayim 12 of 12 out, none hit turning (it waits for a traffic car coming up the street), one finished on the spot -- HaMeri (630, -609) hits a post standing 1 m onto its asphalt on the way in (main was stuck there for good), and HaMaalot (716, -198) sometimes brushes a street tree 0.6 m off the asphalt on a bend; Bedford 16 of 16, 0 hits, all three moves |
| `knot_lights` | 3 | one signalled junction watched for 2 min (`KNOT_AT=x,z`, default Sderot Herzl x HaGdud HaIvri): each car that goes in on red with what it saw in the 4 s before; drive logs centred on the junction | 1 of 17 on red (was 5 of 40: one junction counted as five, and a car stopped for a zebra past its line drove on through the red) |
| `head_look` | 1 | the driver looking left and right approaching a junction, from the seat and from behind (shots), and the "look" switch for driving yourself | looks left 54 deg, right 54; off: 0 deg, on: 54 |
| `lane_position` | 1, 3 | where the cars sit across the road driving straight: each one's gap from its right side to the asphalt's edge, by kind of road, how often under 0.3 m; autodrive against its own planned line; its turns on the spot | autodrive on its line within ~0.1 m; was hugging the kerb on 3-lane Sderot Herzl (0.09 m), now in the middle lane (4 m); traffic on two-way streets under 0.3 m 17% -> 14% (what is left: 5.4 m streets) |
| `seat_steady` | 1 | the view from the driver's seat over 90 s of autodrive: how far it looks off ahead, how fast it turns, how often it swings back | was 9.4 deg off on average, 171 swings a minute (the look-round fed the steering in twice); now 3.3 deg, 67 |
| `traffic_motion` | 1 | how the other vehicles move: the rear sliding sideways (a real one never does), heading snaps, per kind; the bus that turned most for `bus_turn_chart.py` | rear sliding 3-7% of the moving time -> 0; snaps only tight corners at walking pace |
| `queue_start` | 1, 3 | a real queue (a car at the red, the car it holds up, ...) pulling away at the green (`KNOT_AT`), each car's speed for 12 s and when its front crosses the stop line; `queue_start_chart.py` draws it. QUEUE CHECK: PASS / FAIL against real queues (start gaps; each car's gap over the line against Greenshields' figure for its place in the queue; queues whose front car is held up past the line not judged). Few queues form: Givatayim `KNOT_AT=-800,-288 SECS=900` gives ~17 (Ashdod's default junction gave none in 150 s) | Givatayim, 15 min: 17 queues, 11 judged; moving off 1.2 s after the car in front (good); over the line 1.23x the real gaps (good 0.8-1.2: second car ~3.9 s behind the first, real 3.1): **FAIL, just** -- queues clear about a quarter slower than real |
| `walls_on_roads` | 1 | walls the car collides with (garden walls, fences, hedges, shelter backs) standing on a road's asphalt; `WALL_AT=x,z` lists those near a point | 0 (was 41: garden walls of one street laid across the next) (it counts only walls wholly on the asphalt: `city_check` counts any 0.3 m in, and finds hedges) |
| `city_check` | 1-4 (0: all) | the city as built, before anything drives it, on bodies (every metre of a wall, a post's circle, a building's outline): walls, posts, buildings 0.3 m+ into a street's asphalt; lit points in no junction (should be 0). Traps to stage tests at: stub roads under 5 m at a junction, lit points under 25 m apart in two junctions, walls and posts on service roads. Seconds a city headless; `SHOTS=1 OUT=dir` (run.sh) saves the worst two of each kind from above, ringed | after the first fixes: Givatayim 13 (11 low garden walls, one a cul-de-sac's turning bulb; 2 buildings, the passages kept on purpose), Bedford 2 (buildings), Ashdod 3 (garden walls), test town 0. First round: 20 / 5 / 19 / 0 (hedges over the kerb, a mall's columns 1.9 m into Zahal, a fuel station's column, parked motorbikes' solid circles in the lane). Traps: stub roads 10 / 17 / 31 / 12, split junctions 4 / 0 / 6 / 0 |
| `filmed_spots` | 1 | the game from the spots a filmed walk or drive was at, at chest height, to set beside the film's stills (`SPOTS=<json>` from the scratch directory, never the repo; the format and the pavement placement are at its top; `RES=1280x720` for the pairs) | 19 spots in ~6 min; mid-walk a spot moves 0-2 m onto its pavement, 6-12 m at a track's start or by a big junction (check those by eye) |
| `walk_snap` | 1 | a filmed walk's GPS route (`ROUTE`, from tools/gpx_route.py) moved onto the pavements it was walked on by the game's own road widths (`SIDES`: spans of seconds, left/right, street); prints each point's move and any point on asphalt, and the crossings kerb to kerb; writes `$OUT/walk.json` for the details file | mid-street 0-2.5 m; by a big junction 10+ m (cut the walk there) |
| `street_fronts` | 1 | the parked motorbikes and the wooden board fences on garden walls nearest the start (`N`, default 3 of each), from where people walk on the pavement | Givatayim: ~2900 motorbikes, ~5800 fence pieces; scooters on the front half of the pavement, boards on the walls |
| `shop_looks` | 1 | each place the details file gives a look (`shops`), seen from the middle of the street facing it; prints where its front went and its tables | Givatayim: 5 shops on Sirkin, all on walls; Roladin 3 tables under white umbrellas |
| `decks` | 4, 2, 3, 7 | roads off the ground (levels 2, 3, 7: Bedford's, Ashdod's and Tel Aviv's inferred decks, their tunnels and highest bridges driven off both ways; each take-off printed with where): autodrive through the hill's tunnel both ways, over the flyover, under the underpass, over a river bridge and the ring road's bridge, up a slip road into the junction on HaZayit's embankment and down the other into the boulevard -- frames where the car is not at the height of a road it is on, frames in the air, wall hits, which decks it drove; then fixed views of each (shots). Headless (`--headless`, see the script) gives the numbers in two minutes | every run drives its deck, 0 frames off the level, 0 wall hits; in the air 0 except 8 frames (a 2 cm hop) off the end of HaNasi's bridge |
| `deck_air` | any | one deck run traced (`AT=x,z FACE=deg`): every quarter second and every frame in the air, where the car is, its height, the surface under it, the deck it is on -- for a run `decks` reports "in the air" | shows the seam or crest it flew from |
| `street_holes` | 7, 4, 3 | every street on the ground sampled every 2 m (middle and both edges of its asphalt): what a car there stands on -- more than 0.5 m under the street is a hole it falls through (a cutting, or a tunnel taken for the street) -- and whether a deck's wall stands there at street level (printed by kind: pier, em, bank, br, cu). Headless, a minute or two | holes: Tel Aviv 6 (the HaShalom bridge's west ramp, 0.6-0.9 m), the test town 0, Ashdod 0; walls: Tel Aviv 41, Ashdod 51, test town 10 (ramps' walls tight beside other roads; piers in lanes were 25 and 29, now 0) |
| `door_to_door` | 1 | a "go to" trip from a house on a side street to another 900-1600 m away (`SEED` picks the pair) | SEED 3: arrives in 235 s, no hits, longest wait 16 s behind a car; was 390 s with 2 min stuck at a dead end |
| `zoom_out` | 4, 1 | zoom out from the car: the city held still (car, traffic, people), dragged, turned, landed, moving again; the pause button; from the seat and on foot (shots) | Givatayim: held 0.00 m up, looking round and paused; lowest view inside a building at 0 of 16 spots; one notch in at the lowest stays up, 1.4 s of it comes down; ranges put back; moving again after landing, camera back at 3 m; seat restored. Up 137 m (default, 282 draws), 441 m (top, 368 draws; 296 driving) |

## Faster runs: `SIM_SPEED`

`SIM_SPEED=n` (run.sh) or `STREETS_SIM_SPEED=n` (straight from the engine) runs n times as
much game time a tick: the game holds the engine's time scale at n every tick (the shell puts
it back to 1 when a game starts, so `--time-scale` does nothing). Tests count time by the real
tick (`Engine.time_scale / Engine.physics_ticks_per_second`), never 1/60. `sim_cost.gd`
measures what a game second costs.

Measured on the test town's exam (headless, 4 starts x 75 s, November 2026):

| | 1x | 1x again | 2x | 3x |
|---|---|---|---|---|
| wall time (6 s of it loading) | 66 s | 66 s | 43 s | 33 s |
| CHECKS total | 13 | 12 | 13 | 6 |
| autodrive hits a car | 2 | 1 | 2 | 1 |
| bodies overlapping (traffic) | 6 | 5 | 10 | 4 |
| traffic: cars overlapping | 11 | 7 | 11 | 18 |
| harsh braking | 50 | 27 | 15 | 12 |
| ticks left of the middle | 14 | 15 | 6 | 1 |

Two runs at 1x differ a lot by themselves; 2x stays within that, 3x does not. So:
- **1x** for how driving feels and anything measured tick by tick (crashes, steering,
  the seat view, `feel`, `head_look`, `seat_steady`, `on_foot`, `decks`' heights, the filmed
  walk, recorded frames), and for the numbers written in this table.
- **2x** for behaviour counted over minutes while iterating (the exam, `dead_ends`,
  `door_to_door`, `knot_lights`, `queue_start`, traffic) -- harsh braking reads lower (a
  jerk spread over a longer tick) and "ticks left of the middle" counts ticks. Check the
  final result at 1x.
- **3x** for a quick "does it still run" only: the counts drift.
- `city_check` drives nothing: speed does not apply. Headless (`--headless --fixed-fps 60`)
  is the bigger saving for anything without screenshots.

`drive_log_map.py` draws a saved drive log (the "save log" button on the perf view's map
page, or `drive_log.gd`'s output) over the city: `python3 game/streets/tests/drive_log_map.py
drive-....json [out.png]` (`--from`/`--to` seconds to zoom on a stretch). `exam_chart.py`
draws two exam printouts side by side as a scorecard (`exam_chart.py out.png
"Givatayim:round1.txt:round2.txt:round3.txt" ...`); `side_by_side.py` puts two pictures
side by side under a title each (a drive before and after a fix). The map names the
streets driven and the main roads in view, with a legend for the path's colours (speed).
