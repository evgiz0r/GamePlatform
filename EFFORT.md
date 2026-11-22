# Effort: the kit

How long each change took, in minutes, from the Claude Code sessions that made it (`tools/effort.py`, which says how it is counted): **agent** thinking and writing, **runs** the tests, engine and git it waited on, **you** between its reply and your next message, **active** the three together. **away** is left out: gaps over 10 minutes, and the rest of any step past its cap. **lines** added and removed and **files** touched, leaving out generated files (baked data, the web build, imports); **steps** the times the model was called, **tools** its tool calls, **engine runs** those that ran the engine (a test, a playtest, a check), **tokens out** what it wrote (thinking included). Newest first; rows are kept once written.

| date (UTC) | commit | change | agent | runs | you | active | away | lines | files | steps | tools | engine runs | tokens out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-11-22 01:22 | eb759c8 | effort.py: per change also its lines added and removed and files touched (generated files left out), model ... | 1.2 | 0.2 | 0.0 | **1.3** | 11 | +47 -6 | 1 | 6 | 7 | 0 | 7.4k |
| 2026-11-22 01:09 | b52c7d7 | effort.py --detail: the agent's minutes as thinking, writing and waiting on the model, the runs' by what ra... | 2.0 | 0.2 | 0.1 | **2.3** | 0.0 | +114 -4 | 1 | 12 | 14 | 0 | 11.5k |
| 2026-11-22 01:07 | 520eb44 | effort.py: a commit of the tables alone is no game's work (it had a row in every game) | 0.4 | 0.2 | 0.0 | **0.6** | 0.0 | +5 -0 | 1 | 3 | 3 | 0 | 2.1k |
| 2026-11-22 01:06 | 7ece738 | tools/effort.py: how long each change took -- agent, runs and the person's active minutes, time away left o... | 2.9 | 0.9 | 0.0 | **3.8** | 12 | +269 -0 | 2 | 13 | 14 | 0 | 15.5k |
| 2026-09-10 19:41 | f7f38c6 | GameMode3D: render the 3D view at window resolution with 4x MSAA | 1.4 | 0.7 | 0.0 | **2.2** | 11 | +29 -5 | 2 | 6 | 6 | 1 | 8.5k |
| 2026-09-09 22:58 | 5187280 | publish workflow: quote the Godot invocation so YAML parses | 0.5 | 0.6 | 0.0 | **1.1** | 0.0 | +2 -1 | 1 | 5 | 6 | 0 | 2.1k |
| 2026-09-09 22:57 | 0b918b7 | Publish the web build from GitHub Actions on every push to main | 1.5 | 0.7 | 1.2 | **3.4** | 0.0 | +70 -10 | 3 | 9 | 11 | 3 | 7.1k |
| 2026-09-09 21:30 | 1816107 | Web build: stop caches serving a stale pck, check for new builds every launch | 15 | 4.9 | 0.0 | **20** | 45 | +87 -18 | 3 | 31 | 43 | 9 | 61.1k |
| 2026-09-03 18:50 | 72fa9ae | Note three more music candidates, not downloaded yet | 0.3 | 0.1 | 0.0 | **0.4** | 0.0 | +11 -0 | 1 | 3 | 3 | 0 | 1.3k |
| 2026-09-02 22:37 | ddf7f42 | Rewrite the README around the live link, and clear out cruft | 1.5 | 0.3 | 8.0 | **9.9** | 0.0 | +49 -26 | 3 | 6 | 5 | 3 | 5.8k |
| 2026-09-02 22:27 | fd943a3 | Stop the installed web app serving a stale build forever | 2.6 | 0.5 | 7.4 | **10** | 0.0 | +58 -1 | 2 | 8 | 8 | 2 | 9.8k |
| 2026-09-02 18:34 | 3e7656e | Tone the build stamp down | 0.5 | 0.3 | 1.0 | **1.9** | 0.0 | +6 -2 | 2 | 2 | 1 | 1 | 1.8k |
| 2026-09-02 18:32 | f387585 | Stamp the build and show it on the menu | 11 | 0.7 | 6.4 | **19** | 0.0 | +19 -1 | 4 | 14 | 8 | 3 | 12.5k |
| 2026-09-02 18:13 | b0b026b | Make the PWA actually installable, and fullscreen | 1.8 | 0.5 | 0.0 | **2.4** | 0.0 | +54 -8 | 4 | 5 | 4 | 2 | 7.8k |
| 2026-09-02 18:11 | f25600a | Make the web build installable (PWA) | 4.7 | 0.4 | 0.0 | **5.1** | 0.0 | +1 -1 | 1 | 4 | 3 | 2 | 4.5k |
| 2026-09-01 22:02 | 8d8bdde | Undo what the mono editor did to project.godot | 0.6 | 0.1 | 0.0 | **0.7** | 0.0 | +10 -2 | 1 | 3 | 3 | 3 | 2.5k |
| 2026-09-01 22:01 | 174cac7 | Add the Web export preset | 4.9 | 1.3 | 4.0 | **10** | 19 | +34 -0 | 1 | 25 | 22 | 2 | 17.1k |
