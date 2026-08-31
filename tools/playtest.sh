#!/usr/bin/env bash
# Headless self-play. Usage: tools/playtest.sh <game> [bot] [seconds]
# Set GODOT to your Godot 4 binary if it is not on PATH.
set -u
GAME="${1:-dodge}"; BOT="${2:-smart}"; SECS="${3:-30}"
BIN="${GODOT:-}"
if [ -z "$BIN" ]; then
  for c in godot godot4 Godot; do command -v "$c" >/dev/null 2>&1 && BIN="$c" && break; done
fi
if [ -z "$BIN" ]; then
  echo "Godot not found. Set GODOT=/path/to/godot (or add it to PATH)." >&2; exit 1
fi
cd "$(dirname "$0")/.."

# First run after a fresh clone has no .godot/ import cache. Without this the engine
# blocks instead of running, which looks like a hang -- the first thing a new user hits.
if [ ! -d .godot ]; then
  echo "First run: importing assets, this takes about ten seconds..." >&2
  "$BIN" --headless --path . --import >/dev/null 2>&1
fi
"$BIN" --headless --fixed-fps 60 --path . -- \
  --sim="$GAME" --bot="$BOT" --seconds="$SECS" 2>&1 \
  | sed -n '/=== PLAYTEST/,/=== END REPORT ===/p'
