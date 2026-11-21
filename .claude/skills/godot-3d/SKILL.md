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
  A band along something whose ground is already drawn with coordinates across it (a
  pavement whose UV is metres out from the kerb) is cheaper as a term in that ground's
  shader, flagged in a spare vertex channel, than as strips of its own: the same band
  cost 40 ms of build as geometry and nothing as a shader term.
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
- **Grass blades without millions of triangles.** One patch of blades in a grid that moves
  with the camera a patch at a time, the vertex shader growing each blade only where a
  top-down mask says grass grows (paint the mask into a spare channel of a picture you bake
  anyway) at the ground's height (the height grid as a float texture, `texelFetch`, the same
  triangles the game interpolates on). With `cull_disabled` the renderer turns a back face's
  normal to the ground: flip it back (`if (!FRONT_FACING) NORMAL = -NORMAL;`) or every blade
  seen from behind is black. Fade by the camera's 3D distance, or from above you pay for
  blades you cannot see.
- **People who walk through things.** Walkers on a fixed line need steering, not just a
  push: look a step ahead for anything solid and edge off the line before it; for other
  people, step away from whichever side they are on and hold it until past (reacting only
  to someone "ahead" lets them drift back as they draw level and brush); then push out of
  whatever is left, twice. Measure it: sample everyone's overlaps over a run.
- **Things the car knocks over, in a merged world.** Merged meshes cannot hide one copy, so
  give the knockable kinds multimeshes of their own (a draw or so a square near the eye),
  keep a map from each one's collision post to its multimesh copy, and on a hit hide or
  bend that copy and throw a RigidBody3D with its mesh -- with a slab to land on, if the
  world has no physics of its own -- and put it back once the player is out of sight. Make
  sure a braking assist does not brake for what is meant to be knocked aside.
- **Split the costliest builder by distance, not the squares by number.** When one kind of
  dressing is most of the wait before the player can move (front gardens were 0.7 s of
  3.9), lay only the part within the first view's reach while loading, remember what the
  rest needs (its inputs, not its results), and lay it first thing in the background
  build, nearest first. Deterministic keys make it the same either way -- prove that with
  a test that counts the result both ways (an env switch for the old way), or it will
  quietly drop or double things at the seam.
- **Built in squares, decided the same in every square.** When one square's builder needs
  something another square builds (where a building's door is, to lead a path to it), work
  it out again from the data with the same choices, cached by id -- never read what the
  other square's builder stored, which is not there yet when that square comes later.
- **Night glow without a glow effect.** A bloom over the frame costs a browser a millisecond
  or two a frame; a halo per light, drawn additively in the same mesh as the light's pool on
  the ground (every vertex of its quad at the light, the corner in UV, turned to the eye in
  the vertex shader with `skip_vertex_transform`, sized at least ~1% of the distance so far
  lamps stay points -- 0.4% left a tower's red roof lights invisible at 400 m, 1.1% made
  them ~6 px) costs nothing extra. As a MultiMesh of quads grown in the shader, give it an
  `extra_cull_margin`: its box is the unscaled quad's, and far ones are culled. Two traps: an additive material that is fogged
  gets the fog colour *added* (far pools turned into cyan blobs at night: use
  `fog_disabled` and fade by distance yourself), and a glow decal laid at the road's height
  is under the pavement (lay it above the highest surface it can fall on).
- **Golden hour is warm light and cool shade.** A sunset HDRI tonemapped to the day sky's
  brightness came out as a plain day; keep it darker (half the exposure) so its glow
  survives. Don't put the light where the photo's sun is (5 degrees up made every shadow 12
  times the height of what cast it): 12-15 degrees still reads as evening. Tint the sun
  orange (yellow alone looked lemon), light the shade with the sky's blue rather than grey
  haze (with haze the shadows went khaki), and let the fog glow towards the sun
  (`fog_sun_scatter`). Anything baked for one sun's direction (painted shadows, offsets)
  either moves in a shader by a uniform or is baked again per sun and kept.
- **Wet ground: dark, and only the puddles glossy.** Lowering a whole road's ROUGHNESS
  to make it wet lets the renderer's ambient reflection (with a colour background, that
  flat colour, at Fresnel's full strength at a low angle) wash over it: it came out pale
  grey, the opposite of wet, and sunlit paving at 0.6 flared white. Darken the albedo by
  about half, keep the soaked surface rough-ish (~0.7, SPECULAR 0.3), and make puddles
  (noise in the dips) the near-mirrors (0.08) that catch the sky and the sun's glare. A
  reflection of the sky added as EMISSION (reflect the view, Fresnel, sky colours) wants a
  darker band low down where a street's buildings would be.
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
- **A Quaternius figure is six draw calls**, one per material (each surface is a draw, and
  another in the shadow pass): a crowd of them costs more than a city block. Join the
  surfaces into one (concatenate vertices, normals, bones, weights, offset the indices; they
  share one skin), put each vertex's part number in its colour, and draw it with a shader
  holding the person's colours in a `uniform vec4 parts[6]` -- one draw a person. Build the
  joined mesh once per figure and share it (a mesh per person is ~0.7 MB); the material is
  per person. Pass colours as `srgb_to_linear()` (a plain uniform array is not converted).
- **No `visibility_range_end` on a multimesh that spans the world.** The distance is measured
  to the instance node's own middle -- for a city-wide multimesh (dogs, pushchairs moved
  about by code, a custom AABB over the whole map) that is the city's middle, so the whole
  multimesh vanished whenever the camera was ~90 m from it, wherever the copies were. Hide
  far copies yourself (a transform 500 m down) and leave the range off.
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
gives draw calls and triangles for the visible pass and the shadow pass (in one test run
under the Compatibility renderer it read 0 throughout; `RenderingServer.get_rendering_info(
RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)` and its `_PRIMITIVES_`/`_OBJECTS_`
siblings gave the whole frame's). Counts like these are the same on any machine, so a test
container's software renderer can measure them even though its frame times mean nothing.
Then list what is in view by material and add up its triangles: the biggest single item
is rarely the one you would guess. What cost the most, in order, last time one did:

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
  range and add half a square's diagonal to the range. (Forgotten once for a city's parked
  cars -- grouped by the 400 m squares the city is built in, a 140 m range drew every one
  out to 420 m: 1.24 M of a 2.4 M-triangle frame. In 100 m squares, the full car out to
  ~70 m and a plain few-dozen-triangle shape with its own `visibility_range_begin` past it:
  0.3 M.) A distant copy needs only the silhouette: the same side outline pushed across the
  width reads as the same car at 80 m.
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
  merged mesh (a cap, ~650k, then leave the rest as multimeshes). And merge only what is
  few or small: a detailed kit with thousands of copies (an AC unit on every other wall:
  ~19,000 x ~230 vertices) copies its vertices into the batch every time -- a hundred MB or
  so of vertices city-wide, and uploading the fatter batches made 50 ms frames while the
  city built in the background (19 hitches in 25 s, from 3). Instanced (a MultiMesh per
  square) it is one copy of the kit and 64 bytes a copy, for a draw or two near the eye.
