# streets -- developer notes

`GAME.md` is the game as the player sees it and asked for it. This file is for whoever
works on the code next: where things are, how to test them, what the numbers were, what is
still wrong. Update it in the same commit as the change that makes it stale.

**More than one session works on this game at once** (late 2026: one on driving, traffic
and people's behaviour, one on realism -- textures, car bodies, sky, profiling -- one on the
made-up test town). Read `git log HEAD..origin/main` before starting and before pushing;
merge, re-check (`tools/check_script.sh`, a playtest, the tests below), never force.

## Files

| File | What |
|---|---|
| `streets.gd` | the game: loading and building the city, the car, autodrive, people, HUD, camera, quality, profiler (~11.5k lines) |
| `traffic.gd` | the AI traffic: spawning, paths, lanes, lights and signs, following, standoffs, drawing (multimeshes per car shape) |
| `furniture.gd` | street furniture built after the places: power lines, lamps and bus-stop kits, flags, ads, fences and hedges, bike racks and scooters |
| `drivelog.gd` | the drive recorder (see below) |
| `decks.gd` | roads off the ground -- bridges, embankments, cuttings, tunnels: their heights, what is under a point at a level (`surf`), their walls for collisions (`push`), the ground cut away over cuttings (`cut_tri`), and drawing them a square at a time (`build`). See "Off the ground" below |
| `cities/*.json` | baked towns (`tools/osm_city.py`) and the made-up test town (`tools/fake_city.py`) |
| `details.gd`, `cities/details/<city>.json` | what a filmed walk showed and OSM lacks, laid over the baked city as it loads (road edits, unmarked zebras, areas, an arcade cut under a block, paving level with the pavement, walls, fences, hedges, bins, railings, bollards, a pole transformer, a barrier, parked motorbikes, trees) and the walks themselves; the format is at the top of `details.gd` |
| `cities/details/make_givatayim.py` | writes `givatayim.json`: every detail placed along the Ha-Meri passage's own line, with the film's seconds beside what each came from. Edit this, not the JSON, and run it |
| `textures/` | CC0 photo textures (Poly Haven) and the scripts that made the sky and the leaf atlas; credited in `textures/CREDITS.md` |
| `tests/` | scene tests, see below |

`streets.gd` is in sections (`## ---- name`); `grep -n "^## ---- " streets.gd` lists them.
The ones most often touched, and the functions in them:

- **loading the city** -- `_load_city`, then `_fit_dual_carriageways` (halves of a divided
  road sized to their lanes, `r["median"]`), `_fit_widths_to_buildings` (widths are guesses),
  `_clip_buildings` (fronts still on a road cut back to road + 1.5 m), `_build_graph`.
- **building the world, near-first** -- `_build_world` does the once-only things
  (`_build_setup`: which roads, nodes, buildings, areas, places reach each 400 m square;
  the park, tree and light set-ups), then `_build_tile` square by square: the ones within
  `NEAR_FIRST` of the start behind the loading text, the rest in `_build_rest` while you
  drive, nearest the car first, every builder stopping when the frame's budget is used up
  (`if _over(): await _pause()`; `BUILD_US`). Two rules keep squares from doubling or
  missing things: what lies along a road or fence is worked out by every square it crosses
  and kept only where its triangles start (`CBuf.clip`, `_near_part`, `_near_span`);
  everything else, and whatever it records (posts, parked cars, lights, tables), belongs
  to the square its spot is in (`_mine`, `_ring_mine`). A builder that is a coroutine must
  be awaited everywhere, or what it builds after a pause lands in the wrong square.
  `STREETS_BUILD_ALL=1` builds every square before the car is shown (the tests do).
- **looks at street level** -- the pavement is drawn by `KERB_SHADER` in the kerb's own
  mesh (vertex COLOR.b 1: a pavement; COLOR.r the street's paving, `_set_pave_code`;
  COLOR.g its leaves, `_leafy`; UV metres along and out from the kerb), so it costs no draw
  of its own; the kerbs are built after the trees for the leaves. A block's ground floor
  (barred windows, the door in the middle bay), stone courses, plinth and mosaic are
  `WALL_SHADER`'s `ground` / `door` / `stone_k`; worn asphalt is `TONE_SHADER`'s
  `crazing()` and patches. `tests/eye_level.gd` puts a camera where a person stands.
