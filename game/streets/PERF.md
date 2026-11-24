# streets -- performance: load time, frame time, stalls, memory, download

The place to start for anything about speed. It sums up and points into `DEV.md`, where the
details live. Keep this page short: put each new measurement in `DEV.md` (usually "Numbers to
compare against") and update the summary here in the same commit.

## The one rule about numbers

**The container's numbers are for ratios, not for players.** Headless runs and the
container's Chromium (SwiftShader, a software renderer) are about 3x slower on the CPU and
very much slower at drawing: their "warm-up" of 27-60 s says nothing about a phone's. The
real measure is **the user's own device**: the load line shown for 20 s after each load
("loaded in X s (+ page Y s): city file · start area · graphics (N shaders, X s
compiling)") and the perf view (P, or the fps button on the left; P twice for the map page
and "save log"). Ask for a screenshot of both. Check which build it is from (the build line over the
minimap) with `git merge-base --is-ancestor <fix> <commit>`.

## Where things stand (user's PC in a browser, build d9b49f2, 21 Nov 2026)

| | Givatayim | Tel Aviv |
|---|---|---|
| load (file · start area · graphics) | 2.8 s (0.4 · 0.8 · 1.6) | 3.6 s (0.9 · 1.3 · 1.4) |
| shaders at load | 137, 1.2 s compiling | 129, 1.1 s |
| frame, quality 2 | 29.0 ms = draw 16.1 + script 12.9 | 33.9 ms = 19.7 + 14.2 (night 27.1) |
| script, by part | building 5.8, people 2.7, traffic 2.5, minimap 0.9, follow 0.8 | building 4.0, traffic 3.6, people 3.4, minimap 1.2, follow 1.0 |
| physics ticks a frame | 1.7 | 2.0 |
| draws / triangles | 746 / 1.83 M | 769 / 1.87 M (night 800) |
| shaders compiled after the car | 5 (0.5 s) | 102 (6.6 s) by 2 min, 159 after night |
| background build of the rest | -- | ~11 min at 4-6 ms a frame |

Since that build: traffic and people tick on alternate ticks (people 16-17 -> 8-11 ms,
traffic 13-14 -> 8-10 ms per 8 ticks, measured in the container's browser); the far city
past `SEE_M` 900 m builds at 1.5 ms a frame; the time-of-day clicks compile 4-6 programs
instead of 30-44. **Not yet confirmed on the user's PC.**

**The cold load (22 Nov 2026, build 5928bd1, the desktop app's own browser pane on the
user's PC: RTX 3060, ANGLE on Direct3D 11, 1024x768).** That pane keeps no compiled shaders
between loads, so every load there is what a first visit -- or the first visit after a
publish that changed shader code -- costs. Givatayim, twice, the same both times:

| | load 1 | load 2 |
|---|---|---|
| loaded in | 64.9 s (+ page 0.5) | 73.1 s (+ page 1.2) |
| city file · start area · graphics | 0.5 · 1.1 · 63.3 | 0.5 · 5.8 · 66.8 |
| shaders at load, time in the compile calls | 143, 62.8 s | 143, 63.5 s |
| warm-up frames, ms | 3698, 15277, 7998, 9109, 5067, 8115, 10984, 364, 17, 2588, 11, 16 | about the same |
| shaders by ~2 min after the car | 212, 80 s in all | 212, 77 s |

**~0.44 s a shader, one after another**: Direct3D's shader compiler, which ANGLE feeds every
WebGL program to, is what the minute is (9 ms a shader once Chrome has it cached). About
70 more come after the car -- ~17 s of stalls in the first minutes. The start area's 5.8 s
on load 2 was the user working on the PC meanwhile (kerbs 2.1 s, parked 1.0, places 1.0).
The perf view a minute in: 13 fps, script 7.9 ms in 2.5 ticks (building 2.2, people 2.1,
traffic 1.6, follow 0.9) -- the script down from 12.9 on d9b49f2, the ticks taking turns
working -- drawing 57.6 ms, still shaders compiling (worst frame 1061 ms), 512 draws,
2.30 M triangles. This pane is a bench for the cold case, not for frame times.

Tel Aviv, the same pane, cold: **loaded in 92.4 s** (+ page 2.3): city file 1.1 · start
area 8.3 · graphics 83.0 (151 shaders, 75.5 s compiling). Then 77 more shaders in the next
~2 min of autodrive (228 in all, 98 s of compiling). Evening: 0 shaders, 127 ms at the
click. **Night: 13 shaders, 6.4 s, the slowest frame 7.1 s** -- the night click still
freezes a cold browser (the 4-6 programs measured in the container's browser were not
the whole story). The frame read 1 fps with the GPU idle: the app's window was behind
others and Chromium throttled it while the page still said "visible" -- the script's
split from that view, per physics tick: traffic 3.9, people 2.6, autodrive 1.8, following
1.65 ms, ~11 ms a tick (8 ticks a frame, the cap), against Givatayim's ~3.2 -- to be
checked natively before it is believed. **Checked, not real**: `tests/sim_cost.gd`
natively on the user's PC (Godot 4.7.2 headless, `--fixed-fps 60`, 40 s of autodrive, the
city all built, 22 Nov): Givatayim script 3.3-3.8 ms a tick (people 1.0-1.4, traffic 0.8,
autodrive 0.3-0.6, following 0.4, minimap 0.3-0.4), 4.7 ms a tick in all; Tel Aviv 3.9 ms
(people 1.0-1.2, traffic 0.9-1.0, minimap 0.7-0.9, following 0.4-0.5, autodrive 0.3-0.5),
5.2 in all. The two cities cost the same a tick; the browser's Givatayim (3.2 ms a tick in
wasm) is close to native. Tel Aviv's only extra is the minimap (twice Givatayim's). The 11
ms a tick was the throttled window's frames, each running eight ticks. **Hidden or covered, the pane's frames come one a
second**, and every `_pause` in the loading waits for a frame: a stage reading a round
1000 or 2000 ms is that, not work (Tel Aviv's start area 8.3 s here).

Quality 0 bought the user's PC nothing (25-27 fps at every level): the levels change pixels
and shadow reach, not draws or the script, and a frame held back by the script on the
browser's one thread is helped by none of them.

## What has been done (and where it is written)

All in `DEV.md`; search for the bold lead-in.

- **Load**: near-first (only the 1-2 squares the first view needs before the car; the rest
  while driving, `_catch_up` then `BUILD_US`, `BUILD_FAR_US` past `SEE_M`) -- "building the
  world, near-first". The decks baked per build by `prepublish.gd` (Tel Aviv's file 3.9 ->
  1.5 s) -- "prepublish". Far shadows after the car, the other sun's drawn ahead -- "far
  shadows after the car". The load bar estimated from this device's last load -- "loading".
