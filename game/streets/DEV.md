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
| `beach.gd` | the beaches by the sea, any town: umbrellas with white chairs facing the water, lifeguard towers, the chairs as seats for `_bathers`; set up from the sand areas and the sea, built per square (see "The beach") |
| `crowds.gd` | people where the street walkers never go: shoppers down a market's walkway stopping at its stalls (lines from `landmarks.gd`'s `_market_line`), walkers and joggers along a beach's wet sand and people standing in the sea (lines and spots from `beach.gd`'s `_people_lines`); pools made the first time a line is near, ticked from `_people_tick` (see "Crowds") |
| `sites.gd` | building sites from a town's own map (the city file's `sites`): printed hoardings round each plot (solid walls), a tower crane over each new building's plot that is tall or 700 m2+ (see "The town's own layers") |
| `landmarks.gd` | a town's landmarks, found by their building's name in the bake (`BY_CITY`: Tel Aviv's Azrieli towers, the Matcal and Marganit towers, Sarona's houses): a glass of their own, a lit crown, a mast or shaft on the roof, red tile roofs; and in every town the red lights on roofs over 90 m at night. Hooks in streets.gd: `_glass` / `_tile` on a building for `_build_buildings`, `build()` per square, `set_night` |
| `rails.gd` | railways: the tracks the city file has (`rails`, `platforms`, `stations`), their beds, rails and sleepers, the platforms with canopies and the station's name, and trains running along them (`tick`). See "Railways" below |
| `cities/*.json` | baked towns (`tools/osm_city.py`) and the made-up test town (`tools/fake_city.py`) |
| `details.gd`, `cities/details/<city>.json` | what a filmed walk showed and OSM lacks, laid over the baked city as it loads (road edits, unmarked zebras, areas, an arcade cut under a block, paving level with the pavement, walls, fences, hedges, bins, railings, bollards, a pole transformer, a barrier, parked motorbikes, trees) and the walks themselves; the format is at the top of `details.gd` |
| `cities/details/make_givatayim.py` | writes the Katzenelson-Ha-Meri walk's part of `givatayim.json`: every detail placed along the Ha-Meri passage's own line, with the film's seconds beside what each came from. Edit this, not those items in the JSON, and run it. The file is shared (the Sheinkin-Sirkin walk and its kerb paint were put in by hand): the script marks what it writes `"src": "make_givatayim"` and keeps everything else on a re-run |
| `textures/` | CC0 photo textures (Poly Haven) and the scripts that made the sky and the leaf atlas; credited in `textures/CREDITS.md` |
| `tests/` | scene tests, see below |

`streets.gd` is in sections (`## ---- name`); `grep -n "^## ---- " streets.gd` lists them.
The ones most often touched, and the functions in them:

- **bridges and tunnels baked per build** -- `prepublish.gd` (run by tools/publish_web.sh
  before every web export, headless; also by hand: `$GODOT --headless --path . -s
  res://game/streets/prepublish.gd`) loads each town and level setting twice: once working
  out Decks.infer and Decks.setup and recording what they did (`_bake_rec`: the city file's
  keys infer changed -- it re-cuts the roads and adds nodes, so roads and nodes whole -- the
  decks' own variables, `_vars_of`, and what setup wrote on each road), once from that record
  (`_bake_use`); it keeps `baked/<town>_<setting hash>.bin` (zstd) only if `_differs` finds
  every variable of the game (but timings and `_dressing`'s `decks_baked`), the decks' and the
  details' the same. Stamped with res://build.txt and hashes of the file, its details and the
  level's settings (`_bake_key`), so only the build it was made for uses it; not committed
  (.gitignore), removed after the export. `STREETS_NO_BAKED=1` ignores it; the city event's
  `decks_baked` says it was used. A change to decks.gd or the loading that the record does
  not carry shows as "NOT baked -- ... differs" in the publish log, and the build works it
  out as before: a lost shortcut, never a wrong town.
- **far shadows after the car** -- a city level (`_far_later`, not a walk or a route, not
  STREETS_BUILD_ALL) draws `_build_far_shadows(true)` from `_build_rest` once the squares
  round the car are up (`_far_now`), its building loops paced like a square's (`_over` /
  `_pause`); the grass is made at load all the same (its shader in the warm-up) with
  `_fs_blank`, a 1x1 picture where nothing grows. `_build_far_shadows` keeps the sun it was
  started for (`ev`): the evening switched on meanwhile keeps its own.
- **loading the city** -- `_load_city`, then `_fit_dual_carriageways` (halves of a divided
  road sized to their lanes, `r["median"]`), `_fit_widths_to_buildings` (widths are guesses),
  `_clip_buildings` (fronts still on a road cut back to road + 1.5 m), `_build_graph`.
- **building the world, near-first** -- `_build_world` does the once-only things
  (`_build_setup`: which roads, nodes, buildings, areas, places reach each 400 m square;
  the park, tree and light set-ups), then `_build_tile` square by square: `_first_squares`
  behind the loading text (a city level: the start's square, any within `NEAR_NOW` 60 m, and
  those the street ahead crosses within `AHEAD_NOW` 160 m -- usually 1-2; a filmed walk or a
  test route: all within `NEAR_FIRST` 320 m, as before, also `STREETS_NEAR_FIRST=1`), the
  rest in `_build_rest` while you drive, nearest the car first -- the rest of NEAR_FIRST in
  a hurry (`_catch_up`: `CATCH_UP_US` 16 ms a frame, the first seconds only, `_catch_up_ms`
  when done), then `BUILD_US` -- every builder stopping when the frame's budget is used up
  (`if _over(): await _pause()`). Two rules keep squares from doubling or
  missing things: what lies along a road or fence is worked out by every square it crosses
  and kept only where its triangles start (`CBuf.clip`, `_near_part`, `_near_span`);
  everything else, and whatever it records (posts, parked cars, lights, tables), belongs
  to the square its spot is in (`_mine`, `_ring_mine`). A builder that is a coroutine must
  be awaited everywhere, or what it builds after a pause lands in the wrong square.
  `STREETS_BUILD_ALL=1` builds every square before the car is shown (the tests do).
  `STREETS_CITY_FILE=/path/x.json` drives that file instead of the level's own (the same
  test on a file from before a re-bake: `tests/real_trees.gd`).
- **looks at street level** -- the pavement is drawn by `KERB_SHADER` in the kerb's own
  mesh (vertex COLOR.b 1: a pavement; COLOR.r the street's paving, `_set_pave_code`;
  COLOR.g its leaves, `_leafy`; UV metres along and out from the kerb), so it costs no draw
  of its own; the kerbs are built after the trees for the leaves. A block's ground floor
  (barred windows, the door in the middle bay), stone courses, plinth and mosaic are
  `WALL_SHADER`'s `ground` / `door` / `stone_k`; worn asphalt is `TONE_SHADER`'s
  `crazing()` and patches. `tests/eye_level.gd` puts a camera where a person stands.
- **night lights** -- GLOW_SHADER (additive, unfogged, `skip_vertex_transform`) draws the
  pools (`_pool`, at pavement height + 3 cm), the headlight beams (`_beam_mesh`) and halos
  (`_halo`: a quad whose vertices all sit at the light, UV2.y 1, turned to the eye in the
  shader, never under ~1% of the distance across): the lamps' halos go in the pools' mesh
  (`_make_pools`), the headlights' in the beam mesh the player's car and the traffic share
  -- no draws of their own. Lit shops' light on the pavement: `_shop_lights`. The night's
  colours: the night branch of `_retint_city` (a little of the palette's player colour, not
  half of it). Shop glass at night 0.85 (2.0 clipped to white).
- **front gardens split out of loading** -- while the squares round the start are built
  (`_gardens_split`), `_garden_fronts(..., part)` lays only the plots within GARDENS_NOW
  (120 m) of the start; each run side is remembered (`_gardens_later`: square -> [run, hw,
  sgn, key, walled]) and `_build_gardens_later` lays the rest first thing in `_build_rest`,
  nearest square first, with their yard cars (`_draw_parked`). Same plots, same keys.
  tests/gardens_later.gd (and STREETS_GARDENS_SPLIT=0 for the old way): Givatayim's 6 start
  squares 7510 wall pieces and 858 board points both ways; the gardens' part of loading
  678 -> 128 ms (kerbs 1.47 -> 1.03 s); the rest there 1.2 s after the car appears.
- **the street's goings-on** (traffic.gd) -- a van or truck (DBL_SHARE of them) gets a
  delivery stop `dbl_s` ahead when it starts; `_double_park` puts it off past junctions,
  zebras and roads not in DBL_ROADS, pulls it in toward the kerb as far as there is room,
  stands it `dbl` s with hazards (blink 2: the blinkers multimesh has four lamps a car
  now). A follower on a two-way street of one lane each way with it ahead (< 35 m) and
  `_oncoming_clear` takes `pass_i`: `_steer_lanes` shifts it `_pass_shift` (over the centre
  line) until past; on wider roads the old "out to pass" does it. Autodrive: `_ap_pass_bus`
  takes a double-parked van too, and on a one-lane street goes over the line when the other
  way is clear 45 m past it -- waiting 4.5 m further back than behind a car (room to pull
  out), its plan given a point every 2 m first (`_ap_densify`) and the bend measured from the
  car, not the plan's first point (on a straight street that can be 40 m back: the bend
  landed behind the car and nothing moved; buses had the same bug). `_kerb_tick`: every 35-75 s, while driving a street in
  DBL_ROADS of one lane each way, the furthest car out of view is parked at the kerb
  90-150 m ahead in a gap among the parked cars (`kerb`), and pulls out (`_kerb_wait`) when
  the player is 18-45 m behind. tests/street_goings.gd.
