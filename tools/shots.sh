#!/usr/bin/env bash
# Capture real screenshots of a game. Usage: tools/shots.sh <game> [bot] [seconds] [count]
# Runs WITHOUT --headless because the headless driver renders nothing (black frames).
# Images land in shots/ (gitignored).
set -u
GAME="${1:-dodge}"; BOT="${2:-smart}"; SECS="${3:-10}"; N="${4:-2}"
BIN="${GODOT:-}"
if [ -z "$BIN" ]; then
  for c in godot godot4 Godot; do command -v "$c" >/dev/null 2>&1 && BIN="$c" && break; done
fi
if [ -z "$BIN" ]; then
  echo "Godot not found. Set GODOT=/path/to/godot (or add it to PATH)." >&2; exit 1
fi
cd "$(dirname "$0")/.."
"$BIN" --path . --rendering-driver opengl3 --audio-driver Dummy -- \
  --sim="$GAME" --bot="$BOT" --seconds="$SECS" --shots="$N" 2>&1 | grep -E "^\[shot\]"
