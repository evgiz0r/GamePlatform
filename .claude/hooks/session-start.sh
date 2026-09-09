#!/bin/bash
# Claude Code on the web starts from a bare container: no Godot, no export templates, no
# import cache. Without them every playtest, screenshot and publish claim is a guess. This
# fetches what the kit needs (see tools/setup_godot.sh) and hands the binary to the
# session as $GODOT, which every tools/*.sh script honours. Local machines are untouched.
set -euo pipefail
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi
cd "$CLAUDE_PROJECT_DIR"
BIN="$(tools/setup_godot.sh --templates | tail -1)"
echo "export GODOT=\"$BIN\"" >> "$CLAUDE_ENV_FILE"
# first-run asset import, so the first playtest does not look like a hang
[ -d .godot ] || "$BIN" --headless --path . --import >/dev/null 2>&1 || true
echo "godot ready: $BIN"
