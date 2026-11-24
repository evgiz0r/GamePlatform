#!/usr/bin/env bash
# The streets validation: the checks that should read 0, in one go, headless, one Godot run
# at a time, and a summary at the end to set beside the last results in README.md here.
#
#   game/streets/tests/validate.sh           quick, ~4 min: the city as built in all four
#                                            towns, and the driving exam in the test town at 2x
#   FULL=1 game/streets/tests/validate.sh    also the exam in Givatayim and Ashdod at 1x and
#                                            the queue check in Givatayim: ~6 min more
#   REGRESS=1 (with or without FULL)         also the tests written for the bugs the user
#                                            reported, each a PASS / FAIL line: ~10 min more
# Tel Aviv (level 7) is in the city checks since 21 Nov: the quick run is ~6 min now.
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
run() {   # name, level, speed, script, timeout; optional EXTRA="VAR=value ..." and FPS=n (or "free")
	local t0=$(date +%s)
	local fps="--fixed-fps ${FPS:-60}"
	[ "${FPS:-}" = "free" ] && fps=""
	# (-u OUT: this script's own OUT is the tests' "save screenshots here" too, and a test
	# taking a screenshot headless hangs -- seat_steady, lane_position and deck_corner ran to
	# their timeouts with no verdict whenever validate.sh was given an OUT)
	env -u OUT LEVEL="$2" STREETS_SIM_SPEED="$3" ${EXTRA:-} timeout "$5" "$godot" --headless $fps --path . \
		-s "res://game/streets/tests/$4.gd" > "$out/$1.txt" 2>&1
	echo "  $1: $(( $(date +%s) - t0 )) s" >&2
}
echo "validating into $out ..." >&2
for l in 1 2 3 4 7; do run "city$l" "$l" 1 city_check 1200; done
run exam4 4 2 exam 1800
if [ -n "${FULL:-}" ]; then
	run exam1 1 1 exam 3600
	run exam3 3 1 exam 3600
	KNOT_AT="-800,-288" SECS=2400 run queue1 1 2 queue_start 3600
fi
if [ -n "${REGRESS:-}" ]; then
	# the tests written for the bugs the user reported, each ending in one "REGRESS <name>:
	# PASS|FAIL -- ..." line (what it measures, the value, the good band and what the bug read).
	# Timeouts about 3x each one's time here (8-125 s): the first run had one stall each in
	# seat_steady and deck_corner, not seen again in 4 runs of each -- "NO VERDICT" and its log
	# say so in minutes, not a quarter of an hour
	EXTRA="STREETS_BUILD_ALL=1" run re_median_cross 4 1 median_cross 180
	EXTRA="STREETS_BUILD_ALL=1" run re_traffic_motion 1 1 traffic_motion 300
	EXTRA="STREETS_BUILD_ALL=1" run re_seat_steady 1 1 seat_steady 300
	EXTRA="STREETS_BUILD_ALL=1" run re_lane_position 1 1 lane_position 300
	EXTRA="STREETS_BUILD_ALL=1" run re_deck_corner 2 1 deck_corner 360
	EXTRA="STREETS_BUILD_ALL=0" run re_turn_width 1 1 turn_width 300
	EXTRA="STREETS_BUILD_ALL=0" run re_hitches 7 1 hitches 360
	EXTRA="STREETS_BUILD_ALL=0" run re_auto_stands 7 2 auto_stands 600
	EXTRA="STREETS_BUILD_ALL=0 FROM=45" FPS=10 run re_walk_people 6 1 walk_people 300
	EXTRA="STREETS_BUILD_ALL=0" FPS=free run re_start_soon 1 1 start_soon 180
	EXTRA="STREETS_BUILD_ALL=0" run re_load_bar 1 1 load_bar 240
	# (object permanence: people and cars popping, sliding or on a street in view; 90 s of
	# autodrive in Givatayim, ~5 min headless)
	EXTRA="STREETS_BUILD_ALL=1" run re_people_pops 1 1 people_pops 900
	# (driving, 24 Nov, each 1-2 min here: traffic turning round in cul-de-sac estates, 120 s at Bedford's
	# Meadowview; autodrive and the people stepping into its lane, 3 trips down Hollyhock;
	# racer through a railing and the panel falling)
	EXTRA="STREETS_BUILD_ALL=1 SECS=120" run re_traffic_pockets 2 1 traffic_pockets 900
	EXTRA="STREETS_BUILD_ALL=1 TRIPS=3" run re_people_near 2 1 people_near 900
	EXTRA="STREETS_BUILD_ALL=1" run re_rail_break 25 1 rail_break 900
	EXTRA="STREETS_BUILD_ALL=1" run re_corner_post 1 1 corner_post 900
fi
echo
echo "=== STREETS VALIDATION ($(git rev-parse --short HEAD)) ==="
for l in 1 2 3 4 7; do
	grep -h -E "^CITY CHECK [^:]|^  (walls|posts|buildings) on the road|^  lit points alone|^  ((signs|walk lights|lights|bus stops) doubled|posts twice|parked |lights: |junction offers twice|islands on the road|median over a road|road leaning|two pavings)" "$out/city$l.txt" 2>/dev/null
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
for f in "$out"/re_*.txt; do
	[ -f "$f" ] || continue
	n=$(basename "$f" .txt); n=${n#re_}
	grep -h "^REGRESS " "$f" || echo "REGRESS $n: NO VERDICT (crashed or timed out: see $f)"
	grep -q "SCRIPT ERROR" "$f" && echo "  !! SCRIPT ERROR in $n"
done
echo "(0 is good everywhere; compare the rest with tests/README.md's last results)"
