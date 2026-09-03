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

1. Read the design. For an existing game that is `game/<name>/GAME.md`; for a new one it
   is the root `GAME.md`, which is where someone sketches before a game exists. It is the
   player's design in their own words and it wins any argument with your own taste.
2. Create `game/<name>/<name>.gd`, `game/<name>/<name>.tscn`, and `game/<name>/GAME.md`
   (move the root sketch into it and blank the root file for the next idea).
3. The script extends `GameMode` (see `shell/game_mode.gd`).
4. The scene is a single `Node2D` with that script attached. Build everything else in code.
5. Run a playtest (below). Read the report. Fix what it tells you.
6. Only then tell the user it is ready.

## A game is one folder

```
game/count/
  count.gd      # the code
  count.tscn    # one Node2D with that script
  GAME.md       # the design, in the player's words
```

**To add a game, create the folder. To remove one, delete the folder.** The menu scans
`game/` for any folder holding a matching `.tscn`, so there is no registry, no list, and
nothing else to update. `tools/playtest.sh` with no arguments picks the first game it
finds, so it keeps working whatever you add or delete.

Nothing outside a game's own folder should ever name that game. If you find yourself
writing its name in a doc, a tool or another game, that is the thing that will rot when it
is deleted — the kit's own onboarding once told people to play a game that had been gone
for weeks.

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
| `Flow.pointer_over_hud()` | true when the pointer is over the shell's HUD |

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
- **Mouse clicks**: if the game acts on a click, bail out first when
  `Flow.pointer_over_hud()` is true. Games read clicks in `_input()`, which runs before
  the GUI, so without this a tap on the shell's "menu" button also fires the game
  underneath it.
- **Touch controls**: assume a phone, not just a mouse. A pointer control should never need
  to sit on top of the thing it is steering — see "Controls" in the `game-design` skill for
  why (`bricks`' paddle got this wrong once already) and what to do instead.
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

## Things this kit learned the hard way

Short, specific, and all of them cost a debugging session:

- **The default sound is loud.** `SaveData.data["volume_sfx"]` ships at `0.8`, which is a
  lot for a game that makes a noise every few seconds. Every game so far drops it to
  `~0.28` in `start()` and restores it in `_exit_tree()`, in memory only so the saved
  settings file is never touched. Copy that. `volume_music` gets the same treatment in any
  game that plays background music.
- **Don't loop one of the kit's jingles as background music.** `jingle_1`-`jingle_4` are
  short stings built for a one-off moment (a win, a menu) -- calling `Audio.music()` on
  repeat to fake a loop out of one is mechanically easy (the function no-ops while the
  track is still playing, so calling it every `_process()` frame just restarts it once the
  clip ends) but it sounds like exactly what it is: the same ten seconds on repeat,
  annoying within a minute. `bricks` tried this and pulled it back out.
  For real background music, `assets/audio/music/` also has four longer, loop-friendly
  tracks now (`peaceful_1am_in_may`, `bonus_round`, `chiptune_battle`, `on_the_offensive`)
  -- see `assets/INDEX.md` for the feel of each. Same `Audio.music()` polling trick, just
  aimed at a track that is actually meant to repeat. One of the four
  (`peaceful_1am_in_may`) is CC-BY, not CC0 -- already credited in `assets/CREDITS.md`,
  nothing more to do, but worth knowing before assuming everything in the folder is CC0.
- **A sound on/off toggle is already on screen, always.** `Flow` builds it once, outside
  the menu/game rebuild cycle, so it survives every transition and sits in the corner on
  every screen including the main menu -- see `_build_sound_toggle()` in
  `shell/autoload/flow.gd`. It gates `Audio.play()`/`Audio.music()` centrally
  (`Audio.muted()`), so no game needs to check it or do anything for it to work. A
  percentage slider on the main menu was tried first and reverted: reaching a menu-level
  control meant backing out of whatever game you were adjusting it for, which defeated
  the point.
- **`win.ogg` is a two-second jingle**, byte-identical to `music/jingle_1`. It is a bad
  choice for a hit. Use `impact_*` or a `voice_*` line.
- **The `smart` bot flees anything tagged `"x"` within 90px.** Space out anything it has
  to walk onto, or it oscillates between two of them forever. And only tag a real threat
  as `"x"` — tagging harmless things as hazards is false instrumentation and it wrecks the
  bot's judgement as surely as it would a human's.
- **If the bots cannot play your game, give them a way in.** The bots have no
  pathfinding, planning or reading ability, so a puzzle game is invisible to them: they
  will report it runs and nothing else. If the game has a self-play or auto-solve mode,
  bind it to `action_a` as well as a button -- the bots pulse that, so they switch it on
  and the run becomes a real test. `maze` went from "score never moved" to fourteen levels
  cleared in one run that way.
- **A game whose only input is the mouse cannot be self-playtested.** Always give the same
  verb a `PInput` path too, even if no human will use it.
- **A swipe control should track the drag, not the touch point.** Snapping whatever you are
  steering straight to the finger's absolute position means a single tap anywhere on the
  field yanks it there -- on a phone this reads as broken. Record where the drag started
  and where the thing being steered was at that moment, then move it by the same delta the
  finger has moved since. A stationary tap then asks for zero movement and a small drag
  asks for a proportionally small one. `bricks`' paddle does this.
- **Animated art exists in `assets/actors/` only** — five human characters with real
  frames, via `Blob.set_actor()` / `Blob.play()`. Everything else in `assets/` is a single
  static image, so animals and items can only be animated by hand: position, rotation and
  squash. See `assets/INDEX.md`.

## The web build

`docs/` holds the exported web build that GitHub Pages serves. It is generated, not
written by hand — regenerate it with `/publish` after a change worth sharing. Exporting
needs the **standard** Godot build; the .NET/mono one refuses web export outright.

## Style

Bright neon on a dark background. Glow, trails, squash-and-stretch, screen shake. Games
should feel alive within the first second. When in doubt add more juice, not more systems.

## Scope discipline

A good first version is one screen, one verb, one reason to keep playing. Ship that, play
it, then add. Do not build an inventory, a save system, a dialogue tree, or multiplayer
unless explicitly asked — and say plainly that those are large before starting.
