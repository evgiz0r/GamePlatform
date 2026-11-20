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
game/space_cat/
  space_cat.gd    # the code
  space_cat.tscn  # one Node2D with that script
  GAME.md         # the design, in the player's words
```

**To add a game, create the folder. To remove one, delete the folder.** The menu scans
`game/` for any folder holding a matching `.tscn`, so there is no registry, no list, and
nothing else to update. `tools/playtest.sh` with no arguments picks the first game it
finds, so it keeps working whatever you add or delete.

**The menu has a front page and an "other" shelf.** A game whose folder holds an empty
file named `ACTIVE` sits on the front page; every other game is one tap away behind the
"other" button. The front page is for the one or two games being worked on right now, so
only add the marker when asked (`touch game/<name>/ACTIVE`) and delete it when that game
is done. Still no registry: the marker lives in the game's own folder.

**A game can have levels.** Declare a `const LEVELS := [...]` array in the game's script
(one entry per level, whatever shape the game wants) and entering it from the menu opens
the game's own start screen first: "new game" or a numbered grid to start from any level.
Either calls `start({"level": n})`, and pause and game over gain a "levels" button back to
that screen. The menu itself has no level picking. Self-play skips the start screen, so
`config` may have no "level" -- default to 1. When a run reaches a new level, set
`Flow.current_config["level"] = n` so "play again" resumes there rather than at the start.
`LEVEL=n tools/playtest.sh <game> ...` (and `tools/shots.sh`) start a run at level n, and
`tools/menu_shot.sh levels:<game>` screenshots the start screen. Levels that are
Dictionaries with a `"name"` are picked by name; give them a `"group"` too and the start
screen lists each group under its heading, side by side (a level's `"sort"` orders it within
its group; its number is still its place in `LEVELS`, so reordering the screen never
renumbers the levels).

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

## 3D games

The kit can do 3D too. Extend `GameMode3D` (`shell/game_mode_3d.gd`) instead of `GameMode`;
the scene is still one `Node2D`, and menu, pause, HUD, palette and self-play all keep
working. What it gives you on top: `world` (a `Node3D` to build in), `cam` + `sun`,
`look_from(pos, target)`, `mat("hazard")` (palette-role materials that reskin with
`/look`), `ground_point(screen_pos)` for taps, `to_screen(world_pos)` for `Juice.text()`,
`track3d(node, "@")` so bots and ASCII maps see 3D actors, `shake3d()` / `hit3d()`,
`model("taxi", 3.0)` for the CC0 3D models in `assets/models/` and `Actor3D` for the
animated people in `assets/characters3d/` (both fall back to shapes when a file is missing).
Set `world_area` (the X/Z rectangle of your ground) so the ASCII eye knows what to draw.
Read the `godot-3d` skill before writing one. `reference/drop/` (parked out of the menu,
still readable) is the reference. The bots see a 3D world only as dots on a 2D map, so its
spatial bugs (a person in the road, a car in a wall, a seam in the ground) need scene
tests -- scripts that stage the moment and measure it, with screenshots: see the
`scene-tests` skill.

## Real places

`tools/osm_city.py` bakes a real town from OpenStreetMap into one JSON file a game can
build from: roads (path, kind, width, lanes, one-way, name), building outlines with
heights, parks, water, trees, traffic lights, crossings, railways (each track, the
platforms, the stations) and the town's boundary, all in
metres on the X/Z ground. The format is documented at the top of the tool. It needs
`overpass-api.de` reachable from the network, caches the raw download in `tools/.cache/`
(not committed) and re-bakes from it with `--offline`. Everything baked is
© OpenStreetMap contributors (ODbL): a game that shows it must credit that on screen.
OSM rarely knows building heights; the tool guesses those and marks the guesses. When the
session's network cannot reach Overpass, run the "bake a real city" GitHub workflow
(`.github/workflows/bake_city.yml`, inputs `place` and `out`, or `bbox` for a few
neighbourhoods of a big city) instead: it bakes on GitHub's
machines and commits the file, and you can start it with the GitHub tools.

`tools/fake_city.py` makes up a town in the same format instead -- no network, a second
or two -- for a quick test bench: one neighbourhood with one of each thing a real town has
(divided road, roundabouts, a hill, a mall, a school, shops, bus stops...), ringed by
mountains too steep to drive up. It writes `"made_up": 1`, so the OSM credit does not
apply.

OSM data is full of traps for a driving or walking game -- widths are guesses, a divided
road is two roads, one junction is several points, a car park is only its lanes -- and
each cost a round of the user's bug reports. Read the `real-places` skill before building
on a baked city.

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
  the GUI, so without this a tap on the shell's "exit" button also fires the game
  underneath it.
- **Touch controls**: assume a phone, not just a mouse. A pointer control should never need
  to sit on top of the thing it is steering — see "Controls" in the `game-design` skill for
  why (`bricks`' paddle got this wrong once already) and what to do instead.
- **No physics nodes required.** Distance checks are fine and far more predictable. Use
  `Area2D` only if the game genuinely needs shaped collision. (3D games may use
  `RigidBody3D` for things that fall and tumble -- that is the one place physics earns
  its keep -- but still detect hits with distance checks, see `reference/drop/`.)

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

A playtest passing says the game runs and can be played; it says little about whether a
3D scene looks right or a system behaves in a particular spot. For that, write a scene
test (the `scene-tests` skill): stage the situation, measure it, screenshot it, keep the
script in the game's `tests/` folder.

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
- **A WAV you add does not loop on its own.** Godot's import loops a WAV only when the
  file carries loop points, and a made-up one (numpy, a synth) has none: it plays once and
  stops. Import it once, set `edit/loop_mode=2` in its `.wav.import`, import again.
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
- **The "other" shelf goes two-up past four games.** A single column of full-height
  buttons ran off the bottom at five, which is why `reference/` exists (finished games
  parked out of the menu). Now `_show_other()` in `shell/autoload/flow.gd` switches to a
  two-column grid of slightly shorter buttons above four games, and ten fit. Past that,
  park one. The front page itself never has this problem: it only ever holds the one or
  two `ACTIVE` games plus the "other" button. `tools/menu_shot.sh other` screenshots the
  shelf.
- **Animated art exists in `assets/actors/` only** — five human characters with real
  frames, via `Blob.set_actor()` / `Blob.play()`. Everything else in `assets/` is a single
  static image, so animals and items can only be animated by hand: position, rotation and
  squash. See `assets/INDEX.md`.

## Ideas that are not being built yet

`IDEAS.md` at the root is the parking lot for concepts about the kit that are noted but
not scheduled. Read it before pitching features, so you do not re-pitch what is already
there. When someone mentions an idea and says it is for later, offer to add it to that
file rather than letting it disappear into the chat.

## Running in a remote session

Claude Code on the web starts from a bare container. `.claude/hooks/session-start.sh`
fetches a matching Godot plus the web export templates (`tools/setup_godot.sh`) and sets
`GODOT`, so `tools/playtest.sh`, `tools/shots.sh`, `tools/menu_shot.sh` and
`tools/publish_web.sh` all just work there. The user's own machine is not reachable from
that session: never ask them to run something for you or for the path to their install.

These containers are slow at 3D: a city that builds in 5 s on a laptop can take 15 here,
and a minute of simulated play can take five of wall time under the software renderer.
Run anything long with the shell's background mode and a long timeout (a foreground
command is cut off at 10 minutes, and a job you put in the background with `&` inside a
foreground command dies with it), chain several runs in one background script, and keep
working while they go. Two Godot runs at once on a 4-core container is about the limit.

**Say how long a wait will be.** The user asked for this: whenever you start something they
will wait on (a background run, a recording, a push that republishes the site), tell them
roughly how long it should take, and when you report back on a long chain, what is left and
how long that should take. Measured on these containers, one Godot run at a time (two at
once each take about half again as long):

| What | About |
|---|---|
| `tools/check_script.sh`, git fetch / merge / push | seconds |
| a playtest of a small 2D game, 20-30 s of play | 1-2 min |
| a playtest of a big 3D city game (loading the city is most of it) | under 1 min to 5 min |
| a scene test on a big city: load, then stills or a scan | 1-7 min |
| recording 100 s of play frame by frame (1280x720, `--fixed-fps 10`) | 18-20 min |
| turning frames into a video with ffmpeg | 1-2 min |
| the site republishing after a push to `main` | about 5 min |

Loading changes as games grow, so these drift: when a run comes in much faster or slower
than you said, correct this table (or the game's own times in its `DEV.md`).

## The web build

`docs/` holds the exported web build that GitHub Pages serves. It is generated, not
written by hand, and **it publishes itself**: every push to `main` runs
`.github/workflows/publish.yml`, which exports and commits `docs/` back. Do not run
`/publish` just to get a change online; push it. `git pull` before pushing, because the
workflow's own commit moves `main`. `/publish` remains for checking a build locally.
Exporting needs the **standard** Godot build; the .NET/mono one refuses web export outright.

## Several sessions at once

More than one session (on the web, the desktop app, a phone) can be working on the same game
at the same moment, each on its own branch, all publishing to `main`. Expect it; it is
normal, not an accident. What that asks of you:

- **Fetch and merge `origin/main` before you test something you mean to publish, and again
  right before you push.** `git log HEAD..origin/main` shows what the others did since you
  last looked; read it -- their commit messages say what changed and why.
- **A clean merge is not a working game.** Git merges two sessions' edits to the same file
  happily and the result can still be broken (a function one renamed, a constant the other
  retuned). After merging anything that touches your game, parse it
  (`tools/check_script.sh res://game/<name>/<name>.gd`, seconds) and run the playtest again
  before pushing to `main`. And `git add` happily stages a file that still has conflict
  markers in it: before committing a merge, `git diff --cached --check` (or grep for
  `<<<<<<<`) -- a merge here once published two notes files with both sides and the markers.
