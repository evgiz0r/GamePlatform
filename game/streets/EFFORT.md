# Effort: streets

How long each change took, in minutes, from the Claude Code sessions that made it (`tools/effort.py`, which says how it is counted): **agent** thinking and writing, **runs** the tests, engine and git it waited on, **you** between its reply and your next message, **active** the three together. **away** is left out: gaps over 10 minutes, and the rest of any step past its cap. Newest first; rows are kept once written.

| date (UTC) | commit | change | agent | runs | you | active | away |
|---|---|---|---|---|---|---|---|
| 2026-11-22 01:06 | 652d3a0 | streets scenarios: tour stops on public streets, arrival at the kerb counts; the chase's look-back cut, cha... | 2.0 | 17 | 3.2 | **23** | 0.0 |
| 2026-11-22 00:59 | f93b9bf | streets HUD: no lights button (key L only); walk on the right under the camera, look under it | 1.0 | 2.9 | 0.0 | **4.0** | 17 |
| 2026-11-22 00:51 | 82c1ba6 | streets: the walk clip's pace by the figures in use (the new people's walk ~0.85 m/s at x1): foot slide 26.... | 2.3 | 1.7 | 0.0 | **4.0** | 0.0 |
| 2026-11-22 00:47 | db80877 | streets: walkers' feet stay put (the walk clip's own pace measured, 0.97 m/s, not 1.35: 16.5 -> 4.6 cm of s... | 6.5 | 17 | 2.7 | **26** | 0.0 |
| 2026-11-22 00:47 | 486942e | streets: Leiden (level 16), the second Dutch town by the recipe; islands no longer lie on bridges' feet or ... | 16 | 21 | 17 | **53** | 0.0 |
| 2026-11-22 00:43 | 9823141 | streets: Scenarios -- a page of tours (built from each town's story) and getaways (a police car on your tai... | 8.5 | 15 | 0.0 | **24** | 15 |
| 2026-11-22 00:43 | 7183629 | streets people: skirts and dresses, older people (grey hair, slower), children walking with a grown-up, caf... | 4.5 | 4.6 | 2.8 | **12** | 0.0 |
| 2026-11-22 00:43 | 2d86d7c | streets: a check for programs compiled and never drawn; the load line counts the skipped ones | 2.3 | 3.9 | 1.3 | **7.5** | 0.0 |
| 2026-11-22 00:38 | 37d8115 | streets: the lists' settings -- test drives and cities choose normal or racer and day, evening or night, wa... | 3.9 | 6.2 | 2.6 | **13** | 0.0 |
| 2026-11-22 00:36 | 98cdec5 | notes: performance's next steps, scored (effort, gain, risk) | 3.1 | 1.9 | 4.6 | **9.6** | 0.0 |
| 2026-11-22 00:31 | dc9d443 | streets: new people -- Quaternius' Universal Base Characters (CC0) with the Universal Animation Library's m... | 6.2 | 15 | 1.1 | **22** | 0.0 |
| 2026-11-22 00:26 | a060f8d | streets: the never-drawn lit programs compiled as an empty placeholder -- cold compiling 15 -> 6 s | 3.8 | 3.6 | 3.8 | **11** | 0.0 |
| 2026-11-22 00:25 | a594bf0 | streets: the HUD's buttons and the 'more' drawer fill under a real mouse as the shell's buttons do on hover... | 1.1 | 1.4 | 2.0 | **4.5** | 41 |
| 2026-11-22 00:21 | 6353432 | streets: the map-reading steps name the town as the rest of the loading text does | 0.5 | 0.6 | 0.0 | **1.1** | 0.0 |
| 2026-11-22 00:20 | f734fab | streets: the loading screen names its inner steps -- the city file's 11 parts and each square's 13 stages; ... | 4.4 | 1.4 | 0.8 | **6.5** | 0.0 |
| 2026-11-22 00:15 | 66bdabe | notes: the shader strip measured live (cold Givatayim 27.6 s, 15.0 s compiling, was 62.8) | 1.7 | 3.6 | 5.8 | **11** | 0.0 |
| 2026-11-22 00:13 | 5272b83 | streets: the map-edge pocket and a quicker three-point turn -- autodrive turns round short of a junction on... | 3.0 | 4.0 | 3.8 | **11** | 0.0 |
| 2026-11-22 00:09 | 799816b | notes: the Universal Base Characters trial -- what the free packs hold, dressing by bone weights, gotchas, ... | 5.0 | 8.7 | 5.7 | **19** | 0.0 |
| 2026-11-22 00:05 | 6c1f2a5 | streets walks: seen from the eyes (1.58 m, not the film's chest-high 1.44), and the head turns to a passing... | 2.3 | 7.7 | 0.0 | **9.9** | 33 |
| 2026-11-22 00:04 | c833f80 | streets: a cold load's minute of shader compiling cut ~4x -- LIGHT_STRIP_JS | 15 | 17 | 4.9 | **37** | 31 |
| 2026-11-22 00:04 | 25f8704 | streets: each town's own story (cities/stories), shown a line at a time in the opening | 4.7 | 0.8 | 0.0 | **5.5** | 0.0 |
| 2026-11-21 23:58 | fdddaf8 | Blender: swings, see-saw, climbing dome; streets: models.gd stamps made models into batches, parks' playgro... | 4.1 | 5.8 | 0.0 | **9.9** | 0.0 |
| 2026-11-21 23:53 | a5e1583 | streets: Delft looks Dutch -- brick and measured pitched roofs (a level's "build": "nl") | 9.9 | 3.3 | 6.7 | **20** | 30 |
| 2026-11-21 23:49 | f92bbf9 | look tests: each shot's greys (red/green, blue/green of the truly grey pixels; FAIL past 0.07 off) beside t... | 0.8 | 0.5 | 0.0 | **1.3** | 0.0 |
| 2026-11-21 23:48 | d325ec3 | notes: talking hands, walk 2's paving measured, car greys, shutter boxes; people_talk in the tests list | 1.1 | 1.5 | 0.0 | **2.6** | 0.0 |
| 2026-11-21 23:48 | 9e77601 | streets notes: racer and the green wave are autodrive's styles now | 0.5 | 0.2 | 0.0 | **0.7** | 0.0 |
| 2026-11-21 23:48 | 4565146 | Ideas: next-steps tables carry an AI grade and a comment (CLAUDE.md); streets: scenarios playing out in a town | 0.8 | 1.6 | 5.6 | **8.0** | 0.0 |
| 2026-11-21 23:45 | e888506 | streets: the red-and-brown pavers muted as filmed (walk 2 on Sirkin: red over green 1.22-1.30 on screen -> ... | 2.6 | 2.9 | 0.0 | **5.5** | 0.0 |
| 2026-11-21 23:40 | b43c01c | streets: hands while talking (Talk, a SkeletonModifier3D) for the cafe chatters and the film's talking grou... | 3.4 | 3.9 | 7.4 | **15** | 16 |
| 2026-11-21 23:40 | 998e3e0 | Blender models for the kit; streets: the opening, playground pieces, racer goes round anything | 8.8 | 23 | 1.9 | **34** | 0.0 |
| 2026-11-21 23:40 | 9685a1e | streets: the HUD's buttons reorganised -- on screen only what is used while driving (autodrive + its style ... | 10 | 1.9 | 0.5 | **13** | 0.0 |
| 2026-11-21 23:35 | 99c8da6 | streets traffic: no rolling backwards after a hard brake, dead ends turned round in the lane going out, bus... | 19 | 36 | 4.8 | **60** | 46 |
| 2026-11-21 23:26 | f6be176 | streets: autodrive gets back from the map's edge -- turns round short of a junction whose every way leads o... | 3.4 | 14 | 6.6 | **24** | 0.0 |
| 2026-11-21 23:22 | 6ad6dc4 | streets: a Cities list beside the test routes and the walks, a back on each list, the walks' names without ... | 3.0 | 8.9 | 5.0 | **17** | 0.0 |
| 2026-11-21 23:09 | b722cbb | streets: people carry things -- shopping bags, handbags, backpacks, a box in the carrying walk (it had arms... | 1.0 | 2.3 | 0.0 | **3.3** | 0.0 |
| 2026-11-21 23:06 | 913056c | streets ideas: something to watch while the city loads | 2.4 | 7.9 | 8.2 | **19** | 0.0 |
| 2026-11-21 23:06 | 5047f2b | wip carry | 6.3 | 11 | 3.7 | **21** | 0.0 |
| 2026-11-21 23:05 | 3b2b910 | streets walk 1, pass 15: the forecourt as measured (bollards a cluster, the barrier, the twin poles' plinth... | 8.3 | 11 | 7.2 | **27** | 0.0 |
| 2026-11-21 23:03 | 78ffd2d | streets: Delft (level 9), the first Dutch town, and a repeatable process for adding cities | 12 | 4.6 | 6.2 | **23** | 13 |
| 2026-11-21 23:02 | 37fde7b | streets: a cafe table at the lane's edge kept off the asphalt (Dizengoff: 0.35 m in; Tel Aviv's posts in th... | 2.4 | 2.1 | 1.9 | **6.4** | 0.0 |
| 2026-11-21 22:56 | 5fd62a9 | streets: nothing in the road, stop lines off zebras, splits kept clear, a smoother Tel Aviv, autodrive away... | 18 | 12 | 8.1 | **38** | 0.0 |
| 2026-11-21 22:47 | e207034 | streets: the Ministry's bus roads, BRT and junction lanes; racer passes on the right, takes the pavement, k... | 5.1 | 25 | 4.7 | **35** | 0.0 |
| 2026-11-21 22:45 | d788866 | streets: better people on the ideas list | 0.1 | 0.0 | 0.0 | **0.1** | 0.0 |
| 2026-11-21 22:45 | 056afca | streets: better people on the ideas list; test .uid files | 1.8 | 0.3 | 5.0 | **7.2** | 0.0 |
| 2026-11-21 22:39 | e0881ea | streets: a Walks list beside the test routes (both filmed walks behind it), and four walks nobody filmed --... | 8.5 | 12 | 0.0 | **21** | 0.0 |
| 2026-11-21 22:38 | 6374b83 | streets: look tests flag burn-out (each shot's pure-white share, FAIL over 5%); the walk's grade gets a whi... | 4.9 | 9.0 | 9.8 | **24** | 0.0 |
| 2026-11-21 22:32 | 07315e5 | notes: walk 1's score after merging main (34.1, the passage's end up 10) | 0.5 | 3.0 | 0.0 | **3.5** | 0.0 |
| 2026-11-21 22:28 | e015633 | streets walk 1: measured against the full 1080p film -- film_score.py (a calibrated likeness per second), f... | 20 | 6.4 | 1.2 | **27** | 0.0 |
| 2026-11-21 22:18 | de5e25f | streets: walkers no longer appear in view, light poles for every way in, nothing put up twice, a bank's foo... | 18 | 7.7 | 4.0 | **30** | 0.0 |
| 2026-11-21 22:18 | ae24486 | streets walks (wip): film_score.py (per-second likeness to the film, calibrated), film_marks.py (landmarks:... | 12 | 3.6 | 1.2 | **17** | 0.0 |
| 2026-11-21 22:14 | ec432c7 | streets: white plaster no longer burns out (the Compatibility renderer clips at 1 before any tone curve: ro... | 6.7 | 14 | 11 | **31** | 0.0 |
| 2026-11-21 22:13 | d3bd1b7 | streets: racer mode, the Ministry's bus lanes, the towns' kindergartens and shelters | 14 | 17 | 11 | **42** | 0.0 |
| 2026-11-21 21:43 | b388d2f | streets: the wall shader's balconies as the kit's (dark creases, coping, lip and drip line, railings of bar... | 7.3 | 5.2 | 9.0 | **22** | 0.0 |
| 2026-11-21 21:31 | 704537e | streets: the green wave and the city from above before it is built | 13 | 14 | 1.4 | **28** | 0.0 |
| 2026-11-20 22:30 | 1b5f176 | streets data, second round: Givatayim's trees, spot heights, land use, addresses and city things; Ramat Gan... | 5.8 | 11 | 7.5 | **24** | 0.0 |
| 2026-11-20 22:06 | 214e920 | streets data from the user's computer: Givatayim's and Ramat Gan's storeys on level 1 (guessed heights 4,72... | 13 | 7.4 | 0.0 | **20** | 0.0 |
