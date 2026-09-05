# count

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

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
