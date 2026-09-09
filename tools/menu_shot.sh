#!/usr/bin/env bash
# Screenshot the main menu into shots/menu.png -- the one screen tools/shots.sh cannot
# reach, since that starts straight into a game. Worth a look whenever the number of games
# changes: the menu is the thing that overflows. Set GODOT if it is not on PATH.
set -u
BIN="${GODOT:-}"
if [ -z "$BIN" ]; then
  for c in godot godot4 Godot; do command -v "$c" >/dev/null 2>&1 && BIN="$c" && break; done
fi
if [ -z "$BIN" ]; then
  echo "Godot not found. Set GODOT=/path/to/godot (or add it to PATH)." >&2; exit 1
fi
cd "$(dirname "$0")/.."
[ -d .godot ] || "$BIN" --headless --path . --import >/dev/null 2>&1
RUN=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
  RUN=(xvfb-run -a -s "-screen 0 1280x720x24")
fi
"${RUN[@]}" "$BIN" --path . --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/tools/menu_shot.gd" 2>&1 | grep -E "^\[shot\]"
