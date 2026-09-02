---
description: First time here? Check the setup, fix what is missing, and make a first game.
---

Work out which situation you are in **before** saying anything, by looking:

- Are there folders under `game/`?
- Is any `game/*/GAME.md` filled in?
- Does `git log --oneline | wc -l` show more than a handful of commits?

**Fresh copy** (no games, or only what the template shipped, few commits) — a new person is
holding this for the first time. Load the `getting-started` skill and follow it. Their goal
is to have a game they made, today. Do not show them the workings.

**Somebody's own kit** (games with filled-in designs, real history) — this is the owner
coming back. Skip onboarding entirely. Instead: run `tools/playtest.sh` on each game, tell
them in two lines what is here and whether it still passes, and ask what they want to
change. They know how it works. Do not explain the kit to them.

If you genuinely cannot tell, ask: *"first time with this, or is this your kit?"*
