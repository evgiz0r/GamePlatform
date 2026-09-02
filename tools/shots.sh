#!/usr/bin/env bash
# Capture real screenshots of a game. Usage: tools/shots.sh <game> [bot] [seconds] [count]
# Runs WITHOUT --headless because the headless driver renders nothing (black frames).
# Images land in shots/ (gitignored).
set -u
GAME="${1:-}"; BOT="${2:-smart}"; SECS="${3:-10}"; N="${4:-2}"
BIN="${GODOT:-}"
if [ -z "$BIN" ]; then
  for c in godot godot4 Godot; do command -v "$c" >/dev/null 2>&1 && BIN="$c" && break; done
fi
if [ -z "$BIN" ]; then
  echo "Godot not found. Set GODOT=/path/to/godot (or add it to PATH)." >&2; exit 1
fi
cd "$(dirname "$0")/.."

# No game named: use the first one there is. Hard-coding a default here means deleting
# that game silently breaks this script.
if [ -z "$GAME" ]; then
  GAME="$(ls game 2>/dev/null | head -1)"
  if [ -z "$GAME" ]; then echo "No games in game/ yet." >&2; exit 1; fi
fi

# First run after a fresh clone has no .godot/ import cache. Without this the engine
# blocks instead of running, which looks like a hang -- the first thing a new user hits.
if [ ! -d .godot ]; then
  echo "First run: importing assets, this takes about ten seconds..." >&2
  "$BIN" --headless --path . --import >/dev/null 2>&1
fi
"$BIN" --path . --rendering-driver opengl3 --audio-driver Dummy -- \
  --sim="$GAME" --bot="$BOT" --seconds="$SECS" --shots="$N" 2>&1 | grep -E "^\[shot\]"
