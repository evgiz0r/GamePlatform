---
name: scene-tests
description: 'Scripted scene tests for a game -- a SceneTree script that loads the game, stages one situation (the player somewhere, an AI sent at it, a quality level, made-up frame times), measures it, prints numbers and saves screenshots. Use when a bug is spatial or visual, when the user sends a screenshot of something wrong, when the bots cannot reach the situation, to compare before and after a fix, or to keep a regression test. Especially for 3D games.'
---

# Scene tests: stage it, measure it, look at it

The bots (`tools/playtest.sh`) tell you a game runs and can be played. They cannot tell you
that a person is walking in the road, that a car parks inside a wall, that a texture
vanished at a quality level, or that the AI deadlocks in one narrow street. For those,
write a small script that loads the game, puts things where the bug is, measures it, and
saves a picture. It is how almost every 3D bug in this kit has been found and proved fixed.

Keep the good ones in the game's own `tests/` folder (with a `run.sh` and a README saying
what each prints and what a good result is), not in a scratch directory: they are the
regression tests for the fixes they proved.

## The skeleton

```gdscript
extends SceneTree
## What this measures, in a sentence; what a good result is.
var g: Node
func _initialize() -> void:
	_run()
func _snap(name: String) -> void:
	await create_timer(0.5).timeout           # let ranges / LODs settle after a camera move
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("OUT") + "/" + name + ".png")
func _run() -> void:
	await create_timer(0.3).timeout
	root.get_node("Flow").start_game("<game>", {"level": int(OS.get_environment("LEVEL"))})
	while g == null or not g._loaded:          # poll: a fixed wait breaks on a slower machine
		await create_timer(0.25).timeout
		for n in root.find_children("*", "Node2D", true, false):
			if n.get_script() != null and String(n.get_script().resource_path).ends_with("<game>.gd"):
				g = n
	# ... stage, measure, snap ...
	print("what: %d of %d (%.1f%%)" % [bad, seen, 100.0 * bad / maxf(seen, 1)])
	quit(0)
```

(`_loaded` is whatever flag the game sets once it is built; add one if it has none.)

Run it with a real renderer under a virtual display -- `--headless` draws nothing:

```bash
LEVEL=3 OUT=/tmp/shots xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . \
  --rendering-driver opengl3 --audio-driver Dummy -s res://game/<game>/tests/<test>.gd
```

A game's `tests/run.sh <test> [level]` wraps that line (see an existing one).

## Ways in

- **Simulate, don't sleep.** `for f in range(60 * 30): await physics_frame` runs 30 s of game
  time however slow the machine is; `create_timer` waits wall time and the game may do far
  less in it on a slow box.
- **Freeze for stills.** `g.set_physics_process(false)` and disconnect the game's per-frame
  function (`process_frame.disconnect(g._frame)`), then place the camera with
  `g.look_from(eye, target)` and snap. Unfrozen, the game's own camera moves it back.
- **Stage the situation directly.** Put the player at a point and heading, send one AI car
  at it down a chosen road, set a quality level, drop the car in a courtyard. Waiting for it
  to happen by itself costs minutes and may never happen in a test run.
- **Put a looking-down camera well above the roofs** (30 m and more in a town), not at
  roof height: a camera 9 m up over a junction sat just above a building, and its flat
  roof filled half of every shot as a featureless pale plane -- it looked exactly like the
  ground failing to draw, and cost two runs to see it was the camera.
- **Find the subject by searching**, not by coordinates you guessed: the nearest instance
  of a mesh to the start, a road that runs out to the map's edge with a clear run, the
  divided-road zebra nearest the start.
- **Measure a rate, broken down by cause.** "29% of walkers on asphalt: 444 on service
  lanes, 161 on the inner side of divided roads" pointed straight at both fixes. Then the
  same test after the fix: 0%.
- **Log why something stands still.** Each second the AI is stopped, print what holds it
  (the car ahead and its distance, something solid at its nose, a light, people, a choice
  pending, reversing). A deadlock reads itself out.
- **Make logic testable by splitting the guard from the judgement.** A frame-rate watcher
  that only runs on the web can't be tested natively; split it into `_watch_fps(dt)` (the
  `OS.has_feature("web")` check) and `_judge_fps(dt)` (the logic) and feed the second
  made-up frame times: a 50 fps PC with a 0.48 s stall every 5 s, a 35 fps phone, recovery.
- **Record what the old rule would have done**, when the fix changes a decision made while
  building: keep a debug list in the game of the places where old and new disagree, count
  them, and look at a few. That is the before/after without keeping two builds.
- **Compare pictures side by side.** Python with PIL: crop the same region from two shots
  and paste them into one sheet. Differences that are invisible flipping between files are
  obvious next to each other.

## When the user saw it and you cannot: a recorder