- **sound** -- `sounds/make_sounds.py` makes the loops (engine, engine_load, road, wind,
  city; numpy, run it again after changing it, the .wav files are committed and imported
  looping, QOA); "the sounds of driving" in streets.gd plays them: `_build_engine`,
  `_engine_tick` (the gearbox, then each layer's pitch and volume a frame; the car going by
  is the nearest traffic car, its closing speed from its distance a frame ago for the
  pitch). Levels are relative to `SFX_SCALE`. `tests/sound_drive.gd` records the game's own
  mix headless. The old engine (pulses below 200 Hz, made at load) measured centroid
  40-140 Hz, 2-16% above 200 Hz; the new mix 290-550 Hz moving, 45-66% above 200 Hz.
- **time of day** -- `SKIES` (day, evening: the photo, its sun and colours from `hdr_sky.py`,
  where the sunlight comes from, its warmth and energy), `_sky_now()`; `_next_time()` (the
  button: day, evening, night), `_set_evening()`. `_retint_city` reads `_evening` for the
  ambient (the sky's blue in the evening, not the haze), the sun's colour (ink to warn, and
  in the evening a little hazard: orange, not lemon) and the haze's glow towards the sun
  (`fog_sun_scatter`). The far shadows are drawn per sun and kept (`_fs_cache`); the trees'
  patches are laid at the trunk and moved by the sun in `AO_SHADER` (`sun_off`,
  `sun_stretch`), so they need no laying again. `FS_DARK_EVE` 0.4: a low sun lights the
  ground less, so its shadows take less (real 0.76, painted 0.75, `far_shadows` EVENING=1).
  `STREETS_CAM=...,2` starts in the evening. `tests/time_of_day.gd`.
- **shadows past the shadows** -- `_build_far_shadows` (after `_build_setup`, at load):
  every outline swept along the sun by its height (`Geometry2D.convex_hull` of the outline
  and the outline moved), then the outlines themselves cleared, drawn white on black into a
  SubViewport (one `canvas_item_add_triangle_array`), read back, mipmapped, ~1.6 m a pixel.
  `FAR_SHADE` (`far_shade()`) goes into the kerb, tone and ground shaders by `_with_far()`
  and darkens the ground (faces up) by it past `fs_near * fs_fade` -- the real shadows'
  own range and fade start -- so the two meet; `_far()` keeps those materials in step with
  quality and night. Trees: `_ao_tree` in the contact-shadow layer (COLOR.b 1), left out
  inside a building's shadow. `FS_DARK` 0.55 matches the real shadows (both leave 0.69 of
  the light on screen, `tests/far_shadows.gd`). ~100 ms of work plus two frames at load.
- **contact shadows** -- `AO_SHADER` (multiply, no depth, fades out to `AO_SEEN`), one
  CBuf `_ao` per square made in `_build_tile` and drawn after the cars; `_ao_footprint`
  (strips out from each building's foot, a fan at outside corners; negative width: in under
  it, for the parking under a block on columns) and `_ao_car` (parked and car-park cars).
  Ramp in UV.x, strength COLOR.r, a flat floor COLOR.g. Lies at pavement height + 2.5 cm.
  First pass: ~115 ms for 1519 buildings once each height was looked up once (308 ms
  plainly). `tests/contact_shadows.gd` shoots each with the layer on and off.
- **front gardens** -- `_garden_fronts`, called from the kerbs for each side of a yard
  street in the south, after the low stone wall. Plots keyed to the run (so every square
  along the street works out the same ones) and skipped when nowhere near the square. The
  kerbs stage cost 549 ms in pass 1 before them, 1.2 s with them done the obvious way
  (`_fence_line` / `_hedge_line` checking every piece for roads and houses), ~0.85 s now:
  the wall loop records which pieces of the run have the wall (`walled`), and a fence on
  the wall is laid by `furniture.wall_fence` with no checks and no walls of its own (the
  wall is both); a hedge looks only for houses (`roads` false). Of that, the look for the
  nearest road (`_off_road` -> `_nearest_seg`) was the dear part: half the hedges' 300 ms.
- **the builders** -- kerbs and pavements `_build_kerbs`, `_street_runs`,
  `_kerb_run_piece`, corners `_kerb_corners` (checked along their length), the asphalt grid
  `_asph_hash` / `_asphalt_other`; parked cars `_build_parked`, car parks `_build_lots`; the
  map's edge `_build_edge` / `_keep_inside`.
- **batching** -- `_batch_add`, `_flush_batches`, the one material `TONE_SHADER` with its
  `tones[64]` / `tone_fx[64]` tables; `_chunked` and `_add_mesh` route into it while building.
