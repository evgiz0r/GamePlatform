#!/usr/bin/env bash
# The streets validation: the checks that should read 0, in one go, headless, one Godot run
# at a time, and a summary at the end to set beside the last results in README.md here.
#
#   game/streets/tests/validate.sh           quick, ~10 min: the city as built in all four
#                                            towns, and the driving exam in the test town at 2x
#   FULL=1 game/streets/tests/validate.sh    also the exam in Givatayim and Ashdod at 1x and
#                                            the queue check in Givatayim: ~1 h more
#
# It changes nothing and fixes nothing: it reads the game and prints counts. Each run's whole
# output is in $OUT (default /tmp/streets-validate), the drive logs of the worst places under
# Godot's user:// drive_logs. Run it in the background (a foreground command is cut off at 10
# minutes), and not beside another Godot run if the times matter. What each count means and
# what to do with it: "The checks that should read 0" in DEV.md.
set -uo pipefail
cd "$(dirname "$0")/../../.."
godot="${GODOT:-godot}"
out="${OUT:-/tmp/streets-validate}"
mkdir -p "$out"
if [ ! -f .godot/.import_stamp ] || [ -n "$(find game assets -name '*.import' -newer .godot/.import_stamp 2>/dev/null | head -n 1)" ]; then
	"$godot" --headless --path . --import >/dev/null 2>&1 || true
	mkdir -p .godot && touch .godot/.import_stamp
fi
export STREETS_BUILD_ALL=1
run() {   # name, level, speed, script, timeout
	local t0=$(date +%s)
	LEVEL="$2" STREETS_SIM_SPEED="$3" timeout "$5" "$godot" --headless --fixed-fps 60 --path . \
		-s "res://game/streets/tests/$4.gd" > "$out/$1.txt" 2>&1
	echo "  $1: $(( $(date +%s) - t0 )) s" >&2
}
echo "validating into $out ..." >&2
for l in 1 2 3 4; do run "city$l" "$l" 1 city_check 1200; done
run exam4 4 2 exam 1800
if [ -n "${FULL:-}" ]; then
	run exam1 1 1 exam 3600
	run exam3 3 1 exam 3600
	KNOT_AT="-800,-288" SECS=900 run queue1 1 2 queue_start 3600
fi
echo
echo "=== STREETS VALIDATION ($(git rev-parse --short HEAD)) ==="
for l in 1 2 3 4; do
	grep -h -E "^CITY CHECK [^:]|^  (walls|posts|buildings) on the road|^  lit points alone" "$out/city$l.txt" 2>/dev/null
	grep -q "SCRIPT ERROR" "$out/city$l.txt" && echo "  !! SCRIPT ERROR in city$l"
done
for e in exam4 exam1 exam3; do
	[ -f "$out/$e.txt" ] || continue
	grep -h "^EXAM" "$out/$e.txt"
	grep -h -E "^  check: " "$out/$e.txt" | grep -v " 0   0.00 a minute"
	grep -h -E "^CHECKS: " "$out/$e.txt"
	grep -q "SCRIPT ERROR" "$out/$e.txt" && echo "  !! SCRIPT ERROR in $e"
done
[ -f "$out/queue1.txt" ] && grep -h -E "^  (start gaps|line gaps|first car)|^QUEUE CHECK" "$out/queue1.txt"
echo "(0 is good everywhere; compare the rest with tests/README.md's last results)"
