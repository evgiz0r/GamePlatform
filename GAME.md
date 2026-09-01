# My Games

> This file is the design, in the words of whoever is making the game. The AI reads it
> before every change and it outranks the AI's own taste. Fill it in loosely — bad
> handwriting is fine, so is changing your mind.
>
> One section per game. Newest first.

# tank

## Who are you?

A tank in the bottom-left corner of the board.

## What do you do?

**Stand the mouse somewhere and click, and the tank shoots there** — a real lobbed
trajectory, an arc like the one in my drawing.

(Arrow keys move the crosshair and space fires, so the bots can play it too.)

## What is trying to stop you?

There are **characters** on the screen and **only one of them is different** — at least 3
of them, all the same one except one. I have to hit the different one.

(They started out as the flat animal badges. Once the animated actors arrived they became
adventurers, zombies and kids instead — they walk, cheer and get hurt, which the badges
could never do.)

**No time cap, no shots cap.** Take as long as you like.

## How do you win?

Hit the odd one out and **it cries** — the hurt pose, tears, and a voice saying "correct"
— then on to the next level. Hit a wrong one and **it just laughs and spins** at you, arms
in the air, while the voice says "wrong".

As the levels get harder **the animals start moving a bit, and there are more of them.**

## Core loop

> Spot the odd animal out → lob a shell onto it → it cries and the level advances → next
> level has more animals and they wander.

## Notes

- It cannot be lost — that is on purpose (no time cap, no shots cap). The playtest bots
  will always report "idle bot survived, the game has no teeth". That check is right about
  the facts and wrong about this game.
- Score is the only thing that moves: 100 for a level, minus 15 for each wrong animal you
  hit on the way, floor of 25.
- 3 characters at level 1, up to 6. They stand still and breathe until level 3, then walk
  their wander with the walk cycle, facing the way they are going.
- The shell is inert up to the point you aimed at, then stays live and keeps falling until
  it hits somebody or reaches the ground. So it no longer pops in mid-air on a miss — and
  a shell that sails past can still land on somebody further along, which is fair game.
- A soldier stands next to the tank and works the gun. He is deliberately kept out of the
  target line-up so there are never two soldiers meaning different things.

# count

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
