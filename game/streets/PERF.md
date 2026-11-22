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
compiling)") and the perf view (P, or tap the fps text; twice for the map page and "save
log"). Ask for a screenshot of both. Check which build it is from (the build line over the
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
| `tests/quality_ladder.gd` | the quality ladder's rule, made-up frame times | |

## Open problems, biggest first

1. **The cold load is still ~6 s of shader compiling at load and ~13 s by the car** on a
   Windows browser (was a minute before `LIGHT_STRIP_JS`) -- now mostly the sun's additive
   pass, ~0.25 s a program (39 of them). Next: fewer shader codes (each is ~2 additive
   programs), or parallel compiling (measured 3.3x, see above; a big job).
2. **The script on the browser's one thread** -- 7.9 ms on 5928bd1 (12.9 on d9b49f2), 2.5
   ticks a frame; ~3.5-4 ms a tick natively in both Givatayim and Tel Aviv. Building is
   the biggest part while the rest of the city goes up; the minimap is Tel Aviv's 0.7-0.9.
3. **Draws** -- 500-800, and no quality level lowers them.
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

**Step 2, how to measure on a phone:** after a publish, open the site on the phone (if it
says "new version ready", tap it -- that is the cold case for anything whose shaders
changed); pick a city; screenshot the line under the map within 8 s of the car appearing
("loaded in ... (N shaders, X s compiling, M skipped)"); open "more" > "perf view" and
screenshot it after a minute of driving. Note the phone's model and browser. Put the numbers
under "Where things stand".

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