- **A merge can bring new assets** (another session's textures, models). Godot only imports
  them when asked: `tools/playtest.sh` and `tools/shots.sh` now do it when they see assets
  newer than the last import, but if you run the engine yourself, run
  `$GODOT --headless --path . --import` first, or your screenshots quietly lack them.
- **Never force-push, never rebase `main`, never "fix" a conflict by taking only your side.**
  Merge, keep both, and if two changes really contradict each other, keep the user's latest
  request and say in your reply what you changed of the other session's work.
- **A user's report may come from a build you did not make.** Their screenshot can show
  another session's feature, or still show something you already removed (the build had not
  republished yet, or their browser cached it). Check what build it is from (the HUD, a
  feature you know is gone) before chasing the bug.
- **Say so when others' work rides along.** If your push publishes changes from another
  session, tell the user in a line, so a surprise on screen has an explanation.
- Editing the same lines at the same time is the one real clash. When you see another
  session busy in the same corner of the code (its commits keep landing there), keep your
  change small and focused, and leave its constants and structure alone unless the user
  asked you to change them.

## Keep what you learn

Every session starts knowing only what is written down. Anything that cost you a debugging
session -- a gotcha, a measurement, a test that finally showed the bug, a number that
turned out to matter -- goes into the repo **as part of the same task**, even when that
makes the task a little longer. The user has asked for this explicitly: the cost of
writing it down is small next to the next session rediscovering it.

