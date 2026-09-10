# planets

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## Who are you?

A tank sitting on a planet. **Like Scorched Earth, but it's planets and gravity.**

## What do you do?

Aim and fire. The planets have gravity which affects the bullets (and the tanks),
so the shell bends around them -- a shot can curve right round a planet and land on
the far side, like in my drawings. **The gravity is strong**, and a long shot can go
out past the edge of the screen and come back (an arrow on the edge shows where it
is) -- but it must not take too long: gravity is **even stronger further away** than
a real planet's would be, so a shot turns round quickly. A shell that gets itself into
orbit is cool, but it has a fuse: after eight seconds **it just explodes wherever it
is**, and a shell that stays off screen for more than about three seconds is lost.

**The view is zoomed out** so there is more space round the planets and aiming on a
phone is not cramped against the edge. A drag of about 100 px is full power.

**The shot does an AOE explosion.** Anything close to where it lands gets hurt, and
the planet gets hurt too: the blast removes a chunk of it. If the ground under a tank
is blown away, **the tank falls** down to whatever is left -- it does not hang in the air.

**Tap (or click) anywhere and the aim point moves there** -- further from the tank is
more power. **Shooting is a separate control**: the big FIRE button bottom right, or
tap your own tank, or space. **Drag to move around the map.** (Arrow keys / WASD
nudge the aim point too, so the bots can play it.)

**The map is bigger than the screen** -- one and a half screens each way, not too big
-- and it has limits: you can't scroll past the edge. When you shoot, the camera follows
the shot if it goes off screen. The enemy tank may be off screen; you have to find it.
Your turn always starts back at your own tank.

## What is trying to stop you?

The enemy tank shoots back, and it gets more accurate every time it misses you. **Both
tanks have HP**, shown as **two bars along the top, Tekken style** (yours left, the
enemy's right), and don't die from one hit: **the closer the blast, the more damage**
-- a direct hit takes 60 of your 100, a blast at the edge of its range takes 12. You also have fifteen seconds per shot before the turn passes. Gravity is
the real enemy: your own shell can come round and hit you.

## How do you win?

Hit the enemy tank until its HP is gone; then the next level. Level 1 is one big planet
with both tanks on it (my first drawing). **After the first level the layouts are
randomized** (later maybe all of them): **at least 4 planets, various sizes**, and
**the two tanks somewhat apart** from each other. More planets as the levels go up.

## Core loop

> Drag to aim → watch the shell bend round the planets → hit the enemy or get shot at →
> next level has more planets in the way.

## Later (not built yet)

- Planets can get moved (they can already be chewed up).
- The tanks can fly and land on other planets.

## Notes

- The playtest bots aim straight at the enemy tank, which gravity punishes, so an
  honest `smart` run rarely scores. Set the env var `PLANETS_AUTOAIM=1` and the bot
  is handed the solved aim point instead, which exercises level progression and the
  random generator. Humans never see that.
- Every generated level is checked to be solvable from both sides with the same solver
  the enemy uses, so there is always a shot.
- Gravity is 1/r^2 out to 1.5x a planet's radius and only 1/r beyond that, so nothing
  ever really escapes. Shells explode after eight seconds wherever they are, may wander
  700 px off screen, and count as lost after three seconds off screen in total.
- The map is 1440x810 behind a camera at 2/3 zoom, so the 640x360 screen shows a
  960x540 window of it and everything in the code is in map pixels. The HUD (HP bars,
  level, prompt, FIRE) is drawn in that same `_draw` but anchored to the camera. Random
  levels put the two home planets in the outer thirds at least 720 px apart, then fill
  in 3-7 more of assorted sizes.
- HP is restored to full at the start of every level, Scorched Earth style: a level
  is a duel, not attrition across the whole run.
- A planet is a radial heightmap (144 spokes). A blast carves each spoke back to where
  it first enters the crater circle, so craters are bowls, never caves. Gravity keeps
  the planet's original mass; only the ground moves. Tanks stand on the live surface
  and fall straight toward the centre when it drops.
- Your last shot's path stays on screen, faintly, until you fire again -- that is how
  Scorched Earth let you walk your shots in, and with curved arcs it matters more.
- The enemy's opening shots are deliberately off by a margin (never dead on), and it
  closes in by about a third with every miss. Later levels open tighter.
- Speeds sit around escape speed on purpose (about 290 px/s off the big planet): shots
  much faster than that fly nearly straight and stop being interesting.
