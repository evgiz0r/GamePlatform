#!/usr/bin/env bash
# Pull CC0 Kenney 3D models (.glb) into assets/models/<kit>/ from the shorepine/kenney
# mirror on GitHub. Usage: tools/fetch_model.sh <kit> <name> [name...]
#   tools/fetch_model.sh car sedan taxi van
#   tools/fetch_model.sh food utensil-fork plate
# Kits + names: https://github.com/shorepine/kenney/tree/main/3d  (all CC0, see assets/CREDITS.md)
# Afterwards: import ($GODOT --headless --path . --import), then add the names to
# assets/INDEX.md -- the index is the only thing standing between the AI and a guessed path.
set -u
KIT="${1:-}"; shift || true
if [ -z "$KIT" ] || [ $# -eq 0 ]; then
  echo "usage: tools/fetch_model.sh <kit> <name> [name...]" >&2; exit 1
fi
cd "$(dirname "$0")/.."
BASE="https://raw.githubusercontent.com/shorepine/kenney/main/3d"
mkdir -p "assets/models/$KIT"
# Most kits share one texture next to the models. Fetch it FIRST: a model imported before
# its colormap exists caches a missing texture and renders pure white until re-imported.
if [ ! -f "assets/models/$KIT/Textures/colormap.png" ]; then
  mkdir -p "assets/models/$KIT/Textures"
  if curl -sfL "$BASE/$KIT/Textures/colormap.png" -o "assets/models/$KIT/Textures/colormap.png"; then
    echo "fetched assets/models/$KIT/Textures/colormap.png (shared kit texture)"
  else
    rmdir "assets/models/$KIT/Textures" 2>/dev/null
  fi
fi
ok=0
for n in "$@"; do
  if curl -sfL "$BASE/$KIT/$n.glb" -o "assets/models/$KIT/$n.glb"; then
    echo "fetched assets/models/$KIT/$n.glb ($(du -k "assets/models/$KIT/$n.glb" | cut -f1) KB)"
    ok=$((ok+1))
  else
    echo "not found: $KIT/$n  (check https://github.com/shorepine/kenney/tree/main/3d/$KIT)" >&2
    rm -f "assets/models/$KIT/$n.glb"
  fi
done
echo "$ok fetched. Now: import, then list them under 'models/' in assets/INDEX.md."
