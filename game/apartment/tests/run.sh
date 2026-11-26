#!/usr/bin/env bash
# tests/run.sh <test> [level]: run game/apartment/tests/<test>.gd with a real renderer.
cd "$(dirname "$0")/../../.."
T="${1:-views}"; export LEVEL="${2:-${LEVEL:-1}}"; export OUT="${OUT:-/tmp/apartment_shots}"
mkdir -p "$OUT"
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --path . --rendering-driver opengl3 \
  --audio-driver Dummy -s "res://game/apartment/tests/$T.gd" 2>&1 | grep -v "^$" | tail -40
