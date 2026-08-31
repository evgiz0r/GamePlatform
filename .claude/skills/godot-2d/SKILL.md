---
name: godot-2d
description: 'Implementation knowledge for building 2D games in this kit — Godot 4 + GDScript patterns, the GameMode contract, Blob actors, movement/collision/spawning recipes, and the engine gotchas that break AI-written Godot code. Use whenever writing or debugging anything under game/.'
---

# Building games in this kit

## Environment

- Godot 4.x, **GDScript only** (no C#). Renderer is `gl_compatibility` so web export works —
  do not change it in `project.godot`.
- Viewport is 640x360, stretched. Design in those coordinates; it scales to any window.
- No build step. Edit a `.gd`, press F5.

## Anatomy of a game

```
game/space_cat/
  space_cat.gd      # extends GameMode
  space_cat.tscn    # one Node2D with the script attached — nothing else
```

The `.tscn` is deliberately trivial. **Build the game in code, not in the scene tree.**
Hand-authored scene files are the most common source of broken AI-written Godot, and a
code-built game is one file the AI can read end to end.

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://game/space_cat/space_cat.gd" id="1"]

[node name="SpaceCat" type="Node2D"]
script = ExtResource("1")
```

## Actors without art

`Blob` draws a glowing shape in a palette role — no image files needed:

```gdscript
var b := Blob.new()
b.role = "hazard"        # bg bg_alt ink player friend hazard warn prize accent
b.radius = 8.0
b.shape = "triangle"     # circle square triangle diamond
add_child(b)
b.position = Vector2(100, 50)
```

To upgrade to real art later, set `b.texture = load("res://assets/...")`. Nothing else
changes — this is why game logic must never reference colors or images directly.

## Movement

```gdscript
func _process(delta: float) -> void:
    player.position += PInput.dir() * SPEED * delta
    player.position = player.position.clamp(play_area.position, play_area.end)
```

Platformer gravity:

```gdscript
_vel.y += GRAVITY * delta
if PInput.just_pressed("action_a") and _on_ground:
    _vel.y = -JUMP_FORCE
```

**Read input through `PInput`, never `Input`.** Bots drive `PInput`; using `Input` directly
means the game cannot be self-playtested and you will be debugging blind.

## Collision — prefer distance checks

For circles-and-blobs games, skip physics entirely:

```gdscript
if a.position.distance_to(b.position) < a_radius + b_radius:
    pass
```

Predictable, debuggable, and fast. Reach for `Area2D` and `body_entered` only when you need
real shapes (tilemap terrain, odd hitboxes). Never use `RigidBody2D` for a player — you
will fight it.

## Spawning and despawning

Keep your own arrays and prune them. Do not rely on `get_children()`:

```gdscript
var keep: Array = []
for h in hazards:
    if not is_instance_valid(h):
        continue
    h.position += h.get_meta("vel") * delta
    if not in_play_area(h.position, 40.0):
        h.queue_free()
        continue
    keep.append(h)
hazards = keep
```

`queue_free()` is deferred — the node is still valid for the rest of the frame. Always
guard with `is_instance_valid()` and never index an array while mutating it.

## Instrumentation (non-optional)

```gdscript
Probe.track(player, "@")      # one char: "@" player, "x" hazard, "*" prize, "#" wall
Probe.event("prize_taken")    # meaningful moments
```

This costs nothing in normal play (`Probe.enabled` is false) and is the only reason
playtest reports are readable. A game without it produces an empty report.

## GDScript gotchas that bite AI-written code

- **Type inference on untyped returns**: `var x := some_func()` fails to parse when
  `some_func()` has no declared return type. Either annotate the function
  (`-> AudioStream`) or write `var x: Type = ...`. This is the most frequent parse error
  in this kit.
- **Never name a method get, set, call, or free** — they shadow `Object` builtins and the
  failure is confusing.
- **Splitting a string into characters**: `String.split("")` does not do it. Build the
  character array with a loop.
- **`@export` on a variable typed by a `class_name`** can fail if that class is not yet
  registered. Plain vars are safer inside `game/`.
- **`super()`** calls the parent method of the same name. When overriding `_ready()` in a
  `GameMode`, set `title` and `play_area` first, then call `super()`.
- **`Engine.time_scale` is global and survives scene changes.** Only `Juice` should touch
  it; the shell resets it on every transition.
- **`_process(delta)` delta is scaled by `time_scale`.** Use `_physics_process` when you
  need real time during hitstop.

## Signals

Use `Bus` for anything cross-cutting, direct connections for local things. Do not emit
`Bus.game_over` yourself — call `win()` or `lose()` on the `GameMode`.

## Performance

At 640x360 with a few hundred `Blob` actors you have enormous headroom. If it stutters the
cause is almost always `queue_redraw()` every frame on hundreds of nodes, or an O(n^2)
distance loop over thousands of actors. Cap actor counts before optimizing anything else.
