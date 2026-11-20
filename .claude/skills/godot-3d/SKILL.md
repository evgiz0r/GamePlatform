---
name: godot-3d
description: 'How to build a 3D game in this kit — the GameMode3D contract (shell/game_mode_3d.gd), palette materials, tap-to-ground picking, Probe bridging so bots and ASCII maps work, RigidBody3D for falling things, and the Compatibility-renderer/web gotchas. Use whenever a game under game/ extends GameMode3D or someone asks for anything 3D.'
---

# 3D games in this kit

The kit was 2D-only until `drop` (2026-09, now parked in `reference/drop/`). Everything 3D lives in one shell file,
`shell/game_mode_3d.gd`, and games extend `GameMode3D` instead of `GameMode`. Same
one-`Node2D` scene, same `start()`, same verbs (`add_score`, `lose_life`, `win`...), same
menu / pause / HUD / palette / self-play. Read `reference/drop/drop.gd` end to end once: it is
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
  without it. Tonemapper is linear on purpose: filmic turned the pink accent orange. (A
  later realistic-looking game switched to ACES after mixing its ground and wall tones
  partly toward grey; if you do, check the palette's accent colours on screen after.)
  Shadows are off by default (`sun.shadow_enabled`); turn them on per game if the look
  needs them, they cost on phones.
- **Ambient occlusion, faked.** The Compatibility renderer has no SSAO, and without it
  buildings and parked cars seem to hover over the ground even with sun shadows on (most of
  a street is in some shadow already, where a sun shadow adds nothing). What works: a layer
  of soft strips laid out with the world (out from each wall's foot, under each parked car)
  in a shader with `render_mode unshaded, blend_mul, depth_draw_never, fog_disabled`, its
  ALBEDO `1 - strength * ramp^2`, faded out with distance in the shader. Multiply needs no
  sorting against what is under it and doubles up by itself in inside corners, where it
  should be darker. Lay it a few cm above the highest ground it can be on (the pavement): a
  soft ramp floating a hand's width over a lawn does not show, one sunk under the pavement
  is gone. One mesh per merged square: a draw each. Build cost is per corner of every
  outline, so look each height up once. Darken the walls' own feet in the wall shader too.
  To judge it, shoot the same view with the layer hidden and shown, and diff the pictures:
  by eye, at a 0.4 strength it was invisible, and traffic and fading HUD labels change
  between shots too.
- **Shadows past the shadow distance, painted once.** Real shadows end at
  `directional_shadow_max_distance` (45-75 m is what a browser affords), and past it a city
  looks flat. With a sun that does not move, sweep each building's outline along the light
  by its height (the convex hull of the outline and the moved outline is close enough at
  that distance), draw them white on black into a `SubViewport` (one
  `RenderingServer.canvas_item_add_triangle_array` call, then the outlines in black so
  what is on a roof is not "in shadow"), and let the ground shaders darken by it where the
  real shadows fade out: from `max_distance * directional_shadow_fade_start` to
  `max_distance`, the same ramp, so there is no seam. A viewport's texture has no
  mipmaps, and unfiltered shadow edges shimmer badly at a distance, so read it back once
  (`get_image()`), `generate_mipmaps()` and make an `ImageTexture`. Take the texture
  read out of any branch (mipmapped reads in non-uniform control flow sparkle at edges).
  Match the strength by measuring, not by eye: shoot the same block with only the real
  shadows and with only the painted ones, and compare shadowed / unshadowed brightness.
  An albedo multiplier is linear and the screen is sRGB: 0.55 off the albedo is what left
  the same 0.69 on screen as a real shadow did. Under a test's software renderer each frame
  the bake waits for costs most of a second; in a browser it is a few ms.
- **Resolution**: the 3D `SubViewport` renders at the real window size (up to 3x the
  640x360 design space, half-step multiples) and is scaled down with linear filtering,
  with 4x MSAA. The kit's nearest-neighbour default is for pixel art and made 3D look
  blocky. `ground_point()` / `to_screen()` hide the scale; game code stays in 640x360.
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
  Most kits share one `Textures/colormap.png`; fetch_model fetches it and imports it on
  its own before fetching the models. **A model imported in the same pass as (or before)
  its colormap renders pure white** (it cached a missing texture) -- the cure is to delete
  its `.glb.import` and import again. Seen twice; hence the two-step import in the tool. Quaternius characters embed their
  textures, so they never have this problem.
- **Quaternius people read as cartoons** (big head and hands, near-black skin, white slit
  eyes). Grown-up proportions come from scaling bones: head ~0.64, hands ~0.7, feet ~0.85,
  upper legs 1.16 along Y, abdomen 1.06 along Y, the whole model x1.06 to keep its height.
  Setting `set_bone_pose_scale` once does nothing -- the animation sets every pose each
  frame. Do it from a `SkeletonModifier3D` subclass added under the `Skeleton3D`, in
  `_process_modification_with_delta()`. Reading `get_bone_pose_scale()` back after the
  frame says 1.0 even when it works (the pose is put back after skinning): judge by eye,
  same character side by side at the same distance. Their materials are named `Skin`,
  `Shirt`, `Pants`, `Belt`, `Hair` and `Face` (the eyes, pure white): duplicate them per
  person and give `Face` a darker shade of that person's skin.
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

## Rail games: a road that bends (`reference/drive_by/`)

Do not scroll the world past a fixed camera; **move the camera along a curve** and build
the world in road coordinates. `drive_by` keeps `u` (distance along the road) and `lat`
(sideways, negative = the building side) per thing and `_frame(u)` gives the world
`Transform3D` of the road there (origin on the centre line, +X forward, +Z sideways);
`_road_pos(u, lat, y)` places anything. The centre line is a sum of two sines of `u`, so
it bends gently and never repeats obviously. Road, sidewalk and kerb are 4-unit boxes
placed per segment along the curve (tiny overlaps at the joints are invisible). Things
behind the car (`u < dist - 8`) are freed, the street is built ahead (`u < dist + 42`),
the far skyline the same way further out — with a moving camera, parallax is free.
Head movement is a slow sum-of-sines offset added to the look target in road space, plus
a bob that grows with speed. Aim through `screen_ray()` and march it until it hits your
own surfaces (`_lat_of(p) <= FACADE` or `p.y <= 0`) — there is no physics to ray-cast.
Opening shot: interpolate camera pose from an outside point to the seat, both expressed in
`_frame(0)`, with `ease(k, -2.2)`; fade the 2D interior in over the last quarter.

## Big worlds in a browser

A world of thousands of objects that runs fine on the desktop can crawl in a laptop
browser (WebGL, one thread). Measure before guessing: `view.get_render_info(TYPE, WHAT)`
gives draw calls and triangles for the visible pass and the shadow pass. What cost the
most, in order, last time one did:

- **The default sun shadow is four cascades**: every caster is drawn again per cascade.
  `sun.directional_shadow_mode = SHADOW_ORTHOGONAL` with a short
  `directional_shadow_max_distance` (50-75 m round a chase cam) cut shadow triangles from
  1.5M to under 0.1M. Switch `cast_shadow` off for small or numerous dressing and for the
  ground itself; keep it on what reads (buildings, trees, cars, people).
- **One mesh for the whole map is drawn whole every frame**, behind the camera too, and
  into the shadow map. Cut ground, roads, kerbs into squares (a few hundred m), one
  `MeshInstance3D` each, with a `visibility_range_end`.
- **Visibility range counts to the middle of a node's box**, not its nearest point. A
  multimesh over a 400 m square with a 160 m range draws every copy in the square, and
  none when the camera sits near a corner. Make the squares no bigger than about 0.6x the
  range and add half a square's diagonal to the range.
- **A camera that rises over the world (a zoom-out, a map view) meets every range at
  once.** Visibility ranges and fog both count from the camera, so from 500 m up the
  ground right below is already 500 m away. Thinning the fog with height is needed
  (street-level density turns the town below a washed-out white) but it uncovers the
  range cut-offs: with ranges per square of a few hundred metres, whole squares of trees
  and walls pop in as the view pans. While the camera is up, set every range above a
  threshold to 0 (no limit) and put them back when it comes down; walk the world once,
  then only its new children. Leave the tiny things (signs, people) on their ranges.
  Push `cam.near` out with the height, or paint laid a few cm over asphalt z-fights. And
  lean the view (about 50 degrees down): straight down reads as a plan, not a place. To freeze the world under it without
  `get_tree().paused` (which would freeze the camera too), skip the physics tick and
  set the characters' `process_mode` to disabled, which stops their AnimationPlayers.
  Draw interpolated things at fraction 1 while frozen, or they rock between two ticks.
  Keep the frame-rate watcher (if any) out of it: the whole world in view costs more.
- **A Quaternius character is about eight meshes**: eight draw calls and eight skinnings.
  Thirty of them out-drew the whole city. Give their `MeshInstance3D`s a
  `visibility_range_end` (~90 m) and set `anim.active = false` beyond it.
- **Move the camera per drawn frame, not per physics tick.** A camera tied to the 60 Hz
  tick judders on a 75/120/144 Hz screen or a browser that drops frames. Keep the
  physics in `_physics_process`, blend the drawn pose with
  `Engine.get_physics_interpolation_fraction()`, and to keep `shake3d()` working connect
  that per-frame function to `get_tree().process_frame` *before* `super()` in `_ready()`:
  the shell's own per-frame hook adds the shake on top of `look_from()`, and must run after.
- **Many-surface meshes in a multimesh multiply draws.** A car of six surfaces (paint,
  glass, trim, tyres, lights) costs six draws per batch. One surface with a `ShaderMaterial`
  that reads each part from the vertex colour (alpha as a part code) and the per-instance
  paint from `INSTANCE_CUSTOM` costs one. **Gotcha**: with `use_custom_data` on and
  `use_colors` off, the Compatibility renderer hands the shader a vertex `COLOR` of zero
  (it multiplies in an instance colour that is not there). Turn `use_colors` on and set
  every instance colour to white.
- MSAA is the big pixel cost; `view.msaa_3d` and `view.scaling_3d_scale` can be lowered
  at runtime. Godot caps a frame's time step at 8 physics ticks, so a measured frame rate
  never reads below 7.5 fps however slow the frames really are.
- **Merge the static world into a few big meshes.** Hundreds of separate pieces (road
  surfaces, kerbs, paint, poles, signs) are hundreds of draws. Merging them while the level
  builds into one `ArrayMesh` per square (a few hundred metres) and per draw-range class,
  all with ONE `ShaderMaterial`, took one city view from about 425 draws to 290. The trick
  that keeps the palette: a vertex either carries its colour (alpha 1) or the number of a
  palette tone (alpha 0, the number in red) looked up in a `uniform vec4 tones[64]` table
  the material holds -- `/look` rewrites the table, nothing is rebuilt. Keep what changes
  at night or moves (lamps, lit glass, cars, people) out of it. Watch the vertex count per
  merged mesh (a cap, ~650k, then leave the rest as multimeshes).
- **Step quality down when the browser can't keep up -- and back up.** Watch the frame
  rate in 2-second spells on the web only (natively the test renderer would step itself to
  nothing): step down a level after two slow spells in a row (under ~45 fps, or more than
  one frame in ten over 33 ms). Leave hitches (frames over a quarter second: loading, a
  shader compiling) out of the count -- one half-second stall made a smooth 50 fps read as
  38 and a PC stepped itself to the bottom. And step up again: after 8 s at the display's
  full rate try the level above; a level that fails again waits longer each time (30 s,
  1, 2, 4 min). "Only down, never up" left a PC at the lowest level for the whole drive
  after one bad moment. What a level drops, in order: MSAA, shadow distance, then shadows,
  3D resolution and photo textures. With shadows off, put a soft dark quad under each car
  (one multimesh) or everything floats and the street goes flat.
- **Find stalls by timing the parts.** Time each part of a frame (the script's own work, in
  microseconds) and call a frame much slower than its neighbours a hitch, keeping which
  parts took its time. Every few seconds' stall found that way was periodic work done all
  at once: a minimap re-gathering every outline in range each time the car moved 60 m
  (bucket them once at load), every left-behind AI car respawned in one tick (one a tick),
  an AI planning several legs of its route at once (one a tick), every car deciding its
  speed every tick (20 Hz, staggered).
- **Build a big world near-first; the rest while it runs.** Build it in the same squares
  its meshes are merged into (so pieces cost no extra draws): only the squares round the
  start before the player sees anything, the rest in a coroutine a few ms a frame, nearest
  where the player is heading first. A city that took 7-18 s to load started in 1-3 s.
  What made the squares add up to exactly the old all-at-once world:
  - Anything laid along a line (road surface, paint, kerbs, wires, fences) is worked out
    in full by every square the line crosses, and each square keeps only the triangles
    whose first vertex is in it. Everything else, and whatever it records (posts, parked
    cars, lights), belongs to the one square its anchor point is in, and all its triangles
    go into that square's mesh.
  - One random sequence across the whole world comes out different once the order changes.
    Seed per item (per road, per outline, per grid cell) so every square works out the same
    positions, and draw every random number whether or not the item is placed.
  - Work out only the stretch of a long line near the square (with two points more each
    side so its mitred bends match), or a 3 km road's paint is redone for every square.
  - Pause inside every loop (`if over_budget(): await pause()`), between mesh creations
    (`add_surface_from_arrays` on a big array is several ms), inside polygon subdivision on
    hills, and while letting go of a big parsed JSON (freeing it at once took 40 ms).
  - **A function that contains `await` must be awaited by every caller**, or the part after
    its pause runs later, in another square's context. List the coroutines and grep their
    calls. Pause on a signal the game itself emits once a frame, not `process_frame`: when
    the game is left mid-build, its own signal dies with it and the coroutine just stops.
  - Turn off the frame-rate quality watcher while building: the build is not the machine
    being slow. Check the result by comparing every item count with the old build.
- **Kilometres of small dressing cost in the checks, not the triangles.** A fence or hedge
  along every front garden, laid by the helper that checks each 2.5 m piece for roads and
  houses, doubled a build stage. Timed piece by piece, the look for the nearest road was
  half of it. When a caller already knows the line is clear (it stands on a wall that was
  checked, on a strip that was), pass that down and skip the check; lay one panel per
  piece of the line it follows rather than many short ones; and leave out faces that are
  inside the thing (the ends between two pieces of a hedge). Build stages on these
  containers swing 20% between runs, so time the part itself, not the stage around it.
- **Photo textures under a palette.** Divide the photo by its own average colour and
  multiply by the palette tone: the photo gives the grain, the tone the colour, and `/look`
  still reskins it. Fade fine detail and repeating photos out with distance (a repeat shows
  as a grid far off) and turn them off at the lowest quality level. Variation that needs no
  file at all -- worn patches, grain, slab joints -- is a cheap hash noise (no `sin`) of
  the world position in the fragment shader: nothing to load.

## Self-play

The bots and the ASCII map are 2D and stay that way: `track3d()` keeps a 2D proxy per
tracked node in `play_area` space via `world_area`. So the usual rules apply — track the
thing the player steers as `"@"` (in `drop` it is the ground cursor under the hovering
piece), targets as `"*"`, real threats as `"x"`, and give the main verb an `action_a`
binding. Then `tools/playtest.sh <game> smart 25` and `idle 25` as for any game. Real
frames: `tools/shots.sh <game> smart 9 2` — the headless driver renders nothing, so this
opens a window briefly.

## GDScript and shader gotchas

- `for w in some_array:` leaves `w` untyped, so `var to := goal - w.position` fails to
  parse ("cannot infer type"). Write `for w: Node3D in some_array:` or annotate the var.
- `Rect2.get_center()` gives (x, z) for `world_area`; build the `Vector3` by hand.
- A `MeshInstance3D`'s `global_position` inside a `RigidBody3D` follows the body's
  tumble, which is exactly what per-cell hit checks want.
- A member variable with the same name as a function (`var _blob_mesh` beside
  `func _blob_mesh()`) is a parse error that stops the whole script loading; so is a local
  lambda named like a built-in (`var free := func...`). In a long script, grep the name
  first. `tools/check_script.sh res://game/<name>/<name>.gd` finds these in seconds.
- `{node: true}` keys the dictionary by the *value* of `node`, not the string "node".
- `Geometry2D.clip_polygons(a, b)` returns several polygons: the pieces, and holes when `b`
  lies wholly inside `a`. Take the largest by area (a hole is always smaller than its
  outline) and fix its winding to match the original's if anything relies on it.
- **Cutting a hole in a terrain mesh**: clip each triangle that reaches the hole with
  `Geometry2D.clip_polygons(tri, hole)`, triangulate the pieces, take each new vertex's
  height and normal from the original triangle (barycentric), and wind them as the ground's
  own (clockwise seen from above: `(b - a).cross(c - a).y < 0`) or they vanish from above.
- **A tube seen from inside does not shade itself.** Its faces point inward, so the sun
  sees their backs and casts no shadow: the inside of a tunnel was lit like the street.
  Give its meshes `cast_shadow = SHADOW_CASTING_SETTING_DOUBLE_SIDED` (their own instances,
  not merged into a batch that casts one-sided).
- Polygon-to-segment distance: `Geometry2D.get_closest_points_between_segments()` over the
  polygon's edges, plus a point-in-polygon test for a segment wholly inside.
- **A shader error shows only when something draws with it**, as a `SHADER ERROR` in the
  log, and the material then draws nothing: the script parse check, a headless playtest and
  the bots all pass. Render a screenshot after any shader edit and grep its log. Godot also
  refuses `return` inside `fragment()`: write the cases as `if / else`.
- **Comparing with photos of the real place** finds what a screenshot from the game's own
  camera never shows: stand a camera where a person stands (1.5 m up, on the pavement) and
  look along, across and down, beside frames of a walk there. That is how a row of black
  boxes along every street (painted hollow ground floors on solid buildings) turned up.
- **Writing `ALPHA` anywhere in a shader makes the material transparent** (sorted, no depth
  prepass, other objects show through it oddly), even in a branch that never runs. For an
  opaque and a see-through variant of one shader, prefix the code with `#define CURTAIN\n`
  for one of them and wrap the alpha in `#ifdef` -- two `Shader`s, one source.
- Distance from the camera in a spatial shader: `length((MODELVIEW_MATRIX * vec4(VERTEX,
  1.0)).xyz)` in `vertex()` into a varying (or `length(VERTEX)` in `fragment()`, already
  in view space).
- A procedural `PlaneMesh` lies in X/Z with UV.x across, UV.y along: scale it per instance
  for footprints (soft shadows, decals) rather than building one mesh per size.
