# me -- developer notes

## Making the videos

    FPS=30 tools/record_video.sh me <level> <seconds> out.mp4

(under `xvfb-run -a -s "-screen 0 1280x720x24"` in a cloud session). Levels and their
lengths are `LEVELS` in `me.gd`; give a second or so more than `secs`, `film_done()` stops
it. At 1280x720, 30 fps the four together took about 4.5 minutes here (23 Nov 2026).

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

## The realistic version (Blender, not Godot)

`realistic/make.sh` builds a real-proportioned human and films him with real motion capture.
It runs Blender as a Python module (`pip install bpy`, so the cloud sessions need no Blender)
and reads only data, never add-on code:

- **Body**: MakeHuman's base mesh and shape targets (CC0, from the makehuman repo; the mpfb2
  repo's own `targets/` are empty placeholders -- its real targets ship as a separate download
  that is not reachable). Shape values are `TARGETS` in `build_me.py`.
- **Rig**: MPFB's `rig.cmu_mb.json` + `weights.cmu_mb.json` (CC0): bone names are exactly
  the CMU BVH names, so retargeting is name to name. Joints sit at the mean of each
  `joint-*` helper cube.
- **Clothes**: cut from his own skin surface (a copy of the body's faces), relaxed, pushed
  out and given thickness; the skin under them is deleted so nothing pokes through. MakeHuman's
  `helper-tights` shell gave him a female-looking chest -- don't use it.
- **Hair**: a Curves object (60 k strands was slow, 30 k is enough), roots sampled on the
  scalp by *direction from the skull's centre* (`HL` in `build_me.py`: front, temples, sides,
  nape) with jitter, rigid on the Head bone, over a dark scalp shell. The `helper-hair` shell
  is a long-hair helmet with cards: don't emit from it. Particle hair took its velocity as the
  length (hair half a metre long).
- **Eyes**: procedural iris/pupil round each eyeball's forward axis (the eye helpers' UVs do
  not fit `brown_eye.png`). **Stubble**: a per-vertex mask baked at rest -- Object texture
  coordinates follow the deformed mesh, so a mask built from them painted stubble on a
  forearm raised past the face.
- **Motion**: CMU mocap (`mocap.py`): world-space rotation deltas from the BVH's rest, with
  a per-bone swing aligning his A-pose rest to the BVH's T-pose rest; hips height = CMU hips
  height x leg-length ratio (CMU's floor is z=0). Clips: walk 16_15, wave 141_16, dance
  113_04, explain 18_08 (index in the cmu-mocap repo). The first frame of a CMU clip is
  often a T-pose: start a few frames in.
- **Rendering**: EEVEE through EGL on the CPU (llvmpipe): `apt-get install libegl1
  libegl-mesa0` first or it fails with "Couldn't open libEGL.so.1". About 22 s a frame at
  854x480, 8 samples, using under two cores -- two renders at once double the throughput.
  Cycles at 640x360 / 32 samples was ~30 s a frame.

Still missing for a likeness: his face. A head scan (Avaturn .glb or a photo-fitted head)
would replace the MakeHuman head; the body, clothes and motion stay.
