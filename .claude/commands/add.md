---
description: Add one new thing to the current game — an enemy, a powerup, an obstacle, a rule.
---

Add this to the game: **$ARGUMENTS**

1. Read `GAME.md` and the current game's `.gd` file first.
2. Add **only** what was asked. Do not refactor, do not "improve" nearby code, do not add
   a second thing because it seemed natural.
3. Follow the rules in CLAUDE.md: `PInput`, `Palette.col()`, `Blob`, `Probe.track()` and
   `Probe.event()` for anything new that moves or matters.
4. Give it juice — a sound, a pop, a flash. A new thing that lands with no feedback feels
   broken even when the logic is correct.
5. Playtest with `smart` for 25 seconds. If the addition made the game unfair, tune it
   before reporting back.
6. Update `GAME.md` with one line describing the new thing.

Report in one or two sentences what was added and what it does. Nothing more.
