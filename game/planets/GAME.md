# planets

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## Who are you?

A tank sitting on a planet. **Like Scorched Earth, but it's planets and gravity.**

## What do you do?

Aim and fire. The planets have gravity which affects the bullets (and the tanks),
so the shell bends around them -- a shot can curve right round a planet and land on
the far side, like in my drawings.

**Drag anywhere on the screen** in the direction you want to shoot -- a longer drag is
more power -- and let go to fire. A plain tap fires the same shot again. (Arrow keys /
WASD nudge the aim point and space fires, so the bots can play it too.)

## What is trying to stop you?

The enemy tank shoots back, and it gets more accurate every time it misses you. Three
hits and you are gone. You also have ten seconds per shot before the turn passes.
Gravity is the real enemy: your own shell can come round and hit you.

## How do you win?

Hit the enemy tank and it explodes; then the next level. Level 1 is one big planet
with both tanks on it (my first drawing). Level 2 is two planets with a small one in
between that bends the shot (my second drawing). After that the layouts are random and
there are more planets and moons.

## Core loop

> Drag to aim → watch the shell bend round the planets → hit the enemy or get shot at →
> next level has more planets in the way.

## Later (not built yet)

- Planets can get destroyed or moved.
- The tanks can fly and land on other planets.

## Notes

- The playtest bots aim straight at the enemy tank, which gravity punishes, so an
  honest `smart` run rarely scores. Set the env var `PLANETS_AUTOAIM=1` and the bot
  is handed the solved aim point instead, which exercises level progression and the
  random generator. Humans never see that.
- Every generated level is checked to be solvable from both sides with the same solver
  the enemy uses, so there is always a shot.
- Shells live at most seven seconds; a real orbit is possible but it eventually falls.
- Your last shot's path stays on screen, faintly, until you fire again -- that is how
  Scorched Earth let you walk your shots in, and with curved arcs it matters more.
- The enemy's opening shots are deliberately off by a margin (never dead on), and it
  closes in by about a third with every miss. Later levels open tighter.
- Speeds sit around escape speed on purpose (about 240 px/s off the big planet): shots
  much faster than that fly nearly straight and stop being interesting.
