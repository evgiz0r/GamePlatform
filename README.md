# GamePlatform

A starter kit for making complete 2D games by **describing them to an AI**.

You bring the ideas. The kit already has the boring parts — menu, pause, score, high
scores, sound, screen shake, and a way for the AI to play the game itself and find its own
bugs. You never have to ask for those.

## Setup (about five minutes)

1. **Install [Godot 4](https://godotengine.org/download)** — the standard version, not .NET.
2. **Install an AI coding tool** — [Claude Code](https://claude.com/claude-code) is what
   this kit is tuned for.
3. **Clone this repo** and open the folder in your AI tool.
4. Open the same folder in Godot and press **F5**. You should get a menu with one game
   called *count*. Play it for ten seconds so you know what "working" looks like.

Optional but recommended — tell the kit where Godot lives, so the AI can playtest:

```bash
export GODOT="/path/to/godot"
```

## Making a game

Just say what you want:

> make a game where a fox runs across rooftops and jumps over chimneys

Or use the built-in commands:

| Command | What it does |
|---|---|
| `/start` | first time here? checks your setup and gets you to a running game |
| `/new-game <idea>` | designs and builds a whole new game |
| `/add <thing>` | adds one enemy, powerup, obstacle or rule |
| `/look <style>` | changes the colors and mood |
| `/playtest` | the AI plays the game itself and reports problems |
| `/publish` | exports to the web so you can share a link |

Every game you make shows up on the menu automatically. The kit's three starter games have
been removed; **count** (a counting quiz) is the working reference now, and a frozen copy
lives in `reference/count/` with notes on what is worth copying from it.

## Working with a kid

This kit was built with a specific situation in mind: a parent at the keyboard and a child
supplying the ideas. Two things make that work far better:

- **Let them answer the design questions.** When the AI asks who the hero is and what makes
  it hard, those are their answers to give. `GAME.md` records them in their own words.
- **Put their drawings in `assets/drawings/`.** Ask the AI to turn one into the player.
  A game starring something they drew is a different experience from a game with a circle.

## If something breaks

Say **"undo the last change."** This is a git repo, so nothing is ever really lost. A
broken game cannot break the menu — worst case you land back on a working main menu.

Commit whenever a game is in a good state, so you always have somewhere to fall back to.

## What is where

```
game/       your games — one folder each. This is where the AI works.
shell/      menu, pause, score, audio, juice, self-play. The AI is told not to touch it.
assets/     art and sound — people, monsters, animals, items, music. See assets/INDEX.md.
tools/      playtest.sh (headless self-play) and shots.sh (real screenshots)
GAME.md     your game's design, in your words
CLAUDE.md   the rules the AI follows
```

## Playing the game the AI cannot play

The kit can play its own games with bots and report what happened, which catches broken
spawners, impossible objectives and unloseable games. It cannot tell you whether a game is
**fun**. That part is yours.
