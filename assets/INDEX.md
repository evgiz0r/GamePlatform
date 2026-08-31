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
| `animals/` | 256x256 | `0.10` - `0.14` | 26-36 px |

Passing an animal the default scale of `2.0` gives you a 512 px sprite that fills the
screen. This is the most likely mistake with these assets.

`Blob` draws a soft tinted copy behind the sprite, which is what makes flat pixel art sit
properly in the neon look.

Games work **with no sprites at all** — `Blob` falls back to a glowing shape in a palette
role. Art is an upgrade, never a dependency. An unknown name leaves the placeholder and
records a warning in the playtest report.

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
wrong for its job, swap the file — nothing depends on the specific sound.

A missing sound is not an error: the game runs silent and the playtest report warns once.

## audio/music/ — `Audio.music("name")`

`jingle_1` `jingle_2` `jingle_3` `jingle_4` — short 8-bit stings, good for menus, wins and
level transitions. They are short and will not loop seamlessly.

## drawings/

Empty, and meant to be. This is where the person whose game it is puts their own pictures
so they can be turned into sprites. A drawing with a clear subject on a plain background
converts best.

## Keeping this file honest

When assets are added or removed, update this file in the same change. It is the only
thing standing between the AI and confidently-wrong asset paths.
