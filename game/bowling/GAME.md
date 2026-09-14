# bowling

The kit's third 3D game: real physics, one wide lane, a wall of pins or a floor with
holes in it, nobody to beat but yourself.

## What is it called?

bowling

## Who are you?

A bowler on one lane of a neon alley, alone, chasing your own best score. There is no
opponent and no clock: ten throws, then the total goes on the high score table. The
first screen asks which rack you want:

- **100 pins**: a ten-by-ten wall of them on a whole lane.
- **random ground**: past the approach, the lane floor itself is a random shape. It is
  a patchwork of big tiles grown out from the end of the approach, with holes where the
  growth wandered past, and sometimes a whole side missing; a glowing lip marks every
  edge that drops off. Twenty pins are scattered over the tiles. A ball that lands on
  a hole, or rolls into one, drops out of play and the throw is over; so do pins that
  get knocked off the edge, which counts. Clear the pins and the next throw gets a new
  floor and a new scatter.

## What do you do?

Tap where the ball should land. It flies there low and flat, lands, rolls on and ploughs
into the rack. A farther spot is a harder throw (tap the middle of the rack and it drops
straight into it; tap short and it rolls the rest of the way in: even the softest throw
carries to the rack). Hold and drag to move the
landing marker, let go to throw. The lane has bumpers, not gutters: the ball banks off
the walls and keeps most of its speed, so a spot past a wall is a bank shot into the
side of the rack.

Keys and pad: left and right slide the ball along the foul line, up and down move the
landing spot, A throws. That is also how the bots play it.

## What is trying to stop you?

Only the rack. A ball carves a channel through it and knocks down the pins in its way
and the ones they fall onto; the next throw has to go somewhere fresh. Fallen pins are
swept away after every throw, the standing ones stay exactly where they were pushed to.
Every pin down is a point. Knock down the last one and it is a bonus of half the rack
(+50 on the wall, +10 on the random ground) and a fresh rack for the throws you have
left.

## How do you win?

Highest score. The game ends after the tenth throw and the shell keeps your best.
There is no way to lose, by design: the `idle` bot never throws, so it never finishes,
and that playtest check fails on purpose.

## What should it look like?

A wide lane at night: a polished dark lane with board lines between two glowing pink
bumpers, arrows on the boards, a crowd of white pins with red bands filling the far end,
a glossy ball with three finger holes so you can see it roll, and a masking unit with a
row of marquee bulbs over the deck. The camera sits behind and above the ball looking
down the lane at about thirty-five degrees, so the whole lane is on screen to tap and
the pins at the far end are still pins; it rides down the lane behind the ball, watches
the pins go, and glides back for the next throw.
A strip along the bottom keeps the pins per throw and how many are still up.

## Core loop

Pick a game. Tap, watch the pins scatter, find the next gap (or the next island),
throw again. Ten throws.
