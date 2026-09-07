# tank

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## Who are you?

A tank in the bottom-left corner of the board.

## What do you do?

**Stand the mouse somewhere and click, and the tank shoots there** — a real lobbed
trajectory, an arc like the one in my drawing.

(Arrow keys move the crosshair and space fires, so the bots can play it too.)

## What is trying to stop you?

There are animals on the screen and **only one of them is different** — at least 3 of
them, all the same animal except one. I have to hit the different one.

**Animals, not people.** They were briefly adventurers and zombies, because those are the
only sprites in the kit with real animation frames. Animals won. Kenney's animal art has
no frames at all, so all the life in them is hand-animated instead — see the notes.

**No time cap, no shots cap.** Take as long as you like.

## How do you win?

Hit the odd one out and **it cries** — it droops over, shakes, sheds tears, and a voice
says "correct" — then on to the next level. Hit a wrong one and **it just laughs and
spins**, bouncing on the spot, while the voice says "wrong".

As the levels get harder **the animals start moving a bit, and there are more of them.**

## Core loop

> Spot the odd animal out → lob a shell onto it → it cries and the level advances → next
> level has more animals and they wander.

## Notes

- It cannot be lost — that is on purpose (no time cap, no shots cap). The playtest bots
  will always report "idle bot survived, the game has no teeth". That check is right about
  the facts and wrong about this game.
- Score is the only thing that moves: 100 for a level, minus 15 for each wrong animal you
  hit on the way, floor of 25.
- 3 animals at level 1, up to 6. They sway on the spot until level 3, then **hop** their
  wander rather than gliding, facing the way they are going.
- The shell is inert up to the point you aimed at, then stays live and keeps falling until
  it hits somebody or reaches the ground. So it no longer pops in mid-air on a miss — and
  a shell that sails past can still land on somebody further along, which is fair game.
- A penguin crews the tank, drawn smaller than a target and kept out of the line-up, so
  the same animal never means two things on screen.
