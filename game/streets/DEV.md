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
| `cities/*.json` | baked towns (`tools/osm_city.py`) and the made-up test town (`tools/fake_city.py`) |
| `details.gd`, `cities/details/<city>.json` | what a filmed walk showed and OSM lacks, laid over the baked city as it loads (road edits, unmarked zebras, areas, walls, fences, hedges, bins, railings) and the walks themselves; the format is at the top of `details.gd` |
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

Two that are not in the list above: `filmed_walk` (level 5: the walk loads, walks itself,
stops at Ha-Meri; shots at the landmarks with the nearest wall, `RECORD=1` saves every
frame) and `steep_ground` (level 4: the car flat out at the mountains eight ways round;
good is 30-70 m past the town's edge, stopped by "steep ground").

Before anything: `tools/check_script.sh res://game/streets/streets.gd
res://game/streets/traffic.gd res://game/streets/furniture.gd` (seconds).

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

## The filmed walk (level 5)

A walk filmed on a phone in Givatayim, from Katzenelson by the Ha-Meri passage to Ha-Meri
past Sheinkin, replayed in first person (`_film_begin` / `_film_tick` / `_film_at` in
streets.gd, "a filmed walk, replayed"). It is how that street is being made realistic: a
pass at a time, biggest differences first, each pass checked with a side-by-side video.

- **The route** is `walks.katzenelson_hameri.points` in `cities/details/givatayim.json`:
  [seconds, x, z], the seconds the film's. Landmarks in the film: off the north kerb 1.5 s,
  the far kerb 16 s (so the road there is ~17 m across by walking time; the game's two
  9 m halves are right), the forecourt 25 s, into the passage 33 s, out of it 64 s, the
  corner of Sheinkin 80 s, over it 90 s, into Ha-Meri 93-96 s. The game's pavement from the
  zebra to the passage is ~7 m longer than the film's, so the walk hurries there (2.2 m/s).
- **The passage's coordinates** were worked out along its own line: S0 (667.9, -653.0) on
  Katzenelson to S1 (611.3, -588.2) on Sheinkin (both baked nodes); a point is `s` metres
  along it and `off` to the south-east (negative: north-west). Walking it south-west: the
  stone wall, wooden fence, bin and hedge are on the right (north-west), the low white
  fence on the left; the passage ends at s = 58 and a short street (parked cars, the
  walker on its north-west pavement) runs on to Sheinkin. The corner building stands only
  2.7-3.5 m south-east of that street's line.
- **The side-by-side.** The film reached the session as a 100 s clip under 10 MB (VLC
  transcode, emailed as an attachment: the connectors will not hand over anything bigger,
  nor a video from OneDrive at all). That clip came out **mirrored** (a shop sign read
  backwards): flip it (`hflip`). Record the game's half with
  `GODOT_ARGS="--fixed-fps 10" STREETS_BUILD_ALL=0 RECORD=1 OUT=... game/streets/tests/run.sh
  filmed_walk 5` (1280x720; about 1 frame a second in the container: 15 minutes), crop the middle 406x720
  (the 70 degree vertical field of view then matches a phone held upright) and `hstack` the
  two. The film itself is the user's: it, its frames and anything past Ha-Meri never go in
  the repo.
- **Next passes** (seen in the first side-by-side): the forecourt is big plain concrete
  slabs with black-and-yellow bollards, a transformer on twin lattice poles and a parking
  barrier; at the zebra's south end the white hoop railing and the red-white kerb, and the
  game's building there stands too close; the passage's stone wall is rough grey stone and
  its fence darker wood; the corner of Sheinkin is a raised crossing paved in charcoal
  herringbone with the zebra painted on it, white bollards round the corner, another
  transformer; Ha-Meri has blue-white kerbs, a Zone 30 sign and a painted 30 ring; the
  confectionery's front; motorbikes in a row on the pavement.

## Open problems

- A kerb fragment is left on the road near a roundabout's zebra in Ashdod (pieces of a
  corner laid one by one, where the probes miss the asphalt by a little).
- Traffic cars do not steer round parked cars; parked cars are placed so the lanes miss them.
- The quality ladder's thresholds are judged from one user's PC and phone; the profiler's
  hitch events are the place to look before retuning.
