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
  to happen by itself costs minutes and may never happen in a test run. For two drivers
  meeting at a junction: clear the rest of the traffic (and keep it off), send the other
  car when the player is ~35 m out at the distance that makes them arrive together, and
  skip the case when the map makes it not a meeting (where the main road bends, the car
  "from the side" came up behind instead).
- **When a fix changes nothing to the decimal, the code you changed is not reached.** Put a
  print at each filter before it (behind an env variable, taken out after) and run the one
  case: a decision that ignored a car turned out, three times running, to drop it at a
  filter upstream of the one being tuned.
- **Put a looking-down camera well above the roofs** (30 m and more in a town), not at
  roof height: a camera 9 m up over a junction sat just above a building, and its flat
  roof filled half of every shot as a featureless pale plane -- it looked exactly like the
  ground failing to draw, and cost two runs to see it was the camera.
- **Find the subject by searching**, not by coordinates you guessed: the nearest instance
  of a mesh to the start, a road that runs out to the map's edge with a clear run, the
  divided-road zebra nearest the start. Search what the game *built*, not the file it built
  it from: a game that lets go of its source data once the world is up (to save memory)
  hands a test looking there an empty list, and the test reports "0 found" for things
  standing in plain sight.
- **Look at a building's front from the middle of the road**, facing it at eye height: from
  the far pavement the cars parked along the kerb hide the shopfront, and a replayed walk's
  camera looks along the street, past what stands at its side. To check that something was
  placed (a hydrant by a wall, a shop's awning), aim one still straight at it.
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

## Cameras and motion: measure the swing

A camera effect that reads well in one screenshot can be sickening in motion -- a look-round
added to a first-person view fed the steering into the camera twice, and every small
correction the AI made swung the view ("chaotic, it jumps around"). Before shipping a
camera or body-motion change, measure it over a minute of driving: how far the view turns
from ahead, how fast, how often it swings back. And measure in game time, not drawn
frames: on a slow test machine a frame is several physics ticks, and counting each as
1/60 s inflated the turning speed tenfold. For vehicles that look like they "jump", measure
the rear axle's sideways speed -- a real car's is about zero; a body pointed along its
path from its middle swings its back out at every corner.

**A camera set beside a real film: measure the film too.** Two numbers carried a replay of
a phone film further than any amount of looking. *Where the horizon sits*: tile the film one
frame a second with a line drawn at a fraction of the frame's height, the replay likewise,
and read off where the street's vanishing point falls in each. A pinhole camera tipped p
below level puts it at 0.5 - tan(p) / (2 tan(fov/2)) of the way down, so a few hundredths
of the frame are degrees of tilt (one replay sat at 0.36 against the film's 0.30: 11 degrees
down against 16, the street seen too level). *How the hand shakes*: the image's shift from
frame to frame by phase correlation (numpy FFTs, no OpenCV needed), summed into angles, the
slow turns taken out with a 1 s running mean, then rms and the spectrum. A phone's
stabiliser takes the steps' jolts out: what is left is a slow drift of a few tenths of a
degree at about 0.5-0.8 Hz, not a bob at the step rate, so a replay should sway slowly
rather than bounce. Measure on straight stretches only: through a corner the image moves
too far between frames, the correlation locks on the wrong peak, and it reads tens of
degrees of nonsense. Run the same measure on the replay's recording -- it shows what the
replay does, not what the code was meant to do. *The picture*: levels at 1-99%, the share
clipped, saturation and the near-greys' colour, one frame a second over both, then a tone
curve that maps one's levels onto the other's -- a phone's HDR squeezes its bright end and
lifts its shade, which by eye passed for "a blown-out sky" and was the opposite. Content
differs (the game's materials are not the street's), so fit a moderate warmth rather than
the whole gap (fitted freely it turned grey pavers mauve) and look at the graded frames
beside the film before trusting the numbers. A canvas shader over the finished frame reads
the same 8-bit sRGB a recording saves, so a grade fitted on recorded frames in numpy carries
into the game exactly -- check it with the same moments graded and bare. *Exposure*: a
phone's brightness second to second barely moves (it exposes for what it sees) while a
fixed-exposure replay's swings with the scene -- a roofed arcade read half the film's, and no
curve or exposure lifted it until the floor's own colour was fixed: measure the two apart. A
shader can meter the whole frame off the screen texture's mipmaps (`filter_linear_mipmap`, a
few `textureLod` taps at a high mip) in the Compatibility renderer too; paint the reading
in a corner once and compare it with the frame's true mean before trusting it.
*Which way it faces and how far things are*: the fronts across a street sit level in the
frame when the camera faces square to them, and stripes or kerbs tilt toward the side it is
turned to; a thing's foot y of the way down the frame is tilt + atan((y - 0.5) * 2 tan(fov/2))
below level, so eye height / tan of that is how far off it stands. A wait that read by eye as
"looking left for the traffic" faced straight across, two metres back from where the replay
stood. Read the film four frames a second for this, not one: at one a second a car that
passed in a second and a half, and the turn of the head, fell between the frames.
*The whole walk's movement*: on every frame (30 a second, where a turn is a few pixels a frame),
sum the far band's slide across for the facing and take the ground band's slide down less the
far band's for the pace (a pinhole's numbers turn pixels into degrees and metres). Read each
band as several tiles and take the median: a car passing fills a tile, and a whole-band
reading followed it for 60 degrees. Measure the replay by logging its camera, not from its
recording: its repeating paving slid more than one repeat between frames and read a fifth of
its pace. Line the two facings up on a straight stretch -- summed over a minute and a half the
film's drifted by a degree or two -- and the differences are the head's turns to copy (the
head = the film's facing less the body's) and the pace's shape to copy (the share of each
stretch's distance, between landmark times kept, since a replayed place's lengths are not
the real one's). The up-and-down summed this way is not usable: while the camera looks down,
its far band is ground, and walking forward reads as tipping down. And the summed facing reads
a turn short wherever the "far" band is near: under an arcade it held the ceiling, the columns
and motorbikes a metre or two off, the walker's own steps slid them as much as a turn did, and
a 90-degree turn along the arcade read 50 -- the head fitted to it pointed the replay at the
shop windows from half a metre for six seconds. Check a fitted facing against the frames
wherever the scene closes in (arcades, columns, a car filling the frame), and there take the
facing from the frames (what is level, what the stripes and kerbs point at) instead.

