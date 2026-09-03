# bricks

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

bricks

## Who are you?

The paddle at the bottom. Like breakout.

## What do you do?

**Tap or hold to one side of the paddle to move it that way.** Not a drag — swiping meant
dragging a finger right over the paddle, which hides it right when you need to see it
most. Tap right of it to go right, left of it to go left. Keep the ball up, break the
wall.

## The bit I actually want

**Power-ups that drop out of the wall, once in a while.** They can make my player
**bigger** or **smaller**, or let me **shoot at the top**, and one of them lets me
**shoot three**. One of them gives me **multiple balls flying to different directions**.

**They can also be power-downs.** Some are positive and some are negative, and I want a
**different icon for positive and negative so it's noticeable** — I should be able to tell
whether to catch it or dodge it without thinking.

**Blocks of different types.** Different colours for something that takes 1 hit and
something that takes 2. Some blocks **can't be destroyed** — they just sit there. Some
blocks **explode**, taking their neighbours with them.

**Some more graphics, a background, and a little music.** First attempt looped a short
jingle from the kit's stings — that got old fast and was pulled back out. Now playing a
real composed track ("Peaceful 1am in May") instead of a repeating sting. See Notes.

## What is trying to stop you?

The ball falling past me. **Three lives.** Miss three times and it's over.

## How do you win?

Clear the wall and the next level builds a bigger one. Chase the score.

## Core loop

> Break bricks → something falls out → decide in a split second whether to catch it or get
> out of its way → the wall gets deeper.

## Notes

- **Positive drops are diamonds with a `+`; negative drops are squares with a `-`.** Shape
  *and* colour *and* the sign all say the same thing, so it still reads if you cannot pick
  the colours apart. A letter underneath says which one it is.
- Good: `W` wider paddle, `G` gun, `3` triple shot, `S` slower ball, `M` two more balls.
  Bad: `N` narrower paddle, `F` faster ball, `X` jams the gun.
- Opposites cancel: catching wide clears narrow, slow clears fast.
- The ball sits on the paddle between lives and launches on tap or space, or by itself
  after 1.2s so nothing can ever sit stuck waiting.
- 3 rows of bricks to start, +1 per level up to 7.
- **Four kinds of brick.** Plain (1 hit, colour rotates by row), tough (2 hits, one solid
  colour, cracks after the first hit), steel (hatched, never breaks — the ball just bounces
  off it forever), bomb (bright with a spark on it — breaking it takes every non-steel
  brick near it with it, and if one of THOSE is also a bomb, it keeps going). Steel and
  bomb start turning up from level 2, sparsely at first. Steel never counts towards
  clearing a level, so a wall with one in it can always still be finished.
- **Controls went through two swipe designs before landing here.** First, a straight drag
  (paddle snaps under your finger) — a single tap anywhere yanked the paddle across the
  whole field, since it chased the exact touch point. Fixed that by tracking the drag
  relative to where it started instead of the raw touch position. Still bad: dragging
  still meant a finger sitting right on top of the paddle, hiding it exactly when the ball
  was arriving. The real fix was dropping "chase the touch point" entirely — holding a
  point now only sets a DIRECTION relative to wherever the paddle currently is, and the
  paddle stops with a visible gap once it is safely past the paddle's own edge, so a hand
  resting to one side never covers the thing it is steering.
- **The multi-ball drop** fans two new balls out of whichever ball is currently in flight,
  same speed, off to either side. Losing one ball while others are still up does not cost a
  life — only running out of balls entirely does. Capped at 5 balls at once.
- A soft glow along the side walls and behind the wall, and each ball leaves a short fading
  trail.
- **Background music is "Peaceful 1am in May" by TAD** (CC-BY 3.0 — credited in
  `assets/CREDITS.md`), not one of the kit's short jingles looped on repeat. Quieter than
  the sfx, same "scale whatever the setting already is" trick as the sound effects.
- **A sound on/off toggle sits in the corner at all times** — main menu or mid-game, no
  need to back out to reach it. That is a shell-level thing now (`Flow`), not specific to
  this game, so every game gets it automatically.
- **This is the first game here with a real fail state**, so the idle bot finally dies the
  way the playtest expects.

## Ideas for later

- A brick that has to be shot rather than hit
- Keeping the gun between levels if you cleared without losing a life
- A drop that shrinks or grows the ball itself, not just the paddle
