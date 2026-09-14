# bowling

The kit's third 3D game: real physics, one wide lane, a hundred pins, nobody to beat but
yourself.

## What is it called?

bowling

## Who are you?

A bowler on one lane of a neon alley, alone, chasing your own best score. There is no
opponent and no clock: ten throws at a rack of a hundred pins, then the total goes on the
high score table.

## What do you do?

Tap where the ball should land. It flies there, lands, rolls on and ploughs into the
rack. A farther spot is a harder throw (tap the middle of the rack and it drops straight
into it; tap short and it rolls the rest of the way in). Hold and drag to move the
landing marker, let go to throw. The lane has bumpers, not gutters: the ball banks off
the walls and keeps most of its speed, so a spot past a wall is a bank shot into the
side of the rack.

Keys and pad: left and right slide the ball along the foul line, up and down move the
landing spot, A throws. That is also how the bots play it.

## What is trying to stop you?

Only the rack. A ball carves a channel through it and knocks down the pins in its way
and the ones they fall onto; the next throw has to go somewhere fresh. Fallen pins are
swept away after every throw, the standing ones stay exactly where they were pushed to.
Every pin down is a point. Knock down the last one and it is +50 and a fresh rack of a
hundred for the throws you have left.

## How do you win?

Highest score. The game ends after the tenth throw and the shell keeps your best.
There is no way to lose, by design: the `idle` bot never throws, so it never finishes,
and that playtest check fails on purpose.

## What should it look like?

A wide lane at night: a polished dark lane with board lines between two glowing pink
bumpers, arrows on the boards, a crowd of white pins with red bands filling the far end,
a glossy ball with three finger holes so you can see it roll, and a masking unit with a
row of marquee bulbs over the deck. The camera looks down on the lane from high behind
the ball, steeply enough that the lane reads as a flat rectangle with the whole of it on
screen to tap; it rides down the lane behind the ball, watches the pins go, and glides
back for the next throw.
A strip along the bottom keeps the pins per throw and how many are still up.

## Core loop

Aim, swipe, watch the pins scatter, find the next gap, throw again. Ten throws.