**Pull a film's frames by decoding, not by a fast seek.** `ffmpeg -ss T -i clip.mp4` (the
seek before the input) jumps by keyframes, and on one phone clip it returned the same frozen
frame for every time in its first 8 s -- a whole pass's "it faces straight across at 1-2.5 s"
was read off that frame, and the replay looked the wrong way for its first five seconds.
`ffmpeg -i clip.mp4 -ss T` decodes up to the time (slower: fine for a few frames), or check that
two nearby times give different pictures before measuring anything on them.

**A test that jumps a scene's clock cannot show what is timed by it.** Stills taken by
setting a replay's time and running a third of a second skip every scripted event in
between: cars sent at a second never drove their distance, and the stills showed none of
them. Log timed things at the scene's own pace from its start (a trace every quarter second
of what is near) or record it.

**Checks that should read 0, every tick.** Counting what went wrong per minute finds the
big things; checks of what must never happen find the bugs before anyone looks for them.
Each is a kind of bug already fixed once, written so it cannot come back unseen: bodies
overlapping (measured by their outlines -- see "the whole body, not its middle" in the
`real-places` skill), a body into a wall or post, standing over the stop line at a red,
pushing against something without moving, and standing still with nothing named holding it
(follow what holds it down the queue: a car that holds the next one is a reason, the speed
limit at a standstill is not). Print every check with its count even at 0, so a reader
sees it ran. The first version of a check finds its own false alarms first (the front of a
queue in its moment to react at a green read "held by nothing"): run it once in the small
test town and read every hit before trusting the number. When a check fires, print the
last few seconds of everyone involved with it (speed, what it wanted, what held it, a few
times a second): a car "held by nothing" is usually explained by what it did just before,
and without that history each one costs a staged re-run.

