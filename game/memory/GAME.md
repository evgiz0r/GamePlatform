# memory

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

memory

## Who are you?

You are remembering. A shape appears for a second, then it is gone, then you have to say
what it was.

## What do you do?

**You see a shape for a second. Then you have to choose.**

You have some time that you see it, and then you wait some time, and then you choose one
of the possible answers.

(Click a card with the mouse or tap it. Arrow keys also work: they steer a glowing
cursor, and touching a card picks it.)

## What is trying to stop you?

Time, both ways. The look is short and the wait is long, and once the cards are out there
is a countdown to pick one. Running out, or picking wrong, loses a life. **Three lives**
and the run is over.

And it **gets harder: you need to remember a series of shapes**, not just one. The row
gets longer, the look gets shorter, the blank wait gets longer, and the wrong answers get
closer to the right one.

## How do you win?

You do not. It is endless. Keep the streak going, chase the high score.

## What should it look like?

Neon shapes on a dark screen. Big on the stage, small on the cards.

## Core loop

> Shapes appear → they vanish → blank wait → cards come out → pick the card with the
> same row → longer row, shorter look, longer wait, meaner wrong answers.

## Notes

- **Four things get harder, one at a time**, so each step is felt rather than everything
  ramping at once:
  - the row grows by one every two rounds, up to seven;
  - the look shrinks a little every round, never under about half a second per shape;
  - the blank wait grows from half a second to four seconds;
  - the wrong cards start as random rows, become the right row with one shape changed
    from round four, and from round eight can also be the right row with two neighbours
    swapped.
- **Colour joins in from round five.** Until then each shape always has its own colour so
  there is only the shape to remember; after that any shape can be any of four colours,
  and a wrong card can be the same shape in the wrong colour.
- Two cards for the first two rounds, three until round five, four after.
- Points are ten per shape in the row plus the seconds left on the pick countdown.
- The shapes land one after another with a rising click, and the blank shows three slow
  dots so it does not look like the game froze.
- The kit's default sound is too loud, so memory scales it down to 0.35 of the setting
  while it is on screen and puts it back when you leave.
- **For playtests, wrong cards are tracked as `o`, not `x`.** Tagging them as hazards was
  tried: the smart bot then flees them on its way to the right card and times out once
  there are four cards in a row. So the report always warns that nothing hostile was
  tracked -- that is expected for this game, not a bug to fix.

## Ideas for later

- Show the shapes one at a time instead of all at once, Simon style
- A bonus life every ten in a row
- Sounds as things to remember, not just shapes
