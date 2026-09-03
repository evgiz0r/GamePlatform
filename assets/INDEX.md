# Asset index

**Read this before referencing any asset. Do not guess filenames** — a path that does not
exist fails silently as an invisible sprite, which is one of the hardest bugs to spot.

Everything here is CC0 (Kenney). See `CREDITS.md`.

## Using a sprite

```gdscript
var b := Blob.new()
add_child(b)
b.set_sprite("wizard")          # searches characters/, animals/, items/
b.set_sprite("penguin", 0.12)   # second arg is the scale (default 2.0)
```

**Sizes differ between folders, so the scale you pass differs too.** The viewport is
640x360, so aim for roughly 20-35 px on screen:

| Folder | Source size | Good scale | On screen |
|---|---|---|---|
| `characters/`, `items/` | 16x16 | `1.5` - `2.0` | 24-32 px |
| `animals/` | ~300-400 px | `0.10` - `0.14` | 30-45 px |
| `actors/` | 80x110 | `0.40` - `0.60` | 32-66 px |

Passing an animal the default scale of `2.0` gives you a 512 px sprite that fills the
screen. This is the most likely mistake with these assets.

`Blob` draws a soft tinted copy behind the sprite, which is what makes flat pixel art sit
properly in the neon look.

Games work **with no sprites at all** — `Blob` falls back to a glowing shape in a palette
role. Art is an upgrade, never a dependency. An unknown name leaves the placeholder and
records a warning in the playtest report.

## actors/ — animated characters (the only animated art in the kit)

Five characters, each with **24 poses** at a uniform 80x110, plus **9 separate limbs** for
building your own puppet rig. This is the only place frame animation exists — everything
else in `assets/` is a single static image.

`adventurer` `female` `player` `soldier` `zombie`

```gdscript
var b := Blob.new()
add_child(b)
b.set_actor("zombie")          # second arg is scale, default 0.5
b.play("walk", 10.0)           # loops walk1 -> walk2 at 10 fps
b.play("cheer", 6.0, false)    # plays once, holds the last frame
b.flip_h = true                # face the other way
```

`play()` returns `false` and records a playtest warning if the clip does not exist, so it
is safe to try one and fall back. `set_actor()` turns `glow` off — the neon halo is tuned
for 16x16 shapes and reads as a dark smear behind a detailed character. Set `glow = true`
again afterwards if you want it.

**Two-frame clips** (pass a name, it loops): `walk` `climb` `cheer` `swim` `action` `hold`

**Single poses** (same call, one frame): `idle` `stand` `jump` `fall` `duck` `hurt` `kick`
`skid` `slide` `hang` `talk` `back`

**Limbs** for puppet rigs live in `actors/<name>/limbs/`: `head` `head_back` `head_focus`
`head_hurt` `body_front` `body_back` `arm` `hand` `leg`. Load these by full path with
`set_sprite("res://assets/actors/zombie/limbs/arm.png", 0.5)`.

## characters/ — 16x16 pixel art

`wizard` `ranger` `skeleton` `viking` `barbarian` `guard` `soldier` `villager` `princess`
`ghost` `goblin` `crab` `bat` `skull` `spider` `snail`

People: wizard, ranger, viking, barbarian, guard, soldier, villager, princess.
Monsters: skeleton, ghost, goblin, crab, bat, skull, spider, snail.

## animals/ — colourful, larger than the pixel sprites

`elephant` `giraffe` `hippo` `monkey` `panda` `parrot` `penguin` `pig` `rabbit` `snake`

**These are icon badges, not game sprites** — each animal sits on an opaque rounded square,
so on a dark background it shows as a coloured tile rather than a free-standing character.
They look right for tokens, cards, menus, buttons and match-3 pieces, and wrong for
something running around an arena.

For an actor that moves, prefer `characters/`. If a game really wants an animal hero, say
so plainly and use it knowing it will read as a badge.

## items/ — 16x16 pixel art

`sword` `axe` `hammer` `bow` `arrow` `potion_red` `potion_green` `potion_blue`
`gold_bar` `beehive` `banner`

## tiles/ — whole tilesheets, not individual tiles

`tiny_dungeon.png` `tiny_town.png` `pixel_platformer.png`