**A check of the world as built**, before anything drives it: walls, posts and buildings
on the road, a junction's points each deciding alone, roads too short to have a direction.
Seconds a city, so run it on every city after changing how one is laid out.

**A target from the real world, not from the last run.** A behaviour tuned by eye swings
both ways: one queue at a green went all at once within 0.3 s, the fix had its third car
move 9 s after the green, the next fix again. Real numbers exist for most of what traffic
does (cars cross a stop line about 2 s apart once a queue is moving, Greenshields 1947 and
the Highway Capacity Manual); put them in the test as bands it passes or fails.

**A fix comes with what would catch it again**: the scene test that staged it, or a check
in the scored run. Half of one day's twenty fixes had neither, and were guarded only by a
per-minute total that random traffic moves about anyway. And about half of those twenty
bugs had been made the same day -- by the change before, or another session's -- so after
merging, run the quick checks (the world check, the route scans) before pushing.

**And that test ends in a verdict, and the game's validation runs it.** A test that prints
numbers for a reader is run once, by the session that wrote it. Of thirty bugs a user
reported in one day, nineteen got a test of their own and nothing ever ran one again; the
validation built the day before caught three of the thirty. End each with one line --
`REGRESS <name>: PASS|FAIL -- <measure> <value> (good <band>; the bug: <what it read>)` --
with the band from the fix's measured result and the bug's, not tighter than the run-to-run
spread, and add it to the validation script's list. Check the verdict on the bug's own code
(the commit before the fix, the new test copied in) and on several healthy runs: a seat
view's angle off ahead read 8.1 for the bug and 1.4-8.6 for healthy drives, as a drive
took more corners or fewer -- useless -- while its turning speed read 0.29 against
0.05-0.13. A check of the world as built goes into
the world check instead, run on every level, not only the one the bug was found in: ported
there, the paving-laid-twice check found 578 m2 flickering in a town nobody had looked at,
and a road-tilt check a town never levelled -- the same bugs, unfixed where no report came
from. Where such a measure never reads 0, give each level a limit at what a fixed level
reads, and let an unfixed level fail until it is fixed: a limit set at whatever it reads
today hides the bug the check was written for.

## Showing the user

