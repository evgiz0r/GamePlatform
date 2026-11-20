# pong

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

pong

## Who are you?

The paddle on the left. The machine has the one on the right.

## What do you do?

**Move up and down and hit the ball back.** Where it hits the paddle decides where it goes:
the middle sends it straight back, the ends send it out steep. Moving while you hit adds a
little spin.

**Drag anywhere on the screen** -- the paddle moves by however far your finger moves, so
your thumb never has to sit on the paddle or anywhere near the ball. Up/down or W/S on a
keyboard.

## What is trying to stop you?

The machine. **First to five.** Every point it wins costs you a life (the stars), and
five gone is a lost match.

## How do you win?

Beat five machines in a row, each one a little sharper:

1. **rookie** -- slow, starts moving late, gets sloppy once the ball is quick.
2. **steady** -- a bit faster, a bit calmer.
3. **sharp** -- reads the bounce off the walls instead of chasing the ball.
4. **ace** -- quick, reads the bounce, starts early.
5. **wall** -- the last one.

Beat all five and you've won. You can start from any of them on the level screen.

## Score

- **+1** for every ball you send back.
- **+10 x level** for every point you win.
- **+50 x level** for every match you win.
- A rally of 10, 20, 30... is worth a bonus on top.

## Core loop

> Get behind the ball → pick which part of the paddle meets it → the ball comes back
> faster → somebody finally misses.

## Notes

- The ball speeds up on every hit within a rally and resets after each point. Long rallies
  get frantic, which is the point -- the machine gets sloppier the faster it goes, and so
  do you.
- The loser of each point receives the next serve.
