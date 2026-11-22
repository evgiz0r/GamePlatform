# Effort: rumor

How long each change took, in minutes, from the Claude Code sessions that made it (`tools/effort.py`, which says how it is counted): **agent** thinking and writing, **runs** the tests, engine and git it waited on, **you** between its reply and your next message, **active** the three together. **away** is left out: gaps over 10 minutes, and the rest of any step past its cap. **lines** added and removed and **files** touched, leaving out generated files (baked data, the web build, imports); **steps** the times the model was called, **tools** its tool calls, **engine runs** those that ran the engine (a test, a playtest, a check), **tokens out** what it wrote (thinking included). Newest first; rows are kept once written.

| date (UTC) | commit | change | agent | runs | you | active | away | lines | files | steps | tools | engine runs | tokens out |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-09 21:46 | bc5c7a1 | rumor: one room, people ask riddles; touch-first controls | 8.1 | 2.0 | 6.0 | **16** | 0.0 | +371 -515 | 3 | 17 | 27 | 8 | 36.7k |
