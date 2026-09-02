# maze

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

maze

## Who are you?

A dot in a maze.

## What do you do?

**Get out.** Move along a line — hold a direction, or hold your finger somewhere and you
run that way down the corridor until a wall stops you.

## What is trying to stop you?

The maze. And it **gets harder** — every maze is one square bigger than the last.

## The bit I actually want

**You watch it generate.** The maze carves itself in front of you and **you cannot move
until it has finished**. Then you solve it. Then the next one builds itself. Forever.

The way **out** of one maze **becomes the way in** to the next, so leaving by the right
edge means arriving at the left of the next one. In and out are otherwise random.

The view stays on the current maze — centred, and scaled so the whole thing fits the
screen however big it gets.

## Core loop

> Watch it build → run the corridors → step out of the doorway → a bigger one builds
> itself.

## Notes

- No lives, no timer, no fail state. On purpose. The playtest bots will report "idle bot
  survived, the game has no teeth" and they are right about the facts.
- 3x3 to start, +1 each maze, capped at 15x15 (past that the cells are too small to see).
- The maze checks itself: after every build it walks the path from the entrance to the
  exit and complains loudly if there isn't one.

## Ideas for later

- A trail showing where you have already been
- Keys and doors
- Something chasing you, so the fail state arrives