- **Step quality down when the browser can't keep up -- and back up.** Watch the frame
  rate in 2-second spells on the web only (natively the test renderer would step itself to
  nothing): step down a level after two slow spells in a row (under ~45 fps, or more than
  one frame in ten over 33 ms). Leave hitches (frames over a quarter second: loading, a
  shader compiling) out of the count -- one half-second stall made a smooth 50 fps read as
  38 and a PC stepped itself to the bottom. And step up again: after 8 s at the display's
  full rate try the level above; a level that fails again waits longer each time (30 s,
  1, 2, 4 min). "Only down, never up" left a PC at the lowest level for the whole drive
  after one bad moment. What a level drops, in order: MSAA, shadow distance, 3D resolution
  and photo textures -- **never the shadows themselves**. In the Compatibility renderer a
  directional light's shadows on or off is a different shader for every material, so a
  level that switched them off made the browser compile them all again: a freeze of
  seconds on every step between that level and the next, over and over as the ladder went
  down and back up (a user saw 3.2 s). Keep shadows on at the bottom with a short reach
  (25 m round the car) instead; anything else a level changes should be a shader parameter
  or a buffer size, not a material's feature.
- **What a browser compiles is shader CODE, not materials.** A ShaderMaterial compiles its
  Shader once per variant (drawn plain or instanced, and again for the shadow pass when it
  casts shadows); a StandardMaterial3D's shader is generated from its switches (flags, modes,
  which textures are set) and shared by every material with the same set -- its colours and
  numbers are uniforms. So merging look-alike standard materials saves nothing, while two
  `Shader.new()`s with the same code compile twice (make one and share it). Count it before
  cutting: group the drawables by Shader / switch set x plain or instanced x shadow -- one
  city's 77 materials were 25 codes, 43 programs -- and step a warm-up by that grouping, not
  by material, or one step gets every material of one shader (no work) and another a dozen
  shaders. Don't call `_get_shader_rid()` from a script (it hung the engine). And locally the
  GLES3 renderer keeps compiled programs in `user://shader_cache`, so after the first run
  nothing compiles here at all: compile counts and stalls can't be seen on the test machine,
  only counted from the scene.