A report like "it drove into the bus" names a moment you will not hit in a test run. Give
the game a flight recorder: a ring buffer of the last minute or two at ~10 Hz (the player's
pose and controls, what the AI planned and *why it chose its speed*, the actors nearby,
events), a debug page that draws it as a map, and a button that saves it --
`JavaScriptBridge.download_buffer(text.to_utf8_buffer(), name, "application/json")` in a
browser, a file under `user://` elsewhere. Ask the user for the file, draw it with a small
script (Python and Pillow are enough: the level's own data gives the map), and stage that
spot in a scene test. Record the reason for each decision, not just the outcome: "held by:
car" against "held by: zebra" is usually the whole diagnosis. Record what it was doing
instead of driving too (backing off, turning round, pushing against something without
moving): a log once read "speed limit" at 0 km/h for a minute because the plan wanted the
limit while the car was pressed against a post. And record *which* thing held it (the car
in front by its id, the wall by its index) -- for the other actors as well as the player's.

## A scored run: the exam

Once there is a recorder, a script can drive the AI from several places for a minute or
so each and count what went wrong per minute (stuck, hits by kind, off the road, wrong
side, red lights, harsh braking, and the other actors' own stalls and overlaps), listing
the worst places with the log of the moments before each. Fix the top of the list, run
again, compare. Check what each counter really counts before chasing its number: one
counted frames of braking (30 per stop), another judged a car mid-turn by the heading it
had at that moment, and both sent a round of work the wrong way.

## Showing the user

The user reads pictures, not tables -- a per-minute scorecard of a dozen rows was "hard to
read". What worked: the map of one drive, the path coloured by speed with a legend for the
colours, **street names** on it (the streets driven in bold, the main roads in grey; a
real town's names give the user their bearings at once), start and end marked, a strip of
speed against time coloured by what held the car; the same drive before and after side by
side under a one-line title each; and a few bullets of what changed. Send each picture as
it is made, with a one-line caption, rather than a report at the end.

## Gotchas (each cost a run)

- **Don't annotate with a `class_name` type that uses autoloads** (`var a: Actor3D`) in a
  `-s` script: it is compiled before the autoloads exist and fails ("Identifier not found:
  Probe"), taking the whole test with it. Use the base type (`Node3D`).
- `var x := g.some_member` cannot infer a type through an untyped node: annotate it.
- **Forget `OUT` and the screenshots land in `/`.** Check the folder after the first run.
- A script error mid-test prints `SCRIPT ERROR` and the test may hang to its timeout: grep
  the output for it, and always run under `timeout`.
- `grep` in a pipe holds its output until the process exits; use `--line-buffered` to
  watch progress.
- A test that is already running keeps the code it loaded; one that starts later in a
  queued batch picks up your newer edits (and the newer bugs).
- The software renderer's frame rates are meaningless in absolute terms. Compare levels
  or before/after on the same box, never against a target. Anything that steps quality
  down by frame rate must be off natively, or every test run steps itself to nothing.
- **New assets from a merge are not imported** until something runs the importer: a test
  run straight from the engine draws without them ("Failed loading resource" in the log).
  Run `$GODOT --headless --path . --import` after merging, or use a runner that does it
  when it sees `.import` files newer than its last import (as `tools/playtest.sh` does).
- **Compare sizes side by side at the same distance.** A before/after lineup with the
  "after" row nearer the camera hid a 26% smaller head completely: perspective made up the
  difference. Same character, same depth, one changed and one not.
- **A game that builds its world in the background is not finished when it says loaded.**
  Wait for its "all built" flag, or have the runner switch the background build off, before
  measuring anything away from the start.
- **A portrait window still gives a 16:9 picture.** The project keeps its aspect, so a
  test run at `--resolution 406x720` (to match a phone's upright video) saved 406x228
  shots, and tiling them to the phone's shape stretched them into nonsense. Render 16:9
  (1280x720) and crop the middle: `ffmpeg -vf crop=406:720:437:0`. Mind that the crop sees
  far less sideways than the shot: check the whole frame before deciding something is
  missing.
- Parse-check first: `tools/check_script.sh res://game/<game>/<game>.gd` takes seconds and
  says which line; a broken script makes a scene test fail in a confusing way minutes in.

## On a slow cloud container

**Tests that measure behaviour should not pay for looks.** The software renderer is bound by
pixels and per-pixel shader work: when a game gained photo textures and per-pixel traced
windows, a frame went to ~0.8 s and every simulation test ran out of time. Have such tests
drop the game to its lowest quality level and use a smaller window (`--resolution 960x540`)
unless asked otherwise (an env var like `FULL=1`); keep full quality for the tests whose
point is a picture.

A city that builds in 5 s on a laptop can take 15 there, and a minute of game time five of
wall time. Run tests with the shell's background mode and a long timeout, chain several
in one script (two Godot runs at once on 4 cores is about the limit), and carry on working.
A foreground command is cut off at 10 minutes, and a `&` job inside it does not outlive it.
