# My Game

> This file is the design, in the words of whoever is making the game. The AI reads it
> before every change and it outranks the AI's own taste. Fill it in loosely — bad
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

## Ideas for later

- Sums instead of counting (3 + 4 → click the 7)
- A bonus life every 10 in a row
- Critters that wander around so they are harder to count