These are packed tilesheets for use with `TileSet`/`TileMapLayer`. Individual tiles are
**not** extracted and are not named — do not invent tile filenames. For a tilemap game,
build a `TileSet` from one of these sheets (16x16 tiles, no margin in the packed sheets).

## audio/sfx/ — `Audio.play("name")`

`coin` `pickup` `click` `select` `jump` `hurt` `hit` `explode` `thud` `step` `open`
`win` `lose`

These names were mapped from Kenney's packs by meaning, not by listening. If one sounds
wrong for its job, swap the file — nothing depends on the specific sound. Note that `win`
is a byte-for-byte copy of `music/jingle_1` and runs about two seconds, so it is a poor
choice for a snappy hit; reach for `impact_*` or a `voice_*` line instead.

### voice_* — a real human voice (female)

Spoken lines, not blips. These are what make a quiz or a level transition feel like a game
rather than a UI.

`voice_correct` `voice_wrong` `voice_level_up` `voice_level` `voice_round` `voice_ready`
`voice_set` `voice_go` `voice_hurry_up` `voice_time_over` `voice_final_round`
`voice_game_over` `voice_you_win` `voice_you_lose` `voice_new_highscore`
`voice_congratulations` `voice_power_up` `voice_objective_achieved`
`voice_mission_completed` `voice_mission_failed`

Spoken numbers **one to ten**: `voice_num_1` … `voice_num_10`.

The male voice and ~16 military lines ("fire in the hole", "reloading") are in the same
CC0 pack but were not vendored — ask if you want them.

### impact_* and step_* — things hitting things

`impact_soft` `impact_punch` `impact_wood` `impact_metal` `impact_glass` `impact_plate`
`impact_bell` `impact_light` `step_grass` `step_wood`

`Audio.play()` takes a pitch-jitter argument (default `0.08`). Firing one sample several
times at climbing pitch is the cheapest way to build a laugh, a combo or a countdown out
of a single file.

A missing sound is not an error: the game runs silent and the playtest report warns once.

## audio/music/ — `Audio.music("name")`

`jingle_1` `jingle_2` `jingle_3` `jingle_4` — short 8-bit stings, good for menus, wins and
level transitions. **Do not loop these as background music** — a game that calls
`Audio.music()` on repeat to fake a loop out of one just repeats the same ten seconds
forever, and it reads as exactly that. See CLAUDE.md.

Real background tracks, long enough to loop sensibly, one licence exception among them:

| Name | Feel | Licence |
|---|---|---|
| `peaceful_1am_in_may` | calm, ambient | **CC-BY 3.0** — credit TAD, see `CREDITS.md` |
| `bonus_round` | bright, playful, short loop | CC0 |
| `chiptune_battle` | driving, tense | CC0 |
| `on_the_offensive` | upbeat, march-like | CC0 |

None of these were checked by ear for a clean loop seam beyond what their own source pages
claim — if one clicks or pops where it repeats, that is a real flaw to fix (a different
track, or trimming the file), not something to shrug off.

### Candidates, not vendored yet

More tracks worth having on hand, checked for license but not yet downloaded into
`assets/`:

| Track | Feel | Licence | Author |
|---|---|---|---|
| [Cyberpunk Moonlight Sonata](https://opengameart.org/content/cyberpunk-moonlight-sonata) | moody, driving, synthwave | CC0 | Joth |
| [Heroic Minority](https://opengameart.org/content/heroic-minority) | orchestral, adventurous | CC-BY 3.0 | Alexandr Zhelanov |
| [Crystal Cave](https://opengameart.org/content/crystal-cave-mysterious-ambience-seamless-loop) | ambient, mysterious, explicitly seamless | CC-BY 3.0 (author also offers CC-BY-SA / GPL — **use the CC-BY option only**, per the licence rule below) | cynicmusic / The Cynic Project |

## drawings/

Empty, and meant to be. This is where the person whose game it is puts their own pictures
so they can be turned into sprites. A drawing with a clear subject on a plain background
converts best.

## Keeping this file honest

When assets are added or removed, update this file in the same change. It is the only
thing standing between the AI and confidently-wrong asset paths.
