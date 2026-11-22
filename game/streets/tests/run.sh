#!/usr/bin/env bash
# Run one of this game's scene tests: a script that loads a city, stages something (the car
# somewhere, a car sent at it, a quality level) and prints what it measured; most also save
# screenshots. See README.md here for the list and what "good" looks like for each.
#
#   game/streets/tests/run.sh <test> [level]        level: 1 Givatayim, 2 Bedford, 3 Ashdod,
#                                                  4 the made-up test town, 5 the filmed walk,
#                                                  7 Tel Aviv (default 1)
#   OUT=/some/dir game/streets/tests/run.sh map_edge 3
#
# Screenshots go to $OUT (default /tmp/streets-tests/<test>). The tests that measure behaviour
# drop the game to its lowest quality first (FULL=1 keeps it). Needs a display: on a
# headless box it runs under xvfb-run. These are slow on a cloud container (a minute of
# game time can take five of wall time): run them in the background with a long timeout.
set -euo pipefail
cd "$(dirname "$0")/../../.."
test="${1:?which test? (ls game/streets/tests/*.gd)}"
level="${2:-1}"
export LEVEL="$level"
# the whole city built before the test starts (the game builds near the start first and the
# rest while you drive; a test looking elsewhere would find it not up yet). A test of that
# loading itself sets STREETS_BUILD_ALL=0.
export STREETS_BUILD_ALL="${STREETS_BUILD_ALL:-1}"
export OUT="${OUT:-/tmp/streets-tests/$test}"
# the player's saved choices (user://streets_prefs.json) neither read nor written: a test starts
# from the defaults and leaves this machine's choices alone (STREETS_PREFS=1 to test them)
export STREETS_PREFS="${STREETS_PREFS:-0}"
mkdir -p "$OUT"
godot="${GODOT:-godot}"
# assets newer than the last import (another session's textures, merged in): import first,
# or the run draws without them
if [ ! -f .godot/.import_stamp ] || [ -n "$(find game assets -name '*.import' -newer .godot/.import_stamp 2>/dev/null | head -n 1)" ]; then
	"$godot" --headless --path . --import >/dev/null 2>&1 || true
	mkdir -p .godot && touch .godot/.import_stamp
fi
x=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
	x=(xvfb-run -a -s "-screen 0 1280x720x24")
fi
# SIM_SPEED=n: n times as much game time a tick (the engine's time scale), so a run needs n times
# fewer ticks a game second. For behaviour counted over minutes (the exam, traffic, queues,
# dead ends, lights) -- not for how driving feels (crashes, steering, the seat view, filmed
# walks, recorded frames), where each tick's precision is the thing measured. What it changes
# and the numbers: "Faster runs" in README.md here. Tests count time by the real tick
# (Engine.time_scale / Engine.physics_ticks_per_second), never by 1/60.
# (Not --time-scale: the shell puts the time scale back to 1 when a game starts. The game holds
# STREETS_SIM_SPEED itself, every tick.)
if [ -n "${SIM_SPEED:-}" ] && [ "${SIM_SPEED}" != "1" ]; then
	export STREETS_SIM_SPEED="$SIM_SPEED"
fi
# a smaller window: the software renderer is bound by pixels (RES=1280x720 for big shots);
# GODOT_ARGS: more engine flags, e.g. "--fixed-fps 10" to record frames at a steady clock
# HEADLESS=1: no window at all (the checks of a test that also shoots, without its shots) --
# a window takes the focus from whatever the person is doing on this machine
if [ "${HEADLESS:-0}" = "1" ]; then
	exec "$godot" --headless --path . --audio-driver Dummy ${GODOT_ARGS:-} -s "res://game/streets/tests/$test.gd"
fi
exec "${x[@]}" "$godot" --path . --rendering-driver opengl3 --audio-driver Dummy --resolution "${RES:-960x540}" \
	${GODOT_ARGS:-} -s "res://game/streets/tests/$test.gd"
