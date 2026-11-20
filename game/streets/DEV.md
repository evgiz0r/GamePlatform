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
| `landmarks.gd` | a town's landmarks, found by their building's name in the bake (`BY_CITY`: Tel Aviv's Azrieli towers, the Matcal and Marganit towers, Sarona's houses): a glass of their own, a lit crown, a mast or shaft on the roof, red tile roofs; and in every town the red lights on roofs over 90 m at night. Hooks in streets.gd: `_glass` / `_tile` on a building for `_build_buildings`, `build()` per square, `set_night` |
| `rails.gd` | railways: the tracks the city file has (`rails`, `platforms`, `stations`), their beds, rails and sleepers, the platforms with canopies and the station's name, and trains running along them (`tick`). See "Railways" below |
| `cities/*.json` | baked towns (`tools/osm_city.py`) and the made-up test town (`tools/fake_city.py`) |
| `details.gd`, `cities/details/<city>.json` | what a filmed walk showed and OSM lacks, laid over the baked city as it loads (road edits, unmarked zebras, areas, an arcade cut under a block, paving level with the pavement, walls, fences, hedges, bins, railings, bollards, a pole transformer, a barrier, parked motorbikes, trees) and the walks themselves; the format is at the top of `details.gd` |
| `cities/details/make_givatayim.py` | writes the Katzenelson-Ha-Meri walk's part of `givatayim.json`: every detail placed along the Ha-Meri passage's own line, with the film's seconds beside what each came from. Edit this, not those items in the JSON, and run it. The file is shared (the Sheinkin-Sirkin walk and its kerb paint were put in by hand): the script marks what it writes `"src": "make_givatayim"` and keeps everything else on a re-run |
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
- **night lights** -- GLOW_SHADER (additive, unfogged, `skip_vertex_transform`) draws the
  pools (`_pool`, at pavement height + 3 cm), the headlight beams (`_beam_mesh`) and halos
  (`_halo`: a quad whose vertices all sit at the light, UV2.y 1, turned to the eye in the
  shader, never under ~1% of the distance across): the lamps' halos go in the pools' mesh
  (`_make_pools`), the headlights' in the beam mesh the player's car and the traffic share
  -- no draws of their own. Lit shops' light on the pavement: `_shop_lights`. The night's
  colours: the night branch of `_retint_city` (a little of the palette's player colour, not
  half of it). Shop glass at night 0.85 (2.0 clipped to white).
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
changes nothing. Quick (default): `city_check` in all four towns and the exam in the test
town at 2x -- about 4 minutes. `FULL=1`: also the exam in Givatayim and Ashdod at 1x and the
queue check -- about 10 minutes in all (November 2026, measured: city checks 10-96 s each,
the exams 46 / 89 / 140 s, the queue watch ~3 min). Run it in the background (a foreground command is cut off
at 10 minutes).

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
- **The city as built** (`city_check.gd`, seconds a city; `LEVEL=0` all four): walls,
  posts and buildings on a street's asphalt (sampled every metre of them), lit points that
  belong to no junction; and the traps to stage a test at -- stub roads under 5 m at a
  junction, lit points under 25 m apart counted as two junctions, walls and posts on
  service roads.
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
(the test town's in ~20 s, a big city's a few minutes), and `route_report.py` draws each
drive with street names (OUT dir) and appends a dated block to `tests/routes_results.md`:
arrived, time, distance, hits, the longest wait and what held it, red lights, rescues, time
off the road. Run it after a change to driving, compare with the last block, look at the
maps of whatever got worse. Pick a new set (another seed) only to widen what is covered;
keep the old block for the record.

## Numbers to compare against (November 2026, cloud container, software renderer)

- Build time in full: Givatayim ~6 s, Bedford ~9 s, Ashdod ~15 s, the test town ~1.2 s
  (the container is slower than a laptop by ~3x; compare ratios). Before the car is shown,
  near-first: Givatayim ~2 s (9 of its 71 squares), Bedford ~1.2 s, Ashdod ~2.8 s, the test
  town ~1.2 s (headless playtest, `build_ms` in the "city" event); the rest of Givatayim
  ~10 s of background building (the "city_built" event). Tel Aviv (the box, 4011 buildings,
  3667 roads, 59 squares): ~2.2-2.5 s before the car, the rest ~11-12 s.
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
  compiled in the warm-up).