- **A merged mesh is a triangle soup; index it in pieces.** Built as triangles, a merged mesh
  repeats most vertices (a quad's two triangles share two). `SurfaceTool`'s `index()` (C++)
  shared them: 9.8 M -> 5.4 M vertices, 187 -> 121 MB. But the web build has no threads: the
  biggest mesh whole took 30 ms on the main thread, so index at most ~30,000 vertices at a
  time, each piece a surface of its own (that also keeps 16-bit indices), the frame handed
  back between them -- and the extra surfaces are draws, so skip it where the build is
  behind a loading screen if load time matters more than memory.
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

### Shader programs: count them in a browser

(What compiles is shader code -- the bullet on it above. This is how to see it, and what
else costs programs.)

- **Count in a real browser.** Locally nothing compiles after the first run (the shader
  cache), but a web export can be run in Playwright's Chromium with an init script wrapping
  `WebGL2RenderingContext.prototype.linkProgram`: count the programs linked before, during
  and after the game's warm-up, and name each by its variant's `#define`s and its material's
  uniform names. Count, don't time: under SwiftShader the status check after a compile also
  waits for the frames before it, seconds of software rendering.
- **About seven programs a game shader**: drawn alone and as a multimesh, the shadow map's
  depth pass for both, and an **additive pass for every light that casts shadows** -- in the
  Compatibility renderer the sun with shadows on is a second pass with its own variant for
  every lit shader.
- **A `#define` variant is another shader.** Two looks of one thing (a barrier and its
  see-through curtain) as one shader with a uniform switch compile once.
- **Before switching a built-in material's flag to share a shader, look for code that reads
  the flag** to mean something else (a batcher keeping anything with emission on out of its
  merged meshes, lights that switch emission at night).

## Self-play

The bots and the ASCII map are 2D and stay that way: `track3d()` keeps a 2D proxy per
tracked node in `play_area` space via `world_area`. So the usual rules apply — track the
thing the player steers as `"@"` (in `drop` it is the ground cursor under the hovering
piece), targets as `"*"`, real threats as `"x"`, and give the main verb an `action_a`
binding. Then `tools/playtest.sh <game> smart 25` and `idle 25` as for any game. Real
frames: `tools/shots.sh <game> smart 9 2` — the headless driver renders nothing, so this
opens a window briefly.

## GDScript and shader gotchas

- **A sky dome that follows the camera must be a whole sphere, not `SphereMesh`'s
  hemisphere.** `is_hemisphere = true` closes the dome with a flat disc at its middle's
  height -- standing on the eye, a plane through the eye. Edge-on it should draw nothing,
  and the software renderer here never does; a phone's GPU drew it now and then, a pixel
  high, straight across the screen at the horizon in the dome's horizon colour, even over
  near hedges (its depth runs from the eye outwards). A test can't see it unless it stands
  the dome a couple of millimetres below the eye (the GPU's rounding, made bigger): then the
  hemisphere draws a band across every frame and a whole sphere nothing. A cylinder or any
  mesh with a cap at the eye's height does the same.

- **A shader that branches on a number (a surface kind, a tone's code) tests each value's
  range on both sides: `fx.w > 3.5 && fx.w < 4.5`, never `fx.w > 3.5`.** Two sessions each
  added a "kind 4" within the hour; git merged the two shaders without a conflict, and the
  one-sided test swallowed every higher kind, so a paved passage drew as the other's garden
  wall stones. After merging a shader, list its branches and the table that feeds them.

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
- **A varying that seeds a hash must be `flat`** (`varying flat float id;`). Interpolated,
  its value differs in the last bits from pixel to pixel even when every vertex wrote the
  same number, and `fract(sin(x) * 43758.5)` turns those bits into a different result in
  each pixel: per-copy digits drawn from such an id came out as garbled blocks.
- **More per-instance data than `INSTANCE_CUSTOM`'s four channels**: the Compatibility
  renderer stores instance colour and custom data as half floats, so whole numbers are
  safe only while small. Pack a few states into a channel holding a 0..1 value by adding
  twice a small integer (`c + 2.0 * k`, decoded `k = floor(c * 0.5)`, `c - 2k`): up to 15
  the value keeps 1/128 of precision. State in alpha as steps of 2, 8, ... above a 0..1
  fraction works the same way.
- **An emissive light at 3x and more goes white in daylight.** The tone curve clips every
  channel, so a brake light or an indicator lit at 3 reads white, not red or amber. Light it
  with a fully saturated colour (from a palette role with its saturation pushed to ~1) at
  1.3-1.8.
- Distance from the camera in a spatial shader: `length((MODELVIEW_MATRIX * vec4(VERTEX,
  1.0)).xyz)` in `vertex()` into a varying (or `length(VERTEX)` in `fragment()`, already
  in view space).
- A procedural `PlaneMesh` lies in X/Z with UV.x across, UV.y along: scale it per instance
  for footprints (soft shadows, decals) rather than building one mesh per size.
