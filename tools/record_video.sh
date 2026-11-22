#!/usr/bin/env bash
# A smooth video of a game playing a level by itself, small enough to send to a phone.
#
#   tools/record_video.sh <game> <level> [seconds] [out.mp4]
#
# Godot's movie maker renders every frame at exactly 1/FPS of game time however long it takes
# to compute, so the video never stutters, whatever the machine. tools/record.gd starts the
# level, waits for the game's film_ready(), hides the HUD (film_mode) and the shell's buttons,
# and stops at `seconds` or a moment after film_done(); everything before filming started
# (the loading screen) is cut off, then ffmpeg encodes H.264 under ~28 MB (the phone chat's
# limit is 30). Needs ffmpeg on PATH, or FFMPEG=/path/to/ffmpeg.
# Env: FPS (60), RES (1280x720; 1920x1080 for the best look), MAXK (the bitrate's ceiling,
#   kbit/s: 3000, or 5000 at 1080p -- under the 28 MB either way), QUALITY (the game's own, if
#   it reads one), and anything the game reads -- e.g. a city game's "build everything first"
#   switch, so nothing pops in. A game may also look its best while filmed (film_mode).
set -u
GAME="${1:?which game?}"; LEVEL="${2:-1}"; SECS="${3:-60}"
cd "$(dirname "$0")/.."
OUT="${4:-$GAME-level$LEVEL.mp4}"
BIN="${GODOT:-godot}"
FF="${FFMPEG:-}"
if [ -z "$FF" ]; then
  FF="$(command -v ffmpeg || true)"
  [ -z "$FF" ] && FF="$(ls "$LOCALAPPDATA"/Microsoft/WinGet/Packages/*FFmpeg*/*/bin/ffmpeg.exe 2>/dev/null | head -1)"
fi
[ -z "$FF" ] && { echo "ffmpeg not found: set FFMPEG=/path/to/ffmpeg" >&2; exit 1; }
FPS="${FPS:-60}"; RES="${RES:-1280x720}"
WORK="$(mktemp -d)"
AVI="$WORK/raw.avi"
AVI_NATIVE="$AVI"
command -v cygpath >/dev/null && AVI_NATIVE="$(cygpath -w "$AVI")"
# assets newer than the last import (a merge brought some): import first, or the film lacks them
if [ ! -f .godot/.import_stamp ] || [ -n "$(find game assets -name '*.import' -newer .godot/.import_stamp 2>/dev/null | head -n 1)" ]; then
  "$BIN" --headless --path . --import >/dev/null 2>&1 || true
  mkdir -p .godot && touch .godot/.import_stamp
fi
echo "recording $GAME level $LEVEL, up to $SECS s at $FPS fps, $RES ..."
GAME="$GAME" LEVEL="$LEVEL" SECS="$SECS" FPS="$FPS" GODOT="$BIN" tools/godot_bg.sh --path . --rendering-driver opengl3 --audio-driver Dummy \
  --resolution "$RES" --write-movie "$AVI_NATIVE" --fixed-fps "$FPS" -s res://tools/record.gd > "$WORK/log.txt" 2>&1
START=$(grep -o "RECORD_START [0-9]*" "$WORK/log.txt" | awk '{print $2}')
grep -E "RECORD|frames at" "$WORK/log.txt"
[ -f "$AVI" ] && [ -n "$START" ] || { echo "no recording (see $WORK/log.txt)" >&2; exit 1; }
# the movie's frames count from the engine's first: cut everything before filming began
CUT=$(awk -v f="$START" -v r="$FPS" 'BEGIN { printf "%.3f", f / r }')
LEN=$("${FF%ffmpeg*}ffprobe${FF##*ffmpeg}" -v error -show_entries format=duration -of csv=p=0 "$AVI" 2>/dev/null || echo "$SECS")
KEEP=$(awk -v l="$LEN" -v c="$CUT" 'BEGIN { k = l - c; if (k < 1) k = 1; printf "%.2f", k }')
# a bitrate that keeps it under ~28 MB, at most MAXK
case "$RES" in 1920x*|2560x*) MAXK="${MAXK:-5000}" ;; *) MAXK="${MAXK:-3000}" ;; esac
RATE=$(awk -v k="$KEEP" -v m="$MAXK" 'BEGIN { r = 28 * 8 * 1000 / k; if (r > m) r = m; printf "%d", r }')
"$FF" -y -loglevel error -ss "$CUT" -i "$AVI" -c:v libx264 -preset slow -crf 26 -maxrate "${RATE}k" \
  -bufsize "$((RATE * 2))k" -pix_fmt yuv420p -movflags +faststart -an "$OUT"
rm -rf "$WORK"
ls -la "$OUT" && echo "$KEEP s from frame $START"
