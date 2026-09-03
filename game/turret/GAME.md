# turret

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

turret

## Who are you?

A tank on the bottom. It does not move.

## What do you do?

**I control just the angle, left and right.** Nothing else. **It shoots every second** on
its own — I do not press fire.

Hold anywhere and the barrel swings towards your finger. Left and right work too. Same
kind of control as bricks: you steer one thing and the game does the rest.

## What is trying to stop you?

**Enemies falling from the sky.** Anything that reaches the ground costs a life. **Three
lives.**

## How do you win?

You do not — they keep coming, faster and more often. Chase the score.

## Core loop

> Something falls → swing the barrel under it → the gun goes off on its own → hit it
> before it lands, or lose a life.

## Notes

- One shot a second is the whole tension: you cannot spray, so a wasted shot is a real
  cost and the aim has to be right before the gun goes off.
- A faint line shows where the barrel is pointing. Without it you are guessing.
- Falls start at 34px/s and build to 96. A new one arrives every 2s at first, down to
  every 0.85s — deliberately close to the one-per-second fire rate, so eventually more
  arrive than you can shoot.
- Enemies drift sideways as they fall, so leading them matters.

## Ideas for later

- A big one that takes several hits
- Something that drops a bomb on the turret instead of landing
- A shot that fires two barrels at once
