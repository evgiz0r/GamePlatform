#!/usr/bin/env bash
# What is in a 3D asset: bounding box, meshes, animation clips.
# Usage: tools/model_info.sh res://assets/models/car/sedan.glb [more...]
set -u
BIN="${GODOT:-}"
if [ -z "$BIN" ]; then
  for c in godot godot4 Godot; do command -v "$c" >/dev/null 2>&1 && BIN="$c" && break; done
fi
if [ -z "$BIN" ]; then
  echo "Godot not found. Set GODOT=/path/to/godot (or add it to PATH)." >&2; exit 1
fi
cd "$(dirname "$0")/.."
if [ ! -d .godot ]; then
  "$BIN" --headless --path . --import >/dev/null 2>&1
fi
"$BIN" --headless --path . -s tools/model_info.gd -- "$@" 2>&1 | grep -E "^(==|   )"