- **Kit-wide lessons** (an engine gotcha, a renderer cost, a way of testing) go in the
  matching skill under `.claude/skills/` -- `godot-3d`, `godot-2d`, `playtesting`,
  `scene-tests`, `real-places`, `game-design` -- or in "Things this kit learned the hard
  way" above. They must not name a game (see "A game is one folder").
- **Lessons about one game** (how its code is laid out, its tests and what good results
  look like, its open problems) go in that game's own folder: `GAME.md` for what the
  player sees and asked for, a `DEV.md` beside it for the developer's notes, its tests in
  a `tests/` folder there.
- **Tests you wrote to find a bug are worth keeping.** A scratch script that staged the
  problem and measured it is the regression test for the fix: put it in the game's
  `tests/` folder rather than leaving it in a scratch directory that vanishes with the
  session.
- Update what is there when it turns out wrong; a stale note is worse than none.

## Style

Bright neon on a dark background. Glow, trails, squash-and-stretch, screen shake. Games
should feel alive within the first second. When in doubt add more juice, not more systems.

## Scope discipline

A good first version is one screen, one verb, one reason to keep playing. Ship that, play
it, then add. Do not build an inventory, a save system, a dialogue tree, or multiplayer
unless explicitly asked — and say plainly that those are large before starting.
