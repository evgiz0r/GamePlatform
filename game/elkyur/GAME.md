# elkyur

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

elkyur

## Who are you?

One of **2 players on grid paper**. You don't know the map. You play against an AI.

## What do you do?

You can move **left/right/up/down**. **There are walls** -- the edge between two grid
squares can be a wall and you can't pass it. Each player has **some amount of dynamite
and then ammo**.

**Each turn you can either use ammo, dynamite or move in some direction.**

**If you hit a wall, you skip that turn and you gain information that there is a wall.**

## What is trying to stop you?

The other player. **You take turns.** You **don't know the relative position of the
second player** to you -- you see **your perspective and his perspective**, and it is
your task to **map them onto the global map**, which is also unknown to you. You do know
the limits: the map is a fixed size (10 x 10 here; the chat said "20x20 or something").

**You explore the world and have the same information as the opposing player.**
Player vs AI, **3 difficulties**.

## How do you win?

Figure out where you and your opponent are, then either **kill him** or **find the
treasure**.

## What should it look like?

Grid paper in the dark. Your map on the left, his on the right.

## Core loop

> Pick a direction and walk, shoot or blast → learn "ok" or "wall" (and he learns it
> too) → watch his move on his own little map → slide his map over yours until the walls
> agree → once you know where he is, line up and shoot, or beat him to the treasure.

## Notes (how the AI filled in the rest -- change anything)

- **The map** is 10 x 10 squares with an outer wall all round and walls on some of the
  lines between squares. Every square can be reached without dynamite. Nobody sees it.
- **Each of you starts** on a random square, at least six steps apart, and nobody is
  told where. Who moves first is a coin flip.
- **Each turn is one of:**
  - **walk** one square. Into a wall: you stay put, the turn is gone, and a wall goes on
    your map.
  - **shoot** (3 bullets). The bullet flies straight until a wall. If he is anywhere on
    that line -- your own square included -- he is dead and you win. Both of you only
    hear "hit" or "miss", never how far it went.
  - **blast** (3 dynamite) the line next to you. A wall there is gone for good. The
    **outer wall does not break** -- and now you know it is the edge of the world. If
    there was no wall, the dynamite is wasted, but you learn that too.
- **The treasure** is hidden on one square. Walk onto it and you win.
- **Your map** (left) is drawn from where you started, because that is all you know.
  The faint grid shows everywhere the world could still be: the map is 10 x 10, so the
  more of it you have walked across, the smaller that area gets. When it is exactly
  10 x 10 you know where you are.
- **The rival's map** (right) is the same thing from his side: every move he makes and
  what happened, drawn from where he started.
- **ghost** lays his map over yours. Drag it around with your finger: where his walls
  and your walls disagree you get a warning cross, and when it fits it says so, along
  with how many places fit at all ("the only place it can!" once there is just one).
  When you think it is right, his marker shows you where he is -- line up and shoot.
- **Difficulties** are the levels: **1 easy, 2 normal, 3 hard**. "new game" starts on
  easy and winning moves you up one.
  - **easy** wanders, prefers new squares, and fires off a shot now and then at random.
  - **normal** explores properly, works out where you are from the same maps you see,
    and shoots when it is fairly sure.
  - **hard** also learns from every missed shot, skips squares you have already
    searched, keeps out of your line of fire, shoots on one-in-three odds while it has
    bullets to spare, and once you are out of bullets it comes and hunts you down.
  - The AI never peeks at the real map. It knows exactly what you know.
- **auto** (or space) lets the computer take your turn for you.
- **Controls:** arrow keys or the on-screen pad act in a direction; the mode buttons (or
  shift) switch between walk, shoot and blast. Shoot and blast drop back to walk after
  use so you don't fire twice by accident.
- **Score:** one point for every new square you walk into, and on a win 100 for the
  treasure or 150 for the shot, times 1, 2 or 3 for the difficulty.
- **When it ends** the real map is shown for a moment: both trails, the treasure, where
  he really was.
- The kit's default sound is loud, so it plays at 0.28 of the setting here.
- **For playtests:** there is no clock in real play, so `ELKYUR_IDLE_SECONDS=8` makes a
  player who does nothing for that long give up (that is the `idle` run's fail state).
  `ELKYUR_AUTOPLAY=easy|normal|hard` has the computer play your side too, which is how
  the AI gets tested against itself. Your marker is the `@`, his is `o`.

## Ideas for later

- Two humans on one device, passing it back and forth
- A bigger map (the chat said 20 x 20)
- Things in the map: holes, rivers, a way out you have to carry the treasure to
