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
| `autodrive_offroad` | 1 | dropped in yards and between blocks: back on the road? | 8 of 8 |
| `autodrive_corners` | 1, 3 | leaving the asphalt at corners | 0 in Givatayim, 3 brief in Ashdod |
| `autodrive_narrow` | 1 | standstills in the narrow streets (David Kalai and others) | longest 2 s |
| `standoff` | 1 | autodrive meeting a car head on in a narrow street | passes, 2.2 m apart |
| `roundabouts` | 3 | longest time on a ring, touches, stalls | 5 s, 0, 0 |
| `junction_traffic` | 1 | traffic: crossing collisions, stalls, creeping through | 0, 0, 0 |
| `zebras` | 1 | crossings, people hurried back, time traffic stood for them | 12 started, 0 hurried |
| `lights` | 1, 3 | pairs of ways the old east-west rule had green together; crossing cars in one junction together; close-ups | 31 / 57 fixed; 0 / 7 |
| `no_entry` | 1, 3 | no-entry signs facing drivers who may go in | 0 / 1 |
| `buildings_on_roads` | 1 | buildings still standing on a road's asphalt | 3 (passages, on purpose) |
| `corners` | 1 | junction corners the old middle-only check let in whole | 261 (fixed), shots |
| `map_edge` | 3 | the car coasting into the map's edge | stops nose to the barrier |
| `feet` | 1 | a walker's feet against the pavement's top | 0.21 = 0.21 |
| `feel` | 1 | a crash at 54 km/h; jumping out at 50 km/h; into a fence | rebound 0-1.3 m/s, no hop; 3.4 m tumble, car rolls 37 m; the fence check picks a fence behind a building (stops 6.5 m short) -- to fix |
| `on_foot` | 1 | getting out, walking, running, a car stopping for you | 2.1 / 6.2 m/s |
| `quality_ladder` | 1 | the frame-rate watcher fed made-up frame times | stays at 2 through stalls; down at 35 fps; back up at 60 |
| `quality_look` | 1 | the street at quality 3 and 0 (shots) | |
| `eye_level` | 1 | the streets at a walker's eye height round a point (`AT="x,z"`, default the start), along, back, across and down, the nearest zebra and the nearest block on columns: for comparing with photos of the real street (shots) | ground floors barred windows, not black; bollards at the zebra |
| `contact_shadows` | 1 | the contact-shadow layer on and off, same view: the nearest building's foot, block on columns, parked car round a point (`AT="x,z"`); how much of each picture got darker (shots `ao_*_on/off`) | wall ~4% darker, by up to 0.5; car ~6% |
| `far_shadows` | 1 | the shadows painted past the real ones: the city's shadow picture (`far_shadow_map.png`), real vs painted over the same block, how much light each leaves, then on/off down the street, a long straight, over the city and from the zoom-out's height at quality 3 and 0 (shots `far_*`); `EVENING=1` in the evening's light | both leave 0.69 of the light (evening: 0.76 and 0.75); ~100 ms of work at load |
| `time_of_day` | 1 | day, evening, night over the same views: an east-west street towards the evening sun and away from it, the start street, the zoom-out height (shots `tod_*`); how long the first switch to the evening takes | ~0.2 s of work (the evening's far shadows), then two frames |
| `sound_drive` | 1 | the game's own mix on autodrive, recorded (AudioEffectRecord on the master bus) to `sound_drive.wav` to listen to, its loudness and brightness second by second; run headless (`OUT=... $GODOT --headless --path . -s res://game/streets/tests/sound_drive.gd`), not with run.sh | -38 dB standing, -31 to -35 driving |
| `draws`, `frame_cost` | 1 | what is drawn and what it costs per quality level | ~280 draws |
| `divided_zebra` | 3 | people crossing both halves of a divided road (shots) | |
| `load_stages` | 1, 3 | where the build time goes, stage by stage (`STREETS_BUILD_ALL=0`: what a player waits for) | Ashdod near-first: ready in 6.8 s here, 2.5 of it shader warm-up; whole city: kerbs 3.0 s, roads 1.9, trees 1.7 |
| `drive_log` | 3 | the drive recorder: 60 s, the map page, a saved log | ~520 samples |
| `exam` | 1, 3 | the driving exam: autodrive from 4 places for 75 s each, everything that went wrong per minute (see DEV.md) | see DEV.md's scorecard |
| `dead_ends` | 1 | "go to" from 8 dead ends, parked facing the closed end: out of the street in 40 s? hits, time off the road. Then free autodrive driving into each: stops at the end, turns, comes out? (`DEAD_ONLY=n`: just the n-th, driving in) | 8 of 8 out, 0 hits; driving in 7 of 8 (stops ~2 m short), the one at (522, 356) being looked at |
| `knot_lights` | 3 | one signalled junction watched for 2 min (`KNOT_AT=x,z`, default Sderot Herzl x HaGdud HaIvri): each car that goes in on red with what it saw in the 4 s before; drive logs centred on the junction | 1 of 17 on red (was 5 of 40: one junction counted as five, and a car stopped for a zebra past its line drove on through the red) |
| `head_look` | 1 | the driver looking left and right approaching a junction, from the seat and from behind (shots), and the "look" switch for driving yourself | looks left 54 deg, right 54; off: 0 deg, on: 54 |
| `queue_start` | 3 | a real queue (a car at the red, the car it holds up, ...) pulling away at the green (`KNOT_AT`), each car's speed for 12 s; `queue_start_chart.py` draws it | (being measured) |
| `walls_on_roads` | 1 | walls the car collides with (garden walls, fences, hedges, shelter backs) standing on a road's asphalt; `WALL_AT=x,z` lists those near a point | 0 (was 41: garden walls of one street laid across the next) |
| `filmed_spots` | 1 | the game from the spots a filmed walk or drive was at, at chest height, to set beside the film's stills (`SPOTS=<json>` from the scratch directory, never the repo; the format and the pavement placement are at its top; `RES=1280x720` for the pairs) | 19 spots in ~6 min; mid-walk a spot moves 0-2 m onto its pavement, 6-12 m at a track's start or by a big junction (check those by eye) |
| `walk_snap` | 1 | a filmed walk's GPS route (`ROUTE`, from tools/gpx_route.py) moved onto the pavements it was walked on by the game's own road widths (`SIDES`: spans of seconds, left/right, street); prints each point's move and any point on asphalt, and the crossings kerb to kerb; writes `$OUT/walk.json` for the details file | mid-street 0-2.5 m; by a big junction 10+ m (cut the walk there) |
| `decks` | 4 | roads off the ground: autodrive through the hill's tunnel both ways, over the flyover, under the underpass, over a river bridge and the ring road's bridge, up a slip road into the junction on HaZayit's embankment and down the other into the boulevard -- frames where the car is not at the height of a road it is on, frames in the air, wall hits, which decks it drove; then fixed views of each (shots). Headless (`--headless`, see the script) gives the numbers in two minutes | every run drives its deck, 0 frames off the level, 0 wall hits; in the air 0 except 8 frames (a 2 cm hop) off the end of HaNasi's bridge |
| `door_to_door` | 1 | a "go to" trip from a house on a side street to another 900-1600 m away (`SEED` picks the pair) | SEED 3: arrives in 235 s, no hits, longest wait 16 s behind a car; was 390 s with 2 min stuck at a dead end |
| `zoom_out` | 4, 1 | zoom out from the car: the city held still (car, traffic, people), dragged, turned, landed, moving again; the pause button; from the seat and on foot (shots) | Givatayim: held 0.00 m up, looking round and paused; lowest view inside a building at 0 of 16 spots; one notch in at the lowest stays up, 1.4 s of it comes down; ranges put back; moving again after landing, camera back at 3 m; seat restored. Up 137 m (default, 282 draws), 441 m (top, 368 draws; 296 driving) |

`drive_log_map.py` draws a saved drive log (the "save log" button on the perf view's map
page, or `drive_log.gd`'s output) over the city: `python3 game/streets/tests/drive_log_map.py
drive-....json [out.png]` (`--from`/`--to` seconds to zoom on a stretch). `exam_chart.py`
draws two exam printouts side by side as a scorecard (`exam_chart.py out.png
"Givatayim:round1.txt:round2.txt:round3.txt" ...`); `side_by_side.py` puts two pictures
side by side under a title each (a drive before and after a fix). The map names the
streets driven and the main roads in view, with a legend for the path's colours (speed).
