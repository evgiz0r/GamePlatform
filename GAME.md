# My Games

> This file is the design, in the words of whoever is making the game. The AI reads it
> before every change and it outranks the AI's own taste. Fill it in loosely — bad
> handwriting is fine, so is changing your mind.
>
> One section per game. Newest first.

# tank

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

# count

## What is it called?

count

## Who are you?

You are counting. A bunch of little critters appear at the top of the screen and you have
to work out how many there are.

## What do you do?

**Click, with the mouse, on the animal that is holding the correct number.**

(Arrow keys also work: they steer a glowing paw, and touching an animal picks it.)

## What is trying to stop you?

A **10 second countdown**. If it runs out you lose a life. Picking the wrong animal loses
a life too. **Three lives** and the run is over.

And it **gets harder — bigger numbers**. It starts with tiny numbers you can see at a
glance, and grows until there are a lot of critters and the wrong answers are only one
away from the right one.

## How do you win?

You do not — it is endless. You keep your streak going as long as you can and chase the
high score.

## What should it look like?

Bright neon. Big friendly animal badges holding big numbers.

## Core loop

> Critters appear → count them before the bar runs out → click the animal holding that
> number → the next round has more critters and closer wrong answers.

## Sound

The kit's default sound effects are **too loud**. count turns them down to 0.28 (the shell
ships at 0.8) while it is on screen and puts them back when you leave. `SFX_VOLUME` at the
top of `game/count/count.gd` is the knob. Any new game should do the same — see
`reference/README.md`.

## Notes

- **The placement is the difficulty, not the number.** The count creeps up (+1 every other
  round, capped at 12) but the arrangement gets mean fast: neat rows, then ragged rows,
  then clumps, then scattered, then jumbled, changing every two rounds. Six in a tidy row
  is trivial; the same six in two clumps with a stray one is not. The current arrangement
  is named at the bottom of the screen so you can see the difficulty rather than just feel
  it.
- A voice **says the number out loud** when you get it right — only one to ten were
  recorded, so bigger answers just get "correct".
- The critters jump for joy when you get it and slump when you do not.
- The things being counted are the small pixel animals; the numbers are held by the big
  animal badges. Two different kinds of picture on purpose — if both were badges you could
  not tell the things being counted from the answers.

## Ideas for later

- Sums instead of counting (3 + 4 → click the 7)
- A bonus life every 10 in a row
- Critters that wander around so they are harder to count