- **Download**: the pack split, so a code-only publish costs ~4 MB not ~40; the service
  worker keeps `index.wasm` -- root `CLAUDE.md`, "The web build".
- **Shaders**: counted per code, not per material; 205 -> fewer programs (flags/ads one
  shader, one fence shader...); sun shadows kept at every quality level and at night
  (switching them off recompiled everything); the evening haze a trace by day --
  "shaders a browser compiles", "render quality", "The warm-up's steps by shader code".
- **The cold load's minute, 22 Nov 2026** (`LIGHT_STRIP_JS` in streets.gd, its comment says
  why): ~85% of it was two lit programs per material that Godot compiles when the material
  is set up and never draws with, with omni, spot and area light code on. The game has only
  the sun, so those three are defined off in exactly those sources. Same build, same cold
  browser: Givatayim's graphics 63 -> 22 s (the compile calls 63 -> 15.5 s), every program
  by the car 80 -> 23 s. What a cold load compiles now is mostly what is drawn: the sun's
  additive pass, ~0.38 s a program on this GPU (39 of them, ~15 s), and the depth passes.
  **Live, build 2026-11-22 00:12 (74671c6), cold, the user's PC: Givatayim loaded in 27.6 s
  (+ page 2.3): city file 0.5 · start area 6.0 · graphics 21.0 (143 shaders, 15.0 s
  compiling)**; 204 programs by the car in 19 s. Steps reading a round ~1000 ms there were
  the pane throttled, so a player in front of the screen waits less.
  **Then the never-drawn programs swapped for an empty placeholder** (they still cost 7.9 s
  of the 21 s left, 42 programs at ~190 ms even stripped): a local export, cold, Givatayim
  **18.4 s (+ page 5.0): city file 0.5 · start area 6.9 · graphics 10.9 (143 shaders, 6.2 s
  compiling)**, 220 programs by 30 s of autodrive in 13.6 s; the night click 7 programs,
  ~0.2 s (was 13 and a 7 s freeze in Tel Aviv). `window.__lstrip.used` -- draws made with a
  placeholder -- 0 through the load, driving and night. The pane was throttled for much of
  it (steps of ~1000 ms), so the real wait is shorter still.
- **Parallel compiling, measured, not built**: `KHR_parallel_shader_compile` is there (16
  threads): 24 of the heaviest real programs 12.2 s one at a time, 3.7 s all at once. But
  Godot asks each program's status as soon as it links it, which makes it serial, and a
  program compiled in another context is not reused (the same source in a second context
  cost the same: no cross-context cache in that browser). Getting it would mean knowing the
  sources before Godot asks -- a list made at publish (a headless browser in CI) -- and
  redirecting Godot's program objects to ones linked ahead in its own context. What is left
  to win: ~13 s of compiling by the car on this PC (sun pass 9.5 s, depth 2.7).
  How it was found: capture each program's sources and link time from the page (wrap
  `shaderSource`, `attachShader`, `linkProgram`), group by `#define`s, then recompile one
  captured program with a define changed in a throwaway WebGL2 context, a unique `#define`
  first so no cache answers.
