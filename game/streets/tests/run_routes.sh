#!/usr/bin/env bash
# Drive the route set (routes.json) and report: maps of each drive and a block in
# routes_results.md. Two at a time, headless at 60 fixed ticks a second, real speed (1x).
#   game/streets/tests/run_routes.sh [route ids...]   (default: all)   OUT=dir for the maps
# About 4-12 minutes a route here (the city's loading is most of a short one); all ten,
# two at a time, ~40-60 minutes.
set -u
# (all in one function, read whole before it runs: an edit to this file while it ran made
# bash read on from the wrong place, 'ython3: command not found')
main() {
	cd "$(dirname "$0")/../../.."
	godot="${GODOT:-godot}"
	out="${OUT:-/tmp/routes}"
	mkdir -p "$out"
	ids=("$@")
	if [ ${#ids[@]} -eq 0 ]; then
		ids=($(python3 -c "import json;print(' '.join(str(r['id']) for r in json.load(open('game/streets/routes.json'))['routes']))"))
	fi
	logs="$HOME/.local/share/godot/app_userdata/GamePlatform/drive_logs"
	mkdir -p "$logs"
	for i in "${ids[@]}"; do rm -f "$logs"/route-"$i"-*.json; done
	: > "$out/results.txt"
	run_one() {
		ROUTE="$1" STREETS_BUILD_ALL=1 timeout 1800 "$godot" --headless --fixed-fps 60 --path . \
			-s res://game/streets/tests/route_set.gd 2>&1 | grep -E "ROUTE RESULT|SCRIPT ERROR|no route" >> "$out/results.txt"
	}
	n=0
	for i in "${ids[@]}"; do
		run_one "$i" &
		n=$((n + 1))
		if [ $((n % 2)) -eq 0 ]; then wait; fi
	done
	wait
	python3 game/streets/tests/route_report.py "$out/results.txt" "$out" "$logs"
}
main "$@"
