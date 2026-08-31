---
description: First time here? Check the setup, fix what is missing, and make a first game.
---

Onboard this user. Load the `getting-started` skill and follow its tone: one instruction at
a time, no jargon, no ten-step lists.

## 1. Check before instructing

Actually verify these rather than asking. Report only what needs action.

```bash
git --version
ls project.godot game/ assets/
echo "GODOT=${GODOT:-unset}"
"${GODOT:-godot}" --version 2>/dev/null || echo "godot not runnable"
```

- **Godot missing or not runnable** → walk them through the download. Stress the
  **standard** build, not .NET. Stop until it works.
- **`GODOT` unset** → ask for the path and have them export it. Self-play needs it.
- **Everything present** → say so in one line and move on. Do not narrate checks that passed.

## 2. Prove it works

Run the starter game headlessly — this validates the whole toolchain without them having
to look at anything:

```bash
tools/playtest.sh dodge smart 10
```

If that produces a report, the setup is good. If it fails, fix that before anything else;
every later step depends on it.

Then tell them to open the project in Godot (Import → select `project.godot` →
Import & Edit → **F5**) and play *dodge* for ten seconds, so they know what "working"
looks like.

## 3. Make something

Ask what they want to make. If they hesitate, ask what their favourite animal is and build
around the answer — do not offer a menu of genres.

Then run the `/new-game` flow.

## 4. Leave them somewhere safe

Once a game runs, commit it so they have a fallback, and tell them two things:

- say **"undo the last change"** if anything breaks
- their game lives in `game/`; everything else is machinery they can ignore

Keep the whole exchange short. The goal of a first session is that something they
described appeared on screen — not a finished game.
