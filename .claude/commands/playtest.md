---
description: Self-play a game headlessly and report what is wrong with it.
---

Playtest: **$ARGUMENTS** (game name, optionally followed by a bot and a duration)

Load the `playtesting` skill.

If no game was named, use the most recently modified folder under `game/`.

Run two bots unless the user asked for something specific:

```bash
tools/playtest.sh <game> smart 25
tools/playtest.sh <game> idle 25
```

Then report to the user in plain language — no raw report dumps, no ASCII maps pasted
back. Four lines at most:

1. Whether it is playable, too hard, or too easy, and how you know.
2. The single most important problem.
3. What you propose to change.
4. Ask whether to make that change.

If everything passes, say so plainly and tell them it is ready to play — the only thing a
bot cannot judge is whether it is fun.
