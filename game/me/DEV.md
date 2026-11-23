# me -- developer notes

## Making the videos

    FPS=30 tools/record_video.sh me <level> <seconds> out.mp4

(under `xvfb-run -a -s "-screen 0 1280x720x24"` in a cloud session). Levels and their
lengths are `LEVELS` in `me.gd`; give a second or so more than `secs`, `film_done()` stops
it. At 1280x720, 30 fps the four together took about 10 minutes here.

Stills of one moment, to check a pose without a video (seconds):

    LEVEL=4 AT="1.5,6,13" xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
      --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 -s res://game/me/tests/stills.gd

## How the poses work

The Quaternius clips have Walk and Idle but no wave, dance or teaching. Those are posed by
hand on top of Idle every frame:

- The AnimationPlayer is switched to manual (`callback_mode_process = MANUAL`) and advanced
  in `_tick()` **before** the pose code runs. Left on its own it updates after `_process`
  and wipes any bone set there.
- `aim(bone, dir, w)` turns a bone so its +Y (which runs along the limb in these rigs)
  points along `dir`, given in the avatar's own space: +X its left, +Y up, +Z the way it
  faces. Parents first: `get_bone_global_pose` of a child is fresh after its parent is set.
- `reach(side, world_point)` aims upper arm, forearm and fist at a point (writing, pointing).
- `twist(bone, axis, deg)` for torso sway and head nods.

Twist along the limb is ignored -- fine for fists, would show on a hand with fingers.

## Gotchas met

- `model()` returns a node that is **not** in the tree: `world.add_child()` it. (The lamps
  were missing from the first stills.)
- `Casual_Male` wears shorts; `Casual2_Male` has long trousers, which is what he wears.
- The skin read as white under the key light at 1.4: key 0.7, ambient 0.4.
- Dance floor tiles in bright palette colours, lit by four coloured lights, washed out to
  white: tiles are the role colour darkened 70% with a faint glow.

## Swapping in a real face

A .glb of him (Avaturn or similar, Mixamo-style humanoid skeleton) will have different bone
names (`mixamorig:RightArm`...), its limbs along a different axis, and no Quaternius clips.
What changes: a bone-name map in `aim()`/`reach()`, a walk clip from elsewhere (Mixamo) or
the procedural one, and `BODY` loading from `game/me/` rather than `assets/characters3d/`.
