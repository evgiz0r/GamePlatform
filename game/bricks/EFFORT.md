# Effort: bricks

How long each change took, in minutes, from the Claude Code sessions that made it (`tools/effort.py`, which says how it is counted): **agent** thinking and writing, **runs** the tests, engine and git it waited on, **you** between its reply and your next message, **active** the three together. **away** is left out: gaps over 10 minutes, and the rest of any step past its cap. **lines** added and removed and **files** touched, leaving out generated files (baked data, the web build, imports); **steps** the times the model was called, **tools** its tool calls, **engine runs** those that ran the engine (a test, a playtest, a check), **tokens out** what it wrote (thinking included). Newest first; rows are kept once written.

| date (UTC) | commit | change | agent | runs | you | active | away | lines | files | steps | tools | engine runs | tokens out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-03 18:50 | e49bf2f | bricks: tap-a-side controls, not drag-to-position | 6.6 | 1.9 | 0.0 | **8.5** | 13 | +66 -24 | 5 | 45 | 46 | 4 | 27.0k |
| 2026-09-03 18:29 | a809196 | Add a persistent sound toggle, and real background music for bricks | 9.5 | 3.3 | 1.0 | **14** | 20 | +125 -16 | 13 | 63 | 62 | 4 | 42.5k |
| 2026-09-03 17:55 | 3e1714c | Revert the menu volume control; drop bricks' background music | 4.3 | 1.4 | 5.2 | **11** | 0.0 | +22 -71 | 6 | 33 | 32 | 4 | 18.7k |
| 2026-09-03 17:44 | 2a6e5b3 | Add a volume control on the main menu, wired to actually work in-game | 11 | 4.3 | 0.0 | **15** | 196 | +82 -18 | 8 | 64 | 66 | 5 | 48.1k |
| 2026-09-03 14:12 | ffa4eba | bricks: four brick types, multi-ball, a tighter swipe, more graphics and music | 22 | 4.9 | 4.4 | **32** | 164 | +363 -77 | 4 | 69 | 66 | 15 | 82.3k |
| 2026-09-03 09:27 | b946237 | Add bricks: breakout with power-ups that can also be power-downs | 7.2 | 3.3 | 0.7 | **11** | 639 | +498 -1 | 4 | 23 | 21 | 12 | 27.3k |