- **Frame**: parked cars in 100 m squares with a far shape; heavy kits kept as multimeshes
  (-131 MB); merged meshes indexed while driving (445 -> 365 MB video memory); traffic and
  people on alternate ticks -- "Performance" in the 20 Nov handoff, "traffic and people
  take turns".
- **Seeing it**: the profiler (`_p("part")`), hitch lines, `GL_COUNT_JS` shader counting,
  the load line -- "where a frame's time goes", "a browser's shader compiling, counted".

## The tools

| Test | What it measures | Notes |
|---|---|---|
| `tests/web_load.js` | a level in the container's Chromium, phase by phase | `TIMES=` clicks time of day, `PLAY=n` prints the profiler |
| `tests/web_shaders.js` | every WebGL program, before/during/after the warm-up | `TIMES=`, `BOT=`, `DUMP=` writes sources to diff |
| `tests/start_soon.gd` | time to the car, headless | `STREETS_NO_BAKED=1` for without the bake |
| `tests/load_stages.gd` | the city file part by part | |
| `tests/perf_dive.gd` | the whole frame: triangles, draws, memory, by who | `STREETS_BUILD_ALL=0` to see the indexed meshes |
| `tests/frame_cost.gd`, `tests/draws.gd` | the start view's triangles and draws | |
| `tests/warm_census.gd`, `tests/shader_kinds.gd` | shader codes and who uses them | |
| `tests/hitches.gd` | frames over 250 ms / 1 s | software renderer: shows the script only |
| `tests/sim_cost.gd`, `tests/traffic_motion.gd` | the simulation's cost per tick | `STREETS_WORLD_SPLIT=0` to compare |
| `tests/index_gain.gd` | what indexing the merged meshes saves | |
| `tests/quality_ladder.gd` | the quality ladder's rule, made-up frame times | and its gate: it runs while the city builds in the background |
| `tests/perf_view.gd` | the perf view readable: nothing over it or through it | shot `perf_view.png` |

## Open problems, biggest first

1. **The cold load is still ~6 s of shader compiling at load and ~13 s by the car** on a
   Windows browser (was a minute before `LIGHT_STRIP_JS`) -- now mostly the sun's additive
   pass, ~0.25 s a program (39 of them). Next: fewer shader codes (each is ~2 additive
   programs), or parallel compiling (measured 3.3x, see above; a big job).
2. **The script on the browser's one thread** -- 7.9 ms on 5928bd1 (12.9 on d9b49f2), 2.5
   ticks a frame; ~3.5-4 ms a tick natively in both Givatayim and Tel Aviv. Building is
   the biggest part while the rest of the city goes up; the minimap is Tel Aviv's 0.7-0.9.
