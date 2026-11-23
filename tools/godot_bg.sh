#!/usr/bin/env bash
# Run Godot WITH a window (for screenshots, recordings: anything --headless cannot render)
# without that window showing up over what the person is doing on this machine.
#
#   tools/godot_bg.sh <the godot arguments, as you would give them>      (uses $GODOT)
#
# On Windows it starts Godot's plain .exe with its window hidden: it still renders (the
# viewport's picture, --write-movie), nothing pops up, nothing steals the keyboard. Its output
# is printed when it ends, not as it goes, and the exit code is Godot's. Measured 22 Nov 2026:
#   - --position off the screen: Godot pulls the window back onto it;
#   - started minimized: Godot stops running altogether (stuck until restored);
#   - hidden through the *_console.exe: that wrapper starts the real exe, which ignores it.
# GODOT_SHOW=1 shows the window as before (to watch a run). Elsewhere (Linux, the cloud's
# xvfb) it just runs Godot.
set -u
BIN="${GODOT:-godot}"
if [ "${OS:-}" != "Windows_NT" ] || [ -n "${GODOT_SHOW:-}" ] || ! command -v powershell >/dev/null 2>&1; then
  exec "$BIN" "$@"
fi
EXE="$(command -v "$BIN" 2>/dev/null || echo "$BIN")"
PLAIN="${EXE%_console.exe}.exe"
[ -f "$PLAIN" ] && EXE="$PLAIN"
# one argument string, each quoted (Start-Process joins an array without quoting), paths made
# Windows ones (bash converts them only for a program it starts itself)
ARGS=""
for a in "$@"; do
  case "$a" in /*) a="$(cygpath -w "$a")" ;; esac
  ARGS="$ARGS \"${a//\"/\\\"}\""
done
OUT="$(mktemp)"; ERR="$(mktemp)"
GBG_EXE="$(cygpath -w "$EXE")" GBG_ARGS="$ARGS" GBG_DIR="$(pwd -W)" GBG_OUT="$(cygpath -w "$OUT")" GBG_ERR="$(cygpath -w "$ERR")" \
  powershell -NoProfile -NonInteractive -Command '
$p = Start-Process -FilePath $env:GBG_EXE -ArgumentList $env:GBG_ARGS -WorkingDirectory $env:GBG_DIR `
  -WindowStyle Hidden -PassThru -RedirectStandardOutput $env:GBG_OUT -RedirectStandardError $env:GBG_ERR
$null = $p.Handle   # (without it ExitCode reads empty: a PowerShell quirk)
$p.WaitForExit()
exit $p.ExitCode'
CODE=$?
cat "$OUT" "$ERR"
rm -f "$OUT" "$ERR"
exit $CODE
