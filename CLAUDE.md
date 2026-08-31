# GamePlatform — instructions for the AI

This repo is a kit for building complete 2D games in Godot 4 by prompting. Someone has
asked you to make them a game. Read this fully before writing anything.

## The one rule

**`shell/` is off limits. `game/` is yours.**

`shell/` already provides the main menu, pause, game over, options, high scores, palette
reskinning, screen shake, audio, and headless self-play. If you find yourself writing a
menu, a pause screen, or a score display, stop — you are rebuilding something that exists.

If the shell genuinely cannot express what the game needs, say so and ask. Do not edit it
silently.

## How to make a game

1. Read `GAME.md` if it exists. It is the player's design in their own words and it wins
   any argument with your own taste.
2. Create `game/<name>/<name>.gd` and `game/<name>/<name>.tscn`.
3. The script extends `GameMode` (see `shell/game_mode.gd`).
4. The scene is a single `Node2D` with that script attached. Build everything else in code.
5. Run a playtest (below). Read the report. Fix what it tells you.
6. Only then tell the user it is ready.

The game appears on the menu automatically — any folder under `game/` containing a
matching `.tscn` is picked up. There is no registry to update.

## The contract

```gdscript
extends GameMode

func _ready() -> void:
    title = "space cat"                       # menu label
    play_area = Rect2(0, 0, 640, 360)         # world bounds
    super()

func start(_config: Dictionary) -> void:
    # build the level; called once, after the game is on screen
    pass
```

Verbs the shell gives you — use these instead of inventing your own:

| Call | Effect |
|---|---|
| `add_score(n)` | score + HUD + high score |
| `set_lives(n)` / `lose_life()` | lives + HUD + hit juice + game over at zero |
| `win()` / `lose()` | ends the run, shows the right screen |
| `center()`, `random_edge_point()`, `in_play_area(p)` | playfield helpers |
| `Juice.hit()`, `Juice.pop(node)`, `Juice.flash(node)`, `Juice.text(...)` | game feel |
| `Audio.play("coin")` | sfx; silent + warns if the file is missing |
| `Palette.col("hazard")` | colors by ROLE, never hardcoded hex |

## Hard requirements

- **Input**: read `PInput`, never `Input`. `PInput.dir()`, `PInput.pressed("action_a")`,
  `PInput.just_pressed(...)`. This is what lets a bot play your game. Using `Input`
  directly silently breaks self-play.
- **Color**: use `Palette.col(role)` with roles `bg bg_alt ink player friend hazard warn
  prize accent`. Never a hex literal. This is what makes `/look` reskin the whole game.
- **Visuals**: use `Blob` (see `shell/blob.gd`) for every actor. `b.set_sprite("wizard")`
  uses real art; with no sprite it draws a glowing shape in a palette role. **Read
  `assets/INDEX.md` before naming any asset** — never guess a filename, and mind the scale
  (16x16 sprites want ~1.5-2.0, the 256x256 animals want ~0.12).
- **Instrumentation**: call `Probe.track(node, "@")` for the player, `"x"` for hazards,
  `"*"` for prizes/goals, and `Probe.event("thing_happened")` at meaningful moments.
  Without this you are blind during playtests and so is the report.
- **No physics nodes required.** Distance checks are fine and far more predictable. Use
  `Area2D` only if the game genuinely needs shaped collision.

## Playtesting — do this before claiming a game works

```bash
tools/playtest.sh <game> <bot> <seconds>
```

Bots: `idle` (does nothing), `random`, `seek` (chases prizes), `avoid` (flees hazards),
`smart` (dodges then collects). Always run at least two:

- `smart` — can a competent player enjoy it? Should survive a while and score.
- `idle` — can the game be lost at all? Should die. If it doesn't, there is no challenge.

The report gives you a timeline, counts, ASCII maps of the playfield, warnings, and
automatic checks. Read the ASCII maps: they show spatial bugs (everything spawning in one
corner, the player stuck in a wall, a goal outside the play area) that counts alone hide.

Keep runs short (20–30s). They are cheap, but not free.

## Style

Bright neon on a dark background. Glow, trails, squash-and-stretch, screen shake. Games
should feel alive within the first second. When in doubt add more juice, not more systems.

## Scope discipline

A good first version is one screen, one verb, one reason to keep playing. Ship that, play
it, then add. Do not build an inventory, a save system, a dialogue tree, or multiplayer
unless explicitly asked — and say plainly that those are large before starting.
