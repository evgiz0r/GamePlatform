# Effort: the kit

How long each change took, in minutes, from the Claude Code sessions that made it (`tools/effort.py`, which says how it is counted): **agent** thinking and writing, **runs** the tests, engine and git it waited on, **you** between its reply and your next message, **active** the three together. **away** is left out: gaps over 10 minutes, and the rest of any step past its cap. **lines** added and removed and **files** touched, leaving out generated files (baked data, the web build, imports); **steps** the times the model was called, **tools** its tool calls, **engine runs** those that ran the engine (a test, a playtest, a check), **tokens out** what it wrote (thinking included). Newest first; rows are kept once written.

| date (UTC) | commit | change | agent | runs | you | active | away | lines | files | steps | tools | engine runs | tokens out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-24 09:20 | 0ec6540 | street points workflow: each town committed as it comes (busy servers: 5-15 min a town) | 0.6 | 24 | 0.0 | **25** | 0.0 | +12 -17 | 1 | 13 | 15 | 0 | 3.5k |
| 2026-11-24 08:33 | a925e47 | tools: osm_city.py --street-points (OSM's post boxes, drinking taps, speed bumps into a baked city file) an... | 0.9 | 0.9 | 0.0 | **1.9** | 0.0 | +121 -0 | 2 | 10 | 13 | 1 | 6.4k |
| 2026-11-22 16:34 | 4af4799 | streets racer: no longer passive -- bends round a car kept (densified from the car on: the plan was remade ... | 7.4 | 30 | 0.0 | **37** | 55 | +0 -0 | 0 | 50 | 53 | 5 | 39.7k |
| 2026-11-22 16:07 | 61d9c5c | effort: rows for the latest commits | 0.3 | 2.3 | 0.0 | **2.6** | 0.0 | +0 -0 | 0 | 4 | 4 | 4 | 1.7k |
| 2026-11-22 16:06 | c9aafb8 | streets: Monaco (level 41) baked but not ready; a level's "trees" key; ground held under held water | 4.4 | 4.5 | 0.0 | **8.9** | 33 | +0 -0 | 0 | 27 | 27 | 4 | 24.3k |
| 2026-11-22 16:04 | e56c780 | streets: a map button over the minimap -- the city from above, paused, to look round; the camera button is ... | 18 | 1.9 | 0.0 | **20** | 89 | +76 -24 | 4 | 25 | 28 | 4 | 14.3k |
| 2026-11-22 15:58 | 40b9f0a | streets notes: parallel compiling parked at the trial (the user) | 0.8 | 0.2 | 0.0 | **1.0** | 57 | +0 -0 | 0 | 5 | 4 | 1 | 2.6k |
| 2026-11-22 15:28 | 0c2754e | streets traffic: clear of parked cars at the kerb (Givatayim's "into a post" was parked cars: 3 vs main 5, ... | 6.7 | 47 | 0.6 | **54** | 667 | +102 -4 | 4 | 53 | 49 | 8 | 27.6k |
| 2026-11-22 15:25 | 4384566 | streets GAME.md: Rawabi on the later list (OSM too thin for now: 94 buildings at its centre, no storeys) | 1.9 | 19 | 0.0 | **20** | 10 | +0 -0 | 0 | 12 | 12 | 1 | 9.7k |
| 2026-11-22 15:15 | 7fe491d | streets notes: the showroom and the trick road after the merge (levels 39, 40, route 14), the two-column te... | 1.8 | 2.6 | 0.0 | **4.4** | 0.0 | +9 -7 | 2 | 27 | 27 | 3 | 10.2k |
| 2026-11-22 15:11 | 5293efd | streets: two made-up places that are not towns -- a showroom walk among the game's things and models, and a... | 25 | 8.9 | 0.0 | **34** | 0.0 | +916 -12 | 10 | 151 | 174 | 18 | 131.0k |
| 2026-11-22 15:02 | b3ce21a | streets racer: tests/racer_drive.gd (a real drive in live traffic, to a street), why each way round a car w... | 1.4 | 2.0 | 0.0 | **3.4** | 0.0 | +0 -0 | 0 | 9 | 9 | 2 | 8.4k |
| 2026-11-22 15:00 | c6e94a2 | streets notes: parallel shader compiling tried in a browser -- compile at load 7.2 -> 0.5 s, what a real bu... | 4.1 | 3.6 | 0.0 | **7.7** | 0.0 | +0 -0 | 0 | 23 | 40 | 1 | 22.5k |
| 2026-11-22 14:58 | 575eefd | streets dragons: the camera placed before its first frame (one frame at the town's origin, in a building --... | 0.3 | 2.2 | 0.0 | **2.5** | 0.0 | +0 -0 | 0 | 3 | 3 | 1 | 1.9k |
| 2026-11-22 14:58 | 35eacfa | streets: parked cars clear of trees, lamps, poles, motorbikes and walls over their whole length (1767 of As... | 5.5 | 5.4 | 0.0 | **11** | 31 | +0 -0 | 0 | 17 | 20 | 8 | 15.4k |
| 2026-11-22 14:56 | 7500e05 | streets dragons: the run for cover goes round, not through (a wall reached in a clear line, at a sprinter's... | 7.6 | 10 | 0.0 | **18** | 0.0 | +0 -0 | 0 | 60 | 68 | 12 | 34.9k |
| 2026-11-22 14:54 | a45d460 | effort: rows for the latest commits | 0.5 | 1.5 | 0.4 | **2.4** | 0.0 | +0 -0 | 0 | 6 | 6 | 2 | 3.0k |
| 2026-11-22 14:52 | 6b19058 | effort: rows for the latest commits | 0.7 | 0.3 | 0.0 | **1.0** | 0.0 | +0 -0 | 0 | 1 | 1 | 1 | 0.5k |
| 2026-11-22 14:52 | 693d074 | streets: Leiden's and Annecy's walks and test drives (NEW_CITY.md: every city has both) | 4.7 | 14 | 0.0 | **19** | 17 | +0 -0 | 0 | 45 | 44 | 12 | 28.2k |
| 2026-11-22 14:51 | 74578ad | streets: the haze set before the warm-up -- the first minute's shader compiling 11.5 s -> 1.5 s | 3.7 | 9.2 | 8.8 | **22** | 0.0 | +0 -0 | 0 | 42 | 52 | 3 | 20.6k |
| 2026-11-22 14:38 | 3c18f9e | streets: dragons over the city -- two dragons duel over the towers, one dives at us, we hide behind a build... | 6.4 | 6.2 | 0.4 | **13** | 0.0 | +0 -0 | 0 | 26 | 34 | 7 | 32.6k |
| 2026-11-22 14:29 | f660b14 | effort: rows for the latest commits | 0.1 | 0.7 | 0.0 | **0.8** | 0.0 | +0 -0 | 0 | 3 | 3 | 1 | 0.6k |
| 2026-11-22 14:28 | d6224c9 | web build: Godot's never-drawn default lit programs compiled as a placeholder, for every game | 1.5 | 1.8 | 9.5 | **13** | 0.0 | +0 -0 | 0 | 17 | 25 | 4 | 9.4k |
| 2026-11-22 14:26 | 525dcdf | streets people: a start back when the car is about to hit them (Startled, the library's Hit_Chest; a stop a... | 4.8 | 8.9 | 0.9 | **15** | 765 | +263 -18 | 9 | 43 | 41 | 10 | 28.9k |
| 2026-11-22 14:25 | d226f5f | tools/record_video.sh: a game playing a level, filmed smooth and cut to the action, sized for the phone cha... | 18 | 40 | 0.1 | **58** | 631 | +0 -0 | 0 | 31 | 33 | 6 | 18.4k |
| 2026-11-22 14:16 | 946226d | effort: rows for the latest commits | 0.1 | 1.2 | 0.0 | **1.3** | 0.0 | +0 -0 | 0 | 2 | 2 | 1 | 0.6k |
| 2026-11-22 14:16 | 7f056b0 | notes: the never-drawn check's 4 -- the engine's own default material, at start, before any game | 17 | 32 | 0.0 | **50** | 647 | +0 -0 | 0 | 17 | 23 | 3 | 11.9k |
| 2026-11-22 14:16 | 0411c23 | effort: rows for the latest commits | 1.3 | 2.8 | 0.0 | **4.0** | 728 | +0 -0 | 0 | 15 | 15 | 3 | 7.3k |
| 2026-11-22 14:15 | e4461df | effort: rows for the latest commits | 16 | 2.6 | 0.0 | **18** | 664 | +0 -0 | 0 | 4 | 3 | 2 | 2.3k |
| 2026-11-22 14:15 | dee9130 | shell: a levelled game's start screen fits any number of groups -- up to three side by side in narrower col... | 1.1 | 1.0 | 0.0 | **2.2** | 770 | +35 -19 | 6 | 11 | 12 | 6 | 7.3k |
| 2026-11-22 14:15 | 6a924b4 | streets on foot: the library's sprint clip past 6 m/s (2.14 m/s at x1, a longer stride than the jog), the c... | 1.9 | 1.8 | 0.0 | **3.7** | 685 | +0 -0 | 0 | 14 | 15 | 5 | 9.3k |
| 2026-11-22 14:15 | 17f8fce | effort: rows for this session's commits | 0.1 | 0.3 | 0.0 | **0.4** | 0.0 | +0 -0 | 0 | 1 | 1 | 1 | 0.4k |
| 2026-11-22 03:27 | a1b8489 | streets: racer past a whole queue (the oncoming lanes on two-way streets, squeezing between lanes with the ... | 26 | 44 | 0.0 | **70** | 43 | +566 -17 | 7 | 147 | 144 | 34 | 122.8k |
| 2026-11-22 02:56 | 2ece45d | scene-tests skill: recording a scene or scenario to a smooth video for a phone (movie maker, trimming, enco... | 1.7 | 6.1 | 0.4 | **8.2** | 0.0 | +16 -0 | 1 | 20 | 17 | 3 | 9.0k |
| 2026-11-22 02:53 | e1c3bec | streets walks with a scene: a night out on Nahalat Binyamin, a Tel Aviv park, the beach (make_walks.py ways... | 6.2 | 16 | 0.0 | **22** | 0.0 | +214 -4 | 4 | 31 | 41 | 14 | 36.2k |
| 2026-11-22 02:48 | f156967 | CLAUDE.md: next-steps tables narrow for a phone, with compute time; comments under the table | 1.0 | 1.0 | 1.2 | **3.2** | 0.0 | +7 -6 | 1 | 10 | 8 | 3 | 5.9k |
| 2026-11-22 02:46 | 712da82 | streets: the run clip at the pace it covers (the jog 1.05 m/s at x1), up to 2.5x fast -- your jog's feet sl... | 1.4 | 0.4 | 0.8 | **2.6** | 0.0 | +0 -0 | 0 | 8 | 9 | 3 | 6.8k |
| 2026-11-22 02:44 | c1ffe87 | streets racer: bends read the plan as it was (orig), not points already moved -- racer no longer stands beh... | 19 | 22 | 0.0 | **41** | 15 | +0 -0 | 0 | 28 | 28 | 15 | 26.6k |
| 2026-11-22 02:44 | 336ea90 | effort: rows for the latest commits | 0.1 | 3.1 | 0.0 | **3.1** | 0.0 | +0 -0 | 0 | 1 | 1 | 0 | 0.3k |
| 2026-11-22 02:41 | bfdad49 | streets: the loading screen names the set-up too; split_posts tells where it knocks something; foot_slide.g... | 6.2 | 13 | 0.0 | **19** | 0.0 | +0 -0 | 0 | 40 | 46 | 19 | 32.1k |
| 2026-11-22 02:39 | 1497e69 | streets: far shadows paced through their road and area layers, half size on phones | 7.1 | 1.9 | 8.0 | **17** | 0.0 | +0 -0 | 0 | 14 | 14 | 4 | 9.9k |
| 2026-11-22 02:31 | 08e3ae6 | streets: walks, test drives and self-playing scenarios are watched, not driven; little building details in ... | 5.1 | 12 | 0.0 | **17** | 0.0 | +230 -12 | 6 | 34 | 37 | 13 | 26.9k |
| 2026-11-22 02:22 | a092562 | effort: rows for the latest commits | 0.2 | 2.8 | 0.0 | **3.0** | 0.0 | +0 -0 | 0 | 2 | 2 | 1 | 1.0k |
| 2026-11-22 02:22 | 6a84563 | streets: slow frames tick traffic and people every 4th tick and halve the catch-up build | 7.7 | 1.9 | 0.0 | **9.7** | 0.0 | +0 -0 | 0 | 20 | 22 | 2 | 12.0k |
| 2026-11-22 02:19 | b60cc54 | streets: autodrive's plan measured from the car (a long straight was never topped up: on past a junction at... | 10 | 28 | 0.5 | **38** | 19 | +0 -0 | 0 | 50 | 52 | 19 | 39.1k |
| 2026-11-22 02:14 | 45f9a36 | streets walks: the camera at 1.75 m; generated walks keep clear of low crowns of trees away from roads wher... | 3.3 | 11 | 0.0 | **15** | 39 | +43 -17 | 3 | 22 | 22 | 11 | 19.3k |
| 2026-11-22 02:12 | 8f4862b | notes: performance handoff -- what is next for the phone | 0.4 | 0.0 | 0.0 | **0.4** | 0.0 | +0 -0 | 0 | 3 | 2 | 0 | 2.3k |
| 2026-11-22 02:12 | 3b675e8 | notes: is a phone's 14-18 fps expected -- no: drawing and script each ~30 ms; the targets | 3.0 | 2.2 | 0.0 | **5.2** | 0.0 | +0 -0 | 0 | 9 | 9 | 1 | 3.5k |
| 2026-11-22 02:07 | 7fa32c1 | streets: building a square hands the frame back between every step; hitches name the step | 5.9 | 23 | 0.0 | **29** | 0.0 | +159 -4 | 4 | 46 | 56 | 8 | 27.3k |
| 2026-11-22 02:04 | 79a6f20 | streets: canals in the Dutch towns, canal-house gables, Dutch plates and cycle paths; Annecy (level 24), th... | 19 | 32 | 0.0 | **51** | 26 | +0 -0 | 0 | 131 | 151 | 20 | 98.9k |
| 2026-11-22 01:48 | 57b6f72 | streets scenarios that play themselves: a day in the town, night tours, the ambulance run, the getaway film... | 4.5 | 21 | 1.0 | **26** | 14 | +0 -0 | 0 | 28 | 28 | 12 | 29.0k |
| 2026-11-22 01:38 | 83c4dd2 | notes: a phone's numbers (Adreno 740): loads 8.5-9.5 s, drives at 5-18 fps -- the script's ticks spiral, th... | 8.0 | 2.5 | 0.0 | **11** | 44 | +36 -0 | 1 | 12 | 13 | 3 | 7.9k |
| 2026-11-22 01:33 | 779db7a | streets racer at a red: the pavement way up tried while coming up to a full queue, bent from the plan as it... | 2.5 | 14 | 0.0 | **17** | 0.0 | +54 -7 | 3 | 14 | 14 | 6 | 12.7k |
| 2026-11-22 01:26 | 7fd85b4 | effort: rows for the latest commits | 0.5 | 0.7 | 0.6 | **1.9** | 0.0 | +0 -0 | 0 | 9 | 9 | 2 | 3.2k |
| 2026-11-22 01:25 | c2224bc | streets people: a box carried in both arms (Carry: the arms held from the walk's mid-stride, the box betwee... | 25 | 8.5 | 7.2 | **41** | 1.0 | +321 -16 | 7 | 59 | 61 | 21 | 52.9k |
| 2026-11-22 01:23 | 7b159e6 | streets start screen: two groups, not three -- Cities and Scenarios under "Drive" (a third column ran off a... | 16 | 0.4 | 0.0 | **16** | 8.2 | +11 -5 | 3 | 11 | 11 | 3 | 4.0k |
| 2026-11-22 01:22 | eb759c8 | effort.py: per change also its lines added and removed and files touched (generated files left out), model ... | 1.2 | 0.3 | 0.0 | **1.5** | 11 | +47 -6 | 1 | 6 | 7 | 0 | 7.4k |
| 2026-11-22 01:20 | 447d3d4 | streets walks: under the street trees, not through them (trees by a road pruned up; no spruce in a pavement... | 15 | 50 | 10 | **75** | 0.0 | +507 -45 | 13 | 76 | 97 | 42 | 90.5k |
| 2026-11-22 01:16 | 1779d9a | streets racer: onto the pavement while coming up to a queue at a red (not once stood 6 m behind it), the wa... | 16 | 70 | 16 | **102** | 0.0 | +401 -20 | 7 | 102 | 100 | 18 | 78.8k |
| 2026-11-22 01:09 | b52c7d7 | effort.py --detail: the agent's minutes as thinking, writing and waiting on the model, the runs' by what ra... | 2.0 | 0.2 | 0.1 | **2.3** | 0.0 | +114 -4 | 1 | 12 | 14 | 0 | 11.5k |
| 2026-11-22 01:09 | a244b5c | effort: rows for the latest commits | 0.0 | 0.1 | 0.0 | **0.1** | 0.0 | +0 -0 | 0 | 0 | 0 | 0 | 0.0k |
| 2026-11-22 01:08 | a481902 | streets on foot: a jog (4.5 m/s) and a sprint (9.5), and into any car in the traffic you stand beside | 2.0 | 0.8 | 0.0 | **2.8** | 0.0 | +0 -0 | 0 | 13 | 14 | 6 | 11.1k |
| 2026-11-22 01:07 | 520eb44 | effort.py: a commit of the tables alone is no game's work (it had a row in every game) | 0.4 | 0.2 | 0.0 | **0.6** | 0.0 | +5 -0 | 1 | 3 | 3 | 0 | 2.1k |
| 2026-11-22 01:06 | 7ece738 | tools/effort.py: how long each change took -- agent, runs and the person's active minutes, time away left o... | 2.9 | 0.9 | 0.0 | **3.8** | 12 | +269 -0 | 2 | 13 | 14 | 0 | 15.5k |
| 2026-11-22 01:06 | 652d3a0 | streets scenarios: tour stops on public streets, arrival at the kerb counts; the chase's look-back cut, cha... | 2.0 | 17 | 3.2 | **23** | 0.0 | +0 -0 | 0 | 19 | 17 | 7 | 10.7k |
| 2026-11-22 00:59 | f93b9bf | streets HUD: no lights button (key L only); walk on the right under the camera, look under it | 1.0 | 2.9 | 0.0 | **4.0** | 17 | +11 -25 | 3 | 13 | 13 | 3 | 5.9k |
| 2026-11-22 00:51 | 82c1ba6 | streets: the walk clip's pace by the figures in use (the new people's walk ~0.85 m/s at x1): foot slide 26.... | 2.3 | 1.7 | 0.0 | **4.0** | 0.0 | +0 -0 | 0 | 16 | 17 | 5 | 11.0k |
| 2026-11-22 00:47 | db80877 | streets: walkers' feet stay put (the walk clip's own pace measured, 0.97 m/s, not 1.35: 16.5 -> 4.6 cm of s... | 6.5 | 17 | 2.7 | **26** | 0.0 | +0 -0 | 0 | 38 | 37 | 13 | 35.5k |
| 2026-11-22 00:47 | 486942e | streets: Leiden (level 16), the second Dutch town by the recipe; islands no longer lie on bridges' feet or ... | 16 | 21 | 17 | **53** | 0.0 | +0 -0 | 0 | 55 | 64 | 9 | 30.7k |
| 2026-11-22 00:43 | 9823141 | streets: Scenarios -- a page of tours (built from each town's story) and getaways (a police car on your tai... | 8.5 | 15 | 0.0 | **24** | 15 | +0 -0 | 0 | 39 | 46 | 13 | 44.2k |
| 2026-11-22 00:43 | 7183629 | streets people: skirts and dresses, older people (grey hair, slower), children walking with a grown-up, caf... | 4.5 | 4.6 | 2.8 | **12** | 0.0 | +151 -16 | 7 | 29 | 30 | 6 | 26.8k |
| 2026-11-22 00:43 | 2d86d7c | streets: a check for programs compiled and never drawn; the load line counts the skipped ones | 2.3 | 3.9 | 1.3 | **7.5** | 0.0 | +44 -4 | 4 | 27 | 39 | 2 | 13.1k |
| 2026-11-22 00:38 | 37d8115 | streets: the lists' settings -- test drives and cities choose normal or racer and day, evening or night, wa... | 3.9 | 6.2 | 2.6 | **13** | 0.0 | +172 -21 | 6 | 41 | 42 | 8 | 22.9k |
| 2026-11-22 00:36 | 98cdec5 | notes: performance's next steps, scored (effort, gain, risk) | 3.1 | 1.9 | 4.6 | **9.6** | 0.0 | +16 -0 | 1 | 14 | 13 | 2 | 5.8k |
| 2026-11-22 00:31 | dc9d443 | streets: new people -- Quaternius' Universal Base Characters (CC0) with the Universal Animation Library's m... | 6.2 | 15 | 1.1 | **22** | 0.0 | +433 -59 | 28 | 28 | 33 | 8 | 38.5k |
| 2026-11-22 00:26 | a060f8d | streets: the never-drawn lit programs compiled as an empty placeholder -- cold compiling 15 -> 6 s | 3.8 | 3.6 | 3.8 | **11** | 0.0 | +58 -18 | 3 | 34 | 44 | 2 | 22.3k |
| 2026-11-22 00:25 | a594bf0 | streets: the HUD's buttons and the 'more' drawer fill under a real mouse as the shell's buttons do on hover... | 1.1 | 1.4 | 2.0 | **4.5** | 41 | +15 -3 | 2 | 15 | 15 | 2 | 6.7k |
| 2026-11-22 00:21 | 6353432 | streets: the map-reading steps name the town as the rest of the loading text does | 0.5 | 0.6 | 0.0 | **1.1** | 0.0 | +0 -0 | 0 | 5 | 5 | 2 | 1.9k |
| 2026-11-22 00:20 | f734fab | streets: the loading screen names its inner steps -- the city file's 11 parts and each square's 13 stages; ... | 4.4 | 1.4 | 0.8 | **6.5** | 0.0 | +0 -0 | 0 | 35 | 36 | 8 | 18.8k |
| 2026-11-22 00:15 | 66bdabe | notes: the shader strip measured live (cold Givatayim 27.6 s, 15.0 s compiling, was 62.8) | 1.7 | 3.6 | 5.8 | **11** | 0.0 | +4 -0 | 1 | 32 | 36 | 5 | 8.9k |
| 2026-11-22 00:13 | 5272b83 | streets: the map-edge pocket and a quicker three-point turn -- autodrive turns round short of a junction on... | 3.0 | 4.0 | 3.8 | **11** | 0.0 | +0 -0 | 0 | 19 | 13 | 4 | 14.3k |
| 2026-11-22 00:09 | 799816b | notes: the Universal Base Characters trial -- what the free packs hold, dressing by bone weights, gotchas, ... | 5.0 | 8.7 | 5.7 | **19** | 0.0 | +57 -3 | 2 | 35 | 39 | 7 | 30.8k |
| 2026-11-22 00:05 | 6c1f2a5 | streets walks: seen from the eyes (1.58 m, not the film's chest-high 1.44), and the head turns to a passing... | 2.3 | 7.7 | 0.0 | **9.9** | 33 | +106 -2 | 4 | 14 | 14 | 7 | 13.2k |
| 2026-11-22 00:04 | c833f80 | streets: a cold load's minute of shader compiling cut ~4x -- LIGHT_STRIP_JS | 15 | 17 | 4.9 | **37** | 31 | +207 -0 | 3 | 158 | 186 | 11 | 73.6k |
| 2026-11-22 00:04 | 25f8704 | streets: each town's own story (cities/stories), shown a line at a time in the opening | 4.7 | 0.8 | 0.0 | **5.5** | 0.0 | +0 -0 | 0 | 15 | 14 | 4 | 23.9k |
| 2026-11-22 00:02 | 99344af | menu: only streets on the front page -- bowling and checkers to the other shelf | 15 | 12 | 9.8 | **36** | 0.0 | +0 -0 | 0 | 51 | 44 | 11 | 21.5k |
| 2026-11-21 23:58 | fdddaf8 | Blender: swings, see-saw, climbing dome; streets: models.gd stamps made models into batches, parks' playgro... | 4.1 | 5.8 | 0.0 | **9.9** | 0.0 | +0 -0 | 0 | 20 | 29 | 6 | 21.4k |
| 2026-11-21 23:53 | a5e1583 | streets: Delft looks Dutch -- brick and measured pitched roofs (a level's "build": "nl") | 9.9 | 3.3 | 6.7 | **20** | 30 | +0 -0 | 0 | 58 | 65 | 7 | 43.3k |
| 2026-11-21 23:49 | f92bbf9 | look tests: each shot's greys (red/green, blue/green of the truly grey pixels; FAIL past 0.07 off) beside t... | 0.8 | 0.5 | 0.0 | **1.3** | 0.0 | +71 -5 | 3 | 4 | 4 | 1 | 4.8k |
| 2026-11-21 23:48 | d325ec3 | notes: talking hands, walk 2's paving measured, car greys, shutter boxes; people_talk in the tests list | 1.1 | 1.5 | 0.0 | **2.6** | 0.0 | +34 -0 | 2 | 8 | 9 | 1 | 6.3k |
| 2026-11-21 23:48 | 9e77601 | streets notes: racer and the green wave are autodrive's styles now | 0.5 | 0.2 | 0.0 | **0.7** | 0.0 | +0 -0 | 0 | 6 | 6 | 2 | 2.7k |
| 2026-11-21 23:48 | 4565146 | Ideas: next-steps tables carry an AI grade and a comment (CLAUDE.md); streets: scenarios playing out in a town | 0.8 | 1.6 | 5.6 | **8.0** | 0.0 | +0 -0 | 0 | 7 | 8 | 1 | 4.9k |
| 2026-11-21 23:45 | e888506 | streets: the red-and-brown pavers muted as filmed (walk 2 on Sirkin: red over green 1.22-1.30 on screen -> ... | 2.6 | 2.9 | 0.0 | **5.5** | 0.0 | +6 -5 | 1 | 24 | 29 | 5 | 14.5k |
| 2026-11-21 23:40 | b43c01c | streets: hands while talking (Talk, a SkeletonModifier3D) for the cafe chatters and the film's talking grou... | 3.4 | 3.9 | 7.4 | **15** | 16 | +121 -0 | 2 | 29 | 32 | 8 | 19.6k |
| 2026-11-21 23:40 | 998e3e0 | Blender models for the kit; streets: the opening, playground pieces, racer goes round anything | 8.8 | 23 | 1.9 | **34** | 0.0 | +0 -0 | 0 | 50 | 61 | 19 | 52.1k |
| 2026-11-21 23:40 | 9685a1e | streets: the HUD's buttons reorganised -- on screen only what is used while driving (autodrive + its style ... | 10 | 1.9 | 0.5 | **13** | 0.0 | +556 -141 | 5 | 79 | 90 | 9 | 61.4k |
| 2026-11-21 23:35 | 99c8da6 | streets traffic: no rolling backwards after a hard brake, dead ends turned round in the lane going out, bus... | 19 | 36 | 4.8 | **60** | 46 | +387 -11 | 10 | 124 | 127 | 11 | 85.2k |
| 2026-11-21 23:26 | f6be176 | streets: autodrive gets back from the map's edge -- turns round short of a junction whose every way leads o... | 3.4 | 14 | 6.6 | **24** | 0.0 | +0 -0 | 0 | 23 | 21 | 7 | 18.9k |
| 2026-11-21 23:22 | 6ad6dc4 | streets: a Cities list beside the test routes and the walks, a back on each list, the walks' names without ... | 3.0 | 8.9 | 5.0 | **17** | 0.0 | +124 -30 | 8 | 22 | 22 | 8 | 17.2k |
| 2026-11-21 23:09 | b722cbb | streets: people carry things -- shopping bags, handbags, backpacks, a box in the carrying walk (it had arms... | 1.0 | 2.3 | 0.0 | **3.3** | 0.0 | +46 -5 | 3 | 9 | 10 | 2 | 5.1k |
| 2026-11-21 23:06 | 913056c | streets ideas: something to watch while the city loads | 2.4 | 7.9 | 8.2 | **19** | 0.0 | +0 -0 | 0 | 20 | 20 | 3 | 14.7k |
| 2026-11-21 23:06 | 5047f2b | wip carry | 6.3 | 11 | 3.7 | **21** | 0.0 | +214 -1 | 3 | 44 | 47 | 14 | 36.3k |
| 2026-11-21 23:05 | 3b2b910 | streets walk 1, pass 15: the forecourt as measured (bollards a cluster, the barrier, the twin poles' plinth... | 8.3 | 11 | 7.2 | **27** | 0.0 | +178 -32 | 8 | 55 | 62 | 13 | 47.6k |
| 2026-11-21 23:03 | 78ffd2d | streets: Delft (level 9), the first Dutch town, and a repeatable process for adding cities | 12 | 4.6 | 6.2 | **23** | 13 | +0 -0 | 0 | 83 | 102 | 6 | 48.8k |
| 2026-11-21 23:02 | 37fde7b | streets: a cafe table at the lane's edge kept off the asphalt (Dizengoff: 0.35 m in; Tel Aviv's posts in th... | 2.4 | 2.1 | 1.9 | **6.4** | 0.0 | +0 -0 | 0 | 19 | 16 | 6 | 12.1k |
| 2026-11-21 22:56 | 5fd62a9 | streets: nothing in the road, stop lines off zebras, splits kept clear, a smoother Tel Aviv, autodrive away... | 18 | 12 | 8.1 | **38** | 0.0 | +0 -0 | 0 | 151 | 147 | 36 | 98.8k |
| 2026-11-21 22:47 | e207034 | streets: the Ministry's bus roads, BRT and junction lanes; racer passes on the right, takes the pavement, k... | 5.1 | 25 | 4.7 | **35** | 0.0 | +0 -0 | 0 | 43 | 40 | 12 | 29.6k |
| 2026-11-21 22:45 | d788866 | streets: better people on the ideas list | 0.1 | 0.0 | 0.0 | **0.1** | 0.0 | +6 -0 | 1 | 1 | 3 | 0 | 0.7k |
| 2026-11-21 22:45 | 056afca | streets: better people on the ideas list; test .uid files | 1.8 | 0.3 | 5.0 | **7.2** | 0.0 | +0 -0 | 0 | 11 | 10 | 0 | 3.6k |
| 2026-11-21 22:39 | e0881ea | streets: a Walks list beside the test routes (both filmed walks behind it), and four walks nobody filmed --... | 8.5 | 12 | 0.0 | **21** | 0.0 | +674 -6 | 9 | 55 | 59 | 16 | 49.5k |
| 2026-11-21 22:38 | 6374b83 | streets: look tests flag burn-out (each shot's pure-white share, FAIL over 5%); the walk's grade gets a whi... | 4.9 | 9.0 | 9.8 | **24** | 0.0 | +111 -13 | 9 | 44 | 46 | 7 | 25.7k |
| 2026-11-21 22:32 | 07315e5 | notes: walk 1's score after merging main (34.1, the passage's end up 10) | 0.5 | 3.0 | 0.0 | **3.5** | 0.0 | +0 -0 | 0 | 6 | 5 | 2 | 2.6k |
| 2026-11-21 22:28 | e015633 | streets walk 1: measured against the full 1080p film -- film_score.py (a calibrated likeness per second), f... | 20 | 6.4 | 1.2 | **27** | 0.0 | +0 -0 | 0 | 82 | 103 | 10 | 93.4k |
| 2026-11-21 22:18 | de5e25f | streets: walkers no longer appear in view, light poles for every way in, nothing put up twice, a bank's foo... | 18 | 7.7 | 4.0 | **30** | 0.0 | +0 -0 | 0 | 141 | 151 | 22 | 79.2k |
| 2026-11-21 22:18 | ae24486 | streets walks (wip): film_score.py (per-second likeness to the film, calibrated), film_marks.py (landmarks:... | 12 | 3.6 | 1.2 | **17** | 0.0 | +759 -0 | 3 | 47 | 54 | 7 | 50.9k |
| 2026-11-21 22:14 | ec432c7 | streets: white plaster no longer burns out (the Compatibility renderer clips at 1 before any tone curve: ro... | 6.7 | 14 | 11 | **31** | 0.0 | +77 -25 | 4 | 47 | 55 | 13 | 38.4k |
| 2026-11-21 22:13 | d3bd1b7 | streets: racer mode, the Ministry's bus lanes, the towns' kindergartens and shelters | 14 | 17 | 11 | **42** | 0.0 | +0 -0 | 0 | 111 | 117 | 19 | 83.8k |
| 2026-11-21 21:43 | b388d2f | streets: the wall shader's balconies as the kit's (dark creases, coping, lip and drip line, railings of bar... | 7.3 | 5.2 | 9.0 | **22** | 0.0 | +132 -22 | 7 | 59 | 73 | 17 | 37.7k |
| 2026-11-21 21:31 | 704537e | streets: the green wave and the city from above before it is built | 13 | 14 | 1.4 | **28** | 0.0 | +0 -0 | 0 | 101 | 99 | 17 | 68.6k |
| 2026-11-20 22:30 | 1b5f176 | streets data, second round: Givatayim's trees, spot heights, land use, addresses and city things; Ramat Gan... | 5.8 | 11 | 7.5 | **24** | 0.0 | +0 -0 | 0 | 40 | 45 | 0 | 37.2k |
| 2026-11-20 22:06 | 214e920 | streets data from the user's computer: Givatayim's and Ramat Gan's storeys on level 1 (guessed heights 4,72... | 13 | 6.2 | 1.2 | **20** | 0.0 | +0 -0 | 0 | 118 | 148 | 0 | 73.0k |
| 2026-09-10 23:52 | a5bb03e | drive_by: bananas that explode, a road that bends, a head that moves | 15 | 6.8 | 0.0 | **21** | 196 | +0 -0 | 0 | 15 | 24 | 13 | 45.1k |
| 2026-09-10 20:15 | 7966b40 | drive_by: no crosshair, view turned toward the road ahead, 3 s opening shot into the car | 1.7 | 0.7 | 8.5 | **11** | 0.0 | +0 -0 | 0 | 5 | 7 | 2 | 9.0k |
| 2026-09-10 20:04 | 8b4da31 | Add drive_by: a rail shooter from a car window (the kit's second 3D game) | 21 | 1.4 | 0.0 | **23** | 0.0 | +0 -0 | 0 | 11 | 21 | 8 | 31.1k |
| 2026-09-10 19:41 | f7f38c6 | GameMode3D: render the 3D view at window resolution with 4x MSAA | 1.4 | 0.7 | 0.0 | **2.2** | 11 | +29 -5 | 2 | 6 | 6 | 1 | 8.5k |
| 2026-09-10 19:28 | b7775f8 | drop: real things and real people; models + characters become platform features | 9.9 | 2.0 | 1.1 | **13** | 0.0 | +0 -0 | 0 | 19 | 29 | 10 | 52.8k |
| 2026-09-10 19:14 | 8fce951 | drop: remove the rotate control; the piece idles with a slow spin and falls at a random yaw | 1.6 | 0.4 | 0.0 | **2.1** | 50 | +0 -0 | 0 | 5 | 9 | 2 | 7.2k |
| 2026-09-10 18:22 | 2501239 | Add 3D to the kit: GameMode3D shell contract + drop, the first 3D game | 25 | 4.0 | 4.7 | **34** | 11 | +0 -0 | 0 | 52 | 104 | 31 | 123.4k |
| 2026-09-10 14:21 | bbc2191 | planets: menu with regular/custom/AI-vs-AI, 2x shot speed, orbiting moons | 12 | 3.4 | 0.0 | **15** | 107 | +0 -0 | 0 | 8 | 19 | 8 | 44.1k |
| 2026-09-10 12:19 | 95a53bd | planets: angle/power wheels by FIRE, random from level 1, destructible moons | 5.9 | 1.4 | 0.0 | **7.2** | 151 | +0 -0 | 0 | 9 | 17 | 5 | 16.9k |
| 2026-09-10 09:41 | 566790b | planets: tap to aim, FIRE button, scrolling map that follows the shot | 5.3 | 1.0 | 0.0 | **6.3** | 595 | +0 -0 | 0 | 7 | 16 | 4 | 17.6k |
| 2026-09-09 23:40 | 21be7c9 | planets: zoomed-out world, random levels from level 2, fuse, top HP bars | 5.4 | 1.3 | 9.3 | **16** | 0.0 | +0 -0 | 0 | 8 | 21 | 6 | 18.0k |
| 2026-09-09 23:24 | a4705da | planets: HP with distance-based blast damage; long shots come back sooner | 7.3 | 1.5 | 3.7 | **12** | 0.0 | +0 -0 | 0 | 13 | 35 | 11 | 30.3k |
| 2026-09-09 23:12 | fc9fb03 | planets: stronger gravity, blast radius, craters, falling tanks | 8.7 | 1.7 | 3.1 | **13** | 0.0 | +0 -0 | 0 | 13 | 31 | 8 | 44.6k |
| 2026-09-09 22:58 | 5187280 | publish workflow: quote the Godot invocation so YAML parses | 0.5 | 0.6 | 0.0 | **1.1** | 0.0 | +2 -1 | 1 | 5 | 6 | 0 | 2.1k |
| 2026-09-09 22:57 | 0b918b7 | Publish the web build from GitHub Actions on every push to main | 1.5 | 0.7 | 1.2 | **3.4** | 0.0 | +70 -10 | 3 | 9 | 11 | 3 | 7.1k |
| 2026-09-09 22:54 | f02275f | planets: Scorched Earth on planets with gravity | 16 | 0.7 | 0.0 | **16** | 53 | +0 -0 | 0 | 27 | 42 | 20 | 67.8k |
| 2026-09-09 21:46 | bc5c7a1 | rumor: one room, people ask riddles; touch-first controls | 8.1 | 2.0 | 6.0 | **16** | 0.0 | +0 -0 | 0 | 17 | 27 | 8 | 36.7k |
| 2026-09-09 21:30 | 1816107 | Web build: stop caches serving a stale pck, check for new builds every launch | 15 | 4.9 | 0.0 | **20** | 45 | +87 -18 | 3 | 31 | 43 | 9 | 61.1k |
| 2026-09-03 18:50 | e49bf2f | bricks: tap-a-side controls, not drag-to-position | 6.6 | 1.9 | 0.0 | **8.5** | 13 | +0 -0 | 0 | 45 | 46 | 4 | 27.0k |
| 2026-09-03 18:50 | 72fa9ae | Note three more music candidates, not downloaded yet | 0.3 | 0.1 | 0.0 | **0.4** | 0.0 | +11 -0 | 1 | 3 | 3 | 0 | 1.3k |
| 2026-09-03 18:29 | a809196 | Add a persistent sound toggle, and real background music for bricks | 9.5 | 3.3 | 1.0 | **14** | 20 | +0 -0 | 0 | 63 | 62 | 4 | 42.5k |
| 2026-09-03 17:55 | 3e1714c | Revert the menu volume control; drop bricks' background music | 4.3 | 1.4 | 5.2 | **11** | 0.0 | +0 -0 | 0 | 33 | 32 | 4 | 18.7k |
| 2026-09-03 17:44 | 2a6e5b3 | Add a volume control on the main menu, wired to actually work in-game | 11 | 4.3 | 0.0 | **15** | 196 | +0 -0 | 0 | 64 | 66 | 5 | 48.1k |
| 2026-09-03 14:12 | ffa4eba | bricks: four brick types, multi-ball, a tighter swipe, more graphics and music | 22 | 4.9 | 4.4 | **32** | 164 | +0 -0 | 0 | 69 | 66 | 15 | 82.3k |
| 2026-09-03 10:56 | 440fe86 | Add turret: aim only, fires by itself, things fall on you | 4.9 | 1.9 | 0.0 | **6.8** | 82 | +0 -0 | 0 | 13 | 12 | 6 | 18.8k |
| 2026-09-03 09:27 | b946237 | Add bricks: breakout with power-ups that can also be power-downs | 7.2 | 3.3 | 0.7 | **11** | 639 | +0 -0 | 0 | 23 | 21 | 12 | 27.3k |
| 2026-09-02 22:37 | ddf7f42 | Rewrite the README around the live link, and clear out cruft | 1.5 | 0.3 | 8.0 | **9.9** | 0.0 | +49 -26 | 3 | 6 | 5 | 3 | 5.8k |
| 2026-09-02 22:27 | fd943a3 | Stop the installed web app serving a stale build forever | 2.6 | 0.5 | 7.4 | **10** | 0.0 | +58 -1 | 2 | 8 | 8 | 2 | 9.8k |
| 2026-09-02 22:16 | c9db038 | Fix the solve button not being clickable | 1.2 | 0.7 | 2.9 | **4.9** | 0.0 | +0 -0 | 0 | 7 | 6 | 1 | 4.3k |
| 2026-09-02 22:12 | 1bfe2dc | maze: a solve button that really solves | 2.9 | 1.2 | 6.0 | **10** | 0.0 | +0 -0 | 0 | 7 | 6 | 4 | 11.9k |
| 2026-09-02 22:01 | f38b269 | maze: several mazes on screen, a far exit, and movement on the grid | 7.4 | 1.5 | 7.4 | **16** | 0.0 | +0 -0 | 0 | 20 | 19 | 4 | 32.5k |
| 2026-09-02 21:45 | 48e1bb4 | Add maze: watch it build itself, then get out | 24 | 2.0 | 0.0 | **26** | 165 | +0 -0 | 0 | 22 | 21 | 6 | 35.3k |
| 2026-09-02 18:34 | 3e7656e | Tone the build stamp down | 0.5 | 0.3 | 1.0 | **1.9** | 0.0 | +6 -2 | 2 | 2 | 1 | 1 | 1.8k |
| 2026-09-02 18:32 | f387585 | Stamp the build and show it on the menu | 11 | 0.7 | 6.4 | **19** | 0.0 | +19 -1 | 4 | 14 | 8 | 3 | 12.5k |
| 2026-09-02 18:13 | b0b026b | Make the PWA actually installable, and fullscreen | 1.8 | 0.5 | 0.0 | **2.4** | 0.0 | +54 -8 | 4 | 5 | 4 | 2 | 7.8k |
| 2026-09-02 18:11 | f25600a | Make the web build installable (PWA) | 4.7 | 0.4 | 0.0 | **5.1** | 0.0 | +1 -1 | 1 | 4 | 3 | 2 | 4.5k |
| 2026-09-02 18:06 | 1370075 | Add an always-available menu button to the HUD | 11 | 2.5 | 0.0 | **14** | 0.0 | +0 -0 | 0 | 33 | 31 | 2 | 20.9k |
| 2026-09-02 17:52 | c26e5ab | Publish to Pages, split designs per game, rewrite onboarding | 8.6 | 0.8 | 5.1 | **14** | 1176 | +0 -0 | 0 | 16 | 10 | 4 | 24.9k |
| 2026-09-01 22:02 | 8d8bdde | Undo what the mono editor did to project.godot | 0.6 | 0.1 | 0.0 | **0.7** | 0.0 | +10 -2 | 1 | 3 | 3 | 3 | 2.5k |
| 2026-09-01 22:01 | 174cac7 | Add the Web export preset | 4.9 | 1.3 | 4.0 | **10** | 19 | +34 -0 | 1 | 25 | 22 | 2 | 17.1k |
| 2026-09-01 21:32 | c480a74 | Animals back in both games, and make placement the difficulty in count | 6.6 | 32 | 0.7 | **39** | 17 | +0 -0 | 0 | 22 | 24 | 5 | 28.3k |
| 2026-09-01 20:36 | 40b664d | Put the animated cast into tank, and let the shell fly on | 3.1 | 0.6 | 1.1 | **4.8** | 0.0 | +0 -0 | 0 | 11 | 10 | 3 | 12.6k |
| 2026-09-01 20:31 | 275d0e3 | Add animated actors and a voice, and teach Blob to play frames | 9.0 | 9.7 | 6.3 | **25** | 0.0 | +0 -0 | 0 | 39 | 44 | 4 | 37.1k |
| 2026-09-01 20:06 | 26ca4f9 | Add tank: lob a shell onto the odd animal out | 12 | 9.2 | 0.3 | **21** | 0.0 | +0 -0 | 0 | 26 | 23 | 9 | 41.1k |
| 2026-09-01 19:45 | bdcce5c | Add count, keep it as the reference, drop the starter games | 8.9 | 2.5 | 2.1 | **14** | 0.0 | +0 -0 | 0 | 51 | 52 | 14 | 38.1k |