- **more kinds of people** -- walkers i % 9 == 2 have a dog (`dog_kit`: legs swung by its
  shader from the instance's custom data), i % 9 == 6 a pushchair (`pram_kit`, the carrying
  walk); a multimesh each and one for the leads, positioned by `_companion` in the walker
  loop. SITTERS on `_bench_spots` (park benches) holding the end of SitDown, WAITERS at
  `_stop_spots` facing the road, placed unseen like the chatters (`_place_still`); a sitter's
  origin (the feet) 0.42 m in front of the bench's middle. The three multimeshes have no
  visibility range (it is measured to their middle, the city's: every dog was culled);
  `_companion` hides those past PEOPLE_SEEN. tests/street_people.gd.
- **people round you on foot** (the user, on walk 2's replay: "people are popping randomly
  and moving aimlessly on my path, and no collision between them and the parked cars") --
  `_unseen` (where people may appear or be swapped out) takes the camera's own heading and
  frustum as well as the body's: on foot the head turns (`_film_look`, 60-90 degrees), and a
  cafe table's person was re-seated 2.3 m in plain view. The walkers' "car coming at them"
  dodge skips you on foot (it fired at walking pace: a metre's jump as you passed); you are
  given way to from 7 m instead (the `_people_who == 0` branch of the side step, up to 0.9 m).
  At the end of its stretch a walker walks on (`_walk_on`): the pavement pieces of the runs
  that begin or end within 30 m, the one 1-18 m ahead going on most straight, reached over
  the side street's mouth (not through a building); `cross` is that step's length, walked at
  `_walk_y`'s level. Nowhere on: swapped out if unseen, else back the way it came. Parked
  cars are five posts (`_add_car_posts`): the old two left a 0.8 m gap at the car's middle a
  walker stood in. A crosser's kerb is checked unseen, not only the crossing's middle.
  tests/walk_people.gd.
- **shaders a browser compiles** (`tests/web_shaders.js`: a web export run in the container's
  Chromium, straight into a level by the shell's self-play args, every WebGL program linked
  counted before, during and after `_warm_up`, by material and variant; `tests/shader_kinds.gd`
  lists the built-in material kinds and the game's shaders with who uses them, headless).
  Givatayim: 225 programs (176 in the warm-up, 6 after it while driving), now 205 (156):
  the flags and the ads one shader (`FLAG_SHADER`, `wave`/`rough`), every fence one Shader
  resource (`_fence_shader`), the map edge's barrier and curtain one (`curtain` uniform, the
  barrier's alpha 1). Each game shader costs ~7 programs (alone and instanced, the shadow
  map's depth, and an additive pass: the Compatibility renderer draws a shadowed light --
  the sun -- as a second pass with its own variant, 39 programs of the 205); the built-in
  materials 43 (`_surface`'s plain kind and the glowing one; merging them was backed out:
  `emission_enabled` is what `_tone_of`/`_merge_as` read as "lit, keep out of the batches"
  and several lights switch it at night). The browser's own time per program is not
  measurable here: its status check after a compile also waits for the last frame, seconds
  of software rendering (the 25-line roof shader read 180 ms a program). Count programs.
- **leftovers** -- people out of a parked car's own outline as well as its posts
  (`_car_box_push`, 4.5 x 1.84 m rounded 0.3 m; `_add_car_posts` records it; the car and
  you on foot still go by the posts): walk_people's deepest into a car 0.17-0.27 -> 0.00 m.
  A dog's spot is the first of four (right ahead, left ahead, ahead, at heel) with no fence
  or railing between it and its walker where it ends up after its push (`_wall_between`).
  Garden paths keep the grass blades off (`_grass_cut` at each path, `_grass_cuts_near`
  hands the shader the 24 nearest as the blade grid moves: the grass picture is 1-2 m a
  pixel and drawn before most gardens exist). Walkers who cannot make room for you (a parked
  car one side, a shop's stool the other) take the side with most room, and stop (`hold_me`)
  if that is under 0.6 m.
- **number plates** -- CAR_SHADER's plate branch (vertex alpha 0.65), `plate_style` 1 for
  the "med" look: yellow, black digits in a black rim, the blue IL strip; 8 digits
  (123-45-678) or the older 7 (12-345-67), each car's made up from `plate_id` (its copy's
  INSTANCE_ID and paint: steady while it drives; the player's car `plate_seed`). The digits
  are a 13-glyph font (`PLATE_GLYPHS`, 5x7 bits, smoothed up 8x into `_plate_font`) read
  with the edge at the half-way grey up close and the grey itself far off (`far`, from
  fwidth: taken at the half-way grey, a plate was blank yellow from the chase view). The
  player's car's plates were boxes in a palette material: faces in its car shader now
  (`_sedan_rest`). No real plate, none from a film, is ever used. tests/plates.gd.
- **cars, more real** -- body kinds as Israeli streets have them (CAR_SHAPES + CAR_MIX):
  "mini" (a 3.6 m city car), "wagon" (an estate), "mpv" (a tall boxy small van) beside
  sedan, hatch, suv, van; each kind is listed in the parked squares' `xf_by`, traffic's
  LENS, CORNERS and kinds loop (a multimesh each: a draw a kind a square). All in CAR_SHADER
  (no new shader): the car's own `plate_id` picks its rim (five spokes, twelve fine, ten, a
  steel wheel's cap; a dark alloy now and then; the brake disc and nuts), how dusty it is
  (more parked: no one in it, custom alpha under 1.5) and how sun-faded (the oldest fifth),
  scuffed bumper corners, a folded silver sunshade behind a parked car's windscreen (45%);
  tyres' sidewalls a shade lighter. Parts a few cars have are in every car's mesh and
  folded away in vertex() on the rest (vertex alpha 0.52 a learner's roof sign with a
  lamed, 0.54 a new driver's sign in the back window, 0.56 a parking permit on a parked
  car's windscreen; UV2 their middle, for the shader's drawing): no draws. Wiper arms, a
  shark-fin aerial, roof rails on an SUV and an estate are trim in the body. The paint mix
  has more white and silver and a dark green -- appended: a film's car asks traffic for a
  paint by its place in `_car_paints()` (white 0, silver 4, grey 7, black 9, blue 11, red
  12). tests/plates.gd shoots them (ends and a side). Cost: the three kinds are ~10 more
  multimeshes in view at the start (`draws`: 216; about 3 a kind, parked squares and
  traffic); the playtest 10 hitches alone (17 with a second Godot rendering beside it).
- **cars' lights and moving parts** -- all in CAR_SHADER and traffic.gd, no new shader.
  A copy's instance data (`Traffic._custom`; the shader's notes at its top): the paint in
  rgb with a small whole number in each channel as twice it added (the paint stays 0..1 under
  it; decoded `kk = floor(rgb / 2)`, half floats keep 1/128 of colour at up to 15): r the
  indicators lit (1 its left, 2 its right, 3 both), g and b the front wheels' steer (g * 8 +
  b, 32 straight, 0 no word: a parked car's own). Alpha: the brake 0..0.95, 2 per person
  aboard, 8 reversing, 16 the passenger's door open, 32 stood at the kerb (dust, permit).
  "Parked" is now no one aboard (occupancy 0), not alpha under 1.5. `plate_id` and the
  decoded values are `flat` varyings: interpolated, `plate_id`'s last digits wandered across
  a plate and its hashes drew a different digit in each pixel (garbled plates). **Lamps**:
  `_lamp` gives its panel UV (x inner 0 to outer 1, y low to high) and UV2 x 1 marks a car's;
  the headlight is an older car's chrome reflector or a newer one's black housing with two
  lenses and a running-light strip lit while it drives, the indicator's amber at the outer
  end; the tail light a red with its position light's shape brighter (a ring or two bars), a
  white reversing light over an amber indicator at the inner end; UV2 x 2 marks the mirror
  repeaters (amber) and the third brake light at the top of the rear window. Lit colours
  are saturated uniforms (`amber_lit`, `red_lit`, from `_real_col`) at under 2: brighter,
  the sun's tone curve took a brake light to white. A bus's, a truck's and a scooter's
  indicators are still traffic's `_blinkers` boxes. **Steering**: the wheels' UV2 is their
  middle; vertex() turns the front ones (UV2.y > 0) about it. Traffic's `steer_to` is the
  lane its front runs on against its heading (`_place`), turned toward at 1.4 rad/s; a
  parked car has its wheels turned now and then (its own `plate_id`). **The kerb car**
  (`_kerb_tick`, `_kerb_wait`): KERB_BOARD of them have someone getting in beside the driver
  first -- the passenger's door open over the pavement (`_door` multimesh, the car's own
  slot so its dust matches; `g._door_mesh`, `g._door_at`: the hinge at the seam behind the
  front wheel, as the shader draws the doorway), them standing at it (`g.boarder_at`, one
  Actor3D in `_boarders`, counted among the people); they step in as the player comes within
  95 m (BOARD_IN 1.1 s), the door shuts (0.7 s), then it waits for the player at 18-62 m
  behind (was 45), backs up 0.27 m with its reversing lights if there is room (`rev_t`),
  signals and pulls out. The kerb side, not the driver's: a door open into the lane was in
  the traffic's way. **Bumps**: `_street_metal` notes each manhole cover and drain grate
  (`_note_cover`, `cover_under`); your wheels crossing one nudge the nose and the side, a
  soft clunk (`_cover_tick`); traffic's front wheels dip its nose, within 50 m of you.
  **The taxi's sign**: yellow, מונית front and back (five Hebrew glyphs added to
  `PLATE_GLYPHS`: the font is 18 glyphs now, read right to left as seen), lit at night;
  vertex alpha 0.58. tests/car_lights.gd (front, back, door, steer, taxi; day and night);
  street_goings prints the boarding.
- **people walking with purpose** (the user: "they are so aimless, maybe make them walk
  coherently first, i think still no collision and they walk through stuff"). Measured
  first (`tests/people_watch.gd`: you on foot on Sirkin, 40 s): nobody inside anything solid
  (posts are nearly everything on a pavement), but 2 walkers in 24 s -- a walker was only
  ever put down 98 m+ away (`_place_walker`), so the street round you stayed empty until
  people walked the whole way in. Now: put down 22-135 m off wherever unseen -- `_unseen`'s,
  or behind a building from the eye (`_spawn_ok`, `_behind_building`: the sight line sampled
  every 1.5 m against the footprints), at a few spots along the piece -- and taken away
  the same way at a dead end; WALKERS 24 (was 18, +6 draws). Their place across the
  pavement is planned 1-3 m ahead (`_walk_lane`, every 0.4 s: the offset clear at all three,
  the nearest to now, kept while clear) instead of a step round each post 1.3 m ahead and
  back (they wove round every tree). Kept apart (`_people_apart`: half the overlap of
  anyone within 0.55 m, each tick). Two walking together (`with`/`mate`, `_walk_beside`:
  i % 4 == 1 with the one before, not a dog's or a pushchair's -- 5 pairs of 24): beside
  the first on its line, the same side as they turn back, a step behind where there is no
  room, or to pass you on foot; seen with it, put down with it at once (sliding there,
  they were 22 pops in walk_people). Walkers past PEOPLE_SEEN + 12 m are brought back round
  you (were left out to 150 m: half the street's people walked where nobody was drawn).
  With you on foot: the step out of your way replaces their planned place (added to it, a
  place 0.6 m one way took most of a 0.9 m step back, and one walked half a metre beside
  you for 2 s), kept till 2 m past you (one cut in just in front), up against a hedge if
  need be (elsewhere a step aside is cut to the room there: `room_at`), never nearer than
  0.6 m; waiting for you more than 4 s, back the way they came. **Jumps in view** (21 Nov,
  validation on main: walk_people FAIL, 2 walkers jumping 1.6-2.5 m 45-57 m off; here 1 in 7
  runs of walk 2 from 45 s): a walker's place across the pavement (`lat`, up to 0.9 m) is
  measured from its line the way it walks, so turning back (at a stretch's end in view, or
  after waiting 4 s for you) or stepping on to a new stretch (`_walk_on`) flipped or turned
  `right` and the same `lat` put it up to 1.8 m across in one tick -- now `lat` is carried
  over as where it stands (`turned`) and eased to the plan; and `_place_walker` kept the old
  life's `lat`, `lane`, `dodge`, `at`, so a walker put down out of sight round a corner was
  drawn up to 0.9 m beside the spot checked, in view -- now reset. After: 0 pops in 12 runs
  (seeds 1-14). The test's "close" counts under 0.58 m now (0.6 is the floor walkers are held
  at; a push off a post after it left one at 0.599 and failed a run). tests/walk_people.gd counts
  someone behind a building as unseen (`_behind_building`).
- **signs bent by the car** (`_bend_sign`, SIGN_BEND_V 4 m/s): street signs are merged into
  the batches, so the one hit is hidden in TONE_SHADER (`gone`/`gone_n`, up to 12: what
  stands within 0.8 m of its pole from 0.35 m to its top is squashed onto a stub) and a bent
  copy -- its pole and plate, 2 draws -- stands in its place, put back as the knocked bins
  are. `_signs_at` (post -> kind, plate, pole) from `_build_street_signs`' plant. Slower than
  4 m/s a sign still stops the car. tests/crash_things.gd drives at the nearest one.
- **indicators in every vehicle's lamps**: the bus's front and tail lamps are car lamps now
  (`_lamp_quad`: UV and UV2 x 1), with repeaters on its sides; the truck's tail lights on
  its box's back (its cab's were hidden behind it); a scooter's four small amber repeaters.
  Traffic's `_blinkers` boxes went (one draw).
- **blocks' plaster by age** (`_med_plaster`, med towns): the city file's year (`yr`, 920
  of Givatayim's 6,243) and OSM colour (`col`, 63) pick a block's plaster: 1950-79 sand
  (most), before 1950 cream, 1980-99 beige, white or stone, 2000 on white, stone-clad or
  grey; no year, mostly sand. WALL_SHADER: a stone lean of 0.4-0.79 is now a render in the
  old blocks' sand (`wall_g`, the tone "wall7": the stone's beige deeper toward the yellow
  with a touch of red -- the stone mixed with the peach plaster read grey-beige, with the
  yellow khaki; `_wall_rgb` the same), only
  0.8 and over is cut stone in courses (it was 0.45: two blocks in five were stone-clad;
  the film's are rendered). Balconies: per bay and floor some closed in (`enclosed`: a share
  of each block's, 20-70%) -- sliding panes in aluminium on the parapet, a shutter part-way
  down from its box, the room behind (near), glass and the box (far); the parapets and slab
  edges a white band on some blocks (`band`); the grime under sills darker on the old blocks
  (`aged`). tests/building_looks.gd (the town's count, six blocks near the start).
- **shop interiors** -- SHOP_SHADER on the shop windows (`_shop_interior`, instead of the
  flat lit `_shop_glass`): a room 3.5 m deep traced from the eye through the glass (back
  wall, sides, floor, ceiling -- no geometry), shelves of goods, racks of clothes or a
  cafe's counter and menu board by the instance colour's red (`glass_k`: 1 cafes, bars,
  restaurants; 0.6 clothes, shoes; 0 the rest), a strip light, the sky's sheen at a glance;
  `lit` 0.45 by day (a shop is dimmer than the sunny street), 1.4 at night. One shader
  more for a browser (~7 programs). tests/shop_fronts.gd (also counts shopkeepers: 3 of 44
  doorways round the start).
- **what breaks, more** -- a knock on a wall or a building at over 2.5 m/s leaves streaks of
  rubber and paint on it at bumper height (`_scrape_at`, 8 kept, 4 minutes); hedges are soft
  walls (`add_wall(..., soft)`, `_wall_soft`): no bounce, dent or glass, the car held to 70%,
  leaves fly (`_leaves_at`, the sparks' material kind). Signs bending was not done: they are
  merged into the batches, and each kind knockable would be a draw a square.
- **shops that look open** -- KEEPERS (3) people stand in open shops' doorways near you
  (`_shop_spots`, placed unseen like the waiters, `_place_keepers`); an A-frame board out in
  front of ~40% of the open shops (`_a_board`, into the crates' mesh: no draws); corner
  shops and kiosks put out crates as the greengrocers do. Lit interiors seen through the
  glass were not done (a textured glass is a new material kind to compile).
- **people in one piece** -- `_one_piece` (end of `_humanize`): the Quaternius figure is one
  mesh of six surfaces (Skin, Shirt, Pants, Belt, Face, Hair), each a draw (and a shadow
  draw). Joined once per figure into one surface (shared by everyone with that figure; the
  part's number in the vertex colour's red), drawn with PIECE_SHADER whose `parts[6]` are
  that person's colours (linear: `srgb_to_linear`), its distance dither done by hand
  (`fade_from`/`fade_to`, set by `_people_lod`). tests/draws.gd at the start: 217 -> 180
  draws, people 48 -> 8. `_shader_key` keys them all as one kind for the warm-up.
- **on the walls** -- `_build_facade_kit`: AC units (`furniture.ac_kit(0)`, ~130 vertices,
  on arms under a window's sill or up on a balcony's back wall; at most 4 a block), washing
  racks (`washing_kit(0)`, under a sill, tinted per copy), towels over parapets
  (`towel_kit`, coloured per copy). The AC units and racks are drawn instanced
  (`_instanced`: a MultiMesh per square, a draw or two near you), not merged: merged, the
  first version (~19,000 AC units of ~230 vertices, ~2,000 racks of ~400 city-wide) made
  the batches fat -- 19 hitches of ~50 ms in a 25 s playtest while the city built behind,
  from 3. The towels (few) are merged. `wall_things` keeps 200 of each for
  tests/wall_things.gd.
- **street sounds** -- `_build_street_sounds` / `_street_snd_tick` (called from
  `_engine_tick`): birds and crickets are 2D loops, the voices and the dog 3D players (at the
  nearest TALKY place or shop within 70 m; at a random point 45-120 m off every 35-100 s
  where `_liveliness` > 0.15). Levels worked out twice a second, eased at 10 dB/s; in the
  car 7-16 dB quieter. A 40 m grid of tree counts (counted as each square plants its trees:
  most street trees are planted by the game, not in the city file) and of talky places
  (from the city file at load, before it is let go). The WAVs are made by sounds/make_sounds.py; a new loop
  needs `edit/loop_mode=2` in its .import (Godot does not loop a WAV without loop points).
  tests/street_sounds.gd records day and night to listen to.
- **what breaks** -- knockable things (bins, recycling, bollards) are placed by
  `furniture._place_knock` into multimeshes of their own (`_knock_add`; `_knockable`: post
  index -> [multimesh, copy, transform, mesh, "tumble"/"bend", radius]), not the batches, so
  one copy can be hidden or bent: +1-3 draws a square near you. `_collide` hands a
  knockable post to `_knock` (the car let through, slowed a little or, a bollard, a lot);
  "tumble" hides the copy and throws a RigidBody3D (its mesh, a box shape, a 40 m slab to
  land on -- the city has no physics of its own); `_knock_tick` puts it back after
  KNOCK_BACK_S once you are 70 m off. `_light_thing`: the assist does not brake for bins.
  `_sparks_at` (one CPUParticles3D, reused), `_glass_at` (a mesh of shards, 6 kept, 90 s),
  `_dent` (CAR_SHADER's `dents[4]`, the player's material only). `tests/crash_things.gd`
  (assist off, else it brakes first; a person waiting by a bollard stops the car short).
- **load, part by part** -- `_part_time("stage: part", t0)` adds to `_stage_ms` while
  loading; `tests/load_stages.gd` lists the parts. Measured headless (what the work costs,
  without the frames drawn while loading): 3.9 s of stages in Givatayim; kerbs 1.7 s, of it
  the front gardens 0.7-0.8 (board fences 0.17, walls 0.14, hedges 0.09, gates 0.15, the
  plot loop the rest) and corners 0.28; the city file 0.55; buildings 0.16 (contact
  shadows 0.08); trees 0.15 (their shadows on the ground 0.05); furniture 0.14; far
  shadows' work 0.17. Under xvfb the "warm up" is 5-7 s, but that is four frames of the
  software renderer: stripping the grass, the contact-shadow layer, the far shade and the
  wet code out of the shaders did not shorten it (5.2, 5.5, 7.1 s: noise).
- **graffiti** -- TONE_SHADER's `graffiti()`: on a face of a tone whose TONE_FX z is 1 with
  kind 0 ("gardenwall", "pole") or a kit's face with vertex alpha 0.3-0.7 (the cabinet's
  body); height above the ground from the height grid (`_set_hmap`, shared with the grass;
  the tone material is made before the grid is read, so `_retint_tone_mat` hands it over).
- **zone and parking signs** -- `furniture.street_signs`: meshes with 7-segment digits
  (`_digit`), not Label3D (a draw each). **Passages** -- `_build_passages` (its own stage).
- **front gardens' walls and gates** -- `_garden_fronts` lays each plot's wall itself
  (`_garden_wall`: rubble in the `wall` buffer, or render + coping in fronts' "plaster" /
  "coping"; its kind and height from the plot's own hash), not the kerb loop any more (that
  only records `walled` and lays the lawn strip). Gates: `_run_gates` (cached per run side
  in `_gate_cache`) finds the doors facing the run -- `_doors_of` works out again, from the
  city's data, the same choices `_build_buildings` makes (style, columns, height), so every
  square agrees whether or not it has built that building -- and the plots end at them.
  `_front_gate`: piers, the path (fronts' "path", tone "slabs", its way in the vertex green:
  `_batch_buf` keeps the green of anything whose first vertex has alpha 0), the arch, the
  yard car (`_yard_cars`, parked with the street's in `_build_parked`). Greenery over the
  walls: fronts' "spill" (crown cards, a post under it when it is low). The kerbs stage
  measured the same with all of it (1.29 s) as without (1.33).
- **pavement covers, tree pits, recycling** -- covers: KERB_SHADER's pavement branch, one
  in a 19 m stretch two times in five (`iron` uniform); the pavement's vertex alpha now
  also says a narrow pavement's width (0.7-0.76: a median's: no covers). Pits:
  `furniture.pit_kit`, four street trees in ten in Israel. Recycling: `furniture._recycling`
  (by one junction in four, kits `_paper_bin_kit`, `_cage_kit`, `_glass_bell_kit`).
- **grass blades** -- GRASS_SHADER on a MultiMesh of 4 m patches (`_build_grass`) whose
  node follows the camera a patch at a time (`_grass_follow`, from `_sky_follow`); a blade's
  three corners sit at its root, the shader grows it where the far-shadow picture's green
  says grass grows (`_build_far_shadows` paints it: 0.5 open ground, 1 lawns, parks, woods,
  pitches, front gardens; roads with their pavements and buildings 0) at the ground's
  height (the height grid as an RF texture, the same triangles as `_h`), by the camera's 3D
  distance (none from up high). Cull off, so it flips NORMAL back on back faces (they went
  black). `_grass_quality`: none below 2, 55% of the patches at 2.
- **people keeping clear** -- `_people_tick` lists everyone (`_people_at`, `_people_who`);
  a walker steers off its line (`lat`, up to 0.7 m) round anything solid 1.3 m ahead and
  away from anyone ahead or alongside (to their other side, the right if dead ahead), then
  two passes of `_push_out` (out of a parked car's one post can be into its other).
  `_people_push`: people solid to the car (`_collide`) and to you on foot, not in
  `_push_out` (which also places things as the city builds). `_crash` makes a person a
  soft knock. People dissolve in over 75-90 m (`_people_lod`, OBJECT_DITHER).
  `tests/people_clear.gd` (7.6% walking into things, 47 too-close: now 0.1%, 2-9).
- **cats, flags on cars** -- the builders call `cat_at(p, y, facing, "sit"/"loaf")` (garden
  walls in `_garden_fronts`, a parked car's nose in `_build_parked`, bins in furniture's
  `kerbside`); furniture.gd's `cats()` places `_cat_kit()` (ellipsoids and tubes, the coat
  an instance colour: `CAT_COATS`, tones `cat_*`), merged into the batches. Flags on parked
  cars: `_car_flags`, `_flag_kit("car", "il")`. A wall cat's choices come from their own
  hash: shifting bits out of the plot's `h` (under 2^20) left nothing to choose with, and
  every one came out sitting. First pass: cats ~12 ms (both models made once), flags ~2 ms.
- **more contact shadows** -- `_ao_disc` at each street tree's foot (not the parks' and open
  land's; one height lookup: ~9 us each, 2,340 in 20-24 ms); along a garden wall's foot the
  pavement itself darkens in KERB_SHADER (COLOR.a: the wall's distance back / 4, set by
  `_pave_walled`): the strips laid as geometry cost 36-47 ms, this nothing.
- **after rain** -- `WET_GLSL` (`wet`, `wet_mirror()`: Fresnel, the sky's two colours, a darker
  band low down for the street's buildings) goes in with `FAR_SHADE` (`_with_far`); the tone
  shader soaks hard kinds (2, 3, 6, 7) and lays puddles by noise, the kerb shader its
  pavement and kerb, the ground shader darkens. `_set_wet` tweens `_wet_k`, `_far_set`
  passes it on. Only the puddles are glossy: a whole road at roughness 0.3 took the
  renderer's flat ambient reflection (the background colour) and went pale grey, and sunlit
  pavers at 0.6 flared white; soaked ground is 0.68-0.7 with SPECULAR 0.3, puddles 0.08.
  The tyres' hiss: `_engine_tick` brightens the road loop and lifts the wind loop with
  `_wet_k`. `tests/wet.gd`.
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
  `_asph_hash` / `_asphalt_other`; paving is laid once (`_laid`, `_laid_cut`, `_laid_by`:
  while a square's kerbs go down, a piece is cut where another street's, side's or corner's
  is already down -- each patterned along its own street, two at one height flickered on a
  phone; `tests/pave_overlap.gd` measures it, Tel Aviv had 19,000 m2 laid twice); parked cars `_build_parked`, car parks `_build_lots`; the
  map's edge `_build_edge` / `_keep_inside`.
- **batching** -- `_batch_add`, `_flush_batches`, the one material `TONE_SHADER` with its
  `tones[64]` / `tone_fx[64]` tables; `_chunked` and `_add_mesh` route into it while building.
- **lanes** -- `_lane_off(r)` (right lane's line), `_lanes_each_way(r)` (capped by width),
  `_nearest_lane`, `_clear_lane`. traffic.gd's `_lane`, `_lanes_dir`, `_lane_shift` use them.
  A traffic car's lane is `lane_i` (0 the right-hand one) and `shift` (metres left of the
  road's lane line, moving to `shift_to`). Onto the next road (`_steer_lanes`, `shift_rd`)
  it takes the lane it is in by where it lies, not by number: roads meeting at a node share
  its middle line, so the second lane of a 12.8 m four-lane link is the first lane of the
  6.4 m slip it runs on into (kept by number, the link's second-lane cars all crossed into
  the slip's other lane and stood on each other: Begin x Kaplan). A shift a road change
  makes is followed at `REALIGN` x the speed (`realign`), not a lane change's 1.4 m/s (at
  that pace a car ran off the slip's edge into its poles for 25 m). Before a narrowing
  (`NARROW_LOOK`, up to the next turn) a car moves to a lane that lies within the narrower
  road. At a light, a turn's curve (`_turn_into`) starts no further out than the stop line
  when coming in from outside the junction, so a car waiting to turn stands straight.
  Sideways only as it rolls: at most `SIDE_PER_V` x its speed, scaled down for a long one
  (`_place` moves the front axle and lets the back trail it, so a shift while standing
  turned the body across the next lane). A car whose `shift` is still heading for its
  `shift_to` stands across two lanes: `_target` counts it in a follower's way by its
  body's half width and angle (`CORNERS`), not by `LANE_W` from its middle.
- **bus lanes** -- the bake's `bf` / `bb` (osm_city.py's `bus_lanes`: a letter a lane, left
  to right, "b" a bus lane) on the road as `r["bf"]` / `r["bb"]`; `_bus_lane(r, idx, dir)`
  (lane idx from the right, never on a one-lane way), `_has_bus_lane`. `_markings` paints a
  wide solid line beside it and `_road_word` "אוטובוס" (BUS outside "med") every
  `BUS_WORD_STEP`; traffic.gd: buses and half the taxis (`bus_ok`) take it, others keep out
  (`_off_bus_lanes`) but for the last `BUS_TURN_IN` m before a right turn; `_lane_off`
  never puts autodrive's line in one. Test: `tests/bus_lanes.gd`.
- **autodrive** -- `_autodrive` (per tick: replanning, pursuit, speed from corners, lights,
  signs, zebras, people, the car ahead via `traffic.lead_on`), `_ap_plan`, `_ap_leg`,
  `_ap_turn_into` (the curve through a junction), `_ap_next` / `_ap_ways` (the ways on),
  `_cluster_exits` (a junction drawn as several points offered as one), `_ap_queue` (legs
  across such a junction), `_cross_tick` (the player's choice), off the road `_way_to_road`,
  lost `_ap_rescue`, stuck for 40 s `_ap_watch`, turning round at a dead end
  `_ap_mark_dead_end` (the stop 7 m short) / `_ap_kturn` (the moves forward and back). The
  map's edge: `_edge_bound` (every way on within `EDGE_LOOK` m runs into the barrier: scored
  down in `_ap_ways`, turned from in `_ap_plan`), `_legs_on`; `_ap_leg` stops a road
  `EDGE_ROOM` short of the barrier, a dead end.
- **traffic lights** -- `_lights_setup` makes SITES: each OSM light taken to its junction,
  the other half of a divided road added (`_other_half`), lit points a short road apart
  (`_site_legs`, `SITE_LEG` 36 m) joined, shortest first, no wider than `SITE_SPAN` 50 m;
  `_site_axes` (group 1 along the main road, group 2 along the road furthest from it, by
  direction, never by name) and `_light_group` (the nearer axis, either way along it; `flip`
  when a neighbouring site needs the road between them in the same group); `_site_ways_in` /
  `_sig_line` (each way in: its stop line -- behind a zebra near the junction, found by
  `_points_back` across OSM's road pieces -- and whether it comes from inside the site: no
  pole, no line); `_light_line`. The cycle is `SIGNAL_CYCLE` (`_MED`: green, flashing green,
  amber, red, red-and-amber; `_NORTH`), `_signals_tick` / `_apply_signals` (the flashing).
  `_light_at` gives what a driver reads ("gf" -> "g", "ry" -> "r"). A car is in a site from
  its nose crossing the line until well out (`_light_site` / `_through_lights` for the player,
  `last_site` / `_passed_lights` / `_in_site` in traffic.gd) and does not stop at its other
  points. Walk lights: `_build_walk_lights`, `_zebra_light` (which point a zebra goes by; the
  people at it ask the same), `_walk_light`, `_box_waiting` (not in front of a car already in
  the junction, waiting to get out over the crossing).
- **the made-up town's mountains** -- `_mtn_from` (`_town_top()` + 6 m: above it the land is
  mountain), the `mountains` part of `GROUND_SHADER` (rock beds, soil, scrub, cloud shadows;
  on every steep slope too), mountain woods in the tree builder (`MTN_TREES`, drawn from
  further off), `_build_turbines` / `_turbines_tick`; the fog halves in that town
  (`_retint_city`). Only a made-up town with hills gets any of it. `tests/mountains.gd` shoots it.
- **traffic islands** -- `_find_islands` (in `_build_setup`): a park, lawn or plaza under
  `ISLAND_MAX` with three quarters of its edge within 3 m of a street's asphalt is an island;
  `_island_cut` takes the roads' asphalt (+0.1 m: its face stands behind a street's own kerb),
  the junctions' discs and the paths through it off it; `_build_ground` lays the pieces at
  `ISLAND_Y` (4 cm under a pavement's top, so a street's pavement over its edge stays on top),
  `_island_faces` the kerb face round them, `_on_island` gives the car the median's jolt.
  Givatayim 19 pieces, Ashdod 41; `tests/islands.gd` checks none is on a road.
- **solid things and the road** -- `_off_road` (a road's edges, and the asphalt a rounded
  corner adds out to its curve: `_in_corner_fill`) and `_in_junction` (the round asphalt at a
  junction's point); furniture's `_free` checks both. The corners' outlines (`_corner_fill`)
  are noted for every corner reaching a square before anything is built in it
  (`_note_corner_fills`, from `_corners_at`, the geometry `_kerb_corners` lays): bollards by a
  zebra near a junction, sign and light poles, trees stood out in them, in front of the kerb.
  Signs are moved across the corner's kerb instead (`_out_of_corner`). `tests/road_blocks.gd`
  finds anything solid on a road's lanes, a junction's asphalt or a corner's.
- **loading** -- the squares round the start are built with the city hidden (`world.visible`)
  and hand a frame back every `FG_US` (`_fg_build`: `_over` / `_pause`), the text ticking;
  `_warm_up` then shows the kinds of surface a few at a time (`_shader_key`; four views only
  under a software renderer), each frame timed in `_warm_ms`; `_load_ms`, `_stage_ms`;
  `_load_text` puts them at the bottom of the perf view, so a player's own load can be read.
  The bar under the text (`_load_bar_begin`, `_load_tick`): phases file / setup / squares /
  warm (`_load_into`, `_load_sub` at each square and warm-up frame), estimated from this
  device's last load of the city in `user://streets_load.json` (`_load_save`: ms per phase,
  per square, the warm-up as on the same build `warm` and on a new build's first load
  `warm_new`, keyed by res://build.txt -- "<UTC time> <commit>", tools/publish_web.sh; shown
  over the minimap by `_build_line`, so a user's screenshot names its build: check a fix
  is in it with `git merge-base --is-ancestor <fix> <commit>`); no history for the city: another city's, the file
  scaled by its size; none: the bar by phase, "timing it, for next time". The city file is
  one blocking call (`_load_city`): the bar stands still through it.
- **people** -- walkers `_place_walker` / `_pavement_piece` / `_people_tick`, zebra crossers
  `_send_crossers` / `_zebra_span` / `_away_from` / `_crossers_tick`, the height their feet go
  at `_walk_y` / `_pave_top`, what autodrive stops for `_ap_people_v`.
- **render quality** -- `QUALITY`, `_set_quality` (what each level drops), `_watch_fps` (web
  only) / `_judge_fps` (the rule; testable natively), the soft car shadows `_set_blobs`.
  Every level keeps the sun's shadows (level 0: 25 m): switching them off recompiled every
  material's shader in the browser, seconds of freeze each time the ladder crossed into or out
  of level 0. Night still switches them off (once, on the button). `tests/hitches.gd` counts
  frames over 250 ms / 1 s driving and from above -- but under the test machine's software
  renderer every Tel Aviv frame takes ~0.8 s, so it shows the script's parts, not a GPU's
  stalls; a browser on the user's machine is the real measure (the perf view's hitch lines).
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
autodrive uses), `push` (the player against the cars). `_junction_ahead` (giving way) skips a
car `_held_at_red`: one that will stand at its red need not hold up a car with the green.

## Tests

`tests/run.sh <test> [level]` (level 1 Givatayim, 2 Bedford, 3 Ashdod, 4 the test town);
screenshots in `$OUT`. On a cloud container each takes 2-10 minutes: run them in the
background. `tests/README.md` lists them with the last results -- what "good" looks like.
Run the ones near what you change, before and after.

**Speed.** `SIM_SPEED=2` (run.sh; `STREETS_SIM_SPEED` for the engine straight) runs twice the
game time a tick, for behaviour counted over minutes while iterating; 1x for how driving
feels and for numbers written down; 3x only to see that something still runs. The measurements
and which test is which: "Faster runs" in tests/README.md. Headless is the bigger saving
whenever no screenshot is wanted.

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

### Validation: one command, and handing it to another session

`game/streets/tests/validate.sh` runs the checks below headless, one after another, and
prints a summary to set beside tests/README.md's last results. It reads the game and
changes nothing. Quick (default): `city_check` in all five towns (Tel Aviv since 21 Nov) and
the exam in the test town at 2x -- about 6 minutes. `FULL=1`: also the exam in Givatayim and
Ashdod at 1x and the queue check -- about 6 minutes more (November 2026, measured: city
checks 10-104 s each, the exams 46 / 89 / 140 s, the queue watch ~3 min). `REGRESS=1` (with
or without FULL): also the eleven tests written for the bugs the user reported on 20 Nov that
need the game run (a drive, a walk, a load), each printing one `REGRESS <name>: PASS|FAIL`
line -- about 10 minutes more. Run it in the background (a foreground command is cut off at
10 minutes).

**When you fix a bug the user reported, its test joins this.** End the test with one line,
`REGRESS <name>: PASS|FAIL -- <measure> <value> (good <band>; the bug: <what it read>)`, the
band from your fix's result and the bug's, and add a `run re_<name> ...` line to
validate.sh's REGRESS list (its level, speed, `EXTRA` settings, `FPS`). If what it measures
is the city as built, put it in `world_checks.gd` and a row in `city_check` instead, so it
runs on every town. On 20 Nov the user reported thirty bugs; nineteen got a test, none was
run again, and the validation of the day before would have caught three.

What it catches: anything solid standing on a road (walls, hedges, posts by kind, buildings),
a junction's lights split in two, and in driving -- bodies overlapping or into a wall or
post, stopping over the line at a red, pushing against something, a car standing with
nothing holding it, queues pulling away unlike real ones. What it does not see: how
anything looks (textures, colours, light, pop-in -- that needs pictures and a person: the
shot tests and `city_check SHOTS=1`), how driving feels (crashes, steering, the camera),
speed on a phone or in a browser (the profiler, `hitches`), the web build itself, the
filmed walks (`filmed_walk SCAN=1`), bridges and tunnels (`decks`). A clean validation says
the town is laid out and drives right by these measures, not that it is right.

Reading it: `city_check` is the same every run, so any change in its counts is real. The
exam is not -- two runs at 1x differed by half on some counts -- so compare against that
spread, not against one number, and look at the places it lists before believing a count.

**Handing it to another session** (say: "in streets, run the validation on the latest main
and report against tests/README.md; don't fix anything"): it should fetch and merge `main`
first (it validates whatever its own branch holds), run the script in the background, and
report the summary. Sessions run in their own containers, so one validating does not slow
another down. Say whether it may fix what it finds: a session that fixes as it goes edits
code other sessions are in the middle of (traffic, the builders), and two fixes to one
corner clash; "report only", or "fix X only", keeps it to one owner. A session that pushes
the README's new numbers publishes `main` (the site rebuilds itself, ~5 minutes); that is
harmless, but it is a push.

**Every night, on its own** (since 21 Nov): `.github/workflows/nightly_checks.yml` runs
`tests/nightly.sh` (validate.sh with `FULL=1 REGRESS=1 EXAM_SEED=1`) on GitHub's machines at
00:15 UTC, and sets its verdicts (the city checks' counts, each REGRESS line) beside the night
before's with `tools/nightly_compare.py`. The run's page (Actions, "nightly checks") shows
what changed in its summary and keeps every output for two weeks; the run fails, and GitHub
emails the owner, only when something got worse -- a new FAIL, OVER or NO VERDICT, or a count
that rose. The exam and the queue check are in the summary, not the verdicts (too noisy to
fail a night on). It commits nothing. A test added to validate.sh's REGRESS list joins it
the next night with nothing more to do.

**The exam's dice** (`EXAM_SEED=n`, exam.gd): seeds the engine's random numbers and the
traffic's before the game loads and again before the drive. Three runs of one build on the
test town at 2x (21 Nov): two read alike to the count (CHECKS 13, every line the same), one
went its own way (11) -- something still not seeded or timing-dependent (threaded loading?),
so a seeded exam agrees most of the time, not always. Unseeded the same build read 4-12.
Compare seeded runs; when two disagree, run a third.

**validate.sh's own `OUT` must not reach the tests** (fixed 21 Nov, `env -u OUT`): for a
test, `OUT` means "save screenshots here", and a screenshot taken headless hangs -- the
first full run had seat_steady, lane_position and deck_corner time out with no verdict.

### The checks that should read 0

A look back over twenty bug fixes (November 2026) found the same few mistakes again and
again, and about half of the bugs made the same day by the change before or by another
session. So there are checks for what must never happen, each one a kind of bug fixed
before, all measured on **bodies, not middles** (`tests/bodies.gd`: a vehicle is a box its
own length and width, a wall a box along all of it, a post a circle -- five of the twenty
were a long thing judged at its middle):

- **The exam's checks** (`exam.gd`, the "check: ..." lines and the CHECKS total): bodies
  overlapping (traffic with traffic, autodrive with a car), a body into a building, wall or
  post, standing over the stop line at a red, autodrive pushing against something 3 s, and
  standing 10 s+ held by nothing named (followed down the queue to its front). Every tick,
  every car. They print 0 when clean, so a reader sees they ran.
- **The city as built** (`city_check.gd`, seconds a city; `LEVEL=0` all five, Tel Aviv
  too): walls, posts and buildings on a street's asphalt (sampled every metre of them), lit
  points that belong to no junction; and the traps to stage a test at -- stub roads under 5 m
  at a junction, lit points under 25 m apart counted as two junctions, walls and posts on
  service roads. Since 21 Nov also the user's reports of the day before that a built city
  shows (`world_checks.gd`, each ported from the test written for its fix): signs doubled, a
  junction offering one street twice, islands on the road, a median's wall over another
  road (0); roads leaning over 6% side to side and two pavings laid over one spot (they
  flicker), under a limit per city (`LIMITS`, the level a fixed city reads: over it, the
  bug is back or was never fixed there).
- **Queues against real ones** (`queue_start.gd`, QUEUE CHECK: PASS / FAIL): start gaps and
  stop-line gaps in bands from real counts (Greenshields 1947, the Highway Capacity Manual),
  not from the last run -- tuned by eye, the queue went from all at once to the third car 9
  s after the green within the hour.

**A fix comes with what would catch it again** -- a scene test that stages it, or a check
here. **After merging** (another session's work, or `main`), before pushing: `city_check`
on the cities the merge touched, the filmed walk's `SCAN=1`, and the exam on the test town
(`LEVEL=4 EXAM_STARTS=2`, headless: under a minute); the exam on a real town when traffic
or autodrive changed. Headless runs take the same numbers several times faster:
`LEVEL=n STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path . -s
res://game/streets/tests/<test>.gd` (no screenshots).

What the checks found on their first rounds (November 2026; numbers in tests/README.md), and
what became of it:
- **Fixed -- a mall's canopy columns in the road** (`_mall_front`: 3.2 m out from the front,
  no road check, fronts cut back to the road's edge + 1.5 m): two 1.9 m into Zahal by
  Ashdod's start, and the exam had a taxi drive through one. The canopy is now as deep as
  the room allows, columns only off the road. Also a fuel station's corner columns
  (`_station_fits`: its middle was checked, not its corners -- Bedford).
- **Fixed -- hedges over the kerb into the lane** (18 in Givatayim, 15 in Ashdod): OSM's
  hedges were laid with a fence's margins; `_open_pieces` takes a body width now (0.4 for
  a hedge). The low garden walls left after that (11 / 3) are fixed too, below.
- **Fixed -- autodrive pushing into a traffic car kept it there**: every touch stunned the
  car 2.5 s (`Traffic.bumped`), so one pressed against never pulled away (a hatch "held by
  the limit" 20 s, then a rescue). Only a knock over 1.2 m/s stuns now; Givatayim's exam
  went from 6 autodrive-into-a-car to 0.
- **Fixed -- a bus pulling in at a stop** moved 0.9 m toward the kerb whatever the room: on
  a 6 m street that is 0.9 m over the kerb, into the stop's pole and the trees. It moves
  only as far as keeps its side 0.3 m on the asphalt.
- **Fixed -- parked motorbikes' solid circle in the lane** (another session's new bikes, an
  hour old: their ends were checked, the 1.1 m circle round their middle was not): Ashdod's
  posts on the road went 12 -> 0 with the columns.
- **Fixed -- traffic's backs over corner posts**: since vehicles steer by the front, the back
  cuts inside a turn by about wb^2/2R; `_turn_into` now swings the arc out by that much
  (capped at 1.5 m), as a driver does.
- **Fixed -- cars that would not roll up**: behind a standing car the moment to react
  waited for it to move off even with metres still to close (one stood 6 m short); now
  only when under ~2 m short, and a car waiting to react stands instead of creeping at
  0.26 m/s. `tests/traffic_stuck.gd` prints such a car's last two seconds tick by tick.
- **Fixed -- two cars changing into one lane from both sides at once** (`_lane_clear` now
  counts a car moving into the lane too), and **a scooter filtering over the line at
  walking pace on amber** stopping on the crossing at the red (moving at all, 0.5 m/s, is
  committed now; it was 2).
- **Fixed -- posts on corners' asphalt**: once `city_check` measured the rounded corners as
  road, 40 posts in Givatayim and 66 in Ashdod stood on one -- light poles mostly (their
  spots were checked against the straight strips only), trees, lamps. Each now keeps off a
  corner's asphalt; a light pole with no clear spot is moved onto the corner's pavement so
  every way in keeps one.
- **Fixed -- garden walls into a road's mouth or a corner**: each point of the wall's line
  is checked with `_off_road` (strips and corners), not only the asphalt grid.
- **Fixed -- a divided road's crossing mid-street split in two**: lit points under 16 m
  apart that no road piece joins are one site now (six on Sderot Herzl).
- **Fixed -- small buildings standing in a road**: a house in the middle of a Bedford
  street, another across one. A building cutting back would take more than half of is
  kept only when it spans the road (past both edges: a passage) or is big (400 m2+);
  otherwise it is left out at load (`_drop_buildings`).
- **Fixed -- gate piers, café tables and cats in the road** (other sessions' work of the same
  hour, caught by `city_check` after a merge): a garden gate's piers stood up to 4 m into the
  next street where the wall's line crossed its mouth (the gate now goes only where both
  piers are off the road); a café table's 0.7 m solid circle reached 0.8 m into the lane
  from a table up against the kerb (the circle now only as big as the room); a cat sat on the
  road by a parked car's nose. Givatayim: 16 posts on the road -> 1; Ashdod 27 -> 0.
- **Fixed -- walls across streets from the passages between blocks** (another session's work
  of the same hour, live for a few minutes): each piece of a passage's wall was checked at
  its middle only, so a long piece of a footway crossing or ending in a street was walled
  right through it -- 318 walls on Givatayim's roads, 394 on Ashdod's, up to 6 m in, solid
  to the car. Now checked every 2 m along; and a bike "dropped by the wall" only off the road.
- **Fixed -- queues cleared slower than real ones.** A trace of the second car (`TRACE=n` in
  queue_start) showed the follow model was not what held it -- what it wanted was always
  above its speed -- but its start: it noticed the car in front only at 0.5 m/s (~0.45 s
  after that car began to creep) and then took 0.35-1.1 s to react, ~1.2 s a car against
  ~1 s at real signals. Now 0.3 m/s and 0.3-0.9 s. At 1x, 40 minutes, gaps between two cars
  both going straight on: 1.07x Greenshields' (the old drivers on the same test: 1.44x),
  start gaps 1.0 s. The test needed fixing first, four ways: speeds sampled by ticks (at 2x
  the old sampling skipped most), the line crossed by the rear wheels as Greenshields timed
  it, gaps judged only between two cars going straight on (a second car turning off and
  giving way read as a slow queue), and 40 minutes of watching (three 15-minute watches of
  one build read 1.18 / 1.44 / 1.57). At 2x it read 1.17x: final numbers at 1x. Tried and no
  help: easing the pull-away against the cruising speed.

### Handoff: the checks, validation, traffic's last findings (20 Nov 2026)

**Done, on `main`** (from branch `claude/brave-hopper-cmk1ky`), each against an exam finding:
- *Rings of cars waiting for each other.* The old way out (ignore the other car) worked only
  head-on (angles 0.8 rad+ apart); two cars at a skewed junction, each in the other's path,
  stood for good. A car waiting 2.5 s+ walks the chain of who holds whom (6 deep); on a loop
  the lowest-numbered car goes past the one it waited for for 3 s (`ignore_car`), which still
  counts when square in front of its wheels (0.6 m, as a filtering motorbike sees). "Held by
  nothing" went from 1-3 a town to 0-1.
- *Stop and give-way signs stopped a car's middle at the painted line* (`_sign_ahead`), so a
  sedan's nose stood 2 m into the junction, in the crossing street's lane, and was driven
  into; a bus's stood at the junction's middle. The front now, as at lights. (Found by the
  exam's new per-incident lines: the waiting car was "held by sign" 5 m from the junction.)
- *A delivery pulled in by the asphalt's room alone* (`_double_park`) and stood 0.3 m into
  the parked cars beside it -- a parked car stands a third in the road, and is two posts to
  traffic. Now no further than keeps its side 0.3 m off what stands along the kerb
  (`_kerb_edge`, measured once a stop).
- *A giving-way car's front corners in a skewed junction's lanes*: `_clear_back` stops it far
  enough back -- only away from lights (within 40 m of one it made queues slower: the second
  car braked for "junction" inside the lit junction).
- *A bus or truck alongside* is on my path by both bodies' half-widths, not its middle (cars
  drove through a truck's flank). Only those: every car by its body read 1.25-1.62x on the
  queue check.
- *The kerb lane on a single-lane road* keeps each vehicle's side 0.3 m on the asphalt
  (`_kerb_room`: a bus on a narrow street's lane line was over the kerb).
- *An amber commitment* holds through that light's red (`amber_go`; a truck went on amber,
  braked at the red and stood 4.5 m past the line).
- The exam prints, for every overlap, both cars (road, lane, shift, plan) and their last
  3 s; for every traffic-into-a-post, the car's lane and the post against the asphalt's
  edge; for "held by nothing", the front car's last 3 s; and a car waiting 25 s for a car.

**Measured** (4 starts x 75 s, 1x; Givatayim / Ashdod / test town): today's `main` before
these 15 / 12 / 7 checks, traffic into posts 10 / 6 / 2; with them 8 / 13 / 11, posts 2 / 1
/ 3. Overlaps did not fall (3 / 10 / 8 against 5 / 6 / 4): the counts swing that much run to
run, and the ones printed are where lanes change (below). Queue check at 2x: main 1.26 on 80
minutes, this 1.29 on 40 -- the same; main read 1.11-1.23 at 2x all day and 1.07 at 1x, so
"OFF" at 2x near 1.2 is the 2x reading, not a regression (judge at 1x).

**Open** (each seen in the exam's lines, with the place):
- *Overlaps where lanes change*: a car leaving Sderot Herzl (3 lanes) for a slip road at
  shift 0 while a bus is in the kerb lane it crosses; two cars on HaGdud HaIvri moving over
  at once by road changes (`realign`, which `_lane_clear` does not check). The lanes code is
  another session's, in progress.
- *A dead end's turning round* (Ashdod, Odem at (-3150, 5190)): cars reversing (v < 0) with
  shift 2-4 m overlapped the cars arriving.
- *Cars put down at the start of a path already in a junction* ("k 0", "held by junction",
  hit by the main road's traffic) -- check where `_spawn` puts a car against junctions.
- *Things in the road traffic cannot see*: details.gd's hand-placed parked car on HaMeri
  (21 Nov: `tests/hand_parked.gd` drives traffic past it on its kerb side, least gap 1.03 m --
  the lane misses it, not reproduced; the other three stand on the little street, a footway);
  the "tree" 0.7 m into Katznelson's was the Sheinkin-Sirkin walk's bin at the corner by the
  light's pole, 1.0 m in (city_check) -- moved 1.8 m onto the pavement in givatayim.json; and a truck on Sderot Herzl's kerb lane
  4.3 m right of the lane line on a pole past the kerb (where the road narrows).
- *The test town reads 19-20 checks at 2x on `main` since the evening's merges* (4-12 that
  morning; this branch beside it 19 and 13), mostly traffic overlapping. One seen whole: the
  autodrive shoved a bus at Derekh HaHarim (-540, 415) back at 5 m/s and 4 m sideways
  through the queue behind it, which then read as a ring. Whose change moved it is not
  found: bisect `main`'s afternoon on the test town (under a minute a run at 2x, twice each).
- Standing over the line at a red, about once a run (a taxi 4.5 m past it in the test town):
  not the amber case now; its drive log next.

**21 Nov: the user's thirty reports of the day before, in the validation.** `city_check`
gained their world checks and Tel Aviv; eleven tests that drive, walk or load end in a
`REGRESS` line (`validate.sh REGRESS=1`, ~10 min). First run, on `main` of 21 Nov 01:00:
- city: the towns' own mapped trees, merged hours before, stood up to 1.3 m into streets
  (Givatayim 40 posts on the road, Tel Aviv 42) -- fixed by that session within the hour
  (1377a70) when sent the list; still over: Tel Aviv 14 buildings 3 m into small streets,
  Ashdod 578 m2 and Tel Aviv 89 m2 of two pavings at once (Tel Aviv read 30 after its fix,
  before it grew to the sea), Bedford's roads 9% over 6% across (never levelled; the limit
  3). These fail until fixed, on purpose.
- the eleven: all PASS, after `seat_steady`'s verdict moved from the angle off ahead to the
  view's turning speed -- five healthy drives read 1.4-8.6 deg off ahead (the bug 8.1-9.4)
  but 0.05-0.13 rad/s turning against the bug's 0.29 (the test run on the code before the
  fix, 5b92fbd). Run a verdict on the bug's own code before trusting it. One stall each in
  `seat_steady` (no output after the warm-up for 13 min) and `deck_corner` (route 1 never
  ended), neither seen again in four runs: timeouts now ~3x a test's time.
- the test town's exam on `main` read 29 checks at 2x (23 traffic overlaps; 4-12 on 20 Nov
  morning, 19-20 that evening): still rising, still to bisect.

**Commands** (all headless, in the background):
- `game/streets/tests/validate.sh` (~6 min), `FULL=1` (~12 min), `REGRESS=1` (+~10 min). Good: city 0 (Givatayim
  1-2 posts and the passage), exams about 7-15 a town and noisy, queue PASS at 1x.
- One check by itself: `LEVEL=1 STREETS_BUILD_ALL=1 $GODOT --headless --fixed-fps 60 --path .
  -s res://game/streets/tests/exam.gd` (`EXAM_STARTS=2` halves it; `STREETS_SIM_SPEED=2`).
- The queue: `STREETS_SIM_SPEED=2 LEVEL=1 KNOT_AT="-800,-288" SECS=2400 STREETS_BUILD_ALL=1
  $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/queue_start.gd`
  (~4 min; `SECS=4800` to compare two builds, back to back). Good: "line gaps / real ones"
  0.8-1.2 at 1x; at 2x it reads ~0.1 higher.
- A car that stands: `tests/traffic_stuck.gd`; the second car of a queue: `TRACE=n`.

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
coloured by what held it. Then stage that spot in a scene test. Each sample also holds the people within 30 m
(`people`: [x, z, who], who the list and state -- "walker", "crosser:cross"...), and
`route_set.gd` saves a log of its own a second after any hit (`route-<n>-hit<t>.json`).

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
  (Since: a junction is a site, its groups by direction -- see "traffic lights" above; by
  name, a street that changed its name at the junction had green with the one across it.)
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
  "18.8 m off the road" and most of its "left of the middle"); planned as a lane out and a
  lane back it also hit the trees and garden walls at the end of all 8 of the test town's
  cul-de-sacs at 21-29 km/h. For a while it stopped at the end and spun round on the spot.
  Now (`_ap_mark_dead_end`, `_ap_kturn`) the plan stops 7 m short of the end and the car
  turns round in moves forward and back on full lock, each ending when a bumper would be
  0.6 m over the kerb (the wheels stay on the asphalt) or near anything solid, the wheel
  turned over standing between them, the throttle allowing for the slope (backing up a
  17% cul-de-sac on the flat's throttle crawled at 0.2 m/s), standing still while a traffic
  car comes up the street at it (the probes at its ends missed one coming at its side, and
  it touched them at 5 km/h). Three moves in a 6.5 m street
  (with only 0.15 m over the kerb allowed it took five); boxed in (two moves running that got
  nowhere), or past 7 moves or 30 s, it turns the rest on the spot. Then the way out is
  planned afresh from where it stands. A one-way street that just ends (cut by the map's
  edge) keeps the stop at the end and the turn on the spot: planned afresh, a turned car would
  be sent back up the one-way into it. `tests/dead_end_turns.gd`. Traffic avoids dead ends
  (`_dead_end` in traffic.gd); it turned round in them in queues and overlapped there.
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
- The look-round made the seat view chaotic ("jumps around, looks at random locations"):
  the steering went into the view twice (its own lead into a turn, and the head's turn on
  top), the scan fired at every junction below 23 km/h, and the eyes jumped to whichever
  person was nearest each frame. Now the head has no steering, scans only standing, holds
  one person, and moves eased; the seat view takes 70% of it. `tests/seat_steady.gd`:
  swings back 171 -> 67 a minute, 9.4 -> 3.3 deg off ahead on average. What is left is the
  view's own lead into turns following autodrive's small corrections, and the body.
- "They drive straight but stand very much on the right": autodrive follows its line
  (`tests/lane_position.gd`), so the line was the cause -- 0.25 m past a two-way lane's
  middle (0.6 m from the kerb on a 7 m street) and the right-hand lane of three on
  Sderot Herzl. Now +0.12 m and 1.1 m clear of the kerb; on three lanes or more the second
  from the right, over to the right-hand one before a right turn.
- A slip road has no name in OSM: the junction offered it as a way of its own beside the
  turn it cuts ("four options, one of them weird"), and turning right from the junction
  itself the car turned from the middle of a three-lane road. It is now named after the
  street it joins, merged with that turn and taken turning right; a way with no name within
  20 degrees of another is the same choice; the choice shows from 70 m and autodrive picks
  for you at 30 m (`tests/junction_offers.gd`: Ashdod's offers of four 95 -> 72).
- The look-round fires only first in line and about to go (no car within 12 m in front;
  at a light, its green): it looked left and right at every red from behind a queue.
- Traffic vehicles steer by their front: the front axle runs on the lane rounded over 4 m,
  the rear trails a wheelbase behind (`_place` in traffic.gd). The body was pointed along
  the lane 2.2 m either side of its middle, the same for a car and a bus, and pivoted on
  its middle at corners. `tests/traffic_motion.gd`: rear sliding sideways 3-7% of moving
  time -> 0.
- Queues at a green (`tests/queue_start.gd`, KNOT_AT="-800,-288" in Givatayim): all at
  once at first (a train), then far too slow (third car 9 s); the follow gap now on the
  slower of the two speeds.
- The exam's own counts were off twice: harsh braking per frame (30x one stop) and traffic
  reds judged at every signal point of a junction by the heading mid-turn. Check what a
  counter counts before chasing its number.

## The route set: the same ten drives, again and again

`routes.json` (beside the game: the "Test routes" level lists them) holds ten drives from one address to another (Givatayim 4, Ashdod 3,
Tel Aviv, Bedford and the test town one each), picked once by `tests/pick_routes.py` (seed
2026; it keeps away from the places in the privacy rule below). `tests/run_routes.sh [ids]`
drives them by "go to" and autodrive, two at a time, headless at 60 fixed ticks a second
(the test town's in ~20 s, a big city's a few minutes; all ten ~10-12 min here, not the
40-60 the script's top says), and `route_report.py` draws each
drive with street names (OUT dir) and appends a dated block to `tests/routes_results.md`:
arrived, time, distance, hits, the longest wait and what held it, red lights, rescues, time
off the road. Run it after a change to driving, compare with the last block, look at the
maps of whatever got worse. Pick a new set (another seed) only to widen what is covered;
keep the old block for the record.

### Routes of your own

The Test routes list has two pages, "the ten" and "yours". "Yours" makes one: a city
button starts that city with `{"make_route": true}`, the address picker opens once it is up
(`_making`: "from", then "to"; its jump/drive choice hidden), and the second pick saves it and
drives it (`_made_pick`). They live in `user://my_routes.json` only (`MY_ROUTES_FILE`,
newest first, at most 9, ids from 1001): the browser's own storage, never the repo, because
a route from home names home. `_route_by_id` looks in both. `tests/my_route.gd` makes one in
the test town by the taps a player would make and puts the file back as it was.
Two things it found: the list's small buttons were sized before they were in the tree and
kept the kit's 180x34 minimum (`_put` after `add_child`, as the picker does) -- a tap on
"test town" started Bedford; and `_land_on_road` looked for a road at the car's own height
wherever it was asked to land, so from the valley to an address up the test town's hill it
skipped the street 32 m away for one 107 m off at the valley's height (now: the car's height
only within 40 m of the car; and a route's start lands within 150 m, as "jump to" does).

## Giving way, crossings, pockets (20 Nov 2026)

**Autodrive gives way** (`_ap_give_v`, `AP_GAP`). Before, it stopped only for a car already
on its lane, and traffic always lets the player go: it pulled out of side streets in front
of cars on the main road, which stood on their brakes (7.5 m/s^2, `BRAKE_HARD`, in all four
meetings `tests/give_way.gd` staged). Now, coming to a junction, it finds the cars whose way
through it meets its own (the two paths cross, or end in the same lane), decides who goes
first by traffic's own rule from its side (in it already; lights: with my green I still let
one going straight on its green by when I turn across it; else the bigger road, a ring above
all, a sign on my way in below all; between equals straight before turning, then whoever is
there first), and holds at the junction's edge unless it can be through before the first of
them gets there with `AP_GAP` (1.5 s) to spare -- after 12 s standing, 0.3 s. While it holds
there, traffic does not wait for it (`_ap_giving`, read in traffic's `_junction_ahead`), and
its head turns to the car it waits for. What it took to work, each found by the test:
- the time to get through is reckoned at the plan's own speed through the junction (a
  corner's), not pulling away flat out: reckoned that way it judged it could get in first,
  then slowed for its turn and arrived in front of the car;
- cars are looked for 110 m along their own paths: traffic's own look (55 m, `_node_index`)
  is 4.6 s at 12 m/s, under the gap wanted, and the car was not seen until too late;
- it aims to stop 1.2 m short of the line (it runs a metre or so past where it aims), and a
  junction it is holding for counts as not yet entered until its nose is at the middle: two
  metres past the line it read itself as in, and went;
- the junctions on its plan are found every quarter second and moved up by the distance
  driven in between (every road segment by every plan point every tick was 1-2 ms); the
  check costs ~50 us a tick in the test town (`_ap_give_us`).
- on Givatayim's hills the car coming was 3-4 m below autodrive 50-80 m off, and the level
  test (`_traffic._level`: within 2.5 m, for bridges) passed it over: now `_same_level`,
  both on the ground or within 2.5 m plus 8% of the distance. `lead_on` (the car ahead)
  had the same blind spot: route 4 side-swiped a car turning across it on La Guardia;
- whose turn it is between equals turning alike ("first come") is judged at its pace through
  the corner and wants a clear second: by its speed coming up to it, it was 2 s ahead, slowed
  for the turn and got there 1.5 s ahead, and the car stood on its brakes;
- two ways that only pass within 2.4 m of each other meet as well (two turns through the
  same corner); and while autodrive drives, traffic waits for it at a junction only if it
  can still stop comfortably -- too close, it goes on and autodrive waits for it;
- its own way in and out of a junction are read where its plan comes within the junction's
  radius and leaves it, not either side of the point nearest the middle: a left turn's
  curve passes nearest the middle after the corner, the way in came out along the road it
  turns onto -- the way the car coming along it goes -- and that car was passed over as one
  following it;
- after 12 s standing (a stream of cars a few seconds apart: 40 s on Ashdod's HaSachlav in
  the route set) a car far enough off to slow comfortably (under 2.5 m/s^2) lets it out, as
  drivers in a stream do; traffic waits for it then.
Side streets meeting a bigger road with no lights: it comes up to them no faster than it
can stop from (5 m/s at the line; not a slip road merging). Results: see `give_way` in
tests/README.md.

**Divided roads' crossings** (`_zebra_clear`). People cross a divided road kerb to kerb, both
halves (18-22 m on Givatayim's, ~15 s on foot), and a car on one half waited for all of it.
On the route set's first drive that was 10 s of its green on Nachalat Yitzhak, then the whole
red after: "41 s, zebra". Now `_zebras_on` carries where the person is and their pace, and a
car (autodrive or traffic) waits only while they are on its half (its carriageway's width
plus a metre) or will be within 2.5 s. A road that is not divided is one half: they wait for
all of it. `tests/zebra_halves.gd`: from the near kerb autodrive stood 3.4 and 7.5 s and was
by while they were still on the far half (they take ~18 s); from the far kerb it did not stop.

**Pockets** (`_find_pockets`). The bake cuts each town at its edge, and with it the far ends
of one-way streets: some streets have no way back to the town but against a one-way
(`_trap`), others no way to them from it (`_cut_off`), and points past the barrier are on no
way at all (`_outside`). Inside the edge, public streets: Givatayim 8.0 km trapped and 8.5 cut
off of 157; Tel Aviv 6.3 / 9.4 of 144; Ashdod 8.3 / 7.3 of 555; Bedford 24.7 / 26.4 of 321
(16%: a whole estate in one corner); the test town none. Found once at load on the graph
the routes use (20-170 ms). Traffic (-6) and free autodrive (-8) do not turn into a trap
from outside one; "go to" an address in a cut-off pocket goes to the nearest street with a
way in (never one past the barrier: left unmarked, that was where "the nearest" landed); a
route that starts in a trap starts at the nearest street with a way out.
`tests/pockets.gd` (counts, those two checks, `$OUT/pockets_<city>.json`) and
`tests/pockets_map.py` (the picture: red trapped, orange cut off). Widening the bake would
only move the cut: a way out beyond the barrier cannot be driven.

### Stops in a junction's middle, roundabouts, pace (21 Nov 2026)

The user, three reports: "the car weirdly stops in the middle of the run" (twice: the amber
stop, see "A green ending far ahead" below); "cars sometimes stop in intersections as if
there are 2 turns... some stops in the middle that cause chaos... maybe also near ramps or
bridges" (Ashdod, a T of two divided roads with lights, behind a car standing in the middle);
"driver pauses before roundabout exits, shouldn't. In general he is very defensive, somewhat
slow" (Givatayim, a small ring on a main road, 13 km/h on it).

- **Where the time goes** (the route set's drive logs, 10 drives, 2,553 s of autodrive, by
  `why`): behind a car 36% (mean 20 km/h, 272 s standing), at its limit 35% (37 km/h),
  slowing for a bend 17% (28 km/h), lights 7%, junctions 3%, zebras 1%, signs 1%, people
  0.6%. Not the car: full throttle is ~4 m/s^2 and it holds its limit within 0.2 m/s.
- **Roundabouts** (`tests/rb_pace.gd`): no pauses on a ring or at an exit with or without
  traffic or a destination, but slow: the slowest on the ring 14-18 km/h, at the exit
  15-25. `PLAN=1` showed why: every point of a ring turns enough to count as a corner, and
  `_route_to` laid an arc at each, squeezed by the next point 1.3-7 m on -- a 17 m ring
  driven as straights and 4-5 m bends; the ways on and off were squeezed the same way. Now a
  point with ring points either side is a plain lane point (`_ring_node`), and a corner
  before one runs out to it; and the sideways limit in `_ap_curves` rises from `AP_LAT` 3.6
  (15 m radius up) to `AP_LAT_TIGHT` 4.8 at 5 m, as people take a tight bend (the tyres
  hold ~9). Givatayim's 9 rings: the slowest on the ring 18-21 km/h, at the exit 18-25, 0
  off the asphalt; `turn_width` 0 of 10 over the middle line, the car 0.5-0.8 m off its
  plan as before, right turns out at 14-22 km/h 1.4 m+ right of the middle line (was
  1.0-1.4 at 13-17). The pause itself was not caught standing: what the user saw at 13 km/h
  was the easing-off for each bend, slowest at the way off.
- **Cars standing inside junctions** (`tests/knot_stops.gd`): with the player parked away,
  traffic alone stood inside none of 5 junctions of 5-8 lit points but for a bus; autodrive
  driven through from every way in stood inside none. Traffic did stand inside the biggest,
  29 m across (8 points), when autodrive drove through (the people on the crossings come out
  only near the player): 7 cars waiting for someone on a crossing 8-10 m outside the
  junction, the person up to 7 m off its middle -- over on its far side. `_zebra_clear` (both
  traffic's and autodrive's) waited for anyone on the crossing till the far kerb but on a
  divided road's other half. Now a person 2.8 m (`ZEBRA_PAST`) past the car's lane line and
  walking away is clear for traffic, 6 m (`ZEBRA_PAST_ME`) for the player's car: people run
  back to their kerb from the player within 5.5 m, and autodrive going by at 2.8 m sent them
  back across its way (`zebra_halves` caught it: 2 of 6 bad, the person "done" in 8 s of a
  28 m crossing) -- `_zebra_past` false for a test: `ZEBRA_OLD=1` (knot_stops, zebra_halves). It did not cut the
  stands there (DRIVE=1 at that junction, both in one sitting: 4 zebra stands inside before,
  6 after -- noise): in those the person was 0.8-3.4 m off the crossing's middle, in or near
  the car's way, and turning cars wait inside a junction for them in life too. It does let
  a car go sooner at any crossing once the person is past it. Open: whether those cars were
  turning (right) or going straight (then the walk light let people out while that way was
  still clearing) -- the drive-through print does not say yet.
- **The drive, charted** (the user: "the car slows down and stops in weird places... sudden
  stops due to other cars... others just drive while the autodrive is hesitant and even
  misses green"): `route_set.gd` `TRACE=path` records a row every 0.1 s (the game keeps
  `_ap_light_dbg`, the light `_ap_light_v` read, and `_ap_lead_i`, the car followed, for
  it); `tests/drive_trace.py` turns it into rows or a report; a chart page of routes 2 and 6
  was made from them. What they show: held back by the car in front 56% / 52% of the drive,
  free at the limit 23% / 32%, bends 18% / 11%; standing on its own green 7 / 8 s in all
  (queues starting, 1.5-4 s a time: no missed greens); 8 hard brakes a drive, most of them
  5-5.6 m/s^2 coming up behind a car already standing 10 m ahead (the follow speed allows
  2.6 m/s^2: the car is seen late, or stops abruptly -- open), some behind a car moving as
  fast as itself (one crossing its way, read as the car in front? -- open); route 6 at 3:10:
  a traffic car pulled in 12 m ahead at 24 km/h and stopped dead for the player (its why
  "player"), autodrive braked 8.8 m/s^2 from 48 km/h and touched it (counted as 3 hits on a
  wall and a building beside it) -- open; at 3:46 it lost 19 km/h in a tenth of a second at
  50 km/h with nothing ahead (a knock the route set does not count: it counts a hit only
  when the thing hit changes) -- open.
- **Not found**: the user's own junction (the T of two divided roads) showed no stands in
  150 s of traffic nor with autodrive through it from 5 ways in; the car in their screenshot
  may have been one of these zebra waits or a turn waiting for oncoming traffic. Ramps and
  bridges: not looked at -- a place or a screenshot is needed.

### Hills, pockets, the end of a green, a divided road's middle (20 Nov 2026, later)

**Autodrive's turns were wide** (the user: "its radius of turning is like double of what it
should be, it hits the opposing or the next lane a lot"). `tests/turn_width.gd` (a side street
to a cross street, right and left, the rest of the traffic off) measured it: on Givatayim's
8 m streets every right turn came out with the car's middle on the middle line of the street it
turned into (-0.2 to 0.2 m right of it; its lane is 2.1), 1.5-2.2 m off its own plan, at 14-22
km/h through a corner planned at 12. Three causes, each fixed:
- **a "go to" route's corners** (`_route_to`: routes, the test routes, routes of your own) were
  one point per corner, put into the lane square to the way to the *next* point -- the next
  street's way -- which put it on the middle line of the street it was leaving: the car swung
  out left over the last 10 m, came round at full lock from there and out over the next
  street's middle line. Free autodrive (`_ap_leg`/`_ap_turn_into`) laid real corners. Now the
  route's points closer than 3 m are one corner, at the junction's point (a junction drawn as
  two points 0.9 m apart was two, the second's curve starting behind the first: the plan
  doubled back; and keeping the first of two, a slip road's point 3 m short of the street it
  joined, laid the corner off that street's line -- route 7 came out of the turn 4.7 m from
  the middle of an 8 m street, over the kerb into a post, and backed off), a corner's
  curve may start behind the lane point before it (dropped) and run on to the next point when
  that is no corner itself (lane points it passed are left out), and the route's first point
  is a corner too when the car is not on it (a side street that is one stretch up to the
  junction has the junction as its first point: a corner of one point, taken wide);
- **both laid a right turn tighter than the car turns**: a curve from 5 m before the junction to
  5 m after through where the two lanes cross is 2-3 m round on an 8 m street, and the car at
  full lock is ~4.1 m. Now every corner is `_lane_corner`: an arc along the lane in and out
  along the lane out, at least `AP_TURN_R` (5.5 m) round, starting further back when it needs
  to (no further than the point before it);
- **it came into corners fast and steered at a point too far ahead**: braking by how far over
  its target it is (2 m/s^2 a m/s), it ran ~1.3 m/s over the 2.6 m/s^2 slope down to each corner
  (now aimed at half a second early); and the point it steers at was 5.4 m ahead at 14 km/h --
  it started round 6 m early and came out with the turn not done (now 2 + 0.6 v, at least
  3.5 m: 4.4 m at 14 km/h, the same as before from ~50 km/h).
After: 0 of 8 over the middle line, the car within 0.5-1.2 m of its plan, right turns out
1.0-1.4 m right of the middle line at 13-17 km/h (Givatayim, five junctions; Ashdod 0 of 10,
the test town 0 of 2). The route set after: 10 of 10, 0 hits, 0 reds, 0 rescues, 0 s off the road.

The open items of the handoff below, done:
- **Traffic sees the player on a hill** (traffic.gd `_level`, `Car.lift`, `_me_lift`). Its
  level test was height alone (2.5 m, for bridges and tunnels), in every check of the player
  and of other cars: the car ahead, the junction, oncoming, the lane beside. Now two things
  are on one level when their heights are within 2.5 m *or* their heights above the ground
  under each (`lift`: ~0 on the street, a deck's height on a bridge) are. `tests/hill_level.gd`
  (Givatayim's five steepest unsignalled approaches, 7-10 m of rise in 60 m): before, a car
  coming down Shim'on Ben Zvi drove into the player standing in the junction (0.1 m) and into
  them waiting 15 m short of it (0.0 m), slowing only 8-10 m off; elsewhere it slowed 15-26 m
  off. Now it slows 34-36 m off on all but one (15 m, the same as before: the car's way comes
  to that junction round a bend), at 3.5-3.7 m/s^2, none closer than 7 m. The test holds the player still by hand: with nobody at the pedals the
  car rolls down a 15% street (`_drive` holds it only under 0.14 rad).
- **No traffic put down in a pocket** (`_spawn` skips segments in `_trap`, `_cut_off`,
  `_outside`). `tests/pockets.gd` now spawns all the cars round 8 places in or by pockets:
  Givatayim 79 cars, 0 inside.
- **The exam's give-way waits** are counted apart: "autodrive: gave way 8 s+" (a wait),
  "autodrive: stuck giving way 30 s+" (a stall, with its incident); "stuck 8 s+" no longer
  counts a car holding at a junction for traffic.
- **A car put down somewhere new forgets the last lit junction** (`_land_on_road` resets
  `_light_site`). It was kept for 120 m driven: a car put back by the light it had just
  crossed (a "go to", a route's start, a test going round again) drove through its red and
  the red was not counted. Found by `tests/amber.gd`: every case read "on through, no red"
  at 50 km/h whatever the light did.
- **The end of a green, from autodrive's seat** (`_ap_light_v`, `_light_red_in`,
  `_ap_time_to`, `_ap_brake_for`, `_ap_amber_n`). It went on through an amber whenever it
  could not stop at 3 m/s^2, and stopped (aiming at 2.6 m/s^2) otherwise -- on a flashing green
  it did nothing. Now, on the flashing green or the amber, it goes on only if its nose will be
  over the line before the red at the pace its plan goes there (a corner just past the line
  slows it first); else it stops -- gently on the flashing green (or decides again on the
  amber), firmly on the amber if need be (up to 4.5 m/s^2; past that, on through). Once it
  decides to stop it keeps to it until green, braking at the rate the stop needs and a fifth
  more: aimed at "the speed that just stops in time from here" the target sat a hair under its
  speed, and the controller (2 m/s^2 for each m/s over) hardly braked -- the need grew until it
  gave up and drove on into the red. `tests/amber.gd` (Ashdod, two lights, 50 km/h, the light
  sent to the end of its green at 10-55 m, straight and left): before, the left turn caught by
  the amber 40 m out ran the red, and an amber 55 m out stopped it at full brake (8.2 m/s^2):
  5 of 40 bad. Now 0 of 40: on through from 30 m and nearer, stopped from 40 and 55 m at
  3.6-3.9 m/s^2, 2.7-11 m short of the line; on a flashing green it goes (6 s to the red).
  The route set's red (route 5, Ashdod) was this. The traffic's own amber rule is not touched.
- **A green ending far ahead stopped the car mid-street** (21 Nov; `_ap_brake_for`). The user,
  twice: "the car weirdly stops in the middle of the run" -- by a side street on Hafetz Haim,
  Givatayim, the road empty, and again 20 m short of a crossing. Both were the amber stop
  above: it braked at the stop's need and a fifth, but at 1.5 m/s^2 at least, wherever the line
  was. A green ending when the light was 80 m off (it cannot get there in the 6 s to the red,
  so it stops: right) brought it to a stand 23 m on; standing, the need is nothing and the speed
  to aim at nothing, and `_ap_amber_n` keeps the decision until green -- it stood 57 m short
  all through the red. The "3-11 m short" the amber test printed was the near end of the same
  thing, put on the open list instead of chased. Now while the need is under 2 m/s^2 the
  speed aimed at is the usual slope up to the line (2.6 m/s^2), as for a red; above, the
  commanded braking as before. Found by `tests/side_street.gd` (Hafetz Haim on the user's
  route, four passes: the third met the end of a green and stood 19 s 2 m from the side
  street, why 'light'); `tests/amber.gd` now has an 80 m case and fails a car left standing
  more than 4 m short (6 s after it stands): before 12 of 12 bad at 80 m (27-45 m short), now
  0 of 72 -- every stop 1.6-1.7 m short of the line (where it aims), braking 3.3-4.3 m/s^2.
  Route set after: 10 of 10, 0 reds, 0 rescues, 0 off road; one hit, a person on Bedford's
  Hammonds Plains Road at 23 km/h (following a car at 36 km/h, why 'car', then 'people' under
  a second before: someone into the lane close ahead -- no light near; open, below).
- **Waiting in a divided road's middle** (`_median_gap`, `_ap_split`, `_ap_mid`,
  `_ap_edge_of`; `_ap_median_ok` turns it off for tests). A junction of points within 18 m is
  one junction for autodrive (`AP_KNOT`): it waits at the kerb for a gap in every stream it
  crosses. Now, where a short road of its own runs straight across the middle from one
  carriageway's point to the other's, with no lights, and the room between the two
  carriageways' edges is a car and 1.2 m (`AP_MEDIAN_SPARE`), it is two: autodrive crosses the
  near carriageway when that is clear and waits in the middle for the far one (stopping 0.4 m
  short of its edge, below it in rank whatever road it came from). Most medians where a street
  crosses are too narrow for that in the game's geometry (the carriageways are drawn at their
  guessed widths, 4-10 m, and their points 7-14 m apart): `tests/median_wait.gd` counts every
  way across a median and the ones deep enough -- Ashdod 9 of 42, Tel Aviv 3 of 17, Givatayim 2
  of 4, Bedford 8 of 16 -- and of the side-street crossings it can stage (a side street with no
  lights, straight 34 m), only Givatayim's one has room. Where there is none nothing changes
  (Ashdod's five staged crossings: the same with and without; 0 hits, no car braking for it;
  Givatayim's one with room: PASS; Bedford has no side street crossing one to stage).

### Handoff: autodrive's junctions, the route set, test routes (20 Nov 2026)

This session's areas, for whoever picks them up (its context is compacted after this).
Nothing is half done: all of the above is on main.
- **Where the code is**: `_ap_give_v` and its helpers (`_ap_at`, `_same_level`, `_rank_of`;
  the cache `_ap_js` of [along, node, enter, leave]) by `_ap_zebra_v` in streets.gd, called
  from `_autodrive` as "junction"; traffic.gd reads `g._ap_giving` in `_junction_ahead` and has
  the `can_stop` rule there; `_zebra_clear` (both); `_find_pockets`, `_pocketed`,
  `_nearest_seg_out` after `_build_graph`; the routes list and routes of your own after
  `ROUTES_FILE` (`_route_list_open`, `_route_new_row`, `_made_pick`, `_cancel_picker`).
- **The tests and good numbers**: `give_way` (LEVEL 4, 1; headless; `GW_NODE=n VERBOSE=1`
  for one junction second by second) -- PASS, test town 10 of 10, Givatayim 8 of 8,
  30-60 us a tick; `zebra_halves` (1, 4) PASS; `pockets` (1, 2, 3, 7) PASS; `my_route` (4,
  through `tests/run.sh`: it takes shots) PASS; `run_routes.sh` -- the last block of
  `tests/routes_results.md`: 10 of 10 arrived, 0 hits, 0 rescues, longest waits 9-40 s.
- **How the bugs were found**: a decision that ignores a car is found fastest by a print at
  each filter in turn (a `GW_DBG`-style env check, removed after); each time it was a filter
  upstream of the change being tried (no path window, the level test, the way in read past
  the corner). A result identical to the decimal after a change means the change is not
  reached.
- **Open** (the six that were here are done: see "Hills, pockets, the end of a green, a
  divided road's middle" above):
  - a right turn's arc is still tighter than 5.5 m where the point before it on the plan is
    within a few metres of the junction (it may not start behind it): 3.6-4.3 m at two of
    Givatayim's four in turn_width. Dropping a plain lane point that the arc would start
    behind would let it;
  - (done 21 Nov: route 9's person hits -- see "People stepping into the lane" below);
  - `_push_out` sets `_last_hit` even when it only probes (the plan's `_clear_lane`, the nose's
    safety net): a test reading `_last_hit` must gate on `_crash_cool`, as route_set and
    give_way do;
  - few medians are deep enough to wait in where side streets cross (the carriageways' guessed
    widths): if real ones look wider than the game draws them, it is the widths
    (`_fit_widths`, the `median` key), not the waiting.

### People stepping into the lane (21 Nov 2026)

Route 9 (Bedford) hit a person in two of four runs (23 km/h on Hammonds Plains Road, 32 on
Hollyhock Way), autodrive holding for "people" only 0.3-0.6 s before. A hit is rare, so the
measure is `tests/people_near.gd`: everyone who comes into the lane ahead (1.7 m of the
plan) nearer the nose than the car can stop. Route 9 twice: 4 over 9.1 km, all walkers
moving 1.4-1.6 m/s square to the lane -- stepping over a side street's mouth (`_walk_on`'s
step, up to 18 m of asphalt) with no look at the traffic, onto the street the car was on or
turning into. Givatayim's route 4 three times: 0 (its mouths are narrow and slower).
Two changes:
- the walker at the kerb of a step over waits while `_safe_to_cross` says a car could not
  stop, or one's middle is within 4 m of the step (the crossers' 2.5 m let them out into
  a car's side once its nose was past); after 15 s, back the way they came (`kerb_t`);
- `_ap_people_v` keeps each person's pace (once a physics frame, `_ap_ppl_at`) and looks
  for them where they will be when the car is level (up to 2 s on) as well as where they
  are, and looks as far as the car needs to stop (32 m, or v^2/7 + 12).
After: route 9 twice 0 late, 3 within 1.6 m of the body (none under 1 m; was 7, 1);
Givatayim 0 late. Traffic cars do not look at walkers at all (they rely on the kerb wait).

### Traffic at slip roads; the City tunnel's test run (21 Nov 2026)

- *Off onto a slip road from the wrong lane.* `_turn_ahead` counted a fork under 34 degrees
  as straight on, so a car leaving Sderot Herzl's three lanes for its slip stayed in the
  middle lane and crossed the kerb lane at the fork, into the bus there (Ashdod's exam: 9 of
  its 16 checks at (-1780, 2275)). Leaving a road for a `_link` (`_onto_link`) is now a turn
  to the fork's side from 0.08 rad (5 degrees), so the car is in that lane 110 m before.
- *Moving over because the road changed* (`realign`: onto a narrower road, a slip's lane)
  never looked; a car with someone level with it or a little ahead in the lane it moves
  to (`_side_clear`) now eases off (0.8 of its speed each decision) and lets them go first.
  Only those level or ahead: braking for one further ahead it slowed to a stop, and its
  move over (paced by its speed) stopped with it.
- Ashdod's exam, before / after: 16 / 5 checks (traffic overlapping 9 / 4, into posts 6 / 1);
  autodrive's harsh braking 4 / 15 a run, 10 of them "for car" -- one run each, noisy, but
  watch it. Givatayim 13 and the test town 15 checks after (no before from the same day).
  Route set after: 10 of 10, route 2 brushed a wall and a post at 11 km/h on Moshe Dayan
  passing a bus pulled in at a stop (its log `route-2-hit306.json`, not kept: autodrive "blocked by
  post 71247" 0.6 s before) -- open, not yet known whether new.
- *The City tunnel "hitting a building"* was the test, not autodrive: `decks.gd` put the
  car down by `_land_on_road`, which goes by the car's height only within 40 m of the car,
  so a tunnel's run was put down on the ground 24 m off -- on a car park aisle whose last
  13 m is a 3.6 m slot between two blocks (Givatayim (-735, -1078), OSM's aisle into an
  underground car park) -- and drove out through it. The test sets the car there first;
  the run drives the tunnel, 0 hits. The slot itself is still drivable (open).
- `auto_stands` prints the lead car's nose and tail off the lane and its heading too: the
  validation's Nahliel stop (4 s behind a sedan at 26 km/h, 2.9 m off, 60 m free) did not
  come back in two runs (13 min, every stop a queue).

## Numbers to compare against (November 2026, cloud container, software renderer)

- Build time in full: Givatayim ~6 s, Bedford ~9 s, Ashdod ~15 s, the test town ~1.2 s
  (the container is slower than a laptop by ~3x; compare ratios). Before the car is shown,
  near-first: Givatayim ~2 s (9 of its 71 squares), Bedford ~1.2 s, Ashdod ~2.8 s, the test
  town ~1.2 s (headless playtest, `build_ms` in the "city" event); the rest of Givatayim
  ~10 s of background building (the "city_built" event). Tel Aviv (the box, 4011 buildings,
  3667 roads, 59 squares): ~2.2-2.5 s before the car, the rest ~11-12 s. After Tel Aviv grew
  to the sea (9,591 buildings, 6,091 roads), the playtest's "city" event, two runs at once:
  Tel Aviv parse 2.7 s + build 3.4 s before the car, Ashdod 2.2 + 3.0, Givatayim 1.0 + 2.0
  (decks_inferred alone 0.8 s of Tel Aviv's parse, 0.24 of Givatayim's).
- **Before the car, near-first cut to what the first view sees** (`tests/start_soon.gd`,
  headless, 20 Nov 2026, old way with `STREETS_NEAR_FIRST=1`): Givatayim 4.4 -> 3.0 s (6 ->
  1 square), Tel Aviv 10.1 -> 6.3 (8 -> 1), Ashdod 8.3 -> 5.9 (8 -> 2); the rest within 320
  m of the car 2.8 / 5.7 / 3.7 s after it, at ~40 frames a second. What is left before the
  car is mostly the city file (1.5 / 4.3 / 3.4 s) and the setup (0.4-1.4 s).
  `tests/load_bar.gd`: the bar's second Givatayim load said "about 3 s" with 2.9 left; Tel
  Aviv from Givatayim's numbers "about 5 s" with 6.6 left (its file takes more than its size
  says).
- **The city file, part by part** (`load_stages`, the "city file: ..." parts, headless, 21 Nov
  2026): Tel Aviv 3.95 s -- decks inferred 1.29, decks set up 1.17, widths fitted 0.40,
  buildings cut 0.37, divided roads 0.27, roads 0.13, parse 0.12 (the JSON itself is cheap),
  graph 0.12; Givatayim 1.39 -- decks 0.70 of it. With the decks baked (`start_soon`,
  STREETS_NO_BAKED=1 for without): Tel Aviv's file 3.9 -> 1.5 s, the car 5.8 -> 3.5 s;
  Givatayim 1.4 -> 0.7, 2.8 -> 2.2. The records: Tel Aviv 674 KB, Ashdod 702, Bedford 613,
  Givatayim 276, the test town 22; prepublish ~25 s for all. What is left of the file is the
  next thing to bake (widths, buildings cut, divided roads: 1 s of Tel Aviv's 1.5).
- **Starting a level in a browser, phase by phase** (`tests/web_load.js`: the container's
  Chromium, the engine's wasm on one thread, SwiftShader drawing; 20 Nov 2026). Givatayim:
  engine up 1.5 s after the page, the level begun ~4 s; city file 1.8-2.1 s; the squares round the start 17 s (kerbs
  4.7, far shadows 2.3 -- 0.65 of it work, the rest its two frames -- parked 1.1, trees 1.1,
  furniture 0.9, places 0.8); warm-up 50 s (twelve frames of 3.6-5.9 s: SwiftShader's
  drawing, not what a phone pays). Tel Aviv: city file 5.5 s, the squares 36 s (kerbs 8.6,
  far shadows 4.1, furniture 2.9, roads 2.7, parked 2.2, places 1.9), warm-up 62 s. The CPU
  stages run ~3-4x the headless numbers above (wasm, one thread). What makes a player's wait
  swing from a few seconds to twenty (user, Nov 2026): a new build since the last visit
  (index.pck's 39 MB downloaded again; index.wasm's 39 MB too until the worker learnt to
  keep it, tools/publish_web.sh -- 77 publishes on 20 Nov alone), shader code changed since
  the last visit (the browser compiles those again: the warm-up's "x of 12" steps), and the
  city's size.
- Frame cost at the start view (`tests/frame_cost.gd`, quality 3, Nov 2026, same run):
  Tel Aviv 1.69 M triangles + 0.75 M shadow, 367 draws; Givatayim (Katznelson by Weizmann)
  2.00 M + 1.01 M, 444 draws -- Tel Aviv's towers are no heavier at the start than
  Givatayim's busy junction.
- Parked cars by the kerb's paint (Givatayim's start view, `tests/frame_cost.gd`, quality
  3): 1.32 M triangles + 632 k shadow before, 1.54 M + 854 k after (+17%, +35%), draws 292
  -> 294. Measured at the old start, a residential street of blue-white kerbs: the densest case.
- Draw calls at the start view: Givatayim ~290, Ashdod ~420 (`tests/draws.gd`), before the
  city was built in squares; since, Givatayim 235 with all of it built (little things are
  grouped per 400 m square, not 220 m) and 200 at the start before the rest is up.
- Givatayim: 140 roads narrowed to their buildings, 865 building fronts cut back, 3
  buildings left over a road on purpose (passages). Ashdod: 44 and 352.
- Corners laid piece by piece (touching another road): Givatayim 920, Ashdod 2794.
- **The whole frame, Tel Aviv** (`tests/perf_dive.gd` level 7, everything built, 20 Nov
  2026; the view and the shadow pass together): at the start, quality 2, 2.41 M triangles
  and 635 draws, of them parked cars 1.24 M -- grouped by 400 m square, every one drawn to
  ~420 m (see "Parked cars" below). With 100 m squares and a far shape: 1.69 M and 641
  draws; a main road 1.81 -> 1.19 M; from above 2.20 -> 1.38 M. What is left in view at the
  start: the batched tone meshes 0.87 M, parked cars 0.31 M, tree crowns 0.14 M, palms 0.12
  M, trunks 0.08 M. The script's own frame while driving, headless: ~3 ms a tick (traffic
  1.3, people 0.7, traffic's following 0.4, minimap 0.3) -- the cheap part.
- **Memory, Tel Aviv**: video memory 575 MB, of it 505 MB vertex buffers: 19.5 M static
  vertices, 16 M of them in the batched tone meshes (every batched copy's vertices written
  out: 9.6 M from vertex-coloured kits, then tanks 0.8 M, poles 0.8 M, furniture 0.75 M,
  railings 0.5 M), the contact shadows 1.1 M, kerbs 0.9 M. Triangle soups, none indexed.
  Nodes 8,134 (4,989 before the parked cars' 100 m squares); 74 shader kinds (each one
  compiled in the warm-up). Who made the copies (`perf_dive`'s "batched, by who", a debug-only
  tally in `_batch_add`): the cast-iron grates and pits round the street trees' feet (384 and
  534 vertices a copy) 3.5 M, balconies and facade kits 2.5 M, roof kits 0.8 M, bins and
  bollard kits 1.1 M, cats (1,182 a copy) 0.45 M, terraces 0.5 M. Since a kit of more than
  `BATCH_KIT_VERTS` (200) stays a multimesh: 13.4 M vertices, video memory 445 MB (buffers
  374 MB, -131), the start view 668 draws (+27) and 1.75 M triangles, 9,278 nodes, 84 shader
  kinds (materials x instanced: the instanced kits' materials count again, though look-alike
  StandardMaterial3Ds share one compiled shader).

## Cities

Re-bake with `main_server_only` on, and diff the counts against the file it replaces
(`git show HEAD:<file>` and compare roads, buildings, crossings, areas): a mirror twice
answered with ~12% fewer road pieces. Last re-bakes: Givatayim and Tel Aviv, 20 Nov 2026
evening, for the extra fields (see "OSM's extra fields and speed limits" below); Ashdod and
Bedford have not been re-baked since.

| Level | City | Bake (`bake_city.yml` inputs) |
|---|---|---|
| 1 | Givatayim (look "med") | place "Givatayim", margin 250 |
| 2 | Bedford, Nova Scotia ("north") | place "Bedford, Nova Scotia", include "Hemlock Ravine Park; Kearney Lake; Sandy Lake; Fleetview Drive" |
| 3 | Ashdod ("med") | place "Ashdod" |
| 4 | Kiryat Dimyon, made up | `tools/fake_city.py` |
| 7 | Tel Aviv, a box of the centre ("med") | place "Tel Aviv", bbox "32.0639,34.7795,32.0858,34.8021" (read off the user's map screenshot), margin 150, bare_ground on (without it Azrieli stood on a 146 m hill of its own roofs) |

The start points are public street corners named in `LEVELS`. **The web build is public:
never use an address the user has mentioned as theirs or their family's -- not as a start,
not in a test, a commit or a doc.** Scratch tests against one stay in the scratch directory.

Givatayim's start moved on 20 November 2026 to Katznelson by Weizmann, at the user's
request (it had been a quiet residential corner since the city was added). Results of tests
that look "near the start" (the narrowest streets, the nearest lights or roundabout, the
exam's first place, the draws and frame cost at the start view) from before then are from
the old corner: rerun before comparing.

## What a filmed walk showed (November 2026)

A walk filmed with GPS along a quiet residential street and a shopping street in
Givatayim, set beside the game from the same spots (`tests/filmed_spots.gd`). The layout,
the zebras at the right corners and the lights at the main road matched. The rest, biggest
first:

- **Buildings**: the game's are white-grey boxes with dark window bands and black ground
  floors. The real ones are warm cream and sand plaster, balconies with railings (many
  closed in), AC units on the walls, shutters, shopfronts with awnings on the shopping
  street; 15-25 storey towers stand behind the low blocks.
- **Between pavement and building** (wooden boards on a fifth of the walls done,
  `_plank_fence` in `_garden_fronts`): front gardens behind low rubble-stone walls, often
  with a wooden plank fence on top, hedges, bushes, iron gates. The game has a low white
  wall and grass, or the building right at the pavement.
- **Pavement**: the game's is near white in the sun. The real one is mid-grey: 20 x 10 cm
  pavers in straight rows along the residential street, with a darker band along the kerb;
  rounded brown "antique" pavers with grey cobble arcs by the cafes. Herringbone is right
  for some streets, not all.
- **Kerb paint** (done: `_kerb_paint`, `_kerb_marks`): blue-and-white along the residential
  street (paid parking), red-and-white at the corners and driveways. The game painted one
  paint a whole street, a tenth of them yellow-and-black.
- **Parked cars** (done, fill by the kerb's paint, `PARKED_FILL`; motorbikes too,
  `_park_moto`, `tests/street_fronts.gd`): an
  unbroken row on both sides of the residential street, motorbikes and scooters parked on
  the pavement; painted bays on the shopping street. The game filled a quarter of the kerb.
- **Street trees**: thin trunks in square earth pits at the kerb edge every ~8-10 m, the
  canopies meeting over the pavement; no palms on these streets.
- **Shops** (second pass, done: `_shop_pieces` keeps gardens out from in front of shops and
  widens the pavement there by `SHOP_PAVE` to the shop windows -- without it a strip of bare
  grass was left between a 2.4 m pavement and the shopfronts;
  Sirkin's rows are `lines` of kind shopfront in `cities/details/givatayim.json`, placed on
  the city file's building edges parallel to the street just behind its pavement): OSM knew
  six businesses along the walk; the film, panning, showed a row down both sides of Sirkin
  -- a green corner shop, a bar under string lights with bar stools, shuttered shops,
  Roladin's posters on its Sirkin side, the sabich stand's red umbrella and the
  greengrocer's produce across the street, white scalloped awnings near Katznelson. The
  game had gardens there and one bright awning per OSM shop. Each shop's own look is now in
  the details file's `shops` (details.gd has the format; `_build_pois` reads it through
  `Details.shop_look`); `tests/shop_looks.gd` stands in the street facing each one and
  prints where its front went. Awnings and umbrellas are instance-coloured (`_awning_col`,
  `_real_col`), no longer one glowing palette material per role.
- **Reds and blues that are real things' colours** (car paint, kerb paint, sign plates,
  hydrants, scooters, awnings by name) are hue-pinned `Color.from_hsv` with their
  saturation and brightness taken from the palette: from the palette's hazard and player
  roles directly they came out pink and teal beside the film. `_real_col(name)` gives the
  named ones.
- **Setts and string lights** (details `setts` on a street, `lights` on a shop): `_sett_fan`
  / `_sett_band` in the street trees' builder (round the trees of that street only),
  `_string_lights` in `_build_pois` (bulbs in `mat("warn", 1.6)`, wire in the crates' buffer).
- **Tests after the city is built cannot read `_city_data`**: the game lets go of the city
  file once every square is up (`_city_data = {}` after building), so a scene test looking
  for places there finds none. The built places are in `_pois` ([spot, role, name sign]).
- **The map's outline at the kerb**: on Sirkin's west side the sabich stand's building
  outline runs to within ~1 m of the kerb (OSM's upper floors), so no terrace fitted; a
  cafe's table and umbrella may now stand right at its window when the shop's look asks for
  an umbrella (`_terrace`'s third try).
- **Light**: the real late afternoon is hazy and warm; the game's sky is saturated blue
  with cartoon clouds and its sunlight bleaches the ground.
- **Small things**: black bollards with a yellow band along the kerb by the main road, a
  red fire hydrant, a push button on the walk light's pole, bar stools and awnings rather
  than umbrellas outside the cafes, green bins.

## The second filmed walk and the GPS pipeline (level 6): handoff

The session that set up filming with GPS (20 Nov 2026) and made "A walk in Givatayim:
Sheinkin and Sirkin" from it, then worked that stretch over pass by pass. The walk session
(level 5's) has since extended this walk to the Katznelson corner and owns its route.

- **The pipeline, for the next walk or drive**: the user films (phone, FHD 30, 1x) with Geo
  Tracker logging GPX at 1 s, uploads both to Drive; the GPX comes through the Drive
  connector, the video needs the user to share it by link for a few minutes and
  `drive.usercontent.google.com` allowed (real-places skill, "Filmed walks and drives").
  `tools/gpx_route.py report` reads the track against the city file; `route --video
  --from A B --to C D` makes a timed route; `tests/walk_snap.gd` puts it on the back of the
  pavements (spans of seconds per side and street); the result goes in the details file's
  `walks`. The film and its track are the user's and stay out of the repo; a route in the
  game starts and ends only at public corners the user agreed.
- **This walk's film**: the route is 1:42 to the end of a 3:30 film (walk second 0 = film
  102.34 s). Side by side: `GODOT_ARGS="--fixed-fps 10" STREETS_BUILD_ALL=0 RECORD=1
  RES=1280x720 OUT=<dir> tests/run.sh filmed_walk 6` (1066 frames, ~22-25 min here), then
  `ffmpeg -ss 102.34 -t <frames/10> -i film.mp4 -framerate 10 -i <dir>/f%05d.jpg
  -filter_complex "[0:v]fps=10,scale=406:720,setsar=1[a];[1:v]crop=406:720:437:0,setsar=1[b];[a][b]hstack=inputs=2:shortest=1"`.
  The phone's own file seeks right with `-ss` (constant 30 fps); a VLC re-encode does not.
- **What it put in the game** (each in "What a filmed walk showed" above): kerb paint by
  place and parking by paint, motorbikes on pavements, board fences on garden walls, no
  garden in front of shops and the pavement widened there, Sirkin's shopfront rows and each
  filmed shop's look (`shops`), per-street paving and setts, string lights, bollards, a
  hydrant and bins, real reds and blues, the start moved to Katznelson by Weizmann.
- **Its tests and good numbers**: `filmed_spots` (stills from GPS spots: mid-walk spots
  move 0-2 m onto their pavement), `walk_snap`, `shop_looks` (5 shops on Sirkin, all on
  walls, Roladin 3 tables under white umbrellas, Kira Sushi's lights and stools),
  `street_fronts` (~2900 parked motorbikes, ~5800 fence pieces in Givatayim), `filmed_walk`
  with `SCAN=1` on level 6 (clean after the walk session's moves) and `AT=` for stills.
  Parking by paint cost +17% triangles at the old start view (frame_cost, above).
- **The details file is written by a tool too** (`make_givatayim.py`, `json.dump(indent=1,
  ensure_ascii=False)`, no trailing newline): edit it by loading it and dumping it back with
  the same settings (the round trip is byte-identical), never by text insertion, or the
  next re-run reformats your lines into a large diff.
- **Open**: painted parking bays on Sirkin (not done: the game parks half on the pavement,
  and an 8 m two-way street has no room for cars wholly in the road beside its lanes); the
  setts fan round the game's own trees, which are not where the filmed ones are; the
  west face of Sirkin's last block (5.2 m from the centre line, OSM's upper floors) has no
  shop row; buildings and light are the realism session's; the drive is to come (the user's
  next film): `gpx_route.py report` by road kind against autodrive's 50 km/h everywhere.

## The filmed walk (level 5)

A walk filmed on a phone in Givatayim, from Katzenelson by the Ha-Meri passage to Ha-Meri
past Sheinkin, replayed in first person (`_film_begin` / `_film_tick` / `_film_at` in
streets.gd, "a filmed walk, replayed"). It is how that street is being made realistic: a
pass at a time, biggest differences first, each pass checked with a side-by-side video.

- **The route** is `walks.katzenelson_hameri.points` in `cities/details/givatayim.json`
  (written by `make_givatayim.py` beside it):
  [seconds, x, z], the seconds the film's. Landmarks in the film: off the north kerb 1.5 s,
  the far kerb 16 s (the road ~17 m across by walking time with its median; the game's
  halves are 7 m each since pass 4), the forecourt 25 s, into the passage 33 s, out of it 64 s, the
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
  filmed_walk 5` (1280x720; about 18.5 minutes for its 966 frames), crop the middle 406x720
  (the 70 degree vertical field of view then matches a phone held upright) and `hstack` the
  two. The film itself is the user's: it, its frames and anything past Ha-Meri never go in
  the repo. The recipe that made every side-by-side so far (frames symlinked to
  `g%05d.jpg` from 0 in their own order first, so frame 0 is the walk's 0 s): `ffmpeg -i clip.mp4
  -framerate 10 -i g%05d.jpg -filter_complex "[0:v]hflip,scale=406:720,fps=30,trim=0:96,
  setpts=PTS-STARTPTS[a];[1:v]crop=406:720:437:0,fps=30,trim=0:96,setpts=PTS-STARTPTS[b];
  [a][b]hstack=inputs=2[v]" -map "[v]" -c:v libx264 -crf 24 -pix_fmt yuv420p out.mp4`, with
  `drawtext` labels ("phone", "game", `%{eif\:t\:d} s` at the foot) -- 36 MB; re-encode at
  `-crf 30` (13 MB) to send it.
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
- **How long a pass takes to check** (one Godot run at a time; measured 20 Nov 2026 after the
  city learnt to load in steps -- it was twice as slow before): the scan (`SCAN=1`) about
  1 min, the recording (`RECORD=1`, 966 frames) about 18.5 min, the side-by-side under 1
  min, the three playtests (levels 5, 1, 6) about a minute together -- the whole chain about
  21 min. Tell the user so when you start it.
- **Other sessions' city-wide things land on the walks' lines after a merge** -- bollards,
  café tables, and the front gardens' bougainvillea clumps that hang over a pavement's back
  (`_add_post` 0.45 m off the garden wall, r 0.22: two of them on walk 2 at 1 s and 29 s).
  `SCAN=1` finds them; `POSTS_NEAR=x,z,r` lists the posts there and also the nearest road's
  edge and which way the road lies, so the walk can step to the road side by the right
  amount. Where a clump and a tree in the pavement leave less than half a metre, the walk
  goes round the tree's road side as a person would, and Catmull-Rom cuts the corner: keep
  0.65 m off a tree's centre at the points either side, not just at one.
- **The scan sees posts only.** A bike in a rack is solid only at its hoop (r 0.35) but
  reaches 0.85 m each side of it, across most of a pavement; café chairs, crates and low
  leaves are not posts at all. Walk 2's first full recording went through a parked bike's
  wheel (86 s) and ended with a tree's trunk filling the frame (1.0 m off), all with a clean
  scan. `POSTS_NEAR` now also lists everything drawn by instance there -- which group, where,
  its size, how high it starts and ends -- which told the bike, the tree and a shop's crates
  apart in one run. Look at a recording one frame every 2 s as well as scanning. Walkers
  still walk through the city's parked bikes (racks are another session's furniture: giving
  the bike posts would leave 0.4 m on many pavements, so walkers need a way round first).
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
- **Pass 6, the little street and the shops' faces**, done: three cars parked along the
  little street's far side (`parked_car`: the game's own cars; its parking rule turns that
  kerb down, the corner block stands too near), a tall hedge on the back of the walk's
  pavement there, a second twin-pole transformer at Sheinkin's corner; the confectionery's
  sign lettered (a `Label3D` in the game's font, which falls back to Noto Sans Hebrew) and
  its yellow boards in the window -- only the shop the film shows is named; shop windows
  dark reflecting glass by day; the slabs warmer (sunlit, the film's are warm beige).
- **Pass 7, people and the last small things**, done: the people the film shows, where it
  shows them (walks' `people`: standing, or walking between two spots over two film
  seconds -- a man by the far kerb's railing, two women in the forecourt, a man at the
  passage's end); the bollards round Sheinkin's corner white (`white_bollards`: the kerb
  pass's own white ones, at the zebras near a spot); the blue pay booth, a yellow parking
  board and two scooters on Sheinkin's far corner (in the room POSTS_NEAR found between the
  zebra's bollards and a sign pole); the little street's gateposts, one with a heart.
- **Pass 9, the phone in a hand**, done: measured against the film rather than by eye
  (`scene-tests` skill, "A camera set beside a real film"). *Tilt*: the film's horizon sits
  0.30 of the way down its frame nearly all the way (one frame a second, under the arcade, in
  the passage, on the little street, on Ha-Meri); the replay's sat at 0.36-0.38, the phone
  11.3 degrees down against the film's ~16. Now `FILM_TILT` -15.6 degrees. *Looks up and
  down*: a walk's `looks` take a fourth number, degrees up (the film looks straight down at
  Katzenelson's stripes at 6-8 s, a foot in shot, and at Ha-Meri's kerb as it steps up,
  92-95 s). *Sway*: `film_shake.py` over the passage (36-52 s) gives the film 0.25 degrees
  rms across and 0.19 up and down, 0.6 peak to peak, at 0.5-0.8 Hz and nothing at the step
  rate (the phone's stabiliser); the replay had 0.01 and 0.03 -- dead still. Now
  `_film_hand()`: sums of slow sines at those sizes across, up and in roll, two thirds of
  it standing. Ha-Meri's last look (60 right, 91.6-94.5 s) turned the camera onto a tree
  pit's trunk 0.56 m off the walk; the film looks down at the kerb there instead.
  Measured on the recording after: 0.11 / 0.10 degrees against the film's 0.25 / 0.19 --
  `film_shake.py`'s 1 s running mean takes out much of a slow sway, so the sizes in code
  were doubled to read as the film does (match the tool's reading on both, not the code).
- **Pass 10, the phone's picture and Ha-Meri's far kerb**, done. *The picture*:
  `tests/film_look.py` (one frame a second, film against a bare replay) found the phone's HDR
  squeezing the bright end -- its brightest 1% stops at 0.87, 0.1% clipped; the game clipped
  4.4% to white and its bright quarter sat far above -- and lifting the dark (the shade on
  the ground at 0.23 against 0.11), greys a little warm where the game's were a little cyan,
  colours less saturated (0.159 against 0.190). It is *not* a blown-out sky, as it looked by
  eye. The fit is a 17-point curve, a 6% warmth fading out over the brightest tones, then
  saturation x1.129, drawn by `_film_look_layer()` over the finished frame on filmed walks
  only (`STREETS_FILM_LOOK=0` turns it off, to measure the bare picture or refit). In the
  game it gives what the fit predicted to the hundredth (levels and saturation, same frames
  on and off), so the screen texture a canvas shader reads is the same 8-bit sRGB a
  recording saves. *Ha-Meri*: the film steps up at the raised crossing's far end beside a
  silver hatchback parked just past it, on a blue-and-white kerb; the game had a red-and-
  white corner kerb and a front yard's car standing on the pavement (the yard code's road
  width is not this corner's: its middle 0.6 m off the kerb). Now a `clear` spot there
  (which the yard car, the greenery over walls and the kerbside furniture all respect), the
  hatchback (`parked_car` takes `paint` now) and blue-and-white `kerb_paint`. And a
  bougainvillea from the front gardens had grown across the little street's pavement at eye
  height by the graffiti gatepost (film 71-76 s, bare): a `clear` spot too.
  Measured on its recording: sway 0.25 / 0.21 degrees (the film's 0.25 / 0.19); levels at
  1-99% within 0.05 of the film's, 0.0% clipped, saturation 0.146 (0.159). The look down
  Ha-Meri at 89-92.5 s is 55 degrees: at 80 the hatchback sat at the frame's right edge
  where the film has it dead ahead with the kerb on the left (AT stills at 91 and 92.3; the
  film frame by frame). AT names its stills by whole seconds: 92 and 92.3 save to one file.
- **Pass 11, the arcade's dark and Katzenelson's traffic**, done. *The arcade*: under it the
  film's floor read 0.39, the game's 0.14-0.18. Two causes, measured apart. The phone exposes
  for what it sees: the film's brightness second to second held at 0.45 +- 0.055 while the
  replay's swung 0.48 +- 0.12 (0.28 under the arcade, 0.64 on the sunny forecourt) -- so the
  grade got an exposure (`FILM_EXPO`): a meter reading the whole screen off its mipmaps (16
  taps at mip 7 read the true mean within 0.015; `STREETS_FILM_LOOK=meter` paints the reading
  in a corner to check it), the frame pulled towards 0.45 by (0.45 / mean)^0.75 in light, the
  curve refitted after it (0.455 +- 0.070 fitted). But exposure alone left the floor at 0.31 in
  every setting: the arcade's "charcoal" pavers were five times darker than the game's other
  paving. `pavers_dark` now 0.62 of the way to bg_alt (was 0.8): the floor 0.31-0.36 in AT
  stills against the film's 0.38-0.41. *The traffic*: the film at 8-14 s, half a second at a
  time -- a white hatchback by in the far half's lane by the median as the walk reaches it
  (9 s), a white sedan stopped in its kerb lane (9.5-12 s), a grey SUV driving on past the
  walk in the median lane, close (12.5-13.5 s); the walk faces across meanwhile (its look right
  was 70 degrees, now 15). `Traffic.send` takes `opts`: "lane" kerb / median, "through" (past
  the walk's own zebras only: `_zebra_ahead` skips the film-tagged ones), "kind", "paint".
  A sent car starts at 70% of its street's pace: 28 m to the zebra on Katzenelson is 2.5 s.
  AT stills jump the walk's clock, so scripted cars never drive their timing in them:
  `TRAFFIC_LOG=from,to` runs the walk at its pace and logs the cars round it -- the hatchback
  3 m in front at 9.0 s, the SUV 4 m in front at 13.0-13.5 s.
  Measured on its recording: each second's brightness 0.471 +- 0.061 (the film's 0.454 +-
  0.055); levels within 0.05 of the film's, 0.0% clipped, saturation 0.146. In the
  side-by-side the hatchback passes at 8.5 s (the film's 9), the sedan waits from 10 s, and
  the SUV crosses in front at 13 s where the film's does at 12-13 s: send it half a second
  sooner if it matters.
- **Pass 12, Katzenelson's crossing as filmed (film 0-13 s)**, done. The film a quarter second
  at a time showed what the side-by-side's seconds had hidden. *The ground*: buff domed
  slabs (tactile paving) along the north kerb across the zebra and filling the cut through
  the median, the median's ends either side of the cut raised blocks -- red pavers in a grey
  concrete kerb, a "no U-turn" sign on the south-east one -- and a black bollard with a steel
  top on the slabs at the zebra's north-west edge. The tone shader's kind 8 (`tactile`:
  0.3 m slabs, 6 x 6 domes each, lit by bending the normal, fading to the slab's tone before
  they shimmer), `pavers_red`, a raised block as a `kerb` surface with paving a shade higher
  and inset on it, `bollard` `top: "grey"`, `no_uturn_sign`, `kerb_paint` `pat: "plain"`
  (bare kerb over a street's paint). *Where it stands and looks*: the far side's shop fronts
  sit level in the film's frame at 1-2.5 s, so it faces straight across, not 70 degrees left
  as by eye; the bollard's foot sits 0.68 of the way down the frame -- with the horizon at
  0.30 and a 70 degree field that is 30 degrees down, 2.5 m off -- so it waits 2 m back from
  the kerb, then steps up beside the bollard (3.7 s); on the median it stands by the cut's
  south-east side, the sign's block half a metre off (7.7-9 s). A walk's first facing is the
  way from its point at 0 s to its point at 1.5 s (`_film_begin`): a first step along the kerb
  had it face up the street for its whole wait. *The cars*: the film shows five in its first
  17 s, not a stream: a black hatchback by in the near half's lane by the median (2 s), a white
  SUV close past the kerb (3 s), then the far half's three. A car sent 39 m up the near half
  was held 2 s at a junction 32 m off and crawled past at 7 s (`TRAFFIC_LOG`): send from past
  it. Measured on the recording: the hatchback at 1.5-2 s, the SUV in front at 3 s, the grey
  SUV at 12.4 s (the film's 12-13); brightness 0.473 +- 0.061, levels as pass 11's. After
  the evening's traffic merge (bus lines, the car mix) the grey SUV, sent at 10 s, passed at
  11.5-12 s in one run and 13.5-14 s in the next (the street's other cars slow it or not):
  now sent at 9.5 s; and a city bus on its real line waits at the near zebra 7.5-11 s.
  Still wrong there: the north kerb north-west of the zebra shows the city's blue and white
  where pass 4's red and white `kerb_paint` (at P(-14.0, -23.95)) should be -- it finds the
  right road, segment, side and height (printed) and draws nothing visible, while the same
  call 6 m south-east shows; the city's own guard railing stands beside the bollard where the
  film has none.

- **Pass 13, the pace and the head as filmed, the people moving**, done. Measured on every
  frame of the film (30 a second), not landmarks or one frame a second: `tests/film_motion.py`
  reads the camera's facing from the far band's slide across each pair of frames (the median of
  six tiles: a car passing fills one or two and alone dragged the reading 60 degrees), and the
  pace from the ground's slide down the frame less the far band's (a pinhole's sums: f
  sin^2(theta) / (h cos^2(alpha)) pixels a metre). The replay is measured by its
  `CAMERA_LOG` (the test's new mode: the camera every 0.1 s at the walk's pace, ~10 min at
  320x180, --fixed-fps 10), not from its recording: at 10 frames a second its pavers'
  pattern repeats within one frame's slide and its ground read 0.2 m/s for 1.4. Lined up on
  the passage (36-52 s), the two facings agreed there and on the little street to a degree or
  two -- the film's summed facing barely drifts over a minute -- and differed at the passage's
  end (the replay's body turned 50 degrees right onto the little street's pavement, the
  film's did not), at Sheinkin's corner (the film looks right at 79-81 s and then turns left
  smoothly to 90 s; the hand-set looks went left at 81 and 88 s) and on Ha-Meri (91-96 s: the
  film faces the far pavement's white wall and e-scooter, the replay looked down the pavement).
  `tests/film_fit.py` then fits from the far kerb on (17 s): between kept anchor seconds (17,
  25.6, 33, 64, 80, 87, 91.5, 96) the replay's own path at the film's share of the distance
  (the streets' lengths are not the street's), capped at 2.6 m/s, points every 0.5 s; and the
  head's turn = the film's facing less the body's (the body worked out as `_film_tick` does)
  every 0.25 s. It writes `cities/details/katzenelson_fit.json`, which `make_givatayim.py`
  takes in: the walk's points from 17 s and its new `"head"` -- [second, degrees right of the
  body], played by `_film_tick` where it runs in place of the turn into bends and the looks'
  turns (their tips up and down still apply). After it: the facing within a few degrees of the
  film's from 19 s to the end (`motion_after` chart); the pace the film's shape, 0.3-0.4 m/s
  quicker from 64 s (the replay's streets are longer there) and 2.4 m/s under the arcade (the
  replay's route from its zebra is ~7 m longer than the street's). Not fitted: 0-17 s -- the
  film's facing there is cars and stripes (the phone looks down), so the crossing keeps pass
  12's frame-read looks. Re-fit after moving any walk point past 17 s (`CAMERA_LOG`, then
  `film_motion.py log`, then `film_fit.py`): the fit follows the path the replay walked.
  *People*: the man by the far kerb's railing walks there along the confectionery's front
  (12.6-16.6 s), a third person stands with the two women in the forecourt, and the three
  "talk" (people's new `talk`: no clip for it in the kit, so each turns a little to the others
  and back, two slow sines), a woman crosses the passage's end in front of the man in blue
  (59.4-63.2 s).

  *Merging main after it*: the black hatch at the crossing passed at 4.4 s, not 2. Not the
  merged traffic: `send` takes the car furthest off from the pool, and `_start_on` reset its
  want, wait and hit but not its smoothed `acc` -- this one came with -7 m/s^2 from a hard stop
  in its last life and braked to 3 m/s with "limit" as its reason and 14 m/s as its want (seen
  only in a tick-by-tick line of v, want, acc). `_start_on` now resets acc, braking, react_t,
  still, blocker, holding and the stop sign it last stopped at (all three of its callers put a
  car down afresh: spawns, kerb pull-outs, film cars). Likely the grey SUV's 0-1.5 s spread of
  pass 12 too. After: the black hatch past the zebra at ~1.8 s (the film's ~2), the white SUV
  at 3.2, the white hatch at 9. The walk test's TRAFFIC_LOG prints each car's `why` now.

### Handoff: the filmed walks (20 Nov 2026, after pass 13)

- **In progress**: nothing. Pass 13 is on main; the list of what is still different is
  `WALKS.md` (walk 1's details, behaviour and quality, walk 2's, both walks'), with a Done
  section that points back here.
- **The biggest open items**, by what the side-by-side shows most: the buildings' faces along
  the route (cream and sand plaster, balconies, shutters: city-wide, another session's); the
  light (hazy, warm, soft shadows: another session's); people that move as the film's do
  (done for walk 1's: pass 13, but the forecourt's talkers and the man in blue are off the
  frame when the film shows them: WALKS.md, Behaviour, with the bearings); the north kerb's paint and the
  city's guard railing north-west of the zebra (pass 12, above); the cars parked along
  Katzenelson's far kerb the film shows across the road at 1-2.5 s; the arcade's columns (white with a dark wooden foot) and the second shop; Ha-Meri's
  far pavement (a low white wall, an e-scooter); the camera's last differences (a touch of
  motion blur, the lens's bend at the edges). Walk 2 has no side-by-side: its film (1:42-3:08
  of the user's video) has not reached a session; ask for it as a clip under 10 MB.
- **Commands** (all `tests/run.sh filmed_walk <level>`, `STREETS_BUILD_ALL=0`, `OUT=` a scratch
  folder): `SCAN=1` (posts and buildings on the line, a minute); `POSTS_NEAR="x,z,r;..."`
  (posts, the kerb's distance, everything drawn by instance, whether a `clear` spot covers
  it); `AT=s,s,...` (stills; jumps the clock); `TRAFFIC_LOG=from,to` (cars at the walk's own
  pace); `RECORD=1` with `RES=1280x720 GODOT_ARGS="--fixed-fps 10"` (18.5 min). The grade:
  `STREETS_FILM_LOOK=0` records the bare picture (to refit with `film_look.py`),
  `STREETS_FILM_LOOK=meter` paints the exposure meter's reading top left. Then the
  side-by-side recipe above, `tests/film_look.py <clip> <frames> 96 --check` (a graded
  recording against the film) and `tests/film_shake.py` (sway, straight stretches only).
  The movement: `CAMERA_LOG=1` (with `RES=320x180 GODOT_ARGS="--fixed-fps 10"`, ~10 min),
  then `tests/film_motion.py film <clip> 96 film.csv` (30 s), `film_motion.py log <log>
  game.csv`, `film_motion.py chart film.csv game.csv out.png`; to re-fit the pace and the
  head, `tests/film_fit.py film.csv <log> 17,25.6,33,64,80,87,91.5,96 17
  cities/details/katzenelson_fit.json` and run `make_givatayim.py`.
- **Good numbers** (walk 1, after pass 12): both walks' scans print only "scan done";
  sway 0.25 / 0.21 degrees rms across / up (the film's 0.25 / 0.19); levels at 1-99% within
  0.05 of the film's, 0.0% clipped, saturation 0.146 (0.159); each second's brightness
  0.473 +- 0.061 (0.454 +- 0.055); the arcade's floor 0.31-0.36 (0.38-0.41); the horizon
  0.30 of the way down (`FILM_TILT`); `TRAFFIC_LOG=0,14`: the black hatchback within 10 m at
  1.5-2 s, the white SUV 4-5 m off at 3-3.5 s, the white hatchback 3-4 m at 9 s, the grey
  SUV 4-5 m off at 12-13 s, give or take a second run to run. Playtests of levels 5, 1 and 6 survive 25 s; validate's
  Givatayim keeps its known 2 posts and 1 building on the road (the café table, the
  passage's building) and the test town's checks read 4-12.
- **Walk 1's coordinates for new props**: `P(s, off)` in `make_givatayim.py` along S0-S1
  (above). Katzenelson runs along `off` (within 2 degrees): its near half s -13.8 to -6.8, the median, its far
  half -3.9 to 3.1, the zebra 3 m wide at off -17.37 (the city's zebras are 3 m); Ha-Meri along the passage's line with its south-east kerb at off +4; the
  raised crossing s 89.6-96, its zebra at P(92.4, 0). The generator owns the items it marks
  `"src": "make_givatayim"` and keeps everyone else's -- other sessions add props to the same
  file, and walk 2's points were edited by hand there (not by the generator).
- **Where the camera's numbers live**: streets.gd's `FILM_TILT`, `FILM_CURVE`, `FILM_WARM`,
  `FILM_SAT`, `FILM_EXPO` and `_film_hand()` (sway sizes, doubled to read as the film's
  through `film_shake.py`'s filter). A change to the game's materials or light moves the
  grade's fit: re-record bare and refit rather than nudging the curve by eye.

## Off the ground: bridges, tunnels, cuttings, embankments (`decks.gd`)

A road whose city file has `y` (its surface's height at each node, decimetres above the
height grid's base) is a **deck**; its OSM tags say what it is built as (`br` bridge, `tu`
tunnel, `em` embankment, `cu` cutting). `tools/fake_city.py` writes `y` into the test town;
a real town opted in with `"decks": "infer"` (Givatayim, Bedford, Ashdod, Tel Aviv) gets it worked out as it
loads (below). Elsewhere a bridge without `y` is drawn on the ground and a tunnel without
it is dropped.

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
- **Embankments are grass banks** (`bank_at`, `_bank`): from the walkway's or shoulder's
  edge down to the ground, 1.5 m out for each metre down, a steel guardrail on posts along
  the top -- wherever the bank's middle and foot land clear of other roads and buildings;
  elsewhere (the test town's ramps between houses) the retaining wall and parapet as before,
  the wall reaching a segment into each change. Collisions match: on a bank a guardrail for
  the car on top and the bank's foot (as steep as a wall) for one on the ground beside it.
- **Junctions in the air.** Where only decks meet (the interchange's slip roads joining
  HaZayit up on its embankment) the junction is drawn by `decks.gd` at its height (no node
  in `_tile_nodes`, so no signs or lights there). A parapet, its wall and the walkway open
  wherever another deck's road comes in (`open_at`, drawing and collisions alike), and a
  ramp's walkway gives way to a street's asphalt where its foot runs into one (the slip road
  merging into the boulevard). Walls are left out of the collisions in a junction's corner
  only at street level -- up on the embankment that would leave a gap to drive off.
  `_clear_ends` says how far: the junction's middle + 6 m from an end that starts at street
  level at a junction. A bridge (`br`) too, but only while its deck is within `CLEAR_LOW`
  (0.6 m) of the ground, and its drawn parapet with it (`_raised`'s `gap_wall`): Bedford's
  highway bridge starts at Union Street's junction, and autodrive turning out of Union Street
  ran into its parapet. `tests/deck_corner.gd` drives that turn every way.
- **Water held at a level** (`areas[].y`, the test town's river) lies at that level, and is
  too deep to drive or walk into (`_deep_push`): the banks were gentle enough to drive down
  and along the bed under the water. Lakes and ponds without a level are as before.
- **A real town's heights, worked out as it loads** (`infer` in decks.gd; a place opts in
  with `"decks": "infer"` in `LEVELS`). Before the roads are read, the
  city data gets heights as if baked: where a drivable bridge (a chain of bridge ways 8 m
  or longer; shorter ones are culverts and stay as they were) crosses a road it must clear
  it by 6.4 m (a path: 4.4); that lift spreads along the drivable roads at a ramp's grade
  (5% motorways and slip roads, 7% the rest) as an absolute height -- the road's own
  grade, not its height over a ground that may fall away too (on Larry Uteck's ramp the
  ground fell 8%: 15% in all, the car hopped down it) -- through junctions, never onto the
  roads crossed (held to the ground). A second pass caps every lift by what a ramp from the
  nearest held point can climb (7% / 10%), so a too-short slip road is steep, not a cliff.
  Bridge over bridge: OSM's layer, else the lesser road over the main line, clearing the
  lower's deck. Roads are cut where their ramp meets the ground (a node put there); the
  lifted pieces get a point every 6 m and their profiles rounded over the crests (junction
  points kept); a road's lift never spreads onto a footpath (below). Bedford: 56 bridges, 72 crossings, ~190 deck
  pieces, 0.2 s; 0 of 63 crossings over roads short of the full clearance (2 when first
  written, 4.8 m the lowest). `LEVEL=2` with `tests/decks.gd` drives its ten highest bridges
  both ways. What `infer` made of a town -- bridges, tunnels, footbridges, crossings short of
  the clearance and where (`short_at`: the first 12 only), tunnels left out and why -- is the
  `decks_inferred` line in any playtest's timeline (`LEVEL=n tools/playtest.sh streets idle
  10`), no scene test needed.
- **Tunnels, worked out the same way** (Ashdod): a drivable tunnel way 20 m or longer that
  runs under a road or path lies 6.2 m down along all of it (OSM's tunnel way is the covered
  part); the depth rises back to the ground along the roads either side -- cuttings -- at a
  ramp's grade, never through a junction (that stays at street level) nor onto what it runs
  under, kept as negative lifts so the rest treats bridges and tunnels alike. Where the
  nearest held point (what it runs under, a junction) is too close for the cuttings to get
  down at 8.5%, the tunnel is left out as before (on the ground it would run across the roads
  it dives under); one under nothing mapped (a passage through a building) is put back on
  the ground (it used to be left out). A body in a tunnel never meets the buildings over it
  (`_push_out`), however shallow the tunnel is there. Ashdod: 46 bridges, 4 tunnels (Menachem Begin's underpass, two service
  roads), 7 cuttings, 0.3 s -- now 2 tunnels: the service roads' are left out, too short for
  their cuttings (4.7 and 5.4 m of room). Two traps on the way: a tunnel "crossed" its own next piece
  (the shared end point; skip roads that share a point), and holding the whole of every
  road crossed, or seeding the depth's room from every junction in town, made it 15 s and
  held the tunnels' own ends at street level -- only near the crossing (80 m) now.
- **Footbridges and footpath tunnels** (`infer` again, the same passes on the paths' own
  network: footway, path, steps, cycleway, pedestrian, bridleway). A footbridge chain (8 m or
  more) clears a street by 5.8 m (`CLEAR_FOOT`; a path by 3.4) -- the street's final height
  there, not the ground's: a footbridge holds nothing down (a road bridge holds the street
  it crosses to the ground); once the streets' lifts are known each footbridge over one is
  raised to clear it (`foot_over`, `footbridges_raised` in the report) -- its lift spreading along the
  paths only, at 25% (`FOOT_RAMP`) or 60% on OSM's steps (`STAIRS`), and never onto a point a
  street has: a path comes down to the pavement where it meets a street. A footpath tunnel
  under something lies 3.6 m down (`CLEAR_UNDER_FOOT`), its ramps down to it the same way; one
  that ends under the ground (the City tunnel's footpath stops there in OSM) is left out.
  The networks are kept apart: a road's lift never spreads onto a path, and a path's point
  that a street has keeps the street's level (`lift_of`) -- without that, a sidewalk joined
  to a tunnel's road at one node got a 6 m dip and became a deck, and the pavement off a
  bridge's ramp rose 5 m in 2 m. A last pass holds every path to stairs' steepness from the
  nearest street point (`stair_capped`, 0 in all three towns once the networks were apart;
  run only near lifted paths -- from every street point Ashdod's load took 2 s). Drawn:
  paved like the pavements (`Y_PATH`), a 0.6 m slab (`FOOT_SLAB`), a steel railing instead
  of the parapet (`_railing`), treads every 17 cm where a path deck is steeper than 30%
  (`_stairs`), the tube 2.8 m high (`FOOT_TUBE`), a little wider than the path, one row of
  lamps. Givatayim: 22 footbridges (the Diamonds Bridge over the Ayalon, Dr Isaac Derazia's),
  3 footpath tunnels; Bedford 24 (most of them its trails' bridges over creeks, spanning bank
  to bank at the banks' height); Ashdod 6 and 2 (its two spiral stairs left on the ground).
  `tests/foot_decks.gd` walks them: Givatayim's 8 routes, Bedford's 4, Ashdod's 3, all to
  their far ends at their full height or depth, 0-18 frames off the level (the walker's
  height eases after the surface: up to 1 m behind running up 60% stairs). A route's last
  few metres run on past the path's end and can walk into something (Bedford's Duke Street
  sidewalk-bridge ends at its abutment: "got 91%" there is that, not the bridge).
  What walking them found: a road bridge's piers stood on a footbridge's foot and across a
  footbridge running alongside a few metres lower (piers now keep off paths and off any deck
  below their top); where three footbridge pieces meet, one piece's railing ran across the
  way onto the next (walls were checked for "another deck comes in here" at their middle;
  a footpath's are now cut into metre pieces, each checked, and its deck drawn every metre);
  a two-point stair ramp down to a tunnel tied the embankment/cutting vote and came out an
  embankment, with no hole cut in the ground (a tie goes by the sum); an OSM fence across a
  footbridge's foot stopped you on its first metre up (a body on a deck off the ground no
  longer meets the fences and posts down on the ground: `off_ground`); Duke Street's
  sidewalk, mapped as its own footbridge beside the road's, stops 2.5 m up on the span (a
  path's dead end now holds the ground like a street's point: it comes down by a stair);
  and a spiral stair mapped as one steps way lies on itself, its railings crossing (a path
  that comes within 0.8 m of itself stays on the ground and holds it; a ramp's hairpin legs
  are further apart -- 1.5 m caught the Diamonds Bridge's zig-zag ramp). And one not about
  decks: on foot you pushed yourself off where you stood last tick (the people list has you
  in it, `_people_push` did not skip you) and ran at 35 m/s.
- **What Bedford found** (the test town had hidden them): a divided road's two carriageways
  overlap at the median at not quite the same height -- `surf` now ranks what is under a
  body: the carriageway it is on, then a deck's pavement or parapet, then (where another
  deck carries on) just past a deck's end, then the ground; of each the one nearest its
  height. A car on the outside of a bend where two decks meet was past the end of one and
  before the start of the other, and fell through (hence "just past the end", 3 m, only at
  deck joints). Buildings OSM maps under a low approach (the MacKay Bridge's) stood in the
  deck: decks under 4 m up are now cut back from like streets (`_clip_buildings`).
- **`surf` and the streets over them.** `surf` ranks a deck whose carriageway a body is
  over before the ground (the divided roads' overlap, above) -- and a tunnel 7 m under a
  street is one: a car on Kaplan dropped into Lova Eliav and hit its wall. A deck more than
  1.5 m under ground the body can reach is now passed over (inside the tunnel the ground
  overhead is out of reach, so it is still found). And on a street's asphalt over a
  cutting or a tunnel (`_street_over`, looked up only there), the street carries a body at
  its level: the ground counts over the cutting, and anything under it at all is passed
  over -- a street across an underpass's mouth, a cutting's shallow top under a street's
  lanes. A cutting's wall where a street's asphalt lies over it is not solid either (a car
  on Kaplan hit the Lova Eliav cutting's wall where it starts at the kerb).
  `tests/street_holes.gd` samples every street's asphalt for both -- what a car there
  stands on, and whether a deck's wall stands there at street level: Tel Aviv 1011 points
  over a hole, then 6 (on the HaShalom bridge's west ramp, 0.6-0.9 m: a bridge ramp, not a
  tunnel); the test town 1, then 0. Walls: Tel Aviv 66, Ashdod 80 -- piers standing in the
  Ayalon's lanes among them (a pier spans the deck's width, and was checked against other
  roads' lanes at its middle only: now at five points across), then 41 and 51.
- **What Tel Aviv found** (another session wrote its own tunnel inference first, a
  mirror of `infer`; this one's found, and its fixes kept): the other half of a divided
  road crossing a tunnel's line where the halves close in at a mouth counted as a road over
  it and held Begin's southbound underpass on the ground (same name: skipped); Lova Eliav's
  two short links into Begin's underpass run under nothing mapped, so they went back on the
  ground as passages, the junction they meet became a street junction, and held the tunnel's
  east end up (a tunnel way below the ground that joins a tunnel at an end is a branch,
  dug with it). With both: 34 tunnels dug, the rest put back on the ground are car park
  ramps, a passage under a building and two branch ramps too short to climb out. And the
  car's own physics: it took the surface's rise in a frame as its climb, so the 0.2-0.3 m
  seam where two decks overlap at a junction in the air read as 17 m/s up and threw the car
  3 m over the Modai bridge -- a rise faster than STEP_GRADE (0.3) of the speed is now a
  step, climbed (`_fly`); Modai's 197 frames in the air became 6, and the test town and
  Bedford are the same with and without it. Building its own version first (dropped for
  the other's) also found: crests where a cutting meets the street at full grade, and
  humps in a tunnel where a branch climbs out, launch cars at 30-50 km/h (a vertical curve,
  rounding) -- not yet in `infer`.
- **Hops at ramp tops** (Nov 2026): Moses, Arvei Nahal, Yitzhak Sadeh and the City tunnel's
  mouth in Tel Aviv, Ashdod's Begin underpass and Laskov bridge, a Givatayim tunnel: 6-51
  frames in the air each at 30-50 km/h. Not crests a car would really leave the road over
  (13% of grade change over 30 m needs 0.5 m/s2 at 40 km/h, gravity is 9.8): the profile is
  points 6 m apart rounded to 10 cm, a kink at every point, and `_fly` took the ground as it
  came, so a kink was a jump of the ground's speed in one frame, over `LIFTOFF`. Now the
  springs feel the ground along the car's way smoothed over half a wheelbase of travel
  (`ride` in `_fly`) and `infer` keeps its heights unrounded; also `_round_joints` puts a
  32 m vertical curve across a joint where two lifted pieces meet in a crest and eases a
  cutting's top into the street. Result (`tests/decks.gd`, levels 1, 3, 4, 7 bridges and
  tunnels): every run 0 frames in the air but Arvei Nahal's 9 and one frame in a Tel Aviv
  tunnel. Measuring under the axles instead was tried first and is wrong: an axle's point
  by a tunnel's wall found the ground over the tunnel (37 frames in the air in Givatayim's
  City tunnel, which had none). `TRACE=1` prints the frames before each take-off;
  `tests/deck_profile.gd` prints the profile of the decks round a spot, with and without
  `_round_joints`.
- **Open: Arvei Nahal's seam** (Tel Aviv, (578, -691)): where Al Parashat Drachim's ramp
  leaves the wide deck at the knot, the two overlap for a metre or two at heights 0.44 m
  apart (the ramp falls at 7% from the shared point, the deck is flat), and the car stays on
  the higher till it ends, then drops: 9 frames in the air at 43 km/h. Wants a ramp leaving
  a deck held at the deck's height until it is clear of its asphalt.
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
- **Givatayim** (with the strip of Ramat Gan and Tel Aviv round it): 11 bridges (Menachem
  Begin's and Arvey Nahal's over the Ayalon), all 23 crossings over roads at full clearance;
  7 tunnels (Uzi Hitman's, the City tunnel's pieces, HaMaayan's), 16 cuttings, 0.3 s. Left
  out, too short for their cuttings: the Rabin Underpass, a piece of the City tunnel, a
  service tunnel. `tests/decks.gd` level 1: the tunnels and bridges driven alone come out
  clean; in the full sequence two runs stall (traffic left by the run before), and two
  cuttings give a short hop.
- **Ashdod's interchanges** (Highway 4 under the motorway at x 3850, z -1590; the
  motorway's at x 4830, z -4150) had 15 crossings short of the clearance, down to 0.5 m:
  each link bridge lands on its own continuation, a cloverleaf loop that turns and passes
  back under the bridge. The road crossed was held to the ground within 80 m of the
  crossing as the crow flies, so the loop's start -- metres from the crossing, hundreds of
  metres along the loop -- was held down, and the bridge's end with it. Held within 80 m
  ALONG the road crossed now: Ashdod 0 short, 0 capped (22 before), every crossing over a
  road at 6.4 m; Bedford and Givatayim the same as before; Tel Aviv's 3 short crossings (at
  Givat HaTahmoshet) the same, capped 49 -> 40. `ROUTES=... tests/decks.gd` drives each link
  bridge and Highway 4 under them: all clean. Ashdod's ten highest, both ways: all clean
  once merged with the springs' smoothing (another session's: Begin's and Laskov Road's
  small hops went with it). `street_holes` on Ashdod: 0 holes, 2 points in a wall (both
  on Laskov Road; 51 before).
- **Tel Aviv's Givat HaTahmoshet** (its bridges and a slip road over Ayalon South) came out 3
  crossings short (4.8 m the lowest) once footbridges went in: a footbridge crossing a
  street held it to the ground for 80 m, as a road bridge does, and there the street is
  the ramp up to a bridge, so the bridge's lift was capped. Footbridges hold nothing down
  now and are raised over the street instead: Tel Aviv 0 short, capped 40 -> 0, one more
  tunnel dug (27), one footbridge raised (to 8.5 m, over a street's ramp); the other three
  towns the same. Driven both ways and on the slip road: 0 hits, 0 frames in the air;
  `street_holes` the same 6 points as before (that ramp's, 0.7-0.9 m) and 6 wall points;
  its 8 highest footbridges walked, 96-100%.
- **Still to do**: grass slopes for cuttings too (they are walled); a
  long-span bridge's height over water (the MacKay's deck is only as high as its ends);
  pavements at street level beside a cutting (the underpass has none); people on a bridge's
  pavement and beside a cutting; the
  minimap draws a tunnel like any street; zooming out from inside the tunnel rises from the
  hilltop (the zoom centres on the ground's height); the heights are whole decimetres, so a
  deck's grade kinks by up to 2% every 5 m (enough for a 2 cm hop off HaNasi's bridge);
  autodrive turning right off the flyover's foot onto HaRakefet clipped a crossing railing's
  post on the corner about one run in two (21 Nov: `decks.gd` at level 1 twice, no such hit;
  its runs no longer take that turn, so not seen either way) (the railing reaches 6 m from the zebra, into the
  corner: a corner-furniture question, not a deck one). Ramps' and cuttings' walls are left
  out of the collisions within a junction's corner (`_walls_of`): there they are a step a
  turning car sweeps over.
- **Handoff -- footbridges, footpath tunnels, the interchanges' clearance (`infer`), 20 Nov
  2026.** Nothing is half done: footbridges and footpath tunnels are in for Givatayim,
  Bedford and Ashdod (and Tel Aviv, which runs the same `infer`: 46 footbridges, 2 foot
  tunnels there, not walked by this session); Ashdod's interchanges are at full clearance.
  How to check it all, and what good looks like:
  - The inference's own report: the `decks_inferred` event in a playtest
    (`tools/playtest.sh streets smart 25`, or `LEVEL=n`) -- `short_of_clear` 0 for
    Givatayim, Bedford, Ashdod and Tel Aviv, `capped` 0 / 2 / 0 / 0,
    `stair_capped` 8 / 1 / 0, footbridges 22 / 24 / 6, foot tunnels 3 / 0 / 2, the whole
    pass 0.3-0.8 s.
  - `tests/foot_decks.gd` (levels 1, 2, 3; headless with `STREETS_BUILD_ALL=0 SHOTS=0
    $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/foot_decks.gd`,
    3-5 min a town, Tel Aviv (level 7) 8): every route "got" 97-100% at its clearance;
    Bedford's Duke Street sidewalk-bridge says 91% and Tel Aviv's raised one 96% (the test's
    run-out past the path's end meets an abutment, a fence: fine).
  - `tests/decks.gd` with `ROUTES` on level 3 for the interchanges (the seven runs are in
    the README row), and plain on levels 4, 2, 3: 0 hits, 0 frames off the level; in the
    air only the test town's 8-9 frames off its two bridge ends.
  - `tests/street_holes.gd` level 3: 0 holes, 2 wall points.
  Open, smallest first: a footbridge whose OSM way ends at a building (a skybridge into a
  mall) now comes down by a stair at its end instead of meeting the wall; fences don't
  open for footpaths (`_open_pieces` asks `_off_road`, drivable roads only), so an OSM
  fence across a path on the ground still blocks a walker; walking up 60% stairs the walker's
  height trails by up to 1 m for a moment (`_walk`'s easing); a sidewalk mapped as its own
  path bridge beside a road bridge (Givat HaTahmoshet's) gets its own height, 0.6 m under
  the road's deck beside it, rather than the road's; `ROUTES ... ,top` in tests/decks.gd can
  still land on a road under the deck where they cross (use `deck_air`, which starts on the
  highest surface, to drive a particular deck).

## Sizes against life (`tests/scale_check.gd`, 20 Nov 2026)

The user's sister said the scale felt off; the check measures what the game builds. Vehicles
are 1:1: a parked sedan 4.62 x 1.8 (2.09 with its mirrors) x 1.46 m, the bus 11.85 x 2.5
(2.8 with mirrors) x 3.33 m, the player's car 4.4 x 1.9 x 1.55 (its body; 4.75 x 2.39 x 1.78
with lamps and mirrors); storeys 3.0 m, kerbs 0.14, pavements 2.4. Off:

- **People were tall**: asked 1.62-1.88 m (1.75 on average) against life's ~1.70, the player
  on foot (a woman's figure) 1.76 against ~1.63. Now `ADULT_LO`-`ADULT_HI`, 1.55-1.85, and
  1.66 for the player. (A first reading said they were drawn 6% over what they ask: that
  was the model's box, which is taken before `_humanize` scales the bones -- the head
  smaller, the legs longer, then the whole 1.06 up to give the asked height back.)
- **The fields of view were wide**: on foot 66 deg up and down (98 across a 16:9 screen),
  from the eyes 70 (102), driving 64-74 (96-106), the seat 72-78 (up to 113): the near
  loomed and the rest looked small and far -- the likeliest "scale feels off". Now on foot
  56, from the eyes 58, driving 54-62, the seat 58-64 (the user agreed); the filmed walks
  keep 70, an upright phone's frame, as they are set beside its film.
- Lanes by OSM's widths: tertiary 3.8 m a lane, a one-way residential street 8 m kerb to
  kerb with its cars parked mostly up on the pavement, so its asphalt reads as one wide lane
  (life: ~3 m of lane between two rows of cars parked in the road).

## Railways (`rails.gd`)

The baker keeps railways since November 2026 (`rails`: each track its own line, as OSM maps
it; `platforms`; `stations`): only Tel Aviv has been baked with them so far -- the other
towns get them when re-baked. What the game does with them:

- **Setup** (`Rails.setup`, before the trees): tracks in a tunnel and metro lines are left
  out (Tel Aviv's Red Line is underground: its 6 tracks and 5 stations); each track is a
  line every 6 m, its ballast bed's foot pulled in where a road's asphalt runs close (along
  the Ayalon it came up through the road's edge at 47 points), and its outline added to
  `_no_grow` (open land's wild trees stood on the tracks). Platforms near a track only
  (OSM's outlines, or a line along a track's edge made a 4 m slab away from it); stations
  within 60 m of a track. `on_track` keeps a bridge's piers off the tracks (`decks.piers`).
- **Lines for trains**: tracks joined end to end where they share an end point exactly
  (the baker writes both from the same OSM node), the straightest way on at each join (no
  sharper than 60 degrees: a crossover's leg is not "on"), sidings and yards left out; up
  to 4 lines of 600 m or more, not one alongside another already taken. Tel Aviv: 3 lines
  of ~3.1 km down the Ayalon.
- **Drawing a square** (`build`, after the decks): the bed (a flat top 3.4 m wide, 0.35 m
  up, slopes to the ground), two rails, concrete sleepers every 0.65 m (a multimesh per
  square), and the platforms: a slab at the coaches' floor, a grey canopy on posts over its
  middle half, the station's name (Hebrew and English) under it.
- **Trains** (`tick`, in `_physics_process`): five double-deck coaches at 22 m/s, one
  train a line, each direction in turn with 40-90 s between; seen, not solid (the Ayalon's
  line runs where no car goes; a level crossing would need them solid). `s` is coach 0's
  middle and coach 0 always leads (positions are worked out from the head along the way it
  runs), so its +Z end has the cab face, windscreen and white lamps and the last coach's
  -Z end the red ones -- nothing swaps when it reverses. Stops (`_stops_of`): where a
  platform's middle is within 12 m of the line, one per 120 m; the train brakes at 0.7
  m/s^2 to stand with its middle at the platform's (measured: 0.3 m off), stands DWELL 30
  s, pulls away at 0.6 m/s^2. At night (`set_night`, from `_set_night`) the shared window
  material glows. The minimap draws the tracks light on dark (`map_lines`).
- **The overhead line** (`_wires`): masts every 50 m on each outer side of the tracks (no
  other track within 4.5 m that side), each with an arm reaching over its track and any
  others within 12 m -- from both sides they meet as a portal over three tracks; a contact
  wire 5.6 m over the rails and a messenger 1.1 m above, the contact wire lowered under a
  bridge's slab (0.4 m clear) and the messenger left out there. No mast on a road or under
  a bridge. Every main-line track is wired (the Ayalon line is; the baker does not keep
  OSM's `electrified=` yet). The arms are one unit box scaled along its own axis
  (`Basis * Basis.from_scale`): `Basis.scaled()` stretches along the world's axes, and the
  arms came out skewed along the track.
- **Sound** (`sound`, from `_engine_tick`, which runs paused too): a 3D rumble on each
  train's middle coach (`sounds/train.wav`, a 4 s loop: the roar, the bogies' thumps coach
  by coach, a faint motor whine), louder with its speed, and the horn (`train_horn.wav`)
  once as it pulls out of a station; silent when muted, paused or the run is over. Both
  made by `sounds/make_sounds.py train train_horn` (only those: the others stay as they are).
- **The test**: `tests/rails.gd` (level 7) prints what was set up and how close the beds
  come to roads (0 over asphalt), stands a train at HaShalom and shoots it from beside the
  line and from the platform, both stations from above, and a track close up. Two things
  it took: the ballast first came out as pale as the bare ground of the median, so from
  beside the line the bed was not there (darker now); and a test that holds the world still
  (`set_physics_process(false)`) must set `_prev_yaw` with `_yaw`, or the view blends from
  the car's old heading and looks the wrong way.
- **Still to do**: level crossings (trains solid, barriers); the light rail where it runs
  on the surface; keeping `electrified=` in the bake; re-baking Ashdod (it has a line) and
  Bedford. Givatayim was re-baked (20 Nov, evening): the Ayalon line's 13 tracks run along
  its west edge with no station in the box (3 lines, 3 km, 0 bed points over asphalt in
  `tests/rails.gd` at level 1), and the Red Line's tracks and its Arlozoroff and Abba Hillel
  stations are underground (light rail, tunnels).

## Landmarks (`landmarks.gd`)

What a town is known by and OSM draws as one more box. `BY_CITY[city]["landmarks"]`: each
a building's name in the bake and what it gets; the tallest building whose middle is inside
the named outline is the one dressed (OSM put the Marganit tower's name on its 18 m podium
and mapped the 80 m tower as an unnamed part inside it). `setup` (after `_rails.setup`)
marks the building -- `_glass` (a glass tone of its own, and COLOR.a 1, the wall shader's
sign for a landmark's curtain wall: darker, glossier glass in thin dark mullions, not panes
in white frames) or `_tile` -- before the squares are built; `build()` per square (after
the rails) adds a crown (a metal band round the top, lit at night through `set_night`), a
concrete shaft with antenna platforms, a mast (red and white bands if striped) with red
lights, and on every roof 90 m or more over its ground red aircraft lights at its corners
(a MultiMesh of quads sized ~1.1% of the distance in the shader, so they stay ~6 px far
off; pulsing; in `_night_nodes`). `"tiles"`: rectangles whose small houses (80-450 m2,
under 13.5 m) get `_gable`'s roof in a red clay tone over walls of 5.5-7.5 m, style 0
(shuttered windows), never on columns. Tel Aviv: Azrieli's three towers (glass 1, crowns),
the Matcal tower (mast to 107 m) and Marganit (shaft to 118 m, striped mast to 138 m,
Wikipedia's figures, modelled without photos), Sarona (39 houses); 92 roofs lit, 355
lights. `found` keeps what was matched, for the test: the city file is let go of once
built. Test: `tests/landmarks.gd`. Since the box grew to the sea: the Shalom Meir tower
(130 m, a mast to 142 m) and the Opera tower (OSM draws its 21 stepped floors in their
stone, #f2e1d6, up to 82 m: found, nothing added), 136 roofs lit. A shaft's and a mast's
`to` is over the ground at the building's foot (the figures are towers' heights): it was
taken as the world's y (over the height grid's base) and Shalom Meir's mast, on ground
15 m up, ended under its own roof; the Kirya's were short by their ground too.

`"market"`: [street name, kind] pieces with stalls down both sides (`_market_line`, set up
with the landmarks): a place every `STALL_STEP` 2.7 m each side, one in `STALL_GAP` 7 left
open, 1.6-2.6 m out from the middle (the walkway between); built per square into a CBuf of
coloured boxes (`_stall`: a counter with four crates of produce tipped toward the walkway,
a rack of goods behind, four poles, a canvas sloping down to the walkway), skipped where
`_push_out` finds a building or a post, two posts each. Colours are `_real_col`'s paint
names (produce: red, orange, green, yellow, maroon; canvas: blue, white, red, green,
orange, cream): the palette's roles, the first try, made a market of pinks and purples.
Tel Aviv: HaCarmel's pedestrian piece, 267 places, 228 stalls. Test: `tests/seaside.gd`.

## The beach (`beach.gd`)

Any town with a coast. The sea: a water area held at its level (`y`, the baker's) whose
outline runs along the map's edge for 50 m+; a beach: an area of kind `sand` (OSM's
`natural=beach|sand`) with the sea's shore within `BAND.y` + 20 m of it. `setup` lays a
6.5 m grid over each beach (jittered), and by the distance to the shore puts an umbrella on
55% of the places 16-52 m up from the water (the wet sand kept clear) and a lifeguard's
tower at ~14 m, one every 230 m; each in its square. `build()` per square (after the
landmarks) drops what is on a road or a path (`_off_road` 2 m) or into a kiosk or a post
(`_push_out` 1.6 m), then: umbrellas (pole and cone, `_chunked`, colours `_real_col`'s),
each with two white chairs (seat, back, legs as one block; now and then one or none)
facing the sea, a little askew, whose seats go into `g._beach_spots`; towers as boxes
(`_tower`: legs, floor, white hut with a blue band and dark window, blue roof, balcony,
ramp behind, red flag). The sand is the tone "beach" (`_build_ground` maps kind sand to
it): warmer and darker than a sandpit's "sand", which over a beach read as snow.
Bathers: streets.gd's `_bathers`, `BATHERS` 10 people made the first time there are chairs,
placed by `_place_still(..., "sit")` like the bench sitters (only where you cannot see them
appear: a scene test turns the eye away a moment first, `tests/seaside.gd`'s `settle`).
Tel Aviv: 9 beaches, ~1085 umbrellas, ~1713 chairs, 10 towers. Test: `tests/seaside.gd`.

## Crowds: the market's shoppers, the beach's walkers and waders (`crowds.gd`, 21 Nov 2026)

The street walkers (`_walkers`) keep to kerbed roads' pavements, so the Carmel market (a
pedestrian street) and the sand stood empty. `crowds.gd` walks people along lines handed in
at setup: `landmarks.gd`'s `_market_line` adds each market piece (`hw` = the stalls' `off` -
1.0: the walkway between the counters and their posts) with a stop per stall place ([s, side,
where to stand 1 m in front of its middle, facing, the stall's middle]); `beach.gd`'s
`_people_lines` chains each beach's shore segments, steps them every 3 m and keeps the line
`SHORE_OFF` (3.5-9 m) up from the water where it lies on that sand (the line's middle, `hw`
2.75), and every third step now and then a spot 3-16 m out in the sea for a wader, facing the
beach or out, its feet at the sea's surface minus 0.25-0.85 m (`_place_still(..., "wade")`).
Pools: `MARKET_PEOPLE` 28, `SHORE_PEOPLE` 12 (a quarter jog at 2.4-3.1 m/s), `WADERS` 9,
made 2 a frame the first time a line is within `PEOPLE_RANGE` (a town with none makes nobody),
hidden with their animation off when not placed. Placing: a few tries a frame for one
person, a point within `PEOPLE_SEEN` + 8 that `_spawn_ok` allows (behind you, past the drawn
range, behind a block); market shoppers within 50 m of your place along the line. Walking:
slower behind someone close ahead, the place across the way drifting every 3-9 s, `_people_apart`,
`_push_out` (the stalls' posts), never into you on foot; at a line's end out of sight they go,
in sight they turn back. A shopper passing a stall on their side stops at it one time in three
for 2-7 s, facing it (Idle). Headless no stalls are built (`landmarks.gd`'s `build` returns), so
there every stop counts as a stall.

- **Good numbers** (`tests/seaside_people.gd`, level 7, headless `--fixed-fps 10`, ~40 s of
  wall time after loading): market 10-15 shoppers within 40 m and 26-28 within 90 m, 1-8 at a
  stall at any moment, ~60 stops in 70 s; beach 12-15 within 90 m (walkers, 1-3 joggers, 3
  waders); 0 in a post, 0 shore walkers in the sea, 0 appearing in view. 1 market line (435 m),
  20 shore lines (897 m), 38 wade spots.
- **Gotcha** (cost a run here though the scene-tests skill has it): a test that types
  `var a: Actor3D` breaks every `Actor3D.new()` in the game, and nobody walks. Use `Node3D`.
- **Open**: beachgoers are dressed like the street's people (no swimwear in the kit's
  characters); nobody swims (they stand); the market's crowd thins 50 m+ from you (the pool
  is placed round you); a shopper does not pick anything up (the kit's PickUp clip is a
  crouch to the floor).

## The town's own layers: lamp posts, building sites, businesses (21 Nov 2026)

`tools/osm_city.py`'s `town_layers_apply` (run by a bake with surveys and by `--add-surveys`;
`TOWN_LAYERS`, `LAMP_LOOKS`, `SITE_STAGES`, `BUSINESS_KINDS` there) lays three of Tel Aviv's
layers from `cities/data/` over a city file, shifted by the trees' offset (-0.4, -1.9 m):
`lamps` + `lamp_info` + `lamp_looks`, `sites`, and extra `pois` rows with a 6th field (the
layer's id). Re-run after a change: `python3 tools/osm_city.py --add-surveys
game/streets/cities/tel_aviv.json --offline` (and givatayim.json: its box has Tel Aviv's west
strip), seconds each; only those keys change (checked: buildings and trees byte-identical).
Tel Aviv: 15,264 lamp posts, 511 sites at work (of 790: a file only opened or a building
finished left out), 2,299 businesses added (5,895 street-level shops, cafes and the like in
the box; 1,440 within 8 m of an OSM place, 2,156 at one door with another); the file 2.8 ->
3.5 MB. Givatayim: 2,641 lamps, 97 sites, 136 businesses.

- **Lamp posts** (`_mapped_lamp`, from `_build_lamps`): onto the pavement 0.55 m past the
  kerb when the map's point is on the asphalt, out of a wall, the arm over the nearest road;
  looks "pole" (the usual grey pole), "wood" (trunk-toned), "ornate" (the ornate kit, no flag),
  "wall" (a bracket and head at 4.5 m, no post); 2+ lamps: a second arm the other way. The
  made-up rows are left out within a 3x3 of `LAMP_COVER` 45 m cells of any mapped lamp
  (`_lamps_mapped_at`). 14,947 of 15,264 stand; dropped where nothing off the asphalt is near.
- **Building sites** (`sites.gd`): a hoarding panel every 3 m of the plot's outline (white,
  blue, green mesh or dark grey, a darker band along the top, a post at each end), left out
  where it would cross a road or a standing building's wall; a crane over each new building
  that is tall ("גבוה" / "מעל" in its work) or 700 m2+: a lattice mast 34-72 m, the cab, a
  38-50 m jib with trolley and hook, the counter-jib's weights, the A-frame and ties, yellow
  or white; about 100 boxes, seen to `CRANE_RANGE` 1500 m. Tel Aviv: 9,216 panels, 120 cranes.
  A panel is kept only when every 0.5 m of it is off the road (0.3 m margin): checked at its
  middle alone, ten panels stood 0.6-1 m into Stein, Shmerling and Yavneel (city_check 7,
  "walls on the road" 10 -> 0, 21 Nov 2026).
- **Businesses**: places like OSM's, so `_build_pois` makes their fronts (window, awning,
  crates or A-board, a shopkeeper, a terrace for food) and their sign shows the Hebrew word
  for the kind (מכולת, מספרה, פירות וירקות...): the data has no names (a sole trader's would be
  their own). Workshops, offices and anything not on the street floor are left out.
- **The car mix** (`CAR_MIX`, `_car_paints`): from the vehicle register's sample
  (`data_tools/car_mix.py`: each make's top models by shape): SUVs 42%, saloons 22,
  hatchbacks 21, city cars 11, vans 3, a people carrier 1; paints white 44, silver 17, grey 17,
  black 13, blue 5, beige and red 2 each (the first 14 paints kept in their places for the
  filmed walk's cars). Credited on screen ("car mix © Israel Ministry of Transport", `_credit_line`
  groups the towns' credits and lists others after).
- **Test**: `tests/town_layers.gd` (headless counts, REGRESS line; drawn: Rothschild's lamps,
  a crane, a hoarding, the street with most added shops). Good: level 7 lamps 15,264 mapped,
  ~14,950 standing, 0 on the asphalt; 511 sites, ~9,200 panels, ~120 cranes; 2,299 businesses,
  ~4,160 places built.
- **Open**: lamps at night are the same pools as before (the town's lamp count per post is
  not used for light); the 1,089 wall lamps hang at the point the map gives, which can be a
  metre off the wall; a "frame" stage site does not show a building's bare shell; Ashdod's and
  Givatayim's own lamps are not fetched; the hydrants (2,102) and the other layers in
  `places_tel_aviv.geojson` (bike-share stations, taxi stands, motorbike parking, sculptures,
  notice boards) are not used yet; the businesses' signs are all the kind's word, so a street
  of them reads as a list of trades.

## Tel Aviv (level 7): handoff, 20 November 2026

The session that added Tel Aviv, its bridges and tunnels' fixes, the railway, the landmarks
and the ramp-top fix. Where things stand:

- **Begin x Kaplan's traffic: fixed down to a few a run** (20 Nov 2026). The exam's watch
  mode stages it: `LEVEL=7 EXAM_AT=-30,160 EXAM_STAND=70 EXAM_SECS=150 STREETS_BUILD_ALL=1
  $GODOT --headless --fixed-fps 60 --path . -s res://game/streets/tests/exam.gd` (~5 min;
  also `EXAM_AT=-45,165`, the eastbound queue). Checks in 150 s: 10 and 8 at first; now 0 at
  (-30, 160) and 1 at (-45, 165) (a "held by nothing" where Begin's slip meets a delivery
  truck's queue). The exam at level 7, 3 x 60 s: 8 then 4; level 1: 4 and 4. What was wrong and what fixed it, all in traffic.gd (see "lanes" in
  the code map):
  1. Cars from Kaplan's four lanes into Begin's two-lane southbound slip kept their lane by
     *number* across the road change, so the link's lane 1 became the slip's lane 1 on the
     other side, and the cars crossed and stood on each other: now the nearest lane by
     where the car physically is. The realigning shift was followed at a lane change's
     1.4 m/s, so a car ran off the slip's edge into its poles: now `REALIGN` x speed.
     Before the narrowing (`NARROW_LOOK`) a car moves into a lane the narrower road has.
  2. Kaplan's eastbound queue stood at 45-156 degrees: a turn's curve (`_turn_into`) began
     back from the junction's first point, out on the approach, so the waiting cars stood
     half turned -- now from no further out than the stop line, for ways in from outside
     the junction only (from inside, it moved inner points' curves and cars ran reds).
  3. A car shifting while it stood moved its front alone and swung its body across the
     next lane: sideways only as it rolls (`SIDE_PER_V` x speed, slower for a long one).
  4. One changing lanes is in the way in both (`_target`: its body's width and angle, not
     its middle, against the follower's line) -- a bus stopped by the light halfway over.
  The exam names a delivery van stopped in the street ("held by delivery"), no longer
  "held by nothing". Left: a car cutting in front of a truck where Kaplan becomes Givat
  HaTahmoshet (-8, 148), its shift a road change's (not gated by `_lane_clear`).
- **Bus lanes: done, from OSM** (`bus:lanes`, `lanes:psv`, `busway`; the bake's `bf`/`bb`;
  see "bus lanes" in the code map and `tests/bus_lanes.gd`). data.gov.il's `nataz_kayam`
  (the Ministry's layer, more stretches) came back as a CloudFront 403 from this container
  -- not to be got round; a copy added to the repo by hand would be the way.
- **Grown to the sea** (20 Nov 2026, the user: "lets try to make it bigger"). The bake's
  bbox `32.0590,34.7595,32.0858,34.8021` (was `32.0639,34.7795,...`), margin 150,
  bare_ground and main_server_only on, and `origin` `32.07485,34.7908` -- the old box's
  centre, so every place in the old box kept its metres (the landmarks, the tests'
  coordinates, the hand fixes; checked: the landmarks found at the same points, the city
  check's old findings at the same points). Bounds now x -3105..1217, z -1364..1907
  (4.3 x 3.3 km); 9597 buildings (4011), 5963 roads (3745), 553 lit points (316), 10
  beaches, the sea 1.6 km^2; the file 2.8 MB (1.4): Ashdod's size. Load before the car,
  measured beside another run: parse 2.6 s, build 3.3 s. Level renamed "Tel Aviv: Azrieli
  to the sea". New in the baker for it: `--origin`, beaches (`natural=beach|sand` ->
  areas of kind `sand`, drawn with the playgrounds' sand), and the sea held at sea level
  (`_hold_sea`: the tiles read the sea at -0.1..+1.2 m and the beach 2.5 m under, and
  water lies at its shore's lowest point -- the sea lay under its own floor and the ground
  was drawn white over it). Checks after: `city_check` 19 (12: 18 buildings into a road,
  1 post 0.3 m into Dizengoff at (-1495, -1306)); `landmarks` 5, 39 tiled, 136 roofs lit
  (with the town's survey: 8322 of the 9597 buildings take its measured height; baked
  after merging that session's baker, so the file has both, and its roads levelled);
  the exam 3 x 60 s 4 checks (the old map 4; one start by the sea at (-2607, 1562)): new
  places, traffic into post 31487 at (-880, 1155) twice at 40 km/h and a bus into one at
  a stop at (-1065, 853); `decks.gd` -- a run now drives Al Parashat Drachim's embankment
  by the Uzi Hitman tunnel and leaves the ground 11 frames at (580, -690), 40-46 km/h
  (its profile is the old file's to 0.1%: a crest, dg -6.7% at 43 m along the piece from
  (583, -684); the old run stuck 11 m in and never drove it). Look with
  `tests/street_views.gd` (`STREETS="אלנבי;הכרמל;רוטשילד;הרברט סמואל"`,
  `LOOK="-2468,0;-2660,616"` for the beaches).
- **Then, asked for (1, 2, 3)**: the Carmel market's stalls, the beach (warm sand,
  umbrellas, chairs, lifeguard towers, bathers) and the Shalom Meir and Opera towers -- see
  "The beach" and "Landmarks" above. Still open: Ashdod's sea is likely under its floor too
  (its water at the shore's 0.8, its sea grid 1.1: re-bake it with this baker, and it gets
  beaches). People on the shore and in the water, and the market's shoppers: done since
  (see "Crowds").
- **Open, smaller**: Arvei Nahal's 0.44 m seam (under "Off the ground"); the HaShalom west
  ramp's 8 hole points; 5 bank feet at a kerb; Marganit and Matcal's tops are modelled from
  heights alone.
- **The checks and their numbers now** (all at level 7 unless said): `tests/decks.gd` (with
  and without `DECK_KINDS=br`, `TRACE=1` to see a take-off) -- 0 frames in the air but
  Arvei Nahal 9 and one tunnel 1; levels 1, 3, 4 all 0. `tests/street_holes.gd` -- 8 holes,
  5 walls. `tests/landmarks.gd` -- 5 landmarks, 39 tiled, 92 roofs lit. `tests/rails.gd` --
  stops at 1379 and 2758 m, stands 0.3 m off. `tests/light_audit.gd` and `exam.gd` as in
  "Open problems" below. `tests/deck_profile.gd` (`CITY=... AT=x,z`) for a profile in
  seconds without the game.

## Handoff: lights, kerbs and paving, islands, quality, menus, performance, signs, level roads (20 Nov 2026)

One session's areas, left for whoever picks them up (its context was compacted after this).
Each line: where the code is, the test, what good reads.

- **Traffic lights**: sites, groups, `flip`, walk lights (`_lights_setup`, `_site_axes`,
  `_light_group`, `_walk_light`, `_through_lights`; traffic.gd `_light_ahead`). `light_audit`
  levels 1, 3, 7 -- crossing pairs green together / a road changing group in a junction /
  walk lights green with cars coming: 0 / 0-1 / 0 (README has the full row).
- **Autodrive and the map's edge** (`_edge_bound`, `_ap_ways` scoring): `autodrive_edge` 1, 3.
- **Paving laid once** (`_laid`, `_laid_cut`, `_laid_by`, `_flat_piece` in `_kerb_piece`):
  `pave_overlap` 7 -- 5,355 m2 overlapping, of it two different pavings ~30 m2 (good); the
  rest a strip's next piece at a bend, the same paving.
- **A rounded corner's asphalt is road** (`_corners_at`, `_note_corner_fills` at the start of
  each square, `_in_corner_fill` inside `_off_road`, signs moved out by `_out_of_corner`):
  `road_blocks` 1, `city_check` (validate.sh). Givatayim's 2 posts left on the road are a
  plain post on Aluf David and a tree on Katznelson by Sirkin (on main before this; the
  filmed walk's details).
- **Traffic islands** (`_find_islands`, `_island_cut`, `_island_faces`, `_on_island`):
  `islands` 1, 3 -- 0 points of any island on a road. **Bare ground** is dusty sand (`_tones`).
- **Bridges at junctions** (decks.gd `_clear_ends`, `_on_street_below`, `_street_at` -- reads
  `_seg_hash`, because the walls are made in `setup()` before `_asph_hash` exists):
  `deck_corner` 2 -- Bedford's Union Street turn: 0 wall hits on 4 routes (were 12).
- **Quality ladder** keeps the sun's shadows at every level (`QUALITY`): switching them off
  recompiled every shader in the browser, a 3 s freeze each step.
- **The minimap's route** (`_draw_map_inner`: wide, the destination's colour, a dark edge):
  `minimap_route` 1. **Go to** (`_open_picker`, `_show_pick_mode`: "jump to" first, "drive
  to"): `picker` 4. **The start screen's two groups** (`"group"` in `LEVELS`; the shell's
  `_level_groups`): `tools/menu_shot.sh levels:streets`.
- **Performance** (`tests/perf_dive.gd` 7; numbers under "Numbers to compare against"):
  parked cars done (`_draw_parked`, `_parked_far_mesh`, `PARKED_CELL/NEAR/SEEN`; `_chunked`
  takes `cell_m` and `range_begin`); heavy kits kept as multimeshes (`BATCH_KIT_VERTS`, -131
  MB in Tel Aviv). **The merged meshes indexed** (`_index_into`, `INDEX_PIECE`): Tel Aviv's
  9.8 M merged vertices are 5.4 M different ones (`index_gain` 7: 187 -> 121 MB); done in
  pieces of 30,000 vertices (the slowest 6.4 ms here; whole, the biggest square's 170 k took
  30 ms -- no threads in the web build), each piece a surface: all indexed, the start view
  went 669 -> 692 draws and video memory 445 -> 365 MB. Only the squares built while
  driving (`_bg_build`) are indexed: the start's are behind the loading text, where it
  would add to the wait (+1-2 s here) and its draws would be in the first view. So
  `STREETS_BUILD_ALL=1` (the tests' default) indexes nothing: measure it with
  `STREETS_BUILD_ALL=0 tests/run.sh perf_dive 7` (it waits for the rest to be built).
- **The warm-up's steps by shader code** (`_shader_key`, `_code_key`): a browser compiles a
  shader per CODE (a ShaderMaterial's Shader; a standard material's set of switches -- Godot
  shares one shader between all materials with the same flags, colours are uniforms), not
  per material. `warm_census` 7: 77 materials were 25 codes, 43 programs (codes x plain /
  instanced x the shadow pass); grouped by material, one step of eight had all 38 people's
  materials (one shader) and another a dozen shaders. Now 35 kinds, 42 programs (the fences'
  two colours had a Shader each: one now). Merging look-alike standard materials saves
  nothing -- they already share. What is left is real: to shorten the warm-up, fewer shader
  codes (the dog's own shader, one ROOF-like code for one node...) or fewer shadow casters.
  `_get_shader_rid()` called from a script hangs Godot (don't); the census reads the
  switches instead.
- **Stop and give-way signs everywhere** (`_infer_signs`, in `_build_setup` after the
  lights): a way in of a smaller class into a junction without lights, OSM's own sign not
  within `SIGN_MAPPED`: a stop before secondary-and-up in the Israeli towns, else a give-way
  (slip roads, Bedford). Left alone: same class meeting (the user was asked; the suggestion
  was to leave them, no answer), roundabouts, service roads, a street going on under another
  class, the gap through a divided road's median (`_points_back` + `_other_half`). Each way
  in is its own sign entry with its facing, through the same `_build_signs` as OSM's -- which
  kept only the LAST sign at a node (a second overwrote the first's rules: fixed). The pole
  tries 8 spots (further back, further out): at the first alone only 44 of 167 stood.
  Give-ways get a dashed line (and האט in "med"). `signs_inferred` 1: 23 stop + 87 give way
  added to OSM's 33, 140 junctions, 151 of 167 poles. Traffic stops / slows for them as for
  OSM's: watch the exam's numbers.
- **Roads level side to side** (`tools/level_roads.py`, called by both bakers; the five city
  files levelled in place): the height grid (8-46 m a point) tilted a road with the
  hillside -- Givatayim 28% of its length over 6% across. Grid points near a road take its
  centre line's height (fully to a cell's diagonal past the pavement, blending back over one
  more cell; the nearest asphalt edge wins). Over 3/6/10% across, before -> after: test town
  24.7/14.9/8.1 -> 2.4/0.6/0.2%, Givatayim 56.6/27.7/10.0 -> 16.5/6.0/1.8, Tel Aviv
  24.9/5.4/0.2 -> 8.4/1.9/0.3, Bedford 52.8/26.4/9.3 -> 24.2/8.8/2.6, Ashdod 22.8/4.2/0.3 ->
  11.6/1.9/0.2. What is left is where two roads at different levels share a cell (the
  Ayalon interchange's slip roads, a service lane below a street) -- a finer grid's job.
  `python3 tools/level_roads.py --check city.json` measures without writing (the same
  triangles as `_h`); `road_tilt` 4 measures in the game. Checked against the unlevelled
  files (a worktree with main's cities, the same code): `decks` 4, 2 clean; 1, 3 the same
  pre-existing marks (Givatayim's City tunnel run starts against walls, Ashdod's Laskov
  Road 1.2 m and Sderot Menachem Begin 0.44 m off the level -- unlevelled too); a Givatayim
  bridge run now drives a different stretch (its inferred bridge moved a few metres) and
  goes 0.31 m off on Menachem Begin by the Ayalon, where the ground under the car was 0.34
  m off before and 0.16 m after (`OFFS=1` prints where). A re-bake of a levelled city
  merged against another session's re-bake: take theirs and run the tool on it again.
- **The first load after a publish is the slow one** (user, Tel Aviv: "getting the graphics
  ready (6 of 12)" took a while): a browser keeps compiled shaders between visits only for
  the same code, and nine commits that day changed shader code -- every first load after
  such a build compiles them all again. The step that stands out is the one the warm-up
  gave the most shaders: grouped by code now, the eight steps share them.
- **Railings across Kaplan** (user: "weird borders in the middle of Kaplan", Tel Aviv's
  start, autodrive): the Lova Eliav tunnel runs under Kaplan in four OSM pieces, and the one
  actually under the eastbound half is 19 m -- under `MIN_TUNNEL` (20), so `Decks.infer` put
  it back on the ground; sandwiched between two tunnel pieces it was dug as a cutting at
  full depth, and a cutting's railing (posts every 2.4 m, rails at 0.55 and 1.0 m) stood
  across both lanes, 1 m high, not solid (the car's walls already skipped it). Not the
  indexing (`STREETS_NO_INDEX=1` showed the same) nor the background build. Fixed at both
  ends: a short tunnel way under something that joins a tunnel at an end is a piece of it
  (`short_tu`, grown like the branches), and `_cutting` stands no railing where its line is
  on a street at grade. `tests/cut_under.gd` 7: cuttings a metre deep or more under a street
  (expect 0), `AT=x,z` lists the tunnels and cuttings near a point; `start_drive`'s t 21 s
  shot (`STREETS_BUILD_ALL=0 SECS=21 STEP=3`) is the user's view.
- **Two give-way signs side by side** (user: "a lot of places have double signs"): a sign
  with a facing (every inferred one, OSM's with a direction) was given to every way in
  within 45 degrees of it, and where a slip road merges at a shallow angle the street it
  joins comes in within 20 degrees: the street got the slip road's triangle (the post of the
  first pushed the second 0.6-1.5 m out) and its dashed line -- and its traffic gave way to
  the slip road. Now only the way in nearest the facing gets it. `tests/signs_double.gd`:
  two poles facing one way within 3 m -- Givatayim 5 of 149, Tel Aviv 9 of 239 before,
  0 after (poles 149 -> 138 and 239 -> 213: the plates streets had been given at merges).
  Ashdod (the user's screenshot, "streets 2 / 645") had 2 more of another kind: two lanes of
  a slip road arriving side by side, each its own sign, and two give-ways OSM maps 2.8 m
  apart -- now a pole is not stood within 3 m of one of the same kind facing the same way
  (`_sign_poles`; the second way in keeps its rule and line) (`sign_at` records each pole and its sign record; the city's data is let
  go after loading, so a test cannot read `_city_data` then).
- **Open: a garage tunnel's tube above the ground** by Kaplan and Begin (Tel Aviv, two
  service tunnels of 79 and 50 m from (38, 121) north to (39-44, 164-177)): from a car's
  height at (55, 175) a long dark box with the tunnel's lamp strips on top stands over the
  ground (`AT="55,175" UP=40 tests/run.sh top_at 7`, low_0.png). The same before this
  round's tunnel change -- not caused by it. `cut_under` also lists 4 service cuttings under
  a street there and elsewhere (garage mouths).
- **Autodrive waiting with the street clear ahead** (user, Tel Aviv's Shenkin: "after some
  standing behind cars, the autodrive just stops and waits for a while while there is a big
  distance ahead it can drive"). `tests/auto_stands.gd` (each stop of 4 s or more: what
  holds it and what is really ahead) caught it on Geula, one-way, one lane: 38 s behind a
  delivery van standing at the kerb, its middle 2.5 m off autodrive's lane, the lane free
  for 60 m. Traffic counts a car in its way by its middle (`LANE_W` 1.5 m) and drove on past
  it; autodrive's `lead_on` counts a car going its way by its body (0.9 + its half + 0.25)
  and stood -- and `_ap_pass_bus` goes round a van only on roads of two lanes each way or
  over a two-way street's centre line, never in a one-way street of one lane. Now
  `_ap_squeeze_by`: there, over just far enough to clear the van's body (by lead_on's own
  points and reach, at most `SQUEEZE_MAX` 2.6 m), when the car's outer side stays on the
  asphalt, nothing solid stands on the bent stretch (`_push_out`: parked cars, posts) and
  no other car is on it; else it waits as before. Traffic still does not go round a van in
  a one-way street (traffic.gd's go_round is two-way only) -- the other session's corner.
  The same squeeze when the plan was already bent round a van and it still holds autodrive
  2 s on (it pulls in further after it stops): `street_goings` 1, Katznelson's van, autodrive
  stood 32.5 s behind it "gone round" (its middle 2 m off the bent plan) -> 2.9 s. Over a
  two-way street's line only when nothing comes for 45 m past it. `street_goings` has a
  one-way case now (Tel Aviv's Karmia: the van stood in the lane, a car queued behind it,
  autodrive waited behind that car 22 s -- right: no room). `auto_stands` from Allenby, the
  same three streets: 4 stops / 66 s -> 0; from Dizengoff 4 stops, 26 s, all real (behind a
  bus queue, a motorbike pulling away; one 4 s 'blocked' by the nose's safety net with 60 m
  free, not chased). Other stops the first run logged were real too: behind a bus pulling
  away, a van at a red, giving way to a car 8-12 m off at a junction.
- **A building across Dizengoff** (user, overhead view: "building in middle of the street"):
  Dizengoff Center's two bridges over Dizengoff Street are OSM outlines with no
  `min_height`, so they stood on the street from the ground, solid. `_clip_buildings` kept
  them whole (a street runs under them: cutting the road out would take more than half) but
  nothing raised them. Now one the street runs right under (`_spans_a_cut`), with no base of
  its own, is put up `OVER_ROAD_BASE` (5.5 m) on its columns (`_stilts`: none in the lanes,
  not solid), or left out when under 8.5 m tall. Tel Aviv 3 raised (`bld_raised_over_road`
  in the "city" event; `over_road_at` lists their middles), 1 left out; Givatayim's one, a
  4 m box across an Ayalon slip road at (890, -511), left out. Shots:
  `AT="-1441,-23;-1486,-85" CAR="-1414,-6,-0.78,-0.62" tests/run.sh top_at 7`.
- **Parked cars down the middle of main roads** (user, Tel Aviv, Katznelson by Manara: "a
  lot of parked cars in the middle of somewhat main roads"): each half of a divided road is a
  one-way road of its own, and `_build_parked` parked both its sides -- its left side is the
  median, so a row of cars stood down the middle. Now the left of a one-way road is skipped
  wherever `_partner` finds its other half within `PARKED_MEDIAN_GAP` (12 m, edge to edge),
  and no car parks where another road's asphalt is 2.6 m past its middle on the kerb side (a
  service lane alongside). `tests/parked_median.gd` counts parked cars with asphalt both sides
  (`_parked_at`, `_parked_face` keep where each stands): Tel Aviv 695 of 16,624 before, 0 now (82 with the median rule alone: service lanes alongside); Givatayim and Ashdod 0. Shots:
  `AT="1110,-52" CAR="1070,-49,1,0.05" tests/run.sh top_at 7`. Not done: the user added that on
  their wider streets the outer lane is parked in, on the road, not up on the pavement -- here
  every street parks half up the kerb, and the lanes share the whole asphalt
  (`_lane_off`/`_lanes_each_way`), so a parking strip on the road needs traffic, autodrive and
  the lane paint to give that width up first.
- **Cars stopping for a slip road's light** (user, Ashdod, Sderot Menachem Begin past Herzl:
  "why are the cars stopping there"): OSM has a traffic signal on Herzl's slip road 18 m
  before it joins Begin eastbound; `_lights_setup` moves a signal to the nearest junction
  within 40 m -- the join, ~35 m past the Herzl junction, by the bus stop -- and every way
  into it stopped, so autodrive and the traffic stood there on red with nothing to wait
  for. `_slip_join` (in `_site_ways_in`): a lit point where only slip roads (`*_link`) join
  a one-way main road running straight through, all from its right-hand side, keeps the
  main road's ways in as from inside the junction (no stop line, no pole; every reader of
  `_sig_line` skips those) -- only the slip road stops; joining from the left, across the
  traffic, it stays a light for all. (Left out instead of marked, the main road's car took
  the slip road's way in -- 24 deg off, inside `_way_in`'s 45 -- for its own and stopped
  anyway.) `lights_slip_joins` in the `city_built` event: Ashdod 10, Tel Aviv 22,
  Givatayim 11. After: the three drives across the knot never stood there.
  `tests/light_line.gd` (autodrive from `CAR`, to `DEST`, every stop of 2 s: what holds it,
  the lit point, nose to stop line, the light's colour): from the start up Herzl to
  HaAtzmaut, `DEST="-1430,2700" CAR="-1799,2526,-0.2,0.98"` level 3 (`WAYS=1` prints each
  light's ways in) -- before, one run in three stood there (the light red), the nose 1.6 m
  short of its line.
- **Medians' ends messy** (user, Tel Aviv, a median with railings by a zebra: "the pavement
  on those middle areas seems messy a lot of times. the geometry doesn't align"): a median
  was pieces laid apart -- each half's strip of it (`inner_side` in the kerb runs), in that
  half's own street paving (two colours side by side), ending square with no kerb across the
  end; corner kerbs curving into it; and the cross street's stretch between the two halves
  with a kerb and pavement of its own standing in front of its end. Now, for a median under
  `MEDIAN_ROUND` (10 m): one paving (the road's name's), a kerb face across each end
  (`_kerb_cap`), no corner on its side (`_corners_at`: `corners_on_a_median`), no kerb run
  facing it (`_faces_median`: `kerb_runs_facing_a_median`). Wider ones keep their rounded
  noses (the corners' curves). `tests/median_ends.gd` (Tel Aviv: 1,652 ends at junctions,
  939 by a zebra) shoots 8 from the driver's seat and above.
- **Slip roads' triangles** (the same report, 21 Nov): the triangle between a slip road
  (`*_link`) and the roads it joins is rarely mapped as an area, so each road laid its own
  kerb and paving into it -- strips standing loose and askew in the junction (Moshe Dayan /
  HaShalom (844, 457), Yigal Alon / Arvey Nahal (752, -501)). `_find_link_islands` (after
  `_find_islands`) closes each slip road with the shortest way back between its ends along
  the other drivable roads (`_short_way`, at most 2.5x its length + 40 m); a ring of
  12-4000 m2 with no building and no mapped island in it becomes a made-up lawn area
  (`"made": "link"`), cut off the roads' strips and the junctions' discs (`_island_cut`, as a mapped island: left
  over the discs, `city_check`'s "islands on the road" read 1 / 13 / 7 / 0 / 2 and a turning
  car would meet the kerb) and kerbed all round. Every kerb piece, end cap and corner whose paving would lie inside the
  triangle is left out (`_in_link_island`, on the whole ring, not the cut pieces: the cut
  ones are too thin to catch the pavement's middle). The trap that cost a round: `_fit_widths`
  pairs a slip road with the road it leaves as a divided road's two halves, so the slip
  road's triangle side is its "median side" (`inner_side`) -- the test must apply there too.
  Tel Aviv: 111 pieces, 5,789 m2, 827 kerb pieces and 132 corners left out, 0 over asphalt;
  `city_check` the same as before in every town (Ashdod's two pavings 271 -> 235 m2).
  `tests/link_islands.gd` (`AT=x,z` also prints every kerb run near the point and how much
  of it faces into a triangle, and shoots the spot as it is, so it works on `main` too for a
  before). Left at (844, 457): Moshe Dayan's own median ends (loose pink blocks) are the
  median work above, not the triangles. A footpath mapped across a junction's corner
  drawn through a median's nose (Shaul HaMelekh / Ibn Gabirol, path 2197, (-847, -70)) was
  noted with the median fix; looked at again 21 Nov (`top_at` AT="-847,-80;-845,-66" UP=16):
  nothing of the path shows (a path's ribbon lies under the asphalt and the median), the pale
  patch at the nose's end is the crossing's tactile paving, and the triangle beside it is now a
  slip road's island. Not reproduced; reopen with a picture if it is seen again.
- **A flickering line across the screen** (user, the first filmed walk's passage: "flickering
  line in the middle of the screen sometimes. dunno if its my screen or godot or bug"): the
  sky dome (`_build_sky_dome`) was Godot's hemisphere, which closes with a flat disc at its
  middle's height, and `_sky_follow` stands the dome on the eye -- a plane through the eye.
  A phone's GPU drew it now and then as a one-pixel line in the horizon's grey at the horizon
  (row ~270 of 896 in the walk's view, pitched 15 deg down), over near hedges too; the
  software renderer here never draws it. Now a whole sphere (the lower half the horizon's
  haze). `tests/horizon_line.gd` + `horizon_line.py`: `DROP=0.002` stands the dome 2 mm below
  the eye, `HEMI=1` puts the hemisphere back -- the line in every frame before, none after.
- **Which build** (user: "add the version somewhere, maybe near the map"): `_build_line` over
  the minimap reads res://build.txt, now "<UTC time> <commit>" (tools/publish_web.sh); the
  credits under the map are size 7 and wrap clear of the bottom buttons (Tel Aviv's ran
  under "autodrive"). To tell whether a screenshot's build holds a fix:
  `git merge-base --is-ancestor <fix> <commit>`.
- **Tel Aviv grew** (another session, the bake workflow's bbox): 4,011 -> 9,597 buildings,
  3,745 -> 5,963 roads, west to the sea -- Ashdod's size now, and its load with it (see
  "Numbers to compare against").
- **Waiting on the user**: the Ashdod "grass patches" spot was never pinned down: islands
  and the ground colour went out without it. **Next**: traffic overlapping at the test town's
  (-639, 261) -- a bus turning off Derekh HaHarim sweeps over the stop line of HaDolev where
  cars wait (the junction is two points at one place joined by 0 m pieces, fake_city's).
- **Tests and tools added**: `hitches` + `hitch_parts.py` (frames over 250 ms by phase --
  only meaningful in a real browser), `top_at` (shots by map point, `CAR=` to put the car
  anywhere), `street_at` (by street name at its roundabouts), `perf_dive`, `deck_corner`,
  `islands`, `pave_overlap`, `picker`, `minimap_route`, `warm_census`, `index_gain`,
  `signs_inferred`, `start_drive`, `rails_near`, `cut_under`, `signs_double`, `auto_stands`,
  `parked_median`, `horizon_line`, `median_ends`, `light_line`;
  `tools/level_roads.py`.

## OSM's extra fields and speed limits: handoff (20 Nov 2026)

One session's work, written for whoever picks it up (its context is compacted after this).
It started from the user asking what the city data lacks for a realistic feel; the answer
and the outside sources that could fill it are in `IDEAS.md` ("Official data for what OSM
leaves out").

- **The bake keeps more of OSM** (`tools/osm_city.py`, format at its top): roads' `ms`
  (speed limit, km/h), `lf`/`lb` (lanes each way), `tl`/`tlf`/`tlb` (turn:lanes as
  written), `sf` (surface when not asphalt), `sw` (pavement sides); buildings' `k`, `lv`,
  `col`, `rc`, `rs`, `mat`, `yr`. (Bus lanes are `bf`/`bb`, the Tel Aviv session's.) Each only
  where tagged: missing means "not known". The bake logs a "tagged:" count per field.
- **What the game uses: the speed limit.** A road's `speed` (streets.gd, where the city's
  roads are read) is OSM's `ms`, else the town's own limit for that kind (`_town_limits`
  -> `_town_ms`: 20+ tagged, a quarter of the kind, 85% one value), else the guess by kind
  (`DRIVE`, `NORTH_FASTER`). Traffic, autodrive and the speed signs all read that one
  number. Givatayim: residential 30 (inferred from 184 of 628 tagged), secondary 60 where
  tagged; Tel Aviv: residential and unclassified 30, the Ayalon 90.
- **So the residential streets of Givatayim and Tel Aviv are driven at 30 now, not 50.**
  Route times, the exam and anything timed there before this are at the old speeds:
  rerun before comparing. Ashdod and Bedford are unchanged until re-baked.
- **Not used, on purpose**: wall and roof colour, roof shape, material, year -- 0.5-4% of
  buildings in both towns (and the wall shader takes a palette tint index, not an RGB:
  a real colour needs its own path); turn lanes and lanes each way (under 1% of pieces);
  pavement sides (2-16%).
- **Tried and dropped: building heights from the terrain tiles** (surface minus bare
  ground) -- no use, see the `real-places` skill.
- **Outside data** (municipal buildings, trees, businesses, GTFS, parking zones): at first
  none was reachable (over.org.il, data.gov.il, gisn.tel-aviv.gov.il, gtfs.mot.gov.il all
  refused), and e.data.gov.il's CDN refuses the cloud even when allowed (Tel Aviv handoff).
  Tel Aviv's own GIS server answers once its host is allowed: see the next section. The
  list and the licence caveat are in `IDEAS.md`.
- **Checks, and what good read** (20 Nov 2026, Givatayim and Tel Aviv re-baked):
  `tests/speed_limits.gd` -- autodrive 40 s never more than 10% over the road's limit
  (Givatayim: 23 s at 30, 17 s at 50, fastest 51 km/h; Tel Aviv's start stays on 50 roads);
  `tests/rails.gd` at level 1 -- 13 tracks, 3 lines, 0 bed points over asphalt;
  `city_check` at level 1 -- 3, the same 3 with the file from before the re-bake (two
  posts 1 m into Aluf David and Katznelson, the passage's building): not the re-bake's.
- **Bus lanes in Givatayim: OSM marks none** (0 road pieces with `bf`/`bb` in a main-server
  bake, 20 Nov), though the Ministry of Transport's layer lists 4 stretches there: they
  would have to be mapped on OSM, or come from that layer (see `IDEAS.md`).
- **Open**: re-bake Ashdod (brings its railway) and Bedford with `main_server_only`; a
  sign at the start of each 30 street (the game has `signs_zone30`, placed by its own
  rule, not by `ms`); the speed signs are on main roads only.

## Tel Aviv's own survey: building heights (20 Nov 2026)

Tel Aviv-Yafo's GIS publishes its buildings layer (`gisn.tel-aviv.gov.il`, IView2 MapServer
layer 513 "מבנים", 45,758 buildings): a measured height (`gova_simplex_2019`, roof top
minus ground, 97%), floors (95%), year built (72%), columns / open ground floor
(`t_amudim`), and kind (regular, temporary, bus shelter, public, under construction).
The cloud environment allows the host now (the user approved it).

- **Where it goes**: `tools/osm_city.py`'s `SURVEYS` step -- part of every bake whose box
  overlaps the layer, or alone on a baked file: `python3 tools/osm_city.py --add-surveys
  game/streets/cities/tel_aviv.json` (~45 s; Givatayim ~25 s). The rules (what OSM keeps,
  the 1.9 m shift, the 2019 towers) are in the `real-places` skill and at `SURVEYS`.
- **What the files have now**: buildings' `h` from the survey with `hm: 1` and no `g`;
  `yr` (where OSM had none) and `pil: 1` (columns) from it; `credits` at the top, which the
  game appends to the OSM line bottom left (`_credits`, `_osm_lbl`).
  Tel Aviv: 3138 of 4011 buildings take the survey's height (median +4.0 m on what they had;
  guesses left 401 of 2623), OSM's own kept on 232 (the record towers, the post-2019 ones);
  462 survey heights out of line with their floors (trees over low houses) taken from the
  floors; `yr` on 2964, `pil` on 1291. Givatayim: its Tel Aviv strip only, 1039 of 6243
  (guesses left ~4730); Givatayim itself is not in this layer.
- **Landmarks** (`tests/landmarks.gd`): measured to the ridge, Sarona's two-storey Templer
  houses are 9-16 m, so `TILE_MAX` went 13.5 -> 16 (with 13.5 the tiled count fell 39 ->
  30). Lit roofs 92 -> 102 and lamps 355 -> 395: more buildings over 90 m now.
- **Licence**: the municipality's open-data licence (as quoted in 2012 and in the portal's
  FAQ) lets anyone copy, publish and process the data for any lawful purpose, crediting the
  source, as-is. Not checked: whether layer 513 itself is in the open-data catalogue
  (`opendatasource.tel-aviv.gov.il`, not reachable from here). The credit on screen:
  "building heights © Tel Aviv-Yafo Municipality".
- **A re-bake must reach the server too**, or the heights are lost and the bake logs
  "survey tel_aviv_yafo: cannot reach ...". GitHub's runners reach it: the workflow's bakes
  of Tel Aviv on 20 Nov (the 4.3 x 3.3 km box) came back with 8,322 of 9,597 heights
  measured. After any bake, check the file's `credits` and its count of `hm`, or run
  `--add-surveys` on the result here.
- **Open**: Givatayim's own buildings (GovMap's public layers have no heights, see
  `IDEAS.md`; its municipality's GIS not found -- `LOCAL_DATA_TASK.md` hands this, with
  GovMap's places, data.gov.il and GTFS, to a session on the user's own computer); drawing `pil` (Tel Aviv's blocks on columns, a
  third of them -- the ground floor as columns and shade); the ~500 small buildings the
  survey has and OSM lacks (median 35 m^2; 57 over 300 m^2), not added; a tower complex
  OSM maps as one outline keeps OSM's height (splitting it into the survey's pieces would
  give the podium and the tower each their own).

## Data fetched on the user's computer: Givatayim's storeys, places, cars, bus lanes, GTFS (21 Nov 2026)

A session on the user's own computer in Israel did `LOCAL_DATA_TASK.md` (now marked done).
Everything is in `game/streets/cities/data/`, small enough to commit; the scripts that
fetched what can be fetched again are in `game/streets/data_tools/`. Raw downloads are in
the user's `tools/.cache/` only.

| File | What | Source, licence, credit line |
|---|---|---|
| `givatayim_muni.geojson` (1.1 MB) | 3,073 building outlines with `fl`, floors incl. the ground floor | Givatayim Municipality's map (Complot GIS-net viewer, layer "מבנים - 2025"); no licence published, only "© עיריית גבעתיים" -- the user approved committing it. "building storeys © Givatayim Municipality" |
| `ramat_gan_muni.geojson` (1.5 MB) | 2,704 outlines with `fl` (NUM_FLOORS), the level-1 box only | Ramat Gan Municipality's own ArcGIS Online layer `building_23_02_2025`; no licence text on the item. "building storeys © Ramat Gan Municipality" |
| `places_givatayim.geojson` (37 KB) | points: kindergarten 87, daycare 35 (no names: private ones are named after people), school 14, shelter 37 (type, above/underground), public_garden 43, community_garden 9, dog_park 16 (gardens as centroid + `area_m2`) | Givatayim's map as above. "places © Givatayim Municipality". No playgrounds layer is published there |
| `vehicle_mix.json` | shares of makes (Hebrew names as registered, maker + country, e.g. "טויוטה יפן" and "טויוטה טורקיה" are both Toyota) with top models, colours, year bands, fuel, private/commercial | Ministry of Transport register on data.gov.il, "Other (Open)"; a 300,000-row evenly spread sample of 4.2 M via the CKAN API (`vehicle_mix.py`). "vehicle mix: Israel Ministry of Transport, data.gov.il" |
| `bus_lanes.json` | public-transport lanes: givatayim 20 stretches, ashdod 47, tel_aviv 122; start/end points, street, direction, hours, taxis, lanes | Ministry of Transport `nataz_kayam` on data.gov.il, CC BY (`bus_lanes.py`). "bus lanes: Israel Ministry of Transport (CC BY)" |
| `transit_givatayim.json` (1.05 MB), `transit_ashdod.json` (1.7 MB) | stops, routes (line, operator, direction, headsign), shapes clipped to the box, every trip of Tue 24 Nov 2026 with its stop times in the box. Givatayim: 213 stops, 132 lines, 11,252 trips; Ashdod: 598 stops, 102 lines, 4,184 trips | Ministry of Transport GTFS (`gtfs_towns.py`, format in its docstring). "public transport: Israel Ministry of Transport" |

- **Heights on level 1** (`--add-surveys`, `SURVEYS` now has `givatayim_muni` and
  `ramat_gan_muni` after Tel Aviv's): measured or surveyed 1,039 -> 5,861 of 6,243
  buildings, guesses 4,726 -> 213. Givatayim's survey set 2,373, Ramat Gan's 2,449, OSM's
  own tagged height kept on 65. No outline under 300 m^2 over 40 m. Spot checks: IM
  Givatayim 1 was a 13 m guess, now 31 floors (94.5 m); the "Beyond" office tower stays at
  OSM's 307.5 m (survey 78 floors). Floors become `fl * 3 + 1.5` m (the ground floor is in
  the count -- they matched OSM's `building:levels` most often), so a 3-storey block is
  10.5 m. A re-bake anywhere reads the two extracts (`survey_extract`); no network needed.
- **What a cloud session should do with it**: run `landmarks` and a playtest of level 1
  (heights changed on 4,800 buildings: lit roofs, lamps and the tiled count may move);
  draw the places (a kindergarten's fenced yard and shade sail, a shelter's sign and
  concrete entrance -- `places_givatayim.geojson`); colour and pick the traffic's and the
  parked cars' models from `vehicle_mix.json` (41% white "שנהב לבן", then silvers, blacks
  and greys; 80% petrol, ~10% electric or hybrid); mark the bus lanes by matching
  `bus_lanes.json`'s street names and end points to the roads (the baker's OSM `bf`/`bb`
  have some already); run buses on `transit_*.json`'s lines and times.
- **Open** (updated after the second round below):
  - **Ashdod's heights:** its map has no layer of all its buildings, only the public
    ones (316 heights). GovMap and the Survey of Israel are long shots, by hand in a
    browser, unchecked.
  - **Ramat Gan's trees:** not fetched. Its ArcGIS Online host (services8.arcgis.com)
    answers from anywhere, but the cloud environment does not allow it yet; whether a
    trees layer exists is unknown.
  - The fetch status and what else could be had are in the root ideas file's "Official
    data" bullet. The GTFS terms page on
  gov.il cannot be read by tools; the user read it and found nothing against reuse.
  Ramat Gan's layer has no licence text either; the user approved committing it too.

**Second round, same night: "a lot of data, usable later even if not obvious now"** (the
user's words). `cities/data/` has a `.gdignore` now: Godot imports `.json` as a resource and
the web export takes every resource, so 20 MB of raw data would have gone to every player
(the first round's ~6 MB of `.json` did ride in one build). To use a piece, bake it into the
city file or a small file outside `data/`.

| File | What | Credit |
|---|---|---|
| `givatayim_trees.json` | 11,893 tree crowns mapped from the air: centre + radius (OSM has a few dozen trees there) | © Givatayim Municipality |
| `givatayim_spot_heights.json` | 10,120 surveyed spot heights, m above sea level (some on roofs) | " |
| `givatayim_land_use.geojson` | 4,006 plots with their statutory use (residential A/B/C, commerce on the ground floor, public, open space, roads...) | " |
| `givatayim_addresses.json` | 3,593 house-number points, Hebrew and English | " |
| `givatayim_units.json` | each building's centre, flats and floors (density: how many people live where) | " |
| `places_givatayim.geojson` | + traffic-light junctions 17, shared scooter/bike parking 180, recycling bins 118 (with kind: clothes, glass...), youth centres 12, defibrillators 93 (place, hours), institutions' protected spaces 148, active building sites 54 (polygons, with what is built), antiquity sites 8 | " |
| `places_ramat_gan.geojson` | the level-1 box: kindergartens 56, schools 10, building sites 63, advertising columns 264, bus stops' shade (`shade_pct`, `canopy_m2`) 58, commercial plots 4 | © Ramat Gan Municipality |
| `ashdod_muni.geojson` | 1,300 public buildings with floors, use, kind and name -- Ashdod publishes no layer of all its buildings; applied to `ashdod.json`: 316 heights, guesses 9,499 -> 9,183 | © Ashdod Municipality |
| `places_ashdod.geojson` | kindergartens 234, schools 133, youth movements 41, pharmacies 22, parks 402 (polygons, names), sculptures 117, sycamores 53, old trees 112, vegetation survey 214 polygons (species), nature sites 31, shelters 76, direction signs 177, city maps 30, billboards 30, bus terminals 8, BRT corridors (stage A 67, B 69 lines), traffic lights 52, bus stops 409 (with their lines), fuel stations 35, covered parking 203, archaeology 31 | " |
| `ashdod_land_use.geojson`, `ashdod_addresses.json` | 11,629 plots' use; 9,718 house numbers | " |
| `tel_aviv_trees.json` | 8,515 street trees with species (Hebrew and Latin) | © Tel Aviv-Yafo Municipality (open-data licence) |
| `tel_aviv_lamp_poles.json`, `tel_aviv_hydrants.json` | 16,894 lamp poles (type, lamps each); 2,102 hydrants | " |
| `tel_aviv_businesses.json` | 13,125 licensed businesses: what they are, floor, street -- no names (a sole trader's is their own) | " |
| `places_tel_aviv.geojson` | bus lanes with hours 89, parking zones 7, building sites 790 (stage, use), preserved buildings 2,188, motorbike parking 371, loading-zone signs 386, taxi stands 44, bike paths 210 (width, direction), bike-share stations 717, sculptures 98, notice boards 137 | " |
| `transit_tel_aviv.json` | level 7's box: 372 stops, 225 lines, 19,482 trips (same format as the others) | Israel Ministry of Transport |

Boxes: Givatayim's and Ramat Gan's are level 1's; Tel Aviv's is level 7's joined with level
1's west strip; Ashdod's map is the whole town. Scripts: `ramat_gan_layers.py` and
`tel_aviv_layers.py` (both reachable from anywhere, so a cloud session can refresh them);
Givatayim's and Ashdod's come only through their map viewers in a browser (see the
`real-places` skill), so there is no script: the layer ids and fields are in each file's
`source`. Not fetched: their security cameras, parcels, planning lines and alerts, and any
manager, phone or key-holder field; Ashdod's bike paths and urban-renewal zones fail on its
server. Ideas it opens: real tree species and sizes along the streets, lit lamp poles where
they stand, shopfronts by kind and floor, building sites with hoardings and cranes, paid-
parking kerbs, bus stops with their real lines and shade, sculptures and defibrillators as
landmarks, a quiz or errand on real addresses.

## The towns' own trees (21 Nov 2026)

Tel Aviv's list of street trees (8,515, each with its species) and Givatayim's crowns traced
from the air (11,893, each with its radius), both fetched on the user's computer
(`cities/data/`), are in levels 1 and 7.

- **Baking** (`tools/osm_city.py`): `TREE_SURVEYS` (each file, its "shift" onto OSM's
  map -- the offset measured on the same town's buildings: Tel Aviv -0.4, -1.9 m;
  Givatayim +0.8, -0.6 -- and "all": whether it maps every tree), `TREE_FORMS` (a word of
  the Hebrew species name to one of nine forms; the 247 names' long tail falls to "round"),
  `tree_surveys_apply` (run by the bake and by `--add-surveys`; a crown over 7 m in radius
  is a grove's canopy, sown as trees of 4.5 m; OSM's trees within 3 m of one dropped). The
  city file gains `tree_info` beside `trees` ([form, crown dm] a tree), `tree_forms`,
  `tree_surveys` (format at the top of the tool). Re-apply after a change:
  `python3 tools/osm_city.py --add-surveys game/streets/cities/tel_aviv.json` (and
  givatayim.json), about a minute each (it re-applies the building surveys too).
- **The game** (`_build_trees`): a mapped tree takes its form's kind (`fixed`), a crown its
  size (`cr / crown width`) and a kind by size when the map has no species (`_crown_kind`:
  over 5.5 m ficus or eucalyptus, under 1.3 m olive or round, else the street mix). It gets
  a trunk's room (`_mapped_tree_ok`: 0.4 m off the asphalt -- the road's strip, a rounded
  corner's curve and a junction's disc, `_off_road` and `_in_junction`: on the strip alone
  40 of Givatayim's and 42 of Tel Aviv's stood up to 1.3 m into a corner, `city_check` --
  0.6 m off a wall, 1.2 m apart),
  and where it has none it is moved (`_tree_nudge`): onto the pavement 1 m or 0.6 m from
  the kerb (Tel Aviv plants in the parking lane, and OSM's widths are guesses) and out past
  a corner's curve (`_out_of_corner`), out to the
  nearest wall's foot from up to 2.5 m inside a house (4 m for a crown from the air, centred
  over the roof it overhangs); a grate or earth square under it on a pavement. Where an
  aerial map covers (`_tree_cover`, within 40-80 m of its trees) nothing is made up; a list
  of street trees is not every street tree (16 listed along a stretch of Rothschild that has
  rows), so there the made-up street rows go on but not within 9 m of a listed tree
  (`_mapped_near`). The caps (`MAX_TREES`, `MAX_FOREST`) count made-up trees only
  (`_trees_mapped`). The credits are one line by owner (`_credit_line`).
- **Test**: `tests/real_trees.gd` (README row: the numbers; before/after with
  `STREETS_CITY_FILE`, which keeps the level's own town id). Load times unchanged.
- **Lost** (Tel Aviv 3,096, Givatayim 4,863): trees deeper in a house than the moves
  allow (Givatayim: ~2,700 crowns centred over a roof by more than 1.4 m; Tel Aviv: ~950
  more than 2.5 m inside an OSM outline -- courtyards drawn as roof, or a private plot),
  over 4.5 m into a road (a boulevard's middle where OSM maps one road), or with no
  trunk's room left between kerb and wall.
- **Open**: what each species looks like beyond its form (a jacaranda's purple in May and
  June, a bottle tree's trunk, a ficus' hanging roots); Tel Aviv's sizes (none given: a
  species' usual size would do); fewer lost (a crown over a roof could stand in the yard
  behind, not only at the nearest wall); Ramat Gan's trees (no layer fetched yet); Ashdod's
  sycamores, old trees and vegetation polygons (`places_ashdod.geojson`).

## Handoff: the street's realism and life, loading split, crashes, sounds (20 Nov 2026)

One session's areas (everything under "front gardens", "the street's goings-on", "more kinds
of people", "people in one piece", "on the walls", "street sounds", "what breaks", "load, part
by part", "graffiti", "zone and parking signs" near the top of this file, and today's earlier
realism passes: contact shadows, far shadows, golden hour, night, grass, wet, garden walls and
gates, pavement covers, recycling, two-wheelers, passages). Shots: `FULL=1 STREETS_BUILD_ALL=0
RES=1280x720 OUT=<dir> game/streets/tests/run.sh <test> 1`; headless ones: `STREETS_BUILD_ALL=0
LEVEL=1 $GODOT --headless --path . -s res://game/streets/tests/<test>.gd`.

- **Good numbers (Givatayim, level 1)**: `draws` 184 in view at the start (people 8);
  `gardens_later` 7510 wall pieces / 858 board points both ways, gardens 96-128 ms of
  loading (678 unsplit); `load_stages` kerbs ~0.8-1.0 s; `street_goings` autodrive stands 0 s
  behind the van on both streets, 1-2 cars go round it on the one-lane street (המפנה or
  שיינקין), the parked car pulls out with the player ~44 m behind and never touched;
  `street_people` a dog, a pushchair, a sitter, a waiter each within 80 m inside a minute;
  `street_sounds` birds -31..-34 dB by day by trees, crickets ~-36 at night, voices -20 / -25;
  `crash_things` a bin knocked, a bollard bent, 3 dents, 2-3 glass patches (its "clear run"
  checks the car's nose all the way in, the target left out: checking the middle only, it
  picked a bin with a new give-way sign's pole 0.5 m in front, and the car stopped at the
  pole -- the game was right; `TRACE=1` prints what is solid at the nose each tick); `wall_things` the person 1
  surface; playtest smart 25 s passes, hitches 4-11 (container noise: compare with main, run
  alone -- 16 with a second Godot running beside it). `walk_people` (level 6, headless,
  `--fixed-fps 10`, ~4 min): 0 pops, 0-1 turned in view, 0 within 0.6 m of you, deepest into
  a parked car 0.17-0.27 m (a car's end corner; was 0.55 in its middle), 5-7 people met
  within 40 m; `people_clear` 0.0% in a post or wall.
- **Open**: Walk 1's
  end (93 s) had a walker 0.37 m off you once. The shop shots (`shop_looks` 6) face down the
  street, not at a front: the boards and shopkeepers have not been seen in a picture yet.
  Walk 2's streets are thin (5-7 people within 40 m over its 106 s); people still
  graze a parked car's end corners by ~0.15 m (round posts); the walk's own line runs
  against parked cars at 60-70 s (WALKS.md), where people giving way pass on its far side;
  a dog can be pushed to the far side of a crossing railing (`_companion`'s
  `_push_out` picks the nearer side); grass blades still poke through a garden path where it
  crosses a lawn; the sounds are synthesised (make_sounds.py) and the user has not said how
  they sound; more things that break (sign posts, fence panels, hedges, a scrape mark on the
  wall) and people who react are on GAME.md's later list; falling rain is on hold (user);
  the browser's 5-7 s warm-up is shader compiling (see the other handoff's 74 shader kinds).
  `draws` hung once for 15 minutes and never again (cause unknown: kill it and rerun).
- **Lights, wheels, doors, plaster (21 Nov)**: good numbers -- `car_lights` (shots): lamps
  read red / amber / white, not white blocks; plates clean (garbled before `plate_id` was
  flat); the front wheel turned; מונית legible. `street_goings KERB_ONLY=1`: in at 86 m,
  shut 0.7 s later, backed up at 61 m, never nearer than 20 m, the door open only while you
  were 84 m+ off. `building_looks`: Givatayim's plaster from its file -- sand 3,310, cream
  1,334, white 1,002, stone 494, tinted 103 (it was half white, two in five of the rest
  stone-clad). Open: speed humps (the baker keeps no traffic_calming; needs it and a
  re-bake); closed-in balconies not yet seen up close in a shot (the blocks near the start
  are mostly punched windows: aim `building_looks` at a balcony block); the bus's, truck's
  and scooter's indicators are still boxes; in the KERB_ONLY run the kerb car came without
  its passenger (the dice, or no room by the pavement: not told apart) and the test put one
  there; the film's sand in shade is browner than the game's.
- **Walk 1's side-by-side, 21 Nov (after the plaster, lights, people rounds)**: recorded
  (`RECORD=1`, 966 frames, 19 min) and put beside the film (the recipe under "The filmed
  walk", `-crf 30`: 15 MB; the film from the mail connector, kept in the scratch folder only).
  Matching well: the crossing, the arcade's shops, the bollards and gate at 27 s, the
  passage's stone wall and plank fence, the hedges, the graffiti pole, the kerb paint, the
  parked rows; the old blocks now sand. Biggest differences left, most first: the light on
  the ground -- the film's pavements lie in dappled shade under dense canopies, the game's
  are bright and even; the pavers -- grey, worn, low contrast in the film, the game's
  herringbone bright and crisp; at 19 s the game's camera stands at a tan wall where the
  film sees motorbikes on an open forecourt; the film's people at 59 s (the man in blue at the
  railing) are off the game's frame (known, WALKS.md).
- **Watch**: hitches in the first seconds of driving now include the start's far gardens
  (`_build_gardens_later`, before the rest of the city), and since the city builds only what
  the first view sees before the car, the catch-up of the rest of NEAR_FIRST (16 ms a frame,
  `CATCH_UP_US`: frames ~34 ms against ~10 for its 3-6 s; the playtest's smart 25 s showed 12-14
  hitches, "building 24", where 4-11 was usual before); kits with thousands of copies go
  through `_instanced`, not the batches (the AC units: 19 hitches of 50 ms when merged).

## Open problems

- **Tel Aviv's lights and the exam, first round** (Nov 2026). `light_audit` at level 7:
  4 junctions where crossing streets shared a green, all skewed (55-65 degrees): the ways
  from inside a junction (the road between two of its points, no light) were counted in
  `_site_axes`' split into two groups, and their directions forced a bad one (Weizmann
  shared its green with Dafna and Berkovich) -- now left out (the audit skips them too);
  0, and the other towns unchanged. 8 ways in with no light: poles were never put up on a
  bridge's deck (every spot beside it was tried at the ground's level: the road below or
  the deck's wall) -- now on the parapet's line at the deck's height, and no post at the
  ground's level under it; 5 left, the same kinds as the other towns'. The exam: 25 checks,
  then 16 -- traffic into kerbside trees and a corner bollard (Begin x Kaplan), cars
  overlapping where Begin's slip roads merge, "held by nothing" loops there, ~1 red run a
  minute; autodrive clean but for 2 brushes of the parapet at the HaShalom bridge's east
  junction, up in the air. Its "off the asphalt" measured to the road below a bridge: now
  at the car's level.
- **Tel Aviv's decks, what is left** (Nov 2026, after the ramp-top fix -- see "Hops at ramp
  tops" under "Off the ground"; `tests/decks.gd` at level 7 with `DECK_KINDS=br` for the
  bridges, without for the tunnels). In the air: Arvei Nahal's seam, 9 frames (a 0.44 m
  step where a ramp overlaps the deck it leaves), one frame in an unnamed tunnel at
  (-178, 245); the rest 0. `tests/street_holes.gd`: 8 points of the HaShalom bridge's west
  ramp 0.7-0.9 m under the street beside it (Givat HaTahmoshet at (129, 173)); 5 points in
  a deck's wall, all banks' feet at a street's edge (Yitzhak Sadeh's at (-170, 1107), one at
  (76, -34)) -- `bank_at` lets a foot come within 0.5 m of another road's asphalt, and a car
  at the kerb brushes it. A car-park service bridge at the south-west corner ends at a
  building (autodrive noses it). Two branch ramps out of Lova Eliav's west end are too short
  to climb out at 10% and lie on the ground. A tunnel's tube is drawn whatever is over it,
  buildings included (Lova Eliav runs under HaKirya's blocks).
  **Measured again 21 Nov** (`decks.gd` `DECK_KINDS=br`, `street_holes.gd`, level 7): every
  bridge driven 0 frames in the air and 0 off the level (Arvei Nahal's seam gone); holes 1
  point (134, 179), 0.5 m (was 8, 0.7-0.9 m); walls 4 points (Yitzhak Sadeh's bank 2, Ayalon
  South's embankment at (753, -1300), the bank at (76, -34)). The car-park "bridge" (`_3447`
  in the test, (-1202, 1203)) is a rooftop car park's ring of parking aisles on layer 1 by
  HaRakevet station, joined to no road on the ground: no car can get onto it, the test puts
  one there and it noses the building it stands beside. Left as it is (dropping a deck network
  joined to nothing would be the fix, if one is seen from the street and looks wrong).
  The same day `decks.gd` at level 1 (twice): every deck run clean but the City tunnel's
  (`מנהרת_הסיטי_1372`), whose autodrive roamed out of the tunnel onto a car park's aisle
  (Givatayim (-722, -1078) to (-735, -1078)) that ends in a building -- an underground car
  park's way in -- and hit the wall and building there at 9-19 km/h, both runs; and
  Menachem Begin 1609, 40 frames off the level by up to 0.31 m. The first is autodrive's
  roaming picking a parking aisle that leads nowhere (driving's, not the decks').
- **Givatayim's ground is the terrain tiles' surface model too**: its "steepest 52%" is
  likely part roofs. Measured on its grid, `--bare-ground` would take the hill's crest
  86 -> 72 m and the steepest slope 48 -> 16%. Not re-baked: it moves the ground under the
  filmed walks and every test number, and is the user's call.
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
