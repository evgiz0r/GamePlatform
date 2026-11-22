# Effort: turret

How long each change took, in minutes, from the Claude Code sessions that made it (`tools/effort.py`, which says how it is counted): **agent** thinking and writing, **runs** the tests, engine and git it waited on, **you** between its reply and your next message, **active** the three together. **away** is left out: gaps over 10 minutes, and the rest of any step past its cap. Newest first; rows are kept once written.

| date (UTC) | commit | change | agent | runs | you | active | away |
|---|---|---|---|---|---|---|---|
| 2026-09-03 17:44 | 2a6e5b3 | Add a volume control on the main menu, wired to actually work in-game | 11 | 4.3 | 0.0 | **15** | 196 |
| 2026-09-03 10:56 | 440fe86 | Add turret: aim only, fires by itself, things fall on you | 4.9 | 1.9 | 0.0 | **6.8** | 82 |
