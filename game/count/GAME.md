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

A **countdown** (10 seconds, down to 7 on the boss). If it runs out you lose a life.
Picking the wrong animal loses a life too. **Three lives** — topped back up at the start
of every level — and the run is over.

And it **gets harder — bigger numbers**. It starts with tiny numbers you can see at a
glance, and grows until there are a lot of critters and the wrong answers are only one
away from the right one.

## Levels

> There will be levels. For each level, there is a goal within the game's rules to
> complete. For example, three consecutive right answers or reached eight in the count.
> Ten levels, increasingly hard, so that the tenth is a boss level. It would take an
> average player three to five minutes to complete it. For each level they get a small
> prize, like a cute icon, and the tenth one is a bigger prize.

| # | Goal | Herd | Prize |
|---|---|---|---|
| 1 | get 3 right | 1–4, neat rows, 3 answers | beehive |
| 2 | get 3 in a row | 2–6, neat rows | red potion |
| 3 | count 8 or more, twice | 4–9, ragged rows, 4 answers | ghost |
| 4 | 3 quick ones, under 4 seconds | 3–8, ragged rows | blue potion |
| 5 | score 70 points | 3–9, clumps | banner |
| 6 | get 4 in a row | 4–10, clumps, wrong answers closer | green potion |
| 7 | count 10 or more, twice | 6–12, scattered, 9 s | bow |
| 8 | 3 quick ones, under 4 seconds | 5–10, scattered, 8 s | princess |
| 9 | right answers add up to 40 | 6–12, jumbled | gold bar |
| 10 | **BOSS:** 5 in a row | 7–13, jumbled, mixed critters, 5 answers, 7 s | **the crown** |

Each level opens with a banner naming the goal; the goal and a row of dots for your
progress sit along the bottom while you play. Prizes pop up big in the middle and fly to a
shelf down the right-hand edge, with empty outlines for the ones still to win. Beat the
boss and a big golden crown appears with every prize you won dancing round it.

## How do you win?

Clear all ten levels. An average player takes three to five minutes; a perfect bot does it
in about a minute and a half. Score still counts (plus a bonus for each level) for the
high-score table.

## What should it look like?

Bright neon. Big friendly animal badges holding big numbers.

## Core loop

> Critters appear → count them before the bar runs out → click the animal holding that
> number → hit the level's goal → win a prize → the next level has more critters and
> closer wrong answers.

## Sound

The kit's default sound effects are **too loud**. count turns them down to 0.28 (the shell
ships at 0.8) while it is on screen and puts them back when you leave. `SFX_VOLUME` at the
top of `game/count/count.gd` is the knob. Any new game should do the same — see
`reference/README.md`.

## Notes

- **The placement is the difficulty, not the number.** The count creeps up level by level
  but the arrangement is what gets mean: neat rows, then ragged rows, then clumps, then
  scattered, then jumbled. Six in a tidy row
  is trivial; the same six in two clumps with a stray one is not.
- On the "quick ones" levels a little mark on the timer bar shows where "quick" runs out.
- All the level numbers live in the `LEVELS` table at the top of `count.gd`.
- Entering count from the menu asks for a new game or any level to start from, and "play again"
  after a game over picks up at the level you were on.
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
