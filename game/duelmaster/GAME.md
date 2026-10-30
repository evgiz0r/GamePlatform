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

## Online

**Switched off for now** (`ONLINE_ENABLED := false` in `duelmaster.gd`): the game opens
straight on the best-of picker and there is no "online" button. Everything below is built
and kept, ready to switch back on.

Agreed and built:

- "online" on the first screen: type your name, pick your **best of N**, press enter, and
  you join a **pool** of everyone online. (Name and N are remembered on that device.)
- Your N is what you play if somebody challenges you.
- Tap somebody to **challenge** them; they get an **accept / no thanks** prompt. If they
  accept, it is **the challenger's N**. No answer in 30 seconds and the challenge lapses.
  If two people tap each other at the same moment they just get one match.
- Duels are played **together**: both players play the same duel at the same time on
  their own device, and it **syncs every round** -- nobody starts the next duel until both
  have finished this one and seen the verdict.
- Somebody who leaves or goes silent for about 20 seconds forfeits the set.

How it works: the game is still served by GitHub Pages; only the small messages (who is in
the pool, challenges, each duel's seed and each player's result) go through a free
**Firebase Realtime Database**. `net.gd` talks to it, `online.gd` runs the pool and the
match, and `firebase-rules.json` is what to paste into the database's Rules tab.

## What should it look like?

Neon on dark, like the rest of the kit. BLUE is the player colour, PINK the hazard colour.
