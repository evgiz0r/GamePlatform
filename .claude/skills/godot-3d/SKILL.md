---
name: godot-3d
description: 'How to build a 3D game in this kit — the GameMode3D contract (shell/game_mode_3d.gd), palette materials, tap-to-ground picking, Probe bridging so bots and ASCII maps work, RigidBody3D for falling things, and the Compatibility-renderer/web gotchas. Use whenever a game under game/ extends GameMode3D or someone asks for anything 3D.'
---

# 3D games in this kit

The kit was 2D-only until `game/drop/` (2026-09). Everything 3D lives in one shell file,
`shell/game_mode_3d.gd`, and games extend `GameMode3D` instead of `GameMode`. Same
one-`Node2D` scene, same `start()`, same verbs (`add_score`, `lose_life`, `win`...), same
menu / pause / HUD / palette / self-play. Read `game/drop/drop.gd` end to end once: it is
the reference and it is short.

## What GameMode3D gives you

| Member | Use |
|---|---|
| `world: Node3D` | put every 3D node under this (it lives in a `SubViewport` with its own `World3D`) |
| `cam`, `sun`, `env` | a camera, a key light and an `Environment` (dark palette bg, linear tonemap, no glow), already wired |
| `look_from(pos, target)` | aim the camera; also the pose `shake3d()` jitters around |
| `mat(role, emission := 0.4)` | `StandardMaterial3D` in a palette role; re-tints on `/look`. Emission > 0 = neon glow |
| `ground_point(screen)` | where a tap (640x360 screen coords from `_input`) hits the Y=0 plane; `Vector3.INF` if it misses — check `is_finite()` |
| `to_screen(world)` | screen position of a 3D point, for `Juice.text()` and 2D overlays |
| `world_area: Rect2` | the X/Z rectangle (x, z, w, d) that maps onto `play_area` for the ASCII eye. **Set it in `_init()`** next to `play_area` |
| `to_play()`, `from_play()`, `clamp_to_area()` | conversions between that rectangle and screen space |
| `track3d(node3d, "@")` | `Probe.track` for 3D nodes: a hidden 2D proxy follows the node so bots and maps work unchanged |
| `shake3d(n)`, `hit3d(n)` | camera shake in world units; `hit3d` adds the shell's hitstop. `Juice.shake()` only knows `Camera2D`, so use these |

## Axes and camera

The ground is the X/Z plane, Y is up. With the default `look_from` the camera sits at
+Z looking toward −Z, so **+Z is toward the camera = screen bottom** and +X is screen
right. `PInput.dir()` therefore maps as `Vector3(d.x, 0, d.y)`. `world_area.position.y`
is a Z coordinate, not a height.

## Materials and look

- Never `Color(...)` literals: `mat("player")`, `mat("hazard", 0.9)`. One material per
  role+emission is cached and shared, so mutate nothing on the returned material.
- The `Backdrop` (2D stars/grid) still draws under the 3D view; the view's background is
  `Palette.col("bg")`, so the two blend. The shell HUD (score, lives, menu, sound) draws
  on top via its `CanvasLayer`.
- **No glow.** `Environment.glow_enabled` inside the 3D `SubViewport` washed the whole
  frame flat bright purple under the Compatibility renderer (4.7.2, seen in `shots.sh`).
  Emissive materials (`mat(role, 0.5..0.9)`) on the dark background give the neon look
  without it. Tonemapper is linear on purpose: filmic turned the pink accent orange.
  Shadows are off by default (`sun.shadow_enabled`); turn them on per game if the look
  needs them, they cost on phones.
- Meshes: `BoxMesh`, `CapsuleMesh`, `SphereMesh`, `PlaneMesh`, `CylinderMesh` — code-built,
  no asset files, like `Blob` in 2D. Real art is an upgrade, not a dependency.

## Models and characters (real art)

- `model(name, size)` → a pivot with the glTF from `assets/models/<kit>/<name>.glb` scaled
  so its longest side is `size`, centred on X/Z, feet at Y=0. **Always pass a size**: kits
  are not to scale with each other (house 1.3, car 2.5, fork 0.5 units natively).
  `tools/model_info.sh res://assets/models/car/sedan.glb` prints real bounds + clips.
- `add_box_collision(body, pivot)` gives a `RigidBody3D`/`StaticBody3D` a box matching that
  pivot (add the pivot to the body first, rotate the body not the pivot). The pivot carries
  `meta "aabb"` (its box in parent space) for hit checks.
