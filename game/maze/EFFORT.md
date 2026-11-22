# Effort: maze

How long each change took, in minutes, from the Claude Code sessions that made it (`tools/effort.py`, which says how it is counted): **agent** thinking and writing, **runs** the tests, engine and git it waited on, **you** between its reply and your next message, **active** the three together. **away** is left out: gaps over 10 minutes, and the rest of any step past its cap. **lines** added and removed and **files** touched, leaving out generated files (baked data, the web build, imports); **steps** the times the model was called, **tools** its tool calls, **engine runs** those that ran the engine (a test, a playtest, a check), **tokens out** what it wrote (thinking included). Newest first; rows are kept once written.

| date (UTC) | commit | change | agent | runs | you | active | away | lines | files | steps | tools | engine runs | tokens out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-03 17:44 | 2a6e5b3 | Add a volume control on the main menu, wired to actually work in-game | 11 | 4.3 | 0.0 | **15** | 196 | +82 -18 | 8 | 64 | 66 | 5 | 48.1k |
| 2026-09-02 22:16 | c9db038 | Fix the solve button not being clickable | 1.2 | 0.7 | 2.9 | **4.9** | 0.0 | +9 -1 | 2 | 7 | 6 | 1 | 4.3k |
| 2026-09-02 22:12 | 1bfe2dc | maze: a solve button that really solves | 2.9 | 1.2 | 6.0 | **10** | 0.0 | +102 -2 | 4 | 7 | 6 | 4 | 11.9k |
| 2026-09-02 22:01 | f38b269 | maze: several mazes on screen, a far exit, and movement on the grid | 7.4 | 1.5 | 7.4 | **16** | 0.0 | +275 -168 | 4 | 20 | 19 | 4 | 32.5k |
| 2026-09-02 21:45 | 48e1bb4 | Add maze: watch it build itself, then get out | 24 | 2.0 | 0.0 | **26** | 165 | +410 -1 | 4 | 22 | 21 | 6 | 35.3k |
