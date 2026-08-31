---
name: playtesting
description: 'How to self-play a game headlessly and read the report — running bots, interpreting ASCII playfield maps, diagnosing common failures, and iterating cheaply. Use after building or changing any game, before telling the user it works.'
---

# Playtesting without eyes

The kit can play its own games. Use it before claiming anything works.

```bash
tools/playtest.sh <game> <bot> <seconds>
```

## Bots

| Bot | Plays like | Answers |
|---|---|---|
| `idle` | does nothing | Can the game be lost at all? |
| `random` | mashes buttons | Does anything crash under noise? |
| `seek` | chases prizes | Are objectives reachable? |
| `avoid` | flees hazards | Is survival possible? |
| `smart` | dodges, then collects | Is it fun for a competent player? |

**Always run `smart` and `idle`.** Together they bracket the difficulty: `idle` must die
(there is challenge) and `smart` must survive a while (it is fair).

## Reading the report

**Timeline** — first occurrence of each event with a total count. Scan for what is
*missing*: no `player_hurt` means nothing threatens the player; no `score` means no reward.

**Counts** — ratios matter more than absolutes. `hazard_spawn=27 hazard_escaped=16` means
most hazards never reached the player: too slow, or spawning in the wrong place.

**ASCII maps** — the highest-value section. Each is the playfield rendered as text:

```
+------------------------------------------------+
|.......@.......x...................x............|
|..............*.........................*.......|
+------------------------------------------------+
```

Read them spatially. They reveal things numbers cannot:

- everything clustered in one corner → spawn logic is wrong
- `@` pinned to the same edge in every frame → the player is stuck
- `*` never appearing → unreachable objective (usually also raises a warning)
- an empty map → nothing spawned, or nothing is being tracked

**Warnings** — missing sounds, actors outside the play area. Cheap to fix, usually real.

**Checks** — automatic pass/fail. A `FAIL` must be fixed before showing the user.

## Diagnosing

| Symptom | Likely cause |
|---|---|
| "no events recorded" | the game never called `Probe.event()`, or never started |
| "no node tracked as the player" | missing `Probe.track(player, "@")` |
| "idle bot survived" | no fail state — nothing can hurt the player |
| "a competent bot died in 3s" | too hard: spawn rate, speed, or the arena is too small |
| score never moved | rewards unreachable, or the collision radius is too small |
| everything in one corner | spawn position not randomized |
| the bot does nothing at all | the game reads `Input` instead of `PInput` |
| bot moves but never jumps/shoots | the game uses `just_pressed()` for that action and something is holding the button. Bot presses are pulsed via `_pulse()` in `bot.gd` for exactly this reason — if you add a policy, pulse it. |

Check that last one first whenever a bot appears passive — it is the most common cause of
a confusing report.

## Actual screenshots

Text reports are the default because they are cheap and explain causality. When you need to
see the game — checking whether art reads well, whether the layout looks right, whether
something is visually broken rather than logically broken — capture real frames:

```bash
tools/shots.sh <game> <bot> <seconds> <count>
```

Images land in `shots/` (gitignored). This runs **without** `--headless`, because the
headless display driver renders nothing and would save black frames. A window will briefly
appear on the user's screen.

Use them sparingly — an image costs several times a text report and tells you far less
about *why* something happened. Reach for a screenshot to answer "does this look right?",
never "does this work?".

## Cost discipline

Runs are cheap but not free; each report is a couple of thousand tokens.

- 20-30 second runs. Longer rarely teaches more.
- Two bots per iteration, not five.
- Change one thing, re-run, compare. Do not re-run after every edit.
- Snapshots are capped at three per run by design. Do not raise the cap to "see more" —
  read the timeline instead.

## The loop

1. Build or change the game.
2. `smart` run — is it fair and rewarding?
3. `idle` run — can it be lost?
4. Fix the top `FAIL`, then re-run only the bot that failed.
5. When both pass and the counts look healthy, hand it to the human. They are the only one
   who can tell you whether it is *fun*.