- `Actor3D` (`shell/actor3d.gd`): `set_character("Casual_Male", 1.8)` + `play("Walk")` +
  `face(dir)`. Quaternius characters face +Z; `face()` handles that. Clip names are in
  `assets/INDEX.md`; `play()` returns false and warns on a bad name.
- New models: `tools/fetch_model.sh <kit> <name>...` from the shorepine/kenney mirror, then
  import, then **list them in `assets/INDEX.md`** and credit the pack in `CREDITS.md`.
  Most kits share one `Textures/colormap.png`; fetch_model fetches it first. **A model
  imported before its colormap exists renders pure white** (it cached a missing texture)
  -- delete its `.glb.import` and import again. Quaternius characters embed their
  textures, so they never have this problem.
- Both helpers fall back to palette shapes + a playtest warning when a file is missing, so
  a game keeps running (and the report tells you which name was wrong).
- Scenery: a ring of `model()`s around the play area (houses behind, trees on the sides,
  lamps on the corners) plus `sun.shadow_enabled = true` is most of the difference between
  "a prototype" and "a place". Shadows cost; turn them on per game, not in the shell.

## Input

- Read taps in `_input()` on the game (the `Node2D`), exactly like 2D games: `e.position`
  is in 640x360 space, feed it to `ground_point()`. The `SubViewportContainer` ignores the
  mouse on purpose; nothing inside the 3D view takes GUI input.
- Bail out on `Flow.pointer_over_hud()` first, and give every mouse verb a `PInput` path
  too (`action_a` to act, `PInput.dir()` to aim) or the bots cannot play it.
- On-screen buttons drawn by a game should be a `ColorRect` + `Label` with
  `mouse_filter = IGNORE` and a `Rect2.has_point()` test in `_input()`, not a `Button`:
  `_input` runs before the GUI, so a real `Button` would also fire the game underneath.

## Physics (the one place it earns its keep)

- Things that fall, tumble, bounce and pile: `RigidBody3D` with `CollisionShape3D`
  children (a `BoxShape3D` per cell for compound pieces) under `world`. A
  `StaticBody3D` + `WorldBoundaryShape3D` is the floor. `gravity_scale` 2-3 reads as a
  "drop"; Earth gravity floats at these scales.
- **Set `global_transform` / velocities only AFTER `add_child`.**
- **Still detect hits with distance checks** in `_physics_process` (cell position vs actor
  position, gated on `linear_velocity.y < -3` so a resting piece is harmless). No
  `Area3D` on actors, no collision layers to get wrong, and the report explains misses.
- `body_entered` (needs `contact_monitor = true`, `max_contacts_reported > 0`) fires
  inside the physics flush: spawning nodes there is fine, but `call_deferred` anything
  that touches physics state to be safe.
- Clean up: a settled body (`sleeping`, or both velocities tiny for a couple of seconds)
  gets `freeze = true`, its shapes `disabled`, sinks under the floor and frees itself.
  Cap live bodies (`MAX_PIECES`) — a tap-happy player makes hundreds.
- Debris: tiny `RigidBody3D` cubes flung upward and freed by a `SceneTree` timer after
  ~1.3 s are the cheapest impact juice there is.
- The project does not pin a 3D physics engine; the default works headless and on the
  web build. Do not add Jolt to `project.godot` for one game.

## Self-play

The bots and the ASCII map are 2D and stay that way: `track3d()` keeps a 2D proxy per
tracked node in `play_area` space via `world_area`. So the usual rules apply — track the
thing the player steers as `"@"` (in `drop` it is the ground cursor under the hovering
piece), targets as `"*"`, real threats as `"x"`, and give the main verb an `action_a`
binding. Then `tools/playtest.sh <game> smart 25` and `idle 25` as for any game. Real
frames: `tools/shots.sh <game> smart 9 2` — the headless driver renders nothing, so this
opens a window briefly.

## GDScript gotchas met while building `drop`

- `for w in some_array:` leaves `w` untyped, so `var to := goal - w.position` fails to
  parse ("cannot infer type"). Write `for w: Node3D in some_array:` or annotate the var.
- `Rect2.get_center()` gives (x, z) for `world_area`; build the `Vector3` by hand.
- A `MeshInstance3D`'s `global_position` inside a `RigidBody3D` follows the body's
  tumble, which is exactly what per-cell hit checks want.