3. **Draws** -- 500-800. A work laptop (Intel graphics, 22 Nov, below) spent 68.5 ms a frame
   drawing them -- under 15 fps with no script at all; the drawing half there scales with
   the CPU, so fewer draws, not fewer pixels. Since 22 Nov levels 1 and 0 lower them (draw
   ranges x0.75 / x0.5, the haze thickened to match): quality 0 is 24-29% fewer draws than 2
   (test town 616 -> 467, Givatayim 575 -> 410); before, it was 3%. What is left is mostly
   near the car: kits (135 of the test town's 614), trees (84), batches (56).
4. **The city file** -- Tel Aviv 1.5 s of it still unbaked (widths, buildings cut, divided
   roads: ~1 s).
5. **Video memory** -- Tel Aviv 365 MB; phones.
6. **No automatic check catches a performance regression** -- the numbers are only read when
   someone runs a test by hand.

## Next steps, scored (22 Nov 2026)

Effort: 1 = an hour, 5 = days. Gain: 1 = barely felt, 5 = every player feels it. Risk: 1 =
can't break the game, 5 = can break it on some devices. Ordered by the pick.

| # | Step | Effort | Gain | Risk | Why |
|---|---|---|---|---|---|
| 1 | Check for programs compiled and never drawn: `web_shaders.js` fails on a lit program with every light type on, or `__lstrip.used` > 0 | 1 | 3 | 1 | guards today's 10x; a Godot upgrade or a new lamp would bring the minute back silently |
| 2 | Phones: the load line and perf view from a phone, cold, after a publish | 1 | 4 | 1 | everything so far is a Windows PC; phones compile differently and may be the real slow case |
| 3 | Fewer shader codes: merge the ones only one or two things use (each costs ~2 sun-pass programs, ~0.25 s cold) | 3 | 3 | 2 | the sun pass is the biggest cold cost left (9.5 s by the car) |
| 4 | Minimap drawn less often in Tel Aviv (0.7-0.9 ms a tick) | 1 | 1 | 1 | cheap, small |
| 5 | Tel Aviv's frame measured properly (panel visible, or `perf_dive` natively) | 2 | 2 | 1 | the 1 fps reading was a throttled window; we don't know the real number |
| 6 | Draws: quality levels that drop shadow casters and far detail | 4 | 4 | 3 | 500-800 draws and no level lowers them; the quality ladder can't help a weak device |
| 7 | Bake more of the city file at publish (widths, buildings cut, divided roads) | 3 | 2 | 2 | ~1 s of Tel Aviv's load; already a pattern (`prepublish.gd`) |
| 8 | Parallel compiling (source list made at publish + redirecting Godot's programs) | 5 | 3 | 4 | measured 3.3x on the remaining compile, but deep in the page's GL layer |

**Step 1 done (22 Nov 2026):** `tests/web_shaders.js` ends with two CHECK lines -- no default
lit program reached the driver, nothing drawn with a placeholder -- and exits 1 on a FAIL.
The load line says it too: "(143 shaders, 10.0 s compiling, 96 skipped)", and "PLACEHOLDER
DRAWN n" if the assumption ever breaks (96: the 42 lit defaults and their depth-pass
defaults, also never drawn). Not run here (no Playwright on the user's PC); the cloud
containers have it.

**Step 2, how to measure on a phone** (the user plays on the same phone they steer the
sessions from -- the Claude app open beside the game, screenshots taken mid-drive -- so the
numbers are a real player's, with a little noise from those):
1. after a publish, open the site; if it says "new version ready", tap it (that is the cold
   case for anything whose shaders changed). The build line over the minimap names the build:
   check it holds the fix being tested (`git merge-base --is-ancestor <fix> <commit>`);
2. pick a city, turn autodrive on, tap the fps button on the left (the perf view);
3. screenshot right after a stutter, and once after a minute of plain driving;
4. send them with what was happening (a turn, night, the first minute).
What to read: "average ... drawing ... script ... in N ticks" (the frame's two halves), the
hitch lines ("building (step) ms" names the build step; a big "rest" is the GPU or a shader),
"N draws", "shaders compiled since the car". Put the numbers under "A phone" below.

## A phone (22 Nov 2026): Adreno 740 (a 2023 flagship), Chrome, build 22 Nov 03:27 Israel

Six perf-view screenshots from the user, Tel Aviv (Kaplan) and another city (Sderot Herzl),
autodrive on, quality 2.

- **Loading is fine**: 8.5-9.5 s; city file 2.4 · start area 3.1-3.4 · graphics 3.0-3.7
  (129-135 shaders, 2.0-2.5 s compiling). Shaders compiled after the car: 54-80, 1.9-3.3 s.
- **Driving is not: 5-18 fps.** The frames, average ms = drawing + script in N ticks:
  113 = 42 + 71 in 6.2 (people 33, traffic 16) · 90 = 45 + 45 in 5.0 · 144 = 70 + 74 in 3.7
  (building 48) · 76 = 42 + 34 in 4.1 · 55 = 25 + 29 in 3.2 · 78 = 33 + 46 in 4.7 (building
  18). 500-680 draws, 1.4-1.8 M triangles.
- **The spiral**: the script costs ~8-11 ms a physics tick on this phone (native PC ~3.5-4),
  and at 60 ticks a second a 100 ms frame has to run ~6 of them -- 60-70 ms of script -- which
  keeps the next frame slow. The script, not the GPU, holds the phone under 20 fps.
- **The worst stutters are the background build**: 2044 ms = building 1032 + rest 969, and
  2250 ms = building 1275 + rest 934. A builder runs ~1 s between `_over()` checks on the
  phone (the budget is 6 ms a frame, `BUILD_US`), and the "rest" that follows is likely the
  new square's meshes going to the GPU (and their shaders). "building the city" stood at 0-5%
  after minutes: the build is eating frames for a long time to come.
- Other hitches of 120-360 ms: people 69-93 ms in one frame (Kaplan), traffic 28, and "rest"
  of 200-300 ms (a shader compiled on first sight, or uploads).

What to do, by expected gain on this phone:
1. **Background build in small pieces on slow devices** -- find the steps that run ~1 s
   between `_over()` checks (natively ~0.3-0.4 s) and split them; and let `_build_us` follow
   the frame (none while a frame is over ~50 ms, except to catch up the squares in view).
   Removes the 1-2 s freezes.
2. **Fewer ticks when frames are slow** -- the physics rate (60) halved on a device whose
   frames stay over ~40 ms (`Engine.physics_ticks_per_second` 30; the car and camera are
   already drawn between ticks, `_frame`), or people/traffic further from the car ticked
   less often. Breaks the spiral: ~half the script time.
3. **People near Kaplan** (33 ms a frame, 69-93 in one) -- how many are ticked, and whether
   the far ones can tick every few frames.
4. **Shaders after the car** (54-80 on the phone) into the warm-up.
5. **Draws** (500-680): the quality ladder cannot help a script-bound frame.

**Fix A, first part (22 Nov 2026).** `tests/build_spans.gd` (STREETS_SPANS=1, a debug run with
the real renderer -- headless hides mesh uploads -- on Ashdod, build in the background):
- before: a stretch of up to 50 ms with no budget check, 15 times in 90 s, from `_build_ground`
  to `_build_buildings` -- decks, rails, marks, beach, works and places back to back, and in
  it `places.gd`'s room search for each shelter/kindergarten (Ashdod has many);
- after (every step of `_build_tile` behind `_build_step`, `places.gd` paced per item): no
  stretch over 20 ms while driving.
- The hitch line now names the step: "building (places) 48" -- and "between squares" -- so a
  phone screenshot says which step froze it (`_bstep_slow`, set in `_pause`).
- Left, and the likely phone freezes: at 8 s after the car "rest 842 ms" on the desktop
  (`FAR_AHEAD_S`: the evening's far shadows drawn ahead -- GPU work in one frame), and
  "building 82-86 ms" twice (far-shadow chunks). The phone's perf view: "far shadows: work
  4.7-5.2 s". Next: the far shadows in smaller pieces, or not drawn ahead on slow devices.

**Is 14-18 fps expected? (22 Nov 2026, the same phone, build 7b520f6 -- before 072cced's
step checks)** No: it is what the current settings cost, not what the phone can do. A frame
of 58-81 ms is two halves of about the same size, and both need halving for ~30 fps:
- drawing 30-45 ms: 530-780 draws and 1.6-2.2 M triangles -- for a phone's WebGL ~250 draws
  and ~1 M triangles is a comfortable budget, and no quality level lowers either today;
- script 28-36 ms in 3.5-4.4 ticks (people 7-11, traffic 6-9, building 4-10, minimap 3).
Target: 30 fps on a 2023 flagship in a browser; 60 is not realistic for a whole city in WebGL
on one thread. Freezes still in that build: building 692 + rest 634, building 1304 + rest
941 (before the step checks; the next screenshots name the step).

**Handoff (22 Nov 2026, end of a long session).** Work branch `streets-perf` (worktree
`C:\Users\evgbo\GP-perf`, merged into main as it goes). Chosen next, for the phone:
1. Script half: tick far people and far traffic less often (every 2nd-4th tick by distance
   from the car; the car and near ones every tick -- no change to how driving feels), then,
   if not enough, the physics rate 60 -> 30 on slow devices (the car is drawn between ticks
   already; check the exam's numbers before and after: `tests/exam.gd`).
2. Drawing half: quality levels that cut draws (shadow casters, far parked cars, furniture,
   trees) so the ladder can help a phone; target ~250 draws, ~1 M triangles.
3. Far shadows drawn ahead (`FAR_AHEAD_S`): one frame of GPU work, 0.85 s on a desktop.
Measure natively with `tests/sim_cost.gd` (script per tick) and `tests/build_spans.gd`;
the phone's own perf view (hitch lines now name the build step) is the real measure.

**Slow frames (22 Nov 2026, after the phone's 04:13 build: 13-15 fps, script 30-51 ms in
3.8-5.1 ticks, of it building 16-21 ms -- the catch-up's 16 ms budget every frame while the
car keeps reaching bare squares -- people ~10, traffic + following ~14; even the made-up
town at 13-15 fps, so not the city's size).** `_slow_watch`: frame time smoothed over ~0.5 s,
on over 40 ms, off under 28 ms; then traffic and people tick every 4th tick with four times
the time (was every 2nd), and the catch-up builds at 8 ms a frame (CATCH_UP_US / 2). The car,
camera and autodrive tick every tick. `STREETS_SLOW=1/0` forces it. Natively, Tel Aviv,
`sim_cost` 40 s: script 2.7-3.2 -> 2.3-2.6 ms a tick (people 0.8 -> 0.4-0.6, traffic
0.6-0.9 -> 0.4-0.5, following 0.3-0.4 -> 0.2-0.3); playtest PASS with it forced. Expected on
the phone: ~24 -> ~14 ms of people and traffic a frame and ~8 ms less building: ~80 -> ~62 ms,
12-13 -> ~16 fps. The rest is the drawing half (next). The minimap (3-3.5 ms on the phone)
left alone: drawn every other frame at ~15 fps its heading-up turn would step visibly.

**After slow frames, the phone (build 04:23 Israel, 27f19a7, Tel Aviv at Kaplan):** 12-19 fps,
51-101 ms a frame; people 4-6 ms (was ~10), building 6-15 (was 16-21); traffic about the same
(3.5-11: each of its ticks costs what it did, there are fewer). Named build hitches small
(decks 58-84, pois 47, signals 42 ms). The two freezes left were unnamed: building 641 + rest
677, building 1044 + rest 1026 -- the far shadows (their own pacing, no `_build_step`), then
the picture's readback. Fixed (`_build_far_shadows`): the canvas commands for every road and
area paced like the rest (they ran at once), and the picture at 1024 px instead of 2048 on a
phone's browser or in slow-frames mode (`_fs_px`: a quarter of the drawing, readback,
conversion and mipmaps). Desktop, Ashdod, forced slow: the far shadows' worst frame 82-86 +
37-70 ms -> 48 and 56 ms. (The "rest ~1 s" at ~8 s on a desktop run is the first frame after
loading, before the far shadows start: part of the load, not a stutter while driving.)

**30 ticks a second on slow frames (23 Nov 2026).** In slow-frames mode traffic and people
already ticked 15 times a second, but autodrive, the car, the lights and the rules still ran
all 60 ticks -- ~1 ms of every tick natively (autodrive 0.4-0.6, car 0.2), 4-5 ticks of a
phone's frame. Now `_slow_rate()` sets `Engine.physics_ticks_per_second` to 30 while slow
frames are on (`STREETS_SLOW_HZ`, 60 for none), the world split counted in 60-a-second ticks
(`per`) so traffic and people keep 15 a second and traffic's "decide every n ticks" its
pace; 60 put back off slow frames, in sped-up tests and in `_exit_tree` (the engine's, every
game's). The one per-tick constant in the car (`_vy` eased 0.5 a tick) made time-based.
Natively, Ashdod, slow forced, `sim_cost` 40 s: 299-309 -> 232 ms a game second (-24%);
autodrive 0.55 -> 0.25 ms a frame, car 0.17 -> 0.08, traffic and people unchanged. The exam
(test town, slow forced, 3 x 60 s, seed 7): checks 9 at 60 Hz, 8 at 30, the same Dimyon
junction's overlaps in both; one "autodrive: hit deep" at 30 was the test town's "deep water"
across a road at (-524, 430), which stops the car at 60 Hz too (`tests/deep_water_road.gd`,
open). Playtest smart 30 s, slow forced: PASS. Expected on the phone: ~half of the 4-6 ms the
car and autodrive cost a frame, and the engine's own per-tick work; to be read from the phone's
perf view ("in N ticks" should read ~2 instead of ~4).
Not done (measured, small): far walkers ticked less often -- the people's tick is ~40 us a
walker spread over ten steps (re-placing 0.2, apart and push 0.17, walking beside 0.1, pose
0.1 ms a frame...), nothing to cut in one place.

## The quality bar lowered to 28 fps (24 Nov 2026)

The user: every browser, even a local one on the PC (Monaco), quickly dropped its quality. The
ladder stepped down under 45 fps (and counted every frame slower than 33 ms as a stutter), so a
PC browser at 25-30 fell to 0 within ~10 s. Now: down under `FPS_LOW` 28, up at `FPS_FULL` 40,
a stutter is a frame over 50 ms (`LONG_FRAME`). `quality_ladder` checks a 25-35 fps browser keeps
level 2 for 2 min. A phone at 15-22 still steps down. The fps button shows the level ("30 fps 2/3").

## A work laptop (22 Nov 2026): Intel graphics (0x7D41), ANGLE on Direct3D 11, a browser, build 2ddd8b3

One perf-view screenshot, mailed: Givatayim at Katznelson, autodrive on, 317 s into the drive.
- **7 fps, worst 319 ms, quality 2.** Average 135.3 ms = drawing and engine 68.5 + script 66.8 in
  **7.9 ticks** (the engine's cap is 8): people 22.4, traffic 21.5 (of it deciding, "traffic:
  follow", 12.5), building 8.1, car 6.0. 588 draws, 2.06 M triangles. Hitches 240-319 ms, each
  "rest" 187-271 (the drawing) plus the usual parts. "building the city 8%" five minutes in.
- **Loading was fine**: start area 3.1 · graphics 2.6 (127 shaders, 1.5 s compiling, 328
  skipped).
- **About 4x the user's home PC in both halves** (Givatayim there: drawing 16.1 ms; script 3.2
  ms a tick against 8.5 here; natively in a cloud container 1.7 ms a tick with slow frames
  forced): the drawing half scales like the script, so the frame is the CPU's in that
  browser, not the graphics chip's.
- **The ticks**: at 60 a second the script's work per real second is fixed, so frame =
  drawing / (1 - script's share) = 68.5 / 0.51 = ~135 ms. The drawing alone caps it at ~14 fps.
- **Three defects found**, fixed in the next build:
  1. *The quality ladder never ran.* `_watch_fps` skipped every frame while `_bg_build` was
     on -- the whole background build, at 8% after 5 minutes there (most of an hour). It
     sat at 2 for the drive. Now only the catch-up round the car is left out
     (`_bg_build and _catch_up`); `tests/quality_ladder.gd` has two CHECK lines for it
     (`_ladder_native` lets the test call the web-only gate). The phone's screenshots (quality
     2 throughout, the build at 0-5% for minutes) were the same bug.
  2. *Slow frames left traffic deciding at full rate.* `ceil(3 / ticks_per)` with ticks_per 4
     is 1: every traffic tick, ~15 a second per near car, the same as at full speed. Now
     doubled in slow mode (near every 2nd traffic tick, ~7.5 a second; far every 3rd).
     The exam (Givatayim, slow frames forced, EXAM_SEED=7, 4 x 75 s): checks 24 before, 21
     after; cars overlapping 6 and 6. One new "stuck 8 s+" after: autodrive behind a bus
     behind a sedan at a red (the exam's queue rule did not follow the chain through the
     bus) -- a queue, not a decision missed. Natively deciding is 0.1-0.2 of 1.7 ms a tick.
  3. *The perf view was half unreadable*: its lines ran over the build line and under the
     minimap. Now on a dark backing above the map, the build line its first line
     (`tests/perf_view.gd`).
- **People, natively, by step** (Givatayim, slow frames, 1.69 ms a people tick, 24 walkers,
  ~43 people listed): push-outs from cars and posts 0.40, re-placing a walker gone far 0.27,
  keeping clear of the others (the pairwise loop) 0.25, facing and the dog or pram 0.15, the
  lane plan 0.13, `_people_apart` 0.11, room to the side 0.10, the rest under 0.08 each. No
  single hot spot: halving it means doing less for the people far off.
- Expected from the fixes on that laptop: modest -- ~6 ms of deciding off each frame, and
  whatever the ladder's levels buy its drawing (on the home PC they bought nothing; this
  chip may differ). Playable there needs the drawing half cut: fewer draws on a weak machine.

**The same laptop on the fixed build (a733fcd, 22 Nov 11:56-11:58), two screenshots:**
- *Tel Aviv*, Givat HaTahmoshet, racer, the "more" drawer open: **quality 0** -- the ladder
  ran. 7 fps, 167.6 ms = drawing 118.2 + script 49.4 in 8.0 ticks (traffic 14.0, people 11.7,
  building 8.8, deciding 4.1 -- was 12.5 in Givatayim, autodrive 3.8); 717 draws, 1.25 M
  triangles. The hitch lines a minute in said "usual 66" (15 fps). **Worst frame 13687 ms**,
  and **107 shaders compiled since the car, 13.9 s** (Givatayim's first screenshot: 54, 1.3 s):
  ~130 ms a program, the uncached rate -- the first time this laptop's browser had seen the
  levels below 2.
- *Delft*, Binnenwatersloot, 193 s in, building 9%: **quality 2**, 10 fps, 112.3 ms = drawing
  86.0 + script 26.3 in 6.4 ticks (building 6.5, people 5.2, traffic 4.5, minimap 4.4,
  autodrive 2.2); 818 draws, 1.57 M triangles. Shaders since the car 76, 1.0 s (cached).
- Script per tick: 4.1 (Delft) and 6.2 ms (Tel Aviv), against 8.5 before -- deciding halved
  and slow frames. **The drawing is now most of the frame (77% in Delft)**, 0.1-0.17 ms a
  draw: CPU work per draw (wasm and ANGLE), not pixels.
- Whether the levels help this laptop the two can't say (one at 0, one back at 2, likely after
  "lower bought nothing"). The perf view now has a "quality ladder:" line -- each step with
  the fps it measured -- so the next screenshot says.
- **A quality step compiles nothing** (`tests/web_shaders.js` QWALK=30, the test town, idle,
  the container's Chromium): 2 -> 1 -> 0 -> 1 -> 2 -> 3 -> 2, 0 programs at each step but the
  last (2). The ladder is safe to run anywhere. The 13.7 s frame was Tel Aviv's programs that
  come only after the car (~100 there, as on the home PC: 102), uncached in that browser for
  this build, ~130 ms each -- open problem "shaders after the car". Even the test town, the
  car standing, compiled 26 programs 21-23 s after the warm-up: what they are is the next
  thing to find (list the after-the-warm-up programs by material in web_shaders.js).
- The same run: `CHECK never-drawn lit programs compiled: 4 (want 0) FAIL` on the test town --
  likely the check's first run in a browser (written on the home PC, which has no
  Playwright). Not looked into yet; 4 programs, ~0.5-1.5 s on a cold Windows browser.

**Levels that cut draws (22 Nov 2026).** The user: 10-20 fps after loading in the test town on
that laptop, "fps is the big blocker". `tests/draw_budget.gd` at the test town's start, quality
2, 614 draws: every range of 150 m+ x0.7 -58, x0.5 -130, x0.35 -187; old quality 0 -21; the
depth pre-pass setting switched at runtime -2 (no effect); the sun's shadows off -72 (and a
recompile of everything: not a level); by kind, hidden: kits -135 (1144 multimeshes), trees
-84, batches -56, people -35, other meshes -38, cars -31, shadows only from walls/roofs/
batches -59. So levels 1 and 0 now scale ranges (x0.75, x0.5) and thicken the haze by as
much: quality 0 616 -> 467 (test town), 575 -> 410 (Givatayim), and `tests/web_shaders.js`
QWALK confirms a step compiles nothing. The ladder keeps the level that runs best, so a
machine whose draws hold it back (the laptop) should now settle at 0; one held back by
pixels or the script loses nothing. Expected on that laptop, if a draw is ~0.1 ms: 15-20 ms
off its 70-86 ms of drawing. **Not yet confirmed on the laptop.**

**The far build on a slow machine (22 Nov 2026).** The user, the same laptop: "the loading of
tel aviv ... in autodrive really takes forever (i am on 30% after few minutes of driving)".
`tests/build_pace.gd` drives Tel Aviv with `--fixed-fps 12` (each frame gets that frame's
budget, as the laptop's did; native GDScript here is about the laptop's wasm): 22% (33 of 150
squares) after 240 s, everything within 900 m up at 179 s, the car never in a bare square; at
60 fps all 150 at 219 s. The "30%" was the whole city out to 2-3 km, at 1.5 ms a frame -- ~25
minutes at 12 fps, every millisecond (and the build's overruns) taken from frames with none
to spare, for squares out of sight. Now sight scales with the level's reach (450 m at quality
0), and on slow frames the far squares wait until the car nears them (`_far_hold`); the HUD
line says only what is left within sight, the perf view the whole city.


**The check's "4 (want 0)" explained (22 Nov 2026, local export of 3ce14ec, the home PC's
pane, hooked 153 ms into the page).** Before any game runs -- engine start, the main menu --
Godot compiles its own default material's four variants: the lit base pass plain and
instanced (1.4 s each on a cold Windows browser: 2.8 s, every cold visit) and the two depth
passes (12-15 ms). No uniforms, so no game's: the engine's. LIGHT_STRIP_JS is installed by
streets at `_ready`, too late for them. Reading rasterizer_scene_gles3.cpp again: a draw's
base pass always sets DISABLE_LIGHTMAP (or USE_LIGHTMAP / USE_LIGHTMAP_CAPTURE), so its
specialization never equals the default mask -- the default lit programs are never drawn in
ANY game, lights or not. The placeholder could therefore live in the page itself, before
the engine starts (`tools/publish_web.sh` patches index.html already), for every game: -2.8 s
on a cold visit here. Kit-wide, so asked first.

**Kit-wide since 22 Nov 2026 (the user: "yes, kit-wide").** `tools/publish_web.sh` puts the
placeholder in `index.html` before the engine starts; streets' own LIGHT_STRIP_JS finds
`window.__lstrip` and stays out. Local export, the home PC's pane, cold: the engine's start
(the main menu) 21 programs in 5 ms of linking (was ~2.85 s: the default material's two lit
programs, 1.4 s each); the test town loads and draws as before, `__lstrip` 116 skipped, 0
drawn with. `web_shaders.js`'s never-drawn check should now read 0 from the page's start.

**Shaders after the car (22 Nov 2026).** A cold browser on the home PC, Tel Aviv, ~90 s of
autodrive after the warm-up, every program linked recorded by material and switches: 59
programs, 11.5 s, and 23 of them -- 10.5 s, the walls 2.2 s, the ground tone 1.65, the cars
1.0 each -- the sun's pass with `USE_SUN_SCATTER`. None of the warm-up's had it: the haze
(fog on, its sun glow, the tone curve) was set by `_retint_city()`, which first ran AFTER the
warm-up, so the warm-up compiled every shader for a scene without haze and the drive
compiled them again. Now `_retint_city()` runs once before `_warm_up()` too. Same browser,
same city: after the car 59 programs / 11.5 s -> 35 / 1.5 s; the warm-up 156 -> 180
programs and the load no longer (graphics 13.0 s, 6.3 s compiling; the PC was busy). What is
left after the car: the traffic cars' shader (`m_night, m_plate_*`: 0.53 s + its depth passes
0.1 s -- the cars spawn after the warm-up), then programs of 100-200 ms.

**Parallel compiling, tried (22 Nov 2026, `tests/parallel_trial.js`, a local export, the home
PC's pane, cold every load).** Load 1 recorded the 243 programs Givatayim links (to 40 s of
autodrive); load 2 linked all of them at once on the engine's first link, in its own context,
with `KHR_parallel_shader_compile` (125 ms to issue them), and handed the engine the ready
program whenever it linked the same sources: 207 hits, 0 misses, 0 drawn with a placeholder.
Givatayim's graphics 14.5 s -> 9.5 s, **the compile calls at load 7.2 s -> 0.5 s**, and no
programs left to compile after the car (the PC was busy: the city file 5.5-7.5 s; compare
the compile column). A first try linked them in the loader's throwaway WebGL-test context
and missed every one. What a real build would need: (1) the list made at publish (a headless
browser driving each city in the workflow) -- and its sources must be byte for byte what the
player's browser gets, unproven across GPUs (Godot writes limits into its GLSL: MAX_* from
the device?); (2) shipping it: 243 programs are 29.7 MB raw, 6.5 MB gzipped (gzip's window is
smaller than one shader), 486 distinct sources sharing most lines -- a line dictionary or
brotli should be well under 1 MB, not measured; (3) the redirect is page-only (index.html),
no engine change. Worth it only for first visits and after shader-changing publishes on
Windows browsers, where today's two fixes already took most of the cost.
**Decision (the user, 22 Nov 2026): stop at the trial.** Parallel compiling is parked; pick it
up only if first visits on Windows browsers become the complaint again. The first thing then:
compare a container capture's sources (`web_shaders.js` DUMP=) with a real browser's,
byte for byte -- if Godot's GLSL differs by device, the whole approach fails.
