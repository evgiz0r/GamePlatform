#!/usr/bin/env bash
# Headless self-play. Usage: tools/playtest.sh <game> [bot] [seconds]
# LEVEL=<n> before it starts a game that has levels at that level.
# Set GODOT to your Godot 4 binary if it is not on PATH.
set -u
GAME="${1:-}"; BOT="${2:-smart}"; SECS="${3:-30}"
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
# Assets added since the last import (a merge brought another session's textures) are
# imported too: a run never imports by itself, so it went on without them, quietly
# ("Failed loading resource" in the log, the look missing from every screenshot).
if [ ! -d .godot ]; then
  echo "First run: importing assets, this takes about ten seconds..." >&2
  "$BIN" --headless --path . --import >/dev/null 2>&1
  touch .godot/.import_stamp
elif [ ! -f .godot/.import_stamp ] || [ -n "$(find game assets -name '*.import' -newer .godot/.import_stamp 2>/dev/null | head -n 1)" ]; then
  echo "New assets since the last import: importing them..." >&2
  "$BIN" --headless --path . --import >/dev/null 2>&1
  touch .godot/.import_stamp
fi
"$BIN" --headless --fixed-fps 60 --path . -- \
  --sim="$GAME" --bot="$BOT" --seconds="$SECS" --level="${LEVEL:-0}" 2>&1 \
  | sed -n '/=== PLAYTEST/,/=== END REPORT ===/p'
