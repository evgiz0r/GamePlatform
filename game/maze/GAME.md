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

## Two modes

The game opens on its own little screen with two buttons. Up/down + space picks one,
or tap it.

**classic** — one maze after another, side by side, each a square bigger. Everything
below is about this one unless it says otherwise.

**infinite** — mazes inside mazes. You play only small ones, 3x3 to start, but as you
play them you are **building the next size up**: a 4x4 whose every cell is one of the
small mazes. **The big one is actually made of the small ones** — not a separate maze
with the small ones drawn inside for show. Every opening in the big maze is a real
doorway in a small maze: the doorway you leave one by, facing the doorway you enter the
next one by. A cell that the big maze branches from gets a new doorway cut into its
finished maze when the building comes back to it, and a dead end of the big maze is a
maze with one doorway and a prize at the far end. Nothing of the big one is drawn ahead
of time; the thick outline that grows as you go is just the finished mazes' own walls.
Once all the cells are done the way out is cut, we **zoom out** and play the big one,
which is regular size now — walking its corridors means walking through the doorways
you made — and **you can still see the small mazes inside it**. Solve that and it
shrinks to become the first cell of the next one up, a 5x5 built out of 4x4s. And so
on, each level the size is one bigger, forever.

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

## Solve button

A **solve** button in the corner. Press it and it plays itself, forever, so I can just
watch. I want **real solving** — not the answer handed over.

It is a depth-first search walked one cell at a time. It only knows the walls of cells it
has actually stood in; of the openings it has not tried it takes the one pointing most at
the exit, and when it hits a dead end it reverses back out the way it came. Knowing where
the exit is is fair — you can see that from anywhere. Knowing which walls are in the way
would not be, and it does not.

Its route and everywhere it has been are drawn while it works.

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
- Space also starts the solver and shift stops it. That is what lets the playtest bots
  turn it on, which is the only reason this game can be checked automatically at all: 14
  mazes solved in a two-minute run, every size up to the cap.
- The maze checks itself: after every build it walks the path from the entrance to the
  exit and complains loudly if there isn't one.
- Infinite mode, how it hangs together: a plan for the big maze is carved invisibly up
  front with the same recursive backtracker, only so the play order and the far exit
  are known. The order its cells were first reached is the order you play them. A
  cell's small maze is entered on the side the carving came from and its exit is cut on
  the side the carving went next, so walking out of one doorway usually puts you at the
  next maze's doorway like classic does. After a dead end the camera jumps to wherever
  the carving went next, and the cell it branches from gets a fresh doorway cut into it,
  lit up for a moment so you see it happen. The big maze you play after the zoom-out is
  read back off the small mazes' doorways — two cells are joined only where both mazes
  have a doorway on the shared wall — and the game checks that this agrees with the plan
  and complains in the playtest report if it ever does not.
- The number of small mazes is the same as the number of cells: 16 for the 4x4, 25 for
  the 5x5 and so on. Branching does not need extra mazes, only extra doorways.
- The zoom-out is the only time the camera zoom changes, and it snaps straight back:
  the world is shrunk by the big maze's size instead, so the maze you play is always
  the same size on screen and the coordinates never run away. Old mazes just get
  smaller and smaller; ones too small to see stop drawing their walls.
- Infinite mode's small mazes are capped at 12x12 like classic, so from there on it is
  12x12s building 13x13s.
- In a playtest the mode screen is skipped and classic starts at once, because the bots
  cannot read a menu. `MAZE_MODE=infinite` in the environment picks the other mode, and
  `MAZE_MODE=menu` keeps the screen up so it can be screenshotted. A 90-second smart
  run fills the first 4x4, zooms out, solves it and gets well into the 5x5.

## Ideas for later

- A trail showing where you have already been
- Keys and doors
- Something chasing you, so the fail state arrives
- Infinite mode: a way to zoom back in and look at the mazes you built ages ago
