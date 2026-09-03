---
name: game-design
description: 'Turn a vague wish ("a game about my cat") into a specific, buildable 2D game. Use when starting a new game, when the user is unsure what they want, when a game is finished but boring, or when deciding what to add next. Covers: core loop, the one-verb rule, difficulty curves, scoring, failure states, juice, and scope control.'
---

# Designing a game someone actually wants to play

## Start from the fantasy, not the mechanics

When someone says "a game about my cat," they are not asking for a specification. They are
telling you the feeling they want. Ask two or three questions, no more:

1. **Who are you, and what are you doing?** ("You are a cat. You knock things off tables.")
2. **What is trying to stop you?** ("The owner comes home.")
3. **How do you know you won?** ("Survive until midnight" / "Break everything.")

If they cannot answer #2, the game has no tension and will be boring no matter how well it
is built. Push gently: *"what makes it hard?"*

Write the answers into `GAME.md` in **their words**, not yours. That file is the source of
truth and outranks your own taste.

## The one-verb rule

A first version has exactly one verb. Move. Or jump. Or shoot. Or grab.

Everything else — enemies, scoring, levels, powerups — is decoration on that verb. Games
that fail during a build usually failed because they had three verbs and none of them felt
good. If the user asks for a game with movement AND combat AND building AND crafting, build
the most important verb first and say you are doing so.

## Controls: design for a thumb, not just a mouse

This kit publishes to the web and gets installed as a phone app — assume every game will
be played on a touchscreen, not just tested with a mouse on a desktop. A control scheme
that works with a precise pointer can still be a bad one on a phone.

The recurring failure mode: **a control that puts the player's own hand over the thing
they need to watch.** Drag-to-position is the classic case — "touch the paddle/ship/character
and drag it where you want it" feels natural to design but means a finger is sitting
directly on top of the most important part of the screen at the exact moment something is
about to happen there. `bricks`' paddle went through this: dragging it worked, but the
player's finger hid the paddle right as the ball arrived. The fix was not a tuning
adjustment, it was a different control shape entirely — tap or hold *beside* the thing you
are steering, never on it, and let a direction (not a destination) do the moving.

Before locking in a control scheme, ask:
- **Does the input point ever need to be where the player needs to look?** If the answer
  is "yes, right where the action is," prefer a control that lets the player's hand stay
  off to the side — a direction, a zone, an angle — over one that plants a fingertip on
  the target.
- **Would this be too small to hit with a fingertip?** A mouse cursor is a pixel; a
  fingertip is closer to 40-50px on a real phone. A button or a hit target sized for a
  cursor can be genuinely unusable on a touchscreen even though it looks fine in a desktop
  browser.
- **Does it need the pointer to be held, or just tapped?** Both are fine, but be
  deliberate: a tap-and-release is instantaneous and easy to miss for continuous movement;
  a hold that only fires once per frame boundary can feel unresponsive. `PInput.dir()` and
  a held pointer should drive movement the same way keyboard input does — see `godot-2d`
  for the actual code pattern.

The design canvas is a fixed 640x360 space that gets stretched to fit whatever shape
screen it lands on (see `CLAUDE.md`) — do not assume the player has a mouse's precision or
a desktop's screen shape just because that is what shows up while building the game.

## The core loop

Every good small game is a 5–20 second loop the player repeats:

> see a threat → react → get rewarded or punished → slightly harder next time

Write the loop down in one sentence before writing code. If you cannot, the design is not
ready. Examples:

- *Dodge*: hazards close in → move away → grab a prize → hazards come faster.
- *Platformer*: see a gap → time the jump → land and progress → gaps get wider.
- *Shooter*: enemies advance → aim and fire → screen clears → more enemies, faster.

## Difficulty

Ramp with **time**, not with hand-authored levels. One line is usually enough:

```gdscript
var spawn_delay: float = maxf(0.25, 1.0 - elapsed * 0.02)
```

Rules that hold up:
- The first 10 seconds must be winnable by someone who has never played.
- The player should die around 60–90 seconds on a first attempt.
- Difficulty should be *visible* — more enemies, faster, bigger — not a hidden multiplier.
- Never make it harder by making the player weaker. Make the world stronger.

## Failure and reward

- A game with no failure state is a screensaver. `idle` bot must die (the playtest checks this).
- A game with no reward is a chore. Something must go up: score, size, speed, territory.
- The gap between "died" and "playing again" must be under two seconds. The shell handles
  this — do not add confirmation dialogs.

## Juice: where "fun" actually comes from

Given equal mechanics, the juicier game is the better game. Budget real effort here:

- Screen shake on impact (`Juice.hit()`)
- Squash-and-stretch on pickup (`Juice.pop(node)`)
- White flash on damage (`Juice.flash(node)`)
- Floating "+10" text (`Juice.text(...)`)
- Hitstop — a 60ms freeze on impact sells weight better than any particle
- Sound on every single player action, even placeholder

A prototype with great juice feels finished. A deep game with no juice feels broken.

## Scope: what to refuse politely

These are large. If asked, say so plainly and offer the smaller version:

| Asked for | Say instead |
|---|---|
| Multiplayer / online | "local two-player on one keyboard first?" |
| Open world | "one screen that gets harder?" |
| Inventory + crafting | "three powerups you pick up?" |
| Story with dialogue | "a line of text between levels?" |
| Procedural levels | "random spawns in a fixed arena?" |

Build the small version. It is usually the one they actually wanted.

## When the game is built but boring

Diagnose in this order — the fix is almost always near the top:

1. **No pressure.** Nothing threatens the player. Add a timer or a chaser.
2. **No feedback.** Things happen but do not *feel* like they happen. Add juice.
3. **Too slow.** Double every speed. Genuinely — double it and playtest.
4. **No ramp.** Minute five plays like minute one. Add the difficulty line.
5. **Choice-free.** The player never decides anything. Add a risk/reward: a prize in a
   dangerous spot, a powerup that costs something.

## Next-thing-to-add, in priority order

1. A reason to take a risk (a prize somewhere dangerous)
2. A second enemy that behaves differently from the first
3. A powerup that changes how you play for 10 seconds
4. A milestone that visibly changes the world (speed up, new color, boss)
