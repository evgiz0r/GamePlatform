# bricks

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

bricks

## Who are you?

The paddle at the bottom. Like breakout.

## What do you do?

**Swipe left and right** to move. Keep the ball up, break the wall.

## The bit I actually want

**Power-ups that drop out of the wall, once in a while.** They can make my player
**bigger** or **smaller**, or let me **shoot at the top**, and one of them lets me
**shoot three**.

**They can also be power-downs.** Some are positive and some are negative, and I want a
**different icon for positive and negative so it's noticeable** — I should be able to tell
whether to catch it or dodge it without thinking.

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
- Good: `W` wider paddle, `G` gun, `3` triple shot, `S` slower ball.
  Bad: `N` narrower paddle, `F` faster ball, `X` jams the gun.
- Opposites cancel: catching wide clears narrow, slow clears fast.
- The ball sits on the paddle between lives and launches on tap or space, or by itself
  after 1.2s so nothing can ever sit stuck waiting.
- 3 rows of bricks to start, +1 per level up to 7. From level 3 the top rows take two hits.
- **This is the first game here with a real fail state**, so the idle bot finally dies the
  way the playtest expects.

## Ideas for later

- A drop that splits the ball in two
- A brick that has to be shot rather than hit
- Keeping the gun between levels if you cleared without losing a life
