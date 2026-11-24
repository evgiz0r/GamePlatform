#!/usr/bin/env bash
# Make a 3D model with Blender, from a recipe: a short Python script that builds it with the
# helpers in tools/blender/kit.py, run headless; the result is written as a .glb.
#
#   tools/blender_model.sh tools/blender/recipes/slide.py            -> assets/models/made/slide.glb
#   tools/blender_model.sh tools/blender/recipes/slide.py out.glb    (somewhere else)
#   tools/blender_model.sh --all                                     every recipe in tools/blender/recipes/
#   tools/blender_model.sh --preview assets/models/made/slide.glb    a picture of one (Workbench render)
#
# Blender is found at $BLENDER, on PATH, or where its installer puts it (Windows, macOS,
# Linux). Not every machine has it (the cloud sessions do not): the .glb files are committed,
# so a game uses them anywhere; only remaking one needs Blender. After making new ones,
# import ($GODOT --headless --path . --import) and list them in assets/INDEX.md.
set -u
cd "$(dirname "$0")/.."

BIN="${BLENDER:-}"
if [ -z "$BIN" ]; then
  if command -v blender >/dev/null 2>&1; then
    BIN="blender"
  else
    for c in "/c/Program Files/Blender Foundation"/Blender*/blender.exe \
             "/Applications/Blender.app/Contents/MacOS/Blender" /usr/bin/blender /snap/bin/blender; do
      [ -x "$c" ] && BIN="$c"
    done
  fi
fi
if [ -z "$BIN" ]; then
  echo "Blender not found: set BLENDER=/path/to/blender (the committed .glb files work without it)" >&2
  exit 1
fi

make_one() {
  local recipe="$1" out="${2:-}"
  if [ -z "$out" ]; then
    out="assets/models/made/$(basename "${recipe%.py}").glb"
  fi
  mkdir -p "$(dirname "$out")"
  # --factory-startup: no user add-ons or preferences in the way; the recipe's own output
  # and Blender's errors are kept, the rest of its chatter dropped
  "$BIN" -b --factory-startup --python "tools/blender/run.py" -- "$recipe" "$out" 2>&1 \
    | grep -E "^(MADE|RECIPE|Error|Traceback|  File|    )" || true
  [ -f "$out" ] || { echo "FAILED: $recipe made no $out" >&2; return 1; }
}

if [ "${1:-}" = "--preview" ]; then   # a picture of a made model: --preview <model.glb> [out.png]
  model="${2:?which .glb?}"
  out="${3:-${model%.glb}_preview.png}"
  "$BIN" -b --factory-startup --python "tools/blender/preview.py" -- "$model" "$out" 2>&1 | grep -E "^(PREVIEW|Error|Traceback)" || true
  exit 0
fi
if [ "${1:-}" = "--all" ]; then
  status=0
  for r in tools/blender/recipes/*.py; do
    make_one "$r" || status=1
  done
  exit $status
fi
[ $# -ge 1 ] || { echo "usage: tools/blender_model.sh <recipe.py> [out.glb] | --all" >&2; exit 1; }
make_one "$1" "${2:-}"
