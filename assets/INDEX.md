# Asset index

**The AI must read this file before referencing any asset path.** Do not guess filenames —
a path that does not exist fails silently as an invisible sprite, which is one of the
hardest bugs to spot in a report.

## Current state: no image assets yet

Games in this kit work with **zero asset files**. Actors are drawn by `Blob`
(`shell/blob.gd`) as glowing shapes coloured by palette role. This is deliberate: the kit
must run immediately after cloning, and art is an upgrade rather than a dependency.

To use real art once it exists:

```gdscript
var b := Blob.new()
b.texture = load("res://assets/characters/fox.png")
```

Game logic never changes — only the texture assignment.

## Audio

`Audio.play("name")` looks for `res://assets/audio/sfx/name.ogg` (or `.wav`, `.mp3`).
A missing sound is **not** an error: the game runs silent and the playtest report warns
once. Common names games ask for: `coin`, `hurt`, `jump`, `hit`, `win`, `lose`.

Music: `Audio.music("name")` → `res://assets/audio/music/name.ogg`.

## Drawings

`assets/drawings/` is for pictures made by the person whose game this is. Ask the AI to
turn one into a player or enemy sprite. This works best with a clear subject on a plain
background.

## Adding a pack

When art is added here, this file must be updated with what exists — names, paths, sizes,
and animation frame counts. An index that has drifted from reality is worse than no index,
because it produces confident references to files that are not there.

Every pack must be CC0 or equivalently unrestricted, and recorded in `CREDITS.md` with its
source and licence.
