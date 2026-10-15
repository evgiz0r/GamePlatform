# duelmaster

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

duelmaster

## The ask

"2 player on same platform. They choose a best of N, and we begin a set of infinite mini
games. Each small duel where each take turns. It can be cutting into pieces something,
shooting, dropping marble. Something measurable, that can compete with the opponent. And
then there is a score counting. But we care only about win lose per round. Or draw."

## Who are you?

One of two players, BLUE or PINK, sharing one phone (or one keyboard).

## What do you do?

Pick **best of 1 / 3 / 5 / 7**. Then duel after duel comes up, picked at random (shuffled
so none repeats until every one has had a turn). In each duel:

1. One player takes their turn. One verb: tap (or space), sometimes hold and release.
2. "Pass to PINK" screen. The other player gets **the exact same setup** -- same target,
   same speeds, same everything. That is what makes it fair.
3. Both results side by side, the closer one wins the duel. Close enough is a **draw**,
   which scores for nobody.

Who goes first alternates every duel (going second means you know the number to beat,
and the second player sees it).

Measurement only decides the duel. The set score is just duels won.

## The duels (first four)

- **marble drop** -- a dropper swings across the top; tap to let go. The marble keeps the
  dropper's sideways speed, so you have to lead it. Measured: distance from the bullseye.
- **slice** -- a log slides under a knife, faster and faster; tap to chop at the mark.
  Measured: distance from the mark.
- **stop the clock** -- stop the timer at the target time. The numbers hide after one
  second. Measured: time off.
- **curling** -- hold to charge (the meter rises and falls), release to slide the puck to
  the line. Off the end of the lane is a miss. Measured: distance from the line.

Doing nothing until the time runs out is a miss. Two misses is a draw.

## How do you win?

First to win more than half of N duels takes the set.

## Online (next, not built yet)

Agreed so far:

- "Online" button: type your name, press enter, and you join a **pool** of everyone online.
- You set your **best of N when you log in**, in case somebody challenges you.
- Tap somebody to **challenge** them; they get an **accept** prompt. If you accept, it is
  **the challenger's N**.
- Duels are played **together**: both players play the same duel at the same time on their
  own device, and it **syncs every round** -- nobody starts the next duel until both have
  finished this one and seen the verdict.
- Needs a small relay service (Firebase or Supabase, free tier), because GitHub Pages only
  serves files and cannot pass messages between two phones.

## What should it look like?

Neon on dark, like the rest of the kit. BLUE is the player colour, PINK the hazard colour.
