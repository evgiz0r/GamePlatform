#!/usr/bin/env bash
# Fetch a Godot binary (and, with --templates, the web export templates) matching the
# version this project declares, for a Linux box that has none -- a fresh Claude Code on
# the web container, a CI runner. Idempotent: everything lands in ~/.cache/godot and is
# reused on the next call.
#
# Usage:  tools/setup_godot.sh [--templates]
# Prints the binary path on the last line, so:  GODOT="$(tools/setup_godot.sh | tail -1)"
#
# The templates are the expensive part: Godot ships them as one 1.2 GB archive of every
# platform. Only the web ones are needed here (about 10 MB), so they are pulled out of the
# archive with HTTP range requests instead of downloading the whole thing.
set -euo pipefail
cd "$(dirname "$0")/.."

WANT_TEMPLATES=0
[ "${1:-}" = "--templates" ] && WANT_TEMPLATES=1

# "4.7" from config/features=PackedStringArray("4.7", "GL Compatibility")
VER="$(grep -o 'config/features=PackedStringArray("[0-9.]*"' project.godot | grep -o '[0-9][0-9.]*')"
[ -n "$VER" ] || { echo "could not read the Godot version from project.godot" >&2; exit 1; }
TAG="${VER}-stable"
BASE="https://github.com/godotengine/godot/releases/download/${TAG}"
CACHE="${HOME}/.cache/godot/${TAG}"
BIN="${CACHE}/Godot_v${TAG}_linux.x86_64"
mkdir -p "$CACHE"

if [ ! -x "$BIN" ]; then
  echo "fetching Godot ${TAG} ..." >&2
  curl -sSL -o "${CACHE}/godot.zip" "${BASE}/Godot_v${TAG}_linux.x86_64.zip"
  unzip -o -q "${CACHE}/godot.zip" -d "$CACHE"
  rm -f "${CACHE}/godot.zip"
  chmod +x "$BIN"
fi
"$BIN" --version >&2

if [ "$WANT_TEMPLATES" = 1 ]; then
  TDIR="${HOME}/.local/share/godot/export_templates/${TAG/-/.}"
  if [ ! -f "${TDIR}/web_release.zip" ]; then
    echo "fetching web export templates for ${TAG} (slicing them out of the full archive) ..." >&2
    mkdir -p "$TDIR"
    python3 tools/zip_slice.py "${BASE}/Godot_v${TAG}_export_templates.tpz" "$TDIR" \
      'templates/web_' 'templates/version.txt'
  fi
  echo "templates: ${TDIR}" >&2
fi

echo "$BIN"