The user reads pictures, not tables -- a per-minute scorecard of a dozen rows was "hard to
read". What worked: the map of one drive, the path coloured by speed with a legend for the
colours, **street names** on it (the streets driven in bold, the main roads in grey; a
real town's names give the user their bearings at once), start and end marked, a strip of
speed against time coloured by what held the car; the same drive before and after side by
side under a one-line title each; and a few bullets of what changed. Send each picture as
it is made, with a one-line caption, rather than a report at the end.

## Gotchas (each cost a run)

- **Read braking over half a second, not a tick.** A follower that steps its speed to its
  target each tick (an AI car at its hard-braking limit) reads 7.5 m/s^2 in every case; a car
  coming to rest whose last creep is zeroed reads 15. Average the speed's drop over ~30 ticks
  and count only the moments the thing you test is the reason (`why == "player"`).
- **A test that puts the car back at the same place resets "the last one passed".** State
  kept per place for a while after passing it (the last lit junction crossed, for 120 m
  driven) goes on applying when a test -- or the game's own "go to" -- sets the car down by the
  same place again: the car ignored the red there and the red went uncounted, every case
  reading "on through, no red". If every case reads the same however you vary it, suspect the
  staging before the code under test, and reset such state wherever the car is put down.
- **A scripted actor whose timing drifts run to run: log its every field from its first
  tick.** Pooled objects (cars, people taken from a pool and put down again) carry their
  last life's state unless the put-down resets it. One scripted car, sent "at the road's
  pace", kept its last life's smoothed acceleration of -7 m/s^2 and braked from 9 to 3 m/s
  over its first 2 s with nothing ahead, its reason reading "limit" and its wanted speed 14:
  only the per-tick line of speed, wanted speed and acceleration showed it. It had passed in
  time on most runs (the object it got had been cruising), so the earlier timing spread of
  0-1.5 s had been put down to traffic noise. When the reason and the target say "go" and
  the speed falls, look at the smoothed state between them.
- **A "last thing hit" that probes also write is not a hit.** A game whose collision helper
  records what it touched every time it is called -- by the planner checking a lane spot, by
  the AI's look-ahead at its nose -- shows "wall 6156" (130 m away) as the last hit. Count a
  hit only with the game's own crash flag (here `_crash_cool`), and find what really blocked
  the AI by calling the same probe yourself at that moment.
- **Hold a parked player by hand on a hill** (its position and speed each physics frame):
  with nobody at the pedals it rolls down a 15% street, 100 m in a case.

- **People that appear only out of sight are never in a still.** A game that places its
  extras (people in chairs, at stops) only where the player cannot see them appear leaves
  a staged camera looking at empty seats, however long it waits. Stand at the spot facing
  away for a few of the game's placing ticks, then turn and take the shot.

- **Headless, a multimesh's copies read back as nothing.** `--headless` has no real
  rendering server: `MultiMesh.get_instance_transform()` returns the identity, so a test
  reading where a copy was put (a dog at a walker's side) gets (0, 0, 0) for every one and
  measures nonsense (2112 "dogs across a fence"). Have the game keep the positions it set in
  its own data for tests to read, or run the test with a display.

- **A collision scan sees only what is solid, and only where it is solid.** A scripted walk
  that scanned clean went through a parked bike's wheel (solid only at its rack's hoop, while
  the bike reached across most of the pavement) and ended with a tree's trunk filling the
  frame; chairs, crates and low leaves have no collider at all. Beside the scan, list
  everything drawn by instance round the spot (each `MultiMeshInstance3D` instance's box
  through its transform: where, how big, how high it starts) and look at the recording one
  frame every 2 s.

- **Measure the exact condition, and name the blocker once.** "Stood still near the van" also
  counted waiting at a red light past it; "within 20 m, the van ahead, held by a car" did
  not. And when a thing does not happen, print once, a few seconds in, what holds it (which
  car, how far off the path its middle is, the flags that gate it) -- one diagnostic line
  found a bend applied 40 m behind the car after three runs of guessing.

- **Don't annotate with a `class_name` type that uses autoloads** (`var a: Actor3D`) in a
  `-s` script: it is compiled before the autoloads exist and fails ("Identifier not found:
  Probe"), taking the whole test with it. Use the base type (`Node3D`). A cast counts too
  (`x as Actor3D`), and the damage reaches past the test: the class stays broken for the
  run, so the game's own `Actor3D.new()` fails and the city has no people -- a crossing test
  ran "PASS" with every case quietly erroring out on an empty list of crossers.
- **Do the work in `_initialize()`, never `_init()`.** In `_init()` the autoloads are not up
  yet, so `load()`ing the game's own script there (even just to read a constant) fails
  ("Compilation failed"), and the error comes before `quit()`: the run sat silent until its
  10-minute timeout.
- `var x := g.some_member` cannot infer a type through an untyped node: annotate it.
- **Forget `OUT` and the screenshots land in `/`.** Check the folder after the first run.
  The same with two jobs started at once: `SP=dir && (job1 > $SP/a.log) & (job2 > $SP/b.log)`
  sets `SP` for the first only -- the second wrote its log to `/b.log`. `export` it first.
- **`await RenderingServer.frame_post_draw` never returns under `--headless`**: a test that
  takes a shot there hangs until its timeout, silently (a run "took 25 minutes" that way and
  printed nothing). Skip shots when `DisplayServer.get_name() == "headless"`, or run the shot
  test under xvfb (`tests/run.sh` does).
- **A check that never fires may be running too early.** One worked out while loading
  (walls along a raised road, leaving out pieces on a street) asked a lookup grid that is
  only built later in the load: it answered "no street" everywhere and the fix changed
  nothing, two runs in a row. When a fix has no effect, print what the check sees at the
  moment it runs, not afterwards.
- A script error mid-test prints `SCRIPT ERROR` and the test may hang to its timeout: grep
  the output for it, and always run under `timeout`. One in the background goes on taking
  a core until then, slowing every run beside it: kill it once you have seen the error.
- `grep` in a pipe holds its output until the process exits; use `--line-buffered` to
  watch progress.
- A test that is already running keeps the code it loaded; one that starts later in a
  queued batch picks up your newer edits (and the newer bugs).
- The software renderer's frame rates are meaningless in absolute terms. Compare levels
  or before/after on the same box, never against a target. Nor can it show a browser's
  stalls: with every frame of a big city at ~0.8 s, a hitch log there measures the renderer.
  What carries over is counts (draw calls, triangles, vertices, nodes, shader kinds) and the
  script's own time; a GPU stall needs the user's browser (a profiler view in the game). Anything that steps quality
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
- **Freezing the game for stills freezes what follows the camera.** With the game's frame
  stopped (so its camera does not move yours back), anything it moves with the camera each
  frame -- a sky dome, a far-off ground plane -- stays where it was: a shot a kilometre away
  was a flat blank, the camera outside the dome. Call the game's own follow step after
  placing the camera. And a view that blends between physics ticks (drawn at the last
  tick's position and heading lerped to this one) keeps blending from the last tick
  while physics is stopped: set the "previous" values with the new ones, or the shot
  looks along the player's old heading.
- **A game may let go of its source data once it is built** (a city's file, outlines, lists
  per square freed a little a frame after the last square): a test that reads them after
  "loaded" (and a runner that builds everything first makes that at once) hits an empty
  array mid-run. Have the module record what a test needs as it sets up, and read that.
- **Pick a still's eye over open ground.** An eye placed by coordinates alone stood inside a
  cafe's arcade, and two more had a tower a few metres in front: three of five shots
  wasted, ten minutes a run. Put it over a road (a street's points are in the data), or high
  over the roofs, and aim at the subject's middle.
- **A marker for a 3D shot goes in the game's 3D world**, not under the game's node: a
  3D game's own node is a 2D one, and a ring added under it is never drawn.
- **A skinned model's box is its rest pose's.** `MeshInstance3D.get_aabb()` (and the shell's
  `aabb_of`) knows nothing of bones scaled at run time, so a game that resizes a figure's
  head or legs through its skeleton draws it at a height the box does not say. Measure
  against what the game asked for and how it scales, not the box alone. Drawing a figure
  alone in a `SubViewport` with its own world, to measure its silhouette, came out empty
  (the figure moved into it was not drawn): do not spend a run on it.
- **Put a body down at the level of what is there.** A test that places a car or a walker
  at a point usually gives it the ground's height: on an embankment or a bridge it then
  drives along underneath, and the run reports "drove nothing" with no error. Start it on
  the highest surface at that point when the point is on something raised.
- **A collision's label is not a collision.** A game's "last hit" text can be rewritten by
  anything that probes for room (placing people tries spots every tick), so counting label
  changes counts noise. Count the ticks where the body moved other than its own step
  (displacement minus heading x speed x dt) and read the label only then.
- **Test where a stop ends up, not only that it stopped.** A stop test that broke off the
  moment the car stood read "stopped, 3-11 m short of the line" as a pass -- and a little
  short was the visible end of a bug: the braking had a floor, so from farther off the car
  stopped far short, and standing (nothing left to brake for) it stayed there all through
  the red, 60 m from the light, in the middle of the street. Keep watching a few seconds
  after it stands and check where it waits; and stage the far case (a light 80 m off), not
  only the near ones the rule was written for. A number a test prints as "a little off" is
  worth one more case before it goes on the open list.
- **A seeded drive may repeat, but do not count on it.** The same code drove the same route
  twice to the tenth of a second -- and the same code and route beside a heavier run went
  otherwise, and old code put back to replay a moment parted from the first drive within
  50 s: anything timed by the wall clock (a build's time budget, work spread over frames by
  how long they took) feeds the randomness. So a one-off seen in a drive (a car cutting in)
  will not come back for a second look: log enough the first time (what was in front, its
  heading and lane, what held it), or stage it in a scene test.
- **A speed lost with nothing hit: divide it.** A drop to an exact fraction of the speed in
  one tick (13.74 -> 8.24 m/s, x0.6) is the game's own multiplier for some event; grep the
  game for `*= 0.6` and the culprit is named (here a sign knocked flat, not a crash).
- Parse-check first: `tools/check_script.sh res://game/<game>/<game>.gd` takes seconds and
  says which line; a broken script makes a scene test fail in a confusing way minutes in.

## On a slow cloud container

**Numbers do not need pictures.** A test that drives something and counts what went wrong
can run headless (`$GODOT --headless --fixed-fps 60 --path . -s res://...`, the screenshot
calls skipped when `DisplayServer.get_name() == "headless"`): two minutes where the same
run under the software renderer took twenty. Render only for the shots, and only the runs
that need them.

**A function from data to data needs no game at all.** When the question is what one step
of the load makes of the data (heights worked out for a map, a parser, a picker), call it
straight from a `-s` script on the data file: no scene, no world built, no renderer, so
several maps in the time one load would take. Read the game's constants from its script
(`load("res://game/<game>/<game>.gd").SOME_CONST`, in `_initialize()`, see Gotchas). To get
more out of it than it reports (a list it caps), load a scratch copy with the cap raised
rather than touching the game.

**Tests that measure behaviour should not pay for looks.** The software renderer is bound by
pixels and per-pixel shader work: when a game gained photo textures and per-pixel traced
windows, a frame went to ~0.8 s and every simulation test ran out of time. Have such tests
drop the game to its lowest quality level and use a smaller window (`--resolution 960x540`)
unless asked otherwise (an env var like `FULL=1`); keep full quality for the tests whose
point is a picture.

**Running the simulation faster than real time** (more game time a tick) pays for
behaviour counted over minutes, and three things are in the way:
- **The shell puts `Engine.time_scale` back to 1** when a game starts and after every
  hit-stop, so Godot's `--time-scale` flag is undone before the first tick (it measured 1x
  three times over before anyone noticed). Have the game hold a speed from an environment
  variable every tick (dev only: unset in play, nothing happens).
- **Tests that count time as 1/60 a tick** misread every duration once a tick is longer:
  count `Engine.time_scale / Engine.physics_ticks_per_second`.
- **A longer tick changes what is measured tick by tick**: braking measured as speed lost
  per tick reads gentler, anything counted in ticks shrinks, coarse steps overlap more.
  Run the same test twice at 1x first -- one game's exam differed by half between two 1x
  runs -- and accept a speed whose counts stay within that spread (there: 2x yes, 3x no).
  The same before calling a change a regression: run the base branch beside yours (a git
  worktree with `.godot` copied in) -- one exam read 11 and 12 on a branch and "7-9" in the
  notes, and the base itself read 8 and 12.
  A pass/fail check over a noisy measure is no better: near variants of one change read
  1.19 to 1.62 on a queue check's 40-minute watch, so a bisect over single runs chased
  noise. Run base and candidate back to back on a doubled watch before bisecting, and do
  it in a worktree, not by copying versions over the file in your own tree: while the
  copy stands the tree cannot be committed or merged.
  Keep 1x for how driving feels (crashes, steering, frames) and for numbers written down.

A city that builds in 5 s on a laptop can take 15 there, and a minute of game time five of
wall time. Run tests with the shell's background mode and a long timeout, chain several
in one script (two Godot runs at once on 4 cores is about the limit), and carry on working.
A foreground command is cut off at 10 minutes, and a `&` job inside it does not outlive it.

## A bench for judging looks

Trying a look on a real town costs minutes a picture: loading it is most of a run. A tiny
made-up place in the same data format (a street or two, a dozen buildings of the kinds that
matter, a few shops and trees), loaded by a test only, takes seconds and shows the same
materials, kits and lights. Put the looks being tried behind a test-only switch (an
environment variable read once, off by default), shoot the same fixed views with each, and
lay them side by side; then keep what reads best. Mind what the generator leaves to the game:
anything it adds by itself (made-up street trees, parked cars) can stand in front of the very
thing a view is aimed at, so give the bench enough of its own to stop that, and aim cameras
from where a person would stand (the middle of the street, the kerb), not from inside the
next garden. A shot that waits for a drawn frame never returns headless: run such a bench
with rendering on.
