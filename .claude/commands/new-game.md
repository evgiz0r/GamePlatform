---
description: Design and build a brand new game from scratch, start to finish.
---

The user wants a new game: **$ARGUMENTS**

Follow this exactly.

## 1. Design first (do not write code yet)

Load the `game-design` skill and use it. Ask **at most three** short questions to pin down:

- who the player is and what they do
- what is trying to stop them
- how they know they won

If `$ARGUMENTS` already answers a question, do not ask it. If the user gives a vague or
silly answer, take it and run — it is their game. Never interrogate; two rounds maximum.

## 2. Write GAME.md

Record the design in **the user's own words**. Add a one-sentence core loop. Keep it short
enough that a child could read it back.

## 3. Build it

Load the `godot-2d` skill. Create `game/<name>/<name>.gd` and `game/<name>/<name>.tscn`
following the `GameMode` contract in CLAUDE.md.

Non-negotiables: read input via `PInput`, colors via `Palette.col()`, actors via `Blob`,
and call `Probe.track()` / `Probe.event()` so playtests work.

Build the **one-verb version**. Resist adding systems.

## 4. Playtest it yourself

Load the `playtesting` skill. Run:

```bash
tools/playtest.sh <name> smart 25
tools/playtest.sh <name> idle 25
```

Fix every `FAIL`, then re-run. Do not skip this step and do not report success without it.

## 5. Hand it over

Tell the user in two or three sentences: what the game is, how to play it (which keys), and
one thing they might want to change. Then stop and let them play.

Do not list everything you built. Do not propose a roadmap. They will tell you what is next.
