# noor

> This is the design of ONE game, in the words of whoever is making it. The AI reads
> it before every change to this game and it outranks the AI's own taste. Bad
> handwriting is fine, so is changing your mind.

## What is it called?

noor

## Who are you?

I like playing strategy games with maps, with like units, building something like
civilization 5.

So maybe a game with 2 players on the map, each with its own lands. The map is a hex
grid or maybe just squares. (It is squares.)

## What do you do?

**Move your units, take their cities.**

Each player has cities, and land tiles are bound to cities, so if player 1 captures a
city belonging to player 2, the tiles related to that city also go over to player 1.

Let's make the game turn based as well.

(Tap a warrior to pick it up, tap a glowing tile to walk there, tap a red-ringed enemy
to hit it. Walk into an empty enemy city to take it. "end turn" or Shift/K passes the
turn. "auto" or Space lets the advisor play your turn for you.)

## What is trying to stop you?

The rival on the other side of the map. Their cities make warriors every couple of
turns, same as yours, and they march at whatever of yours is closest. Neutral cities in
the middle have a guard each; whoever takes them first gets their land too.

You get **thirty seconds a turn**. When the bar runs out the turn ends by itself.

## How do you win?

Take every one of the rival's cities. Lose all of yours and it is over. The hearts in
the corner are your cities.

## What should it look like?

A dark map with each side's land glowing in its colour, borders where the lands meet,
neon banners on the cities.

## Core loop

> Cities make warriors → you walk them at the border → hit, heal, take a city → its
> whole land turns your colour → the rival does the same to you.

## Notes

- 20 x 9 squares, mirrored left-right so both sides start fair. Three cities each plus
  two neutral ones in the middle, and a few lakes nobody can walk on.
- Every land square belongs to the city that is closest to it on foot. There is no
  separate ownership map: a square is yours because its city is yours.
- Warriors: 10 health, 2 moves a turn, hit for 6, hit back for 3. A warrior standing in
  its own city takes 2 less. A warrior that did not move heals 3 at the start of its
  next turn, but only on friendly land. The neutral guards never heal: they are a camp,
  not a city.
- A city makes a warrior every 2 turns, only if nothing is standing in it. So a city
  that never sends anyone out has exactly one defender.
- Score: 10 a kill, 50 a neutral city, 100 a rival city, 500 for the win.
- The rival and the "auto" advisor are the same brain: hit anything next to you (unless
  the hit-back would kill you and yours would not), walk home and rest when you are down
  to 3 health, stay home if an enemy is within three squares of your city, otherwise walk
  toward the nearest city that is not yours. Warriors move front-to-back and sidestep
  round a blocked square, because the first version marched into its own traffic jam
  and stood next to a city for ten turns without taking it.
- Playtests can shorten the turn clock with `NOOR_TURN_SECONDS=1.5` in the environment,
  so a bot that never touches anything loses inside a minute. The idle bot is the "do
  nothing" player and the clock is what beats it.
- Sound is scaled to 0.35 of the setting and music to 0.45 while noor is on screen;
  the saved settings are never touched.

## Ideas for later

- Hexes instead of squares
- A second unit type (archer that hits from two squares away)
- Cities that grow: more land, faster production, the longer you hold them
- Two humans on one screen, taking turns