- **lanes** -- `_lane_off(r)` (right lane's line), `_lanes_each_way(r)` (capped by width),
  `_nearest_lane`, `_clear_lane`. traffic.gd's `_lane`, `_lanes_dir`, `_lane_shift` use them.
- **autodrive** -- `_autodrive` (per tick: replanning, pursuit, speed from corners, lights,
  signs, zebras, people, the car ahead via `traffic.lead_on`), `_ap_plan`, `_ap_leg`,
  `_ap_turn_into` (the curve through a junction), `_ap_next` / `_ap_ways` (the ways on),
  `_cluster_exits` (a junction drawn as several points offered as one), `_ap_queue` (legs
  across such a junction), `_cross_tick` (the player's choice), off the road `_way_to_road`,
  lost `_ap_rescue`, stuck for 40 s `_ap_watch`.
- **people** -- walkers `_place_walker` / `_pavement_piece` / `_people_tick`, zebra crossers
  `_send_crossers` / `_zebra_span` / `_away_from` / `_crossers_tick`, the height their feet go
  at `_walk_y` / `_pave_top`, what autodrive stops for `_ap_people_v`.
- **render quality** -- `QUALITY`, `_set_quality` (what each level drops), `_watch_fps` (web
  only) / `_judge_fps` (the rule; testable natively), the soft car shadows `_set_blobs`.
- **where a frame's time goes** -- the profiler: `_p("part")` around each part, hitches
  kept and reported; P or a tap on the fps text shows it.
- **zoom out and pause** -- "the view from above", after the chase cam: `_paused` stops
  `_physics_process` (and the people's AnimationPlayers via `process_mode`, the engine
  sound; traffic is drawn at `f = 1` so it does not rock between two ticks); `_zoom_set`
  (rising pauses, landing resumes unless paused by hand), `_zoom_camera` (blends whatever
  camera was placed toward the view from above over the first quarter of the zoom; near
  plane out and haze thinned with height), `_zoom_pan` / `_pinch_move` / `_zoom_turn`, the
  marks `_draw_zoom_marks`. The quality watcher ignores frames while zoomed out. Gradual
  zooming goes through `_zoom_by` (stops at `ZOOM_MIN`; `_zoom_in_more` counts real time of
  zooming in there, a second lands). While up, `_zoom_far(true)` sets every draw range of
  `ZOOM_FAR_FROM` (380 m) or more to 0 (no limit) -- above `ZOOM_SMALL` only those of
  `ZOOM_FAR_HIGH` (650 m) or more: kerbs, walls and lamps are under a pixel there, and
  lifting them tripled the draws at the top (Givatayim: 898 against 337; driving 296) --
  and puts them back on landing; it catches
  what the background build adds meanwhile by world's child count -- ranges count to the
  middle of a 400 m square, and from up there those cut-offs swept across the screen (the
  user saw buildings' surroundings pop in as the view moved). The low view is kept over the
  roofs with `_bld_top` (walls' heights, kept at load) via `_roof_near`. The minimap follows
  the view (`_draw_map_inner`: `mid`, `yaw`, `r`; `_view_footprint` is the screen's corners
  on the ground) and drops building outlines past r 450 m (a grey blur, and most of the lines).

traffic.gd: `tick` (per car: path, lights, signs, the car or player ahead, standoffs,
`squeeze`), `_next` / `_leg` / `_turn_into` (routes), `_steer_lanes`, `lead_on` (the query
autodrive uses), `push` (the player against the cars).

## Tests

`tests/run.sh <test> [level]` (level 1 Givatayim, 2 Bedford, 3 Ashdod, 4 the test town);
screenshots in `$OUT`. On a cloud container each takes 2-10 minutes: run them in the
background. `tests/README.md` lists them with the last results -- what "good" looks like.
Run the ones near what you change, before and after.

`run.sh` sets `STREETS_BUILD_ALL=1`: the whole city is built before a test starts, as the
tests look all over it (the game itself builds near the start first and the rest while you
drive).

`tests/filmed_spots.gd` stands the camera at chest height on spots from a filmed walk or
drive (`SPOTS=<json>`, the format is at its top) and screenshots each, to set beside the
film's stills. The spots file stays in the scratch directory, never the repo: a filmed
route can start at the user's door. How to get the film and its GPS track in and lined up:
"Filmed walks and drives" in the `real-places` skill.

Two that are not in the list above: `filmed_walk` (level 5: the walk loads, walks itself,
stops at Ha-Meri; shots at the landmarks with the nearest wall, `RECORD=1` saves every
frame) and `steep_ground` (level 4: the car flat out at the mountains eight ways round;
good is 30-70 m past the town's edge, stopped by "steep ground").

Before anything: `tools/check_script.sh res://game/streets/streets.gd
res://game/streets/traffic.gd res://game/streets/furniture.gd` (seconds).

## Seeing what the car did: the drive recorder

`drivelog.gd` keeps the last two minutes, ten times a second: the car (where, heading,
speed, steering, gear), autodrive's lane ahead and what held its speed down (`_ap_why`:
limit, curve, light, sign, zebra, people, car, blocked, choice), the car ahead, every
traffic car within 50 m and what holds it, and events (hits, rescues, junction choices,
quality steps, buses passed). The perf view's second page (P twice, or the fps text tapped
twice) draws it as a map; "save log" there downloads it (a browser) or writes it under
`user://drive_logs/`. Ask the user for that file when they report bad driving, and draw it:
`python3 game/streets/tests/drive_log_map.py file.json` -- the streets, the track coloured
by speed, the plan every 2 s, the other cars, the events, and a strip of speed against time
coloured by what held it. Then stage that spot in a scene test.

## The driving exam and the test trip: the loop for driving behaviour

`tests/run.sh exam <level>` drives autodrive from the start and three more places spread
over the town (`EXAM_STARTS`, `EXAM_SECS`), with the traffic and people about, and counts
per minute what went wrong: autodrive stuck, hits by kind, off the asphalt, left of the
middle, red lights run, rescues, harsh braking (split by what it braked for), and for
traffic stalls, overlaps and red lights. Then the worst places, with drive logs saved for
the first ten (`user://drive_logs/exam-*.json`). Fix the top of the list, run it again,
and draw both printouts with `exam_chart.py`. `tests/run.sh door_to_door 1` is the same
for one trip as a player makes it ("go to" an address): arrived or not, time, every
standstill and what held it, a log every two minutes and a screenshot every 30 s.

What each round found, so far:
- A divided road's junction is several signalled points 10-30 m apart; each picked its own
  main road and they disagreed (green both ways across the knot: 43 red lights run by
  traffic a run in Ashdod). The points within 40 m now share one main road and groups.
- Red or green was looked up by the direction of the stretch the car was on at the moment
  (mid-turn, diagonal), not the way it came in: now the arrival direction, 6 m back.
- "Go to" planned from the way the car faced only, and from the nearest street as if the
  car were on it. From a house at a dead end it planned on to the closed end and a U-turn
  there (no cost for the turn), swung round into the fence, and crept along the footpath
  beside the road into its bollards for a minute and a half. Now: both ways out, never
  "to the end and straight back", and off the road the way back onto it comes first.
- A bus pulled in at a stop: autodrive went round it by a whole lane, which on a two-way
  street put it over the middle. Now to the inner edge of its own side, or it waits.
- Free autodrive's U-turn at a dead end was a corner a few metres across at 2.5 m/s: it
  swung past the end onto the footpath beyond and drove along it at 40 km/h (the exam's
  "18.8 m off the road" and most of its "left of the middle"). Now `_ap_next` marks the two
  turning points with speed 0 and `_autodrive` steps past them once stopped, so the
  turn-round-on-the-spot rule takes it. Traffic avoids dead ends (`_dead_end` in
  traffic.gd); it turned round in them in queues and overlapped there.
- Plans started at the nearest point of the road's centre line: the car drove diagonally
  from the middle to its lane over the whole first stretch. Now from its lane.
- The test trip's one bump: a garden wall of a side street running alongside a main road
  lay across the main road (checked by the garden strip's middle only). 41 walls in
  Givatayim stood on a road (garden walls at bends and across neighbours, OSM fence pieces
  checked by their middle); `tests/walls_on_roads.gd` counts them, now 0.
- Ashdod's red lights run by traffic were mostly one junction (Sderot Herzl x HaGdud
  HaIvri, five signalled points 5-15 m apart): its points shared groups but not an id, so
  a car clearing the junction in the all-red was counted again at the next point; and a
  car stopped for a zebra a little over its stop line took itself for committed and drove
  on through the red once the people had crossed. `_sig_knot` gives a junction's points one
  id; over the line counts as through only when rolling or in the junction.
  `tests/knot_lights.gd` watches one junction and prints what each car that ran the red
  saw before (5 of 40 on red, now 1 of 17).
- Main roads get the longer green (18 s, side streets 13 s, was 14 each): group 1 at every
  junction is its main road. 20/11 first: with drivers who take a moment to pull away, a
  side street's queue got two cars through a green, and the test trip waited 97 s at one
  junction.
- Traffic drivers have character (`_driver` in traffic.gd: one easy-to-brisk dial with
  noise -- pull-away, standing gap, headway, reaction, drift in the lane), pull away with
  the push building up, and their bodies dip, lift and lean (drawn only). Each car's
  moment to react starts when the car in front is really off (1 m/s): from when it had
  rolled a few millimetres, a whole queue went within 0.3 s (`tests/queue_start.gd`).
- At a signalled junction the lights decide: a car gives way only to one already in it,
  and turning across, to one coming with its green. It gave way by road rank, as at an
  unsignalled one, to a main-road car about to stop at its own red -- the drive log's
  "what holds each car" showed it (light, car, junction, light).
- At crossings without lights, a stream of people kept cars 20 s+; once a car has stood
  there 6 s the next person lets it go (`_kept_waiting`).
- Test drives 6 and 7 each found a bump: a car waiting crossways with its nose in the turn
  (`lead_on` now samples a car's nose and tail), and a 1.5 m road at a junction that turned
  the "lane's way" backwards (`lane_dir` now over 5 m of the plan). And a wrong 'unstuck'
  lift after 40 s in a slow queue at a red (`_in_a_queue`).
- Queues at a green (`tests/queue_start.gd`, KNOT_AT="-800,-288" in Givatayim): all at
  once at first (a train), then far too slow (third car 9 s); the follow gap now on the
  slower of the two speeds.
- The exam's own counts were off twice: harsh braking per frame (30x one stop) and traffic
  reds judged at every signal point of a junction by the heading mid-turn. Check what a
  counter counts before chasing its number.

## Numbers to compare against (November 2026, cloud container, software renderer)

- Build time in full: Givatayim ~6 s, Bedford ~9 s, Ashdod ~15 s, the test town ~1.2 s
  (the container is slower than a laptop by ~3x; compare ratios). Before the car is shown,
  near-first: Givatayim ~2 s (9 of its 71 squares), Bedford ~1.2 s, Ashdod ~2.8 s, the test
  town ~1.2 s (headless playtest, `build_ms` in the "city" event); the rest of Givatayim
  ~10 s of background building (the "city_built" event).
- Draw calls at the start view: Givatayim ~290, Ashdod ~420 (`tests/draws.gd`), before the
  city was built in squares; since, Givatayim 235 with all of it built (little things are
  grouped per 400 m square, not 220 m) and 200 at the start before the rest is up.
- Givatayim: 140 roads narrowed to their buildings, 865 building fronts cut back, 3
  buildings left over a road on purpose (passages). Ashdod: 44 and 352.
- Corners laid piece by piece (touching another road): Givatayim 920, Ashdod 2794.

## Cities

| Level | City | Bake (`bake_city.yml` inputs) |
|---|---|---|
| 1 | Givatayim (look "med") | place "Givatayim", margin 250 |
| 2 | Bedford, Nova Scotia ("north") | place "Bedford, Nova Scotia", include "Hemlock Ravine Park; Kearney Lake; Sandy Lake; Fleetview Drive" |
| 3 | Ashdod ("med") | place "Ashdod" |
| 4 | Kiryat Dimyon, made up | `tools/fake_city.py` |

The start points are public street corners named in `LEVELS`. **The web build is public:
never use an address the user has mentioned as theirs or their family's -- not as a start,
not in a test, a commit or a doc.** Scratch tests against one stay in the scratch directory.

## What a filmed walk showed (November 2026)

A walk filmed with GPS along a quiet residential street and a shopping street in
Givatayim, set beside the game from the same spots (`tests/filmed_spots.gd`). The layout,
the zebras at the right corners and the lights at the main road matched. The rest, biggest
first:

- **Buildings**: the game's are white-grey boxes with dark window bands and black ground
  floors. The real ones are warm cream and sand plaster, balconies with railings (many
  closed in), AC units on the walls, shutters, shopfronts with awnings on the shopping
  street; 15-25 storey towers stand behind the low blocks.
- **Between pavement and building**: front gardens behind low rubble-stone walls, often
  with a wooden plank fence on top, hedges, bushes, iron gates. The game has a low white
  wall and grass, or the building right at the pavement.
- **Pavement**: the game's is near white in the sun. The real one is mid-grey: 20 x 10 cm
  pavers in straight rows along the residential street, with a darker band along the kerb;
  rounded brown "antique" pavers with grey cobble arcs by the cafes. Herringbone is right
  for some streets, not all.
- **Kerb paint**: blue-and-white along the residential street (paid parking), red-and-white
  at the corners and driveways. The game paints yellow-and-black.
- **Parked cars**: an unbroken row on both sides of the residential street, motorbikes and
  scooters parked on the pavement; painted bays on the shopping street. The game has gaps.
- **Street trees**: thin trunks in square earth pits at the kerb edge every ~8-10 m, the
  canopies meeting over the pavement; no palms on these streets.
- **Light**: the real late afternoon is hazy and warm; the game's sky is saturated blue
  with cartoon clouds and its sunlight bleaches the ground.
- **Small things**: black bollards with a yellow band along the kerb by the main road, a
  red fire hydrant, a push button on the walk light's pole, bar stools and awnings rather
  than umbrellas outside the cafes, green bins.

## The filmed walk (level 5)

A walk filmed on a phone in Givatayim, from Katzenelson by the Ha-Meri passage to Ha-Meri
past Sheinkin, replayed in first person (`_film_begin` / `_film_tick` / `_film_at` in
streets.gd, "a filmed walk, replayed"). It is how that street is being made realistic: a
pass at a time, biggest differences first, each pass checked with a side-by-side video.

- **The route** is `walks.katzenelson_hameri.points` in `cities/details/givatayim.json`
  (written by `make_givatayim.py` beside it):
  [seconds, x, z], the seconds the film's. Landmarks in the film: off the north kerb 1.5 s,
  the far kerb 16 s (so the road there is ~17 m across by walking time; the game's two
  9 m halves are right), the forecourt 25 s, into the passage 33 s, out of it 64 s, the
  corner of Sheinkin 80 s, over it 90 s, into Ha-Meri 93-96 s. The game's pavement from the
  zebra to the passage is ~7 m longer than the film's, so the walk hurries there (2.2 m/s).
- **The walk starts where its film does**: `_find_start` puts `_pos` at the walk's first
  point before the city is built, so the squares round the walk go up first. Before that
  the game built round the middle of town and the walk's first seconds crossed bare grass
  (and a scene test jumping along it shot empty ground).
- **The passage's coordinates** were worked out along its own line: S0 (667.9, -653.0) on
  Katzenelson to S1 (611.3, -588.2) on Sheinkin (both baked nodes); a point is `s` metres
  along it and `off` to the south-east (negative: north-west). Walking it south-west: the
  stone wall, wooden fence, bin and hedge are on the right (north-west), the low white
  fence on the left; the passage ends at s = 58 and a short street (parked cars, the
  walker on its north-west pavement) runs on to Sheinkin. The corner building stands only
  2.7-3.5 m south-east of that street's line.
- **The side-by-side.** The film reached the session as a 100 s clip under 10 MB (VLC
  transcode, emailed as an attachment: the connectors will not hand over anything bigger,
  nor a video from OneDrive at all). It is not in the repo and must not be: a new session
  that needs it asks the user for it again, or fetches that attachment through the mail
  connector if the session has one. Everything else a pass needs is here. That clip came out **mirrored** (a shop sign read
  backwards): flip it (`hflip`). Record the game's half with
  `GODOT_ARGS="--fixed-fps 10" STREETS_BUILD_ALL=0 RECORD=1 OUT=... game/streets/tests/run.sh
  filmed_walk 5` (1280x720; about 1 frame a second in the container: 15 minutes), crop the middle 406x720
  (the 70 degree vertical field of view then matches a phone held upright) and `hstack` the
  two. The film itself is the user's: it, its frames and anything past Ha-Meri never go in
  the repo.
- **Crossing like a person (pass 3).** The film waits at Katzenelson's north kerb 1.6-4.5 s
  looking left (a white SUV goes by), crosses the near half, waits on the median 8.7-13.3 s
  looking right (cars stop at the zebra; one drives on), and is at the far kerb at 17 s;
  at Sheinkin it looks right, then left, then crosses. The walk does the same: two points at
  one spot are a wait (`_film_at` holds there, and keeps the curve from swinging past the
  stop), `looks` turn the head (`_film_look`, the camera only), the head also leads into
  every bend (where the walk is 3.4 s on against 1.6 s), `zebras` put the walker in
  `_zebras_on` while it waits or crosses (`_film_on_zebras`, after the crossers rebuild
  the list; tagged so last tick's go) and `cars` send a car at a second
  (`Traffic.send`: the car furthest away, not a bus, onto the road nearest the spot, that
  way). The game's halves of Katzenelson are 9 m: the walk crosses each at 2.3-2.5 m/s to
  keep the film's times; the film's own speed suggests the real halves are narrower.
- **The film's clock is decoding from its start.** `ffmpeg -ss` before `-i` lands on the
  wrong frames in this clip's first seconds (VLC's variable-rate transcode: 2999 frames in
  100 s, said to be 60 fps); `-vf trim=a:b,setpts=PTS-STARTPTS` agrees with the
  side-by-side's own clock. A contact sheet cut with `-ss` showed the crossing over at 3 s.
- **Pass 2, the forecourt (film 17-34 s)**, done: the block at the passage's north-west
  corner got its arcade along Katzenelson (OSM's outline is the upper floors': the walk ran
  1.3 m inside it, through a wall drawn only from outside), shops behind the columns (never
  pilotis); charcoal herringbone under the arcade and pale poured slabs over the forecourt,
  level with the pavement; a row of bollards across it, the twin-pole transformer on its
  plinth, the barrier across the next block's drive, a globe lamp, a manhole; seventeen
  motorbikes and scooters nose to the kerb along the arcade (a gap where the walk comes up
  off the road), two more in the forecourt; the planted bed behind the white fence and the
  trees over the passage's mouth.
- **Pass 4, Katzenelson's crossing and the passage**, done: Katzenelson's halves set to 7 m
  (roads.set: two lanes each; the baker's 9 m made the walk sprint), the walk's kerbs, median
  and zebra stretches moved with them; white hoop railings either side of the zebra on both
  kerbs and the kerb painted red-white 10 m each way (kerb_paint: pieces laid over the
  city's kerb in the kerb shader's colours; a whole road's paint is roads.set's `kerb`); the
  passage paved in small grey pavers in rows across it (the tone shader's kind 7), level
  with the forecourt; its wall rough grey stones on a mortar backing; tall planting both
  sides (shrubs: the trees' leaf-card crowns on the ground, 2.4-3 m) and four more trees, so
  the passage closes in as filmed. Props stand on the higher of the city's pavement
  (`_walk_y`) and the details' own paving.
- **Pass 5, Sheinkin to Ha-Meri and the shops**, done: the film crosses Sheinkin, then Ha-Meri
  on a raised crossing (charcoal herringbone, the zebra painted on it) and steps up its far
  kerb -- the walk had stayed on the near pavement, so its last ten seconds now go that way,
  threading the corner's bollards, sign pole, hydrant and tree pits (POSTS_NEAR lists them).
  The crossing is paving with ramps (`ramps`), the zebra laid on it (`zebra`); Ha-Meri's
  kerbs blue-white (roads.set `kerb`), a 30 in a red ring painted in its lane in (`ring30`)
  and the zone 30 sign on the drivers' right (`zone30_sign`); lit shop fronts in light
  frames under the arcade, the confectionery's sign band dark brown (`shopfront`).
- **Shader kinds**: the tone shader's surface kinds are 1 grass, 2 asphalt, 3 pavers, 4 rough
  stone walls (another session's), 6 the details' slabs, 7 pavers in rows; each tested on
  both sides of its number (see the godot-3d skill: a one-sided test once drew this
  passage as wall stones).
- **Next passes**: the forecourt's slabs may still be too pale in the sun; the shops'
  glass is one even glow (signs with lettering, the confectionery's yellow panels inside);
  white bollards round Sheinkin's corner and its second transformer (the kerb pass put
  bollards at corners: compare with the film); the little street's parked cars and the
  motorbikes along Ha-Meri. People last.

## Off the ground: bridges, tunnels, cuttings, embankments (`decks.gd`)

A road whose city file has `y` (its surface's height at each node, decimetres above the
height grid's base) is a **deck**; its OSM tags say what it is built as (`br` bridge, `tu`
tunnel, `em` embankment, `cu` cutting). Only `tools/fake_city.py` writes `y` so far, so only
the test town has decks; in the real towns a bridge without `y` is drawn on the ground as
before and a tunnel without it is still dropped.

- **One height is not enough.** Everything used to ask `_h(p)`, the ground. Now whatever has
  a level asks `_decks.surf(p, y)`: the highest of the ground and the decks under p that is
  at most `STEP_UP` (1.2 m) above its feet, or the lowest when every one is higher. A car
  keeps its own `_y` (the player's), `c.y` (traffic) and that decides: under a bridge it
  stays under, in the tunnel it is not lifted onto the hill. Over an open cutting the
  ground is not a candidate. The car's physics, pose, slope, air, the chase camera, walking,
  getting out, the driverless car, traffic's placing and drawing all use it.
- **Kept off the ground's builders.** Decks go in `_tile_decks`, not `_tile_roads`, so no
  kerb, parked car, lamp, walker, fence or sign is put along one by the usual builders (they
  would stand on the ground under a bridge or on the hill over a tunnel); `decks.gd` draws
  their asphalt (the game's own `_ribbon` and `_markings`, with `_on_deck` set so `_g3` and
  `_ground_line` take the deck's heights), pavements, parapets, slab, piers, retaining walls,
  railings, the tube and its lamps. Width fitting, building clipping, medians, dual
  carriageways skip decks; the asphalt grid the kerbs check takes only their stretches at
  ground level. A node only decks meet at is left out of `_tile_nodes` (no junction disc).
- **Levels in the lookups.** `_nearest_seg(..., y)` skips roads more than 3 m from y (no y:
  the ground's level at p, so building-time callers ignore a bridge overhead); the car's
  callers pass `_y` (assist, autodrive's planning, the street name on the HUD, back on the
  road). `_push_out(..., y)` checks the decks' walls (each with the band of heights it is
  solid over: a parapet from under the slab to its top, an embankment's wall from the
  ground, a cutting's up to its railing, a tunnel's up to the ceiling) and only checks
  buildings, fences and trees for a body near the ground's level. Traffic skips cars more
  than 2.5 m above or below (`_level`, `lead_on(..., y)`, `push(..., y)`).
- **The ground cut open.** Over a cutting the terrain mesh's triangles are clipped round its
  footprint (`cut_tri`, in `_build_terrain`), and the far-off flat ground plane is put below
  the deepest deck (it showed through the hole). The tunnel's tube casts shadows from both
  faces (its own meshes, not the merged ones) so the sun does not light it inside.
- **Water held at a level** (`areas[].y`, the test town's river) lies at that level, and is
  too deep to drive or walk into (`_deep_push`): the banks were gentle enough to drive down
  and along the bed under the water. Lakes and ponds without a level are as before.
- **Where the heights come from.** The test town's maker knows them: each deck's ends at the
  ground, a bridge straight from bank to bank with a little camber, the flyover's and
  underpass's ramps eased up and down to 6.6 m clear of the boulevard (`CLEAR`), the tunnel
  a straight line between its ends' heights with a 3 m dip, its mouths wherever the ground
  is 7 m over the road (`COVER`). For a real town the heights would have to be worked out:
  OSM tags only the bridge's span (the ramps are ordinary ways, sometimes `embankment=yes`)
  and says nothing of how high; the baker now keeps `layer`, `embankment` and `cutting`.
- **The test**: `tests/decks.gd` (level 4) -- see tests/README.md. Its first rounds found,
  in order: the surface stepped at every joint of a deck (the highest of several nearby
  segments of one road was taken: half the tunnel run airborne), autodrive crawling at
  30 km/h under the hill (its look-ahead probes saw the houses above as obstacles),
  bridges ending on the river bank's slope (the 8 m grid bends the ground a cell past the
  dug channel: a crest past each end, cars took off), a bridge ending 8 m from a junction
  (a turning car clipped the parapet), a 5 cm switch from a cutting's road to the ground
  where it gets shallow (a hop), and ground triangles left whole over a cutting (an edge
  parallel to the hole's leaves a smaller triangle: compare areas, not corner counts).
- **Still to do**: heights for the real towns' bridges and tunnels; pavements at street
  level beside a cutting (the underpass has none); people on a bridge's pavement; the
  minimap draws a tunnel like any street; zooming out from inside the tunnel rises from the
  hilltop (the zoom centres on the ground's height); the heights are whole decimetres, so a
  deck's grade kinks by up to 2% every 5 m (enough for a 2 cm hop off HaNasi's bridge);
  autodrive turning right off the flyover's foot onto HaRakefet clips a crossing railing's
  post on the corner about one run in two (the railing reaches 6 m from the zebra, into the
  corner: a corner-furniture question, not a deck one). Ramps' and cuttings' walls are left
  out of the collisions within a junction's corner (`_walls_of`): there they are a step a
  turning car sweeps over.

## Open problems

- **Scene tests started with `Flow.start_game` (the `tests/*.gd` way) drew no road surfaces
  in Ashdod round its start** (Nov 2026, cloud container): asphalt, kerbs and zebras missing,
  poles, signs, trees and cars there, from 9 m and from 32 m up (`median_nose`). The same
  junction started through the main scene and the sim runner (`--sim=streets`, a
  `change_scene_to_file("res://main.tscn")` script) drew them. Not yet explained; check a
  test's shots for road before trusting what they show of it.

- A kerb fragment is left on the road near a roundabout's zebra in Ashdod (pieces of a
  corner laid one by one, where the probes miss the asphalt by a little).
- Traffic cars do not steer round parked cars; parked cars are placed so the lanes miss them.
- The quality ladder's thresholds are judged from one user's PC and phone; the profiler's
  hitch events are the place to look before retuning.
