# drop

The kit's first 3D game. Built to teach the platform 3D: the shell got `GameMode3D`
(`shell/game_mode_3d.gd`) and this game is the proof it works.

## What is it called?

drop

## Who are you?

The sky. A little pocket monster hovers up there, right where you point, breathing gently:
a yellow one with tall pointy ears and a glowing antenna, a blue water blob with a fin, a
pink bear with a flame on its tail, a green pup with a leaf growing out of its head, a
spiky ball, an owl chick, a big flat sleepy one, a fluffy cloud with wings.

> Change the droppable objects to renders of Pokemon. Make the size a little bit smaller.

Real Pokemon belong to Nintendo and this game is published on the web, so these are our own
monsters instead -- built from spheres and cones in code, coloured by palette role so
`/look` reskins them, and about three quarters the size of the cars and pans they replaced.
They squash flat and spring back when they land.

## What do you do?

Tap somewhere on the square and it falls there, for real (it tumbles, bounces, lands).
Anyone under it gets squashed. The next thing appears straight away. Arrow keys aim too,
A drops. No rotating: it is slop dropping, the thing spins on its own.

## What is trying to stop you?

People. They stroll in from the left or right edge of the square and cross to the other
side -- never popping up in the middle -- faster and more of them as time goes on. Every one that makes it across costs a life. Three lives.

## Levels

> Apply the same logic as count: levels, each with a goal. Invent three or four more
> objectives and mix them across 15 levels, the last one really hard. A level select on
> the main menu so I can start at any of the 15. A timed version, and a limit on how many
> things you can throw on some levels -- so you have to be economical about where you
> drop, and it is not spammable -- but not on every level.

The goals, mixed and stacked:

- **squash** N people
- **combo** -- N drops that land on two or more at once (group levels send people in twos
  and threes so this is possible)
- **streak** -- N hits in a row; a drop that squashes nobody resets it
- **survive** -- hold the square for N seconds
- on top of any of those: **a clock**, **a limited number of drops**, and **people
  wearing halos** you must not squash (squash one and it costs a life; they are allowed to
  cross)

| # | Goal | Extra |
|---|---|---|
| 1 | squash 5 | slow, sparse |
| 2 | squash 10 | |
| 3 | squash 8 | 40 second clock |
| 4 | squash 6 | only 10 drops |
| 5 | 2 double squashes | people walk in groups |
| 6 | hold out 40 seconds | busier, faster |
| 7 | squash 10 | haloes |
| 8 | 4 hits in a row | |
| 9 | squash 10 | 18 drops, 50 second clock |
| 10 | 3 double squashes | 15 drops |
| 11 | squash 12 | haloes, 45 second clock |
| 12 | 5 hits in a row | haloes, fast |
| 13 | hold out 60 seconds | haloes, packed |
| 14 | 4 double squashes | 60 second clock |
| 15 | **FINAL:** squash 20 | 32 drops, 75 second clock, haloes, groups, fast |

Three lives, topped up at the start of every level. People freeze while a level banner is
up. Each level won gives a small prize that flies to a shelf down the right edge; winning
the last gives a big golden crown with every prize you won dancing round it. Running out
of time or drops, or of lives, ends the run -- and "play again" picks up at the level you
were on, not level 1. The "levels" button beside drop on the menu starts at any level.

Tuned against a simulated player who taps about once a second and lands roughly two in
three: a run from level 1 gets to level 12 or 13 in about three and a half minutes, and
the final level is a coin flip for a good player. All the numbers live in the `LEVELS`
table at the top of `drop.gd`.

## How do you win?

Clear all fifteen. Score still counts for the high-score table: 10 a squash, landing on
two or three at once pays 10 + 20 + 30, and each level cleared adds 50 x its number.

## What should it look like?

A little town square at night: houses behind, trees down the sides, street lights on the
corners, a glowing kerb, real low-poly people walking. Monsters that have landed sit there
a couple of seconds, then sink into the ground.

## Core loop

Point, drop, squash, next thing. Hit the level's goal, win a prize, next level. Miss too
many and they walk right past you.
