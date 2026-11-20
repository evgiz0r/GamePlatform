#!/usr/bin/env bash
# Parse-and-compile check for one or more scripts, headless, in seconds:
#   tools/check_script.sh res://game/<name>/<name>.gd [more.gd ...]
# A script that does not compile makes the game fail to load with nothing on screen to say
# why; this says which line. Run it after editing a long script and after every merge.
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${GODOT:-godot}" --headless --path . -s res://tools/check_script.gd -- "$@" 2>&1 \
	| grep -vE "^(Godot Engine|WARNING: .*vsync|   at: )"
