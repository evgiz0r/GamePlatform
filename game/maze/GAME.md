# maze

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

maze

## Who are you?

A dot in a maze.

## What do you do?

**Get out.** You are **on the grid** — one cell at a time, never halfway through a wall.
Tap where you want to end up and you run down that line until you get there or a wall
stops you. Arrow keys work too.

## What is trying to stop you?

The maze. And it **gets harder** — every maze is one square bigger than the last.

## The bit I actually want

**You watch it generate.** The maze carves itself in front of you and **you cannot move
until it has finished**. Then you solve it. Then the next one builds itself. Forever.

The way **out** of one maze **becomes the way in** to the next, so leaving by the right
edge means arriving at the left of the next one. In and out are otherwise random.

**I want to see more than one maze at once.** The mazes sit side by side in one world, so
the one I just escaped is still on screen behind me and I can see the recursion. So the
current maze takes about half the screen rather than all of it, and the camera pans across
when a new one starts.

**The exit is on a far wall.** Not two steps from the entrance — it should be the long way
round.

## Core loop

> Watch it build → run the corridors → step out of the doorway → a bigger one builds
> itself.

## Notes

- No lives, no timer, no fail state. On purpose. The playtest bots will report "idle bot
  survived, the game has no teeth" and they are right about the facts.
- 3x3 to start, +1 each maze, capped at 12x12. Lower than it was, because the maze is only
  half the screen now and the cells would get too small to see.
- Every maze is the same size in world units whatever its cell count, so the camera only
  ever slides — it never zooms. The cells just get smaller.
- The exit is chosen as the border cell **furthest from the entrance by corridor
  distance**. A random exit was often a couple of steps away, which made the maze
  pointless.
- The maze checks itself: after every build it walks the path from the entrance to the
  exit and complains loudly if there isn't one.

## Ideas for later

- A trail showing where you have already been
- Keys and doors
- Something chasing you, so the fail state arrives
