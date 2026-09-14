# bowling

The kit's third 3D game: real physics, one lane, nobody to beat but yourself.

## What is it called?

bowling

## Who are you?

A bowler on one lane of a neon alley, alone, chasing your own best score. There is no
opponent and no clock: ten frames, then the total goes on the high score table.

## What do you do?

Swipe up to roll. The angle of the swipe aims the ball (it has to be fairly straight: a
swipe that leans far to one side is a gutter ball), how fast you flick is how fast it
goes, and a swipe that bends makes the ball hook the same way, so you can start it left
and curl it into the pocket like a real bowler. The ball rolls, the pins tumble and take
each other out, and the pinsetter clears the fallen ones and re-spots the rest.

Keys and pad: left and right slide the ball along the foul line, A rolls it straight at a
good medium speed. That is also how the bots play it.

## What is trying to stop you?

Only the pins. A ball straight down the middle splits the rack and leaves pins standing
on both sides; the strike lives in the 1-3 pocket, just off centre, and a hooking ball
gets there with more force than a straight one. Ten frames of that, scored the real way:
a strike counts the next two balls, a spare the next one, and the tenth frame gives extra
balls to anyone who earns them. 300 is perfect.

## How do you win?

Highest score. The game ends after the tenth frame and the shell keeps your best.
There is no way to lose, by design: the `idle` bot never rolls, so it never finishes,
and that playtest check fails on purpose.

## What should it look like?

A lane at night: a polished dark lane between two glowing rails, arrows on the boards,
white pins with a red band, a glossy ball with three finger holes so you can see it roll,
and a masking unit with a row of marquee bulbs over the pin deck. The camera rides down
the lane behind the ball, watches the pins go, and glides back for the next roll. A
strip along the bottom keeps the frame marks (X, 7/, 9-) the way the overhead screen at
an alley does.

## Core loop

Aim, swipe, watch the pins go, read the strip, roll again. Twenty balls at most.
