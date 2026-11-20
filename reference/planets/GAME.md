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

**The shot does an AOE explosion.** Anything close to where it lands gets hurt, and
the planet gets hurt too: the blast removes a chunk of it. If the ground under a tank
is blown away, **the tank falls** down to whatever is left -- it does not hang in the air.

**Tap (or click) anywhere and the aim point moves there** -- further from the tank is
more power. **Shooting is a separate control**: the big FIRE button bottom right, or
tap your own tank, or space. **Drag to move around the map.** (Arrow keys / WASD
nudge the aim point too, so the bots can play it.)

**Next to FIRE you can see the strength and the angle**, and there are two scrollers
there to set them by hand as well as with the mouse: drag along the angle wheel or
the power wheel and the number scrolls (half a degree, or half a percent, per pixel).
Angle is 0 to 360 anticlockwise, 90 is straight up; power is 0 to 100.

**The map is bigger than the screen** -- one and a half screens each way for two tanks,
more for more tanks, not too big -- and it has limits: you can't scroll past the edge.
When you shoot, the camera follows the shot if it goes off screen. The enemy tank may
be off screen; you have to find it. Your turn always starts back at your own tank.

**The view is zoomed out** so there is more space round the planets and aiming on a
phone is not cramped against the edge.

## The main screen

The game opens on its own menu:

- **regular game** -- you against one AI, what we had.
- **custom game** -- I choose how many tanks there are (2 to 6, the `-`/`+` buttons),
  and the map is made big enough for them. You are one, the rest are AIs, last tank
  standing wins the level.
- **AI plays your tank too** -- a toggle. On, there is no human: the game auto plays
  and you just watch (the camera goes to whoever is shooting).
- **shot speed 1x / 2x** -- a speedup option for the shot animation only, not the
  aiming. Also a small `1x`/`2x` button above FIRE during play.

Choices are remembered between runs.

## What is trying to stop you?

The enemy tanks shoot back, and each gets more accurate every time it misses. **All
tanks have HP**, shown as **bars along the top** (Tekken style with two tanks: yours
left, the enemy's right; a row of small bars with more), and don't die from one hit:
**the closer the blast, the more damage** -- a direct hit takes 60 of your 100, a blast
at the edge of its range takes 12. You also have fifteen seconds per shot before the turn
passes. Gravity is the real enemy: your own shell can come round and hit you.

## How do you win?

Be the last tank standing; then the next level. **The layouts are randomized from
level 1**: **at least 4 planets, various sizes**, and **the tanks somewhat apart** from
each other. More planets as the levels go up.

**Some planets have small moons** that **slowly rotate around them**. They have no
gravity of their own, but a blast chews them up and a couple of hits destroys one
completely. Not too many.

## Core loop

> Tap to aim → FIRE → watch the shell bend round the planets and blow a hole in
> something → the others shoot back → last one standing goes up a level.

## Later (not built yet)

- Planets can get moved (they can already be chewed up).
- The tanks can fly and land on other planets.

## Notes

- The playtest bots aim straight at the nearest enemy tank, which gravity punishes, so
  an honest `smart` run rarely scores. Set the env var `PLANETS_AUTOAIM=1` and the bot
  is handed the solved aim point instead, which exercises level progression and the
  random generator. Humans never see that. In a playtest the menu is skipped and the
  regular game starts at once, because the bots cannot read a menu.
- Every generated level is checked to be solvable with the same solver the AIs use:
  each tank must be able to hit its nearest neighbour. A cheaper solver grid is used for
  that check than for the AIs' actual shots.
- Your last shot's path stays on screen, faintly, until you fire again -- that is how
  Scorched Earth let you walk your shots in, and with curved arcs it matters more.
- An AI's opening shots are deliberately off by a margin (never dead on), and it closes
  in by a quarter with every miss. Later levels open tighter. Against you, AI shells do
  half damage on level 1 and full damage from level 6.
- A shell cannot hurt its own shooter in its first third of a second, so shooting the
  ground at your own feet costs the turn, not a life. It still digs the crater.
- Speeds sit around escape speed on purpose (about 300 px/s off the big planets): shots
  much faster than that fly nearly straight and stop being interesting.
- Gravity is 1/r^2 out to 1.5x a planet's radius and only 1/r beyond that, so nothing
  ever really escapes. The solver prefers quick lobs over long loops, which are far too
  sensitive to noise and fresh craters.
- A planet is a radial heightmap (144 spokes). A blast carves each spoke back to where
  it first enters the crater circle, so craters are bowls, never caves. Gravity keeps
  the planet's original mass; only the ground moves. Tanks stand on the live surface
  and fall straight toward the centre when it drops.
- Moons are planets with zero gravity mass that circle a parent on a ring checked to
  clear everything else. They are always last in the list so destroying one never
  shifts the home indices the tanks refer to. The solver treats them where they are at
  the moment of the shot; they move slowly enough that the blast radius covers it.
- The map is 1440x810 for two tanks, scaled by sqrt(tanks/2), behind a camera at 2/3
  zoom, so the 640x360 screen shows a 960x540 window of it. The HUD (HP bars, level,
  prompt, FIRE, wheels, menu) is drawn in the same `_draw` but anchored to the camera.
  The shell reads a game's `play_area` before `_ready`, so it is set in `_init`, and the
  shell's Backdrop is resized by hand when a custom map is bigger.
- HP is restored to full at the start of every level, Scorched Earth style: a level is a
  duel, not attrition across the whole run. Surviving a level is worth 100.
