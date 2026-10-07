# bowling

The kit's third 3D game: real physics, one wide lane, twelve levels that get wilder as
they go.

## What is it called?

bowling

## Who are you?

A bowler on one lane of a neon alley, alone, working through twelve layouts. There is no
opponent and no clock: each level is a pin target and a handful of throws to reach it.

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

Each throw starts lined up on the thickest bunch of standing pins, so the keys (and the
bots) begin from a sensible guess; a tap can aim anywhere.

## Levels

Twelve, picked on the start screen when you enter the game or played in order. Each one is a layout plus a
target: "knock down 14 pins in 5 throws". The level name and target come up as a banner;
the strip along the bottom keeps the score against the target, the pins per throw, and
the stars at the top are the throws left. Losing a level ends the run, and "play again"
starts on the level you lost.

1. **warm-up**: the plain 5x4 block.
2. **the triangle**: a classic fifteen-pin triangle, and you need every pin.
3. **posts**: three glowing pillars in the lane: thread them or bank round them.
4. **the funnel**: two angled rails that steer the ball to the middle.
5. **magnet lane**: magnetised boards (yellow chevrons) drag the rolling ball right.
6. **split**: a long divider down the middle and a rack on each side.
7. **the chasm**: no lane in the middle third. Land beyond the gap or the ball is gone.
8. **sweepers**: two blocks sliding side to side across the lane. Time it.
9. **the deck**: the pins stand on a raised deck. Take the ramp up, or loft it on.
10. **spinners**: two bars turning in front of a scattered rack.
11. **islands**: the lane is full of holes, the boards drag left, and a moat guards the rack.
12. **chaos**: a kicker ramp to jump the chasm, a sweeper, two fast spinners, a magnet
    drag and twenty-eight scattered pins.

## What is trying to stop you?

The layout and the throw count. A ball carves a channel through the pins and knocks
down the ones in its way and the ones they fall onto; the next throw has to go
somewhere fresh. Fallen pins are swept away after every throw, the standing ones stay
exactly where they were pushed to. Posts, rails, sliders and spinners knock the ball off
line; holes swallow it (and any pin knocked into one counts as down).

## How do you win?

Reach the target on every level. Every pin is a point, clearing a level is 25 x its
number plus 15 for every throw left over, and every pin of a full layout in one throw is
a strike, +20. Run out of throws short of the target and it is game over.
The `idle` bot never throws, so it never runs out, and that playtest check fails on
purpose: there is still no clock.

## What should it look like?

A wide lane at night: a polished dark lane with board lines between two glowing pink
bumpers, arrows on the boards, a crowd of white pins with red bands filling the far end,
a glossy ball with three finger holes so you can see it roll, and a masking unit with a
row of marquee bulbs over the deck. The camera sits behind and above the ball looking
down the lane at about thirty-five degrees, so the whole lane is on screen to tap and
the pins at the far end are still pins; it rides down the lane behind the ball, watches
the pins go, and glides back for the next throw.
A strip along the bottom keeps the level, pins down against the target and pins per
throw. Obstacles glow in their own colours: pink posts and spinners, yellow sliders,
pink-rimmed holes, pale ramps and a raised deck with a green lip.

## Core loop

Read the layout, tap, watch the pins scatter, find the next gap, throw again before the
throws run out. Then a wilder layout.