## Cities

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
- **Next passes**: the light (another session's: the film's afternoon is hazy and warm);
  people that move as the film's do (the walk's `people` take `to` and `t`; none of the
  four walks yet). The street now matches the film in what stands where: what is left is
  look -- the buildings' plaster, balconies and shutters along the route (another session's
  city-wide work), the shops' lettering beyond the one the film names.

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
  pieces, 0.2 s; 2 of 63 crossings over roads short of the full clearance (4.8 m the
  lowest). `LEVEL=2` with `tests/decks.gd` drives its ten highest bridges both ways.
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
  roads), 7 cuttings, 0.3 s. Two traps on the way: a tunnel "crossed" its own next piece
  (the shared end point; skip roads that share a point), and holding the whole of every
  road crossed, or seeding the depth's room from every junction in town, made it 15 s and
  held the tunnels' own ends at street level -- only near the crossing (80 m) now.
- **Footbridges and footpath tunnels** (`infer` again, the same passes on the paths' own
  network: footway, path, steps, cycleway, pedestrian, bridleway). A footbridge chain (8 m or
  more) clears a street by 5.8 m (`CLEAR_FOOT`; a path by 3.4), its lift spreading along the
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
- **Still to do**: Tel Aviv is another session's;
  Ashdod's tight interchange at its east edge (x 3850, z -1590: slip roads crossing slip
  roads at street level -- 15 crossings short of the clearance, 0.5 m the lowest); grass slopes for cuttings too (they are walled); pavements and
  people beside an inferred cutting; a long-span
  bridge's height over water (the MacKay's deck is only as high as its ends); pavements at street
  level beside a cutting (the underpass has none); people on a bridge's pavement; the
  minimap draws a tunnel like any street; zooming out from inside the tunnel rises from the
  hilltop (the zoom centres on the ground's height); the heights are whole decimetres, so a
  deck's grade kinks by up to 2% every 5 m (enough for a 2 cm hop off HaNasi's bridge);
  autodrive turning right off the flyover's foot onto HaRakefet clips a crossing railing's
  post on the corner about one run in two (the railing reaches 6 m from the zebra, into the
  corner: a corner-furniture question, not a deck one). Ramps' and cuttings' walls are left
  out of the collisions within a junction's corner (`_walls_of`): there they are a step a
  turning car sweeps over.

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
  on the surface; keeping `electrified=` in the bake; re-baking the other towns (Ashdod has
  a line).

## Handoff: lights, kerbs and paving, islands, quality, menus, performance (20 Nov 2026)

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
  takes `cell_m` and `range_begin`). **In the middle of**: which vertex-coloured kits make
  the 9.6 M batched vertices -- a debug-only tally in `_batch_add` ("batched by:
  function:line (n verts)") that `perf_dive` prints as "batched, by who"; the plan was to
  draw the biggest as multimeshes (one mesh, a transform each) instead of copying their
  vertices into the batches, then measure memory and draws again. Also open: 74 shader
  kinds for the warm-up (merging look-alike materials would shorten it); nodes up 3,000 from
  the parked cars' squares (watch the browser's culling cost).
- **Waiting on the user**: the test town's hillside roads lean (a finer height grid in
  tools/fake_city.py, or levelling roads in the game; another session owns the test town's
  terrain); stop / give-way signs at every junction (asked whether same-class junctions get
  one -- no answer yet). The Ashdod "grass patches" spot was never pinned down: islands and
  the ground colour went out without it.
- **Tests and tools added**: `hitches` + `hitch_parts.py` (frames over 250 ms by phase --
  only meaningful in a real browser), `top_at` (shots by map point, `CAR=` to put the car
  anywhere), `street_at` (by street name at its roundabouts), `perf_dive`, `deck_corner`,
  `islands`, `pave_overlap`, `picker`, `minimap_route`.

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
- **Tel Aviv's decks, what is left** (Nov 2026; `tests/decks.gd` at level 7). Short hops
  where ramps meet: Moses and Arvei Nahal's embankments (crests at the ramps' tops, the
  same kind as Bedford's Anderson Lake hop: `infer` has no vertical curve at a ramp's top
  yet), and a car-park service bridge at the south-west corner that ends at a building
  (autodrive noses it). 6 points of the HaShalom bridge's west ramp, 0.6-0.9 m under the
  street beside it, and 41 points where an inferred ramp's wall, a bank's foot or a
  parapet stands in a street's lanes (Ashdod 51, the test town 10: embankments running
  tight alongside other roads -- slip roads beside the Ayalon, Yitzhak Sadeh's ramp)
  (`tests/street_holes.gd`). Two branch ramps out of Lova Eliav's west
  end are too short to climb out at 10% and lie on the ground. A tunnel's tube is drawn
  whatever is over it, buildings included (Lova Eliav runs under HaKirya's blocks).
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
